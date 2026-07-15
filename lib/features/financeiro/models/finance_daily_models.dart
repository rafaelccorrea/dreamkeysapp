/// Modelos do dia a dia financeiro (área DAILY):
/// contas a pagar, contas a receber, recorrentes, contas bancárias, cartões,
/// movimentos/extrato, transferências, cadastros (categorias, centros de
/// custo, fornecedores) e orçamento.
///
/// CONTRATO: espelha `imobx-front/src/types/financeiro.ts` (que espelha o
/// back financeiro-c3). Status são Strings cruas (tolerância a valores
/// novos) com constantes + labels pt-BR em classes `*Status`.
library;

import 'finance_common_models.dart';

// ═══════════════════════════════ CONTAS A PAGAR ══════════════════════════════

/// Status persistidos de conta a pagar. "Vencida" NÃO é status do banco —
/// é derivado (dueDate < hoje com status A_PAGAR/APROVADO).
class FinancePayableStatus {
  FinancePayableStatus._();

  static const aPagar = 'A_PAGAR';
  static const aprovado = 'APROVADO';
  static const pago = 'PAGO';
  static const cancelado = 'CANCELADO';

  static const values = [aPagar, aprovado, pago, cancelado];

  static String label(String status) => switch (status) {
        aPagar => 'A pagar',
        aprovado => 'Aprovado',
        pago => 'Pago',
        cancelado => 'Cancelado',
        _ => status,
      };
}

/// Classificação do título (enum PayableTipo). OUTROS exige tipoDescricao.
class FinancePayableTipo {
  FinancePayableTipo._();

  static const fornecedor = 'FORNECEDOR';
  static const interna = 'INTERNA';
  static const transferenciaInterna = 'TRANSFERENCIA_INTERNA';
  static const impostoTaxa = 'IMPOSTO_TAXA';
  static const outros = 'OUTROS';

  static const values = [
    fornecedor,
    interna,
    transferenciaInterna,
    impostoTaxa,
    outros,
  ];

  static String label(String tipo) => switch (tipo) {
        fornecedor => 'Fornecedor',
        interna => 'Interna',
        transferenciaInterna => 'Transferência interna',
        impostoTaxa => 'Imposto/Taxa',
        outros => 'Outros',
        _ => tipo,
      };
}

/// Meios de pagamento aceitos pelo back (enum PaymentMethod).
class FinancePaymentMethod {
  FinancePaymentMethod._();

  static const pix = 'PIX';
  static const ted = 'TED';
  static const transferencia = 'TRANSFERENCIA';
  static const boleto = 'BOLETO';
  static const dinheiro = 'DINHEIRO';
  static const cartaoCredito = 'CARTAO_CREDITO';
  static const cartaoDebito = 'CARTAO_DEBITO';

  static const values = [
    pix,
    ted,
    transferencia,
    boleto,
    dinheiro,
    cartaoCredito,
    cartaoDebito,
  ];

  static String label(String method) => switch (method) {
        pix => 'PIX',
        ted => 'TED',
        transferencia => 'Transferência',
        boleto => 'Boleto',
        dinheiro => 'Dinheiro',
        cartaoCredito => 'Cartão de crédito',
        cartaoDebito => 'Cartão de débito',
        _ => method,
      };
}

/// Linha do rateio entre empresas beneficiadas (Σ percent = 100).
/// `amount`/`company` só vêm na RESPOSTA; no envio basta companyId+percent.
class FinancePayableAllocation {
  final String companyId;
  final double percent;
  final double? amount;
  final FinanceRef? company;

  const FinancePayableAllocation({
    required this.companyId,
    required this.percent,
    this.amount,
    this.company,
  });

  factory FinancePayableAllocation.fromJson(Map<String, dynamic> json) =>
      FinancePayableAllocation(
        companyId: asString(json['companyId']),
        percent: asDouble(json['percent']),
        amount: asDoubleOrNull(json['amount']),
        company: FinanceRef.fromJsonOrNull(json['company']),
      );

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'percent': percent,
      };
}

/// Conta a pagar (GET /financial/payables).
class FinancePayable {
  final String id;

  /// Código legível CP-YYYY-NNNN; ausente em registros antigos.
  final String? code;
  final String companyId;
  final String? supplierId;
  final String? categoryId;
  final String? costCenterId;
  final String description;
  final String? documentNumber;
  final String? notes;
  final double amount;
  final DateTime? dueDate;
  final DateTime? competenciaDate;
  final String status;
  final String? bankAccountId;
  final DateTime? paidAt;
  final double? valorPago;
  final String? receiptUrl;
  final String? empresaBeneficiadaId;
  final String? meioPagamento;

  /// Classificação; ausente em respostas antigas (tratar como FORNECEDOR).
  final String? tipo;
  final String? tipoDescricao;

  /// Rateio; quando presente prevalece sobre empresaBeneficiadaId.
  final List<FinancePayableAllocation> allocations;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Objetos aninhados (INCLUDE do back) — read-only.
  final FinanceRef? company;
  final FinanceRef? supplier;
  final FinanceRef? category;
  final FinanceRef? costCenter;
  final FinanceRef? bankAccount;
  final FinanceRef? empresaBeneficiada;

