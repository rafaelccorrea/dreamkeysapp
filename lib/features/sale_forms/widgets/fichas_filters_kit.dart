import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';

/// Kit dos filtros das listas de Fichas (venda e proposta).
///
/// Gramática = drawer de filtros do CRM (`kanban_filters_drawer.dart`):
/// seções *flush* separadas por filete tracejado + eyebrow com dot de cor,
/// campos em pill com chip de ícone, cor usada só como sinal, rodapé
/// "Limpar filtros" (cinza) + "Aplicar (n)" (verde de confirmação).
/// Escolhas longas (corretores, equipes, unidade, autor, ordenação) abrem um
/// sheet próprio — o modal principal fica curto e legível em 320dp.

// ═══ Tons das seções (só sinal: dot, ícone, ativo) ══════════════════════════

class FichasFilterTones {
  FichasFilterTones._();

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color brand(BuildContext c) =>
      _dark(c) ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  static Color amber(BuildContext c) =>
      _dark(c) ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  static Color green(BuildContext c) =>
      _dark(c) ? const Color(0xFF34D399) : const Color(0xFF059669);
  static Color teal(BuildContext c) =>
      _dark(c) ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
  static Color purple(BuildContext c) =>
      _dark(c) ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
  static Color blue(BuildContext c) =>
      _dark(c) ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
  static Color sky(BuildContext c) =>
      _dark(c) ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
  static Color rose(BuildContext c) =>
      _dark(c) ? const Color(0xFFF472B6) : const Color(0xFFDB2777);
  static Color slate(BuildContext c) => ThemeHelpers.textSecondaryColor(c);
}

// ═══ Catálogos (mesmas fontes do web) ═══════════════════════════════════════

/// Opção de seleção (usuário, equipe, unidade).
class FichasPickOption {
  final String id;
  final String label;
  final String? subtitle;
  final bool inactive;

  const FichasPickOption({
    required this.id,
    required this.label,
    this.subtitle,
    this.inactive = false,
  });
}

class FichasCatalogError implements Exception {
  final String message;
  const FichasCatalogError(this.message);
  @override
  String toString() => message;
}

class FichasFilterCatalog {
  FichasFilterCatalog._();

  static ApiService get _api => ApiService.instance;

  /// Corretores do drawer de fichas de venda — web: `usersApi.getUsers({
  /// page: 1, limit: 500, allCompanyUsers: true })` (`/admin/users`, payload
  /// `compact`), sem quem está inativo na empresa. Sem acesso a esse
  /// endpoint, cai para os membros da empresa.
  static Future<List<FichasPickOption>> saleFormUsers() async {
    try {
      final res = await _api.get<dynamic>(
        ApiConstants.adminUsers,
        queryParameters: const {
          'page': '1',
          'limit': '500',
          'allCompanyUsers': 'true',
          'compact': 'true',
        },
      );
      if (res.success) {
        final list = _rows(res.data)
            .where((u) => u['isActiveInCompany'] != false)
            .map(
              (u) => FichasPickOption(
                id: _s(u['id']),
                label: _s(u['name']).trim(),
                subtitle: _sn(u['email']),
              ),
            )
            .where((o) => o.id.isNotEmpty)
            .toList();
        if (list.isNotEmpty) return _sorted(list);
      }
    } catch (e) {
      debugPrint('[FICHAS_FILTERS] users: $e');
    }
    return companyMembers();
  }

  /// Membros da empresa — `GET /users/company-members/simple` (autor das
  /// fichas de proposta no web).
  static Future<List<FichasPickOption>> companyMembers() async {
    final res = await _api.get<dynamic>('/users/company-members/simple');
    if (!res.success) {
      throw FichasCatalogError(
        res.message ?? 'Não foi possível carregar os usuários.',
      );
    }
    return _sorted(
      _rows(res.data)
          .map(
            (u) => FichasPickOption(
              id: _s(u['id']),
              label: _s(u['name']).trim(),
              subtitle: _sn(u['email']),
            ),
          )
          .where((o) => o.id.isNotEmpty)
          .toList(),
    );
  }

  /// Equipes habilitadas em fichas de venda — web:
  /// `teamApi.getTeams({ useInSaleForms: true })`, só as ativas.
  static Future<List<FichasPickOption>> saleFormTeams() async {
    final res = await _api.get<dynamic>(
      ApiConstants.teams,
      queryParameters: const {'useInSaleForms': 'true'},
    );
    if (!res.success) {
      throw FichasCatalogError(
        res.message ?? 'Não foi possível carregar as equipes.',
      );
    }
    return _sorted(
      _rows(res.data)
          .where((t) => t['isActive'] != false)
          .map(
            (t) => FichasPickOption(
              id: _s(t['id']),
              label: _s(t['name']).trim(),
            ),
          )
          .where((o) => o.id.isNotEmpty)
          .toList(),
    );
  }

