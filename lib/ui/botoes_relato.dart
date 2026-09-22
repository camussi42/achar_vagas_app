/// Botoes de relato (issue #12): vaga / lotado / saindo.
///
/// A tela entrega o `onRelatar`; quem resolve o trecho e grava o relato e o
/// `TelaMapa`. Aqui so vive a escolha do tipo pelo usuario.
library;

import 'package:achar_vagas_app/models/relato.dart';
import 'package:achar_vagas_app/ui/paleta_estado.dart';
import 'package:flutter/material.dart';

class BotoesRelato extends StatelessWidget {
  const BotoesRelato({
    super.key,
    required this.onRelatar,
    this.ocupado = false,
  });

  /// Chamado com o tipo escolhido pelo usuario.
  final ValueChanged<TipoRelato> onRelatar;

  /// `true` enquanto um relato esta sendo gravado (desabilita os botoes).
  final bool ocupado;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final tipo in TipoRelato.values)
            FilledButton.icon(
              onPressed: ocupado ? null : () => onRelatar(tipo),
              style: FilledButton.styleFrom(
                backgroundColor: corDeTipo(tipo),
                foregroundColor: Colors.white,
              ),
              icon: Icon(_icone(tipo), size: 18),
              label: Text(tipo.rotulo),
            ),
        ],
      );

  IconData _icone(TipoRelato tipo) => switch (tipo) {
        TipoRelato.vaga => Icons.local_parking,
        TipoRelato.lotado => Icons.block,
        TipoRelato.saindo => Icons.directions_car,
      };
}
