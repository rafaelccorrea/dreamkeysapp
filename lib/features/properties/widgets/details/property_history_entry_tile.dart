import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../../documents/utils/document_file_actions.dart';
import '../../models/property_activity_models.dart';
import '../../services/property_detail_extras_service.dart';
import 'property_details_kit.dart';

/// Títulos pt-BR dos eventos — `EVENT_TITLE_PT` do web
/// (`utils/propertyHistoryLabels.ts`).
const Map<String, String> _kEventTitles = <String, String>{
  'availability_requested': 'Fila de disponibilidade',
  'availability_approved': 'Disponibilidade aprovada',
  'availability_rejected': 'Disponibilidade recusada',
  'publication_requested': 'Fila de publicação no site',
  'publication_approved': 'Publicação no site aprovada',
  'publication_rejected': 'Publicação no site recusada',
  'republished_on_site': 'Imóvel republicado no site',
  'vote_cast': 'Voto na aprovação',
  'vote_updated': 'Voto alterado',
  'change_request_submitted': 'Alteração solicitada',
  'change_request_approved': 'Alteração aprovada',
  'change_request_rejected': 'Alteração recusada',
  'created': 'Imóvel cadastrado',
  'updated': 'Dados atualizados',
  'deleted': 'Imóvel excluído',
  'reverted_to_revision': 'Versão restaurada',
  'approval_rules_bulk_status': 'Status alterado (regras de aprovação)',
  'status_changed': 'Status alterado',
  'marked_as_sold': 'Marcado como vendido',
  'marked_as_rented': 'Marcado como alugado',
  'owner_authorization_invalidated': 'Autorização do proprietário invalidada',
  'owner_authorization_sent': 'Autorização enviada ao proprietário',
  'owner_authorization_signed': 'Autorização do proprietário assinada',
  'owner_authorization_signature_waived': 'Assinatura digital dispensada',
  'approval_reminder_sent': 'Cobrança a aprovadores',
  'owner_contact_notify_requested': 'Pedido de contato com proprietário',
  'lifecycle_registration': 'Registro no sistema (ficha)',
  'lifecycle_ficha_atualizada': 'Última atualização da ficha',
  'image_downloaded': 'Download de imagem',
  'images_zip_downloaded': 'Download de imagens (ZIP)',
};

/// Título do evento como o web escreve (`formatPropertyHistoryEventTitle`):
/// mensagem da aprovação diz a fila, download em ZIP diz quantas fotos e
/// código desconhecido vira palavras ("foo_bar" → "Foo Bar").
String propertyHistoryEventTitle(PropertyHistoryEntry entry) {
  final ev = entry.event.trim();
  final meta = entry.metadata;
  if (ev == 'approval_thread_message') {
    final ctx = meta?['approvalContext']?.toString();
    if (ctx == 'publication') return 'Mensagem — publicação no site';
    if (ctx == 'availability') return 'Mensagem — disponibilidade';
    return 'Mensagem (aprovador / responsável)';
  }
  if (ev == 'images_zip_downloaded') {
    final n = _asInt(meta?['count']);
    return n > 0
        ? 'Download de imagens em ZIP ($n)'
        : 'Download de imagens (ZIP)';
  }
  final direct = _kEventTitles[ev] ??
      _kEventTitles[ev.toLowerCase()] ??
      _kEventTitles[ev.replaceAll(RegExp(r'\s+'), '_')];
  if (direct != null) return direct;
  final parts = ev.split('_').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'Evento';
  return parts
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join(' ');
}

