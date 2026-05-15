import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import 'api_service.dart';

/// Status retornado pelo backend para uma proposta.
enum ProposalStatus { processing, finalized, canceled }

extension ProposalStatusX on ProposalStatus {
  String get apiValue {
    switch (this) {
      case ProposalStatus.processing:
        return 'processing';
      case ProposalStatus.finalized:
        return 'finalized';
      case ProposalStatus.canceled:
        return 'canceled';
    }
  }

  String get label {
    switch (this) {
      case ProposalStatus.processing:
        return 'Em andamento';
      case ProposalStatus.finalized:
        return 'Finalizada';
      case ProposalStatus.canceled:
        return 'Cancelada';
    }
  }
}

ProposalStatus parseProposalStatus(dynamic raw) {
  final s = raw?.toString().toLowerCase().trim();
  switch (s) {
    case 'finalized':
      return ProposalStatus.finalized;
    case 'canceled':
    case 'cancelled':
      return ProposalStatus.canceled;
    default:
      return ProposalStatus.processing;
  }
}

/// Etapa de assinatura (1=comprador, 2=proprietário, 3=corretor/captadores).
enum ProposalEtapa { comprador, proprietario, corretor }

extension ProposalEtapaX on ProposalEtapa {
  int get number {
    switch (this) {
      case ProposalEtapa.comprador:
        return 1;
      case ProposalEtapa.proprietario:
        return 2;
      case ProposalEtapa.corretor:
        return 3;
    }
  }

  String get label {
    switch (this) {
      case ProposalEtapa.comprador:
        return 'Comprador';
      case ProposalEtapa.proprietario:
        return 'Proprietário';
      case ProposalEtapa.corretor:
        return 'Corretor / Captadores';
    }
  }

  String get titulo {
    switch (this) {
      case ProposalEtapa.comprador:
        return 'Etapa 1 – Comprador';
      case ProposalEtapa.proprietario:
        return 'Etapa 2 – Proprietário';
      case ProposalEtapa.corretor:
        return 'Etapa 3 – Corretor';
    }
  }
}

ProposalEtapa proposalEtapaFromInt(int? n) {
  switch (n) {
    case 3:
      return ProposalEtapa.corretor;
    case 2:
      return ProposalEtapa.proprietario;
    default:
      return ProposalEtapa.comprador;
  }
}

/// Dados básicos de uma proposta para listagem e detalhe.
///
/// O backend devolve um JSON enorme com todos os campos do entity.
/// Mantemos os mais usados como getters tipados + um `raw` para usar campos
/// raros sem precisar mexer aqui sempre.
class PurchaseProposal {
  final Map<String, dynamic> raw;

  PurchaseProposal(this.raw);

  String get id => _str(raw['id']);
  String get proposalNumber => _str(raw['proposalNumber']);
  ProposalStatus get status => parseProposalStatus(raw['status']);
  ProposalEtapa get etapa => proposalEtapaFromInt(_int(raw['etapa']));
  int? get maxEtapaLiberadaParaEnvio => _int(raw['maxEtapaLiberadaParaEnvio']);
  bool get etapa2EnviadaParaAssinatura =>
      raw['etapa2EnviadaParaAssinatura'] == true;

  DateTime? get proposalDate => _date(raw['proposalDate']);
  int? get validityDays => _int(raw['validityDays']);
  double? get proposedPrice => _num(raw['proposedPrice']);
  String? get paymentConditions => _strNull(raw['paymentConditions']);
  double? get downPayment => _num(raw['downPayment']);
  int? get downPaymentDays => _int(raw['downPaymentDays']);
  double? get commissionPercentage => _num(raw['commissionPercentage']);
  int? get deliveryDays => _int(raw['deliveryDays']);
  double? get monthlyPenalty => _num(raw['monthlyPenalty']);

  String? get saleUnit => _strNull(raw['saleUnit']);
  String? get captureUnit => _strNull(raw['captureUnit']);

  // Proponent (comprador)
  String? get proponentName => _strNull(raw['proponentName']);
  String? get proponentRg => _strNull(raw['proponentRg']);
  String? get proponentCpf => _strNull(raw['proponentCpf']);
  String? get proponentNationality => _strNull(raw['proponentNationality']);
  String? get proponentMaritalStatus =>
      _strNull(raw['proponentMaritalStatus']);
  String? get proponentMarriageRegime =>
      _strNull(raw['proponentMarriageRegime']);
  DateTime? get proponentBirthDate => _date(raw['proponentBirthDate']);
  String? get proponentProfession => _strNull(raw['proponentProfession']);
  String? get proponentEmail => _strNull(raw['proponentEmail']);
  String? get proponentPhone => _strNull(raw['proponentPhone']);
  String? get proponentAddress => _strNull(raw['proponentAddress']);
  String? get proponentNeighborhood => _strNull(raw['proponentNeighborhood']);
  String? get proponentZipCode => _strNull(raw['proponentZipCode']);
  String? get proponentCity => _strNull(raw['proponentCity']);
  String? get proponentState => _strNull(raw['proponentState']);

  // Cônjuge do proponente
  String? get proponentSpouseName => _strNull(raw['proponentSpouseName']);
  String? get proponentSpouseRg => _strNull(raw['proponentSpouseRg']);
  String? get proponentSpouseCpf => _strNull(raw['proponentSpouseCpf']);
  String? get proponentSpouseProfession =>
      _strNull(raw['proponentSpouseProfession']);
  String? get proponentSpouseEmail => _strNull(raw['proponentSpouseEmail']);
  String? get proponentSpousePhone => _strNull(raw['proponentSpousePhone']);

