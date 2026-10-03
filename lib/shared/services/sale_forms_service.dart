import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../utils/ficha_anexo_content_type.dart';
import 'api_service.dart';

/// Status de uma ficha de venda (espelha o backend — coluna `status`).
/// NÃO há etapas: o ciclo de vida é só pelo status.
enum SaleFormStatus { waitingForSignature, processing, finalized, canceled }

extension SaleFormStatusX on SaleFormStatus {
  String get apiValue {
    switch (this) {
      case SaleFormStatus.waitingForSignature:
        return 'waiting_for_signature';
      case SaleFormStatus.processing:
        return 'processing';
      case SaleFormStatus.finalized:
        return 'finalized';
      case SaleFormStatus.canceled:
        return 'canceled';
    }
  }

  String get label {
    switch (this) {
      case SaleFormStatus.waitingForSignature:
        return 'Aguardando assinatura';
      case SaleFormStatus.processing:
        return 'Em processamento';
      case SaleFormStatus.finalized:
        return 'Finalizada';
      case SaleFormStatus.canceled:
        return 'Cancelada';
    }
  }

  /// Rótulo curto para chips/badges.
  String get shortLabel {
    switch (this) {
      case SaleFormStatus.waitingForSignature:
        return 'Aguardando';
      case SaleFormStatus.processing:
        return 'Em processo';
      case SaleFormStatus.finalized:
        return 'Finalizadas';
      case SaleFormStatus.canceled:
        return 'Canceladas';
    }
  }
}

SaleFormStatus parseSaleFormStatus(dynamic raw) {
  final s = raw?.toString().toLowerCase().trim();
  switch (s) {
    case 'processing':
      return SaleFormStatus.processing;
    case 'finalized':
      return SaleFormStatus.finalized;
    case 'canceled':
    case 'cancelled':
      return SaleFormStatus.canceled;
    default:
      return SaleFormStatus.waitingForSignature;
  }
}

/// Tipo da ficha (modelo de negócio) — escolhido na criação.
enum SaleFormType { terceiros, lancamento, casaMinhaVida }

extension SaleFormTypeX on SaleFormType {
  String get apiValue {
    switch (this) {
      case SaleFormType.terceiros:
        return 'terceiros';
      case SaleFormType.lancamento:
        return 'lancamento';
      case SaleFormType.casaMinhaVida:
        return 'casa_minha_vida';
    }
  }

  String get label {
    switch (this) {
      case SaleFormType.terceiros:
        return 'Terceiros';
      case SaleFormType.lancamento:
        return 'Lançamento';
      case SaleFormType.casaMinhaVida:
        return 'Casa Minha Vida';
    }
  }

  /// `true` para tipos que usam "Empreendimento" em vez de "Imóvel".
  bool get isEmpreendimento => this != SaleFormType.terceiros;
}

SaleFormType parseSaleFormType(dynamic raw) {
  final s = raw?.toString().toLowerCase().trim();
  switch (s) {
    case 'lancamento':
      return SaleFormType.lancamento;
    case 'casa_minha_vida':
      return SaleFormType.casaMinhaVida;
    default:
      return SaleFormType.terceiros;
  }
}

/// Modelo de pagamento de comissão.
enum CommissionPaymentModel { obrigatorio, naoAplicavel }

CommissionPaymentModel parseCommissionPaymentModel(dynamic raw) {
  final s = raw?.toString().toLowerCase().trim();
  return s == 'nao_aplicavel'
      ? CommissionPaymentModel.naoAplicavel
      : CommissionPaymentModel.obrigatorio;
}

/// Ficha de venda — espelha o entity do backend. Guardamos o `raw` para
/// acessar campos raros sem precisar mapear tudo, com getters tipados nos
/// campos usados pela UI.
class SaleForm {
  final Map<String, dynamic> raw;
  const SaleForm(this.raw);

  factory SaleForm.fromJson(Map<String, dynamic> j) =>
      SaleForm(Map<String, dynamic>.from(j));

  // ── Identidade / meta ──────────────────────────────────────────────────
  String get id => _str(raw['id']);
  String get formNumber => _str(raw['formNumber'] ?? raw['form_number']);
  SaleFormStatus get status => parseSaleFormStatus(raw['status']);

  /// Distrato (30/09/2026, paridade com `distratoDaFicha` do web): aberto =
  /// ficha cancelada por distrato aguardando a prova no Financeiro;
  /// concluído = o Financeiro recebeu a prova.
  bool get distratoAberto {
    final v = raw['distratoAbertoEm'];
    return v != null && v.toString().isNotEmpty;
  }

  bool get distratoConcluido {
    final v = raw['distratoConcluidoEm'];
    return distratoAberto && v != null && v.toString().isNotEmpty;
  }

  /// Rótulo do status igual ao web: distrato vence o "Cancelada".
  String get statusLabel {
    if (distratoConcluido) return 'Distratada';
    if (distratoAberto) return 'Em distrato — aguardando anexo no Financeiro';
    return status.label;
  }

  /// Rótulo curto da pílula (web `saleFormStatusShortLabel` para distrato).
  String get statusShortLabel {
    if (distratoConcluido) return 'Distratada';
    if (distratoAberto) return 'Em distrato';
    return status.label;
  }

  SaleFormType get saleFormType =>
      parseSaleFormType(raw['saleFormType'] ?? raw['sale_form_type']);
  bool get ativo => _bool(raw['ativo'], defaultValue: true);

  // ── Equipe / unidade ───────────────────────────────────────────────────
  String? get teamId => _strNull(raw['teamId'] ?? raw['team_id']);
  String? get teamName {
    final t = raw['team'];
    if (t is Map) return _strNull(t['name']);
    return _strNull(raw['teamName']);
  }

  String? get teamColor {
    final t = raw['team'];
    if (t is Map) return _strNull(t['color']);
    return null;
  }

  String? get saleUnit => _strNull(raw['saleUnit'] ?? raw['sale_unit']);

  // ── Venda / geral ──────────────────────────────────────────────────────
  DateTime? get saleDate => _date(raw['saleDate'] ?? raw['sale_date']);
  String? get mediaSource => _strNull(raw['mediaSource'] ?? raw['media_source']);
  String? get description => _strNull(raw['description']);
  String? get managerName => _strNull(raw['managerName'] ?? raw['manager_name']);
  String? get externalBrokerName =>
      _strNull(raw['externalBrokerName'] ?? raw['external_broker_name']);

  // ── Comprador ──────────────────────────────────────────────────────────
  String? get buyerName => _strNull(raw['buyerName'] ?? raw['buyer_name']);
  String? get buyerCpf => _strNull(raw['buyerCpf'] ?? raw['buyer_cpf']);
  String? get buyerEmail => _strNull(raw['buyerEmail'] ?? raw['buyer_email']);
  String? get buyerPhone => _strNull(raw['buyerPhone'] ?? raw['buyer_phone']);
  String? get buyerCity => _strNull(raw['buyerCity'] ?? raw['buyer_city']);
  String? get buyerState => _strNull(raw['buyerState'] ?? raw['buyer_state']);

  // ── Vendedor ───────────────────────────────────────────────────────────
  String? get sellerName => _strNull(raw['sellerName'] ?? raw['seller_name']);
  String? get sellerCpf => _strNull(raw['sellerCpf'] ?? raw['seller_cpf']);
  String? get sellerEmail => _strNull(raw['sellerEmail'] ?? raw['seller_email']);
  String? get sellerPhone => _strNull(raw['sellerPhone'] ?? raw['seller_phone']);

  // ── Imóvel ─────────────────────────────────────────────────────────────
  String? get propertyId => _strNull(raw['propertyId'] ?? raw['property_id']);
  String? get propertyCode =>
      _strNull(raw['propertyCode'] ?? raw['property_code']);
  String? get propertyNeighborhood =>
      _strNull(raw['propertyNeighborhood'] ?? raw['property_neighborhood']);
  String? get propertyCity =>
      _strNull(raw['propertyCity'] ?? raw['property_city']);
  String? get propertyState =>
      _strNull(raw['propertyState'] ?? raw['property_state']);

