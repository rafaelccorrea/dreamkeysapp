import '../../core/finance_format.dart';

Map<String, dynamic> _map(dynamic v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val))
    : <String, dynamic>{};

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v is List ? v : const []).whereType<Map>().map(_map).toList();

/// `{id, name}` genérico dos cadastros (empresa, categoria, centro…).
class FinanceRef {
  final String id;
  final String name;
  final Map<String, dynamic> raw;
  const FinanceRef(this.id, this.name, [this.raw = const {}]);

  static FinanceRef? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = _map(v);
    final id = m['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return FinanceRef(
      id,
      (m['name'] ?? m['nome'] ?? m['nomeFantasia'] ?? m['razaoSocial'] ?? '')
          .toString(),
      m,
    );
  }

  static List<FinanceRef> list(dynamic v) {
    final src = v is Map ? _map(v)['data'] : v;
    return (src is List ? src : const [])
        .map(FinanceRef.fromJson)
        .whereType<FinanceRef>()
        .toList();
  }
}

/// Etapa da cadeia de aprovação da solicitação.
class RequestApproval {
  final int level;
  final String role;
  final String status;
  final String? comment;
  final String? approverName;
  final String? decidedAt;
  const RequestApproval({
    required this.level,
    required this.role,
    required this.status,
    this.comment,
    this.approverName,
    this.decidedAt,
  });

  factory RequestApproval.fromJson(Map<String, dynamic> j) => RequestApproval(
    level: (j['level'] as num?)?.toInt() ?? 0,
    role: j['role']?.toString() ?? '',
    status: j['status']?.toString() ?? '',
    comment: _str(j['comment']),
    approverName: _str(_map(j['approver'])['name']),
    decidedAt: _str(j['decidedAt']),
  );
}

class RequestComment {
  final String id;
  final String body;
  final String? kind;
  final String? authorName;
  final String? authorId;
  final String? createdAt;
  const RequestComment({
    required this.id,
    required this.body,
    this.kind,
    this.authorName,
    this.authorId,
    this.createdAt,
  });
  factory RequestComment.fromJson(Map<String, dynamic> j) => RequestComment(
    id: j['id']?.toString() ?? '',
    body: j['body']?.toString() ?? '',
    kind: _str(j['kind']),
    authorId: _str(j['authorId']),
    authorName: _str(_map(j['author'])['name']),
    createdAt: _str(j['createdAt']),
  );
}

class RequestAttachment {
  final String id;
  final String name;
  final String url;
  final String? uploadedById;
  final String? createdAt;
  const RequestAttachment({
    required this.id,
    required this.name,
    required this.url,
    this.uploadedById,
    this.createdAt,
  });
  factory RequestAttachment.fromJson(Map<String, dynamic> j) =>
      RequestAttachment(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Anexo',
        url: j['url']?.toString() ?? '',
        uploadedById: _str(j['uploadedById']),
        createdAt: _str(j['createdAt']),
      );
}

/// Item da lista e detalhe (`RequestSummary`/`RequestDetail`,
/// `types/financeiro.ts:2585-2663`; `requests.service.ts:146-185,1006-1030`).
class FinanceRequest {
  final String id;
  final String? code;
  final String type;
  final String? tipoId;
  final String? naturezaId;
  final Map<String, dynamic> camposExtras;
  final String status;
  final String priority;
  final String title;
  final String justification;
  final String? department;
  final double amountRequested;
  final double? amountApproved;
  final String? notes;
  final String? paymentMethod;
  final String? creditCardId;
  final String? purchaseDate;
  final int? installments;
  final FinanceRef? company;
  final FinanceRef? requester;
  final FinanceRef? category;
  final FinanceRef? costCenter;
  final FinanceRef? supplier;
  final FinanceRef? creditCard;
  final List<RequestApproval> approvals;
  final List<RequestComment> comments;
  final List<RequestAttachment> attachments;
  final List<Map<String, dynamic>> payables;
  final List<Map<String, dynamic>> beneficiaries;
  final Map<String, dynamic>? permissoes;
  final String? createdAt;

