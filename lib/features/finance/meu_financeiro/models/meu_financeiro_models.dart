import '../../core/finance_format.dart';

Map<String, dynamic> _map(dynamic v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val))
    : <String, dynamic>{};

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Envelope paginado do Financeiro (`{data, total, page, pageSize}`). O
/// back devolve array cru quando falta `page`/`pageSize` — aceito também.
class FinancePage<T> {
  final List<T> data;
  final int total;
  final int page;
  final int pageSize;

  const FinancePage({
    required this.data,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  bool get hasMore => page * pageSize < total;

  static FinancePage<T> parse<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) item,
  ) {
    if (raw is List) {
      final list = raw.whereType<Map>().map((e) => item(_map(e))).toList();
      return FinancePage(
        data: list,
        total: list.length,
        page: 1,
        pageSize: list.isEmpty ? 1 : list.length,
      );
    }
    final m = _map(raw);
    final data = (m['data'] is List ? m['data'] as List : const [])
        .whereType<Map>()
        .map((e) => item(_map(e)))
        .toList();
    return FinancePage(
      data: data,
      total: (m['total'] as num?)?.toInt() ?? data.length,
      page: (m['page'] as num?)?.toInt() ?? 1,
      pageSize:
          (m['pageSize'] as num?)?.toInt() ?? (data.isEmpty ? 1 : data.length),
    );
  }

  FinancePage<T> append(FinancePage<T> next) => FinancePage(
    data: [...data, ...next.data],
    total: next.total,
    page: next.page,
    pageSize: next.pageSize,
  );
}

// ─── GET /repasses/broker-dashboard ─────────────────────────────────────────

class EarningsTotals {
  final double devido;
  final double recebido;
  final double retido;
  final double aReceber;
  final double? travado;
  final double? bonificacao;
  final double saldoAdiantamento;
  final double saldoDevedor;

  const EarningsTotals({
    this.devido = 0,
    this.recebido = 0,
    this.retido = 0,
    this.aReceber = 0,
    this.travado,
    this.bonificacao,
    this.saldoAdiantamento = 0,
    this.saldoDevedor = 0,
  });

  factory EarningsTotals.fromJson(Map<String, dynamic> j) => EarningsTotals(
    devido: financeNum(j['devido']),
    recebido: financeNum(j['recebido']),
    retido: financeNum(j['retido']),
    aReceber: financeNum(j['aReceber']),
    travado: financeNumOrNull(j['travado']),
    bonificacao: financeNumOrNull(j['bonificacao']),
    saldoAdiantamento: financeNum(j['saldoAdiantamento']),
    saldoDevedor: financeNum(j['saldoDevedor']),
  );
}

class BrokerOption {
  final String brokerId;
  final String? brokerName;
  const BrokerOption(this.brokerId, this.brokerName);
}

class MonthlyEarning {
  /// `YYYY-MM`.
  final String month;
  final double recebido;
  final double retido;
  final double previsto;

  const MonthlyEarning({
    required this.month,
    this.recebido = 0,
    this.retido = 0,
    this.previsto = 0,
  });
}

class CountValue {
  final int count;
  final double valor;
  const CountValue({this.count = 0, this.valor = 0});

  static CountValue? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = _map(raw);
    return CountValue(
      count: (m['count'] as num?)?.toInt() ?? 0,
      valor: financeNum(m['valor']),
    );
  }
}

class BrokerDashboardSummary {
  final EarningsTotals totals;
  final int vendasComRepasse;
  final List<BrokerOption> brokers;
  final List<MonthlyEarning> mensal;
  final CountValue aguardandoAssinatura;

  /// `null` = back antigo sem o campo: mostrar "–" (não portar o paliativo
  /// `?status=APROVADO` sem paginação).
  final CountValue? adiantamentoAprovado;

  const BrokerDashboardSummary({
    this.totals = const EarningsTotals(),
    this.vendasComRepasse = 0,
    this.brokers = const [],
    this.mensal = const [],
    this.aguardandoAssinatura = const CountValue(),
    this.adiantamentoAprovado,
  });