  // ── Financeiro ─────────────────────────────────────────────────────────
  double? get saleValue => _num(raw['saleValue'] ?? raw['sale_value']);
  double? get totalCommission =>
      _num(raw['totalCommission'] ?? raw['total_commission']);
  double? get goalValue => _num(raw['goalValue'] ?? raw['goal_value']);
  CommissionPaymentModel get commissionPaymentModel =>
      parseCommissionPaymentModel(
        raw['commissionPaymentModel'] ?? raw['commission_payment_model'],
      );

  // ── Objetos JSON ───────────────────────────────────────────────────────
  Map<String, dynamic>? get empreendimentoData =>
      _map(raw['empreendimentoData'] ?? raw['empreendimento_data']);
  Map<String, dynamic>? get commissionsData =>
      _map(raw['commissionsData'] ?? raw['commissions_data']);
  Map<String, dynamic>? get collaboratorsData =>
      _map(raw['collaboratorsData'] ?? raw['collaborators_data']);

  List<dynamic> get corretores {
    final c = commissionsData?['corretores'];
    return c is List ? c : const [];
  }

  // ── Auditoria / autoria ────────────────────────────────────────────────
  String? get cancellationReason =>
      _strNull(raw['cancellationReason'] ?? raw['cancellation_reason']);
  String? get deletionReason =>
      _strNull(raw['deletionReason'] ?? raw['deletion_reason']);
  DateTime? get deletedAt => _date(raw['deletedAt'] ?? raw['deleted_at']);

  String? get creatorName {
    final u = raw['user'];
    if (u is Map) return _strNull(u['name']);
    return _strNull(raw['creatorName']);
  }

  DateTime? get createdAt => _date(raw['createdAt'] ?? raw['created_at']);
  DateTime? get updatedAt => _date(raw['updatedAt'] ?? raw['updated_at']);

  // ── Assinaturas (resumo p/ fases futuras) ──────────────────────────────
  int get assinaturasTotal => _int(raw['assinaturasTotal']) ?? 0;
  int get assinaturasAssinadas => _int(raw['assinaturasAssinadas']) ?? 0;

  /// Regra do backend (criador, admin/master, líder de equipe do criador ou
  /// gestor com acesso) para "Cancelar todas as assinaturas (reenvio)". Vem
  /// na listagem e no `GET /:id`; ausente = não pode.
  bool get canInvalidateSignatures =>
      _bool(raw['canInvalidateSignatures'], defaultValue: false);

  /// Usuários vinculados à ficha (`linkedUsers` do `GET /:id`, relação
  /// `sale_form_users` + `user`). Cada item traz `userId` e, quando o back
  /// carrega, o objeto `user` ({id, name, email}).
  List<Map<String, dynamic>> get linkedUsers {
    final l = raw['linkedUsers'] ?? raw['linked_users'];
    if (l is! List) return const [];
    return l
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
}

/// Estatísticas do hero (`GET /sistema/fichas-venda/stats`).
class SaleFormStats {
  final int total;
  final int waitingForSignature;
  final int processing;
  final int finalized;
  final int canceled;

  const SaleFormStats({
    required this.total,
    required this.waitingForSignature,
    required this.processing,
    required this.finalized,
    required this.canceled,
  });

  static const SaleFormStats zero = SaleFormStats(
    total: 0,
    waitingForSignature: 0,
    processing: 0,
    finalized: 0,
    canceled: 0,
  );

  factory SaleFormStats.fromJson(Map<String, dynamic> j) {
    final root = j['data'] is Map ? Map<String, dynamic>.from(j['data']) : j;
    return SaleFormStats(
      total: _int(root['total']) ?? 0,
      waitingForSignature:
          _int(root['waiting_for_signature'] ?? root['waitingForSignature']) ??
              0,
      processing: _int(root['processing']) ?? 0,
      finalized: _int(root['finalized']) ?? 0,
      canceled: _int(root['canceled'] ?? root['cancelled']) ?? 0,
    );
  }
}

class SaleFormListResult {
  final List<SaleForm> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const SaleFormListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });
}

const _kKeep = Object();

/// Filtros da listagem — espelho de `SaleFormFilters` do web
/// (`saleFormsApi.ts`) e do `ListSaleFormsDto` do back.
///
/// Listas (`statuses`, `userIds`, `teamIds`, `unitIds`) vão **separadas por
/// vírgula** numa chave só: o `@Transform` do DTO faz `split(',')` (aceita
/// tanto chave repetida quanto vírgula), e o `ApiService` só leva
/// `Map<String, String>`. Datas vão como `YYYY-MM-DD` (dia local, igual ao
/// web); no `dateTo` o back inclui o dia inteiro.
class SaleFormFilters {
  final String? search;

  /// Status único (legado). O back une `status` + `statuses` (OR).
  final SaleFormStatus? status;

  /// Vários status (chips do topo e do modal — multi, como no web).
  final List<SaleFormStatus> statuses;
  final String? saleUnit;
  final bool? listDeletedOnly;

  /// Um criador específico (gestor/admin) — o web não expõe na lista.
  final String? userId;

  /// Corretores (criadores das fichas).
  final List<String> userIds;

  /// Equipes vinculadas às fichas.
  final List<String> teamIds;

  /// Unidades (filiais): ficha dona ou compartilhada — usado pelo painel.
  final List<String> unitIds;

  /// Apenas fichas com compartilhamento ativo entre unidades.
  final bool? sharedOnly;

  /// Criação da ficha (dia inicial / final).
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Data da venda (`saleDate`), não a de criação.
  final DateTime? saleDateFrom;
  final DateTime? saleDateTo;
  final int page;
  final int limit;
  final String sortBy;
  final String sortOrder;

  const SaleFormFilters({
    this.search,
    this.status,
    this.statuses = const [],
    this.saleUnit,
    this.listDeletedOnly,
    this.userId,
    this.userIds = const [],
    this.teamIds = const [],
    this.unitIds = const [],
    this.sharedOnly,
    this.dateFrom,
    this.dateTo,
    this.saleDateFrom,
    this.saleDateTo,
    this.page = 1,
    this.limit = 20,
    this.sortBy = 'createdAt',
    this.sortOrder = 'DESC',
  });

  /// `status` + `statuses` sem repetição, na ordem do enum.
  List<SaleFormStatus> get effectiveStatuses => [
        for (final s in SaleFormStatus.values)
          if (s == status || statuses.contains(s)) s,
      ];

  /// Contagem do botão "Filtros" — mesma regra de
  /// `countSaleFormsDrawerFilters` (web): status conta 1, cada lista conta 1,
  /// cada data conta 1. Busca fica fora (tem campo próprio na lista).
  int get drawerFilterCount {
    var n = 0;
    if (effectiveStatuses.isNotEmpty) n++;
    if (userIds.isNotEmpty || (userId?.isNotEmpty ?? false)) n++;
    if (teamIds.isNotEmpty) n++;
    if (unitIds.isNotEmpty) n++;
    if (sharedOnly == true) n++;
    if (saleUnit?.trim().isNotEmpty ?? false) n++;
    if (dateFrom != null) n++;
    if (dateTo != null) n++;
    if (saleDateFrom != null) n++;
    if (saleDateTo != null) n++;
    return n;
  }

  /// "Limpar" do modal (web `handleClearFilters`): zera os recortes, mantém
  /// busca, ordenação e paginação.
  SaleFormFilters withoutListFilters() => SaleFormFilters(
        search: search,
        listDeletedOnly: listDeletedOnly,
        limit: limit,
        sortBy: sortBy,
        sortOrder: sortOrder,
      );

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String? _csv(Iterable<String> values) {
    final list =
        values.map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    return list.isEmpty ? null : list.join(',');
  }

