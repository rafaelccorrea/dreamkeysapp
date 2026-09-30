import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import 'api_service.dart';

// ════════════════════════════════════════════════════════════════════════
// Preferências do usuário — paridade com o imobx-front
//
//   - `userPreferencesService.ts`  → GET/PUT /user-preferences e o catálogo
//     GET /user-preferences/notification-categories;
//   - `regrasDasPreferencias.ts`   → leitura (estadoDe) e payload (payloadDe);
//   - `NotificationPreferencesPage.tsx` → escolhas por assunto
//     (`notificationSettings.categories`) e os avisos do Financeiro
//     (`financeiroApi.get/setNotificationPreference`, microserviço).
//
// O back (`UserPreferencesService.updatePreferences`) FUNDE cada bloco
// (themeSettings, notificationSettings — inclusive `channels`, `events` e
// `categories` por categoria —, layoutSettings, generalSettings), então o app
// manda só o bloco que mudou e recebe o objeto inteiro de volta.
//
// Antes o app gravava em GET/PUT /settings (rota que não existe no back) e
// tratava o 404 como sucesso: nada era salvo e a pessoa achava que tinha
// salvado. Aqui não há fallback — erro do back é erro na tela.
// ════════════════════════════════════════════════════════════════════════

const String _kPreferencesPath = '/user-preferences';
const String _kCategoriesPath = '/user-preferences/notification-categories';

/// Rota do microserviço financeiro (fora do PIN — `ROTAS_SEM_PIN`).
const String _kFinancePreferencesPath = '/notifications/preferences';

/// Base do microserviço financeiro (mesmo valor do `VITE_FINANCEIRO_API_URL`
/// de produção do imobx-front). Pode ser trocada por
/// `--dart-define=FINANCE_API_BASE_URL=...`.
const String _kFinanceBaseUrl = String.fromEnvironment(
  'FINANCE_API_BASE_URL',
  defaultValue: 'https://api.financeiro.intellisysbr.com/api/v1',
);

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

bool? _asBool(dynamic v) => v is bool ? v : null;

/// Um dos dois avisos de lead que o web grava em `notificationSettings.events`
/// (`lead_transfer_received`, `lead_whatsapp_received`).
class LeadEventPreference {
  final bool enabled;
  final bool email;
  final bool inApp;
  final bool whatsapp;

  const LeadEventPreference({
    required this.enabled,
    required this.email,
    required this.inApp,
    required this.whatsapp,
  });

  LeadEventPreference copyWith({
    bool? enabled,
    bool? email,
    bool? inApp,
    bool? whatsapp,
  }) {
    return LeadEventPreference(
      enabled: enabled ?? this.enabled,
      email: email ?? this.email,
      inApp: inApp ?? this.inApp,
      whatsapp: whatsapp ?? this.whatsapp,
    );
  }

  /// Mesmo formato do `canaisDe` do web: desligado zera os canais.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'channels': {
      'email': enabled ? email : false,
      'inApp': enabled ? inApp : false,
      'whatsapp': enabled ? whatsapp : false,
    },
  };
}

/// Escolha de uma categoria de notificação (chave ausente = ligado).
class NotificationCategoryChoice {
  final bool enabled;
  final bool inApp;
  final bool email;
  final bool push;

  const NotificationCategoryChoice({
    this.enabled = true,
    this.inApp = true,
    this.email = true,
    this.push = true,
  });

  /// `lerEscolha` do web: só `false` explícito desliga.
  factory NotificationCategoryChoice.fromJson(dynamic json) {
    final m = _asMap(json);
    return NotificationCategoryChoice(
      enabled: m['enabled'] != false,
      inApp: m['inApp'] != false,
      email: m['email'] != false,
      push: m['push'] != false,
    );
  }

  NotificationCategoryChoice copyWith({
    bool? enabled,
    bool? inApp,
    bool? email,
    bool? push,
  }) {
    return NotificationCategoryChoice(
      enabled: enabled ?? this.enabled,
      inApp: inApp ?? this.inApp,
      email: email ?? this.email,
      push: push ?? this.push,
    );
  }

