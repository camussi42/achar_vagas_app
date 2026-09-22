/// Configuracao do mapa e do modo demonstracao.
///
/// Fica tudo aqui para a UI nao espalhar numeros magicos e para que o app use
/// exatamente o mesmo centro da pipeline (`tools/pipeline/export_trechos.py`) e
/// do teste de geohash (`test/geohash_test.dart`).
library;

import 'package:latlong2/latlong.dart';

/// Centro de Campo Mourao/PR (cidade-piloto do trabalho).
const LatLng centroCampoMourao = LatLng(-24.0430793, -52.3772141);

/// Zoom inicial: centro da cidade com os quarteiroes visiveis.
const double zoomInicialMapa = 16;

/// Zoom usado ao centralizar no usuario (o "meu local" dos apps de mapa).
const double zoomUsuarioMapa = 17;

const double zoomMinimoMapa = 12;
const double zoomMaximoMapa = 19;

/// Raio (m) dos relatos observados para pintar o mapa.
const double raioRelatosMapaM = 1200;

/// Raio (m) da consulta de trechos canonicos que fornecem a geometria.
const double raioTrechosMapaM = 1200;

/// Limite de trechos por consulta (o `whereIn` do Firestore aceita no maximo
/// 30 celulas de geohash, mas o limite aqui e do numero de documentos).
const int limiteTrechosMapa = 200;

/// Distancia (m) que o mapa precisa andar para valer uma nova consulta.
const double passoRecargaMapaM = 200;

/// Tiles do OpenStreetMap: sem chave de billing, com atribuicao na tela.
const String urlTilesOsm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Identificacao exigida pela politica de uso dos tiles do OSM.
const String userAgentOsm = 'br.edu.utfpr.achar_vagas_app';

/// Atribuicao obrigatoria dos dados e dos tiles do OSM.
const String atribuicaoOsm = 'OpenStreetMap contributors';
