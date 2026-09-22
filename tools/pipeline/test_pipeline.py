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

import json
import re
import tempfile
import unittest
from pathlib import Path

import export_trechos
import geohash
import semear_firestore
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

    def test_segmento_sem_esquina_no_meio_mantem_a_chave_simples(self):
        conectores = [
            {"connector_id": "a", "at": 0.0},
            {"connector_id": "b", "at": 1.0},
        ]
        resultado = trechos.montar_trechos(
            feature(conectores=conectores), dividir_nos_conectores=True
        )
        self.assertEqual(len(resultado), 1)
        self.assertEqual(
            resultado[0].id, "gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9"
        )
        self.assertFalse(resultado[0].id.endswith(":1.0000"))

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

class ExportTrechosCliTest(unittest.TestCase):
    """O export corta cada segmento nos conectores por padrao (lado de quadra)."""

    def test_divide_por_padrao(self):
        argumentos = export_trechos.criar_parser().parse_args([])
        self.assertTrue(argumentos.dividir_nos_conectores)

    def test_flag_desliga_a_divisao(self):
        argumentos = export_trechos.criar_parser().parse_args(
            ["--nao-dividir-nos-conectores"]
        )
        self.assertFalse(argumentos.dividir_nos_conectores)

    def test_flag_antiga_continua_valendo(self):
        argumentos = export_trechos.criar_parser().parse_args(
            ["--dividir-nos-conectores"]
        )
        self.assertTrue(argumentos.dividir_nos_conectores)

    def test_export_gera_uma_linha_por_lado_de_quadra(self):
        conectores = [
            {"connector_id": "a", "at": 0.0},
            {"connector_id": "esquina", "at": 0.5},
            {"connector_id": "c", "at": 1.0},
        ]
        documento = {
            "type": "FeatureCollection",
            "features": [feature(conectores=conectores)],
        }
        gerados = trechos.trechos_de_geojson(
            documento,
            release="2026-08-19.0",
            dividir_nos_conectores=True,
        )
        self.assertEqual(len(gerados), 2)

        with tempfile.TemporaryDirectory() as pasta:
            caminho = Path(pasta) / "trechos.ndjson"
            export_trechos.gerar_ndjson(gerados, caminho)
            linhas = [
                json.loads(linha)
                for linha in caminho.read_text(encoding="utf-8").splitlines()
                if linha
            ]

        identificador = "c1d70afe-a7de-4b73-a41c-e92526ab72f9"
        self.assertEqual(
            sorted(linha["id"] for linha in linhas),
            [
                f"gers:{identificador}@0.0000:0.5000",
                f"gers:{identificador}@0.5000:1.0000",
            ],
        )
        # Lados de quadra distintos: mesmo segmento, faixas (e centroides) diferentes.
        self.assertNotEqual(linhas[0]["centroide"], linhas[1]["centroide"])
        for linha in linhas:
            self.assertTrue(PADRAO_TRECHO_ID.match(linha["id"]), linha["id"])


class _DocumentoFalso:
    """Documento do Admin SDK reduzido a sua referencia."""

    def __init__(self, identificador: str) -> None:
        self.reference = identificador


class _ColecaoFalsa:
    """Colecao minima do Admin SDK para testar o seeder sem rede."""

    def __init__(self, cliente: "_ClienteFalso") -> None:
        self._cliente = cliente

    def document(self, identificador: str) -> str:
        return identificador

    def limit(self, quantidade: int) -> "_ColecaoFalsa":
        self._cliente.limite = quantidade
        return self

    def stream(self) -> list:
        pagina = self._cliente.existentes[: self._cliente.limite]
        self._cliente.existentes = self._cliente.existentes[self._cliente.limite :]
        return [_DocumentoFalso(identificador) for identificador in pagina]


class _LoteFalso:
    def __init__(self, cliente: "_ClienteFalso") -> None:
        self._cliente = cliente
        self._ids: list[str] = []
        self._apagar: list[str] = []

    def set(self, referencia: str, corpo: dict) -> None:
        self._ids.append(referencia)
        self._cliente.corpos[referencia] = corpo

    def delete(self, referencia: str) -> None:
        self._apagar.append(referencia)

    def commit(self) -> None:
        self._cliente.commits += 1
        self._cliente.gravados.extend(self._ids)
        self._cliente.apagados.extend(self._apagar)


class _ClienteFalso:
    """Cliente do Admin SDK de mentira: so guarda o que foi gravado."""

    def __init__(self, existentes: list | None = None) -> None:
        self.gravados: list[str] = []
        self.apagados: list[str] = []
        self.corpos: dict[str, dict] = {}
        self.existentes = list(existentes or [])
        self.limite = 0
        self.commits = 0

    def collection(self, _nome: str) -> _ColecaoFalsa:
        return _ColecaoFalsa(self)

    def batch(self) -> _LoteFalso:
        return _LoteFalso(self)


