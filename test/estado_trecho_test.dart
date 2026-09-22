import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Regra de cor do mapa (issue #13): o relato mais recente define o estado e
/// relato mais antigo que [validadeRelatoPadrao] e ignorado.
void main() {
  const pontoCentral = LatLng(-24.0430793, -52.3772141);
  const uuid = 'c1d70afe-a7de-4b73-a41c-e92526ab72f9';
  const idCanonico = 'gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9';
  final agora = DateTime.utc(2026, 9, 21, 12);

  Relato relato(
    TipoRelato tipo,
    Duration atras, {
    String trecho = 'gh:6gdz0ph',
    String uid = 'u1',
    DateTime? quando,
  }) =>
      Relato.novo(
        uid: uid,
        trechoId: TrechoId.parse(trecho),
        tipo: tipo,
        ponto: pontoCentral,
        criadoEm: quando ?? agora.subtract(atras),
      );

  test('validadeRelatoPadrao e de 20 minutos', () {
    expect(validadeRelatoPadrao, const Duration(minutes: 20));
  });

  group('resumoDe', () {
    test('sem relato o trecho fica desconhecido', () {
      final resumo = resumoDe(const <Relato>[]);

      expect(resumo.estado, EstadoTrecho.desconhecido);
      expect(resumo.temRelato, isFalse);
      expect(resumo.total, 0);
    });

    test('o relato mais recente define o estado', () {
      final resumo = resumoDe(<Relato>[
        relato(TipoRelato.vaga, const Duration(minutes: 12)),
        relato(TipoRelato.lotado, const Duration(minutes: 1), uid: 'u2'),
        relato(TipoRelato.saindo, const Duration(minutes: 4), uid: 'u3'),
      ]);

      expect(resumo.estado, EstadoTrecho.lotado);
      expect(resumo.total, 3);
      expect(resumo.vagas, 1);
      expect(resumo.lotados, 1);
      expect(resumo.saindo, 1);
      expect(resumo.atualizadoEm, agora.subtract(const Duration(minutes: 1)));
    });

    test('empate de horario e desempatado pela ordem do enum', () {
      final mesmoHorario = agora.subtract(const Duration(minutes: 3));

      final vagaPrimeiro = resumoDe(<Relato>[
        relato(TipoRelato.vaga, Duration.zero, quando: mesmoHorario),
        relato(TipoRelato.saindo, Duration.zero, uid: 'u2', quando: mesmoHorario),
      ]);
      final saindoPrimeiro = resumoDe(<Relato>[
        relato(TipoRelato.saindo, Duration.zero, quando: mesmoHorario),
        relato(TipoRelato.vaga, Duration.zero, uid: 'u2', quando: mesmoHorario),
      ]);

      expect(vagaPrimeiro.estado, EstadoTrecho.vaga);
      expect(saindoPrimeiro.estado, EstadoTrecho.vaga);
    });
  });

  group('agregarPorTrecho', () {
    test('agrupa por trecho e separa os estados', () {
      final resumo = agregarPorTrecho(
        <Relato>[
          relato(TipoRelato.vaga, const Duration(minutes: 5)),
          relato(TipoRelato.saindo, const Duration(minutes: 2), uid: 'u2'),
          relato(TipoRelato.lotado, const Duration(minutes: 1),
              uid: 'u3', trecho: idCanonico),
        ],
        agora: agora,
        validade: validadeRelatoPadrao,
      );

      expect(resumo, hasLength(2));
      expect(resumo['gh:6gdz0ph']!.estado, EstadoTrecho.saindo);
      expect(resumo['gh:6gdz0ph']!.total, 2);
      expect(resumo['gh:6gdz0ph']!.vagas, 1);
      expect(resumo[idCanonico]!.estado, EstadoTrecho.lotado);
      expect(resumo[idCanonico]!.total, 1);
    });

    test('ignora relato mais antigo que a validade', () {
      final vencido = agora.subtract(const Duration(minutes: 21));
      final resumo = agregarPorTrecho(
        <Relato>[
          relato(TipoRelato.vaga, Duration.zero, quando: vencido),
          relato(TipoRelato.lotado, const Duration(minutes: 5), uid: 'u2'),
        ],
        agora: agora,
        validade: validadeRelatoPadrao,
      );

      expect(resumo['gh:6gdz0ph']!.estado, EstadoTrecho.lotado);
      expect(resumo['gh:6gdz0ph']!.total, 1);
    });

    test('trecho sem relato valido nao entra no agregado', () {
      final resumo = agregarPorTrecho(
        <Relato>[relato(TipoRelato.vaga, const Duration(minutes: 30))],
        agora: agora,
        validade: validadeRelatoPadrao,
      );

      expect(resumo, isEmpty);
    });

    test('no limite exato da validade o relato ainda vale', () {
      final noLimite = agora.subtract(validadeRelatoPadrao);
      final resumo = agregarPorTrecho(
        <Relato>[relato(TipoRelato.vaga, Duration.zero, quando: noLimite)],
        agora: agora,
        validade: validadeRelatoPadrao,
      );

      expect(resumo['gh:6gdz0ph']!.estado, EstadoTrecho.vaga);
    });

    test('mantem a chave do trecho canonico intacta', () {
      expect(TrechoId.parse(idCanonico).valor, idCanonico);
      expect(uuid.length, 36);
    });
  });
}
