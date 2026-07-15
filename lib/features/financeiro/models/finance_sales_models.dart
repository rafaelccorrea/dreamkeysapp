/// Modelos da área de VENDAS do Financeiro:
/// fichas de venda (+parcelas e participantes), rateio/correção de comissões
/// D-01, pipeline/confissões de dívida (deals), comissões por tier, repasses
/// e equipes & tiers.
///
/// CONTRATO: espelha `imobx-front/src/types/financeiro.ts` (deals, comissões,
/// repasses, equipes) e `src/types/financeiroVendas.ts` (fichas de venda).
/// Dinheiro: Prisma.Decimal serializa como STRING — sempre [asDouble].
library;

import 'finance_common_models.dart';

// ═══════════════════════════ FICHAS DE VENDA (F-1) ═══════════════════════════

/// enum SaleStatus — compartilhado pela venda e pelas parcelas.
class FinanceSaleStatus {
  FinanceSaleStatus._();

  static const waitingForSignature = 'WAITING_FOR_SIGNATURE';
  static const emConferencia = 'EM_CONFERENCIA';
  static const pending = 'PENDING';
  static const received = 'RECEIVED';
  static const overdue = 'OVERDUE';
  static const cancelled = 'CANCELLED';

  static const values = [
    waitingForSignature,
    emConferencia,
    pending,
    received,
    overdue,
    cancelled,
  ];

  static String label(String status) => switch (status) {
        waitingForSignature => 'Aguardando assinatura',
        emConferencia => 'Em conferência',
        pending => 'A vencer',
        received => 'Recebido',
        overdue => 'Em atraso',
        cancelled => 'Cancelado',
        _ => status,
      };
}

/// enum SaleType.
class FinanceSaleType {
  FinanceSaleType._();

  static const terceiros = 'TERCEIROS';
  static const empreendimento = 'EMPREENDIMENTO';

  static String label(String type) => switch (type) {
        terceiros => 'Terceiros',
        empreendimento => 'Empreendimento',
        _ => type,
      };
}

/// enum ParticipantType — papel do participante na venda (8 valores do
/// Prisma; o webhook Intellisys cria todos, então round-trip precisa dos 8).
class FinanceParticipantType {
  FinanceParticipantType._();

  static const corretor = 'CORRETOR';
  static const gestor = 'GESTOR';
  static const diretor = 'DIRETOR';
  static const captador = 'CAPTADOR';
  static const atendente = 'ATENDENTE';
  static const gestorEmTreinamento = 'GESTOR_EM_TREINAMENTO';
  static const gerente = 'GERENTE';
  static const outros = 'OUTROS';

  static const values = [
    corretor,
    gestor,
    diretor,
    captador,
    atendente,
    gestorEmTreinamento,
    gerente,
    outros,
  ];

  static String label(String type) => switch (type) {
        corretor => 'Corretor',
        gestor => 'Gestor',
        diretor => 'Diretor',
        captador => 'Captador',
        atendente => 'Atendente',
        gestorEmTreinamento => 'Gestor em treinamento',
        gerente => 'Gerente',
        outros => 'Outros',
        _ => type,
      };
}

/// Empresa participante da venda (companies do SALE_INCLUDE).
class FinanceSaleCompanyLink {
  final double? sharePercentage;
  final FinanceRef company;

  const FinanceSaleCompanyLink({this.sharePercentage, required this.company});

  factory FinanceSaleCompanyLink.fromJson(Map<String, dynamic> json) =>
      FinanceSaleCompanyLink(
        sharePercentage: asDoubleOrNull(json['sharePercentage']),
        company: FinanceRef.fromJson(asMap(json['company'])),
      );
}

/// Comprador/vendedor da venda (SaleBuyer/SaleSeller — mesma linha).
class FinanceSaleParty {
  final String id;
  final bool isPrimary;
  final String name;
  final String? document;
  final String? rg;
  final DateTime? birthDate;
  final String? civilStatus;
  final String? profession;
  final String? email;
  final String? phone;
  final String? zipCode;
  final String? street;
  final String? addressNumber;
  final String? complement;
  final String? neighborhood;
  final String? city;
  final String? state;

  const FinanceSaleParty({
    required this.id,
    this.isPrimary = false,
    required this.name,
    this.document,
    this.rg,
    this.birthDate,
    this.civilStatus,
    this.profession,
    this.email,
    this.phone,
    this.zipCode,
    this.street,
    this.addressNumber,
    this.complement,
    this.neighborhood,
    this.city,
    this.state,
  });

  factory FinanceSaleParty.fromJson(Map<String, dynamic> json) =>
      FinanceSaleParty(
        id: asString(json['id']),
        isPrimary: asBool(json['isPrimary']),
        name: asString(json['name']),
        document: asStringOrNull(json['document']),
        rg: asStringOrNull(json['rg']),
        birthDate: asDate(json['birthDate']),
        civilStatus: asStringOrNull(json['civilStatus']),
        profession: asStringOrNull(json['profession']),
        email: asStringOrNull(json['email']),
        phone: asStringOrNull(json['phone']),
        zipCode: asStringOrNull(json['zipCode']),
        street: asStringOrNull(json['street']),
        addressNumber: asStringOrNull(json['addressNumber']),
        complement: asStringOrNull(json['complement']),
        neighborhood: asStringOrNull(json['neighborhood']),
        city: asStringOrNull(json['city']),
        state: asStringOrNull(json['state']),
      );
}

/// Participante (corretor & afins) da venda — SaleBroker + broker {id,name}.
class FinanceSaleBrokerLink {
  final String id;
  final String brokerId;
  final FinanceRef? broker;
  final String participantType;
  final double? commissionRate;
  final double? commissionValue;

  /// Empresa/unidade que o participante representa (vendas compartilhadas).
  final String? unitCompanyId;

  /// QP: fração do VGV atribuída (0–1).
  final double? proportionalQty;

  /// Snapshot cru D-01e — informativo, NÃO editar no front.
  final double? commissionValueCru;
  final double? commissionRateCru;

  const FinanceSaleBrokerLink({
    required this.id,
    required this.brokerId,
    this.broker,
    required this.participantType,
    this.commissionRate,
    this.commissionValue,
    this.unitCompanyId,
    this.proportionalQty,
    this.commissionValueCru,
    this.commissionRateCru,
  });

  factory FinanceSaleBrokerLink.fromJson(Map<String, dynamic> json) =>
      FinanceSaleBrokerLink(
        id: asString(json['id']),
        brokerId: asString(json['brokerId']),
        broker: FinanceRef.fromJsonOrNull(json['broker']),
        participantType: asString(
            json['participantType'], FinanceParticipantType.corretor),
        commissionRate: asDoubleOrNull(json['commissionRate']),
        commissionValue: asDoubleOrNull(json['commissionValue']),
        unitCompanyId: asStringOrNull(json['unitCompanyId']),
        proportionalQty: asDoubleOrNull(json['proportionalQty']),
        commissionValueCru: asDoubleOrNull(json['commissionValueCru']),
        commissionRateCru: asDoubleOrNull(json['commissionRateCru']),
      );
}

/// Comissão de participante POR PARCELA (SaleInstallmentBroker).
class FinanceInstallmentBrokerLink {
  final String id;
  final String installmentId;
  final String brokerId;
  final FinanceRef? broker;
  final String participantType;
  final double? commissionRate;
  final double commissionValue;

  /// Valor ajustado pelo rateio D-01 (quando aplicado).
  final double? adjustedCommissionValue;
  final double? proportionalQty;
  final DateTime? paidAt;

  const FinanceInstallmentBrokerLink({
    required this.id,
    required this.installmentId,
    required this.brokerId,
    this.broker,
    required this.participantType,
    this.commissionRate,
    required this.commissionValue,
    this.adjustedCommissionValue,
    this.proportionalQty,
    this.paidAt,
  });

  factory FinanceInstallmentBrokerLink.fromJson(Map<String, dynamic> json) =>
      FinanceInstallmentBrokerLink(
        id: asString(json['id']),
        installmentId: asString(json['installmentId']),
        brokerId: asString(json['brokerId']),
        broker: FinanceRef.fromJsonOrNull(json['broker']),
        participantType: asString(
            json['participantType'], FinanceParticipantType.corretor),
        commissionRate: asDoubleOrNull(json['commissionRate']),
        commissionValue: asDouble(json['commissionValue']),
        adjustedCommissionValue:
            asDoubleOrNull(json['adjustedCommissionValue']),
        proportionalQty: asDoubleOrNull(json['proportionalQty']),
        paidAt: asDate(json['paidAt']),
      );
}

/// Parcela da venda (SaleInstallment + brokerLinks).
class FinanceSaleInstallment {
  final String id;
  final String saleId;

  /// Código legível RCB-YYYY-NNNN.
  final String receiptId;
  final int installmentNumber;
  final double value;
  final DateTime? expectedDate;
  final DateTime? actualDate;
  final DateTime? transferDate;
  final String? receiptMethod;
  final String? paymentMethod;
  final bool hasInvoice;
  final DateTime? invoiceDate;
  final String status;
  final DateTime? cancelledAt;
  final String? notes;
  final List<FinanceInstallmentBrokerLink> brokerLinks;