  bool valueOf(String channel) => switch (channel) {
    'inApp' => inApp,
    'email' => email,
    'push' => push,
    _ => enabled,
  };

  NotificationCategoryChoice withChannel(String channel, bool value) =>
      switch (channel) {
        'inApp' => copyWith(inApp: value),
        'email' => copyWith(email: value),
        'push' => copyWith(push: value),
        _ => copyWith(enabled: value),
      };

  /// `paraPayload` do web: só grava `false`; toda ligada vira `null`
  /// (o back apaga a categoria e ela volta ao padrão "tudo ligado").
  Map<String, dynamic>? toPayload() {
    final out = <String, dynamic>{};
    if (!enabled) out['enabled'] = false;
    if (!inApp) out['inApp'] = false;
    if (!email) out['email'] = false;
    if (!push) out['push'] = false;
    return out.isEmpty ? null : out;
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationCategoryChoice &&
      other.enabled == enabled &&
      other.inApp == inApp &&
      other.email == email &&
      other.push == push;

  @override
  int get hashCode => Object.hash(enabled, inApp, email, push);
}

/// Item do catálogo `GET /user-preferences/notification-categories`.
class NotificationCategoryMeta {
  final String key;
  final String label;
  final String descricao;
  final bool silenciavel;

  const NotificationCategoryMeta({
    required this.key,
    required this.label,
    required this.descricao,
    required this.silenciavel,
  });

  factory NotificationCategoryMeta.fromJson(Map<String, dynamic> json) {
    return NotificationCategoryMeta(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      descricao: json['descricao']?.toString() ?? '',
      silenciavel: json['silenciavel'] != false,
    );
  }
}

/// Evento do catálogo de avisos do Financeiro (microserviço).
class FinanceNotificationEvent {
  final String event;
  final String label;
  final String quando;

  const FinanceNotificationEvent({
    required this.event,
    required this.label,
    required this.quando,
  });

  factory FinanceNotificationEvent.fromJson(Map<String, dynamic> json) {
    return FinanceNotificationEvent(
      event: json['event']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      quando: json['quando']?.toString() ?? '',
    );
  }
}

/// `GET /notifications/preferences` do financeiro: catálogo + o que EU desliguei.
class FinanceNotificationPreferences {
  final List<FinanceNotificationEvent> catalogo;
  final Set<String> desligados;

  const FinanceNotificationPreferences({
    required this.catalogo,
    required this.desligados,
  });
}

/// Preferências do usuário como o back devolve (`user_preferences`).
class UserPreferences {
  final Map<String, dynamic> themeSettings;
  final Map<String, dynamic> notificationSettings;
  final Map<String, dynamic> layoutSettings;
  final Map<String, dynamic> generalSettings;
  final String? updatedAt;

