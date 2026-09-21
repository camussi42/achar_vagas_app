"""Converte segmentos do Overture Maps (`theme=transportation`, `type=segment`)
em documentos de trecho do Firestore.

Regras do formato (as mesmas que o app valida em `lib/geo/trecho_id.dart`):

- `id` do documento = `gers:<id>` ou, quando cortado nos conectores,
  `gers:<id>@<start_lr>:<end_lr>`;
- geometria gravada como lista de `[lat, lng]` (mesma ordem usada pelo app);
- `geohashConsulta` calculado com a mesma precisao do app;
- a escrita em `trechos` e feita **somente** por aqui (Admin SDK), nunca pelo app.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any

from geohash import PRECISAO_GEOHASH_CONSULTA, RAIO_TERRA_M, codificar

ID_HEX = re.compile(r"^[0-9a-f]{32}$")
ID_UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

#: Formato do id do documento gravado em `trechos`.
#:
#: MESMO texto de `TrechoId.padraoRegex` (lib/geo/trecho_id.dart) e da funcao
#: `trechoIdValido` (firestore.rules). O teste de contrato em
#: `test_pipeline.py` compara os tres arquivos entre si.
PADRAO_TRECHO_ID = re.compile(
    r"^(gers:([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"
    r"(@[0-9.]+:[0-9.]+)?|gh:[0-9a-z]{6,9})$"
)

#: Classes viarias que fazem sentido para estacionamento em via publica.
CLASSES_PADRAO = (
    "residential",
    "living_street",
    "unclassified",
    "service",
    "tertiary",
    "secondary",
    "primary",
)


def normalizar_id(bruto: Any) -> str:
    """Aceita o id em qualquer das formas ja publicadas pelo Overture.

    V2 (atual) usa UUID; V1 usava 32 hexadecimais; e alguns extratores entregam
    o id prefixado (`overture:transportation:segment:<id>`).
    """
    texto = str(bruto or "").strip().lower()
    if not texto:
        raise ValueError("feature sem id")
    if ":" in texto:
        texto = texto.rsplit(":", 1)[-1]
    if ID_HEX.match(texto) or ID_UUID.match(texto):
        return texto
    raise ValueError(f"id do Overture em formato desconhecido: {bruto!r}")


def metros_por_grau(lat: float) -> tuple[float, float]:
    """Metros por grau de latitude e de longitude na latitude informada."""
    por_grau = RAIO_TERRA_M * math.pi / 180.0
    return por_grau, por_grau * math.cos(math.radians(lat))


def comprimento_m(pontos: list[list[float]]) -> float:
    """Comprimento aproximado de uma linha `[[lng, lat], ...]`."""
    if len(pontos) < 2:
        return 0.0
    lat_media = sum(p[1] for p in pontos) / len(pontos)
    metros_lat, metros_lng = metros_por_grau(lat_media)
    total = 0.0
    for (x1, y1), (x2, y2) in zip(pontos, pontos[1:]):
        total += math.hypot((x2 - x1) * metros_lng, (y2 - y1) * metros_lat)
    return total


@dataclass(frozen=True)
class Trecho:
    """Trecho pronto para virar documento no Firestore."""

    id: str
    via: str | None
    classe: str | None
    geometria: list[list[float]]
    centroide: list[float]
    geohash_consulta: str
    release: str | None

    def para_documento(self) -> dict[str, Any]:
        """Corpo do documento `trechos/{id}` no Firestore."""
        return {
            "id": self.id,
            "via": self.via,
            "classe": self.classe,
            "geometria": self.geometria,
            "centroide": self.centroide,
            "geohashConsulta": self.geohash_consulta,
            "release": self.release,
        }


def _para_lat_lng(pontos: list[list[float]]) -> list[list[float]]:
    """Converte `[lng, lat]` (Overture/GeoJSON) para `[lat, lng]` (Firestore/app)."""
    return [[round(p[1], 7), round(p[0], 7)] for p in pontos]


def _centroide(geometria: list[list[float]]) -> list[float]:
    lat = sum(p[0] for p in geometria) / len(geometria)
    lng = sum(p[1] for p in geometria) / len(geometria)
    return [round(lat, 7), round(lng, 7)]


def simplificar(
    pontos: list[list[float]], tolerancia_graus: float
) -> list[list[float]]:
    """Douglas-Peucker sobre `[[lng, lat], ...]` (reduz o documento no Firestore)."""
    if len(pontos) <= 2 or tolerancia_graus <= 0:
        return list(pontos)

    def distancia_do_segmento(p, a, b) -> float:
        if a == b:
            return math.hypot(p[0] - a[0], p[1] - a[1])
        (x1, y1), (x2, y2) = a, b
        px, py = p
        dx, dy = x2 - x1, y2 - y1
        t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
        t = min(1.0, max(0.0, t))
        return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))

    pilha: list[tuple[int, int]] = [(0, len(pontos) - 1)]
    manter = {0, len(pontos) - 1}
    while pilha:
        inicio, fim = pilha.pop()
        maior, indice = 0.0, None
        for i in range(inicio + 1, fim):
            d = distancia_do_segmento(pontos[i], pontos[inicio], pontos[fim])
            if d > maior:
                maior, indice = d, i
        if indice is not None and maior > tolerancia_graus:
            manter.add(indice)
            pilha.append((inicio, indice))
            pilha.append((indice, fim))

    return [pontos[i] for i in sorted(manter)]


def recortar(
    pontos: list[list[float]], inicio_lr: float, fim_lr: float
) -> list[list[float]]:
    """Recorta a sub-linha entre duas posicoes lineares (0..1 do comprimento)."""
    if not 0 <= inicio_lr < fim_lr <= 1:
        raise ValueError(f"faixa linear invalida: {inicio_lr}..{fim_lr}")
    if len(pontos) < 2:
        return list(pontos)

    cumulativo = [0.0]
    for (x1, y1), (x2, y2) in zip(pontos, pontos[1:]):
        cumulativo.append(cumulativo[-1] + math.hypot(x2 - x1, y2 - y1))
    total = cumulativo[-1]
    if total == 0:
        return list(pontos)

    alvo_inicio, alvo_fim = inicio_lr * total, fim_lr * total

    def ponto_em(distancia: float) -> list[float]:
        for i in range(len(cumulativo) - 1):
            if cumulativo[i] <= distancia <= cumulativo[i + 1]:
                trecho = cumulativo[i + 1] - cumulativo[i]
                t = 0.0 if trecho == 0 else (distancia - cumulativo[i]) / trecho
                return [
                    pontos[i][0] + t * (pontos[i + 1][0] - pontos[i][0]),
                    pontos[i][1] + t * (pontos[i + 1][1] - pontos[i][1]),
                ]
        return list(pontos[-1])

    recorte = [ponto_em(alvo_inicio)]
    for indice, distancia in enumerate(cumulativo):
        if alvo_inicio < distancia < alvo_fim:
            recorte.append(pontos[indice])
    recorte.append(ponto_em(alvo_fim))
    return recorte


def faixas_dos_conectores(
    conectores: list[dict[str, Any]] | None,
    min_metros: float,
    comprimento_total_m: float,
) -> list[list[float]]:
    """Faixas lineares que dividem o segmento nos conectores (lado de quadra).

    Conectores muito proximos (entrada de garagem, por exemplo) sao absorvidos
    pelo trecho anterior para nao gerar pedacos inuteis.
    """
    marcos = sorted(
        {0.0, 1.0} | {float(c.get("at") or 0.0) for c in (conectores or [])}
    )
    faixas: list[list[float]] = []
    for inicio, fim in zip(marcos, marcos[1:]):
        metros = (fim - inicio) * comprimento_total_m
        if faixas and metros < min_metros:
            faixas[-1][1] = fim
        else:
            faixas.append([inicio, fim])

    # O primeiro pedaco tambem pode ser curto demais (conector colado na ponta).
    if (
        len(faixas) > 1
        and (faixas[0][1] - faixas[0][0]) * comprimento_total_m < min_metros
    ):
        faixas[1][0] = faixas[0][0]
        faixas.pop(0)

    return faixas


def montar_trechos(
    feature: dict[str, Any],
    *,
    release: str | None = None,
    classes: tuple[str, ...] | None = CLASSES_PADRAO,
    somente_com_nome: bool = False,
    dividir_nos_conectores: bool = False,
    min_metros_trecho: float = 40.0,
    tolerancia_simplificacao_graus: float = 0.00005,
) -> list[Trecho]:
    """Converte **uma** feature de segmento em zero ou mais trechos.

    `dividers_nos_conectores=False` (padrao) mantem o segmento inteiro, que e o
    suficiente para o mapa por cor. Ligando a divisao, cada trecho passa a ser um
    lado de quadra entre conectores (`gers:<id>@<start>:<end>`).
    """
    propriedades = feature.get("properties") or {}
    if (propriedades.get("subtype") or "road") != "road":
        return []

    classe = propriedades.get("class")
    if classes is not None and classe not in classes:
        return []

    nome = (propriedades.get("names") or {}).get("primary")
    if somente_com_nome and not nome:
        return []

    try:
        identificador = normalizar_id(feature.get("id") or propriedades.get("id"))
    except ValueError:
        return []

    geometria = feature.get("geometry") or {}
    if geometria.get("type") != "LineString":
        return []
    coordenadas = geometria.get("coordinates") or []
    if len(coordenadas) < 2:
        return []

    if dividir_nos_conectores:
        faixas = faixas_dos_conectores(
            propriedades.get("connectors"),
            min_metros_trecho,
            comprimento_m(coordenadas),
        )
    else:
        faixas = [[0.0, 1.0]]

    trechos: list[Trecho] = []
    for inicio, fim in faixas:
        recorte = (
            recortar(coordenadas, inicio, fim)
            if dividir_nos_conectores
            else list(coordenadas)
        )
        simplificado = simplificar(recorte, tolerancia_simplificacao_graus)
        if len(simplificado) < 2:
            continue

        lat_lng = _para_lat_lng(simplificado)
        centroide = _centroide(lat_lng)
        sufixo = f"@{inicio:.4f}:{fim:.4f}" if dividir_nos_conectores else ""
        trechos.append(
            Trecho(
                id=f"gers:{identificador}{sufixo}",
                via=nome,
                classe=classe,
                geometria=lat_lng,
                centroide=centroide,
                geohash_consulta=codificar(
                    centroide[0], centroide[1], PRECISAO_GEOHASH_CONSULTA
                ),
                release=release,
            )
        )
    return trechos


def trechos_de_geojson(
    documento: dict[str, Any], **opcoes: Any
) -> list[Trecho]:
    """Converte um GeoJSON FeatureCollection do Overture, sem ids repetidos."""
    if documento.get("type") != "FeatureCollection":
        raise ValueError("esperado um GeoJSON do tipo FeatureCollection")

    por_id: dict[str, Trecho] = {}
    for feature in documento.get("features") or []:
        for trecho in montar_trechos(feature, **opcoes):
            por_id.setdefault(trecho.id, trecho)
    return list(por_id.values())
