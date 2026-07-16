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
import '../widgets/competition_card.dart';
import '../widgets/gamification_ui.dart';

final NumberFormat _currency =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final DateFormat _date = DateFormat('dd/MM/yyyy', 'pt_BR');

/// Prêmios de **uma competição** — lista por posição + adicionar/remover.
/// Paridade `AddPrizesPage.tsx` (`POST /competitions/:id/prizes`).
class AddPrizesPage extends StatefulWidget {
  final String competitionId;

  const AddPrizesPage({super.key, required this.competitionId});

  @override
  State<AddPrizesPage> createState() => _AddPrizesPageState();
}

class _AddPrizesPageState extends State<AddPrizesPage> {
  static const double _padH = 16;

  bool _loading = true;
  String? _error;
  Competition? _competition;

  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission('prize:create');
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission('prize:delete');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res =
        await CompetitionService.instance.getById(widget.competitionId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _competition = res.data;
      } else {
        _error = res.message ?? 'Erro ao carregar competição';
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

  List<CompetitionPrize> get _prizes {
    final list = List<CompetitionPrize>.from(_competition?.prizes ?? const []);
    list.sort((a, b) => a.position.compareTo(b.position));
    return list;
  }

  int get _nextPosition {
    final prizes = _prizes;
    if (prizes.isEmpty) return 1;
    return prizes.map((p) => p.position).reduce((a, b) => a > b ? a : b) + 1;
  }

  // ─── Ações ─────────────────────────────────────────────────────────────────

  Future<void> _removePrize(CompetitionPrize prize) async {
    final danger = gamDanger(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Remover prêmio?',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        content: Text(
          'O prêmio "${prize.name}" (${prize.position}º lugar) será removido '
          'da competição.',
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
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await CompetitionService.instance.removePrize(prize.id);
    if (!mounted) return;
    if (res.success) {
      _snack('Prêmio removido!');
      _load();
    } else {
      _snack(res.message ?? 'Erro ao remover prêmio', error: true);
    }
  }

  void _openAddPrizeSheet() {
    final positionController =
        TextEditingController(text: '$_nextPosition');
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final valueController = TextEditingController();
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

              if (name.isEmpty || position < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        const Text('Preencha posição e nome do prêmio!'),
                    backgroundColor: gamDanger(context),
                  ),
                );
                return;
              }
              if (_prizes.any((p) => p.position == position)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Já existe um prêmio para a posição $positionº!'),
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
              final res = await CompetitionService.instance.addPrize(
                widget.competitionId,
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
                _snack('Prêmio adicionado com sucesso!');
                _load();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(res.message ?? 'Erro ao adicionar prêmio'),
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
                          Icon(LucideIcons.gift, size: 17, color: amber),
                          const SizedBox(width: 8),
                          Text(
                            'Adicionar prêmio',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                label('Posição *'),
                                TextField(
                                  controller: positionController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3),
                                  ],
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: ThemeHelpers.textColor(context),
                                    fontWeight: FontWeight.w800,
                                  ),
                                  decoration: deco(hint: '1'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
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
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          ThemeHelpers.textColor(context)),
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
                              : const Icon(LucideIcons.plus, size: 16),
                          label: Text(
                            saving ? 'Adicionando…' : 'Adicionar prêmio',
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
      positionController.dispose();
      nameController.dispose();
      descriptionController.dispose();
      valueController.dispose();
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canCreate) {
      return const AppScaffold(
        title: 'Prêmios da Competição',
        showBottomNavigation: false,
        body: GamDeniedView(
          what: 'cadastro de prêmios',
          permission: 'prize:create',
        ),
      );
    }

    final accent = gamAccentColor(context);

    return AppScaffold(
      title: 'Prêmios da Competição',
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
          if (!_loading && _competition != null)
            Positioned(
              right: 16,
              bottom: 24,
              child: FloatingActionButton.extended(
                heroTag: 'add-prizes-fab',
                onPressed: _openAddPrizeSheet,
                backgroundColor: accent,
                foregroundColor: Colors.white,
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text(
                  'Adicionar prêmio',
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

    final competition = _competition!;
    final prizes = _prizes;
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final amber = gamAmber(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 10, _padH, 108),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero: competição ─────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: amber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'PREMIAÇÃO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: amber,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            competition.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GamMiniPill(
                label: competition.status.label,
                color: competitionStatusColor(context, competition.status),
                icon: competitionStatusIcon(competition.status),
              ),
              GamMiniPill(
                label: competition.type.label,
                color: competition.type == CompetitionType.team
                    ? gamPurple(context)
                    : competition.type == CompetitionType.mixed
                        ? gamBlue(context)
                        : gamAccentColor(context),
              ),
              GamMiniPill(
                label:
                    '${competition.startDate != null ? _date.format(competition.startDate!) : '—'}'
                    ' → '
                    '${competition.endDate != null ? _date.format(competition.endDate!) : '—'}',
                color: secondary,
                icon: LucideIcons.calendarRange,
              ),
            ],
          ),
          if ((competition.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              competition.description!.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 22),

          // ── Prêmios ──────────────────────────────────────────────────────
          GamSubsectionHeader(
            label: 'Prêmios cadastrados',
            icon: LucideIcons.gift,
            count: prizes.length,
          ),
          const SizedBox(height: 12),
          if (prizes.isEmpty)
            GamEmptyState(
              icon: LucideIcons.gift,
              title: 'Nenhum prêmio cadastrado',
              body: 'Adicione prêmios por posição para motivar os '
                  'participantes!',
              tone: amber,
              action: FilledButton.icon(
                onPressed: _openAddPrizeSheet,
                style: FilledButton.styleFrom(
                  backgroundColor: gamAccentColor(context),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Adicionar primeiro prêmio'),
              ),
            )
          else
            for (var i = 0; i < prizes.length; i++)
              _prizeTile(context, prizes[i])
                  .animate(key: ValueKey('prize-${prizes[i].id}'))
                  .fadeIn(
                    delay: Duration(milliseconds: 30 * i.clamp(0, 10)),
                    duration: 220.ms,
                  ),
        ],
      ),
    );
  }

  Widget _prizeTile(BuildContext context, CompetitionPrize prize) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = gamRankColor(context, prize.position);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green = gamGreen(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Medalha da posição
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                tone.withValues(alpha: isDark ? 0.3 : 0.18),
                tone.withValues(alpha: isDark ? 0.12 : 0.06),
              ]),
              border: Border.all(color: tone.withValues(alpha: 0.5)),
            ),
            alignment: Alignment.center,
            child: Text(
              '${prize.position}º',
              style: TextStyle(
                color: tone,
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
                if ((prize.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
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
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (prize.value != null && prize.value! > 0)
                      Text(
                        _currency.format(prize.value),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: green,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    if (prize.isDelivered)
                      GamMiniPill(
                        label: 'Entregue',
                        color: green,
                        icon: LucideIcons.check,
                      ),
                    if ((prize.winnerUserName ?? prize.winnerTeamName) !=
                        null)
                      GamMiniPill(
                        label:
                            prize.winnerUserName ?? prize.winnerTeamName!,
                        color: gamBlue(context),
                        icon: LucideIcons.crown,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_canDelete && !prize.isDelivered) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Remover prêmio',
              visualDensity: VisualDensity.compact,
              onPressed: () => _removePrize(prize),
              icon: Icon(LucideIcons.trash2,
                  size: 16, color: gamDanger(context)),
            ),
          ],
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
          const SkeletonText(width: 110, height: 11, borderRadius: 999),
          const SizedBox(height: 12),
          const SkeletonText(width: 240, height: 22, borderRadius: 8),
          const SizedBox(height: 12),
          Row(
            children: const [
              SkeletonBox(width: 90, height: 24, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 80, height: 24, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 140, height: 24, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 26),
          const SkeletonText(width: 180, height: 11),
          const SizedBox(height: 14),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(
                width: double.infinity, height: 84, borderRadius: 16),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