  const FinanceSaleInstallment({
    required this.id,
    required this.saleId,
    required this.receiptId,
    required this.installmentNumber,
    required this.value,
    this.expectedDate,
    this.actualDate,
    this.transferDate,
    this.receiptMethod,
    this.paymentMethod,
    this.hasInvoice = false,
    this.invoiceDate,
    required this.status,
    this.cancelledAt,
    this.notes,
    this.brokerLinks = const [],
  });

  bool get isReceived => status == FinanceSaleStatus.received;

  factory FinanceSaleInstallment.fromJson(Map<String, dynamic> json) =>
      FinanceSaleInstallment(
        id: asString(json['id']),
        saleId: asString(json['saleId']),
        receiptId: asString(json['receiptId']),
        installmentNumber: asInt(json['installmentNumber'], 1),
        value: asDouble(json['value']),
        expectedDate: asDate(json['expectedDate']),
        actualDate: asDate(json['actualDate']),
        transferDate: asDate(json['transferDate']),
        receiptMethod: asStringOrNull(json['receiptMethod']),
        paymentMethod: asStringOrNull(json['paymentMethod']),
        hasInvoice: asBool(json['hasInvoice']),
        invoiceDate: asDate(json['invoiceDate']),
        status: asString(json['status'], FinanceSaleStatus.pending),
        cancelledAt: asDate(json['cancelledAt']),
        notes: asStringOrNull(json['notes']),
        brokerLinks: asMapList(json['brokerLinks'])
            .map(FinanceInstallmentBrokerLink.fromJson)
            .toList(),
      );
}

/// Ficha de venda completa — GET /sales e GET /sales/:id (SALE_INCLUDE).
/// `id` é o código legível VND-YYYY-NNNN.
class FinanceSale {
  final String id;
  final String? unit;
  final String? fichaVenda;
  final String? fichaExternalId;
  final DateTime? saleDate;
  final DateTime? processStart;
  final String? saleType;
  final String? propertyAddress;
  final String? propertyName;
  final String? developer;
  final String? paymentTerms;
  final double? entryValue;
  final DateTime? entryDate;
  final String? propertyPortfolio;
  final String? originMedia;
  final double vgvGross;
  final double? goalValue;
  final double? totalCommission;
  final double? vgcTotal;
  final double? commissionRate;
  final int installmentCount;
  final double? installmentValue;
  final String? receiptMethod;
  final String? paymentMethod;
  final String? costCenter;
  final String? costCenterId;
  final String? notes;
  final String status;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<FinanceSaleCompanyLink> companies;
  final List<FinanceSaleParty> buyers;
  final List<FinanceSaleParty> sellers;
  final List<FinanceSaleBrokerLink> brokers;

  /// IDs das confissões de dívida vivas ligadas à venda.
  final List<String> dealIds;
  final List<FinanceSaleInstallment> installments;

  const FinanceSale({
    required this.id,
    this.unit,
    this.fichaVenda,
    this.fichaExternalId,
    this.saleDate,
    this.processStart,
    this.saleType,
    this.propertyAddress,
    this.propertyName,
    this.developer,
    this.paymentTerms,
    this.entryValue,
    this.entryDate,
    this.propertyPortfolio,
    this.originMedia,
    required this.vgvGross,
    this.goalValue,
    this.totalCommission,
    this.vgcTotal,
    this.commissionRate,
    this.installmentCount = 0,
    this.installmentValue,
    this.receiptMethod,
    this.paymentMethod,
    this.costCenter,
    this.costCenterId,
    this.notes,
    required this.status,
    this.cancelledAt,
    this.createdAt,
    this.updatedAt,
    this.companies = const [],
    this.buyers = const [],
    this.sellers = const [],
    this.brokers = const [],
    this.dealIds = const [],
    this.installments = const [],
  });

  bool get isCancelled => status == FinanceSaleStatus.cancelled;

  factory FinanceSale.fromJson(Map<String, dynamic> json) => FinanceSale(
        id: asString(json['id']),
        unit: asStringOrNull(json['unit']),
        fichaVenda: asStringOrNull(json['fichaVenda']),
        fichaExternalId: asStringOrNull(json['fichaExternalId']),
        saleDate: asDate(json['saleDate']),
        processStart: asDate(json['processStart']),
        saleType: asStringOrNull(json['saleType']),
        propertyAddress: asStringOrNull(json['propertyAddress']),
        propertyName: asStringOrNull(json['propertyName']),
        developer: asStringOrNull(json['developer']),
        paymentTerms: asStringOrNull(json['paymentTerms']),
        entryValue: asDoubleOrNull(json['entryValue']),
        entryDate: asDate(json['entryDate']),
        propertyPortfolio: asStringOrNull(json['propertyPortfolio']),
        originMedia: asStringOrNull(json['originMedia']),
        vgvGross: asDouble(json['vgvGross']),
        goalValue: asDoubleOrNull(json['goalValue']),
        totalCommission: asDoubleOrNull(json['totalCommission']),
        vgcTotal: asDoubleOrNull(json['vgcTotal']),
        commissionRate: asDoubleOrNull(json['commissionRate']),
        installmentCount: asInt(json['installmentCount']),
        installmentValue: asDoubleOrNull(json['installmentValue']),
        receiptMethod: asStringOrNull(json['receiptMethod']),
        paymentMethod: asStringOrNull(json['paymentMethod']),
        costCenter: asStringOrNull(json['costCenter']),
        costCenterId: asStringOrNull(json['costCenterId']),
        notes: asStringOrNull(json['notes']),
        status: asString(json['status'], FinanceSaleStatus.pending),
        cancelledAt: asDate(json['cancelledAt']),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
        companies: asMapList(json['companies'])
            .map(FinanceSaleCompanyLink.fromJson)
            .toList(),
        buyers:
            asMapList(json['buyers']).map(FinanceSaleParty.fromJson).toList(),
        sellers:
            asMapList(json['sellers']).map(FinanceSaleParty.fromJson).toList(),
        brokers: asMapList(json['brokers'])
            .map(FinanceSaleBrokerLink.fromJson)
            .toList(),
        dealIds: asMapList(json['deals'])
            .map((d) => asString(d['id']))
            .where((id) => id.isNotEmpty)
            .toList(),
        installments: asMapList(json['installments'])
            .map(FinanceSaleInstallment.fromJson)
            .toList(),
      );
}

/// Filtros de GET /sales (SaleListQueryDto). page+pageSize sempre enviados
/// pelo service para receber o envelope `{data,total,page,pageSize}`.
class FinanceSaleQuery {
  final String? search;
  final String? status;
  final String? companyId;

  /// 'YYYY-MM-DD' — o back fecha o dia no dateTo.
  final String? dateFrom;
  final String? dateTo;
  final int page;

  /// Máx 100 (PaginationDto do back).
  final int pageSize;

  const FinanceSaleQuery({
    this.search,
    this.status,
    this.companyId,
    this.dateFrom,
    this.dateTo,
    this.page = 1,
    this.pageSize = 20,
  });

  Map<String, String> toQueryParameters() {
    final params = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
    };
    if (search != null && search!.trim().isNotEmpty) {
      params['search'] = search!.trim();
    }
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (companyId != null && companyId!.isNotEmpty) {
      params['companyId'] = companyId!;
    }
    if (dateFrom != null && dateFrom!.isNotEmpty) {
      params['dateFrom'] = dateFrom!;
    }
    if (dateTo != null && dateTo!.isNotEmpty) params['dateTo'] = dateTo!;
    return params;
  }
}

/// Comprador no envio (buyers de POST/PATCH /sales).
class FinanceSaleBuyerInput {
  final bool isPrimary;
  final String name;
  final String? document;
  final String? birthDate;
  final String? email;
  final String? phone;

  const FinanceSaleBuyerInput({
    required this.isPrimary,
    required this.name,
    this.document,
    this.birthDate,
    this.email,
    this.phone,
  });

  Map<String, dynamic> toJson() => compactBody({
        'isPrimary': isPrimary,
        'name': name,
        'document': document,
        'birthDate': birthDate,
        'email': email,
        'phone': phone,
      });
}

/// Vendedor no envio (sellers de POST/PATCH /sales).
class FinanceSaleSellerInput {
  final String name;
  final String? document;
  final String? birthDate;
  final String? email;
  final String? phone;

  const FinanceSaleSellerInput({
    required this.name,
    this.document,
    this.birthDate,
    this.email,
    this.phone,
  });

  Map<String, dynamic> toJson() => compactBody({
        'name': name,
        'document': document,
        'birthDate': birthDate,
        'email': email,
        'phone': phone,
      });
}

/// Participante no envio (brokers de POST/PATCH /sales).
class FinanceSaleBrokerInput {
  final String brokerId;
  final String? participantType;
  final double? commissionRate;
  final double? commissionValue;
  final String? unitCompanyId;
  final double? proportionalQty;

  const FinanceSaleBrokerInput({
    required this.brokerId,
    this.participantType,
    this.commissionRate,
    this.commissionValue,
    this.unitCompanyId,
    this.proportionalQty,
  });

  Map<String, dynamic> toJson() => compactBody({
        'brokerId': brokerId,
        'participantType': participantType,
        'commissionRate': commissionRate,
        'commissionValue': commissionValue,
        'unitCompanyId': unitCompanyId,
        'proportionalQty': proportionalQty,
      });
}

