/// Geometria pura (sem dependencia de Firebase), usada para snap de ponto em
/// trecho de rua, distancias e caixas envolventes.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Raio medio da Terra em metros (WGS84).
const double raioTerraM = 6371008.8;

const double _grauParaRadiano = math.pi / 180.0;

/// Distancia entre dois pontos, em metros (formula de haversine).
double distanciaM(LatLng a, LatLng b) {
  final dLat = (b.latitude - a.latitude) * _grauParaRadiano;
  final dLng = (b.longitude - a.longitude) * _grauParaRadiano;
  final lat1 = a.latitude * _grauParaRadiano;
  final lat2 = b.latitude * _grauParaRadiano;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * raioTerraM * math.asin(math.min(1, math.sqrt(h)));
}

/// Distancia (em metros) do [ponto] ate o ponto mais proximo do segmento
/// [inicio]-[fim].
///
/// A projecao local equirretangular (metros) e suficiente na escala de uma
/// quadra: o erro e desprezivel para trechos urbanos de poucas centenas de m.
double distanciaPontoSegmentoM(LatLng ponto, LatLng inicio, LatLng fim) {
  // Projecao equirretangular com origem no [inicio].
  final fator = math.cos(inicio.latitude * _grauParaRadiano);
  double x(LatLng p) => (p.longitude - inicio.longitude) * _grauParaRadiano * raioTerraM * fator;
  double y(LatLng p) => (p.latitude - inicio.latitude) * _grauParaRadiano * raioTerraM;

  final px = x(ponto), py = y(ponto);
  final ax = 0.0, ay = 0.0;
  final bx = x(fim), by = y(fim);

  final dx = bx - ax, dy = by - ay;
  final comprimento2 = dx * dx + dy * dy;
  if (comprimento2 == 0) return math.sqrt(px * px + py * py);

  var t = ((px - ax) * dx + (py - ay) * dy) / comprimento2;
  t = t.clamp(0.0, 1.0);
  final projX = ax + t * dx, projY = ay + t * dy;
  return math.sqrt(math.pow(px - projX, 2) + math.pow(py - projY, 2));
}

/// Distancia (em metros) do [ponto] ate a linha definida por [vertices].
///
/// Retorna `double.infinity` quando a linha tem menos de dois vertices.
double distanciaPontoLinhaM(LatLng ponto, List<LatLng> vertices) {
  if (vertices.length < 2) return double.infinity;
  var menor = double.infinity;
  for (var i = 0; i < vertices.length - 1; i++) {
    final d = distanciaPontoSegmentoM(ponto, vertices[i], vertices[i + 1]);
    if (d < menor) menor = d;
  }
  return menor;
}

/// Ponto sobre a linha mais proximo do [ponto] informado.
///
/// Util para "ancorar" o relato na geometria do trecho.
LatLng pontoMaisProximoNaLinha(LatLng ponto, List<LatLng> vertices) {
  if (vertices.isEmpty) return ponto;
  if (vertices.length == 1) return vertices.first;

  var melhor = vertices.first;
  var menorDist = double.infinity;
  for (var i = 0; i < vertices.length - 1; i++) {
    final d = distanciaPontoSegmentoM(ponto, vertices[i], vertices[i + 1]);
    if (d < menorDist) {
      menorDist = d;
      melhor = _projecaoNoSegmento(ponto, vertices[i], vertices[i + 1]);
    }
  }
  return melhor;
}

LatLng _projecaoNoSegmento(LatLng ponto, LatLng inicio, LatLng fim) {
  final fator = math.cos(inicio.latitude * _grauParaRadiano);
  final ax = 0.0, ay = 0.0;
  final bx = (fim.longitude - inicio.longitude) * _grauParaRadiano * raioTerraM * fator;
  final by = (fim.latitude - inicio.latitude) * _grauParaRadiano * raioTerraM;
  final px = (ponto.longitude - inicio.longitude) * _grauParaRadiano * raioTerraM * fator;
  final py = (ponto.latitude - inicio.latitude) * _grauParaRadiano * raioTerraM;

  final dx = bx - ax, dy = by - ay;
  final comprimento2 = dx * dx + dy * dy;
  if (comprimento2 == 0) return inicio;

  var t = ((px - ax) * dx + (py - ay) * dy) / comprimento2;
  t = t.clamp(0.0, 1.0);

  final metrosX = t * bx;
  final metrosY = t * by;
  return LatLng(
    inicio.latitude + metrosY / raioTerraM / _grauParaRadiano,
    inicio.longitude + metrosX / raioTerraM / _grauParaRadiano / fator,
  );
}

/// Deslocamento de [raioM] metros a partir de [origem] num rumo de [graus]
/// (0 = norte, 90 = leste). Usado para gerar caixas de consulta.
LatLng deslocarM(LatLng origem, double metros, double graus) {
  final rad = graus * _grauParaRadiano;
  final dLat = metros * math.cos(rad) / raioTerraM;
  final dLng = metros * math.sin(rad) / (raioTerraM * math.cos(origem.latitude * _grauParaRadiano));
  return LatLng(
    origem.latitude + dLat / _grauParaRadiano,
    origem.longitude + dLng / _grauParaRadiano,
  );
}
