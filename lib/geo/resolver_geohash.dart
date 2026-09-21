/// Fallback universal do resolvedor de trecho.
///
/// Nao depende de rede, chave de API, base importada ou cobertura de dados:
/// sempre devolve uma area aproximada (geohash de ~150 m). E o que garante que
/// o app funcione em **qualquer centro urbano de qualquer cidade**, mesmo onde
/// a pipeline ainda nao importou a malha viaria.
///
/// Limitacao assumida (documentada no ADR): a area nao tem nome de rua nem
/// geometria, portanto o mapa mostra um circulo em vez de uma linha.
library;

import 'package:achar_vagas_app/geo/trecho_resolver.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:latlong2/latlong.dart';

class ResolverGeohash implements TrechoResolver {
  const ResolverGeohash();

  @override
  String get nome => 'geohash';

  @override
  Future<Trecho?> resolver(LatLng ponto) async => Trecho.aproximado(ponto);
}
