import 'package:achar_vagas_app/main.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/tiles_falsos.dart';

void main() {
  testWidgets('abre a tela inicial com o mapa em modo demonstracao',
      (tester) async {
    // Sem `ambiente` informado o app usa os repositorios em memoria, semeados
    // com os trechos reais do centro de Campo Mourao (nenhuma rede).
    await tester.pumpWidget(AcharVagasApp(tileProvider: TilesFalsos()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Achar vagas'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Relatar o que você vê nesta via'), findsOneWidget);
  });
}
