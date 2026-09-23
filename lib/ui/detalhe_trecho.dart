/// detalhe do trecho tocado, com o que a tela ja calculou (sem consulta nova).
library;

import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/ui/camadas_mapa.dart';
import 'package:achar_vagas_app/ui/paleta_estado.dart';
import 'package:flutter/material.dart';

/// chave do conteudo do detalhe (testes de widget).
const Key chaveDetalheTrecho = Key('detalhe-trecho');

/// chave do botao de rota ate o trecho.
const Key chaveBotaoIrAteTrecho = Key('detalhe-ir-ate-aqui');

/// idade do relato mais recente em texto curto; horario futuro vira "agora".
String idadeLegivel(DateTime? criadoEm, {required DateTime agora}) {
  if (criadoEm == null) return 'sem relato';

  final decorrido = agora.difference(criadoEm);
  if (decorrido.inMinutes < 1) return 'agora';
  if (decorrido.inHours < 1) return 'há ${decorrido.inMinutes} min';

  final minutos = decorrido.inMinutes % 60;
  if (minutos == 0) return 'há ${decorrido.inHours} h';
  return 'há ${decorrido.inHours} h ${minutos.toString().padLeft(2, '0')}';
}

/// "1 relato válido" / "3 relatos válidos".
String _contagem(int total) =>
    total == 1 ? '1 relato válido' : '$total relatos válidos';

/// abre o detalhe de [camada]; com rota, pedir a rota fecha a folha antes.
Future<void> mostrarDetalheTrecho(
  BuildContext context, {
  required TrechoEstado camada,
  required DateTime agora,
  VoidCallback? onIrAteAqui,
}) {
  final irAteAqui = onIrAteAqui;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) => DetalheTrecho(
      camada: camada,
      agora: agora,
      onIrAteAqui: irAteAqui == null
          ? null
          : () {
              Navigator.of(context).pop();
              irAteAqui();
            },
    ),
  );
}

class DetalheTrecho extends StatelessWidget {
  const DetalheTrecho({
    super.key,
    required this.camada,
    required this.agora,
    this.onIrAteAqui,
  });

  final TrechoEstado camada;

  /// relogio usado para a idade do relato.
  final DateTime agora;

  /// abre a rota ate o trecho; sem callback o botao nao existe.
  final VoidCallback? onIrAteAqui;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final resumo = camada.resumo;
    final cor = corDeEstado(camada.estado);

    return SafeArea(
      top: false,
      child: Padding(
        key: chaveDetalheTrecho,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(camada.rotulo, style: tema.textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(camada.estado.rotulo, style: tema.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              resumo.temRelato
                  ? '${_contagem(resumo.total)} nos últimos '
                      '${validadeRelatoPadrao.inMinutes} min'
                  : 'Nenhum relato válido agora',
              style: tema.textTheme.bodyMedium,
            ),
            if (resumo.temRelato) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '${resumo.vagas} com vaga · ${resumo.lotados} lotado · '
                '${resumo.saindo} liberando',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Relato mais recente: '
                '${idadeLegivel(resumo.atualizadoEm, agora: agora)}',
                style: tema.textTheme.bodySmall,
              ),
            ],
            if (onIrAteAqui != null) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: chaveBotaoIrAteTrecho,
                onPressed: onIrAteAqui,
                icon: const Icon(Icons.directions),
                label: const Text('Ir até aqui'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
