/// Faixas de aviso da tela (issue #29).
///
/// Nao e tela de erro: o modo demonstracao precisa continuar util (e o que roda
/// sem nenhum servico externo). A faixa so deixa explicito de onde vem as cores
/// do mapa e quando a leitura dos relatos falhou em tempo de execucao.
library;

import 'package:achar_vagas_app/ambiente.dart';
import 'package:flutter/material.dart';

/// Chave da faixa que avisa o modo demonstracao (sem Firebase).
const Key chaveFaixaDemonstracao = Key('faixa-demonstracao');

/// Chave da faixa que avisa falha de leitura dos relatos/trechos.
const Key chaveFaixaSemDados = Key('faixa-sem-dados');

/// Ambar da faixa: visivel o bastante para ser lida, discreta o bastante para
/// nao competir com as cores do mapa (verde, vermelho e laranja da paleta).
const Color corFundoFaixaAviso = Color(0xFFFFF3E0);
const Color corTextoFaixaAviso = Color(0xFF5D4037);
const Color corIconeFaixaAviso = Color(0xFF8D6E63);

class FaixaAviso extends StatelessWidget {
  /// Faixa do modo demonstracao: [motivo] e o que o bootstrap registrou.
  FaixaAviso.demonstracao({required MotivoSemFirebase motivo})
      : this(
          key: chaveFaixaDemonstracao,
          icone: Icons.science_outlined,
          texto: 'Modo demonstração: relatos locais, sem backend '
              '(${motivo.rotulo}).',
        );

  /// Faixa de falha de leitura em tempo de execucao: o mapa continua util, mas
  /// os relatos podem estar velhos.
  const FaixaAviso.semDados()
      : this(
          key: chaveFaixaSemDados,
          icone: Icons.cloud_off,
          texto: 'Não foi possível ler os relatos agora: o mapa pode estar '
              'desatualizado.',
        );

  const FaixaAviso({
    super.key,
    required this.icone,
    required this.texto,
  });

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) => Material(
        color: corFundoFaixaAviso,
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(icone, size: 18, color: corIconeFaixaAviso),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texto,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: corTextoFaixaAviso),
                ),
              ),
            ],
          ),
        ),
      );
}