/// Empresa no envio (companies de POST/PATCH /sales).
class FinanceSaleCompanyShareInput {
  final String companyId;
  final double? commissionValue;
  final double? sharePercentage;

  const FinanceSaleCompanyShareInput({
    required this.companyId,
    this.commissionValue,
    this.sharePercentage,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'commissionValue': commissionValue,
        'sharePercentage': sharePercentage,
      });
}

/// Body de POST /sales e PATCH /sales/:id (CreateSaleDto/UpdateSaleDto).
///
/// ATENÇÃO (regras do back):
///  - enviar buyers/sellers/brokers/companies SUBSTITUI as listas inteiras;
///  - mudar installmentCount REGENERA as parcelas e APAGA os repasses da venda;
///  - POST exige saleDate, vgvGross, buyers, sellers, brokers.
class FinanceSaleInput {
  final List<String>? companyIds;
  final List<FinanceSaleCompanyShareInput>? companies;
  final String? fichaVenda;
  final String? unit;
  final String? saleDate;
  final String? processStart;
  final String? saleType;
  final String? propertyAddress;
  final String? propertyName;
  final String? developer;
  final String? paymentTerms;
  final double? entryValue;
  final String? entryDate;
  final String? propertyPortfolio;
  final String? originMedia;
  final double? vgvGross;
  final double? vgcTotal;
  final double? commissionRate;
  final int? installmentCount;
  final double? installmentValue;
  final String? firstInstallmentDate;
  final String? receiptMethod;
  final String? paymentMethod;
  final String? costCenter;
  final String? notes;
  final String? status;
  final List<FinanceSaleBuyerInput>? buyers;
  final List<FinanceSaleSellerInput>? sellers;
  final List<FinanceSaleBrokerInput>? brokers;

  const FinanceSaleInput({
    this.companyIds,
    this.companies,
    this.fichaVenda,
    this.unit,
    this.saleDate,
    this.processStart,
    this.saleType,
    this.propertyAddress,
    this.propertyName,
    this.developer,
    this.paymentTerms,
    this.entryValue,
    this.entryDate,
    this.propertyPortfolio,
    this.originMedia,
    this.vgvGross,
    this.vgcTotal,
    this.commissionRate,
    this.installmentCount,
    this.installmentValue,
    this.firstInstallmentDate,
    this.receiptMethod,
    this.paymentMethod,
    this.costCenter,
    this.notes,
    this.status,
    this.buyers,
    this.sellers,
    this.brokers,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyIds': companyIds,
        'companies': companies?.map((c) => c.toJson()).toList(),
        'fichaVenda': fichaVenda,
        'unit': unit,
        'saleDate': saleDate,
        'processStart': processStart,
        'saleType': saleType,
        'propertyAddress': propertyAddress,
        'propertyName': propertyName,
        'developer': developer,
        'paymentTerms': paymentTerms,
        'entryValue': entryValue,
        'entryDate': entryDate,
        'propertyPortfolio': propertyPortfolio,
        'originMedia': originMedia,
        'vgvGross': vgvGross,
        'vgcTotal': vgcTotal,
        'commissionRate': commissionRate,
        'installmentCount': installmentCount,
        'installmentValue': installmentValue,
        'firstInstallmentDate': firstInstallmentDate,
        'receiptMethod': receiptMethod,
        'paymentMethod': paymentMethod,
        'costCenter': costCenter,
        'notes': notes,
        'status': status,
        'buyers': buyers?.map((b) => b.toJson()).toList(),
        'sellers': sellers?.map((s) => s.toJson()).toList(),
        'brokers': brokers?.map((b) => b.toJson()).toList(),
      });
}

/// Body de PATCH /sales/:id/installments/:installmentId
/// (UpdateInstallmentDto). NÃO existe campo `value` — valor de parcela só
/// muda regenerando o cronograma no PATCH da venda.
/// String vazia ('') em actualDate/transferDate/invoiceDate LIMPA a data.
class FinanceSaleInstallmentInput {
  final String? expectedDate;
  final String? actualDate;
  final String? transferDate;
  final String? receiptMethod;
  final String? paymentMethod;
  final bool? hasInvoice;
  final String? invoiceDate;
  final String? status;
  final String? notes;

  const FinanceSaleInstallmentInput({
    this.expectedDate,
    this.actualDate,
    this.transferDate,
    this.receiptMethod,
    this.paymentMethod,
    this.hasInvoice,
    this.invoiceDate,
    this.status,
    this.notes,
  });

  Map<String, dynamic> toJson() => compactBody({
        'expectedDate': expectedDate,
        'actualDate': actualDate,
        'transferDate': transferDate,
        'receiptMethod': receiptMethod,
        'paymentMethod': paymentMethod,
        'hasInvoice': hasInvoice,
        'invoiceDate': invoiceDate,
        'status': status,
        'notes': notes,
      });
}

// ═══════════════════ RATEIO / CORREÇÃO DE COMISSÕES (D-01) ═══════════════════

/// Fatia do rateio D-01 (CommissionShareExtended).
/// `id` = SaleBroker.id (tipo 'broker') ou SaleCompany.id (tipo 'company').
class FinanceCommissionShare {
  final String id;

  /// Valor bruto proporcional, sem arredondamento.
  final double cru;

  /// Valor após o arredondamento D-01 (pessoas a R$1; casa absorve residual).
  final double ajustado;
  final double pctCru;
  final double pctAjustado;
  final bool isHouse;

  /// 'broker' | 'company'.
  final String tipo;
  final String participanteId;

  const FinanceCommissionShare({
    required this.id,
    required this.cru,
    required this.ajustado,
    required this.pctCru,
    required this.pctAjustado,
    required this.isHouse,
    required this.tipo,
    required this.participanteId,
  });

  factory FinanceCommissionShare.fromJson(Map<String, dynamic> json) =>
      FinanceCommissionShare(
        id: asString(json['id']),
        cru: asDouble(json['cru']),
        ajustado: asDouble(json['ajustado']),
        pctCru: asDouble(json['pctCru']),
        pctAjustado: asDouble(json['pctAjustado']),
        isHouse: asBool(json['isHouse']),
        tipo: asString(json['tipo'], 'broker'),
        participanteId: asString(json['participanteId']),
      );
}

/// POST /sales/:id/commissions/rateio — calcula E PERSISTE o rateio D-01.
class FinanceCommissionRateioResult {
  final String saleId;
  final double vgcTotal;
  final List<FinanceCommissionShare> shares;

  const FinanceCommissionRateioResult({
    required this.saleId,
    required this.vgcTotal,
    this.shares = const [],
  });

  factory FinanceCommissionRateioResult.fromJson(Map<String, dynamic> json) =>
      FinanceCommissionRateioResult(
        saleId: asString(json['saleId']),
        vgcTotal: asDouble(json['vgcTotal']),
        shares: asMapList(json['shares'])
            .map(FinanceCommissionShare.fromJson)
            .toList(),
      );
}

/// Linha da aba de correção: original (cru) vs ajustado por recebedor.
/// `papel` = ParticipantType do broker ou 'CASA'.
/// `origem` 'recomputado' = venda legada sem snapshot cru.
class FinanceCommissionCorrectionItem {
  final String id;
  final String nome;
  final String papel;
  final double valorCru;
  final double pctCru;
  final double valorAjustado;
  final double pctAjustado;
  final bool ehCasa;
  final double delta;
  final String origem;

  const FinanceCommissionCorrectionItem({
    required this.id,
    required this.nome,
    required this.papel,
    required this.valorCru,
    required this.pctCru,
    required this.valorAjustado,
    required this.pctAjustado,
    required this.ehCasa,
    required this.delta,
    required this.origem,
  });

  factory FinanceCommissionCorrectionItem.fromJson(
          Map<String, dynamic> json) =>
      FinanceCommissionCorrectionItem(
        id: asString(json['id']),
        nome: asString(json['nome']),
        papel: asString(json['papel']),
        valorCru: asDouble(json['valorCru']),
        pctCru: asDouble(json['pctCru']),
        valorAjustado: asDouble(json['valorAjustado']),
        pctAjustado: asDouble(json['pctAjustado']),
        ehCasa: asBool(json['ehCasa']),
        delta: asDouble(json['delta']),
        origem: asString(json['origem'], 'persistido'),
      );
}

/// GET /sales/:id/commissions/correction — read-only.
class FinanceCommissionCorrectionView {
  final String saleId;
  final double vgcTotal;
  final List<FinanceCommissionCorrectionItem> items;

  const FinanceCommissionCorrectionView({
    required this.saleId,
    required this.vgcTotal,
    this.items = const [],
  });

  factory FinanceCommissionCorrectionView.fromJson(
          Map<String, dynamic> json) =>
      FinanceCommissionCorrectionView(
        saleId: asString(json['saleId']),
        vgcTotal: asDouble(json['vgcTotal']),
        items: asMapList(json['items'])
            .map(FinanceCommissionCorrectionItem.fromJson)
            .toList(),
      );
}

// ═══════════════════ PIPELINE / CONFISSÕES DE DÍVIDA (deals) ═════════════════

/// Etapas do pipeline (enum FinanceDealStage).
class FinanceDealStage {
  FinanceDealStage._();