  Map<String, String> toQuery() {
    final qp = <String, String>{
      'page': '$page',
      'limit': '$limit',
      'sortBy': sortBy,
      'sortOrder': sortOrder,
    };
    final s = search?.trim();
    if (s != null && s.isNotEmpty) qp['search'] = s;
    final sts = effectiveStatuses;
    // Igual ao web: `status` só quando há exatamente um; `statuses` sempre.
    if (sts.length == 1) qp['status'] = sts.first.apiValue;
    final stsCsv = _csv(sts.map((e) => e.apiValue));
    if (stsCsv != null) qp['statuses'] = stsCsv;
    if (saleUnit != null && saleUnit!.trim().isNotEmpty) {
      qp['saleUnit'] = saleUnit!.trim();
    }
    if (userId != null && userId!.trim().isNotEmpty) {
      qp['userId'] = userId!.trim();
    }
    final usersCsv = _csv(userIds);
    if (usersCsv != null) qp['userIds'] = usersCsv;
    final teamsCsv = _csv(teamIds);
    if (teamsCsv != null) qp['teamIds'] = teamsCsv;
    final unitsCsv = _csv(unitIds);
    if (unitsCsv != null) qp['unitIds'] = unitsCsv;
    if (sharedOnly == true) qp['sharedOnly'] = 'true';
    if (dateFrom != null) qp['dateFrom'] = _ymd(dateFrom!);
    if (dateTo != null) qp['dateTo'] = _ymd(dateTo!);
    if (saleDateFrom != null) qp['saleDateFrom'] = _ymd(saleDateFrom!);
    if (saleDateTo != null) qp['saleDateTo'] = _ymd(saleDateTo!);
    if (listDeletedOnly == true) qp['listDeletedOnly'] = 'true';
    return qp;
  }

  /// Anuláveis: passar `null` limpa, omitir mantém. Listas: `null` mantém,
  /// lista vazia limpa.
  SaleFormFilters copyWith({
    Object? search = _kKeep,
    Object? status = _kKeep,
    List<SaleFormStatus>? statuses,
    Object? saleUnit = _kKeep,
    Object? listDeletedOnly = _kKeep,
    Object? userId = _kKeep,
    List<String>? userIds,
    List<String>? teamIds,
    List<String>? unitIds,
    Object? sharedOnly = _kKeep,
    Object? dateFrom = _kKeep,
    Object? dateTo = _kKeep,
    Object? saleDateFrom = _kKeep,
    Object? saleDateTo = _kKeep,
    int? page,
    int? limit,
    String? sortBy,
    String? sortOrder,
  }) =>
      SaleFormFilters(
        search: identical(search, _kKeep) ? this.search : search as String?,
        status: identical(status, _kKeep)
            ? this.status
            : status as SaleFormStatus?,
        statuses: statuses ?? this.statuses,
        saleUnit:
            identical(saleUnit, _kKeep) ? this.saleUnit : saleUnit as String?,
        listDeletedOnly: identical(listDeletedOnly, _kKeep)
            ? this.listDeletedOnly
            : listDeletedOnly as bool?,
        userId: identical(userId, _kKeep) ? this.userId : userId as String?,
        userIds: userIds ?? this.userIds,
        teamIds: teamIds ?? this.teamIds,
        unitIds: unitIds ?? this.unitIds,
        sharedOnly: identical(sharedOnly, _kKeep)
            ? this.sharedOnly
            : sharedOnly as bool?,
        dateFrom: identical(dateFrom, _kKeep)
            ? this.dateFrom
            : dateFrom as DateTime?,
        dateTo: identical(dateTo, _kKeep) ? this.dateTo : dateTo as DateTime?,
        saleDateFrom: identical(saleDateFrom, _kKeep)
            ? this.saleDateFrom
            : saleDateFrom as DateTime?,
        saleDateTo: identical(saleDateTo, _kKeep)
            ? this.saleDateTo
            : saleDateTo as DateTime?,
        page: page ?? this.page,
        limit: limit ?? this.limit,
        sortBy: sortBy ?? this.sortBy,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// Assinatura de uma ficha de venda (a ficha de venda NÃO tem etapas).
class SaleFormSignature {
  final String id;
  final String saleFormId;
  final String status;
  final String? signerName;
  final String? signerEmail;
  final String? signatureUrl;
  final DateTime? signedAt;
  final DateTime? createdAt;

  const SaleFormSignature({
    required this.id,
    required this.saleFormId,
    required this.status,
    this.signerName,
    this.signerEmail,
    this.signatureUrl,
    this.signedAt,
    this.createdAt,
  });

  bool get isSigned => status.toLowerCase() == 'signed';
  bool get isRejected {
    final s = status.toLowerCase();
    return s == 'rejected' || s == 'refused';
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'signed':
        return 'Assinado';
      case 'rejected':
      case 'refused':
        return 'Rejeitado';
      case 'viewed':
        return 'Visualizado';
      case 'cancelled':
      case 'canceled':
        return 'Cancelado';
      case 'expired':
        return 'Expirado';
      default:
        return 'Pendente';
    }
  }

  factory SaleFormSignature.fromJson(Map<String, dynamic> j) =>
      SaleFormSignature(
        id: _str(j['id']),
        saleFormId: _str(j['saleFormId'] ?? j['sale_form_id']),
        status: _str(j['status']),
        signerName: _strNull(j['signerName'] ?? j['signer_name']),
        signerEmail: _strNull(j['signerEmail'] ?? j['signer_email']),
        signatureUrl: _strNull(j['signatureUrl'] ?? j['signature_url']),
        signedAt: _date(j['signedAt'] ?? j['signed_at']),
        createdAt: _date(j['createdAt'] ?? j['created_at']),
      );
}

/// Anexo de uma ficha de venda.
class SaleFormAttachment {
  final String id;
  final String saleFormId;
  final String? fileKey;
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final String? contentType;
  final String? descricao;
  final String status; // pending_approval | approved | rejected
  final String? uploadedByName;
  final String? approvedByCpf;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final DateTime? createdAt;

  const SaleFormAttachment({
    required this.id,
    required this.saleFormId,
    this.fileKey,
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    this.contentType,
    this.descricao,
    required this.status,
    this.uploadedByName,
    this.approvedByCpf,
    this.approvedAt,
    this.rejectionReason,
    this.createdAt,
  });

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'approved':
        return 'Aprovado';
      case 'rejected':
        return 'Rejeitado';
      case 'pending_approval':
      default:
        // Web (`FichaVendaAnexosModalPrivate.tsx`): "Pendente".
        return 'Pendente';
    }
  }

  factory SaleFormAttachment.fromJson(Map<String, dynamic> j) =>
      SaleFormAttachment(
        id: _str(j['id']),
        saleFormId: _str(j['saleFormId'] ?? j['sale_form_id']),
        fileKey: _strNull(j['fileKey'] ?? j['file_key']),
        fileUrl: _str(j['fileUrl'] ?? j['file_url']),
        fileName: _str(j['fileName'] ?? j['file_name']),
        fileSize: _int(j['fileSize'] ?? j['file_size']) ?? 0,
        contentType: _strNull(j['contentType'] ?? j['content_type']),
        descricao: _strNull(j['descricao'] ?? j['description']),
        status: _str(j['status']),
        uploadedByName:
            _strNull(j['uploadedByName'] ?? j['uploaded_by_name']),
        approvedByCpf: _strNull(j['approvedByCpf'] ?? j['approved_by_cpf']),
        approvedAt: _date(j['approvedAt'] ?? j['approved_at']),
        rejectionReason:
            _strNull(j['rejectionReason'] ?? j['rejection_reason']),
        createdAt: _date(j['createdAt'] ?? j['created_at']),
      );
}

/// Prévia de um signatário sugerido pelo backend. O fluxo "automático" traz
/// `source` ('mandatory' = obrigatório da empresa, 'pdf' = extraído do PDF).
class SaleFormSignerPreview {
  final String name;
  final String email;
  final String? source; // 'mandatory' | 'pdf' | null

  const SaleFormSignerPreview({
    required this.name,
    required this.email,
    this.source,
  });

  factory SaleFormSignerPreview.fromJson(Map<String, dynamic> j) =>
      SaleFormSignerPreview(
        name: _str(j['name'] ?? j['signerName'] ?? j['signer_name']),
        email: _str(j['email'] ?? j['signerEmail'] ?? j['signer_email']),
        source: _strNull(j['source']),
      );
}

