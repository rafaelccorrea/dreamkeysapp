// Modelos da Central de Integrações — espelham o hub `IntegrationsPage.tsx`
// do imobx-front (catálogo, categorias, permissões e regras de status).
//
// O app NÃO configura integrações pesadas: mostra o status real vindo do
// backend, informações de conexão e ações leves (ativar/desativar/testar)
// quando o backend expõe endpoint próprio para isso.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ─── Helpers defensivos (null/string/number tolerantes) ─────────────────────

bool asBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'sim';
  }
  return false;
}

String? asString(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

DateTime? asDate(dynamic v) {
  final s = asString(v);
  if (s == null) return null;
  return DateTime.tryParse(s);
}

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return const {};
}

final DateFormat integrationDateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

// ─── Categorias (paridade com CATEGORY_META do web) ─────────────────────────

enum IntegrationCategory {
  messaging,
  marketing,
  portals,
  leads,
  documents;

  String get label {
    switch (this) {
      case IntegrationCategory.messaging:
        return 'Mensageria';
      case IntegrationCategory.marketing:
        return 'Marketing & Campanhas';
      case IntegrationCategory.portals:
        return 'Portais imobiliários';
      case IntegrationCategory.leads:
        return 'Leads & Automação';
      case IntegrationCategory.documents:
        return 'Documentos & Assinatura';
    }
  }

  /// Cor da categoria — mesma paleta do hub web (`CATEGORY_META`).
  Color get color {
    switch (this) {
      case IntegrationCategory.messaging:
        return const Color(0xFF25D366);
      case IntegrationCategory.marketing:
        return const Color(0xFFDD2A7B);
      case IntegrationCategory.portals:
        return const Color(0xFF00A651);
      case IntegrationCategory.leads:
        return const Color(0xFF6366F1);
      case IntegrationCategory.documents:
        return const Color(0xFF16A34A);
    }
  }
}

/// Ordem de exibição das seções (paridade com `CATEGORY_ORDER` do web).
const List<IntegrationCategory> kIntegrationCategoryOrder = [
  IntegrationCategory.messaging,
  IntegrationCategory.marketing,
  IntegrationCategory.portals,
  IntegrationCategory.leads,
  IntegrationCategory.documents,
];

// ─── Permissões (strings EXATAS do web: integrations.routes.tsx) ────────────

class IntegrationPermissions {
  IntegrationPermissions._();

  static const whatsappView = 'whatsapp:view';
  static const whatsappViewMessages = 'whatsapp:view_messages';
  static const whatsappManageConfig = 'whatsapp:manage_config';
  static const metaCampaignView = 'meta_campaign:view';
  static const metaCampaignManageConfig = 'meta_campaign:manage_config';
  static const googleAdsView = 'google_ads:view';
  static const googleAdsManageConfig = 'google_ads:manage_config';
  static const grupoZapView = 'grupo_zap:view';
  static const grupoZapManageConfig = 'grupo_zap:manage_config';
  static const propertiesApiView = 'properties_api:view';
  static const propertiesApiManage = 'properties_api:manage';
  static const chavesNaMaoView = 'chaves_na_mao:view';
  static const chavesNaMaoManageConfig = 'chaves_na_mao:manage_config';
  static const imovelwebView = 'imovelweb:view';
  static const imovelwebManageConfig = 'imovelweb:manage_config';
  static const autentiqueView = 'autentique:view';
  static const autentiqueManageConfig = 'autentique:manage_config';
  static const leadDistributionView = 'lead_distribution:view';
  static const leadDistributionManageConfig = 'lead_distribution:manage_config';
  static const instagramView = 'instagram:view';
  static const instagramManageConfig = 'instagram:manage_config';
  static const kanbanView = 'kanban:view';
  static const kanbanManageUsers = 'kanban:manage_users';