  static const closedContract = 'CLOSED_CONTRACT';
  static const engineeringPayment = 'ENGINEERING_PAYMENT';
  static const ibtiRegistryDeed = 'IBTI_REGISTRY_DEED';
  static const debtReceived = 'DEBT_RECEIVED';

  static const values = [
    closedContract,
    engineeringPayment,
    ibtiRegistryDeed,
    debtReceived,
  ];

  static String label(String stage) => switch (stage) {
        closedContract => 'Contrato fechado',
        engineeringPayment => 'Pagamento engenharia',
        ibtiRegistryDeed => 'ITBI/Registro/Escritura',
        debtReceived => 'Dívida recebida',
        _ => stage,
      };
}

class FinanceCashFlowType {
  FinanceCashFlowType._();

  static const cost = 'COST';
  static const revenue = 'REVENUE';

  static String label(String type) => switch (type) {
        cost => 'Custo',
        revenue => 'Receita',
        _ => type,
      };
}

/// Lançamento de fluxo de caixa do processo.
class FinanceDealCashFlow {
  final String id;
  final String type;
  final double amount;
  final String? description;
  final DateTime? date;
  final String? stage;

  const FinanceDealCashFlow({
    required this.id,
    required this.type,
    required this.amount,
    this.description,
    this.date,
    this.stage,
  });

  factory FinanceDealCashFlow.fromJson(Map<String, dynamic> json) =>
      FinanceDealCashFlow(
        id: asString(json['id']),
        type: asString(json['type'], FinanceCashFlowType.cost),
        amount: asDouble(json['amount']),
        description: asStringOrNull(json['description']),
        date: asDate(json['date']),
        stage: asStringOrNull(json['stage']),
      );
}

/// Pagamento do cliente no processo.
class FinanceDealClientPayment {
  final String id;
  final double amount;
  final DateTime? date;
  final String? description;

  const FinanceDealClientPayment({
    required this.id,
    required this.amount,
    this.date,
    this.description,
  });

  factory FinanceDealClientPayment.fromJson(Map<String, dynamic> json) =>
      FinanceDealClientPayment(
        id: asString(json['id']),
        amount: asDouble(json['amount']),
        date: asDate(json['date']),
        description: asStringOrNull(json['description']),
      );
}

/// Entrada do histórico de etapas — `user` só vem no detalhe.
class FinanceDealStageHistoryEntry {
  final String id;
  final String stage;
  final DateTime? enteredAt;
  final String? notes;
  final String? userName;

  const FinanceDealStageHistoryEntry({
    required this.id,
    required this.stage,
    this.enteredAt,
    this.notes,
    this.userName,
  });

  factory FinanceDealStageHistoryEntry.fromJson(Map<String, dynamic> json) =>
      FinanceDealStageHistoryEntry(
        id: asString(json['id']),
        stage: asString(json['stage'], FinanceDealStage.closedContract),
        enteredAt: asDate(json['enteredAt']),
        notes: asStringOrNull(json['notes']),
        userName: asStringOrNull(asMap(json['user'])['name']),
      );
}

/// Processo (confissão de dívida) — shape da lista GET /sales/deals.
/// Na lista o include traz broker {name} (sem id — usar brokerId escalar),
/// stageHistory take:1 desc e cashFlows/clientPayments enxutos.
class FinanceDeal {
  final String id;
  final String companyId;
  final String? brokerId;
  final String stage;
  final double saleValue;
  final double? propertyValue;
  final double? debtPercentage;
  final String? debtorName;
  final String? debtorDoc;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final DateTime? cancelledAt;
  final DateTime? completedAt;
  final DateTime? saleContractDate;
  final DateTime? confessionSignatureDate;
  final bool allCostsLocked;
  final double? clientPaidAmount;
  final double? refundAmount;
  final double? clientOwesAmount;
  final DateTime? refundDueDate;
  final DateTime? refundPaidAt;
  final double? operationFee;
  final String? brokerName;
  final List<FinanceDealStageHistoryEntry> stageHistory;
  final List<FinanceDealCashFlow> cashFlows;
  final List<FinanceDealClientPayment> clientPayments;

  const FinanceDeal({
    required this.id,
    required this.companyId,
    this.brokerId,
    required this.stage,
    required this.saleValue,
    this.propertyValue,
    this.debtPercentage,
    this.debtorName,
    this.debtorDoc,
    this.notes,
    this.createdAt,
    this.closedAt,
    this.cancelledAt,
    this.completedAt,
    this.saleContractDate,
    this.confessionSignatureDate,
    this.allCostsLocked = false,
    this.clientPaidAmount,
    this.refundAmount,
    this.clientOwesAmount,
    this.refundDueDate,
    this.refundPaidAt,
    this.operationFee,
    this.brokerName,
    this.stageHistory = const [],
    this.cashFlows = const [],
    this.clientPayments = const [],
  });

  bool get isArchived => cancelledAt != null || completedAt != null;

  factory FinanceDeal.fromJson(Map<String, dynamic> json) => FinanceDeal(
        id: asString(json['id']),
        companyId: asString(json['companyId']),
        brokerId: asStringOrNull(json['brokerId']),
        stage: asString(json['stage'], FinanceDealStage.closedContract),
        saleValue: asDouble(json['saleValue']),
        propertyValue: asDoubleOrNull(json['propertyValue']),
        debtPercentage: asDoubleOrNull(json['debtPercentage']),
        debtorName: asStringOrNull(json['debtorName']),
        debtorDoc: asStringOrNull(json['debtorDoc']),
        notes: asStringOrNull(json['notes']),
        createdAt: asDate(json['createdAt']),
        closedAt: asDate(json['closedAt']),
        cancelledAt: asDate(json['cancelledAt']),
        completedAt: asDate(json['completedAt']),
        saleContractDate: asDate(json['saleContractDate']),
        confessionSignatureDate: asDate(json['confessionSignatureDate']),
        allCostsLocked: asBool(json['allCostsLocked']),
        clientPaidAmount: asDoubleOrNull(json['clientPaidAmount']),
        refundAmount: asDoubleOrNull(json['refundAmount']),
        clientOwesAmount: asDoubleOrNull(json['clientOwesAmount']),
        refundDueDate: asDate(json['refundDueDate']),
        refundPaidAt: asDate(json['refundPaidAt']),
        operationFee: asDoubleOrNull(json['operationFee']),
        brokerName: asStringOrNull(asMap(json['broker'])['name']),
        stageHistory: asMapList(json['stageHistory'])
            .map(FinanceDealStageHistoryEntry.fromJson)
            .toList(),
        cashFlows: asMapList(json['cashFlows'])
            .map(FinanceDealCashFlow.fromJson)
            .toList(),
        clientPayments: asMapList(json['clientPayments'])
            .map(FinanceDealClientPayment.fromJson)
            .toList(),
      );

  static List<FinanceDeal> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceDeal.fromJson).toList();
}

/// Detalhe do processo — GET /sales/deals/:id (stageHistory asc, com user).
class FinanceDealDetail extends FinanceDeal {
  final String? buyerName;
  final String? buyerDoc;
  final String? addressStreet;
  final String? addressNumber;
  final String? addressComplement;
  final String? addressNeighborhood;
  final String? addressCondominium;
  final FinanceRef? company;
  final FinanceRef? broker;

  const FinanceDealDetail({
    required super.id,
    required super.companyId,
    super.brokerId,
    required super.stage,
    required super.saleValue,
    super.propertyValue,
    super.debtPercentage,
    super.debtorName,
    super.debtorDoc,
    super.notes,
    super.createdAt,
    super.closedAt,
    super.cancelledAt,
    super.completedAt,
    super.saleContractDate,
    super.confessionSignatureDate,
    super.allCostsLocked,
    super.clientPaidAmount,
    super.refundAmount,
    super.clientOwesAmount,
    super.refundDueDate,
    super.refundPaidAt,
    super.operationFee,
    super.brokerName,
    super.stageHistory,
    super.cashFlows,
    super.clientPayments,
    this.buyerName,
    this.buyerDoc,
    this.addressStreet,
    this.addressNumber,
    this.addressComplement,
    this.addressNeighborhood,
    this.addressCondominium,
    this.company,
    this.broker,
  });

  factory FinanceDealDetail.fromJson(Map<String, dynamic> json) {
    final base = FinanceDeal.fromJson(json);
    final broker = FinanceRef.fromJsonOrNull(json['broker']);
    return FinanceDealDetail(
      id: base.id,
      companyId: base.companyId,
      brokerId: base.brokerId,
      stage: base.stage,
      saleValue: base.saleValue,
      propertyValue: base.propertyValue,
      debtPercentage: base.debtPercentage,
      debtorName: base.debtorName,
      debtorDoc: base.debtorDoc,
      notes: base.notes,
      createdAt: base.createdAt,
      closedAt: base.closedAt,
      cancelledAt: base.cancelledAt,
      completedAt: base.completedAt,
      saleContractDate: base.saleContractDate,
      confessionSignatureDate: base.confessionSignatureDate,
      allCostsLocked: base.allCostsLocked,
      clientPaidAmount: base.clientPaidAmount,
      refundAmount: base.refundAmount,
      clientOwesAmount: base.clientOwesAmount,
      refundDueDate: base.refundDueDate,
      refundPaidAt: base.refundPaidAt,
      operationFee: base.operationFee,
      brokerName: broker?.name ?? base.brokerName,
      stageHistory: base.stageHistory,
      cashFlows: base.cashFlows,
      clientPayments: base.clientPayments,
      buyerName: asStringOrNull(json['buyerName']),
      buyerDoc: asStringOrNull(json['buyerDoc']),
      addressStreet: asStringOrNull(json['addressStreet']),
      addressNumber: asStringOrNull(json['addressNumber']),
      addressComplement: asStringOrNull(json['addressComplement']),
      addressNeighborhood: asStringOrNull(json['addressNeighborhood']),
      addressCondominium: asStringOrNull(json['addressCondominium']),
      company: FinanceRef.fromJsonOrNull(json['company']),
      broker: broker,
    );
  }
}