  const FinancePayable({
    required this.id,
    this.code,
    required this.companyId,
    this.supplierId,
    this.categoryId,
    this.costCenterId,
    required this.description,
    this.documentNumber,
    this.notes,
    required this.amount,
    this.dueDate,
    this.competenciaDate,
    required this.status,
    this.bankAccountId,
    this.paidAt,
    this.valorPago,
    this.receiptUrl,
    this.empresaBeneficiadaId,
    this.meioPagamento,
    this.tipo,
    this.tipoDescricao,
    this.allocations = const [],
    this.createdAt,
    this.updatedAt,
    this.company,
    this.supplier,
    this.category,
    this.costCenter,
    this.bankAccount,
    this.empresaBeneficiada,
  });

  bool get isPaid => status == FinancePayableStatus.pago;
  bool get isCancelled => status == FinancePayableStatus.cancelado;

  /// "Vencida" derivada — mesmo critério do web (dueDate < hoje, em aberto).
  bool get isOverdue {
    if (isPaid || isCancelled || dueDate == null) return false;
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    return dueDate!.isBefore(d);
  }

  factory FinancePayable.fromJson(Map<String, dynamic> json) => FinancePayable(
        id: asString(json['id']),
        code: asStringOrNull(json['code']),
        companyId: asString(json['companyId']),
        supplierId: asStringOrNull(json['supplierId']),
        categoryId: asStringOrNull(json['categoryId']),
        costCenterId: asStringOrNull(json['costCenterId']),
        description: asString(json['description']),
        documentNumber: asStringOrNull(json['documentNumber']),
        notes: asStringOrNull(json['notes']),
        amount: asDouble(json['amount']),
        dueDate: asDate(json['dueDate']),
        competenciaDate: asDate(json['competenciaDate']),
        status: asString(json['status'], FinancePayableStatus.aPagar),
        bankAccountId: asStringOrNull(json['bankAccountId']),
        paidAt: asDate(json['paidAt']),
        valorPago: asDoubleOrNull(json['valorPago']),
        receiptUrl: asStringOrNull(json['receiptUrl']),
        empresaBeneficiadaId: asStringOrNull(json['empresaBeneficiadaId']),
        meioPagamento: asStringOrNull(json['meioPagamento']),
        tipo: asStringOrNull(json['tipo']),
        tipoDescricao: asStringOrNull(json['tipoDescricao']),
        allocations: asMapList(json['allocations'])
            .map(FinancePayableAllocation.fromJson)
            .toList(),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
        company: FinanceRef.fromJsonOrNull(json['company']),
        supplier: FinanceRef.fromJsonOrNull(json['supplier']),
        category: FinanceRef.fromJsonOrNull(json['category']),
        costCenter: FinanceRef.fromJsonOrNull(json['costCenter']),
        bankAccount: FinanceRef.fromJsonOrNull(json['bankAccount']),
        empresaBeneficiada:
            FinanceRef.fromJsonOrNull(json['empresaBeneficiada']),
      );
}

/// Filtros de GET /financial/payables.
/// ATENÇÃO: `status` é ÚNICO (o back valida @IsString — array dá 400).
class FinancePayableQuery {
  final String? status;
  final String? tipo;
  final String? companyId;
  final String? supplierId;
  final String? categoryId;
  final String? search;
  final DateTime? dueFrom;
  final DateTime? dueTo;
  final bool? overdueOnly;
  final int page;
  final int pageSize;

  const FinancePayableQuery({
    this.status,
    this.tipo,
    this.companyId,
    this.supplierId,
    this.categoryId,
    this.search,
    this.dueFrom,
    this.dueTo,
    this.overdueOnly,
    this.page = 1,
    this.pageSize = 20,
  });

  Map<String, String> toQueryParameters() {
    final params = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
    };
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (tipo != null && tipo!.isNotEmpty) params['tipo'] = tipo!;
    if (companyId != null && companyId!.isNotEmpty) {
      params['companyId'] = companyId!;
    }
    if (supplierId != null && supplierId!.isNotEmpty) {
      params['supplierId'] = supplierId!;
    }
    if (categoryId != null && categoryId!.isNotEmpty) {
      params['categoryId'] = categoryId!;
    }
    if (search != null && search!.trim().isNotEmpty) {
      params['search'] = search!.trim();
    }
    if (dueFrom != null) {
      params['dueFrom'] = dueFrom!.toIso8601String().substring(0, 10);
    }
    if (dueTo != null) {
      params['dueTo'] = dueTo!.toIso8601String().substring(0, 10);
    }
    if (overdueOnly == true) params['overdueOnly'] = 'true';
    return params;
  }
}

/// Body de POST /financial/payables e PATCH /financial/payables/:id.
/// No PATCH todos os campos são opcionais (enviar só o que mudou).
class FinancePayableInput {
  final String? companyId;
  final String? supplierId;
  final String? categoryId;
  final String? costCenterId;
  final String? description;
  final String? documentNumber;
  final String? notes;
  final double? amount;

  /// 'YYYY-MM-DD'.
  final String? dueDate;
  final String? competenciaDate;
  final String? bankAccountId;
  final String? empresaBeneficiadaId;
  final String? meioPagamento;
  final String? tipo;
  final String? tipoDescricao;
  final List<FinancePayableAllocation>? allocations;

