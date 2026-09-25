/// O que o mapa deve pintar para cada trecho que tem relato recente (#13).
///
/// Regras, explicitas para serem testaveis:
/// 1. trecho canonico (`gers:`) com geometria carregada -> linha (polyline);
/// 2. trecho canonico sem geometria no raio consultado -> circulo pequeno no
///    ponto do relato mais recente (o app nao inventa geometria);
/// 3. fallback geohash (`gh:`) -> circulo no centro da celula, com o raio da
///    menor dimensao dela: a identidade do fallback e a *area*, nao a rua;
/// 4. trecho sem relato valido nao e desenhado (o neutro fica na legenda).
///
/// Nao depende de widget algum: recebe dados e devolve o que pintar, o que
/// permite testar a regra sem montar o mapa.
library;

import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:latlong2/latlong.dart';

/// Raio (m) do circulo usado quando o trecho canonico nao tem geometria.
const double raioSemGeometriaM = 30;

/// Trecho pronto para desenhar: estado, geometria e area de fallback.
class TrechoEstado {
  const TrechoEstado({
    required this.id,
    required this.resumo,
    required this.centro,
    this.via,
    this.linha = const <LatLng>[],
    this.raioM = 0,
  });

  final TrechoId id;
  final ResumoEstado resumo;

  /// Nome da via quando o trecho e canonico (nulo no fallback).
  final String? via;

  /// Vertices do trecho. Vazio -> desenhar circulo em [centro] com [raioM].
  final List<LatLng> linha;

  /// Centro do circulo (fallback/geometria desconhecida) ou centroide da linha.
  final LatLng centro;

  /// Raio do circulo, em metros (zero quando ha linha).
  final double raioM;

  EstadoTrecho get estado => resumo.estado;

  bool get temLinha => linha.length >= 2;

  /// Rotulo do trecho para a interface (nome da via ou area aproximada).
  String get rotulo {
    if (via != null && via!.isNotEmpty) return via!;
    if (id.canonico) return 'Via sem nome';
    return 'Área aproximada (~${raioM.round()} m)';
  }

  @override
  String toString() =>
      'TrechoEstado(${id.valor}, ${estado.rotulo}, linha: ${linha.length})';
}

/// Monta as camadas do mapa a partir dos trechos conhecidos, dos estados
/// agregados por trecho e do ponto do relato mais recente de cada trecho.
///
/// A ordem da saida e estavel (por id) para o desenho nao "tremer" entre
/// rebuilds.
List<TrechoEstado> combinar({
  required Iterable<Trecho> trechos,
  required Map<String, ResumoEstado> estados,
  required Map<String, LatLng> pontos,
}) {
  final porId = <String, Trecho>{
    for (final trecho in trechos) trecho.id.valor: trecho,
  };

  final camadas = <TrechoEstado>[];
  final chaves = estados.keys.toList()..sort();
  for (final chave in chaves) {
    final resumo = estados[chave];
    final id = TrechoId.tentarParse(chave);
    if (resumo == null || id == null) continue;

    final canonico = porId[chave];
    if (canonico != null && canonico.temGeometria) {
      camadas.add(
        TrechoEstado(
          id: id,
          resumo: resumo,
          via: canonico.via,
          linha: canonico.geometria,
          centro: canonico.centroide,
        ),
      );
      continue;
    }

    if (id.canonico) {
      // Trecho canonico sem geometria carregada: marca o ponto relatado.
      final ponto = pontos[chave];
      if (ponto == null) continue;
      camadas.add(
        TrechoEstado(
          id: id,
          resumo: resumo,
          via: canonico?.via,
          centro: ponto,
          raioM: raioSemGeometriaM,
        ),
      );
      continue;
    }

    // Fallback geohash: mesmo centro para todos os relatos da mesma celula.
    final caixa = _caixaSegura(id.chave);
    if (caixa == null) continue;
    camadas.add(
      TrechoEstado(
        id: id,
        resumo: resumo,
        centro: caixa.centro,
        raioM: _raioDaCelulaM(caixa),
      ),
    );
  }
  return camadas;
}

/// Ponto do relato mais recente de cada trecho que ainda vale em [agora].
Map<String, LatLng> pontosMaisRecentes(
  Iterable<Relato> relatos, {
  required DateTime agora,
  required Duration validade,
}) {
  final pontos = <String, LatLng>{};
  final horarios = <String, DateTime>{};
  for (final relato in relatos) {
    if (!relato.validoEm(agora, validade)) continue;
    final chave = relato.trechoId.valor;
    final anterior = horarios[chave];
    if (anterior == null || relato.criadoEm.isAfter(anterior)) {
      horarios[chave] = relato.criadoEm;
      pontos[chave] = relato.ponto;
    }
  }
  return pontos;
}

/// primeiro id tocado que o mapa conhece; ids desconhecidos sao ignorados.
TrechoEstado? trechoTocado(
  Iterable<TrechoEstado> camadas,
  Iterable<String> valoresTocados,
) {
  final porValor = <String, TrechoEstado>{
    for (final camada in camadas) camada.id.valor: camada,
  };
  for (final valor in valoresTocados) {
    final camada = porValor[valor];
    if (camada != null) return camada;
  }
  return null;
}

/// Meio da menor dimensao da celula (o circulo fica dentro dela).
double _raioDaCelulaM(GeoHashCaixa caixa) {
  final menor = caixa.alturaM < caixa.larguraM ? caixa.alturaM : caixa.larguraM;
  return menor / 2;
}

/// [geohashCaixa] aceita so o alfabeto base32; o regex de `TrechoId` e mais
/// permissivo (aceita a, i, l, o), entao um id fora do padrao e ignorado em vez
/// de derrubar o mapa.
GeoHashCaixa? _caixaSegura(String hash) {
  try {
    return geohashCaixa(hash);
  } on ArgumentError {
    return null;
  }
}
