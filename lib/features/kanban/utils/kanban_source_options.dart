import 'package:flutter/material.dart';

/// Catálogo oficial de "Fonte (Mídia de origem)" do card do CRM — espelho de
/// `imobx-front/src/constants/kanbanSourceOptions.ts` (mesmos valores
/// gravados, mesmas cores). Quem cria e quem edita o card escolhe daqui;
/// quem lê resolve o que está gravado (inclusive rótulos de integrações e
/// slugs de atribuição) para um item deste catálogo.
class KanbanSourceOption {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const KanbanSourceOption({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });
}

const List<KanbanSourceOption> kKanbanSourceOptions = <KanbanSourceOption>[
  KanbanSourceOption(
    value: 'Meta',
    label: 'Meta',
    color: Color(0xFF0081FB),
    icon: Icons.public_rounded,
  ),
  KanbanSourceOption(
    value: 'Facebook Ads',
    label: 'Facebook Ads',
    color: Color(0xFF1877F2),
    icon: Icons.facebook_rounded,
  ),
  KanbanSourceOption(
    value: 'Google Ads',
    label: 'Google Ads',
    color: Color(0xFF4285F4),
    icon: Icons.campaign_rounded,
  ),
  KanbanSourceOption(
    value: 'Google',
    label: 'Google',
    color: Color(0xFF34A853),
    icon: Icons.travel_explore_rounded,
  ),
  KanbanSourceOption(
    value: 'Instagram',
    label: 'Instagram',
    color: Color(0xFFE4405F),
    icon: Icons.photo_camera_rounded,
  ),
  KanbanSourceOption(
    value: 'Instagram Ads',
    label: 'Instagram Ads',
    color: Color(0xFFDD2A7B),
    icon: Icons.photo_camera_rounded,
  ),
  KanbanSourceOption(
    value: 'WhatsApp',
    label: 'WhatsApp',
    color: Color(0xFF25D366),
    icon: Icons.chat_rounded,
  ),
  KanbanSourceOption(
    value: 'ChatPro',
    label: 'ChatPro',
    color: Color(0xFF128C7E),
    icon: Icons.forum_rounded,
  ),
  KanbanSourceOption(
    value: 'Site',
    label: 'Site',
    color: Color(0xFF00897B),
    icon: Icons.language_rounded,
  ),
  KanbanSourceOption(
    value: 'Landing Page',
    label: 'Landing Page',
    color: Color(0xFF0097A7),
    icon: Icons.web_asset_rounded,
  ),
  KanbanSourceOption(
    value: 'Indicação',
    label: 'Indicação',
    color: Color(0xFFFF9800),
    icon: Icons.group_rounded,
  ),
  // Lead que nasce da carteira/rede do corretor (não é indicação de terceiro).
  KanbanSourceOption(
    value: 'Relacionamento',
    label: 'Relacionamento',
    color: Color(0xFFEC4899),
    icon: Icons.handshake_rounded,
  ),
  KanbanSourceOption(
    value: 'ZAP Imóveis',
    label: 'ZAP Imóveis',
    color: Color(0xFFFF6D00),
    icon: Icons.apartment_rounded,
  ),
  KanbanSourceOption(
    value: 'Viva Real',
    label: 'Viva Real',
    color: Color(0xFFFF6900),
    icon: Icons.apartment_rounded,
  ),
  KanbanSourceOption(
    value: 'OLX',
    label: 'OLX',
    color: Color(0xFF6E0AD6),
    icon: Icons.storefront_rounded,
  ),
  KanbanSourceOption(
    value: 'Chaves na Mão',
    label: 'Chaves na Mão',
    color: Color(0xFF1565C0),
    icon: Icons.vpn_key_rounded,
  ),
  KanbanSourceOption(
    value: 'Imovelweb',
    label: 'Imovelweb',
    color: Color(0xFFE53935),
    icon: Icons.apartment_rounded,
  ),
  KanbanSourceOption(
    value: 'Wimoveis',
    label: 'Wimoveis',
    color: Color(0xFFC62828),
    icon: Icons.apartment_rounded,
  ),
  KanbanSourceOption(
    value: 'Casa Mineira',
    label: 'Casa Mineira',
    color: Color(0xFF795548),
    icon: Icons.house_rounded,
  ),
  // Valor gravado continua 'ManyChat' (registros antigos); só o rótulo mudou.
  KanbanSourceOption(
    value: 'ManyChat',
    label: 'Disparos Manychat',
    color: Color(0xFF0084FF),
    icon: Icons.forum_rounded,
  ),
  KanbanSourceOption(
    value: 'Webhook de Leads',
    label: 'Webhook de Leads',
    color: Color(0xFF6366F1),
    icon: Icons.webhook_rounded,
  ),
  KanbanSourceOption(
    value: 'Presencial Imobiliária',
    label: 'Presencial',
    color: Color(0xFF6D4C41),
    icon: Icons.storefront_rounded,
  ),
  KanbanSourceOption(
    value: 'Telefone',
    label: 'Telefone',
    color: Color(0xFF4CAF50),
    icon: Icons.call_rounded,
  ),
  KanbanSourceOption(
    value: 'E-mail',
    label: 'E-mail',
    color: Color(0xFFF59E0B),
    icon: Icons.mail_rounded,
  ),
  KanbanSourceOption(
    value: 'Evento',
    label: 'Evento',
    color: Color(0xFF8B5CF6),
    icon: Icons.event_rounded,
  ),
  KanbanSourceOption(
    value: 'Placa',
    label: 'Placa',
    color: Color(0xFF795548),
    icon: Icons.signpost_rounded,
  ),
  KanbanSourceOption(
    value: 'Outro',
    label: 'Outro',
    color: Color(0xFF78909C),
    icon: Icons.more_horiz_rounded,
  ),
];