  const FinanceRequest({
    required this.id,
    required this.title,
    required this.status,
    this.code,
    this.type = 'OUTROS',
    this.tipoId,
    this.naturezaId,
    this.camposExtras = const {},
    this.priority = 'MEDIA',
    this.justification = '',
    this.department,
    this.amountRequested = 0,
    this.amountApproved,
    this.notes,
    this.paymentMethod,
    this.creditCardId,
    this.purchaseDate,
    this.installments,
    this.company,
    this.requester,
    this.category,
    this.costCenter,
    this.supplier,
    this.creditCard,
    this.approvals = const [],
    this.comments = const [],
    this.attachments = const [],
    this.payables = const [],
    this.beneficiaries = const [],
    this.permissoes,
    this.createdAt,
  });

  factory FinanceRequest.fromJson(Map<String, dynamic> j) {
    final approvals = _maps(j['approvals']).map(RequestApproval.fromJson)
        .toList()
      ..sort((a, b) => a.level.compareTo(b.level));
    return FinanceRequest(
      id: j['id']?.toString() ?? '',
      code: _str(j['code']),
      type: j['type']?.toString() ?? 'OUTROS',
      tipoId: _str(j['tipoId']),
      naturezaId: _str(j['naturezaId']),
      camposExtras: _map(j['camposExtras']),
      status: j['status']?.toString() ?? '',
      priority: j['priority']?.toString() ?? 'MEDIA',
      title: j['title']?.toString() ?? '',
      justification: j['justification']?.toString() ?? '',
      department: _str(j['department']),
      amountRequested: financeNum(j['amountRequested']),
      amountApproved: financeNumOrNull(j['amountApproved']),
      notes: _str(j['notes']),
      paymentMethod: _str(j['paymentMethod']),
      creditCardId: _str(j['creditCardId']),
      purchaseDate: _str(j['purchaseDate']),
      installments: (j['installments'] as num?)?.toInt(),
      company: FinanceRef.fromJson(j['company']),
      requester: FinanceRef.fromJson(j['requester']),
      category: FinanceRef.fromJson(j['category']),
      costCenter: FinanceRef.fromJson(j['costCenter']),
      supplier: FinanceRef.fromJson(j['supplier']),
      creditCard: FinanceRef.fromJson(j['creditCard']),
      approvals: approvals,
      comments: _maps(j['comments']).map(RequestComment.fromJson).toList(),
      attachments: _maps(
        j['attachments'],
      ).map(RequestAttachment.fromJson).toList(),
      payables: _maps(j['payables']),
      beneficiaries: _maps(j['beneficiaries']),
      permissoes: j['permissoes'] is Map ? _map(j['permissoes']) : null,
      createdAt: _str(j['createdAt']),
    );
  }

  bool get algumaEtapaAprovada => approvals.any((a) => a.status == 'APROVADO');

  /// `permissoes` do back; sem ele (back antigo), o fallback do web
  /// (`acoesSolicitacao.ts:40-71`) — dono é quem pediu.
  bool podeEditar({String? meId}) {
    final p = permissoes?['podeEditar'];
    if (p is bool) return p;
    final dono = meId != null && requester?.id == meId;
    return dono && (status == 'PENDENTE' || status == 'REPROVADO');
  }

  bool podeCancelar({String? meId}) {
    final p = permissoes?['podeCancelar'];
    if (p is bool) return p;
    final dono = meId != null && requester?.id == meId;
    final temTitulo = payables.any((x) => x['status'] != 'CANCELADO');
    return dono &&
        status != 'CONCLUIDO' &&
        status != 'CANCELADO' &&
        !temTitulo;
  }

  /// O valor fica travado se é PENDENTE e alguma etapa já aprovou.
  bool get valorTravado => status == 'PENDENTE' && algumaEtapaAprovada;
}

/// `GET /requests/dashboard` (só o que o app mostra).
class RequestsDashboard {
  final int total;
  final Map<String, int> byStatus;
  final double requested;
  final double approved;
  final double paid;
  const RequestsDashboard({
    this.total = 0,
    this.byStatus = const {},
    this.requested = 0,
    this.approved = 0,
    this.paid = 0,
  });

