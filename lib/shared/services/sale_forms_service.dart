import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
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
        return 'Em assinatura';
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
        return 'Em assinatura';
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

class SaleFormFilters {
  final String? search;
  final SaleFormStatus? status;
  final String? saleUnit;
  final bool? listDeletedOnly;
  final int page;
  final int limit;
  final String sortBy;
  final String sortOrder;

  const SaleFormFilters({
    this.search,
    this.status,
    this.saleUnit,
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
    if (status != null) qp['status'] = status!.apiValue;
    if (saleUnit != null && saleUnit!.trim().isNotEmpty) {
      qp['saleUnit'] = saleUnit!.trim();
    }
    if (listDeletedOnly == true) qp['listDeletedOnly'] = 'true';
    return qp;
  }

  SaleFormFilters copyWith({
    Object? search = _kKeep,
    Object? status = _kKeep,
    Object? saleUnit = _kKeep,
    Object? listDeletedOnly = _kKeep,
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
        saleUnit:
            identical(saleUnit, _kKeep) ? this.saleUnit : saleUnit as String?,
        listDeletedOnly: identical(listDeletedOnly, _kKeep)
            ? this.listDeletedOnly
            : listDeletedOnly as bool?,
        page: page ?? this.page,
        limit: limit ?? this.limit,
        sortBy: sortBy ?? this.sortBy,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// Service de Fichas de Venda — espelha `saleFormsApi.ts` (web) e o
/// `SaleFormsController` do backend. Fase 1: leitura + cancelar/excluir.
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
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao criar ficha de venda',
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
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao salvar ficha de venda',
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
