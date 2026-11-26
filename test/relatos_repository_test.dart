import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/geo_utils.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:achar_vagas_app/services/relatos_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// consulta de relatos no firestore falso: janela, ordem e limite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ponto = LatLng(-24.0430793, -52.3772141);
  const idTrecho = 'gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9';

  /// a consulta mede o agora pelo relogio do aparelho.
  final agora = DateTime.now().toUtc();

  late FakeFirebaseFirestore firestore;
  late RelatosFirestore repositorio;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repositorio = RelatosFirestore(firestore: firestore);
  });

  /// grava como o app grava, sem passar pelas regras.
  Future<void> semear({
    required DateTime criadoEm,
    required String trecho,
    LatLng local = ponto,
    TipoRelato tipo = TipoRelato.vaga,
    String? celula,
    String id = '',
  }) async {
    final colecao = firestore.collection(RelatosFirestore.colecao);
    final referencia = id.isEmpty ? colecao.doc() : colecao.doc(id);
    await referencia.set(<String, dynamic>{
      'uid': 'u1',
      'trechoId': trecho,
      'tipo': tipo.valor,
      'geo': <String, dynamic>{
        'geopoint': GeoPoint(local.latitude, local.longitude),
        'geohash': geohashCodificar(
          local.latitude,
          local.longitude,
          precisao: 9,
        ),
        'geohashConsulta': celula ??
            geohashCodificar(
              local.latitude,
              local.longitude,
              precisao: precisaoGeohashConsulta,
            ),
      },
      'criadoEm': Timestamp.fromDate(criadoEm),
      'expiraEm': Timestamp.fromDate(criadoEm.add(validadeRelatoPadrao)),
    });
  }

  test('inicioJanelaRelatos cobre a validade com a folga de relogio', () {
    expect(
      inicioJanelaRelatos(agora),
      agora.subtract(validadeRelatoPadrao + margemJanelaRelatos),
    );
  });

  test('criar grava o geohash de consulta e o expiraEm do relato', () async {
    final salvo = await repositorio.criar(
      Relato.novo(
        uid: 'u1',
        trechoId: TrechoId.parse(idTrecho),
        tipo: TipoRelato.vaga,
        ponto: ponto,
      ),
    );

    final dados = (await firestore
            .collection(RelatosFirestore.colecao)
            .doc(salvo.id)
            .get())
        .data()!;

    expect(dados['uid'], 'u1');
    expect(dados['trechoId'], idTrecho);
    expect(dados['tipo'], 'vaga');
    expect(
      (dados['geo'] as Map<String, dynamic>)['geohashConsulta'],
      hasLength(precisaoGeohashConsulta),
    );

    // expiraEm e criadoEm mais a validade.
    final criadoEm = dados['criadoEm'] as Timestamp;
    final expiraEm = dados['expiraEm'] as Timestamp;
    expect(
      expiraEm.toDate().difference(criadoEm.toDate()).inSeconds,
      closeTo(validadeRelatoPadrao.inSeconds, 1),
    );
  });

  test('limite cheio de relatos antigos nao esconde o relato novo', () async {
    // 300 antigos do mesmo geohash: sem janela e ordem, tomariam o limite.
    for (var i = 0; i < 300; i++) {
      await semear(
        criadoEm: agora.subtract(Duration(minutes: 30 + i)),
        trecho: idTrecho,
        id: 'antigo_$i',
      );
    }
    await semear(
      criadoEm: agora,
      trecho: idTrecho,
      tipo: TipoRelato.lotado,
      id: 'novo',
    );

    final encontrados = await repositorio.buscarProximos(ponto, limite: 5);

    expect(encontrados, hasLength(1));
    expect(encontrados.single.id, 'novo');
    expect(encontrados.single.tipo, TipoRelato.lotado);

    // o trecho continua pintado pelo relato novo.
    final estados = agregarPorTrecho(
      encontrados,
      agora: agora,
      validade: validadeRelatoPadrao,
    );
    expect(estados[idTrecho]?.estado, EstadoTrecho.lotado);
  });

  test('relato fora da janela de validade nao volta da consulta', () async {
    await semear(
      criadoEm: agora.subtract(const Duration(minutes: 45)),
      trecho: idTrecho,
      id: 'vencido',
    );
    await semear(criadoEm: agora, trecho: idTrecho, id: 'valido');

    final encontrados = await repositorio.buscarProximos(ponto);

    expect(encontrados.map((relato) => relato.id), <String>['valido']);
  });

  test('a consulta devolve do mais recente para o mais antigo', () async {
    await semear(
      criadoEm: agora.subtract(const Duration(minutes: 10)),
      trecho: idTrecho,
      id: 'dez_minutos',
    );
    await semear(criadoEm: agora, trecho: idTrecho, id: 'agora');

    final encontrados = await repositorio.buscarProximos(ponto);

    expect(
      encontrados.map((relato) => relato.id),
      <String>['agora', 'dez_minutos'],
    );
  });

  test('o filtro fino de distancia continua no cliente', () async {
    // a celula cobre mais que o raio; quem descarta e o filtro do cliente.
    final celula = geohashCodificar(
      ponto.latitude,
      ponto.longitude,
      precisao: precisaoGeohashConsulta,
    );
    await semear(
      criadoEm: agora,
      trecho: idTrecho,
      local: deslocarM(ponto, 400, 90),
      celula: celula,
    );

    final encontrados = await repositorio.buscarProximos(ponto, raioM: 100);

    expect(encontrados, isEmpty);
  });
}