/// Contagem/valor por etapa (byStage do pipeline-stats).
class FinanceStageStat {
  final int count;
  final double value;

  const FinanceStageStat({this.count = 0, this.value = 0});

  factory FinanceStageStat.fromJson(Map<String, dynamic> json) =>
      FinanceStageStat(
        count: asInt(json['count']),
        value: asDouble(json['value']),
      );
}

/// GET /sales/deals/pipeline-stats — métricas já computadas no back.
class FinancePipelineStats {
  final int totalDeals;
  final double totalValue;
  final double? avgReceiptDays;
  final double? roi;
  final double totalCosts;
  final double totalRevenue;
  final double operationFee;
  final double operationFeeRevenue;

  /// Receita líquida da operação = Σ taxas fixas dos contratos.
  final double netRevenue;
  final double totalPendingRefunds;
  final int pendingRefundCount;
  final Map<String, FinanceStageStat> byStage;
  final int? openCount;
  final int? closedCount;
  final double? openAmount;
  final double? feesReceived;
  final double? feesToReceive;
  final double? weightedAvgReceiptDays;
  final double? forecastDocs;
  final double? forecastFees;
  final DateTime? forecastAvgDate;

  const FinancePipelineStats({
    this.totalDeals = 0,
    this.totalValue = 0,
    this.avgReceiptDays,
    this.roi,
    this.totalCosts = 0,
    this.totalRevenue = 0,
    this.operationFee = 0,
    this.operationFeeRevenue = 0,
    this.netRevenue = 0,
    this.totalPendingRefunds = 0,
    this.pendingRefundCount = 0,
    this.byStage = const {},
    this.openCount,
    this.closedCount,
    this.openAmount,
    this.feesReceived,
    this.feesToReceive,
    this.weightedAvgReceiptDays,
    this.forecastDocs,
    this.forecastFees,
    this.forecastAvgDate,
  });

  factory FinancePipelineStats.fromJson(Map<String, dynamic> json) {
    final byStage = <String, FinanceStageStat>{};
    asMap(json['byStage']).forEach((key, value) {
      byStage[key] = FinanceStageStat.fromJson(asMap(value));
    });
    return FinancePipelineStats(
      totalDeals: asInt(json['totalDeals']),
      totalValue: asDouble(json['totalValue']),
      avgReceiptDays: asDoubleOrNull(json['avgReceiptDays']),
      roi: asDoubleOrNull(json['roi']),
      totalCosts: asDouble(json['totalCosts']),
      totalRevenue: asDouble(json['totalRevenue']),
      operationFee: asDouble(json['operationFee']),
      operationFeeRevenue: asDouble(json['operationFeeRevenue']),
      netRevenue: asDouble(json['netRevenue']),
      totalPendingRefunds: asDouble(json['totalPendingRefunds']),
      pendingRefundCount: asInt(json['pendingRefundCount']),
      byStage: byStage,
      openCount: asIntOrNull(json['openCount']),
      closedCount: asIntOrNull(json['closedCount']),
      openAmount: asDoubleOrNull(json['openAmount']),
      feesReceived: asDoubleOrNull(json['feesReceived']),
      feesToReceive: asDoubleOrNull(json['feesToReceive']),
      weightedAvgReceiptDays: asDoubleOrNull(json['weightedAvgReceiptDays']),
      forecastDocs: asDoubleOrNull(json['forecastDocs']),
      forecastFees: asDoubleOrNull(json['forecastFees']),
      forecastAvgDate: asDate(json['forecastAvgDate']),
    );
  }
}

/// Body de POST /sales/deals e PATCH /sales/deals/:id (CreateDealDto).
class FinanceDealInput {
  final String? companyId;
  final String? debtorName;
  final String? debtorDoc;
  final String? buyerName;
  final String? buyerDoc;
  final String? brokerId;
  final double? propertyValue;
  final double? debtPercentage;
  final double? saleValue;
  final String? saleContractDate;
  final String? confessionSignatureDate;
  final String? addressStreet;
  final String? addressNumber;
  final String? addressComplement;
  final String? addressNeighborhood;
  final String? addressCondominium;
  final String? notes;

  const FinanceDealInput({
    this.companyId,
    this.debtorName,
    this.debtorDoc,
    this.buyerName,
    this.buyerDoc,
    this.brokerId,
    this.propertyValue,
    this.debtPercentage,
    this.saleValue,
    this.saleContractDate,
    this.confessionSignatureDate,
    this.addressStreet,
    this.addressNumber,
    this.addressComplement,
    this.addressNeighborhood,
    this.addressCondominium,
    this.notes,
  });

  Map<String, dynamic> toJson() => compactBody({
        'companyId': companyId,
        'debtorName': debtorName,
        'debtorDoc': debtorDoc,
        'buyerName': buyerName,
        'buyerDoc': buyerDoc,
        'brokerId': brokerId,
        'propertyValue': propertyValue,
        'debtPercentage': debtPercentage,
        'saleValue': saleValue,
        'saleContractDate': saleContractDate,
        'confessionSignatureDate': confessionSignatureDate,
        'addressStreet': addressStreet,
        'addressNumber': addressNumber,
        'addressComplement': addressComplement,
        'addressNeighborhood': addressNeighborhood,
        'addressCondominium': addressCondominium,
        'notes': notes,
      });
}

// ═══════════════════════════ COMISSÕES POR TIER (B5) ═════════════════════════

/// Status da comissão por tier (CALCULATED → APPROVED → PAID).
class FinanceTierCommissionStatus {
  FinanceTierCommissionStatus._();

  static const calculated = 'CALCULATED';
  static const approved = 'APPROVED';
  static const paid = 'PAID';

  static const values = [calculated, approved, paid];

  static String label(String status) => switch (status) {
        calculated => 'Calculada',
        approved => 'Aprovada',
        paid => 'Paga',
        _ => status,
      };
}

/// Comissão calculada sobre um processo do pipeline
/// (GET /sales/commissions). NÃO confundir com a Commission nativa do CRM
/// (lib/features/commissions) — esta é do módulo financeiro.
class FinanceTierCommission {
  final String id;
  final String companyId;
  final String dealId;
  final String brokerId;
  final double grossValue;
  final double ratePercent;
  final String status;
  final DateTime? approvedAt;
  final DateTime? paidAt;
  final String? notes;
  final DateTime? createdAt;
  final String brokerName;

  /// Resumo do deal incluído na resposta.
  final double dealSaleValue;
  final String dealStage;
  final String? dealDebtorName;
  final String? dealAddress;

  const FinanceTierCommission({
    required this.id,
    required this.companyId,
    required this.dealId,
    required this.brokerId,
    required this.grossValue,
    required this.ratePercent,
    required this.status,
    this.approvedAt,
    this.paidAt,
    this.notes,
    this.createdAt,
    this.brokerName = '',
    this.dealSaleValue = 0,
    this.dealStage = '',
    this.dealDebtorName,
    this.dealAddress,
  });

  factory FinanceTierCommission.fromJson(Map<String, dynamic> json) {
    final deal = asMap(json['deal']);
    final property = asMap(deal['property']);
    final street = asStringOrNull(deal['addressStreet']);
    final number = asStringOrNull(deal['addressNumber']);
    final address = asStringOrNull(property['address']) ??
        (street != null
            ? [street, number].whereType<String>().join(', ')
            : null);
    return FinanceTierCommission(
      id: asString(json['id']),
      companyId: asString(json['companyId']),
      dealId: asString(json['dealId']),
      brokerId: asString(json['brokerId']),
      grossValue: asDouble(json['grossValue']),
      ratePercent: asDouble(json['ratePercent']),
      status:
          asString(json['status'], FinanceTierCommissionStatus.calculated),
      approvedAt: asDate(json['approvedAt']),
      paidAt: asDate(json['paidAt']),
      notes: asStringOrNull(json['notes']),
      createdAt: asDate(json['createdAt']),
      brokerName: asString(asMap(json['broker'])['name']),
      dealSaleValue: asDouble(deal['saleValue']),
      dealStage: asString(deal['stage']),
      dealDebtorName: asStringOrNull(deal['debtorName']),
      dealAddress: address,
    );
  }

  static List<FinanceTierCommission> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceTierCommission.fromJson).toList();
}

// ═══════════════════════════════════ REPASSES ════════════════════════════════

class FinanceRepasseStatus {
  FinanceRepasseStatus._();

  static const waitingForSignature = 'WAITING_FOR_SIGNATURE';
  static const emConferencia = 'EM_CONFERENCIA';
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const paid = 'PAID';

  static const values = [
    waitingForSignature,
    emConferencia,
    pending,
    approved,
    paid,
  ];