const Map<String, String> _kAcentos = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Chave de comparação: sem acento, espaços colapsados, minúscula — igual ao
/// `normalizeKanbanSourceKey` do web.
String normalizeKanbanSourceKey(String s) {
  final lower = s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final sb = StringBuffer();
  for (final r in lower.runes) {
    final ch = String.fromCharCode(r);
    sb.write(_kAcentos[ch] ?? ch);
  }
  return sb.toString();
}

typedef _Regra = ({String value, bool Function(String raw, String n) test});

/// Regras de resolução para valores gravados por integrações/legado (mesma
/// ordem do web — a ordem importa: "instagram ads" antes de "instagram").
final List<_Regra> _kRegras = <_Regra>[
  (
    value: 'Meta',
    test: (_, n) =>
        n.startsWith('meta') ||
        n == 'facebook_ads' ||
        n.contains('facebook/instagram'),
  ),
  (value: 'Facebook Ads', test: (_, n) => n == 'facebook ads' || n == 'facebook'),
  (value: 'Google Ads', test: (_, n) => n == 'google ads' || n == 'google_ads'),
  (value: 'Google', test: (_, n) => n == 'google' || n == 'google_organic'),
  (
    value: 'Instagram Ads',
    test: (_, n) => n == 'instagram ads' || n == 'instagram_ads',
  ),
  (
    value: 'Instagram',
    test: (_, n) =>
        n == 'instagram' ||
        n == 'instagram_organic' ||
        (n.contains('instagram') && !n.contains('ads')),
  ),
  (
    value: 'WhatsApp',
    test: (_, n) =>
        n == 'whatsapp' ||
        n.startsWith('whatsapp') ||
        n == 'whatsapp_direct' ||
        n == 'whatsapp_ctwa',
  ),
  (value: 'ChatPro', test: (_, n) => n.contains('chatpro')),
  (
    value: 'Site',
    test: (_, n) =>
        n == 'site' ||
        n == 'site_direct' ||
        n == 'site_organic' ||
        n.contains('intellisys') ||
        n.contains('dream keys'),
  ),
  (value: 'Landing Page', test: (_, n) => n == 'landing page'),
  (value: 'Indicação', test: (_, n) => n == 'indicacao' || n.contains('indica')),
  (
    value: 'Relacionamento',
    test: (_, n) => n == 'relacionamento' || n.contains('relacionamento'),
  ),
  (
    value: 'Viva Real',
    test: (_, n) =>
        n.contains('viva real') || n == 'vivareal' || n == 'portal_viva',
  ),
  (
    value: 'OLX',
    test: (_, n) =>
        n == 'olx' ||
        n == 'portal_olx' ||
        n == 'grupo olx' ||
        RegExp(r'\bolx\b').hasMatch(n),
  ),
  (
    value: 'ZAP Imóveis',
    test: (raw, n) =>
        n == 'zap' ||
        n.contains('zap imoveis') ||
        n == 'portal_zap' ||
        n == 'grupo zap' ||
        (n.contains('zap') && !n.contains('viva') && !n.contains('olx')) ||
        RegExp(r'^zap\b', caseSensitive: false).hasMatch(raw),
  ),
  (
    value: 'Chaves na Mão',
    test: (_, n) =>
        n.contains('chaves') ||
        n == 'portal_chaves_na_mao' ||
        n == 'chaves na mao',
  ),
  (value: 'Imovelweb', test: (_, n) => n.contains('imovelweb')),
  (value: 'Wimoveis', test: (_, n) => n.contains('wimoveis')),
  (value: 'Casa Mineira', test: (_, n) => n.contains('casa mineira')),
  (value: 'ManyChat', test: (_, n) => n.contains('manychat')),
  (
    value: 'Webhook de Leads',
    test: (_, n) =>
        n.contains('webhook') &&
        (n.contains('lead') || n.contains('personalizado')),
  ),
  (value: 'Presencial Imobiliária', test: (_, n) => n.contains('presencial')),
  (
    value: 'Telefone',
    test: (_, n) => n == 'telefone' || n == 'phone' || n.contains('telefone'),
  ),
  (value: 'E-mail', test: (_, n) => n == 'email' || n == 'e-mail'),
  (value: 'Evento', test: (_, n) => n == 'evento' || n.contains('feiras')),
  (value: 'Placa', test: (_, n) => n == 'placa' || n == 'fachada'),
  (
    value: 'Outro',
    test: (_, n) => n == 'outro' || n == 'other' || n == 'outros',
  ),
];

