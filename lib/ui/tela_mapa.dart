/// Tela inicial: mapa do OpenStreetMap, GPS do usuario e relatos por trecho.
///
/// Concentra as tres issues desta entrega:
/// - #3  mapa OSM com zoom/pan, centralizado em Campo Mourao, permissao de
///       localizacao pedida na abertura e marcador da posicao atual;
/// - #12 botao de localizacao e botoes de relato, resolvendo o trecho pela
///       cascata Overture (GERS) -> geohash;
/// - #13 trechos pintados pelo relato mais recente (validade de 20 min), com
///       linha para trecho canonico e circulo para o fallback geohash;
/// - #30 localizacao indisponivel explicada por caso, com atalho para as
///       configuracoes do app (permissao negada) ou do sistema (GPS desligado);
/// - #29 faixa discreta sobre o mapa quando o app esta sem backend (modo
///       demonstracao, com o motivo que o bootstrap registrou) e quando a
///       leitura dos relatos ou dos trechos falha em tempo de execucao.
///
/// A tela nao fala com Firebase nem com `geolocator` diretamente: recebe um
/// [AmbienteApp], o que permite rodar em modo demonstracao e testar com
/// posicao fixa.
library;

import 'dart:async';

import 'package:achar_vagas_app/ambiente.dart';
import 'package:achar_vagas_app/config.dart';
import 'package:achar_vagas_app/geo/geo_utils.dart';
import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:achar_vagas_app/services/localizacao.dart';
import 'package:achar_vagas_app/ui/botoes_relato.dart';
import 'package:achar_vagas_app/ui/camadas_mapa.dart';
import 'package:achar_vagas_app/ui/detalhe_trecho.dart';
import 'package:achar_vagas_app/ui/faixa_aviso.dart';
import 'package:achar_vagas_app/ui/legenda_estado.dart';
import 'package:achar_vagas_app/ui/paleta_estado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Chave do marcador da posicao do usuario (usada nos testes de widget).
const Key chaveMarcadorUsuario = Key('marcador-usuario');

/// Chave do botao que pede a permissao e centraliza no usuario.
const Key chaveBotaoLocalizacao = Key('botao-localizacao');

/// chave da acao que abre as configuracoes no aviso de localizacao.
const Key chaveAbrirConfiguracoes = Key('abrir-configuracoes');

class TelaMapa extends StatefulWidget {
  const TelaMapa({super.key, required this.ambiente, this.tileProvider});

  final AmbienteApp ambiente;

  /// Provider de tiles alternativo. Nos testes de widget isso evita a rede
  /// (o `flutter_test` responde 400 para qualquer requisicao HTTP).
  final TileProvider? tileProvider;

  @override
  State<TelaMapa> createState() => _TelaMapaState();
}

class _TelaMapaState extends State<TelaMapa> {
  final MapController _controlador = MapController();

  /// hit test separado por camada: cada uma sobrescreve o proprio valor.
  final LayerHitNotifier<String> _hitLinhas =
      ValueNotifier<LayerHitResult<String>?>(null);
  final LayerHitNotifier<String> _hitCirculos =
      ValueNotifier<LayerHitResult<String>?>(null);

  StreamSubscription<List<Relato>>? _inscricaoRelatos;
  StreamSubscription<LatLng>? _inscricaoPosicao;
  Timer? _relogio;

  bool _mapaPronto = false;
  LatLng? _centroPendente;
  double? _zoomPendente;

  LatLng? _posicaoUsuario;
  LatLng _centroConsulta = centroCampoMourao;
  List<Trecho> _trechos = const <Trecho>[];
  List<Relato> _relatos = const <Relato>[];
  List<TrechoEstado> _camadas = const <TrechoEstado>[];
  bool _gravando = false;

  /// Leitura que falhou em tempo de execucao (issue #29): o stream de relatos e
  /// a consulta de trechos param de alimentar o mapa sem derrubar a tela.
  bool _falhaRelatos = false;
  bool _falhaTrechos = false;

  bool get _semDados => _falhaRelatos || _falhaTrechos;