/// Entrada de signatário para envio manual à assinatura.
class SaleFormSignerInput {
  final String? email;
  final String name;
  final String action; // SIGN | APPROVE | ...

  const SaleFormSignerInput({
    this.email,
    required this.name,
    this.action = 'SIGN',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'action': action,
        if (email != null && email!.trim().isNotEmpty) 'email': email!.trim(),
      };
}

/// Configuração de envio via WhatsApp da ficha de venda.
class SaleFormWhatsappEnvio {
  final bool autoSendEnabled;
  final String? sessionKind;
  final bool canResend;

  /// Sessão escolhida em Signatários obrigatórios › WhatsApp (null = automático).
  final String? preferredSessionKind;

  /// Número que envia os links, quando conhecido (só dígitos).
  final String? phoneNumber;

  const SaleFormWhatsappEnvio({
    required this.autoSendEnabled,
    this.sessionKind,
    required this.canResend,
    this.preferredSessionKind,
    this.phoneNumber,
  });

  factory SaleFormWhatsappEnvio.fromJson(Map<String, dynamic> j) {
    final root = j['data'] is Map ? Map<String, dynamic>.from(j['data']) : j;
    return SaleFormWhatsappEnvio(
      autoSendEnabled:
          _bool(root['autoSendEnabled'] ?? root['auto_send_enabled']),
      sessionKind: _strNull(root['sessionKind'] ?? root['session_kind']),
      canResend: _bool(root['canResend'] ?? root['can_resend']),
      preferredSessionKind: _strNull(
        root['preferredSessionKind'] ?? root['preferred_session_kind'],
      ),
      phoneNumber: _strNull(root['phoneNumber'] ?? root['phone_number']),
    );
  }
}

/// Resultado de um envio dos links por e-mail (`POST …/reenviar-email`) e,
/// com [at], o último envio registrado (`GET …/assinaturas/email-envio`).
class SaleFormEmailEnvio {
  /// 'enviado' | 'parcial' | 'nao_enviado'
  final String status;
  final String? motivo;
  final int sent;
  final int failed;
  final int skippedNoEmail;
  final int total;

  /// 'criacao' | 'reenvio_manual'
  final String? origem;
  final DateTime? at;

  const SaleFormEmailEnvio({
    required this.status,
    this.motivo,
    required this.sent,
    required this.failed,
    required this.skippedNoEmail,
    required this.total,
    this.origem,
    this.at,
  });

  factory SaleFormEmailEnvio.fromJson(Map<String, dynamic> j) =>
      SaleFormEmailEnvio(
        status: _str(j['status']),
        motivo: _strNull(j['motivo']),
        sent: _int(j['sent']) ?? 0,
        failed: _int(j['failed']) ?? 0,
        skippedNoEmail: _int(j['skippedNoEmail']) ?? 0,
        total: _int(j['total']) ?? 0,
        origem: _strNull(j['origem']),
        at: _date(j['at']),
      );

  /// "2 e-mail(s) enviado(s) · 1 sem e-mail" — mesmo texto do web.
  String get resumo {
    final parts = <String>[
      if (sent > 0) '$sent e-mail(s) enviado(s)',
      if (skippedNoEmail > 0) '$skippedNoEmail sem e-mail',
      if (failed > 0) '$failed falha(s)',
    ];
    return parts.isEmpty ? 'Nenhum e-mail enviado.' : parts.join(' · ');
  }
}

/// Um signatário que ainda não assinou (`GET …/assinaturas/pendentes`).
class SaleFormPendingSignature {
  final String signatureId;
  final String? signerName;
  final String? signerEmail;

  /// 'pending' | 'viewed'
  final String status;
  final DateTime? viewedAt;
  final DateTime? enviadaEm;
  final int diasPendente;
  final String? signatureUrl;

  /// `true` quando o signatário é o usuário logado (o back compara o e-mail).
  final bool ehVoce;
  final int lembretesWhatsApp;

  const SaleFormPendingSignature({
    required this.signatureId,
    this.signerName,
    this.signerEmail,
    required this.status,
    this.viewedAt,
    this.enviadaEm,
    required this.diasPendente,
    this.signatureUrl,
    required this.ehVoce,
    required this.lembretesWhatsApp,
  });

  bool get abriu => status.toLowerCase() == 'viewed';

  /// Nome exibido (nome → e-mail → travessão), como `nomeDoSignatario` do web.
  String get nomeExibido {
    final n = signerName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final e = signerEmail?.trim() ?? '';
    return e.isNotEmpty ? e : '—';
  }

  /// Link externo seguro (só http/https) — espelho de `linkAbrivel` do web.
  String? get linkAbrivel => saleFormLinkAbrivel(signatureUrl);

  factory SaleFormPendingSignature.fromJson(Map<String, dynamic> j) =>
      SaleFormPendingSignature(
        signatureId: _str(j['signatureId'] ?? j['id']),
        signerName: _strNull(j['signerName']),
        signerEmail: _strNull(j['signerEmail']),
        status: _str(j['status']),
        viewedAt: _date(j['viewedAt']),
        enviadaEm: _date(j['enviadaEm']),
        diasPendente: _int(j['diasPendente']) ?? 0,
        signatureUrl: _strNull(j['signatureUrl']),
        ehVoce: _bool(j['ehVoce']),
        lembretesWhatsApp: _int(j['lembretesWhatsApp']) ?? 0,
      );
}

/// Ficha com assinatura em aberto no painel de pendentes.
class SaleFormWithPendingSignatures {
  final String saleFormId;
  final String formNumber;
  final String? buyerName;
  final String? sellerName;
  final String? criadorId;
  final String? criadorName;
  final DateTime? enviadaEm;
  final int diasPendente;
  final int assinadas;
  final int total;
  final List<SaleFormPendingSignature> pendentes;
  final DateTime? ultimoEmailEm;
  final DateTime? ultimoWhatsAppEm;

  const SaleFormWithPendingSignatures({
    required this.saleFormId,
    required this.formNumber,
    this.buyerName,
    this.sellerName,
    this.criadorId,
    this.criadorName,
    this.enviadaEm,
    required this.diasPendente,
    required this.assinadas,
    required this.total,
    required this.pendentes,
    this.ultimoEmailEm,
    this.ultimoWhatsAppEm,
  });

  factory SaleFormWithPendingSignatures.fromJson(Map<String, dynamic> j) {
    final criador = j['criador'];
    final email = j['ultimoEmail'];
    final wa = j['ultimoWhatsApp'];
    final pend = j['pendentes'];
    return SaleFormWithPendingSignatures(
      saleFormId: _str(j['saleFormId']),
      formNumber: _str(j['formNumber']),
      buyerName: _strNull(j['buyerName']),
      sellerName: _strNull(j['sellerName']),
      criadorId: criador is Map ? _strNull(criador['id']) : null,
      criadorName: criador is Map ? _strNull(criador['name']) : null,
      enviadaEm: _date(j['enviadaEm']),
      diasPendente: _int(j['diasPendente']) ?? 0,
      assinadas: _int(j['assinadas']) ?? 0,
      total: _int(j['total']) ?? 0,
      pendentes: pend is List
          ? pend
              .whereType<Map>()
              .map((m) => SaleFormPendingSignature.fromJson(
                    Map<String, dynamic>.from(m),
                  ))
              .toList()
          : const [],
      ultimoEmailEm: email is Map ? _date(email['at']) : null,
      ultimoWhatsAppEm: wa is Map ? _date(wa['at']) : null,
    );
  }
}

/// Resposta de `GET /sistema/fichas-venda/assinaturas/pendentes?escopo=`.
class SaleFormPendingSignaturesResponse {
  /// 'minhas' | 'todas'
  final String escopo;
  final int diasParaTravar;
  final int resumoFichas;
  final int resumoAssinaturas;
  final int resumoMinhas;
  final int resumoParadas;
  final int resumoSemEmail;
  final List<SaleFormWithPendingSignatures> fichas;