  factory BrokerDashboardSummary.fromJson(Map<String, dynamic> j) {
    final brokers = (j['brokers'] is List ? j['brokers'] as List : const [])
        .whereType<Map>()
        .map((e) {
          final m = _map(e);
          return BrokerOption(
            m['brokerId']?.toString() ?? '',
            _str(m['brokerName']),
          );
        })
        .where((b) => b.brokerId.isNotEmpty)
        .toList();
    final mensal = (j['mensal'] is List ? j['mensal'] as List : const [])
        .whereType<Map>()
        .map((e) {
          final m = _map(e);
          return MonthlyEarning(
            month: m['month']?.toString() ?? '',
            recebido: financeNum(m['recebido']),
            retido: financeNum(m['retido']),
            previsto: financeNum(m['previsto']),
          );
        })
        .where((m) => m.month.isNotEmpty)
        .toList();
    return BrokerDashboardSummary(
      totals: EarningsTotals.fromJson(_map(j['totals'])),
      vendasComRepasse: (j['vendasComRepasse'] as num?)?.toInt() ?? 0,
      brokers: brokers,
      mensal: mensal,
      aguardandoAssinatura:
          CountValue.fromJson(j['aguardandoAssinatura']) ?? const CountValue(),
      adiantamentoAprovado: CountValue.fromJson(j['adiantamentoAprovado']),
    );
  }
}

// ─── GET /repasses/broker-dashboard/proximos ────────────────────────────────

/// Visões da lista da direita (`VISAO_CONFIG`, MeuFinanceiroPage.tsx:447).
enum FinanceVisao {
  aReceber(
    'a-receber',
    'Próximos recebimentos',
    'Previsto',
    'Nenhum repasse pendente.',
    'Nenhum repasse no filtro aplicado.',
    'previsto',
    'asc',
  ),
  recebido(
    'recebido',
    'Comissões recebidas',
    'Pago em',
    'Nenhuma comissão paga até agora.',
    'Nenhum pagamento no filtro aplicado.',
    'previsto',
    'desc',
  ),
  retido(
    'retido',
    'Retido dos repasses',
    'Retido em',
    'Nenhuma retenção registrada.',
    'Nenhuma retenção no filtro aplicado.',
    'previsto',
    'desc',
  ),
  saldoDevedor(
    'saldo-devedor',
    'Saldo devedor em aberto',
    'Aberto desde',
    'Nenhuma dívida em aberto.',
    'Nenhum débito no filtro aplicado.',
    'valor',
    'desc',
  ),
  adiantamentoAprovado(
    'adiantamento-aprovado',
    'Adiantamentos aprovados',
    'Aprovado em',
    'Nenhum adiantamento aprovado no momento.',
    'Nenhum adiantamento no filtro aplicado.',
    'valor',
    'desc',
  );

  const FinanceVisao(
    this.api,
    this.title,
    this.dateLabel,
    this.empty,
    this.emptyFiltered,
    this.sortBy,
    this.sortDir,
  );

  final String api;
  final String title;
  final String dateLabel;
  final String empty;
  final String emptyFiltered;
  final String sortBy;
  final String sortDir;
}

class BrokerProximo {
  final String repasseId;
  final String? saleId;
  final String? origem;
  final String? receivableCode;
  final String? fichaVenda;
  final String? propertyName;
  final String? unit;
  final String? clientName;
  final int? installmentNumber;
  final double valor;
  final String status;
  final String? previstoPara;
  final bool isAdvanced;
  final bool emAtraso;

  const BrokerProximo({
    required this.repasseId,
    required this.valor,
    required this.status,
    this.saleId,
    this.origem,
    this.receivableCode,
    this.fichaVenda,
    this.propertyName,
    this.unit,
    this.clientName,
    this.installmentNumber,
    this.previstoPara,
    this.isAdvanced = false,
    this.emAtraso = false,
  });

  factory BrokerProximo.fromJson(Map<String, dynamic> j) => BrokerProximo(
    repasseId: j['repasseId']?.toString() ?? '',
    saleId: _str(j['saleId']),
    origem: _str(j['origem']),
    receivableCode: _str(j['receivableCode']),
    fichaVenda: _str(j['fichaVenda']),
    propertyName: _str(j['propertyName']),
    unit: _str(j['unit']),
    clientName: _str(j['clientName']),
    installmentNumber: (j['installmentNumber'] as num?)?.toInt(),
    valor: financeNum(j['valor']),
    status: j['status']?.toString() ?? '',
    previstoPara: _str(j['previstoPara']),
    isAdvanced: j['isAdvanced'] == true,
    emAtraso: j['emAtraso'] == true,
  );

  /// Linha principal: imóvel/unidade, ou a ficha, ou o título avulso.
  String get title {
    final imovel = [propertyName, unit].whereType<String>().join(' · ');
    if (imovel.isNotEmpty) return imovel;
    if (fichaVenda != null) return 'Ficha $fichaVenda';
    if (receivableCode != null) return receivableCode!;
    return origem == 'titulo' ? 'Título avulso' : 'Repasse';
  }