  @override
  void initState() {
    super.initState();
    _observarRelatos(_centroConsulta);
    unawaited(_carregarTrechos(_centroConsulta));
    // #3: na abertura a falha e silenciosa (mapa ja abre em campo mourao) e o
    // aviso com correcao fica so para o botao de localizacao.
    unawaited(_irParaUsuario(inicial: true));
    _inscricaoPosicao = widget.ambiente.localizacao.acompanhar().listen((ponto) {
      if (!mounted) return;
      setState(() => _posicaoUsuario = ponto);
    });
    // Sem evento novo, um relato vence sozinho depois de 20 min: o tique
    // recalcula as cores para o trecho voltar ao neutro.
    _relogio = Timer.periodic(const Duration(minutes: 1), (_) => _recalcular());
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _inscricaoRelatos?.cancel();
    _inscricaoPosicao?.cancel();
    _hitLinhas.dispose();
    _hitCirculos.dispose();
    _controlador.dispose();
    super.dispose();
  }

  /// Assina os relatos proximos do [centro].
  void _observarRelatos(LatLng centro) {
    _inscricaoRelatos?.cancel();
    _inscricaoRelatos = widget.ambiente.relatos
        .observarProximos(centro, raioM: raioRelatosMapaM)
        .listen(
          _receberRelatos,
          // Sem banco/rede o mapa continua util (a camada so nao pinta nada),
          // mas o usuario precisa saber que os dados podem estar velhos (#29).
          onError: (Object _) {
            if (!mounted) return;
            setState(() => _falhaRelatos = true);
          },
        );
  }

  void _receberRelatos(List<Relato> relatos) {
    if (!mounted) return;
    _relatos = relatos;
    // Chegou leitura nova: o aviso de dados velhos sai (issue #29).
    _falhaRelatos = false;
    _recalcular();
  }

  /// Troca o centro de consulta quando o usuario se move o suficiente.
  void _recentralizar(LatLng centro) {
    if (distanciaM(_centroConsulta, centro) < passoRecargaMapaM) return;
    _observarRelatos(centro);
    unawaited(_carregarTrechos(centro));
  }

  /// Busca os trechos canonicos que fornecem geometria e nome de via.
  Future<void> _carregarTrechos(LatLng centro) async {
    _centroConsulta = centro;
    try {
      final trechos = await widget.ambiente.trechos.candidatosProximos(
        centro,
        raioM: raioTrechosMapaM,
        limite: limiteTrechosMapa,
      );
      if (!mounted) return;
      _trechos = trechos;
      _falhaTrechos = false;
      _recalcular();
    } catch (_) {
      // Base indisponivel: trecho canonico vira circulo e a faixa avisa que os
      // dados podem estar velhos, sem quebrar a tela (issue #29).
      if (!mounted) return;
      _falhaTrechos = true;
      _recalcular();
    }
  }

  /// Recalcula o estado por trecho com o relogio atual (regra da #13).
  void _recalcular() {
    if (!mounted) return;
    final agora = DateTime.now().toUtc();
    final camadas = combinar(
      trechos: _trechos,
      estados: agregarPorTrecho(
        _relatos,
        agora: agora,
        validade: validadeRelatoPadrao,
      ),
      pontos: pontosMaisRecentes(
        _relatos,
        agora: agora,
        validade: validadeRelatoPadrao,
      ),
    );
    setState(() => _camadas = camadas);
  }

  /// pede a localizacao e centraliza; na abertura a falha e silenciosa.
  Future<void> _irParaUsuario({bool inicial = false}) async {
    final resultado = await widget.ambiente.localizacao.posicaoAtual();
    if (!mounted) return;
    switch (resultado) {
      case LocalizacaoOk(:final ponto):
        setState(() => _posicaoUsuario = ponto);
        _mover(ponto, zoomUsuarioMapa);
        _recentralizar(ponto);
      case LocalizacaoIndisponivel(:final motivo):
        if (!inicial) _avisarSemLocalizacao(motivo);
    }
  }