  const FinancePayableInput({
    this.companyId,
    this.supplierId,
    this.categoryId,
    this.costCenterId,
    this.description,
    this.documentNumber,
    this.notes,
    this.amount,
    this.dueDate,
    this.competenciaDate,
    this.bankAccountId,
    this.empresaBeneficiadaId,
    this.meioPagamento,
    this.tipo,
    this.tipoDescricao,
    this.allocations,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'supplierId': supplierId,
        'categoryId': categoryId,
        'costCenterId': costCenterId,
        'description': description,
        'documentNumber': documentNumber,
        'notes': notes,
        'amount': amount,
        'dueDate': dueDate,
        'competenciaDate': competenciaDate,
        'bankAccountId': bankAccountId,
        'empresaBeneficiadaId': empresaBeneficiadaId,
        'meioPagamento': meioPagamento,
        'tipo': tipo,
        'tipoDescricao': tipoDescricao,
        'allocations': allocations?.map((a) => a.toJson()).toList(),
      });
}

/// Fatia de pagamento multi-banco (Σ amounts = valor pago).
class FinancePaySplit {
  final String bankAccountId;
  final double amount;

  const FinancePaySplit({required this.bankAccountId, required this.amount});

  Map<String, dynamic> toJson() => {
        'bankAccountId': bankAccountId,
        'amount': amount,
      };
}

/// Body de PATCH /financial/payables/:id/pay.
class FinancePayPayableInput {
  final String bankAccountId;

  /// ISO; default = agora no back.
  final String? paidAt;
  final String? receiptUrl;
  final String? empresaBeneficiadaId;
  final double? valorPago;

  /// Pagamento com mais de um banco (um BankMovement por fatia).
  final List<FinancePaySplit>? splits;

  const FinancePayPayableInput({
    required this.bankAccountId,
    this.paidAt,
    this.receiptUrl,
    this.empresaBeneficiadaId,
    this.valorPago,
    this.splits,
  });

  Map<String, dynamic> toJson() => compactBody({
        'bankAccountId': bankAccountId,
        'paidAt': paidAt,
        'receiptUrl': receiptUrl,
        'empresaBeneficiadaId': empresaBeneficiadaId,
        'valorPago': valorPago,
        'splits': splits?.map((s) => s.toJson()).toList(),
      });
}

// ═══════════════════════════ RECORRENTES (payables) ══════════════════════════

/// Frequências de recorrência (enum RecurrenceFrequency).
class FinanceRecurrenceFrequency {
  FinanceRecurrenceFrequency._();

  static const weekly = 'WEEKLY';
  static const monthly = 'MONTHLY';
  static const quarterly = 'QUARTERLY';
  static const yearly = 'YEARLY';

  static const values = [weekly, monthly, quarterly, yearly];

  static String label(String f) => switch (f) {
        weekly => 'Semanal',
        monthly => 'Mensal',
        quarterly => 'Trimestral',
        yearly => 'Anual',
        _ => f,
      };
}

/// Recorrência de conta a pagar (GET /financial/payables/recurring).
class FinanceRecurringPayable {
  final String id;
  final String companyId;
  final String? supplierId;
  final String? categoryId;
  final String? costCenterId;
  final String description;
  final double amount;
  final String frequency;
  final int? dayOfMonth;

  /// 0=Dom..6=Sáb; só quando frequency=WEEKLY.
  final int? dayOfWeek;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool active;
  final DateTime? nextRunDate;
  final String? notes;
  final FinanceRef? company;
  final FinanceRef? supplier;
  final FinanceRef? category;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceRecurringPayable({
    required this.id,
    required this.companyId,
    this.supplierId,
    this.categoryId,
    this.costCenterId,
    required this.description,
    required this.amount,
    required this.frequency,
    this.dayOfMonth,
    this.dayOfWeek,
    this.startDate,
    this.endDate,
    this.active = true,
    this.nextRunDate,
    this.notes,
    this.company,
    this.supplier,
    this.category,
    this.createdAt,
    this.updatedAt,
  });

  factory FinanceRecurringPayable.fromJson(Map<String, dynamic> json) =>
      FinanceRecurringPayable(
        id: asString(json['id']),
        companyId: asString(json['companyId']),
        supplierId: asStringOrNull(json['supplierId']),
        categoryId: asStringOrNull(json['categoryId']),
        costCenterId: asStringOrNull(json['costCenterId']),
        description: asString(json['description']),
        amount: asDouble(json['amount']),
        frequency: asString(
            json['frequency'], FinanceRecurrenceFrequency.monthly),
        dayOfMonth: asIntOrNull(json['dayOfMonth']),
        dayOfWeek: asIntOrNull(json['dayOfWeek']),
        startDate: asDate(json['startDate']),
        endDate: asDate(json['endDate']),
        active: asBool(json['active'], true),
        nextRunDate: asDate(json['nextRunDate']),
        notes: asStringOrNull(json['notes']),
        company: FinanceRef.fromJsonOrNull(json['company']),
        supplier: FinanceRef.fromJsonOrNull(json['supplier']),
        category: FinanceRef.fromJsonOrNull(json['category']),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
      );

  static List<FinanceRecurringPayable> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceRecurringPayable.fromJson).toList();
}

/// Body de POST/PATCH /financial/payables/recurring.
/// No PATCH inclui `active` (toggle de pausa).
class FinanceRecurringPayableInput {
  final String? companyId;
  final String? supplierId;
  final String? categoryId;
  final String? costCenterId;
  final String? description;
  final double? amount;
  final String? frequency;
  final int? dayOfMonth;
  final int? dayOfWeek;
  final String? startDate;
  final String? endDate;
  final bool? active;
  final String? notes;