  String get subtitle {
    final parts = <String>[
      if (fichaVenda != null && (propertyName != null || unit != null))
        'Ficha $fichaVenda',
      ?clientName,
      if (installmentNumber != null) 'Parcela $installmentNumber',
    ];
    return parts.join(' · ');
  }
}

/// Rótulo da pílula (`LINHA_STATUS_LABEL`, MeuFinanceiroPage.tsx:274-307).
String proximoStatusLabel(String status, {bool emAtraso = false}) {
  if (emAtraso) return 'Em atraso';
  const labels = {
    'WAITING_FOR_SIGNATURE': 'Aguard. assinatura',
    'EM_CONFERENCIA': 'Em conferência',
    'PENDING': 'Pendente',
    'APPROVED': 'Aprovado',
    'PAID': 'Pago',
    'ADVANCE': 'Adiantamento',
    'REVERSAL': 'Estorno',
    'APROVADO': 'Aprovado',
  };
  return labels[status] ?? status;
}

// ─── GET /repasses/broker-dashboard/vendas ──────────────────────────────────

/// Filtro "situação" das vendas (MeuFinanceiroPage.tsx:289,2778).
enum VendaSituacao {
  todas(null, 'Todas'),
  aReceber('a-receber', 'Com a receber'),
  quitadas('quitadas', 'Quitadas'),
  retencao('retencao', 'Com retenção'),
  semAssinatura('sem-assinatura', 'Sem assinatura');

  const VendaSituacao(this.api, this.label);
  final String? api;
  final String label;
}

class VendaPapel {
  final String? participantType;
  final double? commissionRate;
  const VendaPapel(this.participantType, this.commissionRate);
}

class BrokerVenda {
  final String saleId;
  final String? brokerName;
  final String? fichaVenda;
  final String? propertyName;
  final String? unit;
  final String? clientName;
  final List<VendaPapel> papeis;
  final int parcelas;
  final double? bonusRate;
  final EarningsTotals totals;

  const BrokerVenda({
    required this.saleId,
    required this.totals,
    this.brokerName,
    this.fichaVenda,
    this.propertyName,
    this.unit,
    this.clientName,
    this.papeis = const [],
    this.parcelas = 0,
    this.bonusRate,
  });

  factory BrokerVenda.fromJson(Map<String, dynamic> j) => BrokerVenda(
    saleId: j['saleId']?.toString() ?? '',
    brokerName: _str(j['brokerName']),
    fichaVenda: _str(j['fichaVenda']),
    propertyName: _str(j['propertyName']),
    unit: _str(j['unit']),
    clientName: _str(j['clientName']),
    papeis: (j['papeis'] is List ? j['papeis'] as List : const [])
        .whereType<Map>()
        .map((e) {
          final m = _map(e);
          return VendaPapel(
            _str(m['participantType']),
            financeNumOrNull(m['commissionRate']),
          );
        })
        .toList(),
    parcelas: (j['parcelas'] as num?)?.toInt() ?? 0,
    bonusRate: financeNumOrNull(j['bonusRate']),
    totals: EarningsTotals.fromJson(j),
  );

  String get title {
    final imovel = [propertyName, unit].whereType<String>().join(' · ');
    if (imovel.isNotEmpty) return imovel;
    if (fichaVenda != null) return 'Ficha $fichaVenda';
    return 'Venda';
  }

  /// "Captador 2% · Vendedor 3% + 0,5% bônus".
  String get papeisLabel {
    String pct(double v) {
      final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
      return '${s.replaceAll('.', ',')}%';
    }

    final partes = papeis
        .map((p) {
          final tipo = _participantLabel(p.participantType);
          final taxa = p.commissionRate == null
              ? ''
              : ' ${pct(p.commissionRate!)}';
          return '$tipo$taxa'.trim();
        })
        .where((s) => s.isNotEmpty)
        .toList();
    var out = partes.join(' · ');
    if (bonusRate != null && bonusRate! > 0) {
      out = '$out + ${pct(bonusRate!)} bônus'.trim();
    }
    return out;
  }
}

