"""CLI da pipeline: Overture Maps -> trechos.

Exemplos:

    # baixa o bbox do centro de Campo Mourao e gera o NDJSON para o Firestore
    python tools/pipeline/export_trechos.py --out trechos.ndjson

    # reaproveita um export ja baixado, dividindo por esquina
    python tools/pipeline/export_trechos.py --geojson cm.geojson \
        --dividir-nos-conectores --out trechos.ndjson

    # gera a semente de demonstracao (usada quando nao ha Firebase)
    python tools/pipeline/export_trechos.py --geojson cm.geojson \
        --seed-dart lib/data/trechos_demo_gerado.dart

A release nunca fica fixa no codigo: e lida do catalogo STAC da Overture.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path
from urllib.request import urlopen

from trechos import CLASSES_PADRAO, Trecho, trechos_de_geojson

CATALOGO_STAC = "https://stac.overturemaps.org/catalog.json"

#: Centro de Campo Mourao/PR (cidade-piloto do trabalho).
BBOX_PADRAO = "-52.383,-24.049,-52.371,-24.037"


def release_atual() -> str | None:
    """Descobre a release mais recente pelo catalogo STAC (fonte oficial)."""
    try:
        with urlopen(CATALOGO_STAC, timeout=30) as resposta:
            catalogo = json.load(resposta)
    except Exception as erro:  # noqa: BLE001 - rede/parse: degrada sem quebrar
        print(f"aviso: nao consegui consultar o STAC ({erro})", file=sys.stderr)
        return None

    candidato = catalogo.get("latest") or catalogo.get("id")
    if isinstance(candidato, list):
        return candidato[0] if candidato else None
    return candidato if isinstance(candidato, str) else None


def baixar_geojson(bbox: str, release: str | None, destino: Path) -> Path:
    """Baixa os segmentos do bbox usando o CLI oficial do Overture."""
    comando = [
        sys.executable,
        "-m",
        "overturemaps",
        "download",
        f"--bbox={bbox}",
        "-f",
        "geojson",
        "-t",
        "segment",
        "-o",
        str(destino),
    ]
    if release:
        comando += ["-r", release]
    print("baixando:", " ".join(comando))
    subprocess.run(comando, check=True)
    return destino


def centro_do_bbox(bbox: str) -> tuple[float, float]:
    oeste, sul, leste, norte = (float(v) for v in bbox.split(","))
    return (sul + norte) / 2, (oeste + leste) / 2


def distancia_aproximada_m(
    lat1: float, lng1: float, lat2: float, lng2: float
) -> float:
    """Distancia planar: suficiente para ordenar trechos pela distancia."""
    return math.hypot(
        (lat1 - lat2) * 111320.0,
        (lng1 - lng2) * 111320.0 * math.cos(math.radians(lat1)),
    )


def gerar_ndjson(trechos: list[Trecho], destino: Path) -> int:
    """Escreve um documento por linha (formato consumido pelo seeder)."""
    destino.parent.mkdir(parents=True, exist_ok=True)
    with destino.open("w", encoding="utf-8") as arquivo:
        for trecho in trechos:
            arquivo.write(json.dumps(trecho.para_documento(), ensure_ascii=False))
            arquivo.write("\n")
    return destino.stat().st_size


def gerar_semente_dart(
    trechos: list[Trecho], destino: Path, release: str | None, limite: int
) -> None:
    """Escreve a semente usada no modo demonstracao (sem Firebase)."""
    if not trechos:
        raise SystemExit("nada para semear: nenhum trecho gerado")

    centro = (
        sum(t.centroide[0] for t in trechos) / len(trechos),
        sum(t.centroide[1] for t in trechos) / len(trechos),
    )
    ordenados = sorted(
        (t for t in trechos if t.via),
        key=lambda t: distancia_aproximada_m(
            t.centroide[0], t.centroide[1], centro[0], centro[1]
        ),
    )[:limite]

    linhas = [
        "// GERADO AUTOMATICAMENTE por tools/pipeline/export_trechos.py.",
        "// NAO EDITE A MAO: rode a pipeline novamente para atualizar.",
        "//",
        "// Trechos REAIS do Overture Maps (tema transporte) no centro de",
        f"// Campo Mourao/PR, release {release or 'desconhecida'}. Usados apenas no",
        "// modo demonstracao (sem Firebase) e nos testes.",
        "const List<Map<String, dynamic>> trechosDemoGerado = <Map<String, dynamic>>[",
    ]
    for trecho in ordenados:
        documento = trecho.para_documento()
        geometria = ", ".join(f"[{p[0]}, {p[1]}]" for p in documento["geometria"])
        centroide = documento["centroide"]
        linhas.append("  <String, dynamic>{")
        linhas.append(f"    'id': '{documento['id']}',")
        linhas.append(f"    'via': {json.dumps(documento['via'], ensure_ascii=False)},")
        linhas.append(f"    'classe': '{documento['classe']}',")
        linhas.append(f"    'geometria': <List<double>>[{geometria}],")
        linhas.append(f"    'centroide': <double>[{centroide[0]}, {centroide[1]}],")
        linhas.append(f"    'geohashConsulta': '{documento['geohashConsulta']}',")
        linhas.append(f"    'release': '{documento['release']}',")
        linhas.append("  },")
    linhas.append("];")
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text("\n".join(linhas) + "\n", encoding="utf-8")
    print(f"semente Dart: {destino} ({len(ordenados)} trechos)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Overture -> trechos")
    parser.add_argument("--geojson", type=Path, help="GeoJSON ja baixado (pula o download)")
    parser.add_argument("--bbox", default=BBOX_PADRAO, help="bbox O/S/L/N")
    parser.add_argument("--release", default=None, help="release do Overture (padrao: STAC)")
    parser.add_argument("--out", type=Path, default=Path("trechos.ndjson"))
    parser.add_argument("--seed-dart", type=Path, default=None)
    parser.add_argument("--seed-limite", type=int, default=40)
    parser.add_argument("--somente-com-nome", action="store_true")
    parser.add_argument("--sem-filtro-de-classe", action="store_true")
    parser.add_argument("--dividir-nos-conectores", action="store_true")
    parser.add_argument("--min-metros-trecho", type=float, default=40.0)
    parser.add_argument("--tolerancia-graus", type=float, default=0.00005)
    argumentos = parser.parse_args()

    release = argumentos.release or release_atual()
    origem = argumentos.geojson
    if origem is None:
        origem = Path("segmentos_overture.geojson")
        baixar_geojson(argumentos.bbox, release, origem)

    documento = json.loads(origem.read_text(encoding="utf-8"))
    trechos = trechos_de_geojson(
        documento,
        release=release,
        classes=None if argumentos.sem_filtro_de_classe else CLASSES_PADRAO,
        somente_com_nome=argumentos.somente_com_nome,
        dividir_nos_conectores=argumentos.dividir_nos_conectores,
        min_metros_trecho=argumentos.min_metros_trecho,
        tolerancia_simplificacao_graus=argumentos.tolerancia_graus,
    )

    com_nome = sum(1 for trechos_ in trechos if trechos_.via)
    vertices = sum(len(t.geometria) for t in trechos)
    print(
        f"release: {release}\n"
        f"trechos gerados: {len(trechos)} (com nome de via: {com_nome})\n"
        f"vertices de geometria: {vertices}"
    )

    if trechos:
        bytes_ndjson = gerar_ndjson(trechos, argumentos.out)
        print(f"NDJSON: {argumentos.out} ({bytes_ndjson} bytes)")
    if argumentos.seed_dart is not None:
        gerar_semente_dart(
            trechos, argumentos.seed_dart, release, argumentos.seed_limite
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
