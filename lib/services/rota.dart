/// rota ate o trecho: uri pura ([uriRota]) + servico com implementacao real
/// ([RotaUrlLauncher]) e duble para testes; falha vira `false`, nunca excecao.
library;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

abstract class RotaService {
  /// abre a rota ate o trecho; sem app disponivel a tela avisa.
  Future<bool> abrir(LatLng destino, {String? rotulo});
}

/// uri da rota: `geo:` no android, url universal do google maps nos demais.
Uri uriRota(LatLng destino, {String? rotulo, required bool android}) {
  final ponto = '${destino.latitude},${destino.longitude}';
  if (!android) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$ponto',
    );
  }

  // rotulo codificado entre parenteses; sem rotulo so as coordenadas.
  final nome = rotulo == null || rotulo.trim().isEmpty
      ? ''
      : '(${Uri.encodeComponent(rotulo)})';
  return Uri.parse('geo:$ponto?q=$ponto$nome');
}

/// encaminhamento real da rota via `url_launcher`.
class RotaUrlLauncher implements RotaService {
  const RotaUrlLauncher();

  /// `geo:` e so do android: web/desktop vao pelo Maps.
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> abrir(LatLng destino, {String? rotulo}) async {
    final uri = uriRota(destino, rotulo: rotulo, android: _android);
    try {
      // canLaunchUrl vira "nenhum app" em false (android 11+: ve o manifest).
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // falha do plugin ou uri rejeitada: avisa, nao quebra.
      return false;
    }
  }
}
