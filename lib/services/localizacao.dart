/// Localizacao do usuario, isolada atras de uma interface.
///
/// Isolar isso permite: (a) testar a tela sem GPS; (b) rodar o app em modo dev
/// com uma posicao fixa; (c) trocar de provedor de GPS sem tocar na UI.
library;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Por que a localizacao nao esta disponivel (issue #30).
///
/// A tela precisa da diferenca entre os casos: permissao negada e permissao
/// negada para sempre pedem o mesmo caminho (configuracoes do app), enquanto o
/// servico desligado pede as configuracoes de localizacao do sistema.
enum MotivoLocalizacao {
  /// Permissao recusada agora, mas ainda pode ser pedida de novo.
  permissaoNegada,

  /// Permissao recusada em definitivo: so o usuario resolve nas configuracoes.
  permissaoNegadaParaSempre,

  /// GPS do aparelho desligado.
  servicoDesligado,

  /// Timeout, plataforma sem suporte (ex.: web sem HTTPS) ou falha inesperada.
  falha,
}

/// Resultado de [LocalizacaoService.posicaoAtual]: `ok` ou o motivo da falha.
///
/// Substitui o `null` unico das issues #3/#12 (issue #30): a tela deixa de
/// adivinhar o que aconteceu e passa a explicar o caso certo.
sealed class ResultadoLocalizacao {
  const ResultadoLocalizacao();
}

/// Posicao obtida com sucesso.
final class LocalizacaoOk extends ResultadoLocalizacao {
  const LocalizacaoOk(this.ponto);

  final LatLng ponto;
}

/// Sem posicao: a UI usa [motivo] para explicar e oferecer a correcao.
final class LocalizacaoIndisponivel extends ResultadoLocalizacao {
  const LocalizacaoIndisponivel(this.motivo);

  final MotivoLocalizacao motivo;
}

abstract class LocalizacaoService {
  /// Posicao atual ou o motivo pelo qual ela nao esta disponivel.
  ///
  /// Nunca lanca: qualquer falha vira [LocalizacaoIndisponivel].
  Future<ResultadoLocalizacao> posicaoAtual();

  /// Atualizacoes de posicao (vazio quando nao ha permissao).
  Stream<LatLng> acompanhar();

  /// Abre as configuracoes do app: caminho para liberar a permissao negada.
  Future<void> abrirConfiguracoes();

  /// Abre as configuracoes de localizacao do sistema: caminho para ligar o GPS.
  Future<void> abrirConfiguracoesDeLocalizacao();
}

/// Implementacao real, com `geolocator`.
///
/// Nunca lanca excecao para a UI: qualquer falha (servico desligado, permissao
/// negada, timeout, plataforma sem suporte — ex.: web sem HTTPS) vira
/// [LocalizacaoIndisponivel] ou stream vazio, e a tela cai para a posicao
/// inicial configuravel.
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
      // `deniedForever` so sai do `requestPermission` quando o usuario marcou
      // "nao perguntar de novo": o app nao pode insistir, so mandar para as
      // configuracoes (issue #30).
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
      // Plataforma sem suporte (ex.: web): o usuario ja foi avisado na tela.
    }
  }

  @override
  Future<void> abrirConfiguracoesDeLocalizacao() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {
      // Idem: falhar aqui nao muda o que a tela mostrou.
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

/// Posicao fixa e permissao concedida: modo dev (sem GPS) e testes.
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
