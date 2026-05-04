import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/app_routes.dart';
import '../models/property_wizard_pop_result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../models/property_local_draft.dart';
import '../services/property_local_draft_storage.dart';

/// Lista de rascunhos locais de cadastro de imóvel — paridade de estilo com o wizard.
class PropertyDraftsListPage extends StatefulWidget {
  const PropertyDraftsListPage({super.key});

  @override
  State<PropertyDraftsListPage> createState() => _PropertyDraftsListPageState();
}

class _PropertyDraftsListPageState extends State<PropertyDraftsListPage> {
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
            style: TextButton.styleFrom(foregroundColor: AppColors.status.error),
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
          const SnackBar(content: Text('Rascunho removido.')),
        );
      }
    }
  }

  Future<void> _openDraft(PropertyLocalDraft draft) async {
    final result = await Navigator.of(context).pushNamed(
      AppRoutes.propertyCreate,
      arguments: <String, dynamic>{'localDraftId': draft.id},
    );
    if (mounted &&
        (result == true || result is PropertyWizardPopResult)) {
      await _refresh();
    }
  }

  LinearGradient _backdropGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.32, 0.62, 1.0],
        colors: [
          Color(0xFF17172A),
          Color(0xFF1E1E38),
          Color(0xFF25244A),
          Color(0xFF151520),
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(Colors.white, const Color(0xFFF0F4FF), 0.6)!,
        const Color(0xFFEEF2FF),
      ],
    );
  }

  Color _brandAccent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF8B5CF6)
          : const Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final brand = _brandAccent(context);

    return AppScaffold(
      title: 'Rascunhos locais',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Atualizar lista',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _refresh,
        ),
      ],
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: _backdropGradient(context)),
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: brand),
              )
            : RefreshIndicator(
                color: brand,
                onRefresh: _refresh,
                edgeOffset: 80,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: _HeroIntroCard(theme: theme, brand: brand, isDark: isDark),
                      ),
                    ),
                    if (_drafts.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyDrafts(theme: theme, brand: brand, isDark: isDark),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        sliver: SliverList.builder(
                          itemCount: _drafts.length,
                          itemBuilder: (context, i) {
                            final d = _drafts[i];
                            final existingPhotos = d.imagePaths
                                .where((p) => File(p).existsSync())
                                .length;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _DraftCard(
                                draft: d,
                                brand: brand,
                                isDark: isDark,
                                existingPhotoCount: existingPhotos,
                                onOpen: () => _openDraft(d),
                                onDelete: () => _confirmDelete(d),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _HeroIntroCard extends StatelessWidget {
  const _HeroIntroCard({
    required this.theme,
    required this.brand,
    required this.isDark,
  });

  final ThemeData theme;
  final Color brand;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: isDark
              ? [
                  brand.withValues(alpha: 0.22),
                  const Color(0xFF2A2A48).withValues(alpha: 0.9),
                ]
              : [
                  brand.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.92),
                ],
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : brand.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: brand.withValues(alpha: isDark ? 0.12 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: brand.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.auto_stories_rounded, color: brand, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue de onde parou',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Rascunhos ficam só neste aparelho. '
                  'Incluem texto, opções e cópias das fotos que você adicionou.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.4,
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDrafts extends StatelessWidget {
  const _EmptyDrafts({
    required this.theme,
    required this.brand,
    required this.isDark,
  });

  final ThemeData theme;
  final Color brand;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: brand.withValues(alpha: isDark ? 0.15 : 0.1),
              border: Border.all(color: brand.withValues(alpha: 0.25)),
            ),
            child: Icon(
              Icons.draw_rounded,
              size: 56,
              color: brand,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Nenhum rascunho salvo',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'No cadastro de imóvel, use «Rascunho local» e dê um nome '
            'para encontrar tudo aqui depois.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Voltar aos imóveis'),
          ),
        ],
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.brand,
    required this.isDark,
    required this.existingPhotoCount,
    required this.onOpen,
    required this.onDelete,
  });

  final PropertyLocalDraft draft;
  final Color brand;
  final bool isDark;
  final int existingPhotoCount;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = (draft.wizardStep + 1).clamp(1, 7);
    final rel = DateFormat(
      "d MMM · HH:mm",
      'pt_BR',
    ).format(draft.updatedAt.toLocal());
    final type = draft.formJson['type']?.toString() ?? '';
    final typeLabel = _typeLabel(type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: isDark
                ? Colors.white.withValues(alpha: 0.055)
                : Colors.white.withValues(alpha: 0.88),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : brand.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 52,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [brand, brand.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipPill(
                            icon: Icons.layers_rounded,
                            label: 'Etapa $step/7',
                            brand: brand,
                            isDark: isDark,
                          ),
                          _ChipPill(
                            icon: Icons.photo_library_outlined,
                            label: '$existingPhotoCount fotos',
                            brand: brand,
                            isDark: isDark,
                          ),
                          if (typeLabel.isNotEmpty)
                            _ChipPill(
                              icon: Icons.category_outlined,
                              label: typeLabel,
                              brand: brand,
                              isDark: isDark,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Atualizado $rel',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Abrir',
                      onPressed: onOpen,
                      style: IconButton.styleFrom(
                        backgroundColor: brand.withValues(alpha: 0.18),
                        foregroundColor: brand,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    IconButton(
                      tooltip: 'Excluir',
                      onPressed: onDelete,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.status.error.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _typeLabel(String value) {
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
}

class _ChipPill extends StatelessWidget {
  const _ChipPill({
    required this.icon,
    required this.label,
    required this.brand,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final Color brand;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: brand.withValues(alpha: isDark ? 0.12 : 0.1),
        border: Border.all(color: brand.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: brand),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                ),
          ),
        ],
      ),
    );
  }
}
