/// Agregacao dos relatos em um "estado" por trecho (a cor do mapa).
///
/// Regra adotada (explicita e testavel):
/// 1. relatos vencidos (mais antigos que a validade) sao ignorados;
/// 2. o relato **mais recente** define o estado do trecho;
/// 3. empate de horario e desempatado pela ordem do enum, para o resultado ser
///    deterministico.
///
/// Nao existe agregado no servidor: o calculo e feito no cliente a partir dos
/// relatos recentes do raio consultado. Isso evita depender de Cloud Functions
/// (que nao fazem parte do ambiente do projeto) e mantem o custo baixo.
library;

import 'package:achar_vagas_app/models/relato.dart';

// validadeRelatoPadrao mora em models/relato.dart; aqui o prazo chega por parametro.

enum EstadoTrecho { vaga, lotado, saindo, desconhecido }

extension EstadoTrechoTexto on EstadoTrecho {
  String get rotulo => switch (this) {
        EstadoTrecho.vaga => 'Com vaga',
        EstadoTrecho.lotado => 'Lotado',
        EstadoTrecho.saindo => 'Liberando vaga',
        EstadoTrecho.desconhecido => 'Sem relato',
      };
}

/// Resumo de um trecho: estado atual e contagem de relatos validos.
class ResumoEstado {
  const ResumoEstado({
    required this.estado,
    this.total = 0,
    this.vagas = 0,
    this.lotados = 0,
    this.saindo = 0,
    this.atualizadoEm,
  });

  const ResumoEstado.desconhecido() : this(estado: EstadoTrecho.desconhecido);

  final EstadoTrecho estado;
  final int total;
  final int vagas;
  final int lotados;
  final int saindo;
  final DateTime? atualizadoEm;

  bool get temRelato => total > 0;

  @override
  String toString() => 'ResumoEstado(${estado.rotulo}, total: $total)';
}

/// Estado de um conjunto de relatos do **mesmo** trecho (ordem livre).
ResumoEstado resumoDe(Iterable<Relato> relatos) {
  final lista = relatos.toList(growable: false);
  if (lista.isEmpty) return const ResumoEstado.desconhecido();

  final ordenados = [...lista]..sort((a, b) {
      final porData = b.criadoEm.compareTo(a.criadoEm);
      if (porData != 0) return porData;
      return a.tipo.index.compareTo(b.tipo.index);
    });
  final maisRecente = ordenados.first;

  return ResumoEstado(
    estado: switch (maisRecente.tipo) {
      TipoRelato.vaga => EstadoTrecho.vaga,
      TipoRelato.lotado => EstadoTrecho.lotado,
      TipoRelato.saindo => EstadoTrecho.saindo,
    },
    total: lista.length,
    vagas: lista.where((r) => r.tipo == TipoRelato.vaga).length,
    lotados: lista.where((r) => r.tipo == TipoRelato.lotado).length,
    saindo: lista.where((r) => r.tipo == TipoRelato.saindo).length,
    atualizadoEm: maisRecente.criadoEm,
  );
}

/// Agrupa [relatos] por trecho, descartando os que ja venceram.
Map<String, ResumoEstado> agregarPorTrecho(
  Iterable<Relato> relatos, {
  required DateTime agora,
  required Duration validade,
}) {
  final porTrecho = <String, List<Relato>>{};
  for (final relato in relatos) {
    if (!relato.validoEm(agora, validade)) continue;
    porTrecho.putIfAbsent(relato.trechoId.valor, () => []).add(relato);
  }
  return porTrecho.map(
    (chave, lista) => MapEntry(chave, resumoDe(lista)),
  );
}
