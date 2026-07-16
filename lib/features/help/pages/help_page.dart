import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/help_content.dart';

// ─── Paleta tonal da Central de Ajuda ────────────────────────────────────────
// Cor por significado (variedade controlada, sem arco-íris gratuito):
// sky = primeiros passos · violet = CRM · vermelho da marca = imóveis ·
// amber = agenda · rose = documentos/assinatura · emerald = WhatsApp ·
// slate = relatórios · indigo = conta/segurança (mesmo tom do Perfil).
Color _toneBrand(bool d) =>
    d ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
Color _toneSky(bool d) => d ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
Color _toneViolet(bool d) =>
    d ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
Color _toneEmerald(bool d) =>
    d ? const Color(0xFF34D399) : const Color(0xFF059669);
Color _toneRose(bool d) =>
    d ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
Color _toneAmber(bool d) =>
    d ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
Color _toneSlate(bool d) =>
    d ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
Color _toneIndigo(bool d) =>
    d ? const Color(0xFF818CF8) : const Color(0xFF6366F1);

/// Identidade visual de uma categoria do FAQ: acento + ícone tonal.
class _HelpTone {
  final Color color;
  final IconData icon;
  const _HelpTone(this.color, this.icon);
}

_HelpTone _categoryTone(String id, bool d) {
  switch (id) {
    case 'geral':
      return _HelpTone(_toneSky(d), LucideIcons.rocket);
    case 'crm':
      return _HelpTone(_toneViolet(d), LucideIcons.squareKanban);
    case 'imoveis':
      return _HelpTone(_toneBrand(d), LucideIcons.home);
    case 'agenda':
      return _HelpTone(_toneAmber(d), LucideIcons.calendarDays);
    case 'documentos':
      return _HelpTone(_toneRose(d), LucideIcons.fileSignature);
    case 'whatsapp':
      return _HelpTone(_toneEmerald(d), LucideIcons.messageCircle);
    case 'relatorios':
      return _HelpTone(_toneSlate(d), LucideIcons.chartColumn);
    case 'conta':
      return _HelpTone(_toneIndigo(d), LucideIcons.userRound);
    default:
      return _HelpTone(_toneBrand(d), LucideIcons.circleHelp);
  }
}

/// Acento de cada guia passo a passo, herdado do tema a que pertence.
Color _guideAccent(String id, bool d) {
  switch (id) {
    case 'novo-lead':
      return _toneViolet(d);
    case 'novo-imovel':
      return _toneBrand(d);
    case 'ficha-venda':
      return _toneRose(d);
    case 'agendar-visita':
      return _toneAmber(d);
    case 'abrir-chamado':
      return _toneSky(d);
    default:
      return _toneBrand(d);
  }
}

/// Acento de cada atalho ("ir direto para a tela"), pela rota de destino.
Color _quickLinkAccent(String route, bool d) {
  switch (route) {
    case AppRoutes.kanban:
      return _toneViolet(d);
    case AppRoutes.properties:
      return _toneBrand(d);
    case AppRoutes.saleForms:
      return _toneRose(d);
    case AppRoutes.clients:
      return _toneSky(d);
    case AppRoutes.calendar:
      return _toneAmber(d);
    case kHelpTicketsRoute:
      return _toneEmerald(d);
    default:
      return _toneBrand(d);
  }
}

