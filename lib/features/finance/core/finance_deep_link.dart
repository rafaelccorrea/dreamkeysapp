import 'finance_route_names.dart';

/// Que tela do app uma rota `/financeiro/*` abre (função pura, testada).
enum FinanceRouteKind {
  meuDashboard,
  solicitacoes,
  novaSolicitacao,
  solicitacao,
  editarSolicitacao,
  aprovacoes,
  pedirAdiantamento,

  /// A tela existe só no web: o app mostra um aviso claro.
  webOnly,
}

class FinanceRouteMatch {
  final FinanceRouteKind kind;
  final String? id;

  /// Venda a abrir na "Consulta da venda" (Meu Financeiro).
  final String? saleId;

  /// Nome da tela do web (aviso "só no web").
  final String? webLabel;

  const FinanceRouteMatch(this.kind, {this.id, this.saleId, this.webLabel});
}

/// Rótulos das telas do web que o app não tem.
const Map<String, String> kFinanceWebOnlyLabels = {
  'contas-a-pagar': 'Contas a pagar',
  'contas-a-receber': 'Contas a receber',
  'pipeline': 'Pipeline de confissões',
  'vendas': 'Vendas do Financeiro',
  'comissoes': 'Comissões',
  'repasses': 'Repasses',
  'dre': 'DRE',
  'dfc': 'Fluxo de caixa',
  'bancos': 'Bancos',
  'cartoes': 'Cartões',
  'orcamento': 'Orçamento',
  'cadastros': 'Cadastros',
  'acessos': 'Acessos',
  'metas': 'Metas',
};

/// Casa uma rota (`/financeiro/...?...`) com a tela do app. Paths iguais
/// aos do web (`financeiro.routes.tsx`).
FinanceRouteMatch matchFinanceRoute(String route) {
  final uri = Uri.tryParse(route) ?? Uri(path: route);
  final q = uri.queryParameters;
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.isEmpty || seg.first != 'financeiro') {
    return const FinanceRouteMatch(FinanceRouteKind.meuDashboard);
  }
  final s1 = seg.length > 1 ? seg[1] : null;
  final s2 = seg.length > 2 ? seg[2] : null;
  final s3 = seg.length > 3 ? seg[3] : null;
  switch (s1) {
    case null:
    case 'meu-dashboard':
    case 'meu-financeiro':
      return FinanceRouteMatch(
        FinanceRouteKind.meuDashboard,
        saleId: _nz(q['venda']) ?? _nz(q['saleId']),
      );
    case 'solicitacoes':
    case 'acompanhamento':
      if (s2 == null) {
        final id = _nz(q['id']);
        return id == null
            ? const FinanceRouteMatch(FinanceRouteKind.solicitacoes)
            : FinanceRouteMatch(FinanceRouteKind.solicitacao, id: id);
      }
      if (s2 == 'nova' || s2 == 'novo') {
        return const FinanceRouteMatch(FinanceRouteKind.novaSolicitacao);
      }
      if (s3 == 'editar') {
        return FinanceRouteMatch(FinanceRouteKind.editarSolicitacao, id: s2);
      }
      return FinanceRouteMatch(FinanceRouteKind.solicitacao, id: s2);
    case 'aprovacoes':
      return const FinanceRouteMatch(FinanceRouteKind.aprovacoes);
    case 'adiantamentos':
    case 'adiantamento':
      if (s2 == 'novo' || s2 == 'nova' || _nz(q['novo']) != null) {
        return const FinanceRouteMatch(FinanceRouteKind.pedirAdiantamento);
      }
      // A lista de adiantamentos é de gestão (web); no app o histórico
      // pessoal está no Meu Financeiro.
      return const FinanceRouteMatch(FinanceRouteKind.meuDashboard);
    case 'vendas':
      final sale = _nz(q['saleId']);
      // `chat=1` é a conversa da venda — só no web.
      if (sale != null && q['chat'] != '1') {
        return FinanceRouteMatch(FinanceRouteKind.meuDashboard, saleId: sale);
      }
      return FinanceRouteMatch(
        FinanceRouteKind.webOnly,
        webLabel: sale != null ? 'Conversa da venda' : kFinanceWebOnlyLabels['vendas'],
      );
    default:
      return FinanceRouteMatch(
        FinanceRouteKind.webOnly,
        webLabel: kFinanceWebOnlyLabels[s1] ?? 'Esta tela do Financeiro',
      );
  }
}

