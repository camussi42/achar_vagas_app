import 'package:flutter/material.dart';

void main() {
  runApp(const AcharVagasApp());
}

class AcharVagasApp extends StatelessWidget {
  const AcharVagasApp({super.key});

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
        body: const Center(
          child: Text('Projeto inicial'),
        ),
      ),
    );
  }
}
