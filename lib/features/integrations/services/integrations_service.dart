import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/integration_model.dart';

/// Serviço da Central de Integrações — consome os MESMOS endpoints que o hub
/// `IntegrationsPage.tsx` do imobx-front usa para descobrir o status de cada
/// integração, além das ações leves que o backend expõe (ativar/desativar
/// via PATCH/PUT com `isActive` e testar conexão via POST test-connection).
///
/// Regras de "Conectado" espelhadas 1:1 do hub web:
///   whatsapp        → config.isActive OU unofficial.isActive
///   meta-campaign   → config.isActive
///   google-ads      → status.isActive && hasOAuthToken && hasAppCredentials
///   ga4             → status.isActive && hasOAuthToken
///   grupo-zap       → isActive || feedToken || webhookToken
///   properties-api  → config.enabled
///   chaves-na-mao   → isActive || feedToken || webhookToken
///   imovelweb       → isActive && hasCredentials
///   autentique      → status.active
///   custom-leads    → webhookUrl || webhookTokenMasked
///   ficha-webhooks  → webhookUrl
///   chat-pro        → (mesma condição do custom-leads)
///   system-campaigns→ sempre disponível (painel próprio)
class IntegrationsService {
  IntegrationsService._();

  static final IntegrationsService instance = IntegrationsService._();
  final ApiService _api = ApiService.instance;

  // ─── Endpoints (paridade com os services do imobx-front) ─────────────────
  static const String _whatsappConfig = '/whatsapp/config';
  static const String _whatsappUnofficialConfig = '/whatsapp/unofficial/config';
  static const String _metaCampaignConfig = '/integrations/meta-campaign/config';
  static const String _googleAdsStatus = '/integrations/google-ads/status';
  static const String _googleAdsTestConnection =
      '/integrations/google-ads/test-connection';
  static const String _ga4Status = '/integrations/ga4/status';
  static const String _ga4TestConnection = '/integrations/ga4/test-connection';
  static const String _grupoZapConfig = '/integrations/grupo-zap/config';
  static const String _propertiesApiConfig =
      '/integrations/properties-api/config';
  static const String _chavesNaMaoConfig =
      '/integrations/chaves-na-mao/config';
  static const String _imovelwebConfig = '/integrations/imovelweb/config';
  static const String _imovelwebTestConnection =
      '/integrations/imovelweb/test-connection';
  static const String _autentiqueStatus = '/integrations/autentique/status';
  static const String _autentiqueCompanyConfig =
      '/integrations/autentique/company-config';
  static const String _customLeadsConfig =
      '/integrations/custom-leads/config';
  static const String _fichaWebhooksConfig =
      '/integrations/ficha-webhooks/config';

  // ─── Status ───────────────────────────────────────────────────────────────

  /// Carrega o status de TODAS as integrações pedidas, em paralelo.
  /// Falha de uma não derruba as outras (cada chave resolve sozinha).
  Future<Map<String, IntegrationStatusData>> fetchStatuses(
    List<String> keys,
  ) async {
    final results = await Future.wait(keys.map(fetchStatus));
    final map = <String, IntegrationStatusData>{};
    for (var i = 0; i < keys.length; i++) {
      final res = results[i];
      map[keys[i]] = res.success && res.data != null
          ? res.data!
          // Paridade com o hub web: erro de fetch = "não configurada".
          : IntegrationStatusData(key: keys[i], configured: false);
    }
    return map;
  }