/// Uma entrada do "Histórico do imóvel" — paridade com a linha do tempo da
/// ficha web (W:2721-3121), no desenho de trilho da página (ponto + linha).
///
/// Mostra: quando · quem, o título do evento, selo "Assinado"/"Não assinado"
/// da autorização (com "Abrir link de assinatura" para quem pode), a
/// descrição, "Aplicado por … ao aprovar a solicitação" e as notas de
/// regra/processo, o antes → depois de cada campo (`metadata.effectiveChanges`)
/// e, nos registros antigos, a lista dos campos alterados.
///
/// [detailed] = histórico completo (o "Ver histórico completo" do web): mostra
/// o IP, TODAS as alterações e, nas mensagens da aprovação, "Última edição" e
/// o histórico de versões anteriores. Sem ele (as "Últimas atividades"), no
/// máximo 12 alterações e rótulos "Ver …".
///
/// [canOpenSignatureLink]: calcule com [canViewSignatureLink].
class PropertyHistoryEntryTile extends StatelessWidget {
  const PropertyHistoryEntryTile({
    super.key,
    required this.entry,
    this.detailed = false,
    this.canOpenSignatureLink = false,
    this.isLast = false,
    this.tone,
  });

  final PropertyHistoryEntry entry;
  final bool detailed;
  final bool canOpenSignatureLink;

  /// Último item: sem a linha do trilho abaixo do ponto.
  final bool isLast;

  /// Cor do ponto do trilho (token cru). Padrão: ardósia neutra.
  final Color? tone;

