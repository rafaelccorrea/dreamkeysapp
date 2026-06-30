import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../features/workspace/models/company_team_model.dart';
import '../../../features/workspace/services/company_team_service.dart';
import '../../../shared/services/sale_forms_service.dart';

/// Resultado do modal de tipo + equipe.
class SaleFormTypeChoice {
  final SaleFormType type;
  final String teamId;
  final String teamName;
  const SaleFormTypeChoice({
    required this.type,
    required this.teamId,
    required this.teamName,
  });
}

/// Modal que abre ANTES do formulário de criação: escolhe o **tipo** da ficha
/// e a **equipe** (obrigatória) — espelha o `SaleFormTypeModal` do web.
Future<SaleFormTypeChoice?> showSaleFormTypeModal(BuildContext context) {
  return showModalBottomSheet<SaleFormTypeChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SaleFormTypeSheet(),
  );
}

class _SaleFormTypeSheet extends StatefulWidget {
  const _SaleFormTypeSheet();
  @override
  State<_SaleFormTypeSheet> createState() => _SaleFormTypeSheetState();
}

class _SaleFormTypeSheetState extends State<_SaleFormTypeSheet> {
  SaleFormType _type = SaleFormType.terceiros;
  String? _teamId;
  String _teamSearch = '';
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<CompanyTeam> _teams = [];

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CompanyTeamService.instance.listTeams(
      status: 'active',
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _teams =
            res.data!.teams
                .where((t) => t.useInSaleForms && t.isActive)
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
        if (_teams.length == 1) _teamId = _teams.first.id;
      } else {
        _error = res.message ?? 'Erro ao carregar equipes.';
      }
    });
  }

  Color _typeColor(SaleFormType t) {
    switch (t) {
      case SaleFormType.terceiros:
        return const Color(0xFF6366F1);
      case SaleFormType.lancamento:
        return const Color(0xFF2563EB);
      case SaleFormType.casaMinhaVida:
        return const Color(0xFF059669);
    }
  }

  IconData _typeIcon(SaleFormType t) {
    switch (t) {
      case SaleFormType.terceiros:
        return LucideIcons.store;
      case SaleFormType.lancamento:
        return LucideIcons.building2;
      case SaleFormType.casaMinhaVida:
        return LucideIcons.house;
    }
  }

  String _typeSubtitle(SaleFormType t) {
    switch (t) {
      case SaleFormType.terceiros:
        return 'Imóvel de terceiros · revenda';
      case SaleFormType.lancamento:
        return 'Empreendimento · lançamento';
      case SaleFormType.casaMinhaVida:
        return 'Programa habitacional';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final filteredTeams = _teams.where((t) {
      if (_teamSearch.isEmpty) return true;
      return t.name.toLowerCase().contains(_teamSearch);
    }).toList();
    final canConfirm = _teamId != null;

    Widget sectionLabel(String text, {bool required = false}) => Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            color: secondary,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 6),
          Text(
            '*',
            style: TextStyle(color: _accent, fontWeight: FontWeight.w900),
          ),
        ],
      ],
    );

    // Conteúdo central rolável — TUDO rola junto (tipos + equipes), com cabeçalho
    // e botão fixos. Antes só a lista de equipes rolava (área minúscula).
    Widget teamsArea() {
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (_error != null) {
        return _ErrorRow(message: _error!, onRetry: _loadTeams);
      }
      if (_teams.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Nenhuma equipe habilitada para fichas de venda.',
            style: TextStyle(color: secondary, fontWeight: FontWeight.w600),
          ),
        );
      }
      return LayoutBuilder(
        builder: (ctx, c) {
          const gap = 10.0;
          final w = (c.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final t in filteredTeams)
                SizedBox(
                  width: w,
                  child: _TeamTile(
                    team: t,
                    selected: _teamId == t.id,
                    accent: _accent,
                    onTap: () => setState(() => _teamId = t.id),
                  ),
                ),
            ],
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho fixo
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ThemeHelpers.borderColor(context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nova ficha de venda',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Escolha o tipo e a equipe para começar.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
            // Conteúdo rolável
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                children: [
                  sectionLabel('TIPO'),
                  const SizedBox(height: 10),
                  for (final t in SaleFormType.values) ...[
                    _TypeTile(
                      label: t.label,
                      subtitle: _typeSubtitle(t),
                      icon: _typeIcon(t),
                      color: _typeColor(t),
                      selected: _type == t,
                      onTap: () => setState(() => _type = t),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  sectionLabel('EQUIPE', required: true),
                  const SizedBox(height: 10),
                  if (_teams.length >= 4) ...[
                    _TeamSearch(
                      controller: _searchCtrl,
                      accent: _accent,
                      onChanged: (v) =>
                          setState(() => _teamSearch = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                  ],
                  teamsArea(),
                ],
              ),
            ),
            // Botão fixo
            Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                6,
                18,
                14 + MediaQuery.paddingOf(context).bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canConfirm
                      ? () {
                          final team = _teams.firstWhere(
                            (t) => t.id == _teamId,
                          );
                          Navigator.of(context).pop(
                            SaleFormTypeChoice(
                              type: _type,
                              teamId: team.id,
                              teamName: team.name,
                            ),
                          );
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: ThemeHelpers.borderColor(
                      context,
                    ).withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(LucideIcons.arrowRight, size: 18),
                  label: Text(
                    canConfirm ? 'Continuar' : 'Selecione uma equipe',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: isDark ? 0.14 : 0.08)
              : ThemeHelpers.borderLightColor(context).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: isDark ? 0.28 : 0.18),
                    color.withValues(alpha: isDark ? 0.16 : 0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _SelectDot(selected: selected, color: color),
          ],
        ),
      ),
    );
  }
}

