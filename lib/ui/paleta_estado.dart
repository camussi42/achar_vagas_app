/// Cores do estado de um trecho no mapa (issue #13).
///
/// Verde = tem vaga, vermelho = lotado, laranja = liberando vaga e neutro =
/// sem relato recente. O neutro so aparece na legenda: trecho sem relato nao e
/// pintado no mapa.
library;

import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:flutter/material.dart';

const Color corVaga = Color(0xFF2E7D32);
const Color corLotado = Color(0xFFC62828);
const Color corSaindo = Color(0xFFEF6C00);
const Color corNeutro = Color(0xFF90A4AE);

/// Cor de pintura do trecho conforme o estado agregado.
Color corDeEstado(EstadoTrecho estado) => switch (estado) {
      EstadoTrecho.vaga => corVaga,
      EstadoTrecho.lotado => corLotado,
      EstadoTrecho.saindo => corSaindo,
      EstadoTrecho.desconhecido => corNeutro,
    };

/// Mesma cor do estado equivalente, para os botoes de relato.
Color corDeTipo(TipoRelato tipo) => switch (tipo) {
      TipoRelato.vaga => corVaga,
      TipoRelato.lotado => corLotado,
      TipoRelato.saindo => corSaindo,
    };