  /// Permissões que liberam a rota `/integrations` no web (any-of).
  static const List<String> hubRoute = [
    whatsappView,
    whatsappViewMessages,
    whatsappManageConfig,
    metaCampaignView,
    metaCampaignManageConfig,
    grupoZapView,
    grupoZapManageConfig,
    leadDistributionView,
    leadDistributionManageConfig,
    kanbanView,
    kanbanManageUsers,
    instagramView,
    instagramManageConfig,
  ];

  /// Módulos que liberam a rota `/integrations` no web (any-of).
  static const List<String> hubModules = [
    'api_integrations',
    'third_party_integrations',
    'lead_distribution',
  ];

  /// Gate do card "Webhook de Leads"/"ChatPro"/"Webhook de Fichas" — espelha
  /// o `showCustomLeadCard` do hub web (qualquer permissão de integração).
  static const List<String> customLeadCard = [
    kanbanView,
    kanbanManageUsers,
    metaCampaignView,
    grupoZapView,
    leadDistributionView,
    instagramView,
    whatsappView,
    chavesNaMaoView,
    imovelwebView,
  ];
}

// ─── Definição de uma integração (catálogo) ─────────────────────────────────

class IntegrationDef {
  final String key;
  final String name;
  final String tagline;

  /// Descrição quando ainda pendente.
  final String description;

  /// Descrição quando conectada (fallback: [description]).
  final String? configuredDescription;

  final List<String> features;
  final IntegrationCategory category;
  final IconData icon;

  /// Cor de marca da integração (accent do card — mesma do hub web).
  final Color accent;

  /// Permissões que fazem o card aparecer (any-of, com bypass de role).
  final List<String> viewPermissions;

  /// Permissões que liberam ações de gestão (toggle) — any-of.
  final List<String> managePermissions;

  /// Backend expõe ativar/desativar leve (PATCH/PUT com `isActive`)?
  final bool supportsToggle;

  /// Backend expõe teste de conexão (POST test-connection)?
  final bool supportsTest;

  const IntegrationDef({
    required this.key,
    required this.name,
    required this.tagline,
    required this.description,
    this.configuredDescription,
    required this.features,
    required this.category,
    required this.icon,
    required this.accent,
    required this.viewPermissions,
    required this.managePermissions,
    this.supportsToggle = false,
    this.supportsTest = false,
  });

  String descriptionFor(bool configured) =>
      configured ? (configuredDescription ?? description) : description;
}

// ─── Catálogo (paridade com o hub web; instagram/lead-distribution ocultos) ─

class IntegrationCatalog {
  IntegrationCatalog._();

