import 'package:achar_vagas_app/services/rota.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// rota ate o trecho: uri gerada para um ponto conhecido, sem abrir app.
void main() {
  const ponto = LatLng(-24.0430793, -52.3772141);
  const coordenadas = '-24.0430793,-52.3772141';

  test('android usa o esquema geo: com o rótulo entre parênteses', () {
    final uri = uriRota(ponto, rotulo: 'Rua São Paulo', android: true);

    expect(uri.scheme, 'geo');
    expect(uri.path, coordenadas);
    expect(uri.queryParameters['q'], '$coordenadas(Rua São Paulo)');
    // geo: espera texto codificado; nada de espaço cru na uri.
    expect(uri.toString(), isNot(contains(' ')));
  });

  test('android sem rótulo manda só as coordenadas', () {
    final uri = uriRota(ponto, android: true);

    expect(uri.queryParameters['q'], coordenadas);
    expect(uri.toString(), isNot(contains('(')));
  });

  test('rótulo em branco não vira parênteses vazio', () {
    final uri = uriRota(ponto, rotulo: '   ', android: true);

    expect(uri.queryParameters['q'], coordenadas);
  });

  test('web e desktop usam a URL universal do google maps', () {
    final uri = uriRota(ponto, rotulo: 'Rua São Paulo', android: false);

    expect(
      uri.toString(),
      'https://www.google.com/maps/dir/?api=1&destination=$coordenadas',
    );
  });
}