  /// Unidades de venda — web: `useSaleUnits({ activeOnly: false })`: ativas
  /// e inativas (filtro retroativo), inativa marcada. O valor do filtro é o
  /// NOME da unidade (`saleUnit` exato), como no `<option value={u.name}>`.
  static Future<List<FichasPickOption>> saleUnits() async {
    final res = await _api.get<dynamic>('/sistema/sale-units-config');
    if (!res.success) {
      throw FichasCatalogError(
        res.message ?? 'Não foi possível carregar as unidades.',
      );
    }
    final seen = <String>{};
    final out = <FichasPickOption>[];
    for (final u in _rows(res.data)) {
      final name = _s(u['name']).trim();
      if (name.isEmpty || !seen.add(name)) continue;
      out.add(
        FichasPickOption(
          id: name,
          label: name,
          inactive: u['isActive'] == false,
        ),
      );
    }
    return out;
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) {
    List<dynamic> list = const [];
    if (raw is List) {
      list = raw;
    } else if (raw is Map && raw['data'] is List) {
      list = raw['data'] as List;
    }
    return list
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  static List<FichasPickOption> _sorted(List<FichasPickOption> list) {
    list.sort((a, b) => fichasFold(a.label).compareTo(fichasFold(b.label)));
    return list;
  }

  static String _s(dynamic v) => v?.toString() ?? '';
  static String? _sn(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}

/// Minúsculas sem acento — busca e ordenação pt-BR.
String fichasFold(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString();
}

/// Resumo de uma seleção múltipla para o campo do modal.
String? fichasSelectionSummary(
  Set<String> ids,
  List<FichasPickOption>? options, {
  required String noun,
  required String nounPlural,
}) {
  if (ids.isEmpty) return null;
  final names = <String>[];
  if (options != null) {
    for (final o in options) {
      if (ids.contains(o.id)) names.add(o.label);
    }
  }
  if (names.isEmpty || names.length != ids.length) {
    return '${ids.length} ${ids.length == 1 ? noun : nounPlural}';
  }
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2}';
}

String fichasFmtDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

// ═══ Gatilho "Filtros" com contador ═════════════════════════════════════════

/// Botão de filtros da lista — mesma pastilha do CRM (tint da marca, badge
/// com a contagem quando há filtros). Em tela estreita ou fonte grande vira
/// só ícone + badge, para a busca ao lado nunca espremer.
class FichasFiltersButton extends StatelessWidget {
  const FichasFiltersButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = FichasFilterTones.brand(context);
    final active = count > 0;
    final compact = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Semantics(
      button: true,
      label: active ? 'Filtros, $count ativos' : 'Filtros',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: active
                    ? [
                        color.withValues(alpha: isDark ? 0.34 : 0.20),
                        color.withValues(alpha: isDark ? 0.16 : 0.10),
                      ]
                    : [
                        color.withValues(alpha: isDark ? 0.22 : 0.13),
                        color.withValues(alpha: isDark ? 0.10 : 0.06),
                      ],
              ),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.55 : 0.42),
                width: active ? 1.5 : 1,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46, minWidth: 46),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.tune_rounded, size: 18, color: color),
                    if (!compact) ...[
                      const SizedBox(width: 7),
                      Text(
                        'Filtros',
                        maxLines: 1,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                    if (active) ...[
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$count',
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══ Casca dos sheets (grabber, altura máx. 0.88, teclado) ══════════════════

class FichasSheetShell extends StatelessWidget {
  const FichasSheetShell({
    super.key,
    required this.header,
    required this.body,
    this.footer,
  });

  final Widget header;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final free = mq.size.height - mq.viewInsets.bottom - mq.padding.top - 12;
    final cap = mq.size.height * 0.88;
    final maxH = free < cap ? (free < 240 ? 240.0 : free) : cap;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(
                        context,
                      ).withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              header,
              Flexible(child: body),
              if (footer != null) footer!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabeçalho do modal de filtros: ícone tonal + título + contagem, fechar à
/// direita (igual ao "Filtrar leads" do CRM).
class FichasFilterSheetHeader extends StatelessWidget {
  const FichasFilterSheetHeader({
    super.key,
    required this.title,
    required this.activeCount,
  });

  final String title;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = FichasFilterTones.brand(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 10, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune_rounded, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activeCount == 0
                      ? 'Nenhum filtro aplicado'
                      : '$activeCount filtro${activeCount == 1 ? '' : 's'} ativo${activeCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: activeCount == 0
                        ? ThemeHelpers.textSecondaryColor(context)
                        : accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }
}

/// Cabeçalho dos sheets de escolha: eyebrow na cor + título, fechar à
/// direita, divisor em degradê.
class FichasEyebrowHeader extends StatelessWidget {
  const FichasEyebrowHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.accent,
  });

  final String eyebrow;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  size: 19,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                visualDensity: VisualDensity.compact,
                tooltip: 'Fechar',
              ),
            ],
          ),
        ),
        Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.30),
                ThemeHelpers.borderLightColor(context).withValues(alpha: 0.25),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Rodapé do modal: "Limpar filtros" (cinza, só com filtro ativo) +