  static const List<IntegrationDef> all = [
    // ── Mensageria ──
    IntegrationDef(
      key: 'whatsapp',
      name: 'WhatsApp',
      tagline: 'Mensageria oficial e não-oficial',
      description:
          'Conecte a API Oficial ou QR Code, agende mensagens e crie respostas rápidas.',
      configuredDescription:
          'Mensageria ativa — API Oficial e/ou conexão QR Code funcionando para a empresa.',
      features: ['API Oficial', 'QR Code', 'Templates', 'Agendamento'],
      category: IntegrationCategory.messaging,
      icon: LucideIcons.messageCircle,
      accent: Color(0xFF25D366),
      viewPermissions: [
        IntegrationPermissions.whatsappView,
        IntegrationPermissions.whatsappManageConfig,
      ],
      managePermissions: [IntegrationPermissions.whatsappManageConfig],
    ),
    IntegrationDef(
      key: 'whatsapp-lead-claim',
      name: 'Atribuição por Grupo WhatsApp',
      tagline: 'Primeiro a responder ganha o lead',
      description:
          'Anuncie leads novos em um grupo do WhatsApp — o primeiro corretor que responder "EU" ganha o lead automaticamente.',
      features: ['Grupo', 'Claim "EU"', 'First-wins', 'Auto-atribuição'],
      category: IntegrationCategory.messaging,
      icon: LucideIcons.users,
      accent: Color(0xFF128C7E),
      viewPermissions: [IntegrationPermissions.whatsappManageConfig],
      managePermissions: [IntegrationPermissions.whatsappManageConfig],
    ),
    IntegrationDef(
      key: 'chat-pro',
      name: 'ChatPro (Sparks)',
      tagline: 'WhatsApp via Sparks',
      description:
          'Conecte o ChatPro ao CRM. Conclua o Webhook de Leads e use a URL indicada.',
      configuredDescription:
          'Receba conversas do ChatPro e gere cards no funil conforme cada linha cadastrada.',
      features: ['Sparks', 'WhatsApp', 'Auto-card', 'Multi-instância'],
      category: IntegrationCategory.messaging,
      icon: LucideIcons.messagesSquare,
      accent: Color(0xFF2563EB),
      viewPermissions: IntegrationPermissions.customLeadCard,
      managePermissions: [IntegrationPermissions.kanbanManageUsers],
    ),

    // ── Marketing & Campanhas ──
    IntegrationDef(
      key: 'meta-campaign',
      name: 'Campanhas META',
      tagline: 'Anúncios Facebook & Instagram',
      description:
          'Sincronize campanhas do Facebook e Instagram Ads. Traga leads e métricas direto para o CRM.',
      features: ['Facebook Ads', 'Instagram Ads', 'Leads Forms', 'Métricas'],
      category: IntegrationCategory.marketing,
      icon: LucideIcons.megaphone,
      accent: Color(0xFF1877F2),
      viewPermissions: [
        IntegrationPermissions.metaCampaignView,
        IntegrationPermissions.metaCampaignManageConfig,
      ],
      managePermissions: [IntegrationPermissions.metaCampaignManageConfig],
      supportsToggle: true,
    ),
    IntegrationDef(
      key: 'system-campaigns',
      name: 'Campanhas do Sistema',
      tagline: 'Painel de campanhas próprias',
      description:
          'Crie campanhas próprias (Google, TikTok, offline...). Vincule leads, orçamento, custo e período.',
      features: ['Multi-canal', 'Orçamento', 'ROI', 'Atribuição'],
      category: IntegrationCategory.marketing,
      icon: LucideIcons.flag,
      accent: Color(0xFFDC2626),
      viewPermissions: [
        IntegrationPermissions.metaCampaignView,
        IntegrationPermissions.metaCampaignManageConfig,
      ],
      managePermissions: [IntegrationPermissions.metaCampaignManageConfig],
    ),
    IntegrationDef(
      key: 'google-ads',
      name: 'Google Ads',
      tagline: 'Anúncios Google (Search, Display, YouTube)',
      description:
          'Conecte sua conta Google Ads para puxar custo, impressões e cliques por campanha. CPL real na análise de canais.',
      features: ['Search', 'Display', 'YouTube', 'CPL real'],
      category: IntegrationCategory.marketing,
      icon: LucideIcons.chartColumnBig,
      accent: Color(0xFF4285F4),
      viewPermissions: [
        IntegrationPermissions.googleAdsView,
        IntegrationPermissions.googleAdsManageConfig,
      ],
      managePermissions: [IntegrationPermissions.googleAdsManageConfig],
      supportsTest: true,
    ),
    IntegrationDef(
      key: 'ga4',
      name: 'Google Analytics 4',
      tagline: 'Contatos únicos do Google Analytics',
      description:
          'Conecte o GA4 para os "Contatos únicos de WhatsApp" da análise multicanal virem direto do Google Analytics.',
      features: ['Analytics', 'Contatos únicos', 'WhatsApp', 'Bate com GA4'],
      category: IntegrationCategory.marketing,
      icon: LucideIcons.chartPie,
      accent: Color(0xFFE8710A),
      viewPermissions: [
        IntegrationPermissions.googleAdsView,
        IntegrationPermissions.googleAdsManageConfig,
      ],
      managePermissions: [IntegrationPermissions.googleAdsManageConfig],
      supportsTest: true,
    ),

    // ── Portais imobiliários ──
    IntegrationDef(
      key: 'grupo-zap',
      name: 'Portal Grupo ZAP',
      tagline: 'Sindicação Grupo ZAP',
      description:
          'Publique imóveis no ZAP Imóveis, Viva Real e OLX e capte leads automaticamente.',
      features: ['ZAP', 'Viva Real', 'OLX', 'Auto leads'],
      category: IntegrationCategory.portals,
      icon: LucideIcons.zap,
      accent: Color(0xFF00A651),
      viewPermissions: [
        IntegrationPermissions.grupoZapView,
        IntegrationPermissions.grupoZapManageConfig,
      ],
      managePermissions: [IntegrationPermissions.grupoZapManageConfig],
      supportsToggle: true,
    ),
    IntegrationDef(
      key: 'properties-api',
      name: 'API de Imóveis',
      tagline: 'API de imóveis para o seu site',
      description:
          'Disponibilize os imóveis publicados da sua imobiliária no seu próprio site (widget pronto ou API JSON).',
      features: ['Widget', 'API JSON', 'Multi-domínio', 'Somente-leitura'],
      category: IntegrationCategory.portals,
      icon: LucideIcons.globe,
      accent: Color(0xFF2563EB),
      viewPermissions: [
        IntegrationPermissions.propertiesApiView,
        IntegrationPermissions.propertiesApiManage,
      ],
      managePermissions: [IntegrationPermissions.propertiesApiManage],
    ),
    IntegrationDef(
      key: 'chaves-na-mao',
      name: 'Portal Chaves na Mão',
      tagline: 'Sindicação Chaves na Mão',
      description:
          'Publique imóveis via XML no Chaves na Mão e receba leads direto no CRM.',
      features: ['XML', 'Auto leads', 'Sync diário'],
      category: IntegrationCategory.portals,
      icon: LucideIcons.keyRound,
      accent: Color(0xFFE8132A),
      viewPermissions: [
        IntegrationPermissions.chavesNaMaoView,
        IntegrationPermissions.chavesNaMaoManageConfig,
      ],
      managePermissions: [IntegrationPermissions.chavesNaMaoManageConfig],
      supportsToggle: true,
    ),
    IntegrationDef(
      key: 'imovelweb',
      name: 'Imovelweb / Wimoveis / Casa Mineira',
      tagline: 'Portais do Grupo QuintoAndar',
      description:
          'Publique anúncios via API nos portais do Grupo QuintoAndar e receba leads (callback) no CRM.',
      features: ['Imovelweb', 'Wimoveis', 'Casa Mineira', 'API + Callback'],
      category: IntegrationCategory.portals,
      icon: LucideIcons.building2,
      accent: Color(0xFFFF5500),
      viewPermissions: [
        IntegrationPermissions.imovelwebView,
        IntegrationPermissions.imovelwebManageConfig,
      ],
      managePermissions: [IntegrationPermissions.imovelwebManageConfig],
      supportsToggle: true,
      supportsTest: true,
    ),

    // ── Leads & Automação ──
    IntegrationDef(
      key: 'custom-leads',
      name: 'Webhook de Leads',
      tagline: 'Webhook genérico',
      description:
          'Receba leads de qualquer sistema via webhook. Configure o funil e use a URL gerada.',
      configuredDescription:
          'Integração ativa. Receba leads de qualquer sistema via POST na URL do webhook.',
      features: ['Webhook', 'Token', 'Multi-funil', 'Anti-duplicação'],
      category: IntegrationCategory.leads,
      icon: LucideIcons.webhook,
      accent: Color(0xFF0891B2),
      viewPermissions: IntegrationPermissions.customLeadCard,
      managePermissions: [IntegrationPermissions.kanbanManageUsers],
    ),
    IntegrationDef(
      key: 'ficha-webhooks',
      name: 'Webhook de Fichas',
      tagline: 'Webhook outbound de fichas',
      description:
          'Configure endpoint, segredo e filtros para enviar eventos de fichas para outro sistema.',
      configuredDescription:
          'Integração outbound ativa. Envie criação e mudança de status das fichas para sistemas externos.',
      features: ['Outbound', 'Retentativas', 'Logs', 'Replay'],
      category: IntegrationCategory.leads,
      icon: LucideIcons.share2,
      accent: Color(0xFF2563EB),
      viewPermissions: IntegrationPermissions.customLeadCard,
      managePermissions: [
        IntegrationPermissions.leadDistributionManageConfig,
      ],
    ),

    // ── Documentos & Assinatura ──
    IntegrationDef(
      key: 'autentique',
      name: 'Autentique',
      tagline: 'Assinatura digital de documentos',
      description:
          'Assinatura digital com a conta Autentique da sua empresa. Enquanto não estiver ativa, os envios para assinatura ficam bloqueados.',
      configuredDescription:
          'Assinatura digital ativa — fichas e propostas podem ser enviadas para assinatura.',
      features: ['Assinatura digital', 'Fichas', 'Propostas', 'Por empresa'],
      category: IntegrationCategory.documents,
      icon: LucideIcons.signature,
      accent: Color(0xFF16A34A),
      viewPermissions: [
        IntegrationPermissions.autentiqueView,
        IntegrationPermissions.autentiqueManageConfig,
      ],
      managePermissions: [IntegrationPermissions.autentiqueManageConfig],
      supportsToggle: true,
    ),
  ];