  // Imóvel
  String? get propertyRegistry => _strNull(raw['propertyRegistry']);
  String? get propertyNotary => _strNull(raw['propertyNotary']);
  String? get propertyCityRegistry => _strNull(raw['propertyCityRegistry']);
  String? get propertyCode => _strNull(raw['propertyCode']);
  String? get propertyAddress => _strNull(raw['propertyAddress']);
  String? get propertyStreet => _strNull(raw['propertyStreet']);
  String? get propertyNumber => _strNull(raw['propertyNumber']);
  String? get propertyComplement => _strNull(raw['propertyComplement']);
  String? get propertyNeighborhood => _strNull(raw['propertyNeighborhood']);
  String? get propertyCity => _strNull(raw['propertyCity']);
  String? get propertyState => _strNull(raw['propertyState']);
  String? get propertyZipCode => _strNull(raw['propertyZipCode']);

  // Proprietário
  String? get ownerName => _strNull(raw['ownerName']);
  String? get ownerRg => _strNull(raw['ownerRg']);
  String? get ownerCpf => _strNull(raw['ownerCpf']);
  String? get ownerNationality => _strNull(raw['ownerNationality']);
  String? get ownerMaritalStatus => _strNull(raw['ownerMaritalStatus']);
  String? get ownerMarriageRegime => _strNull(raw['ownerMarriageRegime']);
  DateTime? get ownerBirthDate => _date(raw['ownerBirthDate']);
  String? get ownerProfession => _strNull(raw['ownerProfession']);
  String? get ownerEmail => _strNull(raw['ownerEmail']);
  String? get ownerPhone => _strNull(raw['ownerPhone']);
  String? get ownerAddress => _strNull(raw['ownerAddress']);
  String? get ownerNeighborhood => _strNull(raw['ownerNeighborhood']);
  String? get ownerZipCode => _strNull(raw['ownerZipCode']);
  String? get ownerCity => _strNull(raw['ownerCity']);
  String? get ownerState => _strNull(raw['ownerState']);

  // Cônjuge proprietário
  String? get ownerSpouseName => _strNull(raw['ownerSpouseName']);
  String? get ownerSpouseRg => _strNull(raw['ownerSpouseRg']);
  String? get ownerSpouseCpf => _strNull(raw['ownerSpouseCpf']);
  String? get ownerSpouseProfession => _strNull(raw['ownerSpouseProfession']);
  String? get ownerSpouseEmail => _strNull(raw['ownerSpouseEmail']);
  String? get ownerSpousePhone => _strNull(raw['ownerSpousePhone']);