  /// aviso do motivo, com botao de correcao quando houver.
  void _avisarSemLocalizacao(MotivoLocalizacao motivo) {
    final aviso = switch (motivo) {
      MotivoLocalizacao.permissaoNegada => _AvisoLocalizacao(
          texto: 'A permissão de localização está bloqueada. Autorize o '
              'acesso nas configurações do app.',
          rotuloAcao: 'Abrir configurações',
          abrirConfiguracoes: widget.ambiente.localizacao.abrirConfiguracoes,
        ),
      MotivoLocalizacao.permissaoNegadaParaSempre => _AvisoLocalizacao(
          texto: 'A permissão de localização está negada em definitivo. Abra '
              'as configurações do app e permita o acesso.',
          rotuloAcao: 'Abrir configurações',
          abrirConfiguracoes: widget.ambiente.localizacao.abrirConfiguracoes,
        ),
      MotivoLocalizacao.servicoDesligado => _AvisoLocalizacao(
          texto: 'O GPS do aparelho está desligado. Ative a localização do '
              'sistema para o app saber onde você está.',
          rotuloAcao: 'Ativar localização',
          abrirConfiguracoes:
              widget.ambiente.localizacao.abrirConfiguracoesDeLocalizacao,
        ),
      MotivoLocalizacao.falha => const _AvisoLocalizacao(
          texto: 'Não foi possível obter sua localização agora. '
              'Tente de novo em instantes.',
        ),
    };
    final abrirConfiguracoes = aviso.abrirConfiguracoes;
    _avisar(
      aviso.texto,
      acao: abrirConfiguracoes == null
          ? null
          : SnackBarAction(
              key: chaveAbrirConfiguracoes,
              label: aviso.rotuloAcao!,
              onPressed: () => unawaited(abrirConfiguracoes()),
            ),
    );
  }

  /// Move a camera; se o mapa ainda nao estiver pronto, guarda para depois.
  void _mover(LatLng ponto, double zoom) {
    if (!_mapaPronto) {
      _centroPendente = ponto;
      _zoomPendente = zoom;
      return;
    }
    _controlador.move(ponto, zoom);
  }

