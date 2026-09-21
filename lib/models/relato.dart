/// Relato de um usuario sobre um trecho de rua.
///
/// O relato e a *verdade* do sistema: guarda sempre o ponto exato do GPS (com o
/// geohash usado nas consultas) e a referencia do trecho resolvido naquele
/// momento. Se o trecho era apenas aproximado (fallback), isso fica registrado
/// em [trechoId] — nao precisamos "reprocessar" o historico quando a malha
/// daquela rua chegar.
library;

import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:latlong2/latlong.dart';

enum TipoRelato { vaga, lotado, saindo }

extension TipoRelatoTexto on TipoRelato {
  /// Valor gravado no Firestore (validado tambem em `firestore.rules`).
  String get valor => switch (this) {
        TipoRelato.vaga => 'vaga',
        TipoRelato.lotado => 'lotado',
        TipoRelato.saindo => 'saindo',
      };

  String get rotulo => switch (this) {
        TipoRelato.vaga => 'Tem vaga',
        TipoRelato.lotado => 'Lotado',
        TipoRelato.saindo => 'Estou saindo',
      };

  static TipoRelato? tentarParse(String? valor) {
    for (final tipo in TipoRelato.values) {
      if (tipo.valor == valor) return tipo;
    }
    return null;
  }
}

class Relato {
  const Relato({
    required this.uid,
    required this.trechoId,
    required this.tipo,
    required this.ponto,
    required this.geohash,
    required this.geohashConsulta,
    required this.criadoEm,
    this.id,
    this.precisaoM,
  });

  /// Monta o relato calculando os geohashes do ponto informado.
  factory Relato.novo({
    required String uid,
    required TrechoId trechoId,
    required TipoRelato tipo,
    required LatLng ponto,
    double? precisaoM,
    DateTime? criadoEm,
  }) =>
      Relato(
        uid: uid,
        trechoId: trechoId,
        tipo: tipo,
        ponto: ponto,
        geohash: geohashCodificar(
          ponto.latitude,
          ponto.longitude,
          precisao: 9,
        ),
        geohashConsulta: geohashCodificar(
          ponto.latitude,
          ponto.longitude,
          precisao: precisaoGeohashConsulta,
        ),
        precisaoM: precisaoM,
        criadoEm: criadoEm ?? DateTime.now().toUtc(),
      );

  final String? id;
  final String uid;
  final TrechoId trechoId;
  final TipoRelato tipo;
  final LatLng ponto;

  /// Geohash de 9 caracteres (~5 m) do ponto relatado.
  final String geohash;

  /// Geohash de 6 caracteres, indice da consulta por proximidade.
  final String geohashConsulta;

  final double? precisaoM;
  final DateTime criadoEm;

  /// `true` enquanto o relato ainda vale para pintar o mapa.
  bool validoEm(DateTime agora, Duration validade) =>
      agora.difference(criadoEm) <= validade;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uid': uid,
        'trechoId': trechoId.valor,
        'tipo': tipo.valor,
        'ponto': <double>[ponto.latitude, ponto.longitude],
        'geohash': geohash,
        'geohashConsulta': geohashConsulta,
        'precisaoM': precisaoM,
        'criadoEm': criadoEm.toUtc().toIso8601String(),
      };

  static Relato fromMap(String id, Map<String, dynamic> map) {
    final tipo = TipoRelatoTexto.tentarParse(map['tipo'] as String?);
    if (tipo == null) {
      throw FormatException('tipo de relato invalido: ${map['tipo']}');
    }
    final trechoId = TrechoId.parse(map['trechoId'] as String);
    final ponto = map['ponto'];
    final criadoEm = map['criadoEm'];

    return Relato(
      id: id,
      uid: map['uid'] as String,
      trechoId: trechoId,
      tipo: tipo,
      ponto: _ponto(ponto),
      geohash: map['geohash'] as String,
      geohashConsulta: (map['geohashConsulta'] as String?) ??
          (map['geohash'] as String).substring(0, precisaoGeohashConsulta),
      precisaoM: (map['precisaoM'] as num?)?.toDouble(),
      criadoEm: criadoEm is String
          ? DateTime.parse(criadoEm)
          : (criadoEm as DateTime),
    );
  }

  static LatLng _ponto(Object? bruto) {
    if (bruto is Map) {
      final lat = (bruto['lat'] ?? bruto['latitude']) as num;
      final lng = (bruto['lng'] ?? bruto['longitude']) as num;
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    final lista = bruto as List<dynamic>;
    return LatLng((lista[0] as num).toDouble(), (lista[1] as num).toDouble());
  }

  @override
  String toString() =>
      'Relato(${tipo.valor} em ${trechoId.valor} por $uid as $criadoEm)';
}