String? _nz(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

/// Notificação do Financeiro (`GET /notifications`, schema `Notification`).
class FinanceNotification {
  final String id;
  final String type;
  final String message;
  final bool read;
  final String? createdAt;
  final String? saleId;
  final String? dealId;
  final String? payableId;
  final String? payableCode;
  final String? requestId;
  final String? requestCode;

  const FinanceNotification({
    required this.id,
    required this.type,
    required this.message,
    this.read = false,
    this.createdAt,
    this.saleId,
    this.dealId,
    this.payableId,
    this.payableCode,
    this.requestId,
    this.requestCode,
  });

  factory FinanceNotification.fromJson(Map<String, dynamic> j) {
    String? s(dynamic v) {
      final t = v?.toString().trim();
      return t == null || t.isEmpty ? null : t;
    }

    Map<String, dynamic> m(dynamic v) => v is Map
        ? v.map((k, val) => MapEntry(k.toString(), val))
        : const <String, dynamic>{};
    return FinanceNotification(
      id: j['id']?.toString() ?? '',
      type: j['type']?.toString() ?? '',
      message: j['message']?.toString() ?? '',
      read: j['read'] == true,
      createdAt: s(j['createdAt']),
      saleId: s(j['saleId']),
      dealId: s(j['dealId']),
      payableId: s(j['payableId']) ?? s(m(j['payable'])['id']),
      payableCode: s(m(j['payable'])['code']),
      requestId: s(j['requestId']) ?? s(m(j['request'])['id']),
      requestCode: s(m(j['request'])['code']),
    );
  }

  FinanceNotification copyRead() => FinanceNotification(
    id: id,
    type: type,
    message: message,
    read: true,
    createdAt: createdAt,
    saleId: saleId,
    dealId: dealId,
    payableId: payableId,
    payableCode: payableCode,
    requestId: requestId,
    requestCode: requestCode,
  );

  String get title => financeNotificationTitle(type);
}

/// Títulos (`financeNotificationsApi.ts:72-121` + catálogo do back).
String financeNotificationTitle(String type) {
  const t = {
    'REFUND_DUE_5_DAYS': 'Devolução em 5 dias',
    'REFUND_DUE_3_DAYS': 'Devolução em 3 dias',
    'REFUND_DUE_TODAY': 'Devolução vence hoje',
    'REFUND_OVERDUE': 'Devolução vencida',
    'INSTALLMENT_OVERDUE': 'Parcela vencida',
    'RECEIVABLE_OVERDUE': 'Conta a receber vencida',
    'PAYABLE_OVERDUE': 'Conta a pagar vencida',
    'COMMISSION_DEBIT': 'Débito de comissão',
    'ADVANCE_APPROVAL_PENDING': 'Adiantamento aguardando sua aprovação',
    'PAYABLE_APPROVAL_PENDING': 'Conta aguardando sua aprovação',
    'PAYABLE_RECEIPT_PENDING': 'Baixa pendente — registre o pagamento',
    'REQUEST_SUA_VEZ': 'Chegou a sua vez de assinar',
    'REQUEST_APPROVAL_PENDING': 'Solicitação aguardando sua aprovação',
    'REQUEST_APPROVED': 'Solicitação aprovada',
    'REQUEST_REPROVED': 'Solicitação reprovada',
    'REPASSE_APPROVED': 'Repasse aprovado',
    'REPASSE_PAID': 'Repasse pago',
    'SALE_CREATED': 'Venda criada',
    'SALE_CANCELLED': 'Venda cancelada',
    'SALE_COMMENT': 'Conversa da venda',
    'PAYABLE_DUE_SOON': 'Conta a pagar a vencer',
    'RECEIVABLE_DUE_SOON': 'Conta a receber a vencer',
    'DEAL_COST_APPROVAL_PENDING': 'Custo de confissão aguardando aval',
    'DEAL_COST_RECEIPT_PENDING': 'Comprovante do custo pendente',
    'SIGNATURE_PENDING': 'Ficha aguardando sua assinatura',
    'SALE_EDITED_WITH_BYPASS': 'Ficha alterada com dinheiro já movimentado',
    'DISTRATO_ANEXO_PENDENTE': 'Anexo do distrato pendente',
    'DISTRATO_REVERSAO_PENDENTE': 'Pedido de reversão de distrato',
    'TAX_GUIDE_DUE': 'Guia de imposto a vencer',
    'TAX_GUIDE_GENERATED': 'Guia de imposto gerada com valor estimado',
  };
  return t[type] ?? 'Financeiro';
}

/// Para onde um toque na notificação leva NO APP. Mesma ordem do
/// `destino()` do web; o que o app não tem vira rota de "só no web"
/// (aviso claro). `null` = sem destino.
///
/// Diferenças conscientes do web:
/// - quem aprova vai para "Para aprovar" nos avisos de "sua vez";
/// - `saleId` abre a consulta da venda do Meu Financeiro;
/// - `COMMISSION_DEBIT` sem venda abre o Meu Financeiro.
String? financeNotificationRoute(
  FinanceNotification n, {
  bool podeAprovar = false,
}) {
  const aprovar = {'REQUEST_SUA_VEZ', 'REQUEST_APPROVAL_PENDING'};
  if (n.requestId != null) {
    if (podeAprovar && aprovar.contains(n.type)) {
      return FinanceRouteNames.aprovacoes;
    }
    return FinanceRouteNames.solicitacao(n.requestId!);
  }
  if (n.type == 'SALE_COMMENT' && n.saleId != null) {
    return '${FinanceRouteNames.vendas}?saleId=${Uri.encodeQueryComponent(n.saleId!)}&chat=1';
  }
  if (n.type == 'ADVANCE_APPROVAL_PENDING' ||
      n.type == 'DEAL_COST_APPROVAL_PENDING') {
    return podeAprovar ? FinanceRouteNames.aprovacoes : '/financeiro/adiantamentos';
  }
  if (n.type.startsWith('PAYABLE_') || n.type.startsWith('TAX_GUIDE')) {
    return '/financeiro/contas-a-pagar';
  }
  if (n.saleId != null) return FinanceRouteNames.venda(n.saleId!);
  if (n.dealId != null) return '/financeiro/pipeline';
  if (n.type.startsWith('RECEIVABLE_')) return '/financeiro/contas-a-receber';
  if (n.type == 'COMMISSION_DEBIT' ||
      n.type == 'REPASSE_APPROVED' ||
      n.type == 'REPASSE_PAID') {
    return FinanceRouteNames.meuDashboard;
  }
  return null;
}
