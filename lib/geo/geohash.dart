/// Geohash (base32) — a "grade" que usamos para consultas por proximidade no
/// Firestore, que nao possui consulta espacial nativa.
///
/// Estrategia (padrao GeoFire): cada documento guarda o geohash do seu ponto;
/// para procurar perto de [p], calculamos a cobertura de celulas que envolve o
/// raio e consultamos por igualdade com `whereIn`, filtrando a distancia exata
/// no cliente.
library;

import 'package:achar_vagas_app/geo/geo_utils.dart';
import 'package:latlong2/latlong.dart';

const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Direcoes usadas ao caminhar entre celulas vizinhas.
enum DirecaoVizinho { norte, sul, leste, oeste }

/// Tabelas do algoritmo classico (geohash-js) para paridade de comprimento par.
const Map<DirecaoVizinho, String> _vizinhosPar = {
  DirecaoVizinho.leste: 'bc01fg45238967deuvhjyznpkmstqrwx',
  DirecaoVizinho.oeste: '238967debc01fg45kmstqrwxuvhjyznp',
  DirecaoVizinho.norte: 'p0r21436x8zb9dcf5h7kjnmqesgutwvy',
  DirecaoVizinho.sul: '14365h7k9dcfesgujnmqp0r2twvyx8zb',
};

const Map<DirecaoVizinho, String> _bordasPar = {
  DirecaoVizinho.leste: 'bcfguvyz',
  DirecaoVizinho.oeste: '0145hjnp',
  DirecaoVizinho.norte: 'prxz',
  DirecaoVizinho.sul: '028b',
};

/// Comprimento impar "transpoe" as direcoes (norte<->leste, sul<->oeste).
const Map<DirecaoVizinho, DirecaoVizinho> _transposta = {
  DirecaoVizinho.leste: DirecaoVizinho.norte,
  DirecaoVizinho.norte: DirecaoVizinho.leste,
  DirecaoVizinho.oeste: DirecaoVizinho.sul,
  DirecaoVizinho.sul: DirecaoVizinho.oeste,
};

String _tabelaVizinhos(DirecaoVizinho d, bool par) =>
    par ? _vizinhosPar[d]! : _vizinhosPar[_transposta[d]!]!;

String _tabelaBordas(DirecaoVizinho d, bool par) =>
    par ? _bordasPar[d]! : _bordasPar[_transposta[d]!]!;

/// Codifica [lat]/[lng] em um geohash de [precisao] caracteres.
String geohashCodificar(double lat, double lng, {int precisao = 9}) {
  if (precisao < 1 || precisao > 12) {
    throw ArgumentError('precisao deve estar entre 1 e 12: $precisao');
  }
  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;
  var alternaLng = true;
  var bit = 0;
  var acumulado = 0;
  final buffer = StringBuffer();

  while (buffer.length < precisao) {
    if (alternaLng) {
      final meio = (lngMin + lngMax) / 2;
      if (lng >= meio) {
        acumulado = (acumulado << 1) | 1;
        lngMin = meio;
      } else {
        acumulado <<= 1;
        lngMax = meio;
      }
    } else {
      final meio = (latMin + latMax) / 2;
      if (lat >= meio) {
        acumulado = (acumulado << 1) | 1;
        latMin = meio;
      } else {
        acumulado <<= 1;
        latMax = meio;
      }
    }
    alternaLng = !alternaLng;
    if (++bit == 5) {
      buffer.write(_base32[acumulado]);
      bit = 0;
      acumulado = 0;
    }
  }
  return buffer.toString();
}

/// Limites e dimensoes aproximadas de uma celula geohash.
class GeoHashCaixa {
  const GeoHashCaixa({
    required this.latMin,
    required this.latMax,
    required this.lngMin,
    required this.lngMax,
  });

  final double latMin;
  final double latMax;
  final double lngMin;
  final double lngMax;

  LatLng get centro => LatLng((latMin + latMax) / 2, (lngMin + lngMax) / 2);

  /// Altura da celula em metros.
  double get alturaM =>
      distanciaM(LatLng(latMin, lngMin), LatLng(latMax, lngMin));