  const FinanceRecurringPayableInput({
    this.companyId,
    this.supplierId,
    this.categoryId,
    this.costCenterId,
    this.description,
    this.amount,
    this.frequency,
    this.dayOfMonth,
    this.dayOfWeek,
    this.startDate,
    this.endDate,
    this.active,
    this.notes,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'supplierId': supplierId,
        'categoryId': categoryId,
        'costCenterId': costCenterId,
        'description': description,
        'amount': amount,
        'frequency': frequency,
        'dayOfMonth': dayOfMonth,
        'dayOfWeek': dayOfWeek,
        'startDate': startDate,
        'endDate': endDate,
        'active': active,
        'notes': notes,
      });
}

// ═══════════════════════════════ CONTAS A RECEBER ════════════════════════════

class FinanceReceivableStatus {
  FinanceReceivableStatus._();

  static const aReceber = 'A_RECEBER';
  static const recebido = 'RECEBIDO';
  static const cancelado = 'CANCELADO';

  static const values = [aReceber, recebido, cancelado];

  static String label(String status) => switch (status) {
        aReceber => 'A receber',
        recebido => 'Recebido',
        cancelado => 'Cancelado',
        _ => status,
      };
}

/// Rateio da conta a receber entre empresas (resposta traz amount/company).
class FinanceReceivableAllocation {
  final String companyId;
  final double percent;
  final double? amount;
  final FinanceRef? company;

  const FinanceReceivableAllocation({
    required this.companyId,
    required this.percent,
    this.amount,
    this.company,
  });

  factory FinanceReceivableAllocation.fromJson(Map<String, dynamic> json) =>
      FinanceReceivableAllocation(
        companyId: asString(json['companyId']),
        percent: asDouble(json['percent']),
        amount: asDoubleOrNull(json['amount']),
        company: FinanceRef.fromJsonOrNull(json['company']),
      );

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'percent': percent,
      };
}

/// Conta a receber (GET /financial/receivables).
class FinanceReceivable {
  final String id;

  /// Código legível CR-YYYY-NNNN.
  final String? code;
  final String companyId;
  final String? categoryId;
  final String? costCenterId;
  final String? bankAccountId;
  final String? customerName;
  final String description;
  final String? documentNumber;
  final double amount;
  final DateTime? dueDate;
  final DateTime? competenciaDate;
  final String status;
  final DateTime? receivedAt;
  final String? paymentMethod;
  final String? notes;

  /// Vínculo com parcela de venda (D-04) — habilita auto-repasse na baixa.
  final String? saleInstallmentId;
  final List<FinanceReceivableAllocation> allocations;
  final FinanceRef? company;
  final FinanceRef? category;
  final FinanceRef? costCenter;
  final FinanceRef? bankAccount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceReceivable({
    required this.id,
    this.code,
    required this.companyId,
    this.categoryId,
    this.costCenterId,
    this.bankAccountId,
    this.customerName,
    required this.description,
    this.documentNumber,
    required this.amount,
    this.dueDate,
    this.competenciaDate,
    required this.status,
    this.receivedAt,
    this.paymentMethod,
    this.notes,
    this.saleInstallmentId,
    this.allocations = const [],
    this.company,
    this.category,
    this.costCenter,
    this.bankAccount,
    this.createdAt,
    this.updatedAt,
  });

  bool get isReceived => status == FinanceReceivableStatus.recebido;
  bool get isCancelled => status == FinanceReceivableStatus.cancelado;

  bool get isOverdue {
    if (isReceived || isCancelled || dueDate == null) return false;
    final today = DateTime.now();
    return dueDate!.isBefore(DateTime(today.year, today.month, today.day));
  }

  factory FinanceReceivable.fromJson(Map<String, dynamic> json) =>
      FinanceReceivable(
        id: asString(json['id']),
        code: asStringOrNull(json['code']),
        companyId: asString(json['companyId']),
        categoryId: asStringOrNull(json['categoryId']),
        costCenterId: asStringOrNull(json['costCenterId']),
        bankAccountId: asStringOrNull(json['bankAccountId']),
        customerName: asStringOrNull(json['customerName']),
        description: asString(json['description']),
        documentNumber: asStringOrNull(json['documentNumber']),
        amount: asDouble(json['amount']),
        dueDate: asDate(json['dueDate']),
        competenciaDate: asDate(json['competenciaDate']),
        status: asString(json['status'], FinanceReceivableStatus.aReceber),
        receivedAt: asDate(json['receivedAt']),
        paymentMethod: asStringOrNull(json['paymentMethod']),
        notes: asStringOrNull(json['notes']),
        saleInstallmentId: asStringOrNull(json['saleInstallmentId']),
        allocations: asMapList(json['allocations'])
            .map(FinanceReceivableAllocation.fromJson)
            .toList(),
        company: FinanceRef.fromJsonOrNull(json['company']),
        category: FinanceRef.fromJsonOrNull(json['category']),
        costCenter: FinanceRef.fromJsonOrNull(json['costCenter']),
        bankAccount: FinanceRef.fromJsonOrNull(json['bankAccount']),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
      );
}

/// Filtros de GET /financial/receivables.
/// ATENÇÃO: o DTO do back usa forbidNonWhitelisted — NÃO enviar params extras.
class FinanceReceivableQuery {
  final String? status;
  final String? companyId;
  final String? categoryId;
  final String? costCenterId;
  final String? search;
  final DateTime? dueFrom;
  final DateTime? dueTo;
  final bool? overdueOnly;

  /// null em page/pageSize = back devolve array NU (sem envelope).
  final int? page;
  final int? pageSize;