  static String label(String status) => switch (status) {
        waitingForSignature => 'Aguardando assinatura',
        emConferencia => 'Em conferência',
        pending => 'Pendente',
        approved => 'Aprovado',
        paid => 'Pago',
        _ => status,
      };
}

/// Referência enxuta à venda dentro do repasse.
class FinanceRepasseSaleRef {
  final String id;
  final String? fichaVenda;
  final String? propertyAddress;
  final DateTime? saleDate;
  final String? unit;

  const FinanceRepasseSaleRef({
    required this.id,
    this.fichaVenda,
    this.propertyAddress,
    this.saleDate,
    this.unit,
  });

  factory FinanceRepasseSaleRef.fromJson(Map<String, dynamic> json) =>
      FinanceRepasseSaleRef(
        id: asString(json['id']),
        fichaVenda: asStringOrNull(json['fichaVenda']),
        propertyAddress: asStringOrNull(json['propertyAddress']),
        saleDate: asDate(json['saleDate']),
        unit: asStringOrNull(json['unit']),
      );
}

/// Referência enxuta à parcela dentro do repasse.
class FinanceRepasseInstallmentRef {
  final String id;
  final String? receiptId;
  final int? installmentNumber;
  final double? value;

  const FinanceRepasseInstallmentRef({
    required this.id,
    this.receiptId,
    this.installmentNumber,
    this.value,
  });

  factory FinanceRepasseInstallmentRef.fromJson(Map<String, dynamic> json) =>
      FinanceRepasseInstallmentRef(
        id: asString(json['id']),
        receiptId: asStringOrNull(json['receiptId']),
        installmentNumber: asIntOrNull(json['installmentNumber']),
        value: asDoubleOrNull(json['value']),
      );
}

/// Repasse de comissão a corretor (GET /repasses).
class FinanceRepasse {
  final String id;
  final String saleId;
  final FinanceRepasseSaleRef? sale;
  final String? installmentId;
  final FinanceRepasseInstallmentRef? installment;
  final String? brokerId;
  final FinanceRef? broker;
  final String? companyId;
  final FinanceRef? company;
  final String? responsibleId;
  final FinanceRef? responsible;
  final double commissionValue;
  final double? commissionRate;
  final String status;
  final DateTime? approvedAt;
  final DateTime? paidAt;
  final String? paymentMethod;
  final bool isAdvanced;
  final double? advancedValue;
  final double? advanceFeePercent;
  final double? advanceFeeValue;
  final DateTime? advancedAt;
  final String? notes;
  final String? costCenter;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FinanceRepasse({
    required this.id,
    required this.saleId,
    this.sale,
    this.installmentId,
    this.installment,
    this.brokerId,
    this.broker,
    this.companyId,
    this.company,
    this.responsibleId,
    this.responsible,
    required this.commissionValue,
    this.commissionRate,
    required this.status,
    this.approvedAt,
    this.paidAt,
    this.paymentMethod,
    this.isAdvanced = false,
    this.advancedValue,
    this.advanceFeePercent,
    this.advanceFeeValue,
    this.advancedAt,
    this.notes,
    this.costCenter,
    this.createdAt,
    this.updatedAt,
  });

  factory FinanceRepasse.fromJson(Map<String, dynamic> json) => FinanceRepasse(
        id: asString(json['id']),
        saleId: asString(json['saleId']),
        sale: json['sale'] is Map
            ? FinanceRepasseSaleRef.fromJson(asMap(json['sale']))
            : null,
        installmentId: asStringOrNull(json['installmentId']),
        installment: json['installment'] is Map
            ? FinanceRepasseInstallmentRef.fromJson(asMap(json['installment']))
            : null,
        brokerId: asStringOrNull(json['brokerId']),
        broker: FinanceRef.fromJsonOrNull(json['broker']),
        companyId: asStringOrNull(json['companyId']),
        company: FinanceRef.fromJsonOrNull(json['company']),
        responsibleId: asStringOrNull(json['responsibleId']),
        responsible: FinanceRef.fromJsonOrNull(json['responsible']),
        commissionValue: asDouble(json['commissionValue']),
        commissionRate: asDoubleOrNull(json['commissionRate']),
        status: asString(json['status'], FinanceRepasseStatus.pending),
        approvedAt: asDate(json['approvedAt']),
        paidAt: asDate(json['paidAt']),
        paymentMethod: asStringOrNull(json['paymentMethod']),
        isAdvanced: asBool(json['isAdvanced']),
        advancedValue: asDoubleOrNull(json['advancedValue']),
        advanceFeePercent: asDoubleOrNull(json['advanceFeePercent']),
        advanceFeeValue: asDoubleOrNull(json['advanceFeeValue']),
        advancedAt: asDate(json['advancedAt']),
        notes: asStringOrNull(json['notes']),
        costCenter: asStringOrNull(json['costCenter']),
        createdAt: asDate(json['createdAt']),
        updatedAt: asDate(json['updatedAt']),
      );
}

/// Filtros de GET /repasses.
class FinanceRepasseQuery {
  final String? search;
  final String? status;
  final String? brokerId;
  final String? saleId;
  final String? companyId;
  final String? dateFrom;
  final String? dateTo;
  final int page;
  final int pageSize;

  const FinanceRepasseQuery({
    this.search,
    this.status,
    this.brokerId,
    this.saleId,
    this.companyId,
    this.dateFrom,
    this.dateTo,
    this.page = 1,
    this.pageSize = 20,
  });

  Map<String, String> toQueryParameters() {
    final params = <String, String>{
      'page': '$page',
      'pageSize': '$pageSize',
    };
    if (search != null && search!.trim().isNotEmpty) {
      params['search'] = search!.trim();
    }
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (brokerId != null && brokerId!.isNotEmpty) {
      params['brokerId'] = brokerId!;
    }
    if (saleId != null && saleId!.isNotEmpty) params['saleId'] = saleId!;
    if (companyId != null && companyId!.isNotEmpty) {
      params['companyId'] = companyId!;
    }
    if (dateFrom != null && dateFrom!.isNotEmpty) {
      params['dateFrom'] = dateFrom!;
    }
    if (dateTo != null && dateTo!.isNotEmpty) params['dateTo'] = dateTo!;
    return params;
  }
}

/// Body de PATCH /repasses/:id (edição pontual).
class FinanceRepasseInput {
  final String? installmentId;
  final String? brokerId;
  final String? responsibleId;
  final double? commissionValue;
  final double? commissionRate;
  final String? status;
  final String? approvedAt;
  final String? paidAt;
  final String? paymentMethod;
  final bool? isAdvanced;
  final String? notes;
  final String? costCenter;

  const FinanceRepasseInput({
    this.installmentId,
    this.brokerId,
    this.responsibleId,
    this.commissionValue,
    this.commissionRate,
    this.status,
    this.approvedAt,
    this.paidAt,
    this.paymentMethod,
    this.isAdvanced,
    this.notes,
    this.costCenter,
  });

  Map<String, dynamic> toJson() => compactBody({
        'installmentId': installmentId,
        'brokerId': brokerId,
        'responsibleId': responsibleId,
        'commissionValue': commissionValue,
        'commissionRate': commissionRate,
        'status': status,
        'approvedAt': approvedAt,
        'paidAt': paidAt,
        'paymentMethod': paymentMethod,
        'isAdvanced': isAdvanced,
        'notes': notes,
        'costCenter': costCenter,
      });
}

/// Body de POST /repasses/:id/advance —
/// `advancedValue` XOR `advancedPercent` (mutuamente exclusivos).
class FinanceAdvanceRepasseInput {
  final double? advancedValue;
  final double? advancedPercent;
  final double? feePercent;
  final String? advancedAt;
  final String? paymentMethod;
  final String? notes;

  const FinanceAdvanceRepasseInput({
    this.advancedValue,
    this.advancedPercent,
    this.feePercent,
    this.advancedAt,
    this.paymentMethod,
    this.notes,
  });

  Map<String, dynamic> toJson() => compactBody({
        'advancedValue': advancedValue,
        'advancedPercent': advancedPercent,
        'feePercent': feePercent,
        'advancedAt': advancedAt,
        'paymentMethod': paymentMethod,
        'notes': notes,
      });
}

/// Body de PATCH /repasses/bulk (aprovar/pagar em lote).
class FinanceBulkRepasseInput {
  final List<String> ids;
  final String status;
  final String? paidAt;
  final String? paymentMethod;
  final String? responsibleId;

  const FinanceBulkRepasseInput({
    required this.ids,
    required this.status,
    this.paidAt,
    this.paymentMethod,
    this.responsibleId,
  });

  Map<String, dynamic> toJson() => compactBody({
        'ids': ids,
        'status': status,
        'paidAt': paidAt,
        'paymentMethod': paymentMethod,
        'responsibleId': responsibleId,
      });
}

// ═══════════════════════════ EQUIPES & TIERS (B4) ════════════════════════════

/// Tiers de comissionamento.
class FinanceBrokerTier {
  FinanceBrokerTier._();

  static const silver = 'SILVER';
  static const gold = 'GOLD';
  static const diamond = 'DIAMOND';

  static const values = [silver, gold, diamond];

  static String label(String tier) => switch (tier) {
        silver => 'Prata',
        gold => 'Ouro',
        diamond => 'Diamante',
        _ => tier,
      };
}