  factory RequestsDashboard.fromJson(Map<String, dynamic> j) {
    final by = _map(j['byStatus']);
    final totals = _map(j['totals']);
    return RequestsDashboard(
      total: (j['total'] as num?)?.toInt() ?? 0,
      byStatus: by.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      requested: financeNum(totals['requested']),
      approved: financeNum(totals['approved']),
      paid: financeNum(totals['paid']),
    );
  }
}

// ─── /request-tipos ─────────────────────────────────────────────────────────

class TipoCampo {
  final String chave;
  final String rotulo;
  final String? ajuda;
  final String kind; // TEXTO|TEXTO_LONGO|NUMERO|MOEDA|DATA|LISTA|SIM_NAO
  final List<String> opcoes;
  final bool obrigatorio;
  const TipoCampo({
    required this.chave,
    required this.rotulo,
    required this.kind,
    this.ajuda,
    this.opcoes = const [],
    this.obrigatorio = false,
  });
}

class RequestTipo {
  final String id;
  final String nome;
  final String? descricao;
  final String motor; // PAGAMENTO | REEMBOLSO | ADIANTAMENTO_COMISSAO
  final List<String> naturezaIds;
  final Map<String, ({bool visivel, bool obrigatorio})> camposBase;
  final List<TipoCampo> campos;

  const RequestTipo({
    required this.id,
    required this.nome,
    required this.motor,
    this.descricao,
    this.naturezaIds = const [],
    this.camposBase = const {},
    this.campos = const [],
  });

  factory RequestTipo.fromJson(Map<String, dynamic> j) {
    final base = <String, ({bool visivel, bool obrigatorio})>{};
    _map(j['camposBase']).forEach((k, v) {
      final m = _map(v);
      base[k] = (
        visivel: m['visivel'] != false,
        obrigatorio: m['obrigatorio'] == true,
      );
    });
    final campos =
        _maps(j['campos'])
            .where((c) => c['ativo'] != false)
            .map(
              (c) => (
                ordem: (c['ordem'] as num?)?.toInt() ?? 0,
                campo: TipoCampo(
                  chave: c['chave']?.toString() ?? '',
                  rotulo: c['rotulo']?.toString() ?? '',
                  ajuda: _str(c['ajuda']),
                  kind: c['kind']?.toString() ?? 'TEXTO',
                  opcoes: (c['opcoes'] is List ? c['opcoes'] as List : const [])
                      .map((e) => e.toString())
                      .toList(),
                  obrigatorio: c['obrigatorio'] == true,
                ),
              ),
            )
            .where((c) => c.campo.chave.isNotEmpty)
            .toList()
          ..sort((a, b) => a.ordem.compareTo(b.ordem));
    return RequestTipo(
      id: j['id']?.toString() ?? '',
      nome: j['nome']?.toString() ?? '',
      descricao: _str(j['descricao']),
      motor: j['motor']?.toString() ?? 'PAGAMENTO',
      naturezaIds: (j['naturezaIds'] is List ? j['naturezaIds'] as List : [])
          .map((e) => e.toString())
          .toList(),
      camposBase: base,
      campos: campos.map((c) => c.campo).toList(),
    );
  }

  /// Padrões do back (`tipos-de-solicitacao.ts:35-57`) quando o tipo não
  /// define o campo base.
  ({bool visivel, bool obrigatorio}) base(String campo) {
    final b = camposBase[campo];
    if (b != null) return b;
    final reembolso = motor == 'REEMBOLSO';
    switch (campo) {
      case 'natureza':
        return (visivel: true, obrigatorio: true);
      case 'comprovante':
        return (visivel: reembolso, obrigatorio: reembolso);
      case 'fornecedor':
      case 'formaDePagamento':
      case 'rateio':
        return (visivel: !reembolso, obrigatorio: false);
      case 'departamento':
        return (visivel: !reembolso, obrigatorio: false);
      default:
        return (visivel: true, obrigatorio: false);
    }
  }

  bool get ehAdiantamento => motor == 'ADIANTAMENTO_COMISSAO';
  bool get ehReembolso => motor == 'REEMBOLSO';
}

