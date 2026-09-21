/// Identidade global de trecho de rua.
///
/// O app NAO mantem geometria propria: o trecho e sempre uma referencia a uma
/// base global de vias. Duas origens sao aceitas:
///
/// - `gers:<id>`    -> segmento do Overture Maps (id GERS, estavel entre
///   releases). O id aparece em duas formas conforme a versao do schema:
///
///   * v2 (atual): UUID, ex. `c1d70afe-a7de-4b73-a41c-e92526ab72f9`
///   * v1 (legado): 32 hexadecimais, ex. `08628d5437ffffff0473ffc36df547db`
///
///   Quando o segmento e cortado nos conectores (um lado de quadra), a faixa
///   linear entra na chave: `gers:<id>@<start_lr>:<end_lr>`. A precisao de 4
///   casas equivale a menos de 2 m em segmentos de ate 20 km.
/// - `gh:<geohash>` -> fallback universal, quando ainda nao ha malha conhecida
///   para aquele ponto (funciona em qualquer lugar do planeta).
///
/// O formato e validado tambem em `firestore.rules`; manter os dois em sincronia
/// e o que garante que nenhum cliente grave um id inventado.
library;

enum ProvedorTrecho {
  /// Segmento do Overture Maps (id GERS).
  overture,

  /// Celula geohash (fallback universal).
  geohash,
}

class TrechoId {
  TrechoId._(this.provedor, this.chave, {this.inicioLr, this.fimLr});

  /// Trecho de rua vindo do Overture Maps.
  ///
  /// [inicioLr] e [fimLr] sao as posicoes lineares (0.0-1.0) quando o segmento
  /// foi cortado nos conectores (equivale a um lado de quadra).
  factory TrechoId.overture(String gersId, {double? inicioLr, double? fimLr}) {
    final normalizado = gersId.toLowerCase();
    if (!_idGersValido.hasMatch(normalizado)) {
      throw FormatException('Id GERS invalido: $gersId');
    }
    final temInicio = inicioLr != null;
    final temFim = fimLr != null;
    if (temInicio != temFim) {
      throw ArgumentError('inicioLr e fimLr devem ser informados juntos');
    }
    return TrechoId._(
      ProvedorTrecho.overture,
      normalizado,
      inicioLr: temInicio ? _normalizarLr(inicioLr) : null,
      fimLr: temFim ? _normalizarLr(fimLr) : null,
    );
  }

  /// Fallback: identifica a area por geohash quando nao ha trecho canonico.
  factory TrechoId.geohash(String hash) {
    final normalizado = hash.toLowerCase();
    if (!RegExp(r'^[0-9a-z]{6,9}$').hasMatch(normalizado)) {
      throw FormatException('Geohash invalido para trecho: $hash');
    }
    return TrechoId._(ProvedorTrecho.geohash, normalizado);
  }

  /// Tentativa de leitura que devolve `null` em vez de lancar excecao.
  static TrechoId? tentarParse(String? valor) {
    if (valor == null || valor.isEmpty) return null;
    if (!_formatoValido.hasMatch(valor)) return null;
    if (valor.startsWith('gh:')) return TrechoId.geohash(valor.substring(3));

    final semPrefixo = valor.substring(5);
    final partes = semPrefixo.split('@');
    if (partes.length == 1) return TrechoId.overture(partes.first);
    final faixa = partes[1].split(':');
    return TrechoId.overture(
      partes.first,
      inicioLr: double.parse(faixa[0]),
      fimLr: double.parse(faixa[1]),
    );
  }

  /// Leitura estrita, usada ao desserializar dados ja validados.
  static TrechoId parse(String valor) {
    final id = tentarParse(valor);
    if (id == null) throw FormatException('trechoId invalido: $valor');
    return id;
  }

  /// Id GERS nas duas formas ja publicadas pelo Overture: UUID (v2) e 32 hex (v1).
  static final RegExp _idGersValido = RegExp(
    r'^([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
  );

  /// Formato completo de `trechoId`. Este MESMO texto aparece em
  /// `firestore.rules` — os testes de contrato comparam os dois.
  static final RegExp _formatoValido = RegExp(
    r'^(gers:([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'
    r'(@[0-9.]+:[0-9.]+)?|gh:[0-9a-z]{6,9})$',
  );

  /// Expressao regular equivalente a de `firestore.rules` (fonte unica de
  /// verdade usada nos testes de contrato).
  static String get padraoRegex => _formatoValido.pattern;

  final ProvedorTrecho provedor;

  /// Id GERS (sem prefixo) ou geohash, conforme o [provedor].
  final String chave;

  /// Inicio da faixa linear no segmento original (somente Overture).
  final double? inicioLr;

  /// Fim da faixa linear no segmento original (somente Overture).
  final double? fimLr;

  bool get canonico => provedor == ProvedorTrecho.overture;

  /// Id GERS quando o trecho vem do Overture.
  String? get gersId => canonico ? chave : null;

  /// Geohash quando o trecho e um fallback.
  String? get geohash => canonico ? null : chave;

  /// `true` quando o segmento foi recortado em um lado de quadra.
  bool get dividido => inicioLr != null && fimLr != null;

  /// Representacao canonica gravada no Firestore.
  String get valor {
    if (!canonico) return 'gh:$chave';
    if (!dividido) return 'gers:$chave';
    return 'gers:$chave@${inicioLr!.toStringAsFixed(4)}:${fimLr!.toStringAsFixed(4)}';
  }

  static double _normalizarLr(double v) {
    if (v.isNaN || v < 0 || v > 1) {
      throw ArgumentError('Posicao linear fora de 0..1: $v');
    }
    final arredondado = double.parse(v.toStringAsFixed(4));
    return arredondado;
  }

  @override
  String toString() => valor;

  @override
  bool operator ==(Object other) =>
      other is TrechoId &&
      other.provedor == provedor &&
      other.chave == chave &&
      other.inicioLr == inicioLr &&
      other.fimLr == fimLr;

  @override
  int get hashCode => Object.hash(provedor, chave, inicioLr, fimLr);
}