/// Membro da equipe (lista GET /teams).
class FinanceTeamMember {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;

  const FinanceTeamMember({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
  });

  factory FinanceTeamMember.fromJson(Map<String, dynamic> json) {
    final user = asMap(json['user']);
    return FinanceTeamMember(
      id: asString(json['id']),
      userId: asString(user['id']),
      userName: asString(user['name']),
      userEmail: asString(user['email']),
    );
  }
}

/// Equipe de comissionamento (GET /teams). Rates/minValues por tier.
class FinanceTeam {
  final String id;
  final String name;
  final String companyId;
  final String? directorId;
  final FinanceRef? director;
  final String? gestorId;
  final FinanceRef? gestor;
  final double silverRate;
  final double silverMinValue;
  final double goldRate;
  final double goldMinValue;
  final double diamondRate;
  final double diamondMinValue;
  final List<FinanceTeamMember> members;
  final String? companyName;

  const FinanceTeam({
    required this.id,
    required this.name,
    required this.companyId,
    this.directorId,
    this.director,
    this.gestorId,
    this.gestor,
    this.silverRate = 0,
    this.silverMinValue = 0,
    this.goldRate = 0,
    this.goldMinValue = 0,
    this.diamondRate = 0,
    this.diamondMinValue = 0,
    this.members = const [],
    this.companyName,
  });

  factory FinanceTeam.fromJson(Map<String, dynamic> json) => FinanceTeam(
        id: asString(json['id']),
        name: asString(json['name']),
        companyId: asString(json['companyId']),
        directorId: asStringOrNull(json['directorId']),
        director: FinanceRef.fromJsonOrNull(json['director']),
        gestorId: asStringOrNull(json['gestorId']),
        gestor: FinanceRef.fromJsonOrNull(json['gestor']),
        silverRate: asDouble(json['silverRate']),
        silverMinValue: asDouble(json['silverMinValue']),
        goldRate: asDouble(json['goldRate']),
        goldMinValue: asDouble(json['goldMinValue']),
        diamondRate: asDouble(json['diamondRate']),
        diamondMinValue: asDouble(json['diamondMinValue']),
        members: asMapList(json['members'])
            .map(FinanceTeamMember.fromJson)
            .toList(),
        companyName: asStringOrNull(asMap(json['company'])['name']),
      );

  static List<FinanceTeam> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceTeam.fromJson).toList();
}

/// Linha de GET /teams/summary (VGV/VGC por equipe no período).
class FinanceTeamSummaryItem {
  final String teamId;
  final String teamName;
  final String companyId;
  final String? directorId;
  final String? directorName;
  final int memberCount;
  final double vgv;
  final double vgc;

  const FinanceTeamSummaryItem({
    required this.teamId,
    required this.teamName,
    required this.companyId,
    this.directorId,
    this.directorName,
    this.memberCount = 0,
    this.vgv = 0,
    this.vgc = 0,
  });

  factory FinanceTeamSummaryItem.fromJson(Map<String, dynamic> json) =>
      FinanceTeamSummaryItem(
        teamId: asString(json['teamId']),
        teamName: asString(json['teamName']),
        companyId: asString(json['companyId']),
        directorId: asStringOrNull(json['directorId']),
        directorName: asStringOrNull(json['directorName']),
        memberCount: asInt(json['memberCount']),
        vgv: asDouble(json['vgv']),
        vgc: asDouble(json['vgc']),
      );
}

/// GET /teams/summary.
class FinanceTeamsSummary {
  final double totalVgv;
  final double totalVgc;
  final List<FinanceTeamSummaryItem> byTeam;
  final List<int> months;
  final int year;

  const FinanceTeamsSummary({
    this.totalVgv = 0,
    this.totalVgc = 0,
    this.byTeam = const [],
    this.months = const [],
    this.year = 0,
  });

  factory FinanceTeamsSummary.fromJson(Map<String, dynamic> json) =>
      FinanceTeamsSummary(
        totalVgv: asDouble(json['totalVgv']),
        totalVgc: asDouble(json['totalVgc']),
        byTeam: asMapList(json['byTeam'])
            .map(FinanceTeamSummaryItem.fromJson)
            .toList(),
        months: (json['months'] is List)
            ? (json['months'] as List).map((m) => asInt(m)).toList()
            : const [],
        year: asInt(json['year'], DateTime.now().year),
      );
}

/// Movimentação de tier (histórico de corretor, diretor ou gestor).
class FinanceTierHistory {
  final String id;
  final String? fromTier;
  final String toTier;
  final String type;
  final String? reason;
  final int? month;
  final int? quarter;
  final int? year;
  final DateTime? createdAt;
  final String? changedByName;
  final double? totalVgc;
  final double? retroAdjustment;

  const FinanceTierHistory({
    required this.id,
    this.fromTier,
    required this.toTier,
    required this.type,
    this.reason,
    this.month,
    this.quarter,
    this.year,
    this.createdAt,
    this.changedByName,
    this.totalVgc,
    this.retroAdjustment,
  });

  factory FinanceTierHistory.fromJson(Map<String, dynamic> json) =>
      FinanceTierHistory(
        id: asString(json['id']),
        fromTier: asStringOrNull(json['fromTier']),
        toTier: asString(json['toTier']),
        type: asString(json['type']),
        reason: asStringOrNull(json['reason']),
        month: asIntOrNull(json['month']),
        quarter: asIntOrNull(json['quarter']),
        year: asIntOrNull(json['year']),
        createdAt: asDate(json['createdAt']),
        changedByName: asStringOrNull(asMap(json['changedBy'])['name']),
        totalVgc: asDoubleOrNull(json['totalVgc']),
        retroAdjustment: asDoubleOrNull(json['retroAdjustment']),
      );

  static List<FinanceTierHistory> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceTierHistory.fromJson).toList();
}

/// Membro no detalhe da equipe (GET /teams/:id/detail).
class FinanceTeamMemberDetail {
  final String memberId;
  final String userId;
  final String name;
  final String email;
  final String? currentTier;
  final String projectedTier;
  final double vgv;
  final double vgc;
  final double? tierRate;
  final double silverTarget;
  final double goldTarget;
  final double diamondTarget;
  final FinanceTierHistory? lastChange;

  const FinanceTeamMemberDetail({
    required this.memberId,
    required this.userId,
    required this.name,
    required this.email,
    this.currentTier,
    required this.projectedTier,
    this.vgv = 0,
    this.vgc = 0,
    this.tierRate,
    this.silverTarget = 0,
    this.goldTarget = 0,
    this.diamondTarget = 0,
    this.lastChange,
  });

  factory FinanceTeamMemberDetail.fromJson(Map<String, dynamic> json) =>
      FinanceTeamMemberDetail(
        memberId: asString(json['memberId']),
        userId: asString(json['userId']),
        name: asString(json['name']),
        email: asString(json['email']),
        currentTier: asStringOrNull(json['currentTier']),
        projectedTier:
            asString(json['projectedTier'], FinanceBrokerTier.silver),
        vgv: asDouble(json['vgv']),
        vgc: asDouble(json['vgc']),
        tierRate: asDoubleOrNull(json['tierRate']),
        silverTarget: asDouble(json['silverTarget']),
        goldTarget: asDouble(json['goldTarget']),
        diamondTarget: asDouble(json['diamondTarget']),
        lastChange: json['lastChange'] is Map
            ? FinanceTierHistory.fromJson(asMap(json['lastChange']))
            : null,
      );
}

/// Diretor no detalhe da equipe (avaliado por trimestre).
class FinanceDirectorDetail {
  final String userId;
  final String name;
  final String email;
  final String? currentTier;
  final String projectedTier;
  final double totalVgcAllTeams;
  final int teamCount;
  final double tierRate;
  final double silverTarget;
  final double goldTarget;
  final double diamondTarget;
  final double silverRate;
  final double goldRate;
  final double diamondRate;
  final FinanceTierHistory? lastChange;

  const FinanceDirectorDetail({
    required this.userId,
    required this.name,
    required this.email,
    this.currentTier,
    required this.projectedTier,
    this.totalVgcAllTeams = 0,
    this.teamCount = 0,
    this.tierRate = 0,
    this.silverTarget = 0,
    this.goldTarget = 0,
    this.diamondTarget = 0,
    this.silverRate = 0,
    this.goldRate = 0,
    this.diamondRate = 0,
    this.lastChange,
  });

  factory FinanceDirectorDetail.fromJson(Map<String, dynamic> json) =>
      FinanceDirectorDetail(
        userId: asString(json['userId']),
        name: asString(json['name']),
        email: asString(json['email']),
        currentTier: asStringOrNull(json['currentTier']),
        projectedTier:
            asString(json['projectedTier'], FinanceBrokerTier.silver),
        totalVgcAllTeams: asDouble(json['totalVgcAllTeams']),
        teamCount: asInt(json['teamCount']),
        tierRate: asDouble(json['tierRate']),
        silverTarget: asDouble(json['silverTarget']),
        goldTarget: asDouble(json['goldTarget']),
        diamondTarget: asDouble(json['diamondTarget']),
        silverRate: asDouble(json['silverRate']),
        goldRate: asDouble(json['goldRate']),
        diamondRate: asDouble(json['diamondRate']),
        lastChange: json['lastChange'] is Map
            ? FinanceTierHistory.fromJson(asMap(json['lastChange']))
            : null,
      );
}