class RequestNatureza {
  final String id;
  final String nome;
  final String grupo;
  const RequestNatureza(this.id, this.nome, this.grupo);
}

class RequestTiposCatalog {
  final List<RequestTipo> tipos;
  final List<RequestNatureza> naturezas;
  const RequestTiposCatalog({this.tipos = const [], this.naturezas = const []});

  factory RequestTiposCatalog.fromJson(Map<String, dynamic> j) =>
      RequestTiposCatalog(
        tipos: _maps(j['tipos'])
            .where((t) => t['ativo'] != false)
            .map(RequestTipo.fromJson)
            .where((t) => t.id.isNotEmpty)
            .toList(),
        naturezas: _maps(j['naturezas'])
            .where((n) => n['ativo'] != false)
            .map(
              (n) => RequestNatureza(
                n['id']?.toString() ?? '',
                n['nome']?.toString() ?? '',
                n['grupo']?.toString() ?? 'OUTROS',
              ),
            )
            .where((n) => n.id.isNotEmpty)
            .toList(),
      );

  List<RequestNatureza> naturezasDo(RequestTipo t) => t.naturezaIds.isEmpty
      ? naturezas
      : naturezas.where((n) => t.naturezaIds.contains(n.id)).toList();
}

// ─── Rótulos (`utils/rotulosSolicitacao.ts:53-171`, `meiosPagamento.ts`) ────

const Map<String, String> kRequestStatusLabels = {
  'PENDENTE': 'Pendente',
  'APROVADO': 'Aprovado',
  'REPROVADO': 'Reprovado',
  'EM_PROCESSAMENTO': 'Em processamento',
  'CONCLUIDO': 'Concluído',
  'CANCELADO': 'Cancelado',
};

const Map<String, String> kRequestTypeLabels = {
  'MARKETING': 'Marketing',
  'SERVICOS': 'Serviços',
  'PAGAMENTOS': 'Pagamentos',
  'COMPRAS': 'Compras',
  'OUTROS': 'Outros',
  'EXPENSE': 'Despesa',
  'INVESTMENT': 'Investimento',
  'TRANSFER': 'Transferência',
  'REIMBURSEMENT': 'Reembolso',
  'OTHER': 'Outro',
};

/// Tipos aceitos no envio (`RequestTypeDto`).
const List<String> kRequestTypesNovos = [
  'MARKETING',
  'SERVICOS',
  'PAGAMENTOS',
  'COMPRAS',
  'OUTROS',
];

const Map<String, String> kRequestPriorityLabels = {
  'BAIXA': 'Baixa',
  'MEDIA': 'Média',
  'ALTA': 'Alta',
  'URGENTE': 'Urgente',
};

const Map<String, String> kPaymentMethodLabels = {
  'PIX': 'Pix',
  'TED': 'TED',
  'TRANSFERENCIA': 'Transferência bancária',
  'BOLETO': 'Boleto',
  'DINHEIRO': 'Dinheiro',
  'CARTAO_CREDITO': 'Cartão de crédito',
  'CARTAO_DEBITO': 'Cartão de débito (maquininha)',
  'DEBITO_EM_CONTA': 'Débito automático em conta',
};

const Map<String, String> kApprovalRoleLabels = {
  'GESTOR': 'Gestor',
  'FINANCEIRO': 'Financeiro',
  'DIRETORIA': 'Diretoria',
};

String _label(Map<String, String> m, String? v) {
  if (v == null || v.isEmpty) return '—';
  final known = m[v];
  if (known != null) return known;
  final s = v.toLowerCase().replaceAll('_', ' ');
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

String requestTypeLabel(String? v) => _label(kRequestTypeLabels, v);
String requestPriorityLabel(String? v) => _label(kRequestPriorityLabels, v);
String paymentMethodLabel(String? v) => _label(kPaymentMethodLabels, v);
String approvalRoleLabel(String? v) => _label(kApprovalRoleLabels, v);
String approvalStepStatusLabel(String? v) => _label(const {
  'PENDENTE': 'Pendente',
  'APROVADO': 'Aprovado',
  'REPROVADO': 'Reprovado',
}, v);