/// "Aplicar (n)" em verde de confirmação. [error] aparece acima, em vermelho.
class FichasFilterFooter extends StatelessWidget {
  const FichasFilterFooter({
    super.key,
    required this.activeCount,
    required this.onApply,
    required this.onClear,
    this.error,
    this.applyLabel = 'Aplicar',
    this.clearLabel = 'Limpar filtros',
    this.showCount = true,
  });

  final int activeCount;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final String? error;
  final String applyLabel;
  final String clearLabel;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: danger,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: danger,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (activeCount > 0) ...[
                Expanded(
                  child: TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      // Nunca em vermelho: limpar não é destrutivo.
                      foregroundColor: ThemeHelpers.textSecondaryColor(context),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      textStyle:
                          Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(clearLabel),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: activeCount > 0 ? 2 : 1,
                child: FilledButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      (!showCount || activeCount == 0)
                          ? applyLabel
                          : '$applyLabel ($activeCount)',
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    // Verde de confirmação, como em todo sheet do app.
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    elevation: 0,
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
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

// ═══ Seção flush ════════════════════════════════════════════════════════════

/// Seção *flush*: filete tracejado (exceto a primeira) + eyebrow com dot de
/// cor + contagem à direita + hint + conteúdo. Sem card, sem preenchimento.
class FichasFilterSection extends StatelessWidget {
  const FichasFilterSection({
    super.key,
    required this.accent,
    required this.label,
    required this.child,
    this.hint,
    this.trailing,
    this.first = false,
  });

  final Color accent;
  final String label;
  final String? hint;
  final String? trailing;
  final Widget child;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            _DashedLine(color: ThemeHelpers.borderLightColor(context)),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: secondary,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: secondary.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ═══ Chips em grade uniforme (2 colunas) ════════════════════════════════════

/// Grade de largura uniforme (2 colunas) — alinhada, sem scroll horizontal.
/// Item ímpar final ocupa a linha inteira para não deixar célula órfã.
class FichasChipGrid extends StatelessWidget {
  const FichasChipGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        const gap = 8.0;
        final half = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < children.length; i++)
              SizedBox(
                width: (children.length.isOdd && i == children.length - 1)
                    ? c.maxWidth
                    : half,
                child: children[i],
              ),
          ],
        );
      },
    );
  }
}