  static IntegrationDef? byKey(String key) {
    for (final def in all) {
      if (def.key == key) return def;
    }
    return null;
  }
}

// ─── Status carregado do backend ─────────────────────────────────────────────

class IntegrationStatusData {
  final String key;

  /// "Conectado" segundo as MESMAS regras do hub web.
  final bool configured;

  /// Flag `isActive`/`active`/`enabled` crua (quando o payload traz).
  final bool? active;

  /// Uma linha de contexto ("API Oficial ativa", "Chave OAuth conectada"...).
  final String? statusLine;

  /// Payload cru principal (config/status).
  final Map<String, dynamic> raw;

  /// Payload auxiliar (ex.: config não-oficial do WhatsApp).
  final Map<String, dynamic>? extraRaw;

  const IntegrationStatusData({
    required this.key,
    required this.configured,
    this.active,
    this.statusLine,
    this.raw = const {},
    this.extraRaw,
  });

  IntegrationStatusData copyWith({bool? configured, bool? active}) {
    return IntegrationStatusData(
      key: key,
      configured: configured ?? this.configured,
      active: active ?? this.active,
      statusLine: statusLine,
      raw: raw,
      extraRaw: extraRaw,
    );
  }
}

/// Resultado de um teste de conexão (google-ads / ga4 / imovelweb).
class IntegrationTestResult {
  final bool ok;
  final String message;