  /// Largura da celula em metros (na latitude do centro).
  double get larguraM => distanciaM(
        LatLng(centro.latitude, lngMin),
        LatLng(centro.latitude, lngMax),
      );
}

/// Limites geograficos da celula [hash].
GeoHashCaixa geohashCaixa(String hash) {
  if (hash.isEmpty) throw ArgumentError('geohash vazio');
  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;
  var alternaLng = true;

  for (final caractere in hash.toLowerCase().split('')) {
    final indice = _base32.indexOf(caractere);
    if (indice < 0) {
      throw ArgumentError('caractere invalido em geohash: $caractere');
    }
    for (var mascara = 16; mascara > 0; mascara >>= 1) {
      final ligado = (indice & mascara) != 0;
      if (alternaLng) {
        final meio = (lngMin + lngMax) / 2;
        if (ligado) {
          lngMin = meio;
        } else {
          lngMax = meio;
        }
      } else {
        final meio = (latMin + latMax) / 2;
        if (ligado) {
          latMin = meio;
        } else {
          latMax = meio;
        }
      }
      alternaLng = !alternaLng;
    }
  }
  return GeoHashCaixa(
    latMin: latMin,
    latMax: latMax,
    lngMin: lngMin,
    lngMax: lngMax,
  );
}

/// Centro geografico da celula [hash].
LatLng geohashCentro(String hash) => geohashCaixa(hash).centro;

/// Celula vizinha de [hash] na [direcao] informada.
///
/// Lanca [ArgumentError] quando o vizinho cairia fora da area coberta pelo
/// geohash (borda do mundo), situacao que quem chama deve tratar.
String geohashVizinho(String hash, DirecaoVizinho direcao) {
  final normalizado = hash.toLowerCase();
  if (normalizado.isEmpty) throw ArgumentError('geohash vazio');

  final par = normalizado.length.isEven;
  final ultimo = normalizado[normalizado.length - 1];
  final indice = _tabelaVizinhos(direcao, par).indexOf(ultimo);
  if (indice < 0) throw ArgumentError('geohash invalido: $hash');

  var base = normalizado.substring(0, normalizado.length - 1);
  if (_tabelaBordas(direcao, par).contains(ultimo)) {
    if (base.isEmpty) {
      throw ArgumentError('vizinho fora da area coberta pelo geohash: $hash');
    }
    base = geohashVizinho(base, direcao);
  }
  return base + _base32[indice];
}

String? _passo(String hash, DirecaoVizinho direcao) {
  try {
    return geohashVizinho(hash, direcao);
  } on ArgumentError {
    return null;
  }
}

/// As 9 celulas de uma vizinhanca (a celula central e as 8 ao redor).
class GeoHashVizinhanca {
  const GeoHashVizinhanca({
    required this.centro,
    this.norte,
    this.sul,
    this.leste,
    this.oeste,
    this.nordeste,
    this.noroeste,
    this.sudeste,
    this.sudoeste,
  });

  final String centro;
  final String? norte;
  final String? sul;
  final String? leste;
  final String? oeste;
  final String? nordeste;
  final String? noroeste;
  final String? sudeste;
  final String? sudoeste;

  /// Todas as celulas existentes, sem repeticao e em ordem estavel.
  List<String> get todas => <String>{
        centro,
        if (norte != null) norte!,
        if (sul != null) sul!,
        if (leste != null) leste!,
        if (oeste != null) oeste!,
        if (nordeste != null) nordeste!,
        if (noroeste != null) noroeste!,
        if (sudeste != null) sudeste!,
        if (sudoeste != null) sudoeste!,
      }.toList()
        ..sort();
}