  const FinanceReceivableQuery({
    this.status,
    this.companyId,
    this.categoryId,
    this.costCenterId,
    this.search,
    this.dueFrom,
    this.dueTo,
    this.overdueOnly,
    this.page = 1,
    this.pageSize = 20,
  });

  Map<String, String> toQueryParameters() {
    final params = <String, String>{};
    if (page != null) params['page'] = '$page';
    if (pageSize != null) params['pageSize'] = '$pageSize';
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (companyId != null && companyId!.isNotEmpty) {
      params['companyId'] = companyId!;
    }
    if (categoryId != null && categoryId!.isNotEmpty) {
      params['categoryId'] = categoryId!;
    }
    if (costCenterId != null && costCenterId!.isNotEmpty) {
      params['costCenterId'] = costCenterId!;
    }
    if (search != null && search!.trim().isNotEmpty) {
      params['search'] = search!.trim();
    }
    if (dueFrom != null) {
      params['dueFrom'] = dueFrom!.toIso8601String().substring(0, 10);
    }
    if (dueTo != null) {
      params['dueTo'] = dueTo!.toIso8601String().substring(0, 10);
    }
    if (overdueOnly == true) params['overdueOnly'] = 'true';
    return params;
  }
}

/// Body de POST /financial/receivables e PATCH /financial/receivables/:id.
/// No PATCH, `saleInstallmentId: ''` (string vazia) DESVINCULA a parcela.
class FinanceReceivableInput {
  final String? companyId;
  final String? categoryId;
  final String? costCenterId;
  final String? bankAccountId;
  final String? customerName;
  final String? description;
  final String? documentNumber;
  final double? amount;
  final String? dueDate;
  final String? competenciaDate;
  final String? notes;
  final String? saleInstallmentId;
  final List<FinanceReceivableAllocation>? allocations;

  const FinanceReceivableInput({
    this.companyId,
    this.categoryId,
    this.costCenterId,
    this.bankAccountId,
    this.customerName,
    this.description,
    this.documentNumber,
    this.amount,
    this.dueDate,
    this.competenciaDate,
    this.notes,
    this.saleInstallmentId,
    this.allocations,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'categoryId': categoryId,
        'costCenterId': costCenterId,
        'bankAccountId': bankAccountId,
        'customerName': customerName,
        'description': description,
        'documentNumber': documentNumber,
        'amount': amount,
        'dueDate': dueDate,
        'competenciaDate': competenciaDate,
        'notes': notes,
        'saleInstallmentId': saleInstallmentId,
        'allocations': allocations?.map((a) => a.toJson()).toList(),
      });
}

/// Body de POST /financial/receivables/from-installment (D-04).
/// Valor/vencimento/descrição derivam da parcela no back; idempotente.
class FinanceReceivableFromInstallmentInput {
  final String saleInstallmentId;
  final String companyId;
  final String? categoryId;
  final String? costCenterId;
  final String? bankAccountId;
  final String? customerName;
  final String? description;

  /// Fallback de vencimento quando a parcela não tem expectedDate.
  final String? dueDate;
  final String? competenciaDate;

  const FinanceReceivableFromInstallmentInput({
    required this.saleInstallmentId,
    required this.companyId,
    this.categoryId,
    this.costCenterId,
    this.bankAccountId,
    this.customerName,
    this.description,
    this.dueDate,
    this.competenciaDate,
  });

  Map<String, dynamic> toJson() => compactBody({
        'saleInstallmentId': saleInstallmentId,
        'companyId': companyId,
        'categoryId': categoryId,
        'costCenterId': costCenterId,
        'bankAccountId': bankAccountId,
        'customerName': customerName,
        'description': description,
        'dueDate': dueDate,
        'competenciaDate': competenciaDate,
      });
}

// ═══════════════════════════════ CONTAS BANCÁRIAS ════════════════════════════

class FinanceBankAccountType {
  FinanceBankAccountType._();

  static const checking = 'CHECKING';
  static const savings = 'SAVINGS';
  static const cash = 'CASH';
  static const investment = 'INVESTMENT';

  static const values = [checking, savings, cash, investment];

  static String label(String type) => switch (type) {
        checking => 'Conta corrente',
        savings => 'Poupança',
        cash => 'Caixa',
        investment => 'Investimento',
        _ => type,
      };
}

/// Conta bancária (GET /financial/bank-accounts).
class FinanceBankAccount {
  final String id;
  final String companyId;
  final String name;
  final String? bank;
  final String? agency;
  final String? accountNumber;
  final String? type;
  final bool active;
  final double? initialBalance;
  final double? currentBalance;
  final FinanceRef? company;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceBankAccount({
    required this.id,
    required this.companyId,
    required this.name,
    this.bank,
    this.agency,
    this.accountNumber,
    this.type,
    this.active = true,
    this.initialBalance,
    this.currentBalance,
    this.company,
    this.createdAt,
    this.updatedAt,
  });

  factory FinanceBankAccount.fromJson(Map<String, dynamic> json) =>
      FinanceBankAccount(
        id: asString(json['id']),
        companyId: asString(json['companyId']),
        name: asString(json['name']),
        bank: asStringOrNull(json['bank']),
        agency: asStringOrNull(json['agency']),
        accountNumber: asStringOrNull(json['accountNumber']),
        type: asStringOrNull(json['type']),
        active: asBool(json['active'], true),
        initialBalance: asDoubleOrNull(json['initialBalance']),
        currentBalance: asDoubleOrNull(json['currentBalance']),
        company: FinanceRef.fromJsonOrNull(json['company']),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
      );

