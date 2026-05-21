import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/check_in_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Histórico de check-ins — visão editorial sem caixas centrais. Conteúdo
/// flui nas margens, com paleta emerald/teal/slate/indigo (zero vermelho
/// solto). Estados ativos em emerald; encerrados/atrasos em slate.
class CheckInListPage extends StatefulWidget {
  const CheckInListPage({super.key});

  @override
  State<CheckInListPage> createState() => _CheckInListPageState();
}

class _CheckInListPageState extends State<CheckInListPage> {
  bool _bootLoading = true;
  bool _loadingMore = false;
  String? _error;
  String _scope = 'mine';
  DateTime? _fromDate;
  DateTime? _toDate;
  CheckInListResponse _response = CheckInListResponse.empty;
  final ScrollController _scrollController = ScrollController();
  int _pagingGen = 0;
  Timer? _ticker;

  bool get _canSeeAll {
    final access = ModuleAccessService.instance;
    final role = access.userRole?.toLowerCase().trim() ?? '';
    if (role == 'master' || role == 'admin' || role == 'manager') return true;
    return access.hasPermission(AppPermissions.checkInManageSettings);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bootstrap();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _ticker?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadNextPage());
    }
  }

  Future<void> _bootstrap() async {
    final gen = ++_pagingGen;
    setState(() {
      _bootLoading = true;
      _error = null;
    });
    final res = await CheckInService.instance.listCheckIns(
      scope: _scope,
      fromDate: _fromDate?.toIso8601String(),
      toDate: _toDate?.toIso8601String(),
      page: 1,
      limit: 20,
    );
    if (!mounted || gen != _pagingGen) return;
    setState(() {
      _bootLoading = false;
      if (res.success && res.data != null) {
        _response = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar histórico';
      }
    });
  }

  Future<void> _refresh() async => _bootstrap();

  Future<void> _loadNextPage() async {
    if (_loadingMore || _bootLoading) return;
    if (_response.page >= _response.totalPages) return;
    setState(() => _loadingMore = true);
    final gen = _pagingGen;
    final res = await CheckInService.instance.listCheckIns(
      scope: _scope,
      fromDate: _fromDate?.toIso8601String(),
      toDate: _toDate?.toIso8601String(),
      page: _response.page + 1,
      limit: _response.limit > 0 ? _response.limit : 20,
    );
    if (!mounted || gen != _pagingGen) return;
    setState(() {
      _loadingMore = false;
      if (res.success && res.data != null) {
        final merged = <CheckIn>[
          ..._response.data,
          ...res.data!.data,
        ];
        _response = CheckInListResponse(
          data: merged,
          total: res.data!.total,
          page: res.data!.page,
          limit: res.data!.limit,
          totalPages: res.data!.totalPages,
        );
      }
    });
  }

  void _selectScope(String scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _response = CheckInListResponse.empty;
    });
    _bootstrap();
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      _bootstrap();
    }
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(
        () => _toDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        ),
      );
      _bootstrap();
    }
  }

  void _clearFilters() {
    if (_fromDate == null && _toDate == null) return;
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _bootstrap();
  }

  Future<void> _undoCheckIn(CheckIn checkIn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desfazer check-in'),
        content: Text(
          'Desfazer o check-in de ${checkIn.user?.name ?? 'usuário'}? '
          'A pessoa será notificada e precisará fazer um novo check-in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Desfazer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await CheckInService.instance.undoCheckIn(checkIn.id);
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Text(res.message ?? 'Erro ao desfazer check-in',
              style: const TextStyle(color: Colors.white)),
        ),
      );
      return;
    }
    setState(() {
      _response = CheckInListResponse(
        data: _response.data
            .map((c) => c.id == res.data!.id ? res.data! : c)
            .toList(),
        total: _response.total,
        page: _response.page,
        limit: _response.limit,
        totalPages: _response.totalPages,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            isDark ? AppColors.status.greenDarkMode : AppColors.status.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: const Text('Check-in desfeito',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Histórico de check-ins',
      showBottomNavigation: false,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      total: _response.total,
                      scope: _scope,
                      fromDate: _fromDate,
                      toDate: _toDate,
                    ),
                    const SizedBox(height: 14),
                    if (_canSeeAll) ...[
                      _ScopeSwitcher(
                        scope: _scope,
                        onChanged: _selectScope,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _FilterRow(
                      fromDate: _fromDate,
                      toDate: _toDate,
                      onPickFrom: _pickFromDate,
                      onPickTo: _pickToDate,
                      onClear: _clearFilters,
                    ),
                    const SizedBox(height: 18),
                    _ListSectionLabel(scope: _scope),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
            if (_bootLoading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: EdgeInsets.only(bottom: i < 4 ? 14 : 0),
                      child: SkeletonBox(height: 84, borderRadius: 12),
                    ),
                    childCount: 5,
                  ),
                ),
              )
            else if (_error != null && _response.data.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorState(message: _error!, onRetry: _refresh),
              )
            else if (_response.data.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(scope: _scope),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      if (i >= _response.data.length) {
                        return _loadingMore
                            ? const Padding(
                                padding:
                                    EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink();
                      }
                      final item = _response.data[i];
                      return _CheckInRow(
                        checkIn: item,
                        scope: _scope,
                        canUndo: _canSeeAll && item.isActive,
                        onUndo: () => _undoCheckIn(item),
                        isLast: i == _response.data.length - 1,
                      );
                    },
                    childCount: _response.data.length + 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Header — eyebrow + headline + chip do período (sem caixa) ───────────────

class _Header extends StatelessWidget {
  final int total;
  final String scope;
  final DateTime? fromDate;
  final DateTime? toDate;

  const _Header({
    required this.total,
    required this.scope,
    required this.fromDate,
    required this.toDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final periodLabel = _formatPeriod(fromDate, toDate);

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
                color: emerald,
                boxShadow: [
                  BoxShadow(
                    color: emerald.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'PRESENÇA · ${scope == 'all' ? 'EMPRESA' : 'EU'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: emerald,
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
                total == 1 ? 'registro' : 'registros',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: muted,
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
          periodLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static String _formatPeriod(DateTime? from, DateTime? to) {
    final fmt = DateFormat('dd/MM/yyyy');
    if (from != null && to != null) {
      return '${fmt.format(from)} → ${fmt.format(to)}';
    }
    if (from != null) return 'A partir de ${fmt.format(from)}';
    if (to != null) return 'Até ${fmt.format(to)}';
    return 'Todos os períodos';
  }
}

// ─── Scope Switcher — segmented control horizontal ───────────────────────────

class _ScopeSwitcher extends StatelessWidget {
  final String scope;
  final ValueChanged<String> onChanged;
  const _ScopeSwitcher({required this.scope, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final track = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ScopeSegment(
              icon: LucideIcons.user,
              label: 'Eu',
              selected: scope == 'mine',
              accent: emerald,
              onTap: () => onChanged('mine'),
            ),
          ),
          Expanded(
            child: _ScopeSegment(
              icon: LucideIcons.users,
              label: 'Empresa',
              selected: scope == 'all',
              accent: emerald,
              onTap: () => onChanged('all'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ScopeSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : ThemeHelpers.textColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: selected
                ? LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.82)],
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Filter row ──────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClear;

  const _FilterRow({
    required this.fromDate,
    required this.toDate,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilter = fromDate != null || toDate != null;
    return Row(
      children: [
        Expanded(
          child: _DateChip(
            label: fromDate == null
                ? 'De'
                : DateFormat('dd/MM/yyyy').format(fromDate!),
            icon: LucideIcons.calendarRange,
            onTap: onPickFrom,
            isPlaceholder: fromDate == null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DateChip(
            label: toDate == null
                ? 'Até'
                : DateFormat('dd/MM/yyyy').format(toDate!),
            icon: LucideIcons.calendarCheck,
            onTap: onPickTo,
            isPlaceholder: toDate == null,
          ),
        ),
        if (hasFilter) ...[
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onClear,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Icon(LucideIcons.x,
                    size: 14,
                    color: ThemeHelpers.textSecondaryColor(context)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPlaceholder;
  const _DateChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isPlaceholder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final color = isPlaceholder ? muted : ThemeHelpers.textColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
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

// ─── Section label da lista ─────────────────────────────────────────────────

class _ListSectionLabel extends StatelessWidget {
  final String scope;
  const _ListSectionLabel({required this.scope});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(LucideIcons.history, size: 13, color: muted),
        const SizedBox(width: 6),
        Text(
          scope == 'all' ? 'ÚLTIMAS DA EMPRESA' : 'MEUS ÚLTIMOS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: muted.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

// ─── Linha de check-in (sem caixa, separada por divider sutil) ───────────────

class _CheckInRow extends StatelessWidget {
  final CheckIn checkIn;
  final String scope;
  final bool canUndo;
  final VoidCallback onUndo;
  final bool isLast;

  const _CheckInRow({
    required this.checkIn,
    required this.scope,
    required this.canUndo,
    required this.onUndo,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final slate = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final active = checkIn.isActive;
    final accent = active ? emerald : slate;

    final entryTime =
        DateFormat('HH:mm').format(checkIn.checkedInAt.toLocal());
    final entryDate =
        DateFormat('dd/MM').format(checkIn.checkedInAt.toLocal());

    final exitLabel = checkIn.checkedOutAt != null
        ? DateFormat('HH:mm').format(checkIn.checkedOutAt!.toLocal())
        : DateFormat('HH:mm').format(checkIn.expiresAt.toLocal());
    final exitPrefix = checkIn.checkedOutAt != null ? 'Saída' : 'Expira';

    final duration =
        (checkIn.checkedOutAt ?? checkIn.expiresAt).difference(
      checkIn.checkedInAt,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Bolinha de status (verde pulsando se ativo) — substitui o
          // badge "Ativo/Encerrado" sem virar peso visual.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.55),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Conteúdo central (nome + entrada/saída/duração)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        scope == 'all' && checkIn.user?.name != null
                            ? checkIn.user!.name!
                            : (active ? 'Em andamento' : 'Encerrado'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.2,
                          height: 1.15,
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MicroInfo(
                      icon: LucideIcons.logIn,
                      text: '$entryTime · $entryDate',
                      color: emerald,
                    ),
                    _MicroInfo(
                      icon: active ? LucideIcons.timer : LucideIcons.logOut,
                      text: '$exitPrefix $exitLabel',
                      color: active ? emerald : muted,
                    ),
                    if (!active && checkIn.checkedOutByType != null)
                      _MicroInfo(
                        icon: LucideIcons.userCheck,
                        text: checkIn.checkedOutByLabel,
                        color: muted,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (canUndo) ...[
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onUndo,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.status.error.withValues(alpha: 0.28),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    LucideIcons.rotateCcw,
                    size: 14,
                    color: AppColors.status.error,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    if (d.isNegative) return '—';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
    }
    return '${d.inMinutes} min';
  }
}

class _MicroInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MicroInfo({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ─── Empty / Error ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String scope;
  const _EmptyState({required this.scope});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.history, size: 42, color: emerald),
          const SizedBox(height: 14),
          Text(
            scope == 'all'
                ? 'Sem check-ins na empresa ainda'
                : 'Você ainda não tem check-ins',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            scope == 'all'
                ? 'Quando alguém da empresa registrar um check-in, aparece aqui.'
                : 'Faça seu primeiro check-in pela tela anterior pra ver o histórico.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.cloudOff, color: danger, size: 38),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}
