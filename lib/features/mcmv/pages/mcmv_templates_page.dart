import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/mcmv_models.dart';
import '../services/mcmv_service.dart';
import '../widgets/mcmv_common.dart';

/// Tela **Templates MCMV** — modelos de mensagem da empresa + padrões do
/// sistema, com chips por tipo (WhatsApp/Email/SMS) e ações **no próprio
/// item**: copiar o conteúdo e compartilhar direto no WhatsApp.
class McmvTemplatesPage extends StatefulWidget {
  const McmvTemplatesPage({super.key});

  @override
  State<McmvTemplatesPage> createState() => _McmvTemplatesPageState();
}

class _McmvTemplatesPageState extends State<McmvTemplatesPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  List<McmvTemplate> _items = const [];
  bool _loading = true;
  String? _error;

  McmvTemplateType? _typeFilter;

  bool get _canView =>
      mcmvModuleEnabled() &&
      ModuleAccessService.instance.hasPermission(McmvPermissions.templateView);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      if (refresh) _error = null;
    });
    final res = await McmvService.instance.listTemplates();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar templates';
      }
    });
  }

  List<McmvTemplate> get _visibleItems {
    if (_typeFilter == null) return _items;
    return _items.where((t) => t.type == _typeFilter).toList();
  }

  Color _typeColor(BuildContext context, McmvTemplateType type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (type) {
      case McmvTemplateType.whatsapp:
        return kMcmvWhatsappGreen;
      case McmvTemplateType.email:
        return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
      case McmvTemplateType.sms:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case McmvTemplateType.unknown:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  IconData _typeIcon(McmvTemplateType type) {
    switch (type) {
      case McmvTemplateType.whatsapp:
        return LucideIcons.messageCircle;
      case McmvTemplateType.email:
        return LucideIcons.mail;
      case McmvTemplateType.sms:
        return LucideIcons.messageSquare;
      case McmvTemplateType.unknown:
        return LucideIcons.fileText;
    }
  }

  Future<void> _copy(McmvTemplate template) async {
    await Clipboard.setData(ClipboardData(text: template.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Template "${template.name}" copiado!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareWhatsapp(McmvTemplate template) async {
    final text = Uri.encodeComponent(template.content);
    await mcmvLaunchUri(context, 'https://wa.me/?text=$text');
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Templates MCMV',
        showBottomNavigation: false,
        body: McmvDeniedView(
          message: 'Você não tem acesso aos templates do MCMV.',
          permission: McmvPermissions.templateView,
        ),
      );
    }
    return AppScaffold(
      title: 'Templates MCMV',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: mcmvAccentColor(context),
        onRefresh: () => _load(refresh: true),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kPagePadTop, _kPagePadH, 0),
                    child: _buildHero(context),
                  ),
                  const SizedBox(height: _kSectionGap + 4),
                  _buildTypeChips(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(_kPagePadH,
                        _kSectionGap + 4, _kPagePadH, _kPagePadBottom),
                    child: _buildPanel(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = mcmvAccentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final total = _items.length;
    final custom = _items.where((t) => !t.isSystemDefault).length;
    final system = total - custom;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'TEMPLATES MCMV',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  total == 1 ? 'modelo' : 'modelos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            total == 0
                ? 'Modelos de mensagem para o atendimento dos leads MCMV.'
                : '$custom da empresa · $system padrão do sistema',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChips(BuildContext context) {
    final options = <(McmvTemplateType?, String)>[
      (null, 'Todos'),
      (McmvTemplateType.whatsapp, 'WhatsApp'),
      (McmvTemplateType.email, 'Email'),
      (McmvTemplateType.sms, 'SMS'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH),
      child: Row(
        children: [
          for (final (type, label) in options) ...[
            McmvFilterChip(
              label: label,
              icon: type == null ? null : _typeIcon(type),
              selected: _typeFilter == type,
              accent: type == null
                  ? mcmvAccentColor(context)
                  : _typeColor(context, type),
              count: type == null
                  ? null
                  : _items.where((t) => t.type == type).length,
              onTap: () => setState(() => _typeFilter = type),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final tone = _typeFilter == null
        ? mcmvAccentColor(context)
        : _typeColor(context, _typeFilter!);
    final visible = _visibleItems;

    Widget child;
    if (_loading && _items.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _items.isEmpty) {
      child = McmvErrorState(
        message: _error!,
        onRetry: () => _load(refresh: true),
      );
    } else if (visible.isEmpty) {
      child = McmvEmptyState(
        icon: LucideIcons.fileText,
        title: _typeFilter == null
            ? 'Nenhum template'
            : 'Nenhum template de ${_typeFilter!.label}',
        body: 'Os modelos de mensagem da empresa aparecem aqui.',
        tone: tone,
      );
    } else {
      var animIndex = 0;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final template in visible)
            _TemplateItem(
              template: template,
              tone: _typeColor(context, template.type),
              icon: _typeIcon(template.type),
              onCopy: () => _copy(template),
              onWhatsapp: () => _shareWhatsapp(template),
            ).animate(key: ValueKey('tpl-${template.id}')).fadeIn(
                  delay:
                      Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                  duration: 220.ms,
                ),
        ],
      );
    }

    final key = ValueKey('panel-${_typeFilter?.name ?? 'all'}');
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        McmvPanelHeader(
          icon: _typeFilter == null
              ? LucideIcons.fileText
              : _typeIcon(_typeFilter!),
          eyebrow: _typeFilter == null
              ? 'TODOS OS MODELOS'
              : _typeFilter!.label.toUpperCase(),
          title: _typeFilter == null
              ? 'Modelos de mensagem'
              : 'Modelos de ${_typeFilter!.label}',
          hint: 'Toque em copiar ou envie direto pelo WhatsApp — as '
              'variáveis {{...}} são preenchidas na conversa.',
          tone: tone,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: key).fadeIn(duration: 240.ms);
  }

  /// Skeleton fiel ao item de template (cabeçalho + corpo + variáveis + ações).
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  SkeletonBox(width: 40, height: 40, borderRadius: 12),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonText(width: double.infinity,
                      height: 16)),
                  SizedBox(width: 10),
                  SkeletonText(width: 70, height: 18, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 12),
              const SkeletonBox(
                  width: double.infinity, height: 74, borderRadius: 12),
              const SizedBox(height: 10),
              Row(
                children: const [
                  SkeletonText(width: 84, height: 20, borderRadius: 999),
                  SizedBox(width: 6),
                  SkeletonText(width: 96, height: 20, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 12),
              const SkeletonBox(
                  width: double.infinity, height: 36, borderRadius: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Item de template ────────────────────────────────────────────────────────

class _TemplateItem extends StatelessWidget {
  final McmvTemplate template;
  final Color tone;
  final IconData icon;
  final VoidCallback onCopy;
  final VoidCallback onWhatsapp;

  const _TemplateItem({
    required this.template,
    required this.tone,
    required this.icon,
    required this.onCopy,
    required this.onWhatsapp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final border = ThemeHelpers.borderLightColor(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(icon, color: tone, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name.trim().isEmpty
                          ? 'Template'
                          : template.name.trim(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((template.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        template.description!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: neutral,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  McmvStatusPill(label: template.type.label, color: tone),
                  if (template.isSystemDefault) ...[
                    const SizedBox(height: 4),
                    McmvStatusPill(
                      label: 'Padrão',
                      color: neutral,
                      icon: LucideIcons.shield,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Conteúdo do modelo em bloco tonal (prévia legível, sem card).
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: fieldFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Text(
              template.content,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context).withValues(alpha: 0.9),
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (template.variables.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final variable in template.variables)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: purple.withValues(alpha: isDark ? 0.14 : 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border:
                          Border.all(color: purple.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '{{$variable}}',
                      style: TextStyle(
                        color: purple,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Ações no próprio item: copiar / enviar pelo WhatsApp.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(LucideIcons.copy, size: 15),
                  label: const Text('Copiar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeHelpers.textColor(context),
                    side: BorderSide(color: ThemeHelpers.borderColor(context)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onWhatsapp,
                  icon: const Icon(LucideIcons.messageCircle, size: 15),
                  label: const Text('WhatsApp',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                    backgroundColor: kMcmvWhatsappGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