/// Indicador de seleção limpo (radio) — preenche na cor quando ativo.
class _SelectDot extends StatelessWidget {
  const _SelectDot({required this.selected, required this.color});
  final bool selected;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? color : Colors.transparent,
        border: Border.all(
          color: selected
              ? color
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({
    required this.team,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final CompanyTeam team;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color dot = accent;
    final c = team.color;
    if (c != null && c.startsWith('#') && c.length >= 7) {
      dot = Color(int.parse('FF${c.substring(1, 7)}', radix: 16));
    }
    final members = team.totalMembers;
    final leaders = team.leadersCount;
    final initial = team.name.trim().isNotEmpty
        ? team.name.trim()[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? [
                    dot.withValues(alpha: isDark ? 0.20 : 0.12),
                    dot.withValues(alpha: isDark ? 0.10 : 0.05),
                  ]
                : [
                    ThemeHelpers.borderLightColor(
                      context,
                    ).withValues(alpha: 0.45),
                    ThemeHelpers.borderLightColor(
                      context,
                    ).withValues(alpha: 0.18),
                  ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? dot.withValues(alpha: 0.55)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        dot.withValues(alpha: isDark ? 0.34 : 0.22),
                        dot.withValues(alpha: isDark ? 0.20 : 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dot.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: dot,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                const Spacer(),
                _SelectDot(selected: selected, color: dot),
              ],
            ),
            const SizedBox(height: 11),
            SizedBox(
              height: 34,
              child: Text(
                team.name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  height: 1.2,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(LucideIcons.users, size: 12, color: secondary),
                const SizedBox(width: 5),
                Text(
                  '$members ${members == 1 ? 'membro' : 'membros'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: secondary,
                  ),
                ),
                if (leaders > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: secondary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.star, size: 11, color: dot),
                  const SizedBox(width: 3),
                  Text(
                    '$leaders',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: dot,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamSearch extends StatelessWidget {
  const _TeamSearch({
    required this.controller,
    required this.accent,
    required this.onChanged,
  });
  final TextEditingController controller;
  final Color accent;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      cursorColor: accent,
      onChanged: onChanged,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: ThemeHelpers.textColor(context),
      ),
      decoration: InputDecoration(
        hintText: 'Buscar equipe…',
        hintStyle: TextStyle(
          color: secondary.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        prefixIcon: Icon(LucideIcons.search, size: 17, color: secondary),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.045)
            : Colors.black.withValues(alpha: 0.025),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