/// Vizinhanca de 3x3 (celula central + 8 ao redor) de [hash].
GeoHashVizinhanca geohashVizinhanca(String hash) {
  final norte = _passo(hash, DirecaoVizinho.norte);
  final sul = _passo(hash, DirecaoVizinho.sul);
  return GeoHashVizinhanca(
    centro: hash,
    norte: norte,
    sul: sul,
    leste: _passo(hash, DirecaoVizinho.leste),
    oeste: _passo(hash, DirecaoVizinho.oeste),
    nordeste: norte == null ? null : _passo(norte, DirecaoVizinho.leste),
    noroeste: norte == null ? null : _passo(norte, DirecaoVizinho.oeste),
    sudeste: sul == null ? null : _passo(sul, DirecaoVizinho.leste),
    sudoeste: sul == null ? null : _passo(sul, DirecaoVizinho.oeste),
  );
}

/// Celulas de precisao [precisao] que cobrem o disco de [raioM] metros em torno
/// de [centro].
///
/// A quantidade de celulas cresce com o raio; [maxCelulas] existe para evitar
/// consultas grandes (`whereIn` do Firestore aceita no maximo 30 valores).
List<String> geohashCobertura(
  LatLng centro,
  double raioM, {
  int precisao = 6,
  int maxCelulas = 25,
}) {
  if (raioM < 0) throw ArgumentError('raioM nao pode ser negativo');
  final raiz =
      geohashCodificar(centro.latitude, centro.longitude, precisao: precisao);
  final caixa = geohashCaixa(raiz);

  // So expandimos na direcao em que o raio ultrapassa a borda da celula.
  // Isso mantem a consulta correta e evita consultar 9 celulas a toa.
  final passosNorte = _passos(
    raioM,
    distanciaM(centro, LatLng(caixa.latMax, centro.longitude)),
    caixa.alturaM,
  );
  final passosSul = _passos(
    raioM,
    distanciaM(centro, LatLng(caixa.latMin, centro.longitude)),
    caixa.alturaM,
  );
  final passosLeste = _passos(
    raioM,
    distanciaM(centro, LatLng(centro.latitude, caixa.lngMax)),
    caixa.larguraM,
  );
  final passosOeste = _passos(
    raioM,
    distanciaM(centro, LatLng(centro.latitude, caixa.lngMin)),
    caixa.larguraM,
  );

  final total =
      (passosNorte + passosSul + 1) * (passosLeste + passosOeste + 1);
  if (total > maxCelulas) {
    throw ArgumentError(
      'Cobertura de $total celulas excede maxCelulas=$maxCelulas; '
      'reduza o raio ou use uma precisao menor.',
    );
  }

  final colunas = <String>[];
  var atual = raiz;
  final oeste = <String>[];
  for (var i = 0; i < passosOeste; i++) {
    final vizinho = _passo(atual, DirecaoVizinho.oeste);
    if (vizinho == null) break;
    oeste.add(vizinho);
    atual = vizinho;
  }
  atual = raiz;
  final leste = <String>[];
  for (var i = 0; i < passosLeste; i++) {
    final vizinho = _passo(atual, DirecaoVizinho.leste);
    if (vizinho == null) break;
    leste.add(vizinho);
    atual = vizinho;
  }
  colunas
    ..addAll(oeste.reversed)
    ..add(raiz)
    ..addAll(leste);

  final celulas = <String>{};
  for (final coluna in colunas) {
    celulas.add(coluna);
    var norteAtual = coluna;
    for (var i = 0; i < passosNorte; i++) {
      final vizinho = _passo(norteAtual, DirecaoVizinho.norte);
      if (vizinho == null) break;
      celulas.add(vizinho);
      norteAtual = vizinho;
    }
    var sulAtual = coluna;
    for (var i = 0; i < passosSul; i++) {
      final vizinho = _passo(sulAtual, DirecaoVizinho.sul);
      if (vizinho == null) break;
      celulas.add(vizinho);
      sulAtual = vizinho;
    }
  }
  return celulas.toList()..sort();
}

/// Quantas celulas a mais sao necessarias naquela direcao: zero enquanto o raio
/// couber dentro da borda, senao o excedente dividido pelo tamanho da celula.
int _passos(double raioM, double ateBordaM, double tamanhoCelulaM) {
  final excedente = raioM - ateBordaM;
  if (excedente <= 0 || tamanhoCelulaM <= 0) return 0;
  return (excedente / tamanhoCelulaM).ceil().clamp(0, 8);
}