  void _aoFicarPronto() {
    _mapaPronto = true;
    final centro = _centroPendente;
    if (centro == null) return;
    // `onMapReady` acontece junto com o primeiro build: mover no proximo frame
    // evita mexer no mapa enquanto a arvore ainda esta sendo construida.
    final zoom = _zoomPendente ?? zoomUsuarioMapa;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controlador.move(centro, zoom);
    });
  }

  /// Fluxo do relato (#12): posicao -> trecho pela cascata -> repositorio.
  Future<void> _relatar(TipoRelato tipo) async {
    if (_gravando) return;
    setState(() => _gravando = true);
    try {
      final resultado = await widget.ambiente.localizacao.posicaoAtual();
      if (resultado case LocalizacaoIndisponivel(:final motivo)) {
        // mesmo aviso do botao de localizacao.
        _avisarSemLocalizacao(motivo);
        return;
      }
      final posicao = (resultado as LocalizacaoOk).ponto;

      final trecho = await widget.ambiente.resolvedor.resolver(posicao);
      if (trecho == null) {
        _avisar('Não foi possível identificar o trecho desta posição.');
        return;
      }

      await widget.ambiente.relatos.criar(
        Relato.novo(
          uid: widget.ambiente.uid,
          trechoId: trecho.id,
          tipo: tipo,
          ponto: posicao,
        ),
      );

      if (!mounted) return;
      setState(() => _posicaoUsuario = posicao);
      _avisar('${tipo.rotulo} registrado em ${_rotuloTrecho(trecho)}');
    } catch (_) {
      // Regras do Firestore, rede ou base fora do ar: o usuario precisa saber.
      _avisar('Não foi possível registrar o relato.');
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  String _rotuloTrecho(Trecho trecho) => trecho.canonico
      ? trecho.rotulo
      : 'área aproximada (${trecho.id.chave}) — via ainda não mapeada';

  /// mostra um aviso rapido; [acao] e o botao opcional.
  void _avisar(String mensagem, {SnackBarAction? acao}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem), action: acao));
  }

  /// trechos canonicos com relato viram linha; hitValue e o id do trecho.
  List<Polyline<String>> _polylines() => <Polyline<String>>[
        for (final camada in _camadas)
          if (camada.temLinha)
            Polyline<String>(
              points: camada.linha,
              color: corDeEstado(camada.estado),
              strokeWidth: 6,
              borderColor: Colors.black.withValues(alpha: 0.35),
              borderStrokeWidth: 1,
              hitValue: camada.id.valor,
            ),
      ];

  /// Fallback geohash (e trecho sem geometria) viram circulo (regras 2 e 3).
  List<CircleMarker<String>> _circles() => <CircleMarker<String>>[
        for (final camada in _camadas)
          if (!camada.temLinha)
            CircleMarker<String>(
              point: camada.centro,
              radius: camada.raioM,
              useRadiusInMeter: true,
              color: corDeEstado(camada.estado).withValues(alpha: 0.45),
              borderColor: corDeEstado(camada.estado),
              borderStrokeWidth: 2,
              hitValue: camada.id.valor,
            ),
      ];

  /// abre o detalhe do trecho tocado, a partir do hit test da camada.
  void _abrirDetalheDe(LayerHitNotifier<String> hit) {
    final camada =
        trechoTocado(_camadas, hit.value?.hitValues ?? const <String>[]);
    if (camada == null) return;
    unawaited(
      mostrarDetalheTrecho(
        context,
        camada: camada,
        agora: DateTime.now().toUtc(),
      ),
    );
  }

  Marker _marcadorUsuario(LatLng ponto) => Marker(
        point: ponto,
        width: 26,
        height: 26,
        child: Container(
          key: chaveMarcadorUsuario,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
        ),
      );

  /// Faixas de aviso sobre o mapa (issue #29): modo demonstracao e/ou leitura
  /// que falhou em tempo de execucao. Nenhuma delas e tela de erro: o mapa
  /// continua util, so nao da mais para dizer que as cores vem do banco.
  Widget? _faixas() {
    final demonstracao = !widget.ambiente.usandoFirebase;
    if (!demonstracao && !_semDados) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (demonstracao)
          FaixaAviso.demonstracao(
            motivo: widget.ambiente.motivoSemFirebase ??
                MotivoSemFirebase.naoConfigurado,
          ),
        if (demonstracao && _semDados) const SizedBox(height: 4),
        if (_semDados) FaixaAviso.semDados(),
      ],
    );
  }

  Widget _painel(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const LegendaEstado(),
          const SizedBox(height: 8),
          Text(
            'Relatar o que você vê nesta via',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          BotoesRelato(onRelatar: _relatar, ocupado: _gravando),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final faixas = _faixas();
    return Scaffold(
      appBar: AppBar(title: const Text('Achar vagas')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                FlutterMap(
                  mapController: _controlador,
                  options: MapOptions(
                    initialCenter: centroCampoMourao,
                    initialZoom: zoomInicialMapa,
                    minZoom: zoomMinimoMapa,
                    maxZoom: zoomMaximoMapa,
                    onMapReady: _aoFicarPronto,
                    // Rotacao desligada: o app e de estacionamento, girar o mapa
                    // so atrapalha a leitura das vias.
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: <Widget>[
                    TileLayer(
                      urlTemplate: urlTilesOsm,
                      userAgentPackageName: userAgentOsm,
                      maxNativeZoom: 19,
                      tileProvider: widget.tileProvider,
                      // Tile que falha nao derruba a tela: a camada segue com o
                      // que carregou (o modo demonstracao roda muito sem rede).
                      errorTileCallback: (tile, erro, pilha) {},
                    ),
                    // hitNotifier so acerta trecho tocado: toque vazio nao abre.
                    GestureDetector(
                      onTap: () => _abrirDetalheDe(_hitLinhas),
                      child: PolylineLayer<String>(
                        polylines: _polylines(),
                        hitNotifier: _hitLinhas,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _abrirDetalheDe(_hitCirculos),
                      child: CircleLayer<String>(
                        circles: _circles(),
                        hitNotifier: _hitCirculos,
                        optimizeRadiusInMeters: true,
                      ),
                    ),
                    if (_posicaoUsuario != null)
                      MarkerLayer(
                        markers: <Marker>[_marcadorUsuario(_posicaoUsuario!)],
                      ),
                    RichAttributionWidget(
                      attributions: <SourceAttribution>[
                        TextSourceAttribution(atribuicaoOsm),
                      ],
                    ),
                  ],
                ),
                if (faixas != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: faixas,
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton(
                    key: chaveBotaoLocalizacao,
                    tooltip: 'Centralizar na minha localização',
                    onPressed: () => _irParaUsuario(),
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _painel(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// aviso de localizacao indisponivel: texto e, quando houver, botao de ajuste.
class _AvisoLocalizacao {
  const _AvisoLocalizacao({
    required this.texto,
    this.rotuloAcao,
    this.abrirConfiguracoes,
  });

  final String texto;

  /// rotulo do botao; obrigatorio quando [abrirConfiguracoes] existe.
  final String? rotuloAcao;

  /// o que o botao faz: config do app ou do sistema.
  final Future<void> Function()? abrirConfiguracoes;
}
