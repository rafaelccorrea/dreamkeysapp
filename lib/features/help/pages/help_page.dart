import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/help_content.dart';

/// Tela **Central de Ajuda** — porte do `FaqPage.tsx` web: busca, acesso
/// rápido, guias passo a passo e perguntas frequentes por categoria
/// expansível. Conteúdo estático (sem endpoint), disponível para qualquer
/// usuário autenticado. No rodapé, o caminho para abrir um chamado.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _searchFocused = false;
  String _search = '';

  String _activeCategoryId = faqCategories.first.id;
  String? _openFaqKey;
  String? _openGuideId = helpGuides.first.id;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  bool get _isSearching => helpNormalize(_search.trim()).isNotEmpty;

  /// Durante a busca, todas as categorias com itens correspondentes; sem
  /// busca, apenas a categoria selecionada (paridade com o web).
  List<FaqCategory> get _visibleCategories {
    if (!_isSearching) {
      return faqCategories.where((c) => c.id == _activeCategoryId).toList();
    }
    final term = helpNormalize(_search.trim());
    return faqCategories
        .map(
          (category) => FaqCategory(
            id: category.id,
            title: category.title,
            emoji: category.emoji,
            items: category.items
                .where(
                  (item) =>
                      helpNormalize(item.question).contains(term) ||
                      helpNormalize(item.answer).contains(term),
                )
                .toList(),
          ),
        )
        .where((category) => category.items.isNotEmpty)
        .toList();
  }

  void _go(String route) {
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _visibleCategories;

    return AppScaffold(
      title: 'Central de Ajuda',
      showBottomNavigation: false,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(context),
            const SizedBox(height: 12),
            _buildSearchField(context),
            if (!_isSearching) ...[
              const SizedBox(height: 22),
              _sectionLabel(context, LucideIcons.rocket, 'ACESSO RÁPIDO'),
              const SizedBox(height: 12),
              _buildQuickGrid(context),
              const SizedBox(height: 22),
              _sectionLabel(context, LucideIcons.listChecks, 'PASSO A PASSO'),
              const SizedBox(height: 12),
              _buildGuides(context),
            ],
            const SizedBox(height: 22),
            _sectionLabel(
              context,
              LucideIcons.circleHelp,
              'PERGUNTAS FREQUENTES',
            ),
            const SizedBox(height: 12),
            if (!_isSearching) ...[
              _buildCategoryChips(context),
              const SizedBox(height: 14),
            ],
            if (categories.isEmpty)
              _buildEmptySearch(context)
            else
              for (final category in categories)
                _buildCategoryBlock(context, category),
            const SizedBox(height: 10),
            _buildSupportCta(context),
          ],
        ),
      ),
    );
  }

  // ─── Hero flush ──────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'SUPORTE · CENTRAL DE AJUDA',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Como podemos ajudar?',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.6,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Encontre respostas rápidas para as dúvidas mais comuns e vá direto para a tela que você precisa.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ─── Busca flush ─────────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;

    return Focus(
      onFocusChange: (f) => setState(() => _searchFocused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 50,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: showAccent
                ? _accent.withValues(alpha: isDark ? 0.5 : 0.42)
                : borderColor,
            width: showAccent ? 1.4 : 1,
          ),
          boxShadow: showAccent
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              LucideIcons.search,
              size: 18,
              color: showAccent ? _accent : secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                cursorColor: _accent,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar dúvida (ex.: senha, lead, ficha)…',
                  hintStyle: TextStyle(
                    color: secondary.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (v) => setState(() {
                  _search = v;
                  _openFaqKey = null;
                }),
              ),
            ),
            if (hasText)
              InkResponse(
                radius: 18,
                onTap: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(LucideIcons.x, size: 15, color: secondary),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ─── Seções ──────────────────────────────────────────────────────────────

  Widget _sectionLabel(BuildContext context, IconData icon, String label) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 13, color: secondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 10.5,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(
                context,
              ).withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Acesso rápido ───────────────────────────────────────────────────────

  Widget _buildQuickGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        for (final link in helpQuickLinks)
          _QuickLinkCard(link: link, onTap: () => _go(link.route)),
      ],
    );
  }

  // ─── Guias passo a passo ─────────────────────────────────────────────────

  Widget _buildGuides(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final guide in helpGuides)
          _GuideCard(
            guide: guide,
            open: _openGuideId == guide.id,
            accent: _accent,
            onToggle: () => setState(() {
              _openGuideId = _openGuideId == guide.id ? null : guide.id;
            }),
            onCta: () => _go(guide.ctaRoute),
          ),
      ],
    );
  }

  // ─── FAQ ─────────────────────────────────────────────────────────────────

  Widget _buildCategoryChips(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final category in faqCategories) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => setState(() {
                  _activeCategoryId = category.id;
                  _openFaqKey = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: category.id == _activeCategoryId
                        ? _accent.withValues(alpha: isDark ? 0.16 : 0.1)
                        : Colors.transparent,
                    border: Border.all(
                      color: category.id == _activeCategoryId
                          ? _accent.withValues(alpha: 0.45)
                          : ThemeHelpers.borderColor(context),
                      width: category.id == _activeCategoryId ? 1.4 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category.emoji,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        category.title,
                        style: TextStyle(
                          color: category.id == _activeCategoryId
                              ? _accent
                              : ThemeHelpers.textColor(context),
                          fontWeight: category.id == _activeCategoryId
                              ? FontWeight.w800
                              : FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryBlock(BuildContext context, FaqCategory category) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isSearching) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(
              children: [
                Text(category.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 7),
                Text(
                  category.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
        for (var i = 0; i < category.items.length; i++)
          _FaqAccordion(
            item: category.items[i],
            open: _openFaqKey == '${category.id}-$i',
            accent: _accent,
            onToggle: () => setState(() {
              final key = '${category.id}-$i';
              _openFaqKey = _openFaqKey == key ? null : key;
            }),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildEmptySearch(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _accent.withValues(alpha: 0.18),
                  _accent.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: _accent.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.searchX, color: _accent, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'Nenhuma dúvida encontrada',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nada corresponde a "${_search.trim()}". Tente outra palavra-chave ou abra um chamado no Suporte.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── CTA de suporte ──────────────────────────────────────────────────────

  Widget _buildSupportCta(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: _accent.withValues(alpha: isDark ? 0.28 : 0.18),
        ),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: _accent.withValues(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Icon(LucideIcons.lifeBuoy, color: _accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Não encontrou o que procurava?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Abra um chamado e nosso time de suporte vai te ajudar.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => _go(kHelpTicketsRoute),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: const Icon(LucideIcons.messageCircle, size: 17),
              label: const Text(
                'Falar com o Suporte',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card de acesso rápido ────────────────────────────────────────────────────

class _QuickLinkCard extends StatelessWidget {
  final HelpQuickLink link;
  final VoidCallback onTap;

  const _QuickLinkCard({required this.link, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Icon(link.icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      link.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Card de guia passo a passo ───────────────────────────────────────────────

class _GuideCard extends StatelessWidget {
  final HelpGuide guide;
  final bool open;
  final Color accent;
  final VoidCallback onToggle;
  final VoidCallback onCta;

  const _GuideCard({
    required this.guide,
    required this.open,
    required this.accent,
    required this.onToggle,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: open
              ? accent.withValues(alpha: isDark ? 0.4 : 0.3)
              : ThemeHelpers.borderLightColor(context),
          width: open ? 1.3 : 1,
        ),
        boxShadow: open ? ThemeHelpers.cardShadow(context) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                      ),
                      child: Icon(guide.icon, color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            guide.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.2,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            guide.summary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 18,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState: open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < guide.steps.length; i++)
                    _GuideStep(
                      index: i + 1,
                      text: guide.steps[i],
                      accent: accent,
                      isLast: i == guide.steps.length - 1,
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onCta,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                    ),
                    icon: const Icon(LucideIcons.arrowUpRight, size: 15),
                    label: Text(
                      guide.ctaLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final int index;
  final String text;
  final Color accent;
  final bool isLast;

  const _GuideStep({
    required this.index,
    required this.text,
    required this.accent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12, top: 3),
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Acordeão de pergunta frequente ───────────────────────────────────────────

class _FaqAccordion extends StatelessWidget {
  final FaqItem item;
  final bool open;
  final Color accent;
  final VoidCallback onToggle;

  const _FaqAccordion({
    required this.item,
    required this.open,
    required this.accent,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: open
              ? accent.withValues(alpha: isDark ? 0.4 : 0.3)
              : ThemeHelpers.borderLightColor(context),
          width: open ? 1.3 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.question,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                          height: 1.3,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 17,
                        color: open ? accent : secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState: open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item.answer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ).animate().fadeIn(duration: 180.ms),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