/// Tela **Central de Ajuda** — porte do `FaqPage.tsx` web com personalidade
/// própria: a BUSCA é a protagonista. O topo é um convite ("Como podemos
/// ajudar?") com um campo de busca grande; abaixo, os temas viram um grid de
/// cartões tonais (ícone + nome + contagem de artigos, cada um com seu acento
/// de cor por significado), seguidos das perguntas do tema ativo, dos guias
/// passo a passo e dos atalhos de navegação. Conteúdo estático (sem endpoint),
/// disponível para qualquer usuário autenticado. No rodapé, o caminho para
/// abrir um chamado.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  static const List<String> _suggestions = [
    'senha',
    'lead',
    'assinatura',
    'check-in',
    'PDF',
    'empresa',
  ];

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

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _accent => _toneBrand(_isDark);

  bool get _isSearching => helpNormalize(_search.trim()).isNotEmpty;

  int get _totalFaqCount =>
      faqCategories.fold<int>(0, (sum, c) => sum + c.items.length);

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

  void _applySearch(String term) {
    _searchController.text = term;
    _searchController.selection = TextSelection.collapsed(offset: term.length);
    setState(() {
      _search = term;
      _openFaqKey = null;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _search = '';
      _openFaqKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = _visibleCategories;

    return AppScaffold(
      title: 'Central de Ajuda',
      showBottomNavigation: false,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInvite(context),
            const SizedBox(height: 16),
            _buildSearchField(context),
            if (!_isSearching) ...[
              const SizedBox(height: 12),
              _buildSuggestionChips(context),
              const SizedBox(height: 26),
              _sectionHeading(context, 'EXPLORAR POR TEMA'),
              const SizedBox(height: 12),
              _buildCategoryGrid(context),
              const SizedBox(height: 20),
              for (final category in categories)
                _buildCategoryBlock(context, category),
              const SizedBox(height: 16),
              _sectionHeading(context, 'GUIAS PASSO A PASSO'),
              const SizedBox(height: 12),
              _buildGuides(context),
              const SizedBox(height: 16),
              _sectionHeading(context, 'IR DIRETO PARA A TELA'),
              const SizedBox(height: 12),
              _buildQuickStrip(context),
            ] else ...[
              const SizedBox(height: 18),
              if (categories.isEmpty)
                _buildEmptySearch(context)
              else ...[
                _buildResultsSummary(context, categories),
                const SizedBox(height: 14),
                for (final category in categories)
                  _buildCategoryBlock(context, category),
              ],
            ],
            const SizedBox(height: 22),
            _buildSupportCta(context),
          ],
        ),
      ),
    );
  }

  // ─── Convite (título acolhedor, sem eyebrow/pills) ───────────────────────

  Widget _buildInvite(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: 'Como podemos\n',
            children: [
              TextSpan(
                text: 'ajudar',
                style: TextStyle(color: _accent),
              ),
              const TextSpan(text: '?'),
            ],
          ),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -1.0,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Busque em $_totalFaqCount respostas rápidas, siga um guia passo a '
          'passo ou fale direto com o suporte.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 280.ms, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: 320.ms, curve: Curves.easeOutCubic);
  }

  // ─── Busca protagonista ──────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final isDark = _isDark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;

    return Focus(
      onFocusChange: (f) => setState(() => _searchFocused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 58,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: showAccent
                ? _accent.withValues(alpha: isDark ? 0.55 : 0.45)
                : ThemeHelpers.borderColor(context),
            width: showAccent ? 1.5 : 1,
          ),
          boxShadow: [
            ...ThemeHelpers.cardShadow(context),
            if (showAccent)
              BoxShadow(
                color: _accent.withValues(alpha: isDark ? 0.20 : 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
                spreadRadius: -4,
              ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 11),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: _accent.withValues(
                  alpha: showAccent
                      ? (isDark ? 0.24 : 0.14)
                      : (isDark ? 0.16 : 0.08),
                ),
              ),
              child: Icon(LucideIcons.search, size: 17, color: _accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                cursorColor: _accent,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
                decoration: InputDecoration(
                  hintText: 'Busque por senha, lead, ficha, check-in…',
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
                onTap: _clearSearch,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(LucideIcons.x, size: 16, color: secondary),
                ),
              ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 60.ms, duration: 280.ms, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: 320.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildSuggestionChips(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.sparkles, size: 12, color: secondary),
              const SizedBox(width: 5),
              Text(
                'Tente:',
                style: TextStyle(
                  color: secondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        for (final term in _suggestions)
          Material(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _applySearch(term),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ThemeHelpers.borderColor(context),
                  ),
                ),
                child: Text(
                  term,
                  style: TextStyle(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Cabeçalho de seção (editorial, sem ícone) ───────────────────────────

  Widget _sectionHeading(BuildContext context, String label) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: secondary.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
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

  // ─── Grid de temas ───────────────────────────────────────────────────────

  Widget _buildCategoryGrid(BuildContext context) {
    final isDark = _isDark;
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 118,
      ),
      children: [
        for (final category in faqCategories)
          _CategoryCard(
            category: category,
            tone: _categoryTone(category.id, isDark),
            active: category.id == _activeCategoryId,
            onTap: () => setState(() {
              _activeCategoryId = category.id;
              _openFaqKey = null;
            }),
          ),
      ],
    );
  }

  // ─── Bloco de FAQ de uma categoria ───────────────────────────────────────

  Widget _buildCategoryBlock(BuildContext context, FaqCategory category) {
    final theme = Theme.of(context);
    final tone = _categoryTone(category.id, _isDark);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final count = category.items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: tone.color.withValues(alpha: _isDark ? 0.18 : 0.1),
                ),
                child: Icon(tone.icon, color: tone.color, size: 15),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  category.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Text(
                '$count ${count == 1 ? 'artigo' : 'artigos'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < category.items.length; i++)
          _FaqAccordion(
            item: category.items[i],
            open: _openFaqKey == '${category.id}-$i',
            accent: tone.color,
            onToggle: () => setState(() {
              final key = '${category.id}-$i';
              _openFaqKey = _openFaqKey == key ? null : key;
            }),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ─── Resumo e vazio da busca ─────────────────────────────────────────────

  Widget _buildResultsSummary(
    BuildContext context,
    List<FaqCategory> categories,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final total = categories.fold<int>(0, (sum, c) => sum + c.items.length);
    return Text.rich(
      TextSpan(
        text: '$total ${total == 1 ? 'resultado' : 'resultados'} para ',
        children: [
          TextSpan(
            text: '"${_search.trim()}"',
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      style: theme.textTheme.bodySmall?.copyWith(
        color: secondary,
        fontWeight: FontWeight.w600,
      ),
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
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _clearSearch,
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(color: _accent.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
            ),
            icon: const Icon(LucideIcons.x, size: 14),
            label: const Text(
              'Limpar busca',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Guias passo a passo ─────────────────────────────────────────────────

  Widget _buildGuides(BuildContext context) {
    final isDark = _isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final guide in helpGuides)
          _GuideCard(
            guide: guide,
            open: _openGuideId == guide.id,
            accent: _guideAccent(guide.id, isDark),
            onToggle: () => setState(() {
              _openGuideId = _openGuideId == guide.id ? null : guide.id;
            }),
            onCta: () => _go(guide.ctaRoute),
          ),
      ],
    );
  }

  // ─── Atalhos (strip horizontal) ──────────────────────────────────────────

  Widget _buildQuickStrip(BuildContext context) {
    final isDark = _isDark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < helpQuickLinks.length; i++) ...[
            _QuickLinkCard(
              link: helpQuickLinks[i],
              accent: _quickLinkAccent(helpQuickLinks[i].route, isDark),
              onTap: () => _go(helpQuickLinks[i].route),
            ),
            if (i != helpQuickLinks.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  // ─── CTA de suporte ──────────────────────────────────────────────────────

  Widget _buildSupportCta(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = _isDark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
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
                  borderRadius: BorderRadius.circular(14),
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

// ─── Cartão de tema (grid) ────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final FaqCategory category;
  final _HelpTone tone;
  final bool active;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.tone,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final bg = active
        ? Color.alphaBlend(
            tone.color.withValues(alpha: isDark ? 0.10 : 0.06),
            cardColor,
          )
        : cardColor;
    final count = category.items.length;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? tone.color.withValues(alpha: isDark ? 0.55 : 0.45)
                  : ThemeHelpers.borderLightColor(context),
              width: active ? 1.4 : 1,
            ),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: tone.color.withValues(
                        alpha: isDark ? 0.18 : 0.1,
                      ),
                    ),
                    child: Icon(tone.icon, color: tone.color, size: 17),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: active ? 1 : 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone.color,
                      ),
                      child: const Icon(
                        LucideIcons.check,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.2,
                      fontSize: 12.5,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$count ${count == 1 ? 'artigo' : 'artigos'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: active
                          ? tone.color
                          : ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cartão de atalho (strip horizontal) ──────────────────────────────────────

class _QuickLinkCard extends StatelessWidget {
  final HelpQuickLink link;
  final Color accent;
  final VoidCallback onTap;

  const _QuickLinkCard({
    required this.link,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: 196,
      height: 64,
      child: Material(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ThemeHelpers.borderLightColor(context),
              ),
              boxShadow: ThemeHelpers.cardShadow(context),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                  ),
                  child: Icon(link.icon, color: accent, size: 17),
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
                          fontSize: 12.5,
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
                const SizedBox(width: 6),
                Icon(
                  LucideIcons.arrowUpRight,
                  size: 14,
                  color: ThemeHelpers.textSecondaryColor(
                    context,
                  ).withValues(alpha: 0.7),
                ),
              ],
            ),
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
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.listChecks,
                                size: 11,
                                color: accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${guide.steps.length} passos',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: ThemeHelpers.borderLightColor(
                      context,
                    ).withValues(alpha: 0.6),
                  ),
                  Text(
                    item.answer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ).animate().fadeIn(duration: 180.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
