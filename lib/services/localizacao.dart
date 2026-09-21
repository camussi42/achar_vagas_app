/// Localizacao do usuario, isolada atras de uma interface.
///
/// Isolar isso permite: (a) testar a tela sem GPS; (b) rodar o app em modo dev
/// com uma posicao fixa; (c) trocar de provedor de GPS sem tocar na UI.
library;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

abstract class LocalizacaoService {
  /// Posicao atual ou `null` quando indisponivel/sem permissao.
  Future<LatLng?> posicaoAtual();

  /// Atualizacoes de posicao (vazio quando nao ha permissao).
  Stream<LatLng> acompanhar();
}

/// Implementacao real, com `geolocator`.
///
/// Nunca lanca excecao para a UI: qualquer falha (servico desligado, permissao
/// negada, timeout, plataforma sem suporte — ex.: web sem HTTPS) vira `null` ou
/// stream vazio, e a tela cai para a posicao inicial configuravel.
class LocalizacaoGeolocator implements LocalizacaoService {
  const LocalizacaoGeolocator({
    this.precisao = LocationAccuracy.high,
    this.timeout = const Duration(seconds: 12),
  });

  final LocationAccuracy precisao;
  final Duration timeout;

  @override
  Future<LatLng?> posicaoAtual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }
      if (permissao == LocationPermission.denied ||
          permissao == LocationPermission.deniedForever) {
        return null;
      }

      final posicao = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: precisao,
          timeLimit: timeout,
        ),
      );
      return LatLng(posicao.latitude, posicao.longitude);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<LatLng> acompanhar() {
    try {
      return Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: precisao,
          distanceFilter: 25,
        ),
      )
          .map((posicao) => LatLng(posicao.latitude, posicao.longitude))
          .handleError((Object _) {});
    } catch (_) {
      return const Stream<LatLng>.empty();
    }
  }
}

/// Posicao fixa: usada em modo dev (sem GPS) e nos testes.
class LocalizacaoFixa implements LocalizacaoService {
  const LocalizacaoFixa(this.ponto);

  final LatLng ponto;

  @override
  Future<LatLng?> posicaoAtual() async => ponto;

  @override
  Stream<LatLng> acompanhar() => Stream<LatLng>.value(ponto);
}
