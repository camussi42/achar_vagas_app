import 'package:achar_vagas_app/ambiente.dart';
import 'package:achar_vagas_app/bootstrap.dart';
import 'package:achar_vagas_app/ui/tela_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final boot = await bootstrapFirebase();
  runApp(
    AcharVagasApp(
      ambiente: boot.usingFirebase
          ? AmbienteApp.firebase(uid: boot.uid)
          // O motivo vem do bootstrap: a faixa do topo do mapa mostra ele (#29).
          : AmbienteApp.demonstracao(
              motivo: boot.motivoSemFirebase ??
                  MotivoSemFirebase.naoConfigurado,
            ),
    ),
  );
}

class AcharVagasApp extends StatelessWidget {
  /// Sem [ambiente] informado o app roda em modo demonstracao: repositorios em
  /// memoria, semeados com os trechos reais do centro de Campo Mourao.
  AcharVagasApp({super.key, AmbienteApp? ambiente, this.tileProvider})
      : ambiente = ambiente ?? AmbienteApp.demonstracao();

  final AmbienteApp ambiente;

  /// Provider de tiles alternativo (testes de widget, sem rede).
  final TileProvider? tileProvider;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Achar vagas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: TelaMapa(ambiente: ambiente, tileProvider: tileProvider),
    );
  }
}