  // Corretores/captadores (JSON)
  List<ProposalBroker> get brokersData {
    final list = raw['brokersData'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => ProposalBroker.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  List<ProposalCaptador> get captadoresData {
    final list = raw['captadoresData'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => ProposalCaptador.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  String? get corretorCpf => _strNull(raw['corretorCpf']);
  String? get gestorCpf => _strNull(raw['gestorCpf']);

  String? get cancellationReason => _strNull(raw['cancellationReason']);
  String? get deletionReason => _strNull(raw['deletionReason']);
  DateTime? get deletedAt => _date(raw['deletedAt']);

  /// User criador (campo `user` no JSON do controller).
  String? get creatorName {
    final u = raw['user'];
    if (u is Map) return u['name']?.toString();
    return null;
  }

  String? get creatorEmail {
    final u = raw['user'];
    if (u is Map) return u['email']?.toString();
    return null;
  }

  DateTime? get createdAt => _date(raw['createdAt']);
  DateTime? get updatedAt => _date(raw['updatedAt']);

  factory PurchaseProposal.fromJson(Map<String, dynamic> j) =>
      PurchaseProposal(Map<String, dynamic>.from(j));

  PurchaseProposal copyWith(Map<String, dynamic> overrides) {
    final merged = Map<String, dynamic>.from(raw)..addAll(overrides);
    return PurchaseProposal(merged);
  }
}

class ProposalBroker {
  final String id;
  final String nome;
  final String? email;
  final String? unidade;

  const ProposalBroker({
    required this.id,
    required this.nome,
    this.email,
    this.unidade,
  });

  factory ProposalBroker.fromJson(Map<String, dynamic> j) => ProposalBroker(
        id: _str(j['id']),
        nome: _str(j['nome'] ?? j['name']),
        email: _strNull(j['email']),
        unidade: _strNull(j['unidade']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        if (email != null) 'email': email,
        if (unidade != null) 'unidade': unidade,
      };
}

class ProposalCaptador {
  final String id;
  final String nome;
  final String? unidade;
  final double? porcentagem;

  const ProposalCaptador({
    required this.id,
    required this.nome,
    this.unidade,
    this.porcentagem,
  });

  factory ProposalCaptador.fromJson(Map<String, dynamic> j) => ProposalCaptador(
        id: _str(j['id']),
        nome: _str(j['nome'] ?? j['name']),
        unidade: _strNull(j['unidade']),
        porcentagem: _num(j['porcentagem']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        if (unidade != null) 'unidade': unidade,
        if (porcentagem != null) 'porcentagem': porcentagem,
      };
}

class ProposalStats {
  final int total;
  const ProposalStats({required this.total});

  factory ProposalStats.fromJson(Map<String, dynamic> j) =>
      ProposalStats(total: _int(j['total']) ?? 0);
}

class ProposalListResult {
  final List<PurchaseProposal> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  ProposalListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });
}

class ProposalFilters {
  final String? search;
  final String? saleFormId;
  final String? userId;
  final String? saleUnit;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final ProposalEtapa? etapa;
  final ProposalStatus? status;
  final bool? listDeletedOnly;
  final int page;
  final int limit;
  final String sortBy;
  final String sortOrder;

  const ProposalFilters({
    this.search,
    this.saleFormId,
    this.userId,
    this.saleUnit,
    this.dateFrom,
    this.dateTo,
    this.etapa,
    this.status,
    this.listDeletedOnly,
    this.page = 1,
    this.limit = 20,
    this.sortBy = 'createdAt',
    this.sortOrder = 'DESC',
  });

  Map<String, String> toQuery() {
    final qp = <String, String>{
      'page': '$page',
      'limit': '$limit',
      'sortBy': sortBy,
      'sortOrder': sortOrder,
    };
    final s = search?.trim();
    if (s != null && s.isNotEmpty) qp['search'] = s;
    if (saleFormId != null && saleFormId!.isNotEmpty) {
      qp['saleFormId'] = saleFormId!;
    }
    if (userId != null && userId!.isNotEmpty) qp['userId'] = userId!;
    if (saleUnit != null && saleUnit!.trim().isNotEmpty) {
      qp['saleUnit'] = saleUnit!.trim();
    }
    if (dateFrom != null) {
      qp['dateFrom'] = dateFrom!.toUtc().toIso8601String();
    }
    if (dateTo != null) {
      qp['dateTo'] = dateTo!.toUtc().toIso8601String();
    }
    if (etapa != null) qp['etapa'] = '${etapa!.number}';
    if (status != null) qp['status'] = status!.apiValue;
    if (listDeletedOnly == true) qp['listDeletedOnly'] = 'true';
    return qp;
  }

  /// `copyWith` com suporte real a limpeza: passar `null` em campos anuláveis
  /// **limpa** o filtro. Omitir o parâmetro preserva o valor atual.
  /// Usamos um sentinela privado para distinguir "não passado" de "passado como null".
  ProposalFilters copyWith({
    Object? search = _kKeep,
    Object? saleFormId = _kKeep,
    Object? userId = _kKeep,
    Object? saleUnit = _kKeep,
    Object? dateFrom = _kKeep,
    Object? dateTo = _kKeep,
    Object? etapa = _kKeep,
    Object? status = _kKeep,
    Object? listDeletedOnly = _kKeep,
    int? page,
    int? limit,
    String? sortBy,
    String? sortOrder,
  }) =>
      ProposalFilters(
        search: identical(search, _kKeep) ? this.search : search as String?,
        saleFormId: identical(saleFormId, _kKeep)
            ? this.saleFormId
            : saleFormId as String?,
        userId:
            identical(userId, _kKeep) ? this.userId : userId as String?,
        saleUnit:
            identical(saleUnit, _kKeep) ? this.saleUnit : saleUnit as String?,
        dateFrom: identical(dateFrom, _kKeep)
            ? this.dateFrom
            : dateFrom as DateTime?,
        dateTo:
            identical(dateTo, _kKeep) ? this.dateTo : dateTo as DateTime?,
        etapa: identical(etapa, _kKeep)
            ? this.etapa
            : etapa as ProposalEtapa?,
        status: identical(status, _kKeep)
            ? this.status
            : status as ProposalStatus?,
        listDeletedOnly: identical(listDeletedOnly, _kKeep)
            ? this.listDeletedOnly
            : listDeletedOnly as bool?,
        page: page ?? this.page,
        limit: limit ?? this.limit,
        sortBy: sortBy ?? this.sortBy,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// Sentinela usado por [ProposalFilters.copyWith] para diferenciar
/// "parâmetro omitido" de "parâmetro passado como null".
const Object _kKeep = Object();

class ProposalHistoryEvent {
  final int etapa;
  final String eventType;
  final String? cpfActor;
  final Map<String, dynamic>? payload;
  final DateTime? createdAt;

  const ProposalHistoryEvent({
    required this.etapa,
    required this.eventType,
    this.cpfActor,
    this.payload,
    this.createdAt,
  });

  factory ProposalHistoryEvent.fromJson(Map<String, dynamic> j) =>
      ProposalHistoryEvent(
        etapa: _int(j['etapa']) ?? 1,
        eventType: _str(j['eventType']),
        cpfActor: _strNull(j['cpfActor']),
        payload: j['payload'] is Map
            ? Map<String, dynamic>.from(j['payload'] as Map)
            : null,
        createdAt: _date(j['createdAt']),
      );
}

class ProposalSignature {
  final String id;
  final int etapa;
  final String status;
  final String? signerName;
  final String? signerEmail;
  final String? action;
  final String? autentiqueDocumentId;
  final DateTime? signedAt;
  final DateTime? viewedAt;
  final DateTime? createdAt;
  final String? rejectionReason;

  const ProposalSignature({
    required this.id,
    required this.etapa,
    required this.status,
    this.signerName,
    this.signerEmail,
    this.action,
    this.autentiqueDocumentId,
    this.signedAt,
    this.viewedAt,
    this.createdAt,
    this.rejectionReason,
  });

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'signed':
        return 'Assinada';
      case 'rejected':
        return 'Rejeitada';
      case 'cancelled':
      case 'canceled':
        return 'Cancelada';
      case 'pending':
        return 'Aguardando assinatura';
      case 'viewed':
        return 'Visualizada';
      default:
        return status;
    }
  }

  factory ProposalSignature.fromJson(Map<String, dynamic> j) =>
      ProposalSignature(
        id: _str(j['id']),
        etapa: _int(j['etapa']) ?? 1,
        status: _str(j['status']),
        signerName: _strNull(j['signerName']),
        signerEmail: _strNull(j['signerEmail']),
        action: _strNull(j['action']),
        autentiqueDocumentId: _strNull(j['autentiqueDocumentId']),
        signedAt: _date(j['signedAt']),
        viewedAt: _date(j['viewedAt']),
        createdAt: _date(j['createdAt']),
        rejectionReason: _strNull(j['rejectionReason']),
      );
}

class ProposalAttachment {
  final String id;
  final int etapa;
  final String status;
  final String fileName;
  final String fileUrl;
  final int? fileSize;
  final String? uploadedByName;
  final String? rejectionReason;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  const ProposalAttachment({
    required this.id,
    required this.etapa,
    required this.status,
    required this.fileName,
    required this.fileUrl,
    this.fileSize,
    this.uploadedByName,
    this.rejectionReason,
    this.approvedAt,
    this.createdAt,
  });

  factory ProposalAttachment.fromJson(Map<String, dynamic> j) =>
      ProposalAttachment(
        id: _str(j['id']),
        etapa: _int(j['etapa']) ?? 1,
        status: _str(j['status']),
        fileName: _str(j['fileName']),
        fileUrl: _str(j['fileUrl']),
        fileSize: _int(j['fileSize']),
        uploadedByName: _strNull(j['uploadedByName']),
        rejectionReason: _strNull(j['rejectionReason']),
        approvedAt: _date(j['approvedAt']),
        createdAt: _date(j['createdAt']),
      );
}

class ProposalHistorico {
  final String proposalNumber;
  final int etapa;
  final int? maxEtapaLiberadaParaEnvio;
  final List<ProposalHistoryEvent> stageHistory;
  final List<ProposalSignature> signatures;
  final List<ProposalAttachment> attachments;

  const ProposalHistorico({
    required this.proposalNumber,
    required this.etapa,
    this.maxEtapaLiberadaParaEnvio,
    this.stageHistory = const [],
    this.signatures = const [],
    this.attachments = const [],
  });

  factory ProposalHistorico.fromJson(Map<String, dynamic> j) =>
      ProposalHistorico(
        proposalNumber: _str(j['proposalNumber']),
        etapa: _int(j['etapa']) ?? 1,
        maxEtapaLiberadaParaEnvio: _int(j['maxEtapaLiberadaParaEnvio']),
        stageHistory: (j['stageHistory'] as List? ?? const [])
            .whereType<Map>()
            .map((m) =>
                ProposalHistoryEvent.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        signatures: (j['signatures'] as List? ?? const [])
            .whereType<Map>()
            .map((m) =>
                ProposalSignature.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        attachments: (j['attachments'] as List? ?? const [])
            .whereType<Map>()
            .map((m) =>
                ProposalAttachment.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

/// Payload de criar/editar (mesmos campos do `CreateProposalAuthDto` no back).
class CreateProposalPayload {
  CreateProposalPayload();

  String? saleFormId;
  DateTime? proposalDate;
  int? validityDays;
  double? proposedPrice;
  String? paymentConditions;
  double? downPayment;
  int? downPaymentDays;
  double? commissionPercentage;
  int? deliveryDays;
  double? monthlyPenalty;
  String? saleUnit;
  String? captureUnit;
  String? observations;

  // Comprador
  String? buyerName;
  String? buyerCpf;
  String? buyerRg;
  DateTime? buyerBirthDate;
  String? buyerEmail;
  String? buyerPhone;
  String? buyerProfession;
  String? buyerNationality;
  String? buyerMaritalStatus;
  String? buyerMarriageRegime;
  String? buyerZipCode;
  String? buyerStreet;
  String? buyerNumber;
  String? buyerComplement;
  String? buyerNeighborhood;
  String? buyerCity;
  String? buyerState;

  // Cônjuge comprador
  String? buyerSpouseName;
  String? buyerSpouseCpf;
  String? buyerSpouseRg;
  DateTime? buyerSpouseBirthDate;
  String? buyerSpouseEmail;
  String? buyerSpousePhone;
  String? buyerSpouseProfession;

  // Imóvel
  String? propertyRegistry;
  String? propertyNotary;
  String? propertyCityRegistry;
  String? propertyCode;
  String? propertyZipCode;
  String? propertyAddress;
  String? propertyStreet;
  String? propertyNumber;
  String? propertyComplement;
  String? propertyNeighborhood;
  String? propertyCity;
  String? propertyState;

  // Proprietário
  String? ownerName;
  String? ownerCpf;
  String? ownerRg;
  DateTime? ownerBirthDate;
  String? ownerEmail;
  String? ownerPhone;
  String? ownerProfession;
  String? ownerNationality;
  String? ownerMaritalStatus;
  String? ownerMarriageRegime;
  String? ownerZipCode;
  String? ownerAddress;
  String? ownerNeighborhood;
  String? ownerCity;
  String? ownerState;

  // Cônjuge proprietário
  String? ownerSpouseName;
  String? ownerSpouseCpf;
  String? ownerSpouseRg;
  DateTime? ownerSpouseBirthDate;
  String? ownerSpouseEmail;
  String? ownerSpousePhone;
  String? ownerSpouseProfession;

  // Corretores / Captadores
  List<ProposalBroker> brokersData = const [];
  List<ProposalCaptador> captadoresData = const [];

  List<String> linkedUserIds = const [];

  void _addIfPresent(
    Map<String, dynamic> body,
    String key,
    Object? value,
  ) {
    if (value == null) return;
    if (value is String && value.trim().isEmpty) return;
    body[key] = value;
  }

  void _addDate(Map<String, dynamic> body, String key, DateTime? value) {
    if (value == null) return;
    body[key] = value.toIso8601String().substring(0, 10);
  }

  /// Monta payload compatível com `CreateProposalAuthDto`.
  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{};
    _addIfPresent(body, 'saleFormId', saleFormId);
    _addDate(body, 'proposalDate', proposalDate);
    _addIfPresent(body, 'validityDays', validityDays);
    _addIfPresent(body, 'proposedPrice', proposedPrice);
    _addIfPresent(body, 'paymentConditions', paymentConditions?.trim());
    _addIfPresent(body, 'downPayment', downPayment);
    _addIfPresent(body, 'downPaymentDays', downPaymentDays);
    _addIfPresent(body, 'commissionPercentage', commissionPercentage);
    _addIfPresent(body, 'deliveryDays', deliveryDays);
    _addIfPresent(body, 'monthlyPenalty', monthlyPenalty);
    _addIfPresent(body, 'saleUnit', saleUnit?.trim());
    _addIfPresent(body, 'captureUnit', captureUnit?.trim());
    _addIfPresent(body, 'observations', observations?.trim());

    // Comprador
    _addIfPresent(body, 'buyerName', buyerName?.trim());
    _addIfPresent(body, 'buyerCpf', buyerCpf?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(body, 'buyerRg', buyerRg?.trim());
    _addDate(body, 'buyerBirthDate', buyerBirthDate);
    _addIfPresent(body, 'buyerEmail', buyerEmail?.trim());
    _addIfPresent(
        body, 'buyerPhone', buyerPhone?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(body, 'buyerProfession', buyerProfession?.trim());
    _addIfPresent(body, 'buyerNationality', buyerNationality?.trim());
    _addIfPresent(body, 'buyerMaritalStatus', buyerMaritalStatus?.trim());
    _addIfPresent(body, 'buyerMarriageRegime', buyerMarriageRegime?.trim());
    _addIfPresent(
        body, 'buyerZipCode', buyerZipCode?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(body, 'buyerStreet', buyerStreet?.trim());
    _addIfPresent(body, 'buyerNumber', buyerNumber?.trim());
    _addIfPresent(body, 'buyerComplement', buyerComplement?.trim());
    _addIfPresent(body, 'buyerNeighborhood', buyerNeighborhood?.trim());
    _addIfPresent(body, 'buyerCity', buyerCity?.trim());
    _addIfPresent(body, 'buyerState', buyerState?.trim());

    // Cônjuge comprador
    _addIfPresent(body, 'buyerSpouseName', buyerSpouseName?.trim());
    _addIfPresent(
        body, 'buyerSpouseCpf', buyerSpouseCpf?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(body, 'buyerSpouseRg', buyerSpouseRg?.trim());
    _addDate(body, 'buyerSpouseBirthDate', buyerSpouseBirthDate);
    _addIfPresent(body, 'buyerSpouseEmail', buyerSpouseEmail?.trim());
    _addIfPresent(body, 'buyerSpousePhone',
        buyerSpousePhone?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(body, 'buyerSpouseProfession', buyerSpouseProfession?.trim());

    // Imóvel — vai como propertyData JSON livre
    final property = <String, dynamic>{};
    _addIfPresent(property, 'registry', propertyRegistry?.trim());
    _addIfPresent(property, 'notary', propertyNotary?.trim());
    _addIfPresent(property, 'cityRegistry', propertyCityRegistry?.trim());
    _addIfPresent(property, 'code', propertyCode?.trim());
    _addIfPresent(property, 'zipCode',
        propertyZipCode?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(property, 'address', propertyAddress?.trim());
    _addIfPresent(property, 'street', propertyStreet?.trim());
    _addIfPresent(property, 'number', propertyNumber?.trim());
    _addIfPresent(property, 'complement', propertyComplement?.trim());
    _addIfPresent(property, 'neighborhood', propertyNeighborhood?.trim());
    _addIfPresent(property, 'city', propertyCity?.trim());
    _addIfPresent(property, 'state', propertyState?.trim());
    if (property.isNotEmpty) body['propertyData'] = property;

    // Proprietário — vai espelhado no propertyData.owner (backend aceita)
    final ownerData = <String, dynamic>{};
    _addIfPresent(ownerData, 'ownerName', ownerName?.trim());
    _addIfPresent(
        ownerData, 'ownerCpf', ownerCpf?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(ownerData, 'ownerRg', ownerRg?.trim());
    _addDate(ownerData, 'ownerBirthDate', ownerBirthDate);
    _addIfPresent(ownerData, 'ownerEmail', ownerEmail?.trim());
    _addIfPresent(
        ownerData, 'ownerPhone', ownerPhone?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(ownerData, 'ownerProfession', ownerProfession?.trim());
    _addIfPresent(ownerData, 'ownerNationality', ownerNationality?.trim());
    _addIfPresent(ownerData, 'ownerMaritalStatus', ownerMaritalStatus?.trim());
    _addIfPresent(
        ownerData, 'ownerMarriageRegime', ownerMarriageRegime?.trim());
    _addIfPresent(ownerData, 'ownerZipCode',
        ownerZipCode?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(ownerData, 'ownerAddress', ownerAddress?.trim());
    _addIfPresent(ownerData, 'ownerNeighborhood', ownerNeighborhood?.trim());
    _addIfPresent(ownerData, 'ownerCity', ownerCity?.trim());
    _addIfPresent(ownerData, 'ownerState', ownerState?.trim());
    _addIfPresent(ownerData, 'ownerSpouseName', ownerSpouseName?.trim());
    _addIfPresent(ownerData, 'ownerSpouseCpf',
        ownerSpouseCpf?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(ownerData, 'ownerSpouseRg', ownerSpouseRg?.trim());
    _addDate(ownerData, 'ownerSpouseBirthDate', ownerSpouseBirthDate);
    _addIfPresent(ownerData, 'ownerSpouseEmail', ownerSpouseEmail?.trim());
    _addIfPresent(ownerData, 'ownerSpousePhone',
        ownerSpousePhone?.replaceAll(RegExp(r'\D'), ''));
    _addIfPresent(
        ownerData, 'ownerSpouseProfession', ownerSpouseProfession?.trim());
    if (ownerData.isNotEmpty) {
      final base = body['propertyData'];
      if (base is Map) {
        body['propertyData'] = {
          ...Map<String, dynamic>.from(base),
          ...ownerData,
        };
      } else {
        body['propertyData'] = ownerData;
      }
    }

    if (brokersData.isNotEmpty) {
      body['brokersData'] = brokersData.map((e) => e.toJson()).toList();
    }
    if (captadoresData.isNotEmpty) {
      body['captadoresData'] =
          captadoresData.map((e) => e.toJson()).toList();
    }

    if (linkedUserIds.isNotEmpty) {
      body['linkedUserIds'] = linkedUserIds;
    }

    return body;
  }

  /// Constrói payload a partir de uma proposta existente para a tela de edição.
  static CreateProposalPayload fromProposal(PurchaseProposal p) {
    final c = CreateProposalPayload()
      ..proposalDate = p.proposalDate
      ..validityDays = p.validityDays
      ..proposedPrice = p.proposedPrice
      ..paymentConditions = p.paymentConditions
      ..downPayment = p.downPayment
      ..downPaymentDays = p.downPaymentDays
      ..commissionPercentage = p.commissionPercentage
      ..deliveryDays = p.deliveryDays
      ..monthlyPenalty = p.monthlyPenalty
      ..saleUnit = p.saleUnit
      ..captureUnit = p.captureUnit
      ..buyerName = p.proponentName
      ..buyerCpf = p.proponentCpf
      ..buyerRg = p.proponentRg
      ..buyerBirthDate = p.proponentBirthDate
      ..buyerEmail = p.proponentEmail
      ..buyerPhone = p.proponentPhone
      ..buyerProfession = p.proponentProfession
      ..buyerNationality = p.proponentNationality
      ..buyerMaritalStatus = p.proponentMaritalStatus
      ..buyerMarriageRegime = p.proponentMarriageRegime
      ..buyerZipCode = p.proponentZipCode
      ..buyerStreet = p.proponentAddress
      ..buyerNeighborhood = p.proponentNeighborhood
      ..buyerCity = p.proponentCity
      ..buyerState = p.proponentState
      ..buyerSpouseName = p.proponentSpouseName
      ..buyerSpouseCpf = p.proponentSpouseCpf
      ..buyerSpouseRg = p.proponentSpouseRg
      ..buyerSpouseEmail = p.proponentSpouseEmail
      ..buyerSpousePhone = p.proponentSpousePhone
      ..buyerSpouseProfession = p.proponentSpouseProfession
      ..propertyRegistry = p.propertyRegistry
      ..propertyNotary = p.propertyNotary
      ..propertyCityRegistry = p.propertyCityRegistry
      ..propertyCode = p.propertyCode
      ..propertyZipCode = p.propertyZipCode
      ..propertyAddress = p.propertyAddress
      ..propertyStreet = p.propertyStreet
      ..propertyNumber = p.propertyNumber
      ..propertyComplement = p.propertyComplement
      ..propertyNeighborhood = p.propertyNeighborhood
      ..propertyCity = p.propertyCity
      ..propertyState = p.propertyState
      ..ownerName = p.ownerName
      ..ownerCpf = p.ownerCpf
      ..ownerRg = p.ownerRg
      ..ownerBirthDate = p.ownerBirthDate
      ..ownerEmail = p.ownerEmail
      ..ownerPhone = p.ownerPhone
      ..ownerProfession = p.ownerProfession
      ..ownerNationality = p.ownerNationality
      ..ownerMaritalStatus = p.ownerMaritalStatus
      ..ownerMarriageRegime = p.ownerMarriageRegime
      ..ownerZipCode = p.ownerZipCode
      ..ownerAddress = p.ownerAddress
      ..ownerNeighborhood = p.ownerNeighborhood
      ..ownerCity = p.ownerCity
      ..ownerState = p.ownerState
      ..ownerSpouseName = p.ownerSpouseName
      ..ownerSpouseCpf = p.ownerSpouseCpf
      ..ownerSpouseRg = p.ownerSpouseRg
      ..ownerSpouseEmail = p.ownerSpouseEmail
      ..ownerSpousePhone = p.ownerSpousePhone
      ..ownerSpouseProfession = p.ownerSpouseProfession
      ..brokersData = p.brokersData
      ..captadoresData = p.captadoresData;
    return c;
  }
}

/// Resposta do envio para assinatura.
class ProposalSignerInput {
  final String email;
  final String name;
  final String action; // SIGN | APPROVE | RECOGNIZE | SIGN_AS_A_WITNESS
  final String? phone;

  const ProposalSignerInput({
    required this.email,
    required this.name,
    this.action = 'SIGN',
    this.phone,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'name': name,
        'action': action,
        if (phone != null && phone!.isNotEmpty)
          'phone': phone!.replaceAll(RegExp(r'\D'), ''),
      };
}

/// Serviço HTTP para o módulo de fichas de proposta.
///
/// Cobre todos os endpoints expostos por `PurchaseProposalsController`
/// (em `imobx/src/purchase-proposals/purchase-proposals.controller.ts`):
///   - CRUD + cancelar + soft-delete
///   - Histórico (etapas, assinaturas, anexos)
///   - PDF (bytes)
///   - Assinaturas: criar, listar, sync, link, reenviar email/whatsapp
///   - Anexos: listar, upload, aprovar, rejeitar
class PurchaseProposalsService {
  PurchaseProposalsService._();
  static final PurchaseProposalsService instance =
      PurchaseProposalsService._();

  final ApiService _api = ApiService.instance;

  // ─── Listagem / detalhe ────────────────────────────────────────────────

  Future<ApiResponse<ProposalListResult>> list({
    ProposalFilters filters = const ProposalFilters(),
  }) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.purchaseProposals,
        queryParameters: filters.toQuery(),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar fichas de proposta',
          statusCode: res.statusCode,
        );
      }
      final root = res.data!;
      final raw = root['data'];
      if (raw is! List) {
        return ApiResponse.error(
          message: 'Formato de resposta inválido',
          statusCode: res.statusCode,
        );
      }
      final items = raw
          .whereType<Map>()
          .map((m) => PurchaseProposal.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      final total = _int(root['total']) ?? items.length;
      final page = _int(root['page']) ?? filters.page;
      final limit = _int(root['limit']) ?? filters.limit;
      final totalPages = _int(root['totalPages']) ??
          ((total / (limit == 0 ? 1 : limit)).ceil());
      return ApiResponse.success(
        data: ProposalListResult(
          items: items,
          total: total,
          page: page,
          limit: limit,
          totalPages: totalPages,
        ),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] list: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<ProposalStats>> getStats() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.purchaseProposalsStats,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao obter estatísticas',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: ProposalStats.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] stats: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<PurchaseProposal>> getById(String id) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.purchaseProposalById(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar proposta',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: PurchaseProposal.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] getById: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<ProposalHistorico>> getHistorico(String id) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.purchaseProposalHistorico(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar histórico',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: ProposalHistorico.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] historico: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── CRUD ───────────────────────────────────────────────────────────────

  Future<ApiResponse<PurchaseProposal>> create(
      CreateProposalPayload payload) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.purchaseProposals,
        body: payload.toJson(),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao criar proposta',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: PurchaseProposal.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] create: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<PurchaseProposal>> update(
    String id,
    CreateProposalPayload payload,
  ) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(
        ApiConstants.purchaseProposalById(id),
        body: payload.toJson(),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao atualizar proposta',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: PurchaseProposal.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] update: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<PurchaseProposal>> cancelar(
    String id,
    String reason,
  ) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(
        ApiConstants.purchaseProposalCancelar(id),
        body: {'reason': reason},
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao cancelar proposta',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: PurchaseProposal.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] cancelar: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> excluir(String id, String reason) async {
    try {
      final res = await _api.post(
        ApiConstants.purchaseProposalExcluir(id),
        body: {'reason': reason},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao excluir proposta',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPOSALS] excluir: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<PurchaseProposal>> addUsers(
    String id,
    List<String> userIds,
  ) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.purchaseProposalUsuarios(id),
        body: {'userIds': userIds},
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao vincular usuários',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: PurchaseProposal.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] addUsers: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── PDF ────────────────────────────────────────────────────────────────

  /// Baixa o PDF da proposta como bytes. Quando `etapa` informado, gera só
  /// aquela etapa. Se `incluirAutentique=true`, o backend pode devolver ZIP.
  Future<ApiResponse<({Uint8List bytes, String contentType})>> downloadPdf(
    String id, {
    int? etapa,
    bool incluirAutentique = false,
  }) async {
    try {
      final qp = <String, String>{
        'incluirAutentique': incluirAutentique ? 'true' : 'false',
      };
      if (etapa != null) qp['etapa'] = '$etapa';
      final uri = Uri.parse(
        '${ApiConstants.baseApiUrl}${ApiConstants.purchaseProposalPdf(id)}',
      ).replace(queryParameters: qp);

      final headers = await _api.buildOutboundHeaders(
        endpoint: ApiConstants.purchaseProposalPdf(id),
        excludeContentType: true,
      );
      headers.remove('Content-Type');
      headers['Accept'] = 'application/pdf, application/zip';

      final res = await http
          .get(uri, headers: headers)
          .timeout(ApiConstants.receiveTimeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final ct = (res.headers['content-type'] ?? 'application/pdf')
            .toLowerCase();
        return ApiResponse.success(
          data: (
            bytes: res.bodyBytes,
            contentType: ct.contains('zip') ? 'application/zip' : 'application/pdf',
          ),
          statusCode: res.statusCode,
        );
      }
      String message;
      try {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['message'] != null) {
          message = body['message'].toString();
        } else {
          message = 'Erro ao baixar PDF (${res.statusCode})';
        }
      } catch (_) {
        message = 'Erro ao baixar PDF (${res.statusCode})';
      }
      return ApiResponse.error(message: message, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPOSALS] downloadPdf: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── Assinaturas ───────────────────────────────────────────────────────

  Future<ApiResponse<List<ProposalSignature>>> listSignatures(
      String id) async {
    try {
      final res = await _api.get<dynamic>(
        ApiConstants.purchaseProposalAssinaturas(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar assinaturas',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? raw['data'] : null);
      if (list is! List) {
        return ApiResponse.success(data: const [], statusCode: res.statusCode);
      }
      return ApiResponse.success(
        data: list
            .whereType<Map>()
            .map((m) =>
                ProposalSignature.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] listSignatures: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<List<ProposalSignature>>> enviarParaAssinatura(
    String id, {
    required List<ProposalSignerInput> signers,
    int? etapa,
    String? documentName,
    String? documentMessage,
    bool refusable = true,
    bool sortable = false,
  }) async {
    try {
      final document = <String, dynamic>{
        'refusable': refusable,
        'sortable': sortable,
      };
      if (documentName != null) document['name'] = documentName;
      if (documentMessage != null) document['message'] = documentMessage;
      final body = <String, dynamic>{
        'signers': signers.map((s) => s.toJson()).toList(),
        'document': document,
      };
      if (etapa != null) body['etapa'] = etapa;
      final res = await _api.post<dynamic>(
        ApiConstants.purchaseProposalAssinaturas(id),
        body: body,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao enviar para assinatura',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? raw['data'] : null);
      if (list is! List) {
        return ApiResponse.success(data: const [], statusCode: res.statusCode);
      }
      return ApiResponse.success(
        data: list
            .whereType<Map>()
            .map((m) =>
                ProposalSignature.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] enviarParaAssinatura: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<List<ProposalSignature>>> syncAssinaturas(
      String id) async {
    try {
      final res = await _api.post<dynamic>(
        ApiConstants.purchaseProposalAssinaturasSync(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao sincronizar assinaturas',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? raw['data'] : null);
      if (list is! List) {
        return ApiResponse.success(data: const [], statusCode: res.statusCode);
      }
      return ApiResponse.success(
        data: list
            .whereType<Map>()
            .map((m) =>
                ProposalSignature.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] sync: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<String>> obterLinkAssinatura(
    String proposalId,
    String signatureId,
  ) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.purchaseProposalAssinaturaLink(proposalId, signatureId),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao obter link',
          statusCode: res.statusCode,
        );
      }
      final link = res.data!['short_link']?.toString() ??
          res.data!['link']?.toString() ??
          '';
      if (link.isEmpty) {
        return ApiResponse.error(
          message: 'Link de assinatura indisponível',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: link, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPOSALS] link: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> reenviarPorEmail(
    String proposalId,
    String signatureId,
  ) async {
    try {
      final res = await _api.post(
        ApiConstants.purchaseProposalAssinaturaReenviarEmail(
          proposalId,
          signatureId,
        ),
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao reenviar e-mail',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPOSALS] reenviarEmail: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> reenviarTodosWhatsapp(
      String proposalId) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.purchaseProposalAssinaturasReenviarWhatsapp(proposalId),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao reenviar via WhatsApp',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: res.data!, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPOSALS] reenviarWhatsapp all: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> reenviarUmWhatsapp(
    String proposalId,
    String signatureId,
  ) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.purchaseProposalAssinaturaReenviarWhatsapp(
          proposalId,
          signatureId,
        ),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao reenviar via WhatsApp',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: res.data!, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPOSALS] reenviarWhatsapp one: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> reiniciarFluxoAssinaturas(String id) async {
    try {
      final res = await _api.post(
        ApiConstants.purchaseProposalReiniciarFluxoAssinaturas(id),
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao reiniciar fluxo de assinaturas',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPOSALS] reiniciar: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── Anexos ────────────────────────────────────────────────────────────

  Future<ApiResponse<List<ProposalAttachment>>> listAnexos(String id) async {
    try {
      final res = await _api.get<dynamic>(
        ApiConstants.purchaseProposalAnexos(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar anexos',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? raw['data'] : null);
      if (list is! List) {
        return ApiResponse.success(data: const [], statusCode: res.statusCode);
      }
      return ApiResponse.success(
        data: list
            .whereType<Map>()
            .map((m) =>
                ProposalAttachment.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPOSALS] anexos: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}

// ─── Helpers locais ─────────────────────────────────────────────────────

String _str(dynamic v) => v?.toString() ?? '';
String? _strNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.'));
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}