/// Chip de seleção — ativo usa *tint* (fundo translúcido + borda + texto na
/// cor), nunca preenchimento sólido.
class FichasChoiceChip extends StatelessWidget {
  const FichasChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.dot = false,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    final bg = selected
        ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
        : fieldFill;
    final border = selected ? accent : ThemeHelpers.borderLightColor(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: selected ? 1.2 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (dot) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected ? accent : accent.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ] else if (selected) ...[
                Icon(Icons.check_rounded, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 12.5,
                    color: fg,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
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

// ═══ Campo em pill (abre escolha) ═══════════════════════════════════════════

class FichasFilterField extends StatelessWidget {
  const FichasFilterField({
    super.key,
    required this.icon,
    required this.accent,
    required this.caption,
    required this.placeholder,
    required this.onTap,
    this.value,
    this.onClear,
  });

  final IconData icon;
  final Color accent;
  final String caption;
  final String placeholder;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filled = value != null && value!.trim().isNotEmpty;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled
                ? accent.withValues(alpha: 0.55)
                : ThemeHelpers.borderLightColor(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    filled ? value! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
                      color: filled
                          ? ThemeHelpers.textColor(context)
                          : secondary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (filled && onClear != null)
              IconButton(
                onPressed: onClear,
                icon: Icon(Icons.close_rounded, size: 18, color: secondary),
                visualDensity: VisualDensity.compact,
                tooltip: 'Limpar',
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Par de datas (início/fim). Lado a lado quando cabe; empilhado em tela
/// estreita ou fonte grande (zero overflow em 320dp).
class FichasDateRangeField extends StatelessWidget {
  const FichasDateRangeField({
    super.key,
    required this.accent,
    required this.from,
    required this.to,
    required this.onChanged,
    this.fromCaption = 'Data inicial',
    this.toCaption = 'Data final',
    this.icon = Icons.event_outlined,
  });

  final Color accent;
  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;
  final String fromCaption;
  final String toCaption;
  final IconData icon;

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final now = DateTime.now();
    final first = DateTime(2015);
    final last = DateTime(now.year + 2, 12, 31);
    var initial = (isStart ? from : to) ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    if (isStart) {
      onChanged(picked, to);
    } else {
      onChanged(from, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final stack = c.maxWidth < 330 ||
            MediaQuery.textScalerOf(ctx).scale(1) > 1.2;
        final a = FichasFilterField(
          icon: icon,
          accent: accent,
          caption: fromCaption,
          placeholder: 'dd/mm/aaaa',
          value: from == null ? null : fichasFmtDate(from!),
          onTap: () => _pick(ctx, isStart: true),
          onClear: () => onChanged(null, to),
        );
        final b = FichasFilterField(
          icon: icon,
          accent: accent,
          caption: toCaption,
          placeholder: 'dd/mm/aaaa',
          value: to == null ? null : fichasFmtDate(to!),
          onTap: () => _pick(ctx, isStart: false),
          onClear: () => onChanged(from, null),
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 10), b],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
      },
    );
  }
}

// ═══ Sheet de escolha (lista com busca, simples ou múltipla) ═══════════════

/// Abre a lista de [options] com busca. Múltipla: devolve o conjunto marcado
/// ao tocar em "Concluir". Simples: devolve `{id}` ao tocar numa linha, ou
/// `{}` na linha [allLabel]. `null` = fechou sem escolher.
Future<Set<String>?> showFichasPickSheet(
  BuildContext context, {
  required String eyebrow,
  required String title,
  required Color accent,
  required Future<List<FichasPickOption>> options,
  required Set<String> selected,
  bool multi = true,
  String allLabel = 'Todos',
  String searchHint = 'Buscar…',
  String emptyMessage = 'Nenhuma opção encontrada.',
  IconData icon = Icons.person_outline_rounded,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _FichasPickSheet(
      eyebrow: eyebrow,
      title: title,
      accent: accent,
      options: options,
      selected: selected,
      multi: multi,
      allLabel: allLabel,
      searchHint: searchHint,
      emptyMessage: emptyMessage,
      icon: icon,
    ),
  );
}

class _FichasPickSheet extends StatefulWidget {
  const _FichasPickSheet({
    required this.eyebrow,
    required this.title,
    required this.accent,
    required this.options,
    required this.selected,
    required this.multi,
    required this.allLabel,
    required this.searchHint,
    required this.emptyMessage,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final Color accent;
  final Future<List<FichasPickOption>> options;
  final Set<String> selected;
  final bool multi;
  final String allLabel;
  final String searchHint;
  final String emptyMessage;
  final IconData icon;

  @override
  State<_FichasPickSheet> createState() => _FichasPickSheetState();
}

class _FichasPickSheetState extends State<_FichasPickSheet> {
  final _query = TextEditingController();
  late final Set<String> _sel = {...widget.selected};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<FichasPickOption> _filter(List<FichasPickOption> all) {
    final q = fichasFold(_query.text.trim());
    if (q.isEmpty) return all;
    return all
        .where(
          (o) =>
              fichasFold(o.label).contains(q) ||
              fichasFold(o.subtitle ?? '').contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return FichasSheetShell(
      header: FichasEyebrowHeader(
        eyebrow: widget.eyebrow,
        title: widget.title,
        accent: accent,
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: _searchField(context),
          ),
          Flexible(
            child: FutureBuilder<List<FichasPickOption>>(
              future: widget.options,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snap.hasError) {
                  return _message(ctx, snap.error.toString());
                }
                final rows = _filter(snap.data ?? const []);
                final showAll = !widget.multi && _query.text.trim().isEmpty;
                if (rows.isEmpty && !showAll) {
                  return _message(ctx, widget.emptyMessage);
                }
                final count = rows.length + (showAll ? 1 : 0);
                return ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                    10,
                    4,
                    10,
                    widget.multi
                        ? 12
                        : 16 + MediaQuery.of(ctx).padding.bottom,
                  ),
                  itemCount: count,
                  itemBuilder: (_, i) {
                    if (showAll && i == 0) {
                      return _row(
                        ctx,
                        label: widget.allLabel,
                        selected: _sel.isEmpty,
                        onTap: () => Navigator.of(ctx).pop(<String>{}),
                      );
                    }
                    final o = rows[i - (showAll ? 1 : 0)];
                    final on = _sel.contains(o.id);
                    return _row(
                      ctx,
                      label: o.label.isEmpty ? '—' : o.label,
                      subtitle: o.subtitle,
                      inactive: o.inactive,
                      selected: on,
                      onTap: () {
                        if (widget.multi) {
                          setState(() {
                            if (!_sel.remove(o.id)) _sel.add(o.id);
                          });
                        } else {
                          Navigator.of(ctx).pop(<String>{o.id});
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      footer: widget.multi
          ? FichasFilterFooter(
              activeCount: _sel.length,
              applyLabel: 'Concluir',
              clearLabel: 'Limpar',
              onClear: () => setState(_sel.clear),
              onApply: () => Navigator.of(context).pop(<String>{..._sel}),
            )
          : null,
    );
  }

  Widget _searchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return TextField(
      controller: _query,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: ThemeHelpers.textColor(context),
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.searchHint,
        hintStyle: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: secondary.withValues(alpha: 0.9),
        ),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: widget.accent),
        suffixIcon: _query.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: secondary),
                onPressed: () => setState(_query.clear),
                tooltip: 'Limpar busca',
              ),
        filled: true,
        fillColor: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.accent.withValues(alpha: 0.65)),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String? subtitle,
    bool inactive = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accent;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final IconData mark = widget.multi
        ? (selected
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded)
        : (selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                Icon(mark, size: 20, color: selected ? accent : secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        inactive ? '$label (inativa)' : label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? accent
                              : (inactive
                                  ? secondary
                                  : ThemeHelpers.textColor(context)),
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══ Ordenação ══════════════════════════════════════════════════════════════

class FichasSortOption {
  final String value;
  final String label;
  final IconData icon;
  const FichasSortOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

/// Seção de ordenação: campo "Ordenar por" (abre a lista) + direção em dois
/// chips. Mesmo contrato do web (`sortBy` + `sortOrder` ASC/DESC).
class FichasSortControl extends StatelessWidget {
  const FichasSortControl({
    super.key,
    required this.accent,
    required this.options,
    required this.sortBy,
    required this.sortOrder,
    required this.onChanged,
    this.title = 'Ordem da lista',
  });

  final Color accent;
  final List<FichasSortOption> options;
  final String sortBy;
  final String sortOrder;
  final void Function(String sortBy, String sortOrder) onChanged;
  final String title;

  FichasSortOption get _current => options.firstWhere(
        (o) => o.value == sortBy,
        orElse: () => options.first,
      );

  Future<void> _open(BuildContext context) async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => FichasSheetShell(
        header: FichasEyebrowHeader(
          eyebrow: 'Ordenar',
          title: title,
          accent: accent,
        ),
        body: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            16 + MediaQuery.of(ctx).padding.bottom,
          ),
          children: [
            for (final o in options) _option(ctx, o, o.value == _current.value),
          ],
        ),
      ),
    );
    if (escolha != null) onChanged(escolha, sortOrder);
  }

  Widget _option(BuildContext ctx, FichasSortOption o, bool selected) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(ctx);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => Navigator.of(ctx).pop(o.value),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: accent.withValues(
                      alpha: selected ? (isDark ? 0.26 : 0.16) : 0.10,
                    ),
                  ),
                  child: Icon(
                    o.icon,
                    size: 17,
                    color: selected ? accent : secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    o.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? accent
                              : ThemeHelpers.textColor(ctx),
                          letterSpacing: -0.1,
                        ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle_rounded, size: 19, color: accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cur = _current;
    final desc = sortOrder.toUpperCase() != 'ASC';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FichasFilterField(
          icon: cur.icon,
          accent: accent,
          caption: 'Ordenar por',
          placeholder: cur.label,
          value: cur.label,
          onTap: () => _open(context),
        ),
        const SizedBox(height: 10),
        FichasChipGrid(
          children: [
            FichasChoiceChip(
              label: 'Decrescente',
              selected: desc,
              accent: accent,
              onTap: () => onChanged(cur.value, 'DESC'),
            ),
            FichasChoiceChip(
              label: 'Crescente',
              selected: !desc,
              accent: accent,
              onTap: () => onChanged(cur.value, 'ASC'),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══ Filete tracejado ═══════════════════════════════════════════════════════

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedPainter(color)),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) =>
      oldDelegate.color != color;
}
