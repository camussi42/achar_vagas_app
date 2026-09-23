"""Semeia a colecao `trechos` no emulador do Firestore com a saida da pipeline.

Rodar da raiz do repositorio, com o emulador de pe (`docker-compose up`):

    python tools/pipeline/export_trechos.py --geojson cm.geojson --out trechos.ndjson
    python tools/pipeline/semear_firestore.py --arquivo trechos.ndjson

Com o emulador do docker-compose na sua maquina:

    $env:FIRESTORE_EMULATOR_HOST = "localhost:8080"   # PowerShell
    export FIRESTORE_EMULATOR_HOST=localhost:8080     # bash

Dentro do container do firebase o host muda para o nome do servico
(`firebase:8080`), que e o valor usado no `docker-compose.yml`.

A escrita usa o Admin SDK (ignora `firestore.rules`) — e justamente por isso que
as regras negam escrita de cliente em `trechos`. O corpo gravado tem a MESMA
forma que `lib/services/trechos_repository.dart` le: `centroide` e `geometria`
como `GeoPoint`, id do documento igual a chave `gers:<id>` (ou
`gers:<id>@<start_lr>:<end_lr>`, quando o trecho e um lado de quadra).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Callable, Iterator

from export_trechos import caminho_seguro

#: Colecao gravada (a mesma lida por `lib/services/trechos_repository.dart`).
COLECAO = "trechos"

ARQUIVO_PADRAO = Path("trechos.ndjson")
PROJETO_PADRAO = "demo-achar-vagas"
EMULADOR_PADRAO = "localhost:8080"

#: Limite de escritas por lote no Firestore.
TAMANHO_LOTE = 500

HOST_VALIDO = re.compile(r"^[0-9a-zA-Z.\-]+:[0-9]{1,5}$")


def validar_emulador(host: str) -> str:
    """`host:porta` do emulador (reconstroi a string para nao repassar lixo)."""
    texto = (host or "").strip()
    if not HOST_VALIDO.match(texto):
        raise ValueError(f"FIRESTORE_EMULATOR_HOST invalido: {host!r}")
    return texto


def geopoint_padrao(lat: float, lng: float) -> Any:
    """`GeoPoint` do Admin SDK.

    O import fica tardio de proposito: a suite de testes (`test_pipeline.py`)
    roda sem a dependencia instalada, passando outro construtor.
    """
    from google.cloud import firestore

    return firestore.GeoPoint(lat, lng)


def para_firestore(
    documento: dict[str, Any],
    criar_ponto: Callable[[float, float], Any] = geopoint_padrao,
) -> tuple[str, dict[str, Any]]:
    """Uma linha do NDJSON -> `(id do documento, corpo gravado)`."""
    if not isinstance(documento, dict):
        raise ValueError("linha do NDJSON nao e um objeto JSON")

    identificador = documento.get("id")
    if not isinstance(identificador, str) or not identificador:
        raise ValueError(f"documento sem id: {documento!r}")

    centroide = documento.get("centroide")
    if not isinstance(centroide, list) or len(centroide) != 2:
        raise ValueError(f"{identificador}: centroide invalido: {centroide!r}")

    geometria = documento.get("geometria") or []
    if not isinstance(geometria, list) or len(geometria) < 2:
        raise ValueError(f"{identificador}: geometria precisa de 2+ vertices")

    corpo = {
        "id": identificador,
        "via": documento.get("via"),
        "classe": documento.get("classe"),
        "municipio": documento.get("municipio"),
        "uf": documento.get("uf"),
        "geometria": [criar_ponto(float(p[0]), float(p[1])) for p in geometria],
        "centroide": criar_ponto(float(centroide[0]), float(centroide[1])),
        "geohashConsulta": documento.get("geohashConsulta"),
        "release": documento.get("release"),
        "atualizadoEm": documento.get("atualizadoEm"),
    }
    return identificador, corpo


def ler_documentos(
    caminho: Path,
    criar_ponto: Callable[[float, float], Any] = geopoint_padrao,
) -> Iterator[tuple[str, dict[str, Any]]]:
    """Le o NDJSON do export, uma linha (documento) por vez."""
    with caminho.open(encoding="utf-8") as arquivo:
        for numero, linha in enumerate(arquivo, start=1):
            texto = linha.strip()
            if not texto:
                continue
            try:
                documento = json.loads(texto)
            except json.JSONDecodeError as erro:
                raise ValueError(f"linha {numero} nao e JSON: {erro}") from erro

            try:
                yield para_firestore(documento, criar_ponto)
            except ValueError as erro:
                raise ValueError(f"linha {numero}: {erro}") from erro


def escrever(
    cliente: Any,
    documentos: Iterator[tuple[str, dict[str, Any]]],
    tamanho_lote: int = TAMANHO_LOTE,
) -> int:
    """Grava em lotes de `tamanho_lote` e devolve quantos documentos escreveu."""
    gravados = 0
    lote = cliente.batch()
    colecao = cliente.collection(COLECAO)
    for identificador, corpo in documentos:
        lote.set(colecao.document(identificador), corpo)
        gravados += 1
        if gravados % tamanho_lote == 0:
            lote.commit()
            lote = cliente.batch()
            print(f"  {gravados} documentos gravados")

    # O lote final pode estar vazio (numero redondo de documentos) e commit de
    # lote vazio e erro no Admin SDK.
    if gravados and gravados % tamanho_lote:
        lote.commit()
    return gravados


def limpar(cliente: Any, tamanho_lote: int = TAMANHO_LOTE) -> int:
    """Apaga os trechos existentes, para a semente nao misturar com a antiga."""
    apagados = 0
    colecao = cliente.collection(COLECAO)
    while True:
        pagina = list(colecao.limit(tamanho_lote).stream())
        if not pagina:
            return apagados
        lote = cliente.batch()
        for documento in pagina:
            lote.delete(documento.reference)
        lote.commit()
        apagados += len(pagina)


def cliente_emulador(host: str, projeto: str) -> Any:
    """Cliente do Admin SDK apontado para o emulador."""
    os.environ["FIRESTORE_EMULATOR_HOST"] = validar_emulador(host)
    try:
        from google.cloud import firestore
    except ImportError as erro:  # pragma: no cover - depende do ambiente
        raise SystemExit(
            "google-cloud-firestore nao instalado: rode "
            "`pip install google-cloud-firestore` (ou use o container do "
            "docker-compose)"
        ) from erro

    return firestore.Client(project=projeto)


def criar_parser() -> argparse.ArgumentParser:
    """Argumentos da CLI (separado de `main` para os testes lerem os padroes)."""
    parser = argparse.ArgumentParser(description="trechos -> emulador do Firestore")
    parser.add_argument(
        "--arquivo",
        type=Path,
        default=ARQUIVO_PADRAO,
        help="NDJSON gerado pelo export_trechos.py",
    )
    parser.add_argument("--projeto", default=PROJETO_PADRAO)
    parser.add_argument(
        "--emulador",
        default=os.environ.get("FIRESTORE_EMULATOR_HOST") or EMULADOR_PADRAO,
        help="host:porta do emulador (padrao: FIRESTORE_EMULATOR_HOST)",
    )
    parser.add_argument(
        "--limpar",
        action="store_true",
        help="apaga os trechos existentes antes de gravar",
    )
    return parser


def main() -> int:
    argumentos = criar_parser().parse_args()

    origem = caminho_seguro(argumentos.arquivo)
    if not origem.is_file():
        print(f"nao achei o NDJSON: {origem}", file=sys.stderr)
        print(
            "rode antes: python tools/pipeline/export_trechos.py --out trechos.ndjson",
            file=sys.stderr,
        )
        return 1

    emulador = validar_emulador(argumentos.emulador)
    cliente = cliente_emulador(emulador, argumentos.projeto)
    print(f"emulador: {emulador} (projeto {argumentos.projeto})")

    if argumentos.limpar:
        print(f"limpando {COLECAO}: {limpar(cliente)} documentos removidos")

    gravados = escrever(cliente, ler_documentos(origem))
    print(f"{COLECAO}: {gravados} documentos gravados de {origem}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
