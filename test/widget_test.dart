import 'package:achar_vagas_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('abre tela inicial', (tester) async {
    await tester.pumpWidget(const AcharVagasApp());
    expect(find.text('Achar vagas'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsOneWidget);
  });
}