/// Gestor no detalhe da equipe (avaliado por trimestre).
class FinanceGestorDetail {
  final String userId;
  final String name;
  final double commissionRate;
  final String? currentTier;
  final String projectedTier;
  final double teamVgc;
  final double tierRate;
  final double silverTarget;
  final double goldTarget;
  final double diamondTarget;
  final double silverRate;
  final double goldRate;
  final double diamondRate;
  final FinanceTierHistory? lastChange;

  const FinanceGestorDetail({
    required this.userId,
    required this.name,
    this.commissionRate = 0,
    this.currentTier,
    required this.projectedTier,
    this.teamVgc = 0,
    this.tierRate = 0,
    this.silverTarget = 0,
    this.goldTarget = 0,
    this.diamondTarget = 0,
    this.silverRate = 0,
    this.goldRate = 0,
    this.diamondRate = 0,
    this.lastChange,
  });

  factory FinanceGestorDetail.fromJson(Map<String, dynamic> json) =>
      FinanceGestorDetail(
        userId: asString(json['userId']),
        name: asString(json['name']),
        commissionRate: asDouble(json['commissionRate']),
        currentTier: asStringOrNull(json['currentTier']),
        projectedTier:
            asString(json['projectedTier'], FinanceBrokerTier.silver),
        teamVgc: asDouble(json['teamVgc']),
        tierRate: asDouble(json['tierRate']),
        silverTarget: asDouble(json['silverTarget']),
        goldTarget: asDouble(json['goldTarget']),
        diamondTarget: asDouble(json['diamondTarget']),
        silverRate: asDouble(json['silverRate']),
        goldRate: asDouble(json['goldRate']),
        diamondRate: asDouble(json['diamondRate']),
        lastChange: json['lastChange'] is Map
            ? FinanceTierHistory.fromJson(asMap(json['lastChange']))
            : null,
      );
}

/// Detalhe completo da equipe (GET /teams/:id/detail).
class FinanceTeamDetail {
  final FinanceTeam team;
  final int currentQuarter;
  final int currentYear;
  final FinanceDirectorDetail? director;
  final FinanceGestorDetail? gestor;
  final List<FinanceTeamMemberDetail> members;

  const FinanceTeamDetail({
    required this.team,
    required this.currentQuarter,
    required this.currentYear,
    this.director,
    this.gestor,
    this.members = const [],
  });

  factory FinanceTeamDetail.fromJson(Map<String, dynamic> json) =>
      FinanceTeamDetail(
        team: FinanceTeam.fromJson(asMap(json['team'])),
        currentQuarter: asInt(json['currentQuarter'], 1),
        currentYear: asInt(json['currentYear'], DateTime.now().year),
        director: json['director'] is Map
            ? FinanceDirectorDetail.fromJson(asMap(json['director']))
            : null,
        gestor: json['gestor'] is Map
            ? FinanceGestorDetail.fromJson(asMap(json['gestor']))
            : null,
        members: asMapList(json['members'])
            .map(FinanceTeamMemberDetail.fromJson)
            .toList(),
      );
}

/// Body de POST /teams e PATCH /teams/:id (companyId imutável no PATCH).
/// directorId/gestorId aceitam null EXPLÍCITO para desvincular — por isso
/// os flags `clearDirector`/`clearGestor` (compactBody removeria o null).
class FinanceTeamInput {
  final String? companyId;
  final String? name;
  final String? directorId;
  final String? gestorId;
  final bool clearDirector;
  final bool clearGestor;
  final double? silverRate;
  final double? silverMinValue;
  final double? goldRate;
  final double? goldMinValue;
  final double? diamondRate;
  final double? diamondMinValue;

  const FinanceTeamInput({
    this.companyId,
    this.name,
    this.directorId,
    this.gestorId,
    this.clearDirector = false,
    this.clearGestor = false,
    this.silverRate,
    this.silverMinValue,
    this.goldRate,
    this.goldMinValue,
    this.diamondRate,
    this.diamondMinValue,
  });

  Map<String, dynamic> toJson() {
    final body = compactBody({
      'companyId': companyId,
      'name': name,
      'directorId': directorId,
      'gestorId': gestorId,
      'silverRate': silverRate,
      'silverMinValue': silverMinValue,
      'goldRate': goldRate,
      'goldMinValue': goldMinValue,
      'diamondRate': diamondRate,
      'diamondMinValue': diamondMinValue,
    });
    if (clearDirector) body['directorId'] = null;
    if (clearGestor) body['gestorId'] = null;
    return body;
  }
}

/// Body de POST /teams/associate — vincula equipe do CRM (decisão D3).
/// `companyId` é a empresa LOCAL do financeiro; diretor/gestor/membros são
/// `externalId` (id do colaborador no CRM/core).
class FinanceAssociateTeamInput {
  final String crmTeamId;
  final String companyId;
  final String name;
  final String? directorExternalId;
  final String? gestorExternalId;
  final List<String>? memberExternalIds;
  final double? silverRate;
  final double? silverMinValue;
  final double? goldRate;
  final double? goldMinValue;
  final double? diamondRate;
  final double? diamondMinValue;

  const FinanceAssociateTeamInput({
    required this.crmTeamId,
    required this.companyId,
    required this.name,
    this.directorExternalId,
    this.gestorExternalId,
    this.memberExternalIds,
    this.silverRate,
    this.silverMinValue,
    this.goldRate,
    this.goldMinValue,
    this.diamondRate,
    this.diamondMinValue,
  });

  Map<String, dynamic> toJson() => compactBody({
        'crmTeamId': crmTeamId,
        'companyId': companyId,
        'name': name,
        'directorExternalId': directorExternalId,
        'gestorExternalId': gestorExternalId,
        'memberExternalIds': memberExternalIds,
        'silverRate': silverRate,
        'silverMinValue': silverMinValue,
        'goldRate': goldRate,
        'goldMinValue': goldMinValue,
        'diamondRate': diamondRate,
        'diamondMinValue': diamondMinValue,
      });
}

/// Retorno de POST /teams/associate.
class FinanceAssociateTeamResult {
  final FinanceTeam team;

  /// externalIds de corretores ainda sem vínculo no Financeiro.
  final List<String> membrosPendentes;

  const FinanceAssociateTeamResult({
    required this.team,
    this.membrosPendentes = const [],
  });

  factory FinanceAssociateTeamResult.fromJson(Map<String, dynamic> json) =>
      FinanceAssociateTeamResult(
        team: FinanceTeam.fromJson(asMap(json['team'])),
        membrosPendentes: asStringList(json['membrosPendentes']),
      );
}

/// Resultado de POST /teams/:id/evaluate-* — `results` na avaliação normal
/// ou só `message` quando a equipe não tem diretor/gestor.
class FinanceEvaluateTiersResult {
  final List<Map<String, dynamic>> results;
  final String? message;

  const FinanceEvaluateTiersResult({this.results = const [], this.message});

  factory FinanceEvaluateTiersResult.fromJson(Map<String, dynamic> json) =>
      FinanceEvaluateTiersResult(
        results: asMapList(json['results']),
        message: asStringOrNull(json['message']),
      );
}

/// Corretor de GET /brokers — o back NÃO filtra por companyId (só position);
/// o filtro por empresa é client-side pelo array `companies`.
class FinanceTeamBroker {
  final String id;
  final String name;
  final String? email;
  final List<String> companyIds;

  const FinanceTeamBroker({
    required this.id,
    required this.name,
    this.email,
    this.companyIds = const [],
  });

  factory FinanceTeamBroker.fromJson(Map<String, dynamic> json) =>
      FinanceTeamBroker(
        id: asString(json['id']),
        name: asString(json['name']),
        email: asStringOrNull(json['email']),
        companyIds: asMapList(json['companies'])
            .map((c) => asString(asMap(c['company'])['id']))
            .where((id) => id.isNotEmpty)
            .toList(),
      );

  static List<FinanceTeamBroker> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceTeamBroker.fromJson).toList();
}

/// Corretor de GET /users/brokers?companyId= (shape enxuto).
class FinanceCompanyBroker {
  final String id;
  final String name;
  final String email;

  const FinanceCompanyBroker({
    required this.id,
    required this.name,
    required this.email,
  });

  factory FinanceCompanyBroker.fromJson(Map<String, dynamic> json) =>
      FinanceCompanyBroker(
        id: asString(json['id']),
        name: asString(json['name']),
        email: asString(json['email']),
      );

  static List<FinanceCompanyBroker> listFromBody(dynamic body) =>
      asMapList(body).map(FinanceCompanyBroker.fromJson).toList();
}

/// Tier/taxa vigente de um corretor (GET /teams/broker-tier/:brokerId).
class FinanceBrokerTierInfo {
  final String tier;
  final double? rate;
  final FinanceRef? team;

  const FinanceBrokerTierInfo({required this.tier, this.rate, this.team});

  factory FinanceBrokerTierInfo.fromJson(Map<String, dynamic> json) =>
      FinanceBrokerTierInfo(
        tier: asString(json['tier'], FinanceBrokerTier.silver),
        rate: asDoubleOrNull(json['rate']),
        team: FinanceRef.fromJsonOrNull(json['team']),
      );
}