  static List<FinanceBankAccount> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceBankAccount.fromJson).toList();
}

/// Body de POST/PATCH /financial/bank-accounts.
class FinanceBankAccountInput {
  final String? companyId;
  final String? name;
  final String? bank;
  final String? agency;
  final String? accountNumber;
  final String? type;
  final double? initialBalance;
  final bool? active;

  const FinanceBankAccountInput({
    this.companyId,
    this.name,
    this.bank,
    this.agency,
    this.accountNumber,
    this.type,
    this.initialBalance,
    this.active,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'name': name,
        'bank': bank,
        'agency': agency,
        'accountNumber': accountNumber,
        'type': type,
        'initialBalance': initialBalance,
        'active': active,
      });
}

// ═══════════════════════════════ CARTÕES DE CRÉDITO ══════════════════════════

/// Cartão de crédito (GET /financial/credit-cards).
class FinanceCreditCard {
  final String id;
  final String companyId;
  final String name;
  final String? bandeira;
  final String? lastDigits;
  final int? closingDay;
  final int dueDay;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceCreditCard({
    required this.id,
    required this.companyId,
    required this.name,
    this.bandeira,
    this.lastDigits,
    this.closingDay,
    required this.dueDay,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  factory FinanceCreditCard.fromJson(Map<String, dynamic> json) =>
      FinanceCreditCard(
        id: asString(json['id']),
        companyId: asString(json['companyId']),
        name: asString(json['name']),
        bandeira: asStringOrNull(json['bandeira']),
        lastDigits: asStringOrNull(json['lastDigits']),
        closingDay: asIntOrNull(json['closingDay']),
        dueDay: asInt(json['dueDay'], 1),
        active: asBool(json['active'], true),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
      );

  static List<FinanceCreditCard> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceCreditCard.fromJson).toList();
}

/// Body de POST/PATCH /financial/credit-cards.
class FinanceCreditCardInput {
  final String? companyId;
  final String? name;
  final String? bandeira;
  final String? lastDigits;
  final int? closingDay;
  final int? dueDay;
  final bool? active;

  const FinanceCreditCardInput({
    this.companyId,
    this.name,
    this.bandeira,
    this.lastDigits,
    this.closingDay,
    this.dueDay,
    this.active,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'name': name,
        'bandeira': bandeira,
        'lastDigits': lastDigits,
        'closingDay': closingDay,
        'dueDay': dueDay,
        'active': active,
      });
}

// ═══════════════════════════ MOVIMENTOS / EXTRATO ════════════════════════════

class FinanceMovementType {
  FinanceMovementType._();

  static const credit = 'CREDIT';
  static const debit = 'DEBIT';

  static String label(String type) => switch (type) {
        credit => 'Entrada',
        debit => 'Saída',
        _ => type,
      };
}

/// Origem do movimento (enum BankMovementSource).
class FinanceMovementSource {
  FinanceMovementSource._();

  static const manual = 'MANUAL';
  static const payable = 'PAYABLE';
  static const receivable = 'RECEIVABLE';
  static const transfer = 'TRANSFER';
  static const adjustment = 'ADJUSTMENT';

  static String label(String source) => switch (source) {
        manual => 'Manual',
        payable => 'Conta a pagar',
        receivable => 'Conta a receber',
        transfer => 'Transferência',
        adjustment => 'Ajuste',
        _ => source,
      };
}

/// Movimento do extrato (GET /financial/bank-accounts/:id/movements).
class FinanceMovement {
  final String id;
  final String bankAccountId;
  final String type;
  final double amount;
  final DateTime? date;
  final String? description;
  final String source;
  final double? balanceAfter;
  final FinanceRef? category;
  final FinanceRef? costCenter;
  final DateTime? createdAt;

  const FinanceMovement({
    required this.id,
    required this.bankAccountId,
    required this.type,
    required this.amount,
    this.date,
    this.description,
    required this.source,
    this.balanceAfter,
    this.category,
    this.costCenter,
    this.createdAt,
  });

  bool get isCredit => type == FinanceMovementType.credit;

  factory FinanceMovement.fromJson(Map<String, dynamic> json) =>
      FinanceMovement(
        id: asString(json['id']),
        bankAccountId: asString(json['bankAccountId']),
        type: asString(json['type'], FinanceMovementType.debit),
        amount: asDouble(json['amount']),
        date: asDate(json['date']),
        description: asStringOrNull(json['description']),
        source: asString(json['source'], FinanceMovementSource.manual),
        balanceAfter: asDoubleOrNull(json['balanceAfter']),
        category: FinanceRef.fromJsonOrNull(json['category']),
        costCenter: FinanceRef.fromJsonOrNull(json['costCenter']),
        createdAt: asDate(json['createdAt']),
      );

  static List<FinanceMovement> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceMovement.fromJson).toList();
}

/// Body de POST /financial/bank-accounts/:id/movements (movimento manual).
class FinanceMovementInput {
  final String type;
  final double amount;

  /// 'YYYY-MM-DD'.
  final String date;
  final String? description;
  final String? categoryId;
  final String? costCenterId;

  const FinanceMovementInput({
    required this.type,
    required this.amount,
    required this.date,
    this.description,
    this.categoryId,
    this.costCenterId,
  });

  Map<String, dynamic> toJson() => compactBody({
        'type': type,
        'amount': amount,
        'date': date,
        'description': description,
        'categoryId': categoryId,
        'costCenterId': costCenterId,
      });
}

