"""Testes da pipeline.

Rodar:

    python -m unittest discover -s tools/pipeline -v

Os valores de geohash sao os mesmos usados em `test/geohash_test.dart`, gerados
por uma implementacao independente (`pygeohash`). Se Python e Dart divergirem, o
indice gravado pela pipeline deixa de casar com a consulta do app.

Alem do geohash, aqui ficam os **testes de contrato**: o padrao do `trechoId`
tem que ser o mesmo no app (`lib/geo/trecho_id.dart`), nas regras do Firestore
(`firestore.rules`) e na pipeline (`trechos.PADRAO_TRECHO_ID`).
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

import export_trechos
import geohash
import trechos

#: Raiz do repositorio (test_pipeline.py -> tools/pipeline -> tools -> repo).
RAIZ = Path(__file__).resolve().parents[2]

#: Mesmo padrao de `firestore.rules` / `lib/geo/trecho_id.dart` (fonte unica).
PADRAO_TRECHO_ID = trechos.PADRAO_TRECHO_ID


def extrair_padrao_do_app() -> str:
    """Le o texto literal de `TrechoId.padraoRegex` em lib/geo/trecho_id.dart."""
    fonte = (RAIZ / "lib" / "geo" / "trecho_id.dart").read_text(encoding="utf-8")
    corpo = re.search(r"_formatoValido\s*=\s*RegExp\((.*?)\);", fonte, re.S)
    assert corpo is not None, "nao achei _formatoValido em trecho_id.dart"
    partes = re.findall(r"r'([^']*)'", corpo.group(1))
    assert partes, "_formatoValido nao usa literal cru (r'...')"
    return "".join(partes)


def extrair_padrao_das_rules() -> str:
    """Le o texto literal passado para `matches()` em firestore.rules."""
    fonte = (RAIZ / "firestore.rules").read_text(encoding="utf-8")
    corpo = re.search(
        r"function\s+trechoIdValido\(id\)\s*\{(.*?)\n\s*\}", fonte, re.S
    )
    assert corpo is not None, "nao achei a funcao trechoIdValido em firestore.rules"
    padrao = re.search(r"matches\(\s*'([^']+)'\s*\)", corpo.group(1), re.S)
    assert padrao is not None, "trechoIdValido sem matches('...')"
    return padrao.group(1)


class ContratoTrechoIdTest(unittest.TestCase):
    """App, rules e pipeline precisam aceitar exatamente o mesmo id."""

    def test_os_tres_arquivos_usam_o_mesmo_padrao(self):
        esperado = PADRAO_TRECHO_ID.pattern
        self.assertEqual(extrair_padrao_do_app(), esperado)
        self.assertEqual(extrair_padrao_das_rules(), esperado)

    def test_amostras_canonicas_casam_no_padrao(self):
        for texto in (
            "gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9",
            "gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9@0.5000:1.0000",
            "gers:08628d5437ffffff0473ffc36df547db@0.0000:0.5000",
            "gh:6gdz0ph",
        ):
            self.assertTrue(PADRAO_TRECHO_ID.match(texto), texto)

    def test_ids_inventados_nao_casam_no_padrao(self):
        for texto in (
            "gers:xpto",
            "gers:",
            "gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9@0.5",
            "c1d70afe-a7de-4b73-a41c-e92526ab72f9",
            "gh:abc",
            "gh:6G DZ0PH",
            " gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9",
        ):
            self.assertIsNone(PADRAO_TRECHO_ID.match(texto), texto)

    def test_gera_id_de_quadra_que_casa_no_padrao(self):
        conectores = [
            {"connector_id": "a", "at": 0.0},
            {"connector_id": "b", "at": 0.5},
            {"connector_id": "c", "at": 1.0},
        ]
        for trecho in trechos.montar_trechos(
            feature(conectores=conectores), dividir_nos_conectores=True
        ):
            self.assertTrue(PADRAO_TRECHO_ID.match(trecho.id), trecho.id)

    def test_rules_negam_escrita_de_cliente_em_trechos(self):
        fonte = (RAIZ / "firestore.rules").read_text(encoding="utf-8")
        bloco = re.search(r"match /trechos/\{[^}]+\}\s*\{(.*?)\n\s*\}", fonte, re.S)
        self.assertIsNotNone(bloco, "firestore.rules sem regra para /trechos")
        corpo = bloco.group(1)
        self.assertRegex(corpo, r"allow read:\s*if true;")
        self.assertRegex(corpo, r"allow write:\s*if false;")

    def test_rules_validam_relato_por_completo(self):
        fonte = (RAIZ / "firestore.rules").read_text(encoding="utf-8")
        corpo = fonte.split("match /relatos/", 1)[1]
        self.assertRegex(corpo, r"uid == request\.auth\.uid")
        self.assertRegex(corpo, r"trechoIdValido\(request\.resource\.data\.trechoId\)")
        self.assertRegex(corpo, r"tipo in \['vaga', 'lotado', 'saindo'\]")
        self.assertRegex(corpo, r"geo\.geopoint is latlng")
        self.assertRegex(corpo, r"criadoEm == request\.time")


class ValidacaoEntradaTest(unittest.TestCase):
    def test_bbox_valido_normaliza(self):
        self.assertEqual(
            export_trechos.validar_bbox("-52.383,-24.049,-52.371,-24.037"),
            "-52.383000,-24.049000,-52.371000,-24.037000",
        )

    def test_bbox_rejeita_lixo_e_faixa_errada(self):
        for ruim in ("abc", "1,2,3", "-1,-2,999,0", "-52, -24, -51, 999", "a,b,c,d"):
            with self.assertRaises(ValueError):
                export_trechos.validar_bbox(ruim)

    def test_release_valida_faz_roundtrip(self):
        self.assertEqual(export_trechos.validar_release("2026-08-19.0"), "2026-08-19.0")
        self.assertEqual(export_trechos.validar_release(" 2026-08-19.0 "), "2026-08-19.0")

    def test_release_rejeita_formato_estranho(self):
        for ruim in ("2026-08-19", "abc", "2026-08-19; rm -rf /", "1.0"):
            with self.assertRaises(ValueError):
                export_trechos.validar_release(ruim)

    def test_caminho_seguro_confina_no_repositorio(self):
        dentro = export_trechos.caminho_seguro(Path("saida.ndjson"))
        self.assertTrue(dentro.is_absolute())
        with self.assertRaises(ValueError):
            export_trechos.caminho_seguro(Path("../fora.ndjson"))


def feature(
    *,
    identificador: str = "c1d70afe-a7de-4b73-a41c-e92526ab72f9",
    nome: str | None = "Rua Teste",
    classe: str = "residential",
    subtype: str = "road",
    coordenadas: list[list[float]] | None = None,
    conectores: list[dict] | None = None,
    tipo_geometria: str = "LineString",
) -> dict:
    return {
        "type": "Feature",
        "id": identificador,
        "properties": {
            "subtype": subtype,
            "class": classe,
            "names": {"primary": nome},
            "connectors": conectores
            if conectores is not None
            else [{"connector_id": "a", "at": 0.0}, {"connector_id": "b", "at": 1.0}],
        },
        "geometry": {
            "type": tipo_geometria,
            "coordinates": coordenadas
            if coordenadas is not None
            else [[-52.3772, -24.0431], [-52.3756, -24.0442]],
        },
    }


class GeohashTest(unittest.TestCase):
    def test_bate_com_valores_de_referencia(self):
        # `pygeohash` (implementacao independente)
        self.assertEqual(geohash.codificar(-24.0430793, -52.3772141, 4), "6gdz")
        self.assertEqual(geohash.codificar(-24.0430793, -52.3772141, 6), "6gdz0p")
        self.assertEqual(geohash.codificar(-24.0430793, -52.3772141, 7), "6gdz0ph")
        self.assertEqual(geohash.codificar(-24.0430793, -52.3772141, 9), "6gdz0ph4f")
        self.assertEqual(geohash.codificar(42.6, -5.6, 5), "ezs42")

    def test_rejeita_precisao_invalida(self):
        with self.assertRaises(ValueError):
            geohash.codificar(0, 0, 0)
        with self.assertRaises(ValueError):
            geohash.codificar(0, 0, 13)


class NormalizarIdTest(unittest.TestCase):
    def test_aceita_uuid_e_hex(self):
        self.assertEqual(
            trechos.normalizar_id("C1D70AFE-A7DE-4B73-A41C-E92526AB72F9"),
            "c1d70afe-a7de-4b73-a41c-e92526ab72f9",
        )
        self.assertEqual(
            trechos.normalizar_id("08628d5437ffffff0473ffc36df547db"),
            "08628d5437ffffff0473ffc36df547db",
        )

    def test_aceita_id_prefixado(self):
        self.assertEqual(
            trechos.normalizar_id(
                "overture:transportation:segment:08628d5437ffffff0473ffc36df547db"
            ),
            "08628d5437ffffff0473ffc36df547db",
        )

    def test_rejeita_id_invalido(self):
        for invalido in ("", None, "abc", 123, "zzzz"):
            with self.assertRaises(ValueError):
                trechos.normalizar_id(invalido)


class SimplificarTest(unittest.TestCase):
    def test_remove_ponto_colinear(self):
        pontos = [[0.0, 0.0], [0.1, 0.0], [0.2, 0.0]]
        self.assertEqual(trechos.simplificar(pontos, 0.00005), [[0.0, 0.0], [0.2, 0.0]])

    def test_mantem_ponto_que_desvia(self):
        pontos = [[0.0, 0.0], [0.1, 0.01], [0.2, 0.0]]
        self.assertEqual(len(trechos.simplificar(pontos, 0.00005)), 3)

    def test_preserva_as_pontas(self):
        pontos = [[0.0, 0.0], [0.1, 0.0001], [0.2, 0.0]]
        simplificado = trechos.simplificar(pontos, 0.001)
        self.assertEqual(simplificado[0], pontos[0])
        self.assertEqual(simplificado[-1], pontos[-1])

    def test_tolerancia_zero_nao_mexe(self):
        pontos = [[0.0, 0.0], [0.1, 0.0], [0.2, 0.0]]
        self.assertEqual(trechos.simplificar(pontos, 0.0), pontos)


class RecortarTest(unittest.TestCase):
    def test_metade_final_da_reta(self):
        pontos = [[0.0, 0.0], [1.0, 0.0]]
        recorte = trechos.recortar(pontos, 0.5, 1.0)
        self.assertAlmostEqual(recorte[0][0], 0.5, places=6)
        self.assertAlmostEqual(recorte[-1][0], 1.0, places=6)

    def test_intervalo_completo_preserva_vertices(self):
        pontos = [[0.0, 0.0], [0.5, 0.5], [1.0, 0.0]]
        recorte = trechos.recortar(pontos, 0.0, 1.0)
        self.assertEqual(len(recorte), 3)

    def test_faixa_invalida(self):
        with self.assertRaises(ValueError):
            trechos.recortar([[0.0, 0.0], [1.0, 0.0]], 0.8, 0.2)


class FaixasDosConectoresTest(unittest.TestCase):
    def test_divide_nos_conectores(self):
        conectores = [
            {"connector_id": "a", "at": 0.0},
            {"connector_id": "b", "at": 0.3},
            {"connector_id": "c", "at": 1.0},
        ]
        faixas = trechos.faixas_dos_conectores(conectores, 40.0, 1000.0)
        self.assertEqual(faixas, [[0.0, 0.3], [0.3, 1.0]])

    def test_absorve_conector_muito_proximo(self):
        conectores = [
            {"connector_id": "a", "at": 0.0},
            {"connector_id": "b", "at": 0.01},  # ~10 m: entrada de garagem
            {"connector_id": "c", "at": 1.0},
        ]
        faixas = trechos.faixas_dos_conectores(conectores, 40.0, 1000.0)
        self.assertEqual(faixas, [[0.0, 1.0]])

    def test_sem_conectores_e_uma_faixa(self):
        self.assertEqual(trechos.faixas_dos_conectores(None, 40.0, 100.0), [[0.0, 1.0]])


class MontarTrechosTest(unittest.TestCase):
    def test_gera_trecho_com_id_gers_e_lat_lng(self):
        resultado = trechos.montar_trechos(feature(), release="2026-08-19.0")
        self.assertEqual(len(resultado), 1)
        trecho = resultado[0]
        self.assertTrue(PADRAO_TRECHO_ID.match(trecho.id), trecho.id)
        self.assertEqual(trecho.via, "Rua Teste")
        self.assertEqual(trecho.classe, "residential")
        self.assertEqual(trecho.release, "2026-08-19.0")
        # primeira coordenada: [lat, lng] (o GeoJSON vem como [lng, lat])
        self.assertAlmostEqual(trecho.geometria[0][0], -24.0431, places=6)
        self.assertAlmostEqual(trecho.geometria[0][1], -52.3772, places=6)
        self.assertEqual(trecho.geohash_consulta, geohash.codificar(
            trecho.centroide[0], trecho.centroide[1], 6
        ))
        self.assertTrue(trecho.geohash_consulta.startswith("6gdz"))

    def test_descarta_classe_fora_da_lista(self):
        self.assertEqual(trechos.montar_trechos(feature(classe="footway")), [])

    def test_descarta_subtype_diferente_de_road(self):
        self.assertEqual(trechos.montar_trechos(feature(subtype="rail")), [])

    def test_descarta_geometria_que_nao_e_linha(self):
        self.assertEqual(
            trechos.montar_trechos(feature(tipo_geometria="MultiLineString")), []
        )

    def test_somente_com_nome(self):
        self.assertEqual(
            trechos.montar_trechos(feature(nome=None), somente_com_nome=True), []
        )
        self.assertEqual(len(trechos.montar_trechos(feature(nome=None))), 1)

    def test_divisao_por_conector_usa_faixa_linear_no_id(self):
        conectores = [
            {"connector_id": "a", "at": 0.0},
            {"connector_id": "b", "at": 0.5},
            {"connector_id": "c", "at": 1.0},
        ]
        resultado = trechos.montar_trechos(
            feature(conectores=conectores), dividir_nos_conectores=True
        )
        self.assertEqual(len(resultado), 2)
        for trecho in resultado:
            self.assertRegex(trecho.id, r"^gers:[0-9a-f\-]{36}@[0-9.]+:[0-9.]+$")
            self.assertTrue(PADRAO_TRECHO_ID.match(trecho.id), trecho.id)
        self.assertTrue(resultado[0].id.endswith("@0.0000:0.5000"))
        self.assertTrue(resultado[1].id.endswith("@0.5000:1.0000"))

    def test_aceita_o_id_hex_legado(self):
        resultado = trechos.montar_trechos(
            feature(identificador="08628d5437ffffff0473ffc36df547db")
        )
        self.assertEqual(resultado[0].id, "gers:08628d5437ffffff0473ffc36df547db")


class TrechosDeGeojsonTest(unittest.TestCase):
    def test_converte_e_nao_repete_ids(self):
        documento = {
            "type": "FeatureCollection",
            "features": [feature(), feature(), feature(classe="footway")],
        }
        resultado = trechos.trechos_de_geojson(documento)
        self.assertEqual(len(resultado), 1)

    def test_exige_feature_collection(self):
        with self.assertRaises(ValueError):
            trechos.trechos_de_geojson({"type": "Feature"})

if __name__ == "__main__":
    unittest.main()