class SemeadorTest(unittest.TestCase):
    """O seeder le o NDJSON do export e grava na forma que o app espera."""

    @staticmethod
    def ponto(lat: float, lng: float) -> dict:
        """Faz as vezes de `GeoPoint` do Admin SDK (que nao esta instalado aqui)."""
        return {"latitude": lat, "longitude": lng}

    def test_converte_geometria_e_centroide_em_geopoint(self):
        documento = trechos.montar_trechos(feature(), release="2026-08-19.0")[
            0
        ].para_documento()
        identificador, corpo = semear_firestore.para_firestore(documento, self.ponto)

        self.assertEqual(identificador, documento["id"])
        self.assertEqual(corpo["id"], documento["id"])
        self.assertEqual(set(corpo["centroide"]), {"latitude", "longitude"})
        self.assertEqual(len(corpo["geometria"]), len(documento["geometria"]))
        for vertice in corpo["geometria"]:
            self.assertEqual(set(vertice), {"latitude", "longitude"})
        self.assertEqual(corpo["geohashConsulta"], documento["geohashConsulta"])
        self.assertEqual(corpo["via"], "Rua Teste")
        self.assertEqual(corpo["release"], "2026-08-19.0")

    def test_le_o_ndjson_do_export(self):
        trecho = trechos.montar_trechos(feature())[0]
        with tempfile.TemporaryDirectory() as pasta:
            caminho = Path(pasta) / "trechos.ndjson"
            export_trechos.gerar_ndjson([trecho], caminho)
            lidos = list(semear_firestore.ler_documentos(caminho, self.ponto))

        self.assertEqual(len(lidos), 1)
        self.assertEqual(lidos[0][0], trecho.id)

    def test_ignora_linhas_vazias(self):
        documento = json.dumps(trechos.montar_trechos(feature())[0].para_documento())
        with tempfile.TemporaryDirectory() as pasta:
            caminho = Path(pasta) / "trechos.ndjson"
            caminho.write_text(f"\n{documento}\n\n", encoding="utf-8")
            lidos = list(semear_firestore.ler_documentos(caminho, self.ponto))

        self.assertEqual(len(lidos), 1)

    def test_rejeita_linha_quebrada(self):
        for conteudo in ('{"id": "gers:x"}\n', "nao e json\n", "[1, 2]\n"):
            with tempfile.TemporaryDirectory() as pasta:
                caminho = Path(pasta) / "trechos.ndjson"
                caminho.write_text(conteudo, encoding="utf-8")
                with self.assertRaises(ValueError, msg=conteudo):
                    list(semear_firestore.ler_documentos(caminho, self.ponto))

    def test_ida_e_volta_do_export_para_o_seeder(self):
        """GeoJSON -> NDJSON (pipeline) -> documento do Firestore (seeder)."""
        conectores = [
            {"connector_id": "a", "at": 0.0},
            {"connector_id": "esquina", "at": 0.5},
            {"connector_id": "c", "at": 1.0},
        ]
        documento = {
            "type": "FeatureCollection",
            "features": [feature(conectores=conectores)],
        }
        gerados = trechos.trechos_de_geojson(documento, dividir_nos_conectores=True)

        with tempfile.TemporaryDirectory() as pasta:
            caminho = Path(pasta) / "trechos.ndjson"
            export_trechos.gerar_ndjson(gerados, caminho)
            lidos = dict(semear_firestore.ler_documentos(caminho, self.ponto))

        self.assertEqual(len(lidos), 2)
        for identificador, corpo in lidos.items():
            self.assertTrue(PADRAO_TRECHO_ID.match(identificador), identificador)
            self.assertEqual(corpo["id"], identificador)
            self.assertEqual(set(corpo["centroide"]), {"latitude", "longitude"})
            self.assertEqual(len(corpo["geometria"]), 2)


    def test_escreve_em_lotes(self):
        cliente = _ClienteFalso()
        documentos = iter([(f"gers:{i}", {}) for i in range(4)])
        gravados = semear_firestore.escrever(cliente, documentos, tamanho_lote=2)

        self.assertEqual(gravados, 4)
        self.assertEqual(cliente.commits, 2)
        self.assertEqual(cliente.gravados, [f"gers:{i}" for i in range(4)])

    def test_numero_redondo_nao_commita_lote_vazio(self):
        cliente = _ClienteFalso()
        documentos = iter([(f"gers:{i}", {}) for i in range(2)])
        semear_firestore.escrever(cliente, documentos, tamanho_lote=2)

        self.assertEqual(cliente.commits, 1)

    def test_limpa_em_paginas(self):
        cliente = _ClienteFalso(existentes=["gers:a", "gers:b", "gers:c"])
        apagados = semear_firestore.limpar(cliente, tamanho_lote=2)

        self.assertEqual(apagados, 3)
        self.assertEqual(cliente.apagados, ["gers:a", "gers:b", "gers:c"])

    def test_valida_o_host_do_emulador(self):
        self.assertEqual(
            semear_firestore.validar_emulador(" localhost:8080 "), "localhost:8080"
        )
        self.assertEqual(
            semear_firestore.validar_emulador("firebase:8080"), "firebase:8080"
        )
        self.assertEqual(semear_firestore.EMULADOR_PADRAO, "localhost:8080")

        for ruim in ("", "localhost", "http://localhost:8080", "a:8080; rm -rf /"):
            with self.assertRaises(ValueError, msg=ruim):
                semear_firestore.validar_emulador(ruim)

    def test_cli_usa_os_padroes_do_repositorio(self):
        argumentos = semear_firestore.criar_parser().parse_args([])

        self.assertEqual(argumentos.arquivo, Path("trechos.ndjson"))
        self.assertEqual(argumentos.projeto, "demo-achar-vagas")
        self.assertFalse(argumentos.limpar)
        self.assertEqual(
            semear_firestore.validar_emulador(argumentos.emulador),
            argumentos.emulador,
        )









if __name__ == "__main__":
    unittest.main()