/// Body de POST /financial/bank-accounts/transfer.
class FinanceTransferInput {
  final String fromAccountId;
  final String toAccountId;
  final double amount;
  final String date;
  final String? description;

  const FinanceTransferInput({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.date,
    this.description,
  });

  Map<String, dynamic> toJson() => compactBody({
        'fromAccountId': fromAccountId,
        'toAccountId': toAccountId,
        'amount': amount,
        'date': date,
        'description': description,
      });
}

// ═══════════════════════ CADASTROS (categorias/CC/fornecedores) ══════════════

class FinanceCategoryKind {
  FinanceCategoryKind._();

  static const revenue = 'REVENUE';
  static const expense = 'EXPENSE';

  static String label(String kind) => switch (kind) {
        revenue => 'Receita',
        expense => 'Despesa',
        _ => kind,
      };
}

/// Seções da DRE (enum DreSection do cadastro de categorias).
class FinanceDreSection {
  FinanceDreSection._();

  static const values = [
    'RECEITA_OPERACIONAL',
    'DEDUCOES',
    'CUSTO',
    'DESPESA_PESSOAL',
    'DESPESA_OPERACIONAL',
    'DESPESA_ADMINISTRATIVA',
    'DESPESA_FINANCEIRA',
    'RECEITA_FINANCEIRA',
    'OUTRAS_RECEITAS',
    'OUTRAS_DESPESAS',
  ];

  static String label(String section) => switch (section) {
        'RECEITA_OPERACIONAL' => 'Receita operacional',
        'DEDUCOES' => 'Deduções',
        'CUSTO' => 'Custo',
        'DESPESA_PESSOAL' => 'Despesa com pessoal',
        'DESPESA_OPERACIONAL' => 'Despesa operacional',
        'DESPESA_ADMINISTRATIVA' => 'Despesa administrativa',
        'DESPESA_FINANCEIRA' => 'Despesa financeira',
        'RECEITA_FINANCEIRA' => 'Receita financeira',
        'OUTRAS_RECEITAS' => 'Outras receitas',
        'OUTRAS_DESPESAS' => 'Outras despesas',
        _ => section,
      };
}

/// Categoria financeira (GET /financial/categories) — árvore via children.
class FinanceCategory {
  final String id;
  final String companyId;
  final String name;
  final String? code;

  /// REVENUE | EXPENSE (respostas antigas podem trazer 'receita'/'despesa'
  /// em `type` — normalizado aqui para kind).
  final String kind;
  final String? dreSection;
  final String? parentId;
  final int? order;
  final bool active;
  final List<FinanceCategory> children;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceCategory({
    required this.id,
    required this.companyId,
    required this.name,
    this.code,
    required this.kind,
    this.dreSection,
    this.parentId,
    this.order,
    this.active = true,
    this.children = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory FinanceCategory.fromJson(Map<String, dynamic> json) {
    var kind = asString(json['kind']);
    if (kind.isEmpty) {
      final legacy = asString(json['type']).toUpperCase();
      kind = legacy == 'RECEITA'
          ? FinanceCategoryKind.revenue
          : FinanceCategoryKind.expense;
    }
    return FinanceCategory(
      id: asString(json['id']),
      companyId: asString(json['companyId']),
      name: asString(json['name']),
      code: asStringOrNull(json['code']),
      kind: kind,
      dreSection: asStringOrNull(json['dreSection']),
      parentId: asStringOrNull(json['parentId']),
      order: asIntOrNull(json['order']),
      active: asBool(json['active'], true),
      children:
          asMapList(json['children']).map(FinanceCategory.fromJson).toList(),
      createdAt: asDate(json['createdAt']),
      updatedAt: asDate(json['updatedAt']),
    );
  }

  static List<FinanceCategory> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceCategory.fromJson).toList();
}

/// Body de POST/PATCH /financial/categories.
class FinanceCategoryInput {
  final String? name;
  final String? kind;
  final String? code;
  final String? dreSection;
  final String? parentId;
  final int? order;
  final bool? active;

  const FinanceCategoryInput({
    this.name,
    this.kind,
    this.code,
    this.dreSection,
    this.parentId,
    this.order,
    this.active,
  });

  Map<String, dynamic> toJson() => compactBody({
        'name': name,
        'kind': kind,
        'code': code,
        'dreSection': dreSection,
        'parentId': parentId,
        'order': order,
        'active': active,
      });
}

/// Centro de custo (GET /financial/cost-centers).
class FinanceCostCenter {
  final String id;
  final String companyId;
  final String name;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceCostCenter({
    required this.id,
    required this.companyId,
    required this.name,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  factory FinanceCostCenter.fromJson(Map<String, dynamic> json) =>
      FinanceCostCenter(
        id: asString(json['id']),
        companyId: asString(json['companyId']),
        name: asString(json['name']),
        active: asBool(json['active'], true),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
      );

  static List<FinanceCostCenter> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceCostCenter.fromJson).toList();
}

/// Fornecedor (GET /financial/suppliers).
class FinanceSupplier {
  final String id;
  final String companyId;
  final String name;
  final String? document;
  final String? email;
  final String? phone;
  final String? pixKey;
  final String? notes;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceSupplier({
    required this.id,
    required this.companyId,
    required this.name,
    this.document,
    this.email,
    this.phone,
    this.pixKey,
    this.notes,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  factory FinanceSupplier.fromJson(Map<String, dynamic> json) =>
      FinanceSupplier(
        id: asString(json['id']),
        companyId: asString(json['companyId']),
        name: asString(json['name']),
        document: asStringOrNull(json['document']),
        email: asStringOrNull(json['email']),
        phone: asStringOrNull(json['phone']),
        pixKey: asStringOrNull(json['pixKey']),
        notes: asStringOrNull(json['notes']),
        active: asBool(json['active'], true),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
      );

  static List<FinanceSupplier> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceSupplier.fromJson).toList();
}

/// Body de POST/PATCH /financial/suppliers.
class FinanceSupplierInput {
  final String? companyId;
  final String? name;
  final String? document;
  final String? email;
  final String? phone;
  final String? pixKey;
  final String? notes;
  final bool? active;

