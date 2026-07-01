import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/shell_visual_tokens.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../models/property_local_draft.dart';
import '../models/property_wizard_pop_result.dart';
import '../services/property_local_draft_storage.dart';

/// Tela de **Rascunhos locais** de cadastro de imóvel.
///
/// Identidade visual alinhada ao restante do app (mesmos tokens da Fila de
/// Aprovação): gradiente do shell + ambient orbes, hero com ícone gradiente
/// accent→roxo, KPI strip horizontal slim e cards "feed item" fluidos sem
/// painel pai.
class PropertyDraftsListPage extends StatefulWidget {
  const PropertyDraftsListPage({super.key});

  @override
  State<PropertyDraftsListPage> createState() => _PropertyDraftsListPageState();
}

class _PropertyDraftsListPageState extends State<PropertyDraftsListPage> {
  static const double _kSectionGap = 11;
  static const double _kPagePadH = 20;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const int _kWizardTotalSteps = 7;

  final _storage = PropertyLocalDraftStorage.instance;
  List<PropertyLocalDraft> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final list = await _storage.loadAllForCurrentCompany();
    if (mounted) {
      setState(() {
        _drafts = list;
        _loading = false;
      });
    }
  }

  Future<void> _confirmDelete(PropertyLocalDraft draft) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir rascunho'),
        content: Text(
          'Remover «${draft.displayTitle}» deste dispositivo? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: danger),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _storage.delete(draft.id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: danger,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            content: const Row(
              children: [
                Icon(LucideIcons.trash2, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Rascunho removido.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _openDraft(PropertyLocalDraft draft) async {
    final result = await Navigator.of(context).pushNamed(
      AppRoutes.propertyCreate,
      arguments: <String, dynamic>{'localDraftId': draft.id},
    );
    if (mounted && (result == true || result is PropertyWizardPopResult)) {
      await _refresh();
    }
  }

  Future<void> _goCreateNew() async {
    final result = await Navigator.of(
      context,
    ).pushNamed(AppRoutes.propertyCreate);
    if (mounted && (result == true || result is PropertyWizardPopResult)) {
      await _refresh();
    }
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  List<Widget> _ambientHighlights(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final cool = isDark ? const Color(0xFF4F46E5) : const Color(0xFF818CF8);
    return [
      Positioned(
        top: -72,
        right: -48,
        child: IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cool.withValues(alpha: isDark ? 0.14 : 0.065),
                  cool.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 120,
        left: -80,
        child: IgnorePointer(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.16 : 0.07),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // ─── Resumos para o KPI strip ─────────────────────────────────────────

  int get _totalDrafts => _drafts.length;

  int get _draftsWithPhotos => _drafts
      .where((d) => d.imagePaths.any((p) => File(p).existsSync()))
      .length;

  int get _photoSum => _drafts.fold<int>(
    0,
    (acc, d) => acc + d.imagePaths.where((p) => File(p).existsSync()).length,
  );

  String get _lastUpdatedHint {
    if (_drafts.isEmpty) return '—';
    final newest = _drafts.first.updatedAt;
    return _relativeShort(newest);
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Rascunhos',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(LucideIcons.refreshCw, size: 20),
        ),
      ],
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ..._ambientHighlights(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      _kPagePadTop,
                      _kPagePadH,
                      _kPagePadBottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGreeting(context),
                        const SizedBox(height: _kSectionGap + 1),
                        _buildKpiStrip(context),
                        const SizedBox(height: _kSectionGap + 1),
                        _loading
                            ? _buildSkeleton()
                            : (_drafts.isEmpty
                                  ? _buildEmpty(context)
                                  : _buildList(context)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Greeting ─────────────────────────────────────────────────────────

  Widget _buildGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final total = _totalDrafts;

    final headline = total == 0
        ? 'Nenhum rascunho por aqui'
        : (total == 1
              ? '1 rascunho guardado neste aparelho'
              : '$total rascunhos guardados neste aparelho');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF7C3AED)],
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? accent.withValues(alpha: 0.35)
                      : accent.withValues(alpha: 0.22),
                  blurRadius: isDark ? 14 : 11,
                  offset: Offset(0, isDark ? 8 : 4),
                  spreadRadius: isDark ? 0 : -1,
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.bookmark,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RASCUNHOS LOCAIS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  headline,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    height: 1.05,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  total == 0
                      ? 'Capture imóveis offline e finalize o cadastro depois.'
                      : 'Cópias completas com texto, opções e fotos — só aqui no celular.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── KPI strip ────────────────────────────────────────────────────────

  Widget _buildKpiStrip(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final ok = isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final purple = isDark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;

    final items = <_KpiItem>[
      _KpiItem(label: 'Rascunhos', value: '$_totalDrafts', color: accent),
      _KpiItem(label: 'Com fotos', value: '$_draftsWithPhotos', color: ok),
      _KpiItem(label: 'Total fotos', value: '$_photoSum', color: purple),
      _KpiItem(
        label: 'Última edição',
        value: _lastUpdatedHint,
        color: const Color(0xFF7C3AED),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: ShellVisualTokens.dashboardGlassFill(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ShellVisualTokens.dashboardGlassBorder(context),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _KpiTile(item: items[i]),
                if (i < items.length - 1)
                  Container(
                    width: 1,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: ThemeHelpers.borderColor(
                      context,
                    ).withValues(alpha: 0.4),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Lista ────────────────────────────────────────────────────────────

  Widget _buildList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _drafts.length; i++) ...[
          _DraftCard(
                draft: _drafts[i],
                accent: _accentColor(context),
                existingPhotoCount: _drafts[i].imagePaths
                    .where((p) => File(p).existsSync())
                    .length,
                wizardTotalSteps: _kWizardTotalSteps,
                onOpen: () => _openDraft(_drafts[i]),
                onDelete: () => _confirmDelete(_drafts[i]),
              )
              .animate(key: ValueKey('draft-${_drafts[i].id}'))
              .fadeIn(
                delay: Duration(milliseconds: 50 * i),
                duration: 240.ms,
              )
              .slideY(
                begin: 0.05,
                end: 0,
                delay: Duration(milliseconds: 50 * i),
                duration: 260.ms,
                curve: Curves.easeOutCubic,
              ),
          if (i < _drafts.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: i < 2 ? 12 : 0),
          child: Container(
            height: 156,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.025),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Empty state polido ───────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final purple = isDark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child:
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accent.withValues(alpha: isDark ? 0.18 : 0.10),
                            accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            ThemeHelpers.cardBackgroundColor(context),
                            ThemeHelpers.cardBackgroundColor(context),
                          ],
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.32),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.22),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: ShaderMask(
                        shaderCallback: (rect) => LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [accent, purple],
                        ).createShader(rect),
                        child: const Icon(
                          LucideIcons.bookmarkPlus,
                          size: 42,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ).animate().scale(
                  duration: 360.ms,
                  curve: Curves.easeOutBack,
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                ),
          ),
          const SizedBox(height: 22),
          Text(
            'Capture sem perder o impulso',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ).animate().fadeIn(delay: 120.ms, duration: 260.ms),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Estiver na frente do imóvel sem internet, no meio do atendimento ou pegando dados rápidos? Salve como rascunho e termine quando puder — fotos, texto e opções ficam aqui no aparelho.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.5,
              ),
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 260.ms),
          const SizedBox(height: 24),
          _EmptyStateBenefits(accent: accent),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: ThemeHelpers.borderColor(context),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      foregroundColor: ThemeHelpers.textColor(context),
                    ),
                    icon: const Icon(LucideIcons.arrowLeft, size: 16),
                    label: const Text('Voltar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _goCreateNew,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: const Text('Criar imóvel'),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 280.ms, duration: 260.ms),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  static String _relativeShort(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('dd/MM', 'pt_BR').format(when);
  }
}

// ─── Subwidgets ────────────────────────────────────────────────────────

class _KpiItem {
  final String label;
  final String value;
  final Color color;

  _KpiItem({required this.label, required this.value, required this.color});
}

class _KpiTile extends StatelessWidget {
  final _KpiItem item;
  const _KpiTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 9),
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.6,
                  height: 1.05,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            item.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateBenefits extends StatelessWidget {
  final Color accent;
  const _EmptyStateBenefits({required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final benefits = const [
      ('Funciona offline', LucideIcons.wifiOff),
      ('Auto-save por etapa', LucideIcons.save),
      ('Fotos em cópia local', LucideIcons.image),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final b in benefits)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ShellVisualTokens.dashboardGlassFill(context),
                border: Border.all(
                  color: ShellVisualTokens.dashboardGlassBorder(context),
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(b.$2, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    b.$1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(
              delay: Duration(milliseconds: 200 + benefits.indexOf(b) * 80),
              duration: 260.ms,
            ),
        ],
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.accent,
    required this.existingPhotoCount,
    required this.wizardTotalSteps,
    required this.onOpen,
    required this.onDelete,
  });

  final PropertyLocalDraft draft;
  final Color accent;
  final int existingPhotoCount;
  final int wizardTotalSteps;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  String? _firstThumb() {
    for (final p in draft.imagePaths) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  String _typeLabel(String value) {
    switch (value) {
      case 'house':
        return 'Casa';
      case 'apartment':
        return 'Apartamento';
      case 'commercial':
        return 'Comercial';
      case 'land':
        return 'Terreno';
      case 'rural':
        return 'Rural';
      default:
        return '';
    }
  }

  String _relative(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    if (diff.inDays < 7) return 'há ${diff.inDays} d';
    return DateFormat("d MMM 'às' HH:mm", 'pt_BR').format(when);
  }

  String? _location() {
    final neighborhood = draft.formJson['neighborhood']?.toString().trim();
    final city = draft.formJson['city']?.toString().trim();
    final pieces = <String>[];
    if (neighborhood != null && neighborhood.isNotEmpty) {
      pieces.add(neighborhood);
    }
    if (city != null && city.isNotEmpty) pieces.add(city);
    return pieces.isEmpty ? null : pieces.join(' · ');
  }

  String? _priceLabel() {
    final f = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 0,
    );
    final sale = (draft.formJson['salePrice'] is num)
        ? (draft.formJson['salePrice'] as num).toDouble()
        : double.tryParse('${draft.formJson['salePrice']}');
    final rent = (draft.formJson['rentPrice'] is num)
        ? (draft.formJson['rentPrice'] as num).toDouble()
        : double.tryParse('${draft.formJson['rentPrice']}');
    final parts = <String>[];
    if (sale != null && sale > 0) parts.add('Venda ${f.format(sale)}');
    if (rent != null && rent > 0) parts.add('Aluguel ${f.format(rent)}/mês');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  bool get _isRecent => DateTime.now().difference(draft.updatedAt).inHours < 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    final step = (draft.wizardStep + 1).clamp(1, wizardTotalSteps);
    final progress = step / wizardTotalSteps;
    final type = draft.formJson['type']?.toString() ?? '';
    final typeLabel = _typeLabel(type);
    final location = _location();
    final price = _priceLabel();
    final thumb = _firstThumb();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.05),
          child: Container(
            decoration: _feedDecoration(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildThumbnail(context, thumb),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'RASCUNHO',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: neutral,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                ),
                                if (_isRecent) _RecentBadge(accent: accent),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              draft.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.18,
                                letterSpacing: -0.2,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                            if (location != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    LucideIcons.mapPin,
                                    size: 13,
                                    color: neutral,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      location,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: neutral,
                                            fontWeight: FontWeight.w600,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (price != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                price,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ProgressRow(
                    step: step,
                    total: wizardTotalSteps,
                    progress: progress,
                    accent: accent,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (typeLabel.isNotEmpty)
                        _MetaPill(icon: LucideIcons.tag, label: typeLabel),
                      _MetaPill(
                        icon: LucideIcons.image,
                        label: existingPhotoCount == 1
                            ? '1 foto'
                            : '$existingPhotoCount fotos',
                      ),
                      _MetaPill(
                        icon: LucideIcons.clock,
                        label: _relative(draft.updatedAt.toLocal()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _DangerIconButton(onTap: onDelete, color: danger),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: onOpen,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          textStyle: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ),
                        ),
                        icon: const Icon(LucideIcons.play, size: 16),
                        label: const Text('Continuar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _feedDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: ThemeHelpers.cardBackgroundColor(context),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.32),
      ),
      boxShadow: isDark
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
                spreadRadius: -4,
              ),
            ]
          : [
              BoxShadow(
                color: const Color(0xFF1A2340).withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
                spreadRadius: -6,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 3),
                spreadRadius: -3,
              ),
            ],
    );
  }

  Widget _buildThumbnail(BuildContext context, String? thumbPath) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 84,
            height: 84,
            color: ThemeHelpers.borderLightColor(
              context,
            ).withValues(alpha: 0.5),
            child: thumbPath != null
                ? Image.file(
                    File(thumbPath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Center(
                      child: Icon(
                        LucideIcons.imageOff,
                        color: neutral,
                        size: 24,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(LucideIcons.fileEdit, color: neutral, size: 28),
                  ),
          ),
        ),
        if (existingPhotoCount > 1)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accent.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 8,
                    spreadRadius: -2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '+${existingPhotoCount - 1}',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        // Indicador suave no canto se NÃO há fotos
        if (existingPhotoCount == 0 && !isDark)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                shape: BoxShape.circle,
                border: Border.all(color: neutral.withValues(alpha: 0.4)),
              ),
              child: Icon(LucideIcons.imageOff, size: 10, color: neutral),
            ),
          ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final int step;
  final int total;
  final double progress;
  final Color accent;

  const _ProgressRow({
    required this.step,
    required this.total,
    required this.progress,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.layers, size: 13, color: accent),
            const SizedBox(width: 6),
            Text(
              'Etapa $step de $total',
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.55)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.32),
                      blurRadius: 6,
                      spreadRadius: -1,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.045)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: neutral),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentBadge extends StatelessWidget {
  final Color accent;
  const _RecentBadge({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 1,
                end: 1.5,
                duration: 700.ms,
                curve: Curves.easeInOut,
              )
              .fadeIn(begin: 0.55, duration: 700.ms),
          const SizedBox(width: 5),
          Text(
            'Recente',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;
  const _DangerIconButton({required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withValues(alpha: 0.18),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.24)),
          ),
          alignment: Alignment.center,
          child: Icon(LucideIcons.trash2, size: 16, color: color),
        ),
      ),
    );
  }
}
