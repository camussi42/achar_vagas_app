/// Resolucao de "em qual trecho de rua o usuario esta".
///
/// O app nunca mantem malha viaria propria: cada resolvedor consulta uma base
/// global (Overture/GERS) ou cai para uma area aproximada (geohash). A cascata
/// garante que **sempre** exista um trecho, mesmo em ruas que ainda nao foram
/// importadas para o Firestore.
library;

import 'package:achar_vagas_app/models/trecho.dart';
import 'package:latlong2/latlong.dart';

abstract class TrechoResolver {
  /// Identificacao do resolvedor (aparece em logs/diagnostico).
  String get nome;

  /// Devolve o trecho para [ponto] ou `null` quando este resolvedor nao sabe
  /// responder (quem chama decide qual e o proximo).
  Future<Trecho?> resolver(LatLng ponto);
}

/// Tenta os resolvedores na ordem em que foram informados.
///
/// Um erro em um resolvedor nao interrompe o fluxo: a cascata apenas segue para
/// o proximo, garantindo degradacao suave do canônico para o aproximado.
class TrechoResolverCascata implements TrechoResolver {
  TrechoResolverCascata(this._resolvedores);

  final List<TrechoResolver> _resolvedores;

  /// Nomes dos resolvedores na ordem de tentativa.
  List<String> get ordem => _resolvedores.map((r) => r.nome).toList();

  @override
  String get nome => ordem.join(' > ');

  @override
  Future<Trecho?> resolver(LatLng ponto) async {
    for (final resolvedor in _resolvedores) {
      try {
        final trecho = await resolvedor.resolver(ponto);
        if (trecho != null) return trecho;
      } catch (_) {
        // Sem chave/API/rede: segue para o proximo resolvedor.
        continue;
      }
    }
    return null;
  }
}
