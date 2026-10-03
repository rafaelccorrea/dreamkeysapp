import '../../shared/services/sale_forms_service.dart';
import 'sale_forms_relatorio_export.dart';

/// Linha de apoio do hero da lista de fichas de venda — mesmos contadores dos
/// chips do web (`SaleFormsPage.tsx`, "aguardando assinatura" e "em
/// andamento" SEPARADOS; o app somava os dois como "em assinatura").
String saleFormsHeroResumo(SaleFormStats st) {
  final partes = <String>['${st.total} ${st.total == 1 ? 'ficha' : 'fichas'}'];
  if (st.waitingForSignature > 0) {
    partes.add('${st.waitingForSignature} aguardando assinatura');
  }
  if (st.processing > 0) partes.add('${st.processing} em andamento');
  return partes.join(' · ');
}

/// Edição aberta com a ficha recém-lida do back (web, `CreateSaleFormPage`
/// ao abrir `/editar`): finalizada, cancelada ou excluída volta para o
/// detalhe; em processamento fica só leitura (no app, o detalhe). `null` =
/// pode editar.
String? saleFormEdicaoBloqueada(SaleForm f) {
  if (f.deletedAt != null) return 'Ficha excluída: não pode mais ser editada.';
  switch (f.status) {
    case SaleFormStatus.finalized:
      return 'Ficha finalizada: não pode mais ser editada.';
    case SaleFormStatus.canceled:
      return 'Ficha cancelada: não pode mais ser editada.';
    case SaleFormStatus.processing:
      return 'Ficha em processamento (assinaturas em andamento): '
          'abrindo só para leitura.';
    case SaleFormStatus.waitingForSignature:
      return null;
  }
}

/// `formatarSalvoEm` do web (`utils/fichaRascunho.ts`): "hoje às 10:12",
/// "ontem às 18:40" ou "em 28/09 às 09:05" (horário do aparelho).
String fichaRascunhoSalvoEm(DateTime savedAt, DateTime agora) {
  final d = savedAt.toLocal();
  final a = agora.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final hora = '${two(d.hour)}:${two(d.minute)}';
  final dia = DateTime(d.year, d.month, d.day);
  final hoje = DateTime(a.year, a.month, a.day);
  if (dia == hoje) return 'hoje às $hora';
  if (dia == DateTime(hoje.year, hoje.month, hoje.day - 1)) {
    return 'ontem às $hora';
  }
  return 'em ${two(d.day)}/${two(d.month)} às $hora';
}

/// Vendedor da linha (`saleFormSellerListLabel` do web): `sellerName`; em
/// Lançamento/MCMV (sem vendedor no fluxo) a incorporadora ou o
/// empreendimento.
String saleFormSellerListLabel(SaleForm f) {
  final direto = (f.sellerName ?? '').trim();
  if (direto.isNotEmpty) return direto;
  if (f.saleFormType.isEmpreendimento) {
    final emp = f.empreendimentoData;
    final inc = (emp?['incorporadora'] ?? '').toString().trim();
    if (inc.isNotEmpty) return inc;
    final nome = (emp?['empreendimento'] ?? '').toString().trim();
    if (nome.isNotEmpty) return nome;
  }
  return '—';
}

/// "Data da compra" do relatório (`formatSaleFormSaleDate`): só a data,
/// sem fuso.
String saleFormSaleDateLabel(SaleForm f) {
  final raw = (f.raw['saleDate'] ?? f.raw['sale_date'] ?? '').toString();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  return m == null ? '—' : '${m[3]}/${m[2]}/${m[1]}';
}

/// "Compartilhar com outras unidades" no detalhe (web `CreateSaleFormPage`,
/// campo só leitura): o campo só existe com mais de uma unidade ativa;
/// nomes das unidades compartilhadas (ids sem nome conhecido ficam de fora)
/// ou o placeholder do web quando não há nenhuma. `null` = sem campo.
String? saleFormSharedUnitsText(
  List<String>? sharedIds,
  Map<String, String> unitNamesById,
) {
  if (sharedIds == null || unitNamesById.length <= 1) return null;
  final nomes = <String>[
    for (final id in sharedIds)
      if ((unitNamesById[id] ?? '').trim().isNotEmpty) unitNamesById[id]!.trim(),
  ];
  return nomes.isEmpty
      ? 'Nenhuma — visível apenas para a unidade responsável'
      : nomes.join(', ');
}

/// Ficha do detalhe com as contagens de assinaturas ativas (o `GET /:id` do
/// back não traz `assinaturasTotal`/`assinaturasAssinadas`, só a listagem).
/// Contagem `null` (ainda carregando ou falhou) mantém o que veio.
SaleForm saleFormComResumoDeAssinaturas(
  SaleForm f, {
  int? total,
  int? assinadas,
}) {
  if (total == null) return f;
  return SaleForm({
    ...f.raw,
    'assinaturasTotal': total,
    'assinaturasAssinadas': assinadas ?? 0,
  });
}

/// Rastreabilidade da linha (`saleFormTraceabilityOneLine` do web):
/// `lastAudit.summary` quando vem; senão exclusão, cancelamento, desativação
/// automática (`ativo=false`), recusa da trava (data e justificativa),
/// criação e última atualização.
String saleFormRastreioLinha(SaleForm f) => saleFormsExportTraceability(f.raw);