  const IntegrationTestResult({required this.ok, required this.message});

  factory IntegrationTestResult.fromJson(Map<String, dynamic> json) {
    final ok = json.containsKey('success')
        ? asBool(json['success'])
        : json.containsKey('ok')
            ? asBool(json['ok'])
            : json.containsKey('connected')
                ? asBool(json['connected'])
                : true;
    final message = asString(json['message']) ??
        asString(json['error']) ??
        asString(json['detail']) ??
        (ok ? 'Conexão validada com sucesso.' : 'Falha ao validar a conexão.');
    return IntegrationTestResult(ok: ok, message: message);
  }
}

// ─── Linhas de "Informações de conexão" (detalhe) ────────────────────────────

enum InfoTone { neutral, good, warn, bad }

class IntegrationInfoRow {
  final String label;
  final String value;
  final InfoTone tone;
  final IconData? icon;

  const IntegrationInfoRow({
    required this.label,
    required this.value,
    this.tone = InfoTone.neutral,
    this.icon,
  });
}

String _onOff(bool v, {String on = 'Ativa', String off = 'Inativa'}) =>
    v ? on : off;

InfoTone _toneOf(bool v) => v ? InfoTone.good : InfoTone.warn;

IntegrationInfoRow _flagRow(String label, bool v,
    {String on = 'Ativa', String off = 'Inativa', IconData? icon}) {
  return IntegrationInfoRow(
    label: label,
    value: _onOff(v, on: on, off: off),
    tone: _toneOf(v),
    icon: icon,
  );
}