  const UserPreferences({
    required this.themeSettings,
    required this.notificationSettings,
    required this.layoutSettings,
    required this.generalSettings,
    this.updatedAt,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      themeSettings: _asMap(json['themeSettings']),
      notificationSettings: _asMap(json['notificationSettings']),
      layoutSettings: _asMap(json['layoutSettings']),
      generalSettings: _asMap(json['generalSettings']),
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  // ── tema (estadoDe: 'dark' ou 'light') ──────────────────────────────────
  String get theme => themeSettings['theme'] == 'dark' ? 'dark' : 'light';
  String get language {
    final l = themeSettings['language']?.toString().trim() ?? '';
    return l.isEmpty ? 'pt-BR' : l;
  }

  // ── canais (estadoDe: ausente = ligado) ─────────────────────────────────
  bool get emailChannel => _asBool(notificationSettings['email']) ?? true;
  bool get pushChannel => _asBool(notificationSettings['push']) ?? true;
  bool get inAppChannel => _asBool(notificationSettings['inApp']) ?? true;
  bool get whatsappChannel => _asBool(notificationSettings['whatsapp']) ?? true;

  // ── avisos na tela ──────────────────────────────────────────────────────
  bool get sound => _asBool(notificationSettings['sound']) ?? true;
  bool get leadEventToasts => notificationSettings['leadEventToasts'] == true;
  bool get celebrations => notificationSettings['celebrations'] != false;

  // ── os dois avisos de lead ──────────────────────────────────────────────
  LeadEventPreference leadEvent(String key) {
    final e = _asMap(_asMap(notificationSettings['events'])[key]);
    final ch = _asMap(e['channels']);
    return LeadEventPreference(
      enabled: _asBool(e['enabled']) ?? true,
      email: _asBool(ch['email']) ?? emailChannel,
      inApp: _asBool(ch['inApp']) ?? inAppChannel,
      whatsapp: _asBool(ch['whatsapp']) ?? whatsappChannel,
    );
  }

  // ── por assunto ─────────────────────────────────────────────────────────
  NotificationCategoryChoice category(String key) =>
      NotificationCategoryChoice.fromJson(
        _asMap(notificationSettings['categories'])[key],
      );

  // ── agenda ──────────────────────────────────────────────────────────────
  bool get calendarAllowOverlappingSlots =>
      generalSettings['calendarAllowOverlappingSlots'] == true;
}

/// Serviço de Preferências (`/user-preferences`) e dos avisos do Financeiro.
class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();
  final ApiService _apiService = ApiService.instance;

  /// Chaves dos dois eventos de lead gravados em `notificationSettings.events`.
  static const String leadTransferEvent = 'lead_transfer_received';
  static const String leadWhatsappEvent = 'lead_whatsapp_received';

  ApiResponse<UserPreferences> _parsePreferences(
    ApiResponse<Map<String, dynamic>> response,
    String fallbackMessage,
  ) {
    if (response.success && response.data != null) {
      try {
        return ApiResponse.success(
          data: UserPreferences.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      } catch (e) {
        debugPrint('[PREFERENCES] Erro ao ler resposta: $e');
        return ApiResponse.error(
          message: 'Resposta inesperada do servidor ao ler as preferências.',
          statusCode: response.statusCode,
        );
      }
    }
    return ApiResponse.error(
      message: response.message ?? fallbackMessage,
      statusCode: response.statusCode,
      data: response.error,
    );
  }

  /// GET /user-preferences — o back cria o registro com os padrões na 1ª vez.
  Future<ApiResponse<UserPreferences>> getPreferences() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        _kPreferencesPath,
      );
      return _parsePreferences(
        response,
        'Não deu para carregar as preferências.',
      );
    } catch (e) {
      debugPrint('[PREFERENCES] Erro de conexão (GET): $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// PUT /user-preferences — manda só os blocos que mudaram (o back funde).
  Future<ApiResponse<UserPreferences>> updatePreferences(
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        _kPreferencesPath,
        body: body,
      );
      return _parsePreferences(
        response,
        'Não deu para salvar as preferências.',
      );
    } catch (e) {
      debugPrint('[PREFERENCES] Erro de conexão (PUT): $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `updateThemeSettings` do web — `{ theme, language }`.
  Future<ApiResponse<UserPreferences>> updateThemeSettings({
    required String theme,
    required String language,
  }) {
    return updatePreferences({
      'themeSettings': {'theme': theme, 'language': language},
    });
  }

  /// `updateNotificationSettings` do web (parcial; o back funde).
  Future<ApiResponse<UserPreferences>> updateNotificationSettings(
    Map<String, dynamic> notificationSettings,
  ) {
    return updatePreferences({'notificationSettings': notificationSettings});
  }

  /// `generalSettings` (ex.: `calendarAllowOverlappingSlots`).
  Future<ApiResponse<UserPreferences>> updateGeneralSettings(
    Map<String, dynamic> generalSettings,
  ) {
    return updatePreferences({'generalSettings': generalSettings});
  }

  /// Payload dos quatro canais — o mesmo do `payloadDe` do web
  /// (plano + `channels`, que o back usa para email/inApp/whatsapp).
  static Map<String, dynamic> channelsPayload({
    required bool email,
    required bool push,
    required bool inApp,
    required bool whatsapp,
  }) {
    return {
      'email': email,
      'push': push,
      'inApp': inApp,
      'whatsapp': whatsapp,
      'channels': {'email': email, 'inApp': inApp, 'whatsapp': whatsapp},
    };
  }

  /// GET /user-preferences/notification-categories → `{ categorias: [...] }`.
  Future<ApiResponse<List<NotificationCategoryMeta>>>
  getNotificationCategories() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        _kCategoriesPath,
      );
      if (response.success && response.data != null) {
        final raw = response.data!['categorias'];
        final list = raw is List
            ? raw
                  .whereType<Map>()
                  .map((m) => NotificationCategoryMeta.fromJson(_asMap(m)))
                  .where((c) => c.key.isNotEmpty)
                  .toList()
            : <NotificationCategoryMeta>[];
        return ApiResponse.success(
          data: list,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message:
            response.message ?? 'Não deu para carregar a lista de assuntos.',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Grava as escolhas por assunto — `notificationSettings.categories`
  /// com o `paraPayload` do web (só `false`; categoria toda ligada = `null`).
  Future<ApiResponse<UserPreferences>> updateCategoryChoices(
    Map<String, NotificationCategoryChoice> choices,
  ) {
    final categories = <String, dynamic>{
      for (final e in choices.entries) e.key: e.value.toPayload(),
    };
    return updateNotificationSettings({'categories': categories});
  }

  // ── Financeiro (microserviço) ───────────────────────────────────────────

  String _extractMessage(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final m = decoded['message'];
        if (m is String && m.trim().isNotEmpty) return m;
        if (m is List && m.isNotEmpty) return m.first.toString();
      }
    } catch (_) {}
    return fallback;
  }

  /// GET /notifications/preferences do financeiro — mesmos cabeçalhos do web
  /// (Bearer do CRM + X-Company-ID). Rota fora do PIN.
  Future<ApiResponse<FinanceNotificationPreferences>>
  getFinanceNotificationPreferences() async {
    try {
      final headers = await _apiService.buildOutboundHeaders(
        endpoint: _kFinancePreferencesPath,
      );
      final res = await http
          .get(
            Uri.parse('$_kFinanceBaseUrl$_kFinancePreferencesPath'),
            headers: headers,
          )
          .timeout(ApiConstants.connectTimeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final m = _asMap(jsonDecode(res.body));
        final cat = m['catalogo'];
        final off = m['desligados'];
        return ApiResponse.success(
          data: FinanceNotificationPreferences(
            catalogo: cat is List
                ? cat
                      .whereType<Map>()
                      .map((e) => FinanceNotificationEvent.fromJson(_asMap(e)))
                      .where((e) => e.event.isNotEmpty)
                      .toList()
                : const [],
            desligados: off is List
                ? off.map((e) => e.toString()).toSet()
                : <String>{},
          ),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: _extractMessage(
          res.body,
          'Não foi possível carregar os avisos do Financeiro.',
        ),
        statusCode: res.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Não foi possível carregar os avisos do Financeiro.',
        statusCode: 0,
      );
    }
  }

  /// PUT /notifications/preferences do financeiro — `{ event, enabled }`,
  /// um PUT por evento (contrato do microserviço).
  Future<ApiResponse<void>> setFinanceNotificationPreference(
    String event,
    bool enabled,
  ) async {
    try {
      final headers = await _apiService.buildOutboundHeaders(
        endpoint: _kFinancePreferencesPath,
      );
      final res = await http
          .put(
            Uri.parse('$_kFinanceBaseUrl$_kFinancePreferencesPath'),
            headers: headers,
            body: jsonEncode({'event': event, 'enabled': enabled}),
          )
          .timeout(ApiConstants.connectTimeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse.success(statusCode: res.statusCode);
      }
      return ApiResponse.error(
        message: _extractMessage(
          res.body,
          'Não deu para salvar o aviso do Financeiro.',
        ),
        statusCode: res.statusCode,
      );
    } catch (e) {
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}
