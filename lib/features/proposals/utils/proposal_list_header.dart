/// Topo da lista de propostas — as mesmas informações do `HeroFacts` do web
/// (`PurchaseProposalsPage.tsx`): escopo de visão, quantas unidades de
/// venda, rascunho em aberto e a barra de composição da carteira.
library;

class ProposalHeroFatos {
  const ProposalHeroFatos({
    required this.escopo,
    required this.unidades,
    required this.rascunho,
  });

  /// "vendo todas da imobiliária" (`proposal:view_all`) ou "vendo as suas
  /// fichas".
  final String escopo;

  /// "N unidades de venda" — `null` quando não há (o web esconde).
  final String? unidades;

  /// Rascunho de proposta em aberto no aparelho.
  final bool rascunho;
}

ProposalHeroFatos proposalHeroFatos({
  required bool canViewAll,
  required int? unidadesDeVenda,
  required bool temRascunho,
}) {
  final n = unidadesDeVenda ?? 0;
  return ProposalHeroFatos(
    escopo: canViewAll ? 'vendo todas da imobiliária' : 'vendo as suas fichas',
    unidades: n > 0
        ? '$n ${n == 1 ? 'unidade de venda' : 'unidades de venda'}'
        : null,
    rascunho: temRascunho,
  );
}

/// Frações da barra "composição da carteira" (em andamento, finalizadas,
/// canceladas sobre o total). `null` = o web não mostra (sem a contagem de
/// andamento ou total zero).
({double andamento, double finalizadas, double canceladas})?
    proposalComposicao({
  required int total,
  required int? processing,
  required int? finalized,
  required int? canceled,
}) {
  if (processing == null || total <= 0) return null;
  double f(int? v) => ((v ?? 0) / total).clamp(0.0, 1.0).toDouble();
  return (
    andamento: f(processing),
    finalizadas: f(finalized),
    canceladas: f(canceled),
  );
}
