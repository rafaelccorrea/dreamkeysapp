import '../../../shared/services/api_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import 'finance_api_client.dart';

/// `GET /auth/me` do Financeiro (`types/financeiro.ts:4827`).
class FinanceMe {
  final bool linked;
  final String? userId;
  final String? name;
  final String email;
  final String role;
  final List<String> permissoes;
  final List<String> concedidas;
  final List<String> revogadas;
  final List<String> permissoesDoCargo;
  final bool podeVerSino;

  /// Fallback de back antigo para o sino (`receiveNotifications`).
  final bool receiveNotifications;

  /// O back mandou `permissoes`? Sem a lista, `temPermissao` fica
  /// indefinido (`utils/financePermissoes.ts:10`).
  final bool hasPermissoesList;

  /// `no_access` | `not_provisioned` — a empresa do header não serve.
  final String? companyDenial;

  const FinanceMe({
    required this.linked,
    required this.role,
    this.userId,
    this.name,
    this.email = '',
    this.permissoes = const [],
    this.concedidas = const [],
    this.revogadas = const [],
    this.permissoesDoCargo = const [],
    this.podeVerSino = false,
    this.receiveNotifications = false,
    this.hasPermissoesList = false,
    this.companyDenial,
  });

  static List<String> _list(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory FinanceMe.fromJson(Map<String, dynamic> json) {
    final denial = json['companyDenial']?.toString();
    return FinanceMe(
      linked: json['linked'] == true,
      userId: json['userId']?.toString(),
      name: json['name']?.toString(),
      email: json['email']?.toString() ?? '',
      role: (json['role']?.toString() ?? '').trim().toUpperCase(),
      permissoes: _list(json['permissoes']),
      concedidas: _list(json['concedidas']),
      revogadas: _list(json['revogadas']),
      permissoesDoCargo: _list(json['permissoesDoCargo']),
      podeVerSino: json['podeVerSino'] == true,
      receiveNotifications: json['receiveNotifications'] == true,
      hasPermissoesList: json['permissoes'] is List,
      companyDenial: (denial == null || denial.isEmpty) ? null : denial,
    );
  }
}

/// `/auth/me` com cache por empresa (a identidade no Financeiro muda com a
/// empresa do header). Um 404 (back antigo) = "sem gating" → `null`.
class FinanceMeService {
  FinanceMeService._();

  static final FinanceMeService instance = FinanceMeService._();

  String? _companyId;
  FinanceMe? _me;
  DateTime? _at;
  Future<ApiResponse<FinanceMe?>>? _inFlight;

  static const Duration _ttl = Duration(seconds: 60);

  /// Último `/auth/me` carregado (cadastro, não valor) — leitura síncrona
  /// para menus. `null` = ainda não carregou.
  FinanceMe? get cached => _me;

  void clear() {
    _companyId = null;
    _me = null;
    _at = null;
  }

  Future<ApiResponse<FinanceMe?>> load({bool force = false}) async {
    final companyId = await SecureStorageService.instance.getCompanyId();
    final fresh = _at != null && DateTime.now().difference(_at!) < _ttl;
    if (!force && fresh && _companyId == companyId && _me != null) {
      return ApiResponse.success(data: _me, statusCode: 200);
    }
    return _inFlight ??= _fetch(companyId).whenComplete(() => _inFlight = null);
  }

  Future<ApiResponse<FinanceMe?>> _fetch(String? companyId) async {
    final res = await FinanceApiClient.instance.get<Map<String, dynamic>>(
      '/auth/me',
    );
    if (res.success && res.data != null) {
      _me = FinanceMe.fromJson(res.data!);
      _companyId = companyId;
      _at = DateTime.now();
      return ApiResponse.success(data: _me, statusCode: res.statusCode);
    }
    if (res.statusCode == 404) {
      return ApiResponse.success(data: null, statusCode: 404);
    }
    return ApiResponse.error(
      message: res.message ?? 'Erro no Financeiro.',
      statusCode: res.statusCode,
      data: res.financeError,
    );
  }
}