  /// Status de UMA integração (mesma regra do hub web por chave).
  Future<ApiResponse<IntegrationStatusData>> fetchStatus(String key) async {
    try {
      switch (key) {
        case 'whatsapp':
          return await _fetchWhatsapp();
        case 'whatsapp-lead-claim':
          return await _fetchWhatsappLeadClaim();
        case 'meta-campaign':
          return await _fetchMetaCampaign();
        case 'system-campaigns':
          return ApiResponse.success(
            data: const IntegrationStatusData(
              key: 'system-campaigns',
              configured: true,
              active: true,
              statusLine: 'Painel de campanhas próprias sempre disponível.',
            ),
            statusCode: 200,
          );
        case 'google-ads':
          return await _fetchGoogleAds();
        case 'ga4':
          return await _fetchGa4();
        case 'grupo-zap':
          return await _fetchPortalConfig(key, _grupoZapConfig);
        case 'chaves-na-mao':
          return await _fetchPortalConfig(key, _chavesNaMaoConfig);
        case 'properties-api':
          return await _fetchPropertiesApi();
        case 'imovelweb':
          return await _fetchImovelweb();
        case 'autentique':
          return await _fetchAutentique();
        case 'custom-leads':
        case 'chat-pro':
          return await _fetchCustomLeads(key);
        case 'ficha-webhooks':
          return await _fetchFichaWebhooks();
        default:
          return ApiResponse.error(
            message: 'Integração desconhecida: $key',
            statusCode: 404,
          );
      }
    } catch (e) {
      debugPrint('❌ [INTEGRATIONS] fetchStatus($key): $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchWhatsapp() async {
    final results = await Future.wait([
      _api.get<Map<String, dynamic>>(_whatsappConfig),
      _api.get<Map<String, dynamic>>(_whatsappUnofficialConfig),
    ]);
    final official = _unwrap(results[0]);
    final unofficial = _unwrap(results[1]);

    // 404/403 no oficial não é erro fatal (mesma tolerância do web) — mas se
    // AMBAS as chamadas falharam por rede, propaga o erro para o retry.
    if (!results[0].success &&
        !results[1].success &&
        results[0].statusCode == 0) {
      return ApiResponse.error(
        message: results[0].message ?? 'Erro ao carregar o WhatsApp',
        statusCode: results[0].statusCode,
      );
    }

    final officialActive = asBool(official['isActive']);
    final unofficialActive = asBool(unofficial['isActive']);
    final configured = officialActive || unofficialActive;
    final statusLine = officialActive
        ? 'API Oficial ativa para a empresa.'
        : unofficialActive
            ? 'Conexão QR Code ativa para a empresa.'
            : 'Nenhuma conexão de WhatsApp ativa no momento.';

    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'whatsapp',
        configured: configured,
        active: configured,
        statusLine: statusLine,
        raw: official,
        extraRaw: unofficial,
      ),
      statusCode: 200,
    );
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchWhatsappLeadClaim() async {
    final res = await _api.get<Map<String, dynamic>>(_whatsappUnofficialConfig);
    if (!res.success && res.statusCode == 0) {
      return ApiResponse.error(
        message: res.message ?? 'Erro ao carregar a integração',
        statusCode: res.statusCode,
      );
    }
    final raw = _unwrap(res);
    final active = asBool(raw['isActive']);
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'whatsapp-lead-claim',
        configured: active,
        active: active,
        statusLine: active
            ? 'Conexão QR Code ativa — leads podem ser anunciados no grupo.'
            : 'Depende da conexão QR Code do WhatsApp (não-oficial).',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchMetaCampaign() async {
    final res = await _api.get<Map<String, dynamic>>(_metaCampaignConfig);
    if (!res.success && res.statusCode == 0) {
      return _netError(res);
    }
    final raw = _unwrap(res);
    final active = asBool(raw['isActive']);
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'meta-campaign',
        configured: active,
        active: active,
        statusLine: active
            ? 'Sincronização de campanhas META ativa.'
            : 'Configuração pendente ou desativada.',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchGoogleAds() async {
    final res = await _api.get<Map<String, dynamic>>(_googleAdsStatus);
    if (!res.success && res.statusCode == 0) {
      return _netError(res);
    }
    final raw = _unwrap(res);
    final configured = asBool(raw['isActive']) &&
        asBool(raw['hasOAuthToken']) &&
        asBool(raw['hasAppCredentials']);
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'google-ads',
        configured: configured,
        active: asBool(raw['isActive']),
        statusLine: configured
            ? 'Conta conectada — custo e métricas sincronizando.'
            : !asBool(raw['hasAppCredentials'])
                ? 'Credenciais do app ainda não configuradas.'
                : !asBool(raw['hasOAuthToken'])
                    ? 'Conta Google ainda não conectada (OAuth).'
                    : 'Integração desativada.',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchGa4() async {
    final res = await _api.get<Map<String, dynamic>>(_ga4Status);
    if (!res.success && res.statusCode == 0) {
      return _netError(res);
    }
    final raw = _unwrap(res);
    final configured = asBool(raw['isActive']) && asBool(raw['hasOAuthToken']);
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'ga4',
        configured: configured,
        active: asBool(raw['isActive']),
        statusLine: configured
            ? 'GA4 conectado — contatos únicos vindo do Analytics.'
            : !asBool(raw['hasOAuthToken'])
                ? 'Conta Google ainda não conectada (OAuth).'
                : 'Integração desativada.',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  /// Grupo ZAP e Chaves na Mão têm a mesma regra:
  /// conectado se `isActive` OU já existe `feedToken`/`webhookToken`.
  Future<ApiResponse<IntegrationStatusData>> _fetchPortalConfig(
    String key,
    String endpoint,
  ) async {
    final res = await _api.get<Map<String, dynamic>>(endpoint);
    if (!res.success && res.statusCode == 0) {
      return _netError(res);
    }
    final raw = _unwrap(res);
    final active = asBool(raw['isActive']);
    final configured = active ||
        asString(raw['feedToken']) != null ||
        asString(raw['webhookToken']) != null;
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: key,
        configured: configured,
        active: active,
        statusLine: active
            ? 'Sindicação ativa — imóveis e leads sincronizando.'
            : configured
                ? 'Tokens gerados, mas a sindicação está desativada.'
                : 'Configuração ainda não iniciada.',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchPropertiesApi() async {
    final res = await _api.get<Map<String, dynamic>>(_propertiesApiConfig);
    if (!res.success && res.statusCode == 0) {
      return _netError(res);
    }
    final raw = _unwrap(res);
    final enabled = asBool(raw['enabled']);
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'properties-api',
        configured: enabled,
        active: enabled,
        statusLine: enabled
            ? 'API pública habilitada para o site da imobiliária.'
            : 'API pública desabilitada.',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchImovelweb() async {
    final res = await _api.get<Map<String, dynamic>>(_imovelwebConfig);
    if (!res.success && res.statusCode == 0) {
      return _netError(res);
    }
    final raw = _unwrap(res);
    final configured =
        asBool(raw['isActive']) && asBool(raw['hasCredentials']);
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'imovelweb',
        configured: configured,
        active: asBool(raw['isActive']),
        statusLine: configured
            ? 'Publicação via API ativa nos portais do grupo.'
            : !asBool(raw['hasCredentials'])
                ? 'Credenciais de API ainda não configuradas.'
                : 'Integração desativada.',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  /// Autentique: tenta a config mascarada (exige autentique:view/manage);
  /// sem acesso, cai para o `/status` (qualquer usuário autenticado).
  Future<ApiResponse<IntegrationStatusData>> _fetchAutentique() async {
    var res = await _api.get<Map<String, dynamic>>(_autentiqueCompanyConfig);
    if (!res.success) {
      if (res.statusCode == 0) return _netError(res);
      res = await _api.get<Map<String, dynamic>>(_autentiqueStatus);
      if (!res.success && res.statusCode == 0) return _netError(res);
    }
    final raw = _unwrap(res);
    final active = asBool(raw['active']);
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'autentique',
        configured: active,
        active: active,
        statusLine: active
            ? 'Assinatura digital ativa para a empresa.'
            : asBool(raw['hasApiKey'])
                ? 'Chave configurada, mas a integração está desativada.'
                : 'Chave de API da Autentique ainda não configurada.',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchCustomLeads(
    String key,
  ) async {
    final res = await _api.get<Map<String, dynamic>>(_customLeadsConfig);
    if (!res.success && res.statusCode == 0) {
      return _netError(res);
    }
    final raw = _unwrap(res);
    final configured = asString(raw['webhookUrl']) != null ||
        asString(raw['webhookTokenMasked']) != null;
    final statusLine = key == 'chat-pro'
        ? (configured
            ? 'Webhook pronto — conecte as linhas do ChatPro à URL gerada.'
            : 'Conclua o Webhook de Leads para liberar o ChatPro.')
        : (configured
            ? 'Webhook gerado — pronto para receber leads via POST.'
            : 'Webhook ainda não configurado.');
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: key,
        configured: configured,
        active: asBool(raw['isActive']),
        statusLine: statusLine,
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  Future<ApiResponse<IntegrationStatusData>> _fetchFichaWebhooks() async {
    final res = await _api.get<Map<String, dynamic>>(_fichaWebhooksConfig);
    if (!res.success && res.statusCode == 0) {
      return _netError(res);
    }
    final raw = _unwrap(res);
    final configured = asString(raw['webhookUrl']) != null;
    return ApiResponse.success(
      data: IntegrationStatusData(
        key: 'ficha-webhooks',
        configured: configured,
        active: asBool(raw['isActive']),
        statusLine: configured
            ? 'Eventos de fichas sendo enviados ao endpoint configurado.'
            : 'Endpoint de destino ainda não configurado.',
        raw: raw,
      ),
      statusCode: 200,
    );
  }

  // ─── Ações leves ──────────────────────────────────────────────────────────

  /// Ativa/desativa uma integração que expõe PATCH/PUT leve com `isActive`.
  /// Chaves suportadas: meta-campaign, grupo-zap, chaves-na-mao, imovelweb
  /// (PATCH no /config) e autentique (PUT no /company-config).
  Future<ApiResponse<bool>> setActive(String key, bool active) async {
    try {
      ApiResponse<dynamic> res;
      switch (key) {
        case 'meta-campaign':
          res = await _api.patch<dynamic>(_metaCampaignConfig,
              body: {'isActive': active});
          break;
        case 'grupo-zap':
          res = await _api.patch<dynamic>(_grupoZapConfig,
              body: {'isActive': active});
          break;
        case 'chaves-na-mao':
          res = await _api.patch<dynamic>(_chavesNaMaoConfig,
              body: {'isActive': active});
          break;
        case 'imovelweb':
          res = await _api.patch<dynamic>(_imovelwebConfig,
              body: {'isActive': active});
          break;
        case 'autentique':
          res = await _api.put<dynamic>(_autentiqueCompanyConfig,
              body: {'isActive': active});
          break;
        default:
          return ApiResponse.error(
            message: 'Esta integração não permite ativar/desativar pelo app.',
            statusCode: 400,
          );
      }
      if (res.success) {
        return ApiResponse.success(data: true, statusCode: res.statusCode);
      }
      return ApiResponse.error(
        message: res.message ??
            (active
                ? 'Erro ao ativar a integração'
                : 'Erro ao desativar a integração'),
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('❌ [INTEGRATIONS] setActive($key): $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Testa a conexão de integrações que expõem POST test-connection
  /// (google-ads, ga4 e imovelweb).
  Future<ApiResponse<IntegrationTestResult>> testConnection(String key) async {
    try {
      String endpoint;
      switch (key) {
        case 'google-ads':
          endpoint = _googleAdsTestConnection;
          break;
        case 'ga4':
          endpoint = _ga4TestConnection;
          break;
        case 'imovelweb':
          endpoint = _imovelwebTestConnection;
          break;
        default:
          return ApiResponse.error(
            message: 'Esta integração não expõe teste de conexão.',
            statusCode: 400,
          );
      }
      final res = await _api.post<Map<String, dynamic>>(endpoint, body: {});
      if (res.success) {
        final raw = _unwrap(res);
        return ApiResponse.success(
          data: IntegrationTestResult.fromJson(raw),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Falha no teste de conexão',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('❌ [INTEGRATIONS] testConnection($key): $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Desembrulha `{ data: {...} }` quando o backend envelopa a resposta e
  /// tolera respostas nulas/tipos inesperados (devolve mapa vazio).
  Map<String, dynamic> _unwrap(ApiResponse<dynamic> res) {
    final data = res.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final inner = map['data'];
      if (inner is Map &&
          (map.length == 1 || (map.length == 2 && map.containsKey('success')))) {
        return Map<String, dynamic>.from(inner);
      }
      return map;
    }
    return const {};
  }

  ApiResponse<IntegrationStatusData> _netError(ApiResponse<dynamic> res) {
    return ApiResponse.error(
      message: res.message ?? 'Erro ao carregar a integração',
      statusCode: res.statusCode,
      data: res.error,
    );
  }
}