  /// Quem vê o link de assinatura da autorização
  /// (`canViewOwnerAuthHistorySignatureLink` do web): gestão
  /// (master/admin/gestor), o responsável principal ou um responsável
  /// adicional.
  static bool canViewSignatureLink({
    required Property property,
    required String? currentUserId,
    required String? userRole,
  }) {
    final me = currentUserId?.trim() ?? '';
    if (me.isEmpty) return false;
    if (PropertyDetailExtrasService.isManagementRole(userRole)) return true;
    if (property.responsibleUserId.trim() == me) return true;
    return (property.responsibles ?? const <PropertyResponsible>[])
        .any((r) => r.id.trim() == me);
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final dot = tone ?? AppColors.text.textLight;
    final meta = entry.metadata ?? const <String, dynamic>{};
    final who = entry.user?.name?.trim() ?? '';
    final when = DateFormat('dd/MM/yyyy · HH:mm').format(
      entry.createdAt.toLocal(),
    );
    final description = entry.description?.trim() ?? '';
    final signature = _signatureStatus(entry);
    final signatureUrl = _nonEmpty(meta['signatureUrl']);
    final showLink = canOpenSignatureLink && signatureUrl != null;
    final changes = _effectiveChanges(meta);
    final legacy = changes.isEmpty ? _legacyFields(meta) : const <String>[];
    final hint = _actorHint(meta);
    final ip = detailed ? _nonEmpty(meta['ipAddress']) : null;
    final isMessage = entry.event == 'approval_thread_message';
    final editedAt = detailed && isMessage
        ? DateTime.tryParse(meta['editedAt']?.toString() ?? '')
        : null;
    final editHistory =
        detailed && isMessage ? _editHistory(meta) : const <_EditSnapshot>[];

    final content = <Widget>[
      Text(
        who.isEmpty ? when : '$when · $who',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: secondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 2),
      Text(
        propertyHistoryEventTitle(entry),
        style: TextStyle(
          color: ThemeHelpers.textColor(context),
          fontSize: detailed ? 14.5 : 14,
          fontWeight: FontWeight.w800,
          height: 1.3,
          letterSpacing: -0.1,
        ),
      ),
      if (signature != null || showLink) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (signature != null) _SignatureBadge(signed: signature),
            if (showLink)
              _LinkAction(
                label: 'Abrir link de assinatura',
                onTap: () => DocumentFileActions.openSignatureLink(
                  context,
                  signatureUrl,
                ),
              ),
          ],
        ),
      ],
      if (description.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            color: detailed ? ThemeHelpers.textColor(context) : secondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
      if (changes.isNotEmpty || legacy.isNotEmpty || hint != null || ip != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _AuditBlock(
            hint: hint,
            ip: ip,
            legacy: legacy,
            changes: changes,
            detailed: detailed,
          ),
        ),
      if (editedAt != null) ...[
        const SizedBox(height: 6),
        Text(
          'Última edição: '
          '${DateFormat('dd/MM/yyyy · HH:mm').format(editedAt.toLocal())}',
          style: TextStyle(
            color: secondary,
            fontSize: 12,
            fontStyle: FontStyle.italic,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
      if (editHistory.isNotEmpty) ...[
        const SizedBox(height: 6),
        _Disclosure(
          title: 'Histórico de versões anteriores (${editHistory.length})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final snap in editHistory.reversed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (snap.at != null)
                        Text(
                          DateFormat('dd/MM/yyyy · HH:mm')
                              .format(snap.at!.toLocal()),
                          style: TextStyle(
                            color: secondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        snap.previousText.isEmpty
                            ? '(vazio)'
                            : snap.previousText,
                        style: TextStyle(
                          color: ThemeHelpers.textColor(context),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ];

    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: 4,
            top: 16,
            bottom: 0,
            child: Container(
              width: 2,
              color: ThemeHelpers.borderColor(context),
            ),
          ),
        Positioned(
          left: 0,
          top: 4,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 22, bottom: isLast ? 0 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
      ],
    );
  }

  // ─── Leitura do metadata (regras do web) ────────────────────────────────

  /// `true` assinado, `false` não assinado, `null` = evento sem selo.
  static bool? _signatureStatus(PropertyHistoryEntry entry) {
    if (entry.event == 'owner_authorization_signed') return true;
    if (entry.event == 'owner_authorization_sent') {
      final raw = entry.metadata?['signatureStatus']?.toString().toLowerCase();
      return raw == 'signed' || raw == 'assinado';
    }
    return null;
  }

  static List<_FieldChange> _effectiveChanges(Map<String, dynamic> meta) {
    List<_FieldChange> read(dynamic raw) {
      if (raw is! List || raw.isEmpty) return const <_FieldChange>[];
      return [
        for (final item in raw)
          if (item is Map)
            _FieldChange(
              field: item['field']?.toString() ?? '',
              label: (item['label']?.toString().trim().isNotEmpty ?? false)
                  ? item['label'].toString().trim()
                  : (item['field']?.toString() ?? ''),
              before: item['before']?.toString() ?? '',
              after: item['after']?.toString() ?? '',
            ),
      ];
    }

    final effective = read(meta['effectiveChanges']);
    if (effective.isNotEmpty) return effective;
    return read(meta['changes']);
  }

  static List<String> _legacyFields(Map<String, dynamic> meta) {
    final legacy = meta['legacyChangedFields'];
    if (legacy is List && legacy.isNotEmpty) {
      return [
        for (final item in legacy)
          if (item is String && item.trim().isNotEmpty)
            item.trim()
          else if (item is Map)
            ((item['label'] ?? item['field'])?.toString().trim() ?? ''),
      ].where((s) => s.isNotEmpty).toList();
    }
    final fields = meta['fields'];
    if (fields is List && fields.isNotEmpty) {
      return [
        for (final f in fields)
          if (f is String && f.trim().isNotEmpty) f.trim(),
      ];
    }
    return const <String>[];
  }

  static String? _actorHint(Map<String, dynamic> meta) {
    if (meta['attribution'] == 'change_request') {
      final appliedBy = meta['appliedByName']?.toString().trim() ?? '';
      return appliedBy.isNotEmpty
          ? 'Aplicado por $appliedBy ao aprovar a solicitação.'
          : 'Aplicado por um aprovador ao aprovar a solicitação.';
    }
    final kind = meta['actorKind'];
    if (kind == 'business_rule') {
      return 'Inclui campos ajustados automaticamente por regras do sistema.';
    }
    if (kind == 'integration') return 'Alteração por processo interno.';
    return null;
  }

  static List<_EditSnapshot> _editHistory(Map<String, dynamic> meta) {
    final raw = meta['editHistory'];
    if (raw is! List) return const <_EditSnapshot>[];
    return [
      for (final item in raw)
        if (item is Map)
          _EditSnapshot(
            at: DateTime.tryParse(item['at']?.toString() ?? ''),
            previousText: item['previousText']?.toString() ?? '',
          ),
    ];
  }

  static String? _nonEmpty(dynamic v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

class _FieldChange {
  const _FieldChange({
    required this.field,
    required this.label,
    required this.before,
    required this.after,
  });

  final String field;
  final String label;
  final String before;
  final String after;
}

class _EditSnapshot {
  const _EditSnapshot({required this.at, required this.previousText});

  final DateTime? at;
  final String previousText;
}

/// Bloco de auditoria: nota de autoria, IP (completo), campos dos registros
/// antigos e o antes → depois de cada campo.
class _AuditBlock extends StatelessWidget {
  const _AuditBlock({
    required this.hint,
    required this.ip,
    required this.legacy,
    required this.changes,
    required this.detailed,
  });

  final String? hint;
  final String? ip;
  final List<String> legacy;
  final List<_FieldChange> changes;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final text = ThemeHelpers.textColor(context);
    final shown = detailed || changes.length <= 12
        ? changes
        : changes.sublist(0, 12);
    final hintText = hint;
    final ipText = ip;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hintText != null)
            Text(
              hintText,
              style: TextStyle(
                color: text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          if (ipText != null) ...[
            if (hintText != null) const SizedBox(height: 4),
            Text(
              'IP: $ipText',
              style: TextStyle(
                color: secondary,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (legacy.isNotEmpty) ...[
            if (hintText != null || ipText != null) const SizedBox(height: 6),
            _Disclosure(
              title: detailed
                  ? 'Campos alterados (${legacy.length})'
                  : 'Ver os ${legacy.length} campos alterados',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    'Registro antigo: os valores anterior e novo não foram '
                    'gravados nesta época.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final label in legacy)
                    _Bullet(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (changes.isNotEmpty) ...[
            if (hintText != null || ipText != null || legacy.isNotEmpty)
              const SizedBox(height: 6),
            _Disclosure(
              title: detailed
                  ? 'Alterações na base (${changes.length})'
                  : 'Ver ${changes.length} '
                      '${changes.length == 1 ? 'alteração' : 'alterações'} '
                      'na base',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  for (final c in shown)
                    _Bullet(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: c.label,
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const TextSpan(text: ': '),
                            TextSpan(
                              text: c.before.isEmpty ? '(vazio)' : c.before,
                              style: TextStyle(color: secondary),
                            ),
                            const TextSpan(text: '  →  '),
                            TextSpan(
                              text: c.after.isEmpty ? '(vazio)' : c.after,
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (shown.length < changes.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 14),
                      child: Text(
                        '…',
                        style: TextStyle(color: secondary, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.textSecondaryColor(context),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Recolhível do histórico ("Ver …"): seta que gira + conteúdo que abre.
class _Disclosure extends StatefulWidget {
  const _Disclosure({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ink = pdkInk(context, PdkTone.blue(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(LucideIcons.chevronRight, size: 16, color: ink),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open ? widget.child : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SignatureBadge extends StatelessWidget {
  const _SignatureBadge({required this.signed});

  final bool signed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = signed ? PdkTone.green(context) : PdkTone.amber(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            signed ? LucideIcons.badgeCheck : LucideIcons.clock,
            size: 12,
            color: pdkInk(context, tone),
          ),
          const SizedBox(width: 4),
          Text(
            signed ? 'Assinado' : 'Não assinado',
            style: TextStyle(
              color: pdkInk(context, tone),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkAction extends StatelessWidget {
  const _LinkAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = pdkInk(context, PdkTone.blue(context));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.externalLink, size: 13, color: ink),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                    decorationColor: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
