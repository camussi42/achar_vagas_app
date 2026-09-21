/// Resolvedor canonico: usa a malha global importada para o Firestore
/// (tema `transportation` do Overture Maps, ids GERS).
///
/// O trecho escolhido e o segmento cuja linha esta mais perto do ponto, dentro
/// de uma tolerancia. Se o ponto estiver longe de qualquer trecho conhecido
/// (rua que a pipeline ainda nao importou), devolve `null` para a cascata cair
/// no fallback por geohash.
library;

import 'package:achar_vagas_app/geo/trecho_resolver.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:achar_vagas_app/services/trechos_repository.dart';
import 'package:latlong2/latlong.dart';

class ResolverOverture implements TrechoResolver {
  const ResolverOverture(
    this._trechos, {
    this.raioBuscaM = 150,
    this.toleranciaM = 60,
  });

  final TrechosRepository _trechos;

  /// Raio da consulta de candidatos (celulas geohash que serao consultadas).
  final double raioBuscaM;

  /// Distancia maxima, em metros, entre o ponto e a linha do trecho para
  /// considera-lo "o trecho onde o usuario esta".
  ///
  /// 60 m cobre com folga a imprecisao urbana de GPS e a distancia do eixo da
  /// via ate a calcada, sem "pular" para a rua paralela seguinte.
  final double toleranciaM;

  @override
  String get nome => 'overture';

  @override
  Future<Trecho?> resolver(LatLng ponto) async {
    final candidatos = await _trechos.candidatosProximos(
      ponto,
      raioM: raioBuscaM,
    );

    Trecho? melhor;
    var melhorDistancia = double.infinity;
    for (final candidato in candidatos) {
      final distancia = candidato.distanciaDe(ponto);
      if (distancia < melhorDistancia) {
        melhorDistancia = distancia;
        melhor = candidato;
      }
    }

    if (melhor == null || melhorDistancia > toleranciaM) return null;
    return melhor;
  }
}