String? _resolveGravado(String stored) {
  final raw = stored.trim();
  if (raw.isEmpty) return null;
  final n = normalizeKanbanSourceKey(raw);
  for (final o in kKanbanSourceOptions) {
    if (o.value == raw || normalizeKanbanSourceKey(o.value) == n) {
      return o.value;
    }
  }
  for (final r in _kRegras) {
    if (r.test(raw, n)) return r.value;
  }
  return null;
}

/// Resolve `source` / `mediaSource` gravados (inclusive rótulos de
/// integração) para o valor de um item do catálogo. `mediaSource` manda.
String? resolveKanbanSourceToOptionValue(String? source, String? mediaSource) {
  final media = (mediaSource ?? '').trim();
  final src = (source ?? '').trim();
  if (media.isNotEmpty) {
    final r = _resolveGravado(media);
    if (r != null) return r;
  }
  if (src.isNotEmpty) {
    final r = _resolveGravado(src);
    if (r != null) return r;
  }
  return null;
}

/// O item do catálogo correspondente ao que está gravado (null = não
/// resolvido ou vazio).
KanbanSourceOption? kanbanSourceOptionFor(String? source, String? mediaSource) {
  final v = resolveKanbanSourceToOptionValue(source, mediaSource);
  if (v == null) return null;
  for (final o in kKanbanSourceOptions) {
    if (o.value == v) return o;
  }
  return null;
}

/// O texto bruto gravado, para mostrar quando nenhum item do catálogo casa.
String getKanbanSourceStoredDisplay(String? source, String? mediaSource) {
  final src = (source ?? '').trim();
  final media = (mediaSource ?? '').trim();
  return src.isNotEmpty ? src : media;
}

/// Rótulo para exibição: o do catálogo quando resolve; senão o bruto.
String getKanbanSourceLabel(String? source, String? mediaSource) {
  final o = kanbanSourceOptionFor(source, mediaSource);
  if (o != null) return o.label;
  return getKanbanSourceStoredDisplay(source, mediaSource);
}