  const SaleFormPendingSignaturesResponse({
    required this.escopo,
    required this.diasParaTravar,
    required this.resumoFichas,
    required this.resumoAssinaturas,
    required this.resumoMinhas,
    required this.resumoParadas,
    required this.resumoSemEmail,
    required this.fichas,
  });

  factory SaleFormPendingSignaturesResponse.fromJson(Map<String, dynamic> j) {
    final r = j['resumo'] is Map
        ? Map<String, dynamic>.from(j['resumo'] as Map)
        : const <String, dynamic>{};
    final f = j['fichas'];
    return SaleFormPendingSignaturesResponse(
      escopo: _str(j['escopo']),
      diasParaTravar: _int(j['diasParaTravar']) ?? 3,
      resumoFichas: _int(r['fichas']) ?? 0,
      resumoAssinaturas: _int(r['assinaturas']) ?? 0,
      resumoMinhas: _int(r['minhas']) ?? 0,
      resumoParadas: _int(r['paradas']) ?? 0,
      resumoSemEmail: _int(r['semEmail']) ?? 0,
      fichas: f is List
          ? f
              .whereType<Map>()
              .map((m) => SaleFormWithPendingSignatures.fromJson(
                    Map<String, dynamic>.from(m),
                  ))
              .toList()
          : const [],
    );
  }
}

/// Item da trava de assinatura (`GET …/assinatura-lock/status`).
class SaleFormSignatureLockItem {
  final String saleFormId;
  final String formNumber;
  final String? signerEmail;
  final int daysPending;
  final int notificationCount;

  const SaleFormSignatureLockItem({
    required this.saleFormId,
    required this.formNumber,
    this.signerEmail,
    required this.daysPending,
    required this.notificationCount,
  });

  factory SaleFormSignatureLockItem.fromJson(Map<String, dynamic> j) =>
      SaleFormSignatureLockItem(
        saleFormId: _str(j['saleFormId']),
        formNumber: _str(j['formNumber']),
        signerEmail: _strNull(j['signerEmail']),
        daysPending: _int(j['daysPending']) ?? 0,
        notificationCount: _int(j['notificationCount']) ?? 0,
      );
}

class SaleFormSignatureLockStatus {
  final bool blocked;
  final int maxNotifications;
  final int thresholdDays;
  final List<SaleFormSignatureLockItem> items;

  const SaleFormSignatureLockStatus({
    required this.blocked,
    required this.maxNotifications,
    required this.thresholdDays,
    required this.items,
  });

  factory SaleFormSignatureLockStatus.fromJson(Map<String, dynamic> j) {
    final items = j['items'];
    return SaleFormSignatureLockStatus(
      blocked: _bool(j['blocked']),
      maxNotifications: _int(j['maxNotifications']) ?? 3,
      thresholdDays: _int(j['thresholdDays']) ?? 3,
      items: items is List
          ? items
              .whereType<Map>()
              .map((m) => SaleFormSignatureLockItem.fromJson(
                    Map<String, dynamic>.from(m),
                  ))
              .toList()
          : const [],
    );
  }
}

/// Membro da empresa para o seletor de signatários extras
/// (`GET /users/company-members`).
class SaleFormCompanyMember {
  final String id;
  final String name;
  final String email;

  const SaleFormCompanyMember({
    required this.id,
    required this.name,
    required this.email,
  });

  factory SaleFormCompanyMember.fromJson(Map<String, dynamic> j) =>
      SaleFormCompanyMember(
        id: _str(j['id']),
        name: _str(j['name']),
        email: _str(j['email']),
      );
}

/// Link externo seguro para abrir fora do app (só http/https) — espelho de
/// `linkAbrivel` (`regrasDasAssinaturas.ts`).
String? saleFormLinkAbrivel(String? url) {
  final u = (url ?? '').trim();
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(u) ? u : null;
}

/// Contas administrativas genéricas e nomes institucionais que não podem ir
/// para o Autentique — espelho de `saleFormMandatorySignersFilter.ts` (web)
/// e `sale-form-mandatory-signers.filter.ts` (back).
bool saleFormSignerExcluido({String? email, String? name}) {
  const emails = {
    'administrativo@imobiliariauniao.com.br',
    'sistema@imobx.com.br',
  };
  const nomes = {
    'uniao imobiliaria',
    'uniao empreendimentos imobiliarios',
    'uniao empreendimentos imobiliarios s/c ltda',
    'sistema imobx (remetente)',
    'sistema imobx',
  };
  final e = (email ?? '').trim().toLowerCase();
  if (e.isNotEmpty && emails.contains(e)) return true;
  final n = _semAcento((name ?? '').trim().toLowerCase());
  return n.isNotEmpty && nomes.contains(n);
}

String _semAcento(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString();
}

/// Service de Fichas de Venda — espelha `saleFormsApi.ts` (web) e o
/// `SaleFormsController` do backend. Fase 1: leitura + cancelar/excluir.
/// Teto das operações pesadas de assinatura (paridade com o web: 120 s).
const Duration _kLongTimeout = Duration(seconds: 120);

/// Teto de criar/editar ficha — igual ao web (`saleFormsApi.ts`,
/// `SALE_FORMS_LONG_REQUEST_TIMEOUT_MS` = 120 s). Com 30 s o app dava erro com a
/// ficha talvez já criada, e o reenvio duplicava.
const Duration kSaleFormSaveTimeout = Duration(seconds: 120);

class SaleFormsService {
  SaleFormsService._();
  static final SaleFormsService instance = SaleFormsService._();

  final ApiService _api = ApiService.instance;

