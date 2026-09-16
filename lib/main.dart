import 'package:achar_vagas_app/bootstrap.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final boot = await bootstrapFirebase();
  runApp(AcharVagasApp(usingFirebase: boot.usingFirebase, uid: boot.uid));
}

class AcharVagasApp extends StatelessWidget {
  const AcharVagasApp({
    super.key,
    this.usingFirebase = false,
    this.uid = '',
  });

  final bool usingFirebase;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Achar vagas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Achar vagas')),
        body: Center(
          child: Text(
            usingFirebase
                ? 'Firebase ao vivo\nUID: $uid'
                : 'Firebase ainda não configurado\n(Auth anônimo após flutterfire configure)',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
