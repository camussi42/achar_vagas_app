"""Geohash em Python, espelhando `lib/geo/geohash.dart`.

Os dois precisam produzir exatamente o mesmo hash para o mesmo ponto, senao o
indice gravado pela pipeline deixa de casar com as consultas feitas pelo app.
Os testes (`test_pipeline.py`) verificam isso contra valores de referencia
gerados por uma terceira implementacao (`pygeohash`).
"""

from __future__ import annotations

BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
RAIO_TERRA_M = 6371008.8

# Precisao do geohash usado como indice de consulta (~1,2 km x 610 m no Parana).
PRECISAO_GEOHASH_CONSULTA = 6


def codificar(lat: float, lng: float, precisao: int = PRECISAO_GEOHASH_CONSULTA) -> str:
    """Codifica `lat`/`lng` em um geohash de `precisao` caracteres."""
    if not 1 <= precisao <= 12:
        raise ValueError(f"precisao deve estar entre 1 e 12: {precisao}")

    lat_min, lat_max = -90.0, 90.0
    lng_min, lng_max = -180.0, 180.0
    alterna_lng = True
    bit = 0
    acumulado = 0
    saida: list[str] = []

    while len(saida) < precisao:
        if alterna_lng:
            meio = (lng_min + lng_max) / 2
            if lng >= meio:
                acumulado = (acumulado << 1) | 1
                lng_min = meio
            else:
                acumulado <<= 1
                lng_max = meio
        else:
            meio = (lat_min + lat_max) / 2
            if lat >= meio:
                acumulado = (acumulado << 1) | 1
                lat_min = meio
            else:
                acumulado <<= 1
                lat_max = meio
        alterna_lng = not alterna_lng
        bit += 1
        if bit == 5:
            saida.append(BASE32[acumulado])
            bit = 0
            acumulado = 0

    return "".join(saida)