  Future<ApiResponse<SaleFormListResult>> list({
    SaleFormFilters filters = const SaleFormFilters(),
  }) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.saleForms,
        queryParameters: filters.toQuery(),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar fichas de venda',
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
          .map((m) => SaleForm.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      final total = _int(root['total']) ?? items.length;
      final page = _int(root['page']) ?? filters.page;
      final limit = _int(root['limit']) ?? filters.limit;
      final totalPages = _int(root['totalPages']) ??
          ((total / (limit == 0 ? 1 : limit)).ceil());
      return ApiResponse.success(
        data: SaleFormListResult(
          items: items,
          total: total,
          page: page,
          limit: limit,
          totalPages: totalPages,
        ),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] list: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Linhas brutas para o relatório XLSX — `fetchAllSaleFormsForExport` do
  /// web: percorre as páginas (100 por vez, o `@Max(100)` do
  /// `ListSaleFormsDto`) com `includeLastAuditChanges=true`, até
  /// [maxRows]. `truncated` = havia mais fichas que o limite.
  Future<ApiResponse<({List<Map<String, dynamic>> rows, bool truncated})>>
      listForExport(
    SaleFormFilters base, {
    int pageSize = 100,
    int maxRows = 5000,
  }) async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    var total = -1;
    try {
      while (rows.length < maxRows && (total < 0 || rows.length < total)) {
        final qp = base.copyWith(page: page, limit: pageSize).toQuery()
          ..['includeLastAuditChanges'] = 'true';
        final res = await _api.get<Map<String, dynamic>>(
          ApiConstants.saleForms,
          queryParameters: qp,
        );
        if (!res.success || res.data == null) {
          return ApiResponse.error(
            message: res.message ?? 'Erro ao buscar as fichas para exportar',
            statusCode: res.statusCode,
          );
        }
        final data = res.data!['data'];
        final list = data is List ? data.whereType<Map>().toList() : const [];
        for (final m in list) {
          rows.add(Map<String, dynamic>.from(m));
        }
        total = _int(res.data!['total']) ?? rows.length;
        if (list.length < pageSize) break;
        page++;
      }
      final truncated = total > maxRows && rows.length >= maxRows;
      return ApiResponse.success(
        data: (
          rows: rows.length > maxRows ? rows.sublist(0, maxRows) : rows,
          truncated: truncated,
        ),
        statusCode: 200,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] listForExport: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Travas de comissão da empresa da ficha. Mesmo contrato da web
  /// (`saleFormCommissionRules.ts`): `null` num campo = sem trava; no
  /// diretor, `null` = a empresa não usa a função.
  Future<ApiResponse<SaleFormCommissionRules>> getCommissionRules() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.saleFormCommissionRules,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao obter regras de comissão',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: SaleFormCommissionRules.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] commission rules: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<SaleFormStats>> getStats({
    SaleFormFilters filters = const SaleFormFilters(),
  }) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.saleFormsStats,
        queryParameters: filters.toQuery(),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao obter estatísticas',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: SaleFormStats.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] stats: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<SaleForm>> getById(String id) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.saleFormById(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar ficha de venda',
          statusCode: res.statusCode,
        );
      }
      final root = res.data!;
      final body = root['data'] is Map
          ? Map<String, dynamic>.from(root['data'] as Map)
          : root;
      return ApiResponse.success(
        data: SaleForm.fromJson(body),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] getById: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Cria uma ficha de venda. `POST /sistema/fichas-venda`. O `body` é montado
  /// pela tela seguindo o `CreateSaleFormAuthDto` (userId/companyId vêm do JWT).
  Future<ApiResponse<SaleForm>> create(Map<String, dynamic> body) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.saleForms,
        body: body,
        timeout: kSaleFormSaveTimeout,
      );
      if (!res.success || res.data == null) {
        // `data` = corpo do erro (a tela marca os campos do 400).
        return ApiResponse.error(
          message: res.message ?? 'Erro ao criar ficha de venda',
          statusCode: res.statusCode,
          data: res.error,
        );
      }
      final root = res.data!;
      final data = root['data'] is Map
          ? Map<String, dynamic>.from(root['data'] as Map)
          : root;
      return ApiResponse.success(
        data: SaleForm.fromJson(data),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] create: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Atualiza uma ficha de venda. `PATCH /sistema/fichas-venda/:id`.
  Future<ApiResponse<SaleForm>> update(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(
        ApiConstants.saleFormById(id),
        body: body,
        timeout: kSaleFormSaveTimeout,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao salvar ficha de venda',
          statusCode: res.statusCode,
          data: res.error,
        );
      }
      final root = res.data!;
      final data = root['data'] is Map
          ? Map<String, dynamic>.from(root['data'] as Map)
          : root;
      return ApiResponse.success(
        data: SaleForm.fromJson(data),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] update: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Vincula usuários que podem ver a ficha. `POST /:id/usuarios` `{userIds}`.
  Future<ApiResponse<void>> addUsers(String id, List<String> userIds) async {
    try {
      final res = await _api.post(
        ApiConstants.saleFormUsuarios(id),
        body: {'userIds': userIds},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao vincular usuários',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] addUsers: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Cancela a ficha (status → canceled). `PATCH /:id/cancelar` `{reason}`.
  Future<ApiResponse<void>> cancelar(String id, String reason) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(
        ApiConstants.saleFormCancelar(id),
        body: {'reason': reason},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao cancelar ficha',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] cancelar: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Exclui (soft-delete) com motivo. `POST /:id/excluir` `{reason}`.
  Future<ApiResponse<void>> excluir(String id, String reason) async {
    try {
      final res = await _api.post(
        ApiConstants.saleFormExcluir(id),
        body: {'reason': reason},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao excluir ficha',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] excluir: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── PDF ──────────────────────────────────────────────────────────────────

  /// Baixa o PDF da ficha de venda como bytes.
  /// `modo`: 'completo' (padrão, sem query) | 'sistema' (só PDF do sistema,
  /// `incluirAutentique=false`) | 'assinaturas' (só documento assinado,
  /// `apenasAutentique=true`). O backend pode devolver ZIP.
  Future<ApiResponse<({Uint8List bytes, String contentType})>> downloadPdf(
    String id, {
    String modo = 'completo',
  }) async {
    try {
      final qp = <String, String>{};
      if (modo == 'sistema') {
        qp['incluirAutentique'] = 'false';
      } else if (modo == 'assinaturas') {
        qp['apenasAutentique'] = 'true';
      }
      final base = Uri.parse(
        '${ApiConstants.baseApiUrl}${ApiConstants.saleFormPdf(id)}',
      );
      final uri = qp.isEmpty ? base : base.replace(queryParameters: qp);

      final headers = await _api.buildOutboundHeaders(
        endpoint: ApiConstants.saleFormPdf(id),
        excludeContentType: true,
      );
      headers.remove('Content-Type');
      headers['Accept'] = 'application/pdf, application/zip';

      final res = await http
          .get(uri, headers: headers)
          .timeout(ApiConstants.receiveTimeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final ct =
            (res.headers['content-type'] ?? 'application/pdf').toLowerCase();
        return ApiResponse.success(
          data: (
            bytes: res.bodyBytes,
            contentType:
                ct.contains('zip') ? 'application/zip' : 'application/pdf',
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
      debugPrint('❌ [SALE_FORMS] downloadPdf: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── Assinaturas ───────────────────────────────────────────────────────────

  Future<ApiResponse<List<SaleFormSignature>>> listSignatures(
      String id) async {
    try {
      final res = await _api.get<dynamic>(
        ApiConstants.saleFormAssinaturas(id),
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
                SaleFormSignature.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] listSignatures: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Envia a ficha para assinatura. `signers` pode ser vazio — o backend
  /// injeta automaticamente os signatários obrigatórios. Ficha de venda NÃO
  /// possui etapas.
  Future<ApiResponse<List<SaleFormSignature>>> enviarParaAssinatura(
    String id, {
    List<SaleFormSignerInput> signers = const [],
    String? documentName,
    String? documentMessage,
  }) async {
    try {
      final document = <String, dynamic>{};
      if (documentName != null) document['name'] = documentName;
      if (documentMessage != null) document['message'] = documentMessage;
      final body = <String, dynamic>{
        'signers': signers.map((s) => s.toJson()).toList(),
        'document': document,
      };
      final res = await _postLong<dynamic>(
        ApiConstants.saleFormAssinaturas(id),
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
                SaleFormSignature.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] enviarParaAssinatura: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<List<SaleFormSignature>>> syncAssinaturas(
      String id) async {
    try {
      final res = await _postLong<dynamic>(
        ApiConstants.saleFormAssinaturasSync(id),
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
                SaleFormSignature.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] sync: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<String>> obterLinkAssinatura(
    String saleFormId,
    String signatureId,
  ) async {
    try {
      final res = await _postLong<Map<String, dynamic>>(
        ApiConstants.saleFormAssinaturaLink(saleFormId, signatureId),
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
      debugPrint('❌ [SALE_FORMS] link: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<SaleFormWhatsappEnvio>> getWhatsappEnvio(
      String id) async {
    try {
      final res = await _api.get<dynamic>(
        ApiConstants.saleFormAssinaturasWhatsappEnvio(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao obter envio por WhatsApp',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      return ApiResponse.success(
        data: SaleFormWhatsappEnvio.fromJson(map),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] whatsappEnvio: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> reenviarTodosWhatsapp(
      String id) async {
    try {
      final res = await _postLong<Map<String, dynamic>>(
        ApiConstants.saleFormReenviarWhatsappTodos(id),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao reenviar via WhatsApp',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: res.data!, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] reenviarWhatsapp all: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> reenviarUmWhatsapp(
    String id,
    String signatureId,
  ) async {
    try {
      final res = await _postLong<Map<String, dynamic>>(
        ApiConstants.saleFormReenviarWhatsappUm(id, signatureId),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao reenviar via WhatsApp',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: res.data!, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] reenviarWhatsapp one: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<void>> invalidarAssinaturas(String id) async {
    try {
      final res = await _postLong<dynamic>(
        ApiConstants.saleFormInvalidarAssinaturas(id),
        body: const <String, dynamic>{},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao invalidar assinaturas',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] invalidar: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Prévia dos signatários para envio manual (`source` sempre null).
  Future<ApiResponse<List<SaleFormSignerPreview>>> getEnvioSignersPreview(
      String id) async {
    return _getSignersPreview(
      ApiConstants.saleFormAssinaturaEnvioSignersPreview(id),
      tag: 'envioSignersPreview',
    );
  }

  /// Prévia dos signatários do fluxo automático (traz `source`).
  Future<ApiResponse<List<SaleFormSignerPreview>>> getAutomaticaSignersPreview(
      String id) async {
    return _getSignersPreview(
      ApiConstants.saleFormAssinaturaAutomaticaSignersPreview(id),
      tag: 'automaticaSignersPreview',
    );
  }

  Future<ApiResponse<List<SaleFormSignerPreview>>> _getSignersPreview(
    String endpoint, {
    required String tag,
  }) async {
    try {
      final res = await _api.get<dynamic>(endpoint);
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao obter signatários',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map ? (raw['data'] ?? raw['signers']) : null);
      if (list is! List) {
        return ApiResponse.success(data: const [], statusCode: res.statusCode);
      }
      return ApiResponse.success(
        data: list
            .whereType<Map>()
            .map((m) =>
                SaleFormSignerPreview.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] $tag: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── Assinaturas: e-mail, pendentes, trava ──────────────────────────────────

  /// Envia por e-mail o link de cada signatário pendente da ficha (provedor
  /// da plataforma, não o Autentique). O back ignora quem recebeu há < 5 min.
  Future<ApiResponse<SaleFormEmailEnvio>> reenviarTodosEmail(String id) async {
    return _envioEmail(
      ApiConstants.saleFormReenviarEmailTodos(id),
      tag: 'reenviarEmail all',
    );
  }

  /// Envia por e-mail o link de UM signatário.
  Future<ApiResponse<SaleFormEmailEnvio>> reenviarUmEmail(
    String id,
    String signatureId,
  ) async {
    return _envioEmail(
      ApiConstants.saleFormReenviarEmailUm(id, signatureId),
      tag: 'reenviarEmail one',
      timeout: const Duration(seconds: 60),
    );
  }

  Future<ApiResponse<SaleFormEmailEnvio>> _envioEmail(
    String endpoint, {
    required String tag,
    Duration timeout = _kLongTimeout,
  }) async {
    try {
      final res = await _postLong<Map<String, dynamic>>(
        endpoint,
        timeout: timeout,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao enviar por e-mail',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: SaleFormEmailEnvio.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] $tag: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Último envio dos links por e-mail. `data == null` = nunca enviado.
  Future<ApiResponse<SaleFormEmailEnvio?>> getUltimoEnvioEmail(
      String id) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.saleFormUltimoEnvioEmail(id),
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao obter o último envio por e-mail',
          statusCode: res.statusCode,
        );
      }
      final u = res.data?['ultimoEnvio'];
      return ApiResponse.success(
        data: u is Map
            ? SaleFormEmailEnvio.fromJson(Map<String, dynamic>.from(u))
            : null,
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] ultimoEnvioEmail: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Painel de assinaturas pendentes. `escopo`: 'minhas' (o que espera a
  /// MINHA assinatura) ou 'todas' (tudo que vejo na hierarquia).
  Future<ApiResponse<SaleFormPendingSignaturesResponse>>
      listarAssinaturasPendentes({required String escopo}) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.saleFormsAssinaturasPendentes,
        queryParameters: {'escopo': escopo == 'minhas' ? 'minhas' : 'todas'},
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar assinaturas pendentes',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: SaleFormPendingSignaturesResponse.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] pendentes: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Trava global por assinatura parada. ATENÇÃO: o back incrementa o
  /// contador de avisos a cada chamada (até `maxNotifications`) — chamar uma
  /// vez por entrada na tela, nunca em laço.
  Future<ApiResponse<SaleFormSignatureLockStatus>>
      getSignatureLockStatus() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.saleFormsAssinaturaLockStatus,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao verificar assinaturas pendentes',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: SaleFormSignatureLockStatus.fromJson(res.data!),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] lockStatus: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Recusa a assinatura pendente (motivo >= 10 caracteres). O back invalida
  /// TODAS as assinaturas ativas da ficha. Devolve a mensagem do back.
  Future<ApiResponse<String>> recusarSignatureLock(
    String saleFormId,
    String reason,
  ) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        ApiConstants.saleFormsAssinaturaLockRecusar,
        body: {'saleFormId': saleFormId, 'reason': reason},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Não foi possível registrar a recusa',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: res.data?['message']?.toString() ?? 'Recusa registrada.',
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] recusarLock: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Membros da empresa (busca por nome/e-mail) para signatários extras.
  Future<ApiResponse<List<SaleFormCompanyMember>>> buscarMembrosEmpresa({
    String? search,
  }) async {
    try {
      final q = search?.trim() ?? '';
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.saleFormCompanyMembers,
        queryParameters: {
          'page': '1',
          'limit': '100',
          if (q.isNotEmpty) 'search': q,
        },
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao buscar membros da empresa',
          statusCode: res.statusCode,
        );
      }
      final list = res.data!['data'];
      return ApiResponse.success(
        data: list is List
            ? list
                .whereType<Map>()
                .map((m) =>
                    SaleFormCompanyMember.fromJson(Map<String, dynamic>.from(m)))
                .where((m) => m.name.trim().isNotEmpty)
                .toList()
            : const [],
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] membros: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── Auditoria, distrato, equipe, responsável ─────────────────────────────

  /// Histórico de auditoria (`GET /:id/auditoria`). Cada entrada:
  /// `{id, createdAt, action, userId?, userName?, userEmail?,
  ///   changes: [{field, label?, before?, after?}], metadata?}`.
  Future<ApiResponse<List<Map<String, dynamic>>>> getAuditoria(
      String id) async {
    try {
      final res = await _api.get<dynamic>(ApiConstants.saleFormAuditoria(id));
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar o histórico',
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
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] auditoria: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Abre o DISTRATO de uma ficha finalizada (cancela e avisa o Financeiro).
  /// `PATCH /:id/distrato` `{reason}` — o web manda o motivo em `reason`.
  Future<ApiResponse<SaleForm>> abrirDistrato(String id, String reason) async {
    return _patchForm(
      ApiConstants.saleFormDistrato(id),
      {'reason': reason},
      tag: 'distrato',
      fallbackMessage: 'Erro ao abrir o distrato',
    );
  }

  /// Troca só a equipe da ficha. `PATCH /:id/equipe` `{teamId}`.
  Future<ApiResponse<SaleForm>> alterarEquipe(String id, String teamId) async {
    return _patchForm(
      ApiConstants.saleFormEquipe(id),
      {'teamId': teamId},
      tag: 'equipe',
      fallbackMessage: 'Erro ao trocar a equipe',
    );
  }

  /// Transfere o criador da ficha (só finalizada; exige ver todas).
  /// `POST /:id/transferir-responsabilidade` `{newUserId}`.
  Future<ApiResponse<SaleForm>> transferirResponsabilidade(
    String id,
    String newUserId,
  ) async {
    try {
      final res = await _postLong<Map<String, dynamic>>(
        ApiConstants.saleFormTransferirResponsabilidade(id),
        body: {'newUserId': newUserId},
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao transferir a responsabilidade',
          statusCode: res.statusCode,
        );
      }
      final root = res.data!;
      final data = root['data'] is Map
          ? Map<String, dynamic>.from(root['data'] as Map)
          : root;
      return ApiResponse.success(
        data: SaleForm.fromJson(data),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] transferir: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<SaleForm>> _patchForm(
    String endpoint,
    Map<String, dynamic> body, {
    required String tag,
    required String fallbackMessage,
  }) async {
    try {
      final res = await _api.patch<Map<String, dynamic>>(endpoint, body: body);
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? fallbackMessage,
          statusCode: res.statusCode,
        );
      }
      final root = res.data!;
      final data = root['data'] is Map
          ? Map<String, dynamic>.from(root['data'] as Map)
          : root;
      return ApiResponse.success(
        data: SaleForm.fromJson(data),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] $tag: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── POST com teto longo ──────────────────────────────────────────────────

  /// O `ApiService` corta toda requisição em 30 s; gerar o documento no
  /// Autentique, sincronizar e reenviar links passa disso (o web usa 120 s,
  /// `SALE_FORMS_LONG_REQUEST_TIMEOUT_MS`). Aqui a chamada sai direto pelo
  /// `http` com os MESMOS headers do interceptor; num 401 (token vencido)
  /// delega ao `ApiService`, que renova o token e repete — o 401 garante que
  /// o servidor não executou a primeira tentativa.
  Future<ApiResponse<T>> _postLong<T>(
    String endpoint, {
    Object? body,
    Duration timeout = _kLongTimeout,
  }) async {
    try {
      final headers = await _api.buildOutboundHeaders(endpoint: endpoint);
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final res = await http
          .post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      if (res.statusCode == 401) {
        return await _api.post<T>(endpoint, body: body);
      }
      dynamic decoded;
      if (res.bodyBytes.isNotEmpty) {
        try {
          decoded = jsonDecode(utf8.decode(res.bodyBytes));
        } catch (_) {
          decoded = null;
        }
      }
      if (decoded is Map && decoded is! Map<String, dynamic>) {
        decoded = Map<String, dynamic>.from(decoded);
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse.success(
          data: decoded is T ? decoded : null,
          statusCode: res.statusCode,
        );
      }
      String message = 'Erro na requisição (${res.statusCode})';
      if (decoded is Map && decoded['message'] != null) {
        final m = decoded['message'];
        message = m is List ? m.join('\n') : m.toString();
      }
      return ApiResponse.error(
        message: message,
        statusCode: res.statusCode,
        data: decoded,
      );
    } on TimeoutException {
      return ApiResponse.error(
        message: 'O servidor demorou para responder. Atualize a lista: a '
            'operação pode ter sido concluída.',
        statusCode: 0,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] postLong $endpoint: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  // ─── Anexos ─────────────────────────────────────────────────────────────────

  Future<ApiResponse<List<SaleFormAttachment>>> listAnexos(String id) async {
    try {
      final res = await _api.get<dynamic>(
        ApiConstants.saleFormAnexos(id),
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
                SaleFormAttachment.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] anexos: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Upload de anexo (multipart). Valida tipo (pdf/jpeg/jpg/png/webp) e
  /// tamanho (<= 15MB) no cliente antes de enviar.
  Future<ApiResponse<SaleFormAttachment>> uploadAnexo(
    String id,
    File file, {
    String? descricao,
    String? uploadedByName,
  }) async {
    try {
      final validationError = _validateAnexo(file);
      if (validationError != null) {
        return ApiResponse.error(message: validationError, statusCode: 400);
      }

      final endpoint = ApiConstants.saleFormAnexos(id);
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final request = http.MultipartRequest('POST', uri);

      final headers = await _api.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      request.headers.addAll(headers);

      final fileLength = await file.length();
      final fileName = file.path.split('/').last.split('\\').last;
      request.files.add(http.MultipartFile(
        'file',
        http.ByteStream(file.openRead()),
        fileLength,
        filename: fileName,
        // Sem isso vai `application/octet-stream` e o back recusa.
        contentType: fichaAnexoContentType(fileName),
      ));

      if (descricao != null && descricao.trim().isNotEmpty) {
        request.fields['descricao'] = descricao.trim();
      }
      if (uploadedByName != null && uploadedByName.trim().isNotEmpty) {
        request.fields['uploadedByName'] = uploadedByName.trim();
      }

      final streamed =
          await request.send().timeout(ApiConstants.receiveTimeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final map = decoded is Map && decoded['data'] is Map
            ? Map<String, dynamic>.from(decoded['data'])
            : (decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : <String, dynamic>{});
        return ApiResponse.success(
          data: SaleFormAttachment.fromJson(map),
          statusCode: response.statusCode,
        );
      }
      String message;
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        message = (body is Map && body['message'] != null)
            ? body['message'].toString()
            : 'Erro ao enviar anexo (${response.statusCode})';
      } catch (_) {
        message = 'Erro ao enviar anexo (${response.statusCode})';
      }
      return ApiResponse.error(message: message, statusCode: response.statusCode);
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] uploadAnexo: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<SaleFormAttachment>> aprovarAnexo(
    String id,
    String anexoId,
  ) async {
    try {
      final res = await _api.patch<dynamic>(
        ApiConstants.saleFormAnexoAprovar(id, anexoId),
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao aprovar anexo',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final map = raw is Map && raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'])
          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
      return ApiResponse.success(
        data: SaleFormAttachment.fromJson(map),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] aprovarAnexo: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<SaleFormAttachment>> rejeitarAnexo(
    String id,
    String anexoId, {
    String? reason,
  }) async {
    try {
      final res = await _api.patch<dynamic>(
        ApiConstants.saleFormAnexoRejeitar(id, anexoId),
        body: {if (reason != null) 'reason': reason},
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao rejeitar anexo',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final map = raw is Map && raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'])
          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
      return ApiResponse.success(
        data: SaleFormAttachment.fromJson(map),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [SALE_FORMS] rejeitarAnexo: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}

/// Valida um anexo no cliente. Retorna a mensagem de erro (pt-BR) ou `null`
/// se estiver tudo certo. Compartilhado por fichas de venda e proposta.
const int kAnexoMaxBytes = 15 * 1024 * 1024; // 15MB
const List<String> kAnexoAllowedExtensions = [
  'pdf',
  'jpeg',
  'jpg',
  'png',
  'webp',
];

String? _validateAnexo(File file) {
  final name = file.path.split('/').last.split('\\').last;
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  if (!kAnexoAllowedExtensions.contains(ext)) {
    return 'Tipo de arquivo não permitido. Use PDF, JPEG, JPG, PNG ou WEBP.';
  }
  try {
    if (file.lengthSync() > kAnexoMaxBytes) {
      return 'Arquivo muito grande. Tamanho máximo: 15MB.';
    }
  } catch (_) {
    // Se não conseguir medir o tamanho aqui, o backend valida.
  }
  return null;
}

// ─── Helpers de parse ──────────────────────────────────────────────────────

String _str(dynamic v) => v?.toString() ?? '';

String? _strNull(dynamic v) {
  final s = v?.toString();
  if (s == null || s.trim().isEmpty) return null;
  return s;
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

bool _bool(dynamic v, {bool defaultValue = false}) {
  if (v == null) return defaultValue;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1';
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

Map<String, dynamic>? _map(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}


/// Travas de comissão da ficha de venda, por empresa
/// (`companies.sale_form_commission_rules`). Espelho de
/// `imobx-front/src/utils/saleFormCommissionRules.ts`.
class SaleFormCommissionRules {
  const SaleFormCommissionRules({
    this.gerenciaTotalMax = 5,
    this.corretoresTotalMax = 60,
    this.diretorPercent,
    this.gestorSdrMax = 2,
  });

  /// Soma máxima dos gestores/gerentes (gerências sem papel).
  final double? gerenciaTotalMax;

  /// Soma máxima de corretores + captadores.
  final double? corretoresTotalMax;

  /// Percentual FIXO do diretor; `null` = a empresa não usa diretor.
  final double? diretorPercent;

  /// Soma máxima dos gestores SDR (grupo próprio, fora da gerência).
  final double? gestorSdrMax;

  static const SaleFormCommissionRules padrao = SaleFormCommissionRules();

  bool get usaDiretor => diretorPercent != null;
  bool get usaGestorSdr => gestorSdrMax != null;

  static double? _pct(dynamic v, double? fallback) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null || n.isNaN || n < 0) return fallback;
    return n;
  }

  factory SaleFormCommissionRules.fromJson(Map<String, dynamic> j) {
    const d = SaleFormCommissionRules();
    return SaleFormCommissionRules(
      gerenciaTotalMax: j.containsKey('gerenciaTotalMax')
          ? _pct(j['gerenciaTotalMax'], d.gerenciaTotalMax)
          : d.gerenciaTotalMax,
      corretoresTotalMax: j.containsKey('corretoresTotalMax')
          ? _pct(j['corretoresTotalMax'], d.corretoresTotalMax)
          : d.corretoresTotalMax,
      diretorPercent: _pct(j['diretorPercent'], null),
      gestorSdrMax: j.containsKey('gestorSdrMax')
          ? _pct(j['gestorSdrMax'], d.gestorSdrMax)
          : d.gestorSdrMax,
    );
  }
}
