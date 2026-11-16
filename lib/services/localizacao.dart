/// Localizacao do usuario, isolada atras de uma interface.
///
/// Isolar isso permite: (a) testar a tela sem GPS; (b) rodar o app em modo dev
/// com uma posicao fixa; (c) trocar de provedor de GPS sem tocar na UI.
library;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// motivo de a localizacao nao estar disponivel; a tela usa cada caso para
/// oferecer o caminho de correcao certo (configuracoes do app ou do sistema).
enum MotivoLocalizacao {
  /// permissao recusada agora; ainda pode ser pedida de novo.
  permissaoNegada,

  /// permissao recusada em definitivo; so resolve nas configuracoes.
  permissaoNegadaParaSempre,

  /// gps do aparelho desligado.
  servicoDesligado,

  /// timeout, plataforma sem suporte ou falha inesperada.
  falha,
}

/// resultado de [LocalizacaoService.posicaoAtual]: `ok` ou o motivo da falha;
/// nunca lanca, a tela deixa de adivinhar o que aconteceu.
sealed class ResultadoLocalizacao {
  const ResultadoLocalizacao();
}

/// posicao obtida com sucesso.
final class LocalizacaoOk extends ResultadoLocalizacao {
  const LocalizacaoOk(this.ponto);

  final LatLng ponto;
}

/// sem posicao: a ui usa [motivo] para explicar e oferecer a correcao.
final class LocalizacaoIndisponivel extends ResultadoLocalizacao {
  const LocalizacaoIndisponivel(this.motivo);

  final MotivoLocalizacao motivo;
}

abstract class LocalizacaoService {
  /// posicao atual ou o motivo de ela nao estar disponivel; nunca lanca.
  Future<ResultadoLocalizacao> posicaoAtual();

  /// atualizacoes de posicao (vazio quando nao ha permissao).
  Stream<LatLng> acompanhar();

  /// abre as configuracoes do app (permissao negada).
  Future<void> abrirConfiguracoes();

  /// abre as configuracoes de localizacao do sistema (gps desligado).
  Future<void> abrirConfiguracoesDeLocalizacao();
}

/// implementacao real, com `geolocator`; nunca lanca, qualquer falha vira
/// [LocalizacaoIndisponivel] (ou stream vazio) e a tela cai na posicao inicial.
class LocalizacaoGeolocator implements LocalizacaoService {
  const LocalizacaoGeolocator({
    this.precisao = LocationAccuracy.high,
    this.timeout = const Duration(seconds: 12),
  });

  final LocationAccuracy precisao;
  final Duration timeout;

  @override
  Future<ResultadoLocalizacao> posicaoAtual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocalizacaoIndisponivel(MotivoLocalizacao.servicoDesligado);
      }
      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }
      // deniedForever so sai do requestPermission apos "nao perguntar de novo".
      if (permissao == LocationPermission.deniedForever) {
        return const LocalizacaoIndisponivel(
          MotivoLocalizacao.permissaoNegadaParaSempre,
        );
      }
      if (permissao == LocationPermission.denied) {
        return const LocalizacaoIndisponivel(MotivoLocalizacao.permissaoNegada);
      }

      final posicao = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: precisao,
          timeLimit: timeout,
        ),
      );
      return LocalizacaoOk(LatLng(posicao.latitude, posicao.longitude));
    } catch (_) {
      return const LocalizacaoIndisponivel(MotivoLocalizacao.falha);
    }
  }

  @override
  Future<void> abrirConfiguracoes() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // web: o usuario ja foi avisado na tela.
    }
  }

  @override
  Future<void> abrirConfiguracoesDeLocalizacao() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {
      // falhar aqui nao muda o que a tela mostrou.
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

/// posicao fixa e permissao concedida: modo dev (sem gps) e testes.
class LocalizacaoFixa implements LocalizacaoService {
  const LocalizacaoFixa(this.ponto);

  final LatLng ponto;

  @override
  Future<ResultadoLocalizacao> posicaoAtual() async => LocalizacaoOk(ponto);

  @override
  Stream<LatLng> acompanhar() => Stream<LatLng>.value(ponto);

  @override
  Future<void> abrirConfiguracoes() async {}

  @override
  Future<void> abrirConfiguracoesDeLocalizacao() async {}
}
