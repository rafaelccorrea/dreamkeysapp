import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/competition_models.dart';
import '../services/competition_service.dart';
import '../widgets/gamification_ui.dart';

final NumberFormat _currency =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final NumberFormat _compactCurrency = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);

/// Painel de **Prêmios** das competições — visão global com estatísticas,
/// filtro por status, criação, edição, entrega e exclusão.
/// Paridade `PrizesPage.tsx` (`GET /competitions/prizes/all`).
class PrizesPage extends StatefulWidget {
  const PrizesPage({super.key});

  @override
  State<PrizesPage> createState() => _PrizesPageState();
}

class _PrizesPageState extends State<PrizesPage> {
  static const double _padH = 16;

  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Prize> _prizes = const [];
  List<Competition> _competitions = const [];

  PrizeStatus? _statusTab; // null = todos

  bool get _canView => ModuleAccessService.instance.hasPermission('prize:view');
  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission('prize:create');
  bool get _canEdit => ModuleAccessService.instance.hasPermission('prize:edit');
  bool get _canDeliver =>
      ModuleAccessService.instance.hasPermission('prize:deliver');
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission('prize:delete');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      CompetitionService.instance.getAllPrizes(),
      CompetitionService.instance.getCompetitions(),
    ]);
    if (!mounted) return;

    final prizesRes = results[0] as dynamic;
    final compsRes = results[1] as dynamic;

    setState(() {
      _loading = false;
      if (prizesRes.success && prizesRes.data != null) {
        _prizes = prizesRes.data as List<Prize>;
      } else {
        _error = prizesRes.message ?? 'Erro ao carregar prêmios';
      }
      if (compsRes.success && compsRes.data != null) {
        _competitions = compsRes.data as List<Competition>;
      }
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? gamDanger(context) : null,
      ),
    );
  }

  List<Prize> get _visible {
    final term = _searchController.text.trim().toLowerCase();
    return _prizes.where((p) {
      if (_statusTab != null && p.status != _statusTab) return false;
      if (term.isEmpty) return true;
      return p.name.toLowerCase().contains(term) ||
          (p.description ?? '').toLowerCase().contains(term) ||
          p.competitionName.toLowerCase().contains(term);
    }).toList();
  }

  int _countByStatus(PrizeStatus status) =>
      _prizes.where((p) => p.status == status).length;

  double get _totalValue =>
      _prizes.fold<double>(0, (sum, p) => sum + p.value);

  // ─── Ações ─────────────────────────────────────────────────────────────────

  Future<void> _deliverPrize(Prize prize) async {
    final green = gamGreen(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Entregar prêmio?',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        content: Text(
          '"${prize.name}" será marcado como entregue'
          '${prize.winnerUserName != null || prize.winnerTeamName != null ? ' para ${prize.winnerUserName ?? prize.winnerTeamName}' : ''}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar entrega'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await CompetitionService.instance.deliverPrize(prize.id);
    if (!mounted) return;
    if (res.success) {
      _snack('Prêmio marcado como entregue!');
      _load();
    } else {
      _snack(res.message ?? 'Erro ao marcar prêmio como entregue',
          error: true);
    }
  }

  Future<void> _deletePrize(Prize prize) async {
    final danger = gamDanger(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Excluir prêmio?',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        content: Text(
          'O prêmio "${prize.name}" da competição '
          '"${prize.competitionName}" será removido permanentemente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await CompetitionService.instance.removePrize(prize.id);
    if (!mounted) return;
    if (res.success) {
      _snack('Prêmio excluído!');
      _load();
    } else {
      _snack(res.message ?? 'Erro ao excluir prêmio', error: true);
    }
  }

  /// Sheet de criar (prize == null) / editar prêmio.
  void _openPrizeSheet({Prize? prize}) {
    final isEdit = prize != null;
    final nameController = TextEditingController(text: prize?.name ?? '');
    final descriptionController =
        TextEditingController(text: prize?.description ?? '');
    final valueController = TextEditingController(
      text: prize != null && prize.value > 0
          ? CurrencyInputFormatter.format(prize.value)
          : '',
    );
    final positionController =
        TextEditingController(text: '${prize?.position ?? 1}');
    String? competitionId = prize?.competitionId;
    var saving = false;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final accent = gamAccentColor(sheetContext);
        final amber = gamAmber(sheetContext);
        final secondary = ThemeHelpers.textSecondaryColor(sheetContext);
        final fill = isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary;

        InputDecoration deco({String? hint, String? prefixText}) =>
            InputDecoration(
              hintText: hint,
              hintStyle:
                  theme.textTheme.bodySmall?.copyWith(color: secondary),
              prefixText: prefixText,
              prefixStyle: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(sheetContext),
                fontWeight: FontWeight.w700,
              ),
              isDense: true,
              filled: true,
              fillColor: fill,
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: accent.withValues(alpha: 0.5)),
              ),
            );

        Widget label(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                text,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            );

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (saving) return;
              final name = nameController.text.trim();
              final position =
                  int.tryParse(positionController.text.trim()) ?? 0;

              if (name.isEmpty || (!isEdit && competitionId == null)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                        'Preencha todos os campos obrigatórios!'),
                    backgroundColor: gamDanger(context),
                  ),
                );
                return;
              }
              if (!isEdit && position < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Informe uma posição válida!'),
                    backgroundColor: gamDanger(context),
                  ),
                );
                return;
              }

              final rawValue = valueController.text
                  .replaceAll('.', '')
                  .replaceAll(',', '.')
                  .trim();
              final value = double.tryParse(rawValue);

              setSheetState(() => saving = true);

              final res = isEdit
                  ? await CompetitionService.instance.updatePrize(
                      prize.id,
                      name: name,
                      description: descriptionController.text.trim(),
                      value: value,
                    )
                  : await CompetitionService.instance.addPrize(
                      competitionId!,
                      PrizePayload(
                        position: position,
                        name: name,
                        description: descriptionController.text,
                        value: value,
                      ),
                    );

              if (!context.mounted) return;
              setSheetState(() => saving = false);

              if (res.success) {
                Navigator.of(context).pop();
                _snack(isEdit
                    ? 'Prêmio atualizado com sucesso!'
                    : 'Prêmio criado com sucesso!');
                _load();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res.message ??
                        (isEdit
                            ? 'Erro ao atualizar prêmio'
                            : 'Erro ao criar prêmio')),
                    backgroundColor: gamDanger(context),
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: ThemeHelpers.backgroundColor(context),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  16 + MediaQuery.of(context).padding.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: ThemeHelpers.borderColor(context)
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            isEdit ? LucideIcons.pencil : LucideIcons.gift,
                            size: 17,
                            color: amber,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isEdit ? 'Editar prêmio' : 'Novo prêmio',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (!isEdit) ...[
                        label('Competição *'),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: competitionId,
                              isExpanded: true,
                              hint: Text(
                                'Selecione a competição…',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: secondary),
                              ),
                              icon: Icon(LucideIcons.chevronDown,
                                  size: 16, color: secondary),
                              borderRadius: BorderRadius.circular(14),
                              items: [
                                for (final c in _competitions)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        color: ThemeHelpers.textColor(
                                            context),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setSheetState(
                                  () => competitionId = v),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isEdit) ...[
                            SizedBox(
                              width: 100,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  label('Posição *'),
                                  TextField(
                                    controller: positionController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter
                                          .digitsOnly,
                                      LengthLimitingTextInputFormatter(3),
                                    ],
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                      color:
                                          ThemeHelpers.textColor(context),
                                      fontWeight: FontWeight.w800,
                                    ),
                                    decoration: deco(hint: '1'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                label('Nome do prêmio *'),
                                TextField(
                                  controller: nameController,
                                  maxLength: 100,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                          color: ThemeHelpers.textColor(
                                              context)),
                                  decoration: deco(
                                      hint: 'Ex.: R\$ 5.000 em bônus'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      label('Descrição'),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        maxLength: 300,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textColor(context)),
                        decoration: deco(hint: 'Descrição do prêmio…'),
                      ),
                      const SizedBox(height: 12),
                      label('Valor (R\$)'),
                      TextField(
                        controller: valueController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w700,
                        ),
                        decoration:
                            deco(hint: '0,00', prefixText: 'R\$ '),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: saving ? null : submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: saving
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isEdit
                                      ? LucideIcons.save
                                      : LucideIcons.plus,
                                  size: 16,
                                ),
                          label: Text(
                            saving
                                ? 'Salvando…'
                                : isEdit
                                    ? 'Salvar alterações'
                                    : 'Criar prêmio',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      descriptionController.dispose();
      valueController.dispose();
      positionController.dispose();
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Prêmios',
        showBottomNavigation: false,
        body: GamDeniedView(
          what: 'prêmios',
          permission: 'prize:view',
        ),
      );
    }

    final accent = gamAccentColor(context);

    return AppScaffold(
      title: 'Prêmios',
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: _load,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: _buildContent(context),
                ),
              ),
            ),
          ),
          if (_canCreate && !_loading && _competitions.isNotEmpty)
            Positioned(
              right: 16,
              bottom: 24,
              child: FloatingActionButton.extended(
                heroTag: 'prizes-fab',
                onPressed: () => _openPrizeSheet(),
                backgroundColor: accent,
                foregroundColor: Colors.white,
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text(
                  'Novo prêmio',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) return _buildSkeleton(context);

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 60, _padH, 100),
        child: GamErrorState(message: _error!, onRetry: _load),
      );
    }

    final visible = _visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_padH, 10, _padH, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(context),
              const SizedBox(height: 16),
              _buildSearchField(context),
              const SizedBox(height: 4),
            ],
          ),
        ),
        _buildStatusTabs(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 108),
          child: visible.isEmpty
              ? GamEmptyState(
                  icon: LucideIcons.gift,
                  title: 'Nenhum prêmio encontrado',
                  body: _searchController.text.trim().isNotEmpty ||
                          _statusTab != null
                      ? 'Tente ajustar a busca ou o filtro de status.'
                      : _competitions.isEmpty
                          ? 'Crie uma competição primeiro para poder '
                              'adicionar prêmios!'
                          : 'Crie prêmios para recompensar os vencedores '
                              'das competições!',
                  tone: gamAmber(context),
                  action: _searchController.text.trim().isEmpty &&
                          _statusTab == null &&
                          _competitions.isEmpty &&
                          ModuleAccessService.instance
                              .hasPermission('competition:create')
                      ? FilledButton.icon(
                          onPressed: () => Navigator.of(context)
                              .pushNamed('/competitions/new')
                              .then((_) => _load()),
                          style: FilledButton.styleFrom(
                            backgroundColor: gamAccentColor(context),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(LucideIcons.trophy, size: 16),
                          label: const Text('Criar primeira competição'),
                        )
                      : null,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < visible.length; i++)
                      _prizeCard(context, visible[i])
                          .animate(key: ValueKey('gprize-${visible[i].id}'))
                          .fadeIn(
                            delay: Duration(
                                milliseconds: 30 * i.clamp(0, 10)),
                            duration: 220.ms,
                          ),
                  ],
                ),
        ),
      ],
    );
  }

  // ─── Hero ──────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = gamAccentColor(context);
    final green = gamGreen(context);
    final amber = gamAmber(context);
    final purple = gamPurple(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final pending = _countByStatus(PrizeStatus.pending);
    final available = _countByStatus(PrizeStatus.available);
    final delivered = _countByStatus(PrizeStatus.delivered);
    final dot = pending > 0 ? amber : green;

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
                color: dot,
                boxShadow: [
                  BoxShadow(
                    color: dot.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'PRÊMIOS',
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
              '${_prizes.length}',
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
                _prizes.length == 1 ? 'prêmio' : 'prêmios',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const Spacer(),
            if (_totalValue > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(colors: [
                    purple.withValues(alpha: 0.16),
                    purple.withValues(alpha: 0.07),
                  ]),
                  border:
                      Border.all(color: purple.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.banknote, size: 14, color: purple),
                    const SizedBox(width: 5),
                    Text(
                      _compactCurrency.format(_totalValue),
                      style: TextStyle(
                        color: purple,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          pending > 0
              ? '$pending prêmio${pending == 1 ? '' : 's'} aguardando entrega aos vencedores.'
              : 'Recompensas das competições da sua imobiliária.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GamMiniPill(
              label:
                  '$available ${available == 1 ? 'disponível' : 'disponíveis'}',
              color: green,
              icon: LucideIcons.gift,
            ),
            GamMiniPill(
              label: '$pending pendente${pending == 1 ? '' : 's'}',
              color: amber,
              icon: LucideIcons.clock,
            ),
            GamMiniPill(
              label: '$delivered entregue${delivered == 1 ? '' : 's'}',
              color: secondary,
              icon: LucideIcons.check,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyMedium
          ?.copyWith(color: ThemeHelpers.textColor(context)),
      decoration: InputDecoration(
        hintText: 'Buscar por prêmio ou competição…',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: secondary),
        prefixIcon: Icon(LucideIcons.search, size: 17, color: secondary),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: Icon(LucideIcons.x, size: 15, color: secondary),
                onPressed: () => _searchController.clear(),
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: fill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(
            color: gamAccentColor(context).withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTabs(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _padH - 8),
      child: Row(
        children: [
          Expanded(
            child: GamFlushTab(
              icon: LucideIcons.sparkles,
              label: 'Todos',
              count: _prizes.length,
              tone: gamAccentColor(context),
              selected: _statusTab == null,
              onTap: () => setState(() => _statusTab = null),
            ),
          ),
          Expanded(
            child: GamFlushTab(
              icon: LucideIcons.gift,
              label: 'Disponíveis',
              count: _countByStatus(PrizeStatus.available),
              tone: gamGreen(context),
              selected: _statusTab == PrizeStatus.available,
              onTap: () =>
                  setState(() => _statusTab = PrizeStatus.available),
            ),
          ),
          Expanded(
            child: GamFlushTab(
              icon: LucideIcons.clock,
              label: 'Pendentes',
              count: _countByStatus(PrizeStatus.pending),
              tone: gamAmber(context),
              selected: _statusTab == PrizeStatus.pending,
              onTap: () => setState(() => _statusTab = PrizeStatus.pending),
            ),
          ),
          Expanded(
            child: GamFlushTab(
              icon: LucideIcons.check,
              label: 'Entregues',
              count: _countByStatus(PrizeStatus.delivered),
              tone: ThemeHelpers.textSecondaryColor(context),
              selected: _statusTab == PrizeStatus.delivered,
              onTap: () =>
                  setState(() => _statusTab = PrizeStatus.delivered),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Card de prêmio ────────────────────────────────────────────────────────

  Color _prizeStatusColor(BuildContext context, PrizeStatus status) {
    switch (status) {
      case PrizeStatus.available:
        return gamGreen(context);
      case PrizeStatus.pending:
        return gamAmber(context);
      case PrizeStatus.delivered:
      case PrizeStatus.unknown:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  Widget _prizeCard(BuildContext context, Prize prize) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _prizeStatusColor(context, prize.status);
    final rankTone = gamRankColor(context, prize.position);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green = gamGreen(context);
    final winner = prize.winnerUserName ?? prize.winnerTeamName;

    final showEdit = _canEdit && prize.canEdit;
    final showDeliver = _canDeliver && prize.canDeliver;
    final showDelete = _canDelete && prize.canDelete;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Posição em medalha
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    rankTone.withValues(alpha: isDark ? 0.3 : 0.18),
                    rankTone.withValues(alpha: isDark ? 0.12 : 0.06),
                  ]),
                  border:
                      Border.all(color: rankTone.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${prize.position}º',
                  style: TextStyle(
                    color: rankTone,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prize.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(LucideIcons.trophy,
                            size: 11, color: secondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            prize.competitionName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GamMiniPill(label: prize.status.label, color: tone),
            ],
          ),
          if ((prize.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              prize.description!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (prize.value > 0)
                Text(
                  _currency.format(prize.value),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: green,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              if (winner != null) ...[
                if (prize.value > 0) const SizedBox(width: 10),
                Flexible(
                  child: GamMiniPill(
                    label: winner,
                    color: gamBlue(context),
                    icon: LucideIcons.crown,
                  ),
                ),
              ],
              const Spacer(),
              if (showEdit)
                IconButton(
                  tooltip: 'Editar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openPrizeSheet(prize: prize),
                  icon: Icon(LucideIcons.pencil,
                      size: 16, color: secondary),
                ),
              if (showDelete)
                IconButton(
                  tooltip: 'Excluir',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deletePrize(prize),
                  icon: Icon(LucideIcons.trash2,
                      size: 16, color: gamDanger(context)),
                ),
              if (showDeliver) ...[
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () => _deliverPrize(prize),
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(LucideIcons.check, size: 14),
                  label: const Text(
                    'Entregar',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─── Skeleton fiel ─────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 108),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 90, height: 12, borderRadius: 999),
          const SizedBox(height: 14),
          const SkeletonText(width: 130, height: 34, borderRadius: 10),
          const SizedBox(height: 10),
          const SkeletonText(width: double.infinity, height: 13),
          const SizedBox(height: 14),
          Row(
            children: const [
              SkeletonBox(width: 100, height: 26, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 96, height: 26, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 96, height: 26, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(
              width: double.infinity, height: 44, borderRadius: 13),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 40, borderRadius: 8)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 40, borderRadius: 8)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 40, borderRadius: 8)),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(
                width: double.infinity, height: 130, borderRadius: 16),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
