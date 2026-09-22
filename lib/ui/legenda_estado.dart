/// Legenda das cores do mapa (issue #13).
///
/// Mostra tambem o estado neutro, que representa o trecho sem relato recente:
/// esses trechos nao sao pintados no mapa, mas o usuario precisa saber o que a
/// ausencia de cor significa.
library;

import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/ui/paleta_estado.dart';
import 'package:flutter/material.dart';

class LegendaEstado extends StatelessWidget {
  const LegendaEstado({super.key, this.validade = validadeRelatoPadrao});

  /// Validade dos relatos, exibida no rodape da legenda.
  final Duration validade;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      elevation: 2,
      color: tema.colorScheme.surface.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                for (final estado in EstadoTrecho.values)
                  _ItemLegenda(estado: estado, cor: corDeEstado(estado)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Relatos valem por ${validade.inMinutes} min',
              style: tema.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemLegenda extends StatelessWidget {
  const _ItemLegenda({required this.estado, required this.cor});

  final EstadoTrecho estado;
  final Color cor;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(estado.rotulo, style: Theme.of(context).textTheme.labelMedium),
        ],
      );
}