IntegrationInfoRow _presenceRow(String label, dynamic value,
    {IconData? icon}) {
  final present = asString(value) != null;
  return IntegrationInfoRow(
    label: label,
    value: present ? 'Configurado' : 'Não configurado',
    tone: _toneOf(present),
    icon: icon,
  );
}

String _truncateMiddle(String s, {int max = 34}) {
  if (s.length <= max) return s;
  final head = s.substring(0, max ~/ 2);
  final tail = s.substring(s.length - (max ~/ 2 - 2));
  return '$head…$tail';
}

/// Monta as linhas de informação de conexão do detalhe, por integração.
/// Leitura 100% defensiva do payload cru.
List<IntegrationInfoRow> buildIntegrationInfoRows(
  IntegrationDef def,
  IntegrationStatusData st,
) {
  final raw = st.raw;
  final rows = <IntegrationInfoRow>[];

  void addDate(String label, dynamic v) {
    final d = asDate(v);
    if (d != null) {
      rows.add(IntegrationInfoRow(
        label: label,
        value: integrationDateFormat.format(d.toLocal()),
        icon: LucideIcons.calendarDays,
      ));
    }
  }

  switch (def.key) {
    case 'whatsapp':
      final unofficial = st.extraRaw ?? const {};
      rows.add(_flagRow('API Oficial', asBool(raw['isActive'])));
      final phone = asString(raw['phoneNumber']);
      if (phone != null) {
        rows.add(IntegrationInfoRow(
            label: 'Número conectado', value: phone,
            icon: LucideIcons.phone));
      }
      final business = asString(raw['businessName']);
      if (business != null) {
        rows.add(IntegrationInfoRow(
            label: 'Conta business', value: business,
            icon: LucideIcons.building2));
      }
      rows.add(_flagRow('Conexão QR Code (não-oficial)',
          asBool(unofficial['isActive']),
          on: 'Ativa', off: 'Inativa'));
      break;

    case 'whatsapp-lead-claim':
      rows.add(_flagRow('Conexão QR Code', asBool(raw['isActive'])));
      rows.add(const IntegrationInfoRow(
        label: 'Modo de atribuição',
        value: 'Primeiro "EU" ganha o lead',
        icon: LucideIcons.users,
      ));
      break;

    case 'meta-campaign':
      rows.add(_flagRow('Sincronização', asBool(raw['isActive'])));
      final account =
          asString(raw['adAccountId']) ?? asString(raw['accountId']);
      if (account != null) {
        rows.add(IntegrationInfoRow(
            label: 'Conta de anúncios', value: account,
            icon: LucideIcons.megaphone));
      }
      final page = asString(raw['pageName']) ?? asString(raw['pageId']);
      if (page != null) {
        rows.add(IntegrationInfoRow(
            label: 'Página vinculada', value: page,
            icon: LucideIcons.flag));
      }
      addDate('Atualizada em', raw['updatedAt']);
      break;

    case 'system-campaigns':
      rows.add(const IntegrationInfoRow(
        label: 'Painel',
        value: 'Sempre disponível',
        tone: InfoTone.good,
        icon: LucideIcons.circleCheckBig,
      ));
      rows.add(const IntegrationInfoRow(
        label: 'Canais',
        value: 'Google, TikTok, offline e outros',
        icon: LucideIcons.share2,
      ));
      break;

    case 'google-ads':
      rows.add(_flagRow('Integração', asBool(raw['isActive'])));
      rows.add(_flagRow('Credenciais do app', asBool(raw['hasAppCredentials']),
          on: 'Configuradas', off: 'Pendentes'));
      rows.add(_flagRow('Conta Google conectada (OAuth)',
          asBool(raw['hasOAuthToken']),
          on: 'Conectada', off: 'Não conectada'));
      final customer = asString(raw['customerId']);
      if (customer != null) {
        rows.add(IntegrationInfoRow(
            label: 'Customer ID', value: customer,
            icon: LucideIcons.hash));
      }
      addDate('Última sincronização', raw['lastSyncAt']);
      final syncError = asString(raw['lastSyncError']);
      if (syncError != null) {
        rows.add(IntegrationInfoRow(
          label: 'Erro de sincronização',
          value: _truncateMiddle(syncError, max: 60),
          tone: InfoTone.bad,
          icon: LucideIcons.circleAlert,
        ));
      }
      break;

    case 'ga4':
      rows.add(_flagRow('Integração', asBool(raw['isActive'])));
      rows.add(_flagRow('Conta Google conectada (OAuth)',
          asBool(raw['hasOAuthToken']),
          on: 'Conectada', off: 'Não conectada'));
      final property = asString(raw['propertyId']);
      if (property != null) {
        rows.add(IntegrationInfoRow(
            label: 'Property ID', value: property, icon: LucideIcons.hash));
      }
      final event = asString(raw['whatsappEventName']);
      if (event != null) {
        rows.add(IntegrationInfoRow(
            label: 'Evento de WhatsApp', value: event,
            icon: LucideIcons.activity));
      }
      addDate('Última sincronização', raw['lastSyncAt']);
      final ga4Error = asString(raw['lastSyncError']);
      if (ga4Error != null) {
        rows.add(IntegrationInfoRow(
          label: 'Erro de sincronização',
          value: _truncateMiddle(ga4Error, max: 60),
          tone: InfoTone.bad,
          icon: LucideIcons.circleAlert,
        ));
      }
      break;

    case 'grupo-zap':
    case 'chaves-na-mao':
      rows.add(_flagRow('Integração', asBool(raw['isActive'])));
      rows.add(_flagRow('Sincronizar imóveis', asBool(raw['syncProperties']),
          on: 'Sim', off: 'Não'));
      rows.add(_flagRow('Receber leads', asBool(raw['syncLeads']),
          on: 'Sim', off: 'Não'));
      rows.add(_presenceRow('Feed XML (token)', raw['feedToken'],
          icon: LucideIcons.rss));
      rows.add(_presenceRow('Webhook de leads (token)', raw['webhookToken'],
          icon: LucideIcons.webhook));
      final team = asMap(raw['leadDistributionTeam']);
      final teamName = asString(team['name']);
      if (teamName != null) {
        rows.add(IntegrationInfoRow(
            label: 'Equipe de distribuição', value: teamName,
            icon: LucideIcons.users));
      }
      break;

    case 'properties-api':
      final keys = raw['keys'];
      final keyList = keys is List ? keys : const [];
      final activeKeys =
          keyList.where((k) => asBool(asMap(k)['isActive'])).length;
      rows.add(_flagRow('API pública', asBool(raw['enabled']),
          on: 'Habilitada', off: 'Desabilitada'));
      rows.add(IntegrationInfoRow(
        label: 'Chaves ativas',
        value: '$activeKeys de ${keyList.length}',
        tone: activeKeys > 0 ? InfoTone.good : InfoTone.neutral,
        icon: LucideIcons.keyRound,
      ));
      break;

    case 'imovelweb':
      rows.add(_flagRow('Integração', asBool(raw['isActive'])));
      rows.add(_flagRow('Credenciais de API', asBool(raw['hasCredentials']),
          on: 'Configuradas', off: 'Pendentes'));
      final env = asString(raw['environment']);
      if (env != null) {
        rows.add(IntegrationInfoRow(
          label: 'Ambiente',
          value: env.toLowerCase() == 'production' ? 'Produção' : env,
          icon: LucideIcons.satelliteDish,
        ));
      }
      final codigo = asString(raw['codigoInmobiliaria']);
      if (codigo != null) {
        rows.add(IntegrationInfoRow(
            label: 'Código da imobiliária', value: codigo,
            icon: LucideIcons.hash));
      }
      rows.add(_flagRow('Sincronizar imóveis', asBool(raw['syncProperties']),
          on: 'Sim', off: 'Não'));
      rows.add(_flagRow('Receber leads (callback)', asBool(raw['syncLeads']),
          on: 'Sim', off: 'Não'));
      break;

    case 'autentique':
      rows.add(_flagRow('Integração', asBool(raw['active'])));
      rows.add(_flagRow('Chave de API', asBool(raw['hasApiKey']),
          on: 'Configurada', off: 'Pendente'));
      final masked = asString(raw['apiKeyMasked']);
      if (masked != null) {
        rows.add(IntegrationInfoRow(
            label: 'Credencial', value: masked, icon: LucideIcons.lock));
      }
      final aEnv = asString(raw['environment']);
      if (aEnv != null) {
        rows.add(IntegrationInfoRow(
          label: 'Ambiente',
          value: aEnv.toLowerCase() == 'production'
              ? 'Produção'
              : aEnv.toLowerCase() == 'sandbox'
                  ? 'Sandbox'
                  : aEnv,
          icon: LucideIcons.satelliteDish,
        ));
      }
      addDate('Atualizada em', raw['updatedAt']);
      break;

    case 'custom-leads':
      rows.add(_flagRow('Integração', asBool(raw['isActive'])));
      final url = asString(raw['webhookUrl']);
      if (url != null) {
        rows.add(IntegrationInfoRow(
          label: 'URL do webhook',
          value: _truncateMiddle(url),
          tone: InfoTone.good,
          icon: LucideIcons.webhook,
        ));
      }
      rows.add(_presenceRow('Token secreto', raw['webhookTokenMasked'],
          icon: LucideIcons.lock));
      final clTeam = asMap(raw['leadDistributionTeam']);
      final clTeamName = asString(clTeam['name']);
      if (clTeamName != null) {
        rows.add(IntegrationInfoRow(
            label: 'Equipe de distribuição', value: clTeamName,
            icon: LucideIcons.users));
      }
      break;

    case 'ficha-webhooks':
      rows.add(_flagRow('Integração', asBool(raw['isActive'])));
      final fwUrl = asString(raw['webhookUrl']);
      if (fwUrl != null) {
        rows.add(IntegrationInfoRow(
          label: 'Endpoint de destino',
          value: _truncateMiddle(fwUrl),
          tone: InfoTone.good,
          icon: LucideIcons.share2,
        ));
      }
      rows.add(_presenceRow('Segredo (assinatura)', raw['webhookSecretMasked'],
          icon: LucideIcons.lock));
      final statuses = raw['subscribedStatuses'];
      if (statuses is List && statuses.isNotEmpty) {
        rows.add(IntegrationInfoRow(
          label: 'Status assinados',
          value: '${statuses.length}',
          icon: LucideIcons.listChecks,
        ));
      }
      final retries = asInt(raw['maxRetries']);
      if (retries > 0) {
        rows.add(IntegrationInfoRow(
          label: 'Retentativas',
          value: 'até $retries por evento',
          icon: LucideIcons.refreshCw,
        ));
      }
      break;

    case 'chat-pro':
      final ready = st.configured;
      rows.add(IntegrationInfoRow(
        label: 'Pré-requisito (Webhook de Leads)',
        value: ready ? 'Concluído' : 'Pendente',
        tone: _toneOf(ready),
        icon: LucideIcons.webhook,
      ));
      final cpUrl = asString(raw['webhookUrl']);
      if (cpUrl != null) {
        rows.add(IntegrationInfoRow(
          label: 'URL para o ChatPro',
          value: _truncateMiddle(cpUrl),
          tone: InfoTone.good,
          icon: LucideIcons.link2,
        ));
      }
      break;
  }

  return rows;
}