  const FinanceSupplierInput({
    this.companyId,
    this.name,
    this.document,
    this.email,
    this.phone,
    this.pixKey,
    this.notes,
    this.active,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'name': name,
        'document': document,
        'email': email,
        'phone': phone,
        'pixKey': pixKey,
        'notes': notes,
        'active': active,
      });
}

// ═══════════════════════════════════ ORÇAMENTO ═══════════════════════════════

class FinanceBudgetPeriod {
  FinanceBudgetPeriod._();

  static const anual = 'ANUAL';
  static const mensal = 'MENSAL';
  static const trimestral = 'TRIMESTRAL';

  static const values = [anual, mensal, trimestral];

  static String label(String period) => switch (period) {
        anual => 'Anual',
        mensal => 'Mensal',
        trimestral => 'Trimestral',
        _ => period,
      };
}

/// Status de consumo do orçamento (computado no back).
class FinanceBudgetStatus {
  FinanceBudgetStatus._();

  static const ok = 'OK';
  static const alerta = 'ALERTA';
  static const estourado = 'ESTOURADO';

  static String label(String status) => switch (status) {
        ok => 'Dentro do limite',
        alerta => 'Em alerta',
        estourado => 'Estourado',
        _ => status,
      };
}

/// Consumo do orçamento (computado no back a cada GET).
class FinanceBudgetConsumption {
  final double realized;
  final double committed;
  final double consumed;
  final double pct;
  final String status;

  const FinanceBudgetConsumption({
    this.realized = 0,
    this.committed = 0,
    this.consumed = 0,
    this.pct = 0,
    this.status = FinanceBudgetStatus.ok,
  });

  factory FinanceBudgetConsumption.fromJson(Map<String, dynamic> json) =>
      FinanceBudgetConsumption(
        realized: asDouble(json['realized']),
        committed: asDouble(json['committed']),
        consumed: asDouble(json['consumed']),
        pct: asDouble(json['pct']),
        status: asString(json['status'], FinanceBudgetStatus.ok),
      );
}

/// Orçamento (GET /financial/budgets).
class FinanceBudget {
  final String id;
  final String companyId;
  final String name;
  final String period;
  final int year;
  final int? month;
  final int? quarter;
  final double capAmount;
  final double? alertThreshold;
  final String? costCenterId;
  final String? categoryId;
  final FinanceRef? costCenter;
  final FinanceRef? category;
  final FinanceRef? company;
  final FinanceBudgetConsumption consumption;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceBudget({
    required this.id,
    required this.companyId,
    required this.name,
    required this.period,
    required this.year,
    this.month,
    this.quarter,
    required this.capAmount,
    this.alertThreshold,
    this.costCenterId,
    this.categoryId,
    this.costCenter,
    this.category,
    this.company,
    this.consumption = const FinanceBudgetConsumption(),
    this.createdAt,
    this.updatedAt,
  });

  factory FinanceBudget.fromJson(Map<String, dynamic> json) => FinanceBudget(
        id: asString(json['id']),
        companyId: asString(json['companyId']),
        name: asString(json['name']),
        period: asString(json['period'], FinanceBudgetPeriod.mensal),
        year: asInt(json['year'], DateTime.now().year),
        month: asIntOrNull(json['month']),
        quarter: asIntOrNull(json['quarter']),
        capAmount: asDouble(json['capAmount']),
        alertThreshold: asDoubleOrNull(json['alertThreshold']),
        costCenterId: asStringOrNull(json['costCenterId']),
        categoryId: asStringOrNull(json['categoryId']),
        costCenter: FinanceRef.fromJsonOrNull(json['costCenter']),
        category: FinanceRef.fromJsonOrNull(json['category']),
        company: FinanceRef.fromJsonOrNull(json['company']),
        consumption: FinanceBudgetConsumption.fromJson(
          asMap(json['consumption']),
        ),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
      );

  static List<FinanceBudget> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceBudget.fromJson).toList();
}

/// Body de POST/PATCH /financial/budgets.
class FinanceBudgetInput {
  final String? companyId;
  final String? name;
  final String? period;
  final int? year;
  final int? month;
  final int? quarter;
  final double? capAmount;
  final double? alertThreshold;
  final String? costCenterId;
  final String? categoryId;

  const FinanceBudgetInput({
    this.companyId,
    this.name,
    this.period,
    this.year,
    this.month,
    this.quarter,
    this.capAmount,
    this.alertThreshold,
    this.costCenterId,
    this.categoryId,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'name': name,
        'period': period,
        'year': year,
        'month': month,
        'quarter': quarter,
        'capAmount': capAmount,
        'alertThreshold': alertThreshold,
        'costCenterId': costCenterId,
        'categoryId': categoryId,
      });
}
