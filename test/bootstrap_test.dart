import 'package:achar_vagas_app/ambiente.dart';
import 'package:achar_vagas_app/bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bootstrap do Firebase (issue #29): sem `firebase_options` preenchido o app
/// cai no modo demonstracao, mas com o motivo registrado para a tela avisar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sem firebase_options o bootstrap explica o modo demonstracao',
      () async {
    final boot = await bootstrapFirebase();

    expect(boot.usingFirebase, isFalse);
    expect(boot.motivoSemFirebase, MotivoSemFirebase.naoConfigurado);
    expect(boot.uid, isEmpty);
  });

  test('os construtores mantem modo e motivo coerentes', () {
    const firebase = FirebaseBootstrap.firebase('uid-123');
    expect(firebase.usingFirebase, isTrue);
    expect(firebase.motivoSemFirebase, isNull);

    const demonstracao =
        FirebaseBootstrap.demonstracao(MotivoSemFirebase.autenticacaoFalhou);
    expect(demonstracao.usingFirebase, isFalse);
    expect(
      demonstracao.motivoSemFirebase,
      MotivoSemFirebase.autenticacaoFalhou,
    );
  });

  test('cada motivo tem o rotulo que a faixa mostra', () {
    expect(MotivoSemFirebase.naoConfigurado.rotulo, 'Firebase não configurado');
    expect(MotivoSemFirebase.semConexao.rotulo, 'não foi possível conectar');
    expect(
      MotivoSemFirebase.autenticacaoFalhou.rotulo,
      'falha no login anônimo',
    );
  });
}