String _participantLabel(String? t) {
  switch ((t ?? '').toUpperCase()) {
    case 'CAPTADOR':
    case 'CAPTURER':
      return 'Captador';
    case 'VENDEDOR':
    case 'SELLER':
      return 'Vendedor';
    case 'GERENTE':
    case 'MANAGER':
      return 'Gerente';
    case 'INDICADOR':
    case 'REFERRER':
      return 'Indicador';
    case '':
      return '';
    default:
      final s = t!.toLowerCase().replaceAll('_', ' ');
      return '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

// ─── GET /commission-advances ───────────────────────────────────────────────

class CommissionAdvance {
  final String id;
  final String code;
  final String description;
  final double value;
  final double feePercent;
  final double feeValue;
  final double chargedValue;
  final String status;
  final String? createdAt;
  final String? approvedAt;
  final double? debitAmount;
  final double? debitSettled;
  final String? saleLabel;

  const CommissionAdvance({
    required this.id,
    required this.code,
    required this.status,
    this.description = '',
    this.value = 0,
    this.feePercent = 0,
    this.feeValue = 0,
    this.chargedValue = 0,
    this.createdAt,
    this.approvedAt,
    this.debitAmount,
    this.debitSettled,
    this.saleLabel,
  });

  /// Saldo restante a descontar: max(0, debit.amount − amountSettled).
  double? get saldoRestante {
    if (debitAmount == null) return null;
    final r = debitAmount! - (debitSettled ?? 0);
    return r < 0 ? 0 : r;
  }

  factory CommissionAdvance.fromJson(Map<String, dynamic> j) {
    final debit = j['debit'] is Map ? _map(j['debit']) : null;
    String? sale;
    final sales = j['sales'] is List ? j['sales'] as List : const [];
    final nomes = sales
        .whereType<Map>()
        .map((e) {
          final s = _map(_map(e)['sale']);
          return [
            _str(s['propertyName']),
            _str(s['unit']),
          ].whereType<String>().join(' · ');
        })
        .where((s) => s.isNotEmpty)
        .toList();
    if (nomes.isNotEmpty) {
      sale = nomes.length == 1
          ? nomes.first
          : '${nomes.first} +${nomes.length - 1}';
    } else if (j['sale'] is Map) {
      final s = _map(j['sale']);
      final n = [
        _str(s['propertyName']),
        _str(s['unit']),
      ].whereType<String>().join(' · ');
      sale = n.isEmpty ? null : n;
    }
    return CommissionAdvance(
      id: j['id']?.toString() ?? '',
      code: j['code']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      value: financeNum(j['value']),
      feePercent: financeNum(j['feePercent']),
      feeValue: financeNum(j['feeValue']),
      chargedValue: financeNum(j['chargedValue']),
      status: j['status']?.toString() ?? '',
      createdAt: _str(j['createdAt']),
      approvedAt: _str(j['approvedAt']),
      debitAmount: debit == null ? null : financeNum(debit['amount']),
      debitSettled: debit == null ? null : financeNum(debit['amountSettled']),
      saleLabel: sale,
    );
  }
}

/// `ADV_STATUS` (MeuFinanceiroPage.tsx:323). PAGO = "Em desconto".
String advanceStatusLabel(String s) {
  const labels = {
    'SOLICITADO': 'Solicitado',
    'APROVADO': 'Aprovado',
    'PAGO': 'Em desconto',
    'QUITADO': 'Quitado',
    'REPROVADO': 'Reprovado',
    'CANCELADO': 'Cancelado',
  };
  return labels[s] ?? s;
}

// ─── GET /requests ──────────────────────────────────────────────────────────

class RequestSummary {
  final String id;
  final String? code;
  final String title;
  final String status;
  final double amountRequested;
  final double? amountApproved;
  final String? createdAt;

  const RequestSummary({
    required this.id,
    required this.title,
    required this.status,
    this.code,
    this.amountRequested = 0,
    this.amountApproved,
    this.createdAt,
  });

  factory RequestSummary.fromJson(Map<String, dynamic> j) => RequestSummary(
    id: j['id']?.toString() ?? '',
    code: _str(j['code']),
    title: j['title']?.toString() ?? '',
    status: j['status']?.toString() ?? '',
    amountRequested: financeNum(j['amountRequested']),
    amountApproved: financeNumOrNull(j['amountApproved']),
    createdAt: _str(j['createdAt']),
  );
}

/// `solicitacoesFiltros.ts:22`.
String requestStatusLabel(String s) {
  const labels = {
    'PENDENTE': 'Pendente',
    'APROVADO': 'Aprovado',
    'REPROVADO': 'Reprovado',
    'EM_PROCESSAMENTO': 'Em processamento',
    'CONCLUIDO': 'Concluído',
    'CANCELADO': 'Cancelado',
  };
  return labels[s] ?? s;
}
