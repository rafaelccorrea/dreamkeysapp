import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/platform_billing_model.dart';
import '../services/platform_admin_service.dart';
import '../widgets/platform_admin_ui.dart';

final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
final DateFormat _dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

/// **Cobrança do sistema** (Master · `/master/billing`) — paridade compacta
/// com a `BillingControlPage` do web: flag global de cobrança (com dias de
/// graça), busca, segmentação Todas/Gerenciadas/Cobrando/Comuns e um card por
/// conta com regime, situação e ações (toggle "Cobrar" com confirmação e
/// agendamento do fim do trial via date picker).
///
/// Cor por SITUAÇÃO (mesma semântica do web): âmbar = master, céu = comum
/// (assina), rosa = cobrando/bloqueada, esmeralda = gerenciada livre.
class MasterBillingPage extends StatefulWidget {
  const MasterBillingPage({super.key});

  @override
  State<MasterBillingPage> createState() => _MasterBillingPageState();
}

class _MasterBillingPageState extends State<MasterBillingPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  // Config global
  PlatformSettings? _settings;
  bool _settingsLoading = true;
  bool _savingFlag = false;
  int _graceDays = 10;

  // Contas
  List<OwnerAccount> _accounts = const [];
  bool _accountsLoading = true;
  bool _accountsLoaded = false;
  String? _accountsError;
  String? _busyAccountId;

  BillingAccountFilter _filter = BillingAccountFilter.all;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAccounts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    setState(() => _settingsLoading = true);
    final res = await PlatformAdminService.instance.getSettings();
    if (!mounted) return;
    setState(() {
      _settingsLoading = false;
      if (res.success && res.data != null) {
        _settings = res.data;
        _graceDays = res.data!.billingGraceDays;
      }
    });
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _accountsLoading = true;
      _accountsError = null;
    });
    final res = await PlatformAdminService.instance
        .listAccounts(search: _appliedSearch);
    if (!mounted) return;
    setState(() {
      _accountsLoading = false;
      _accountsLoaded = true;
      if (res.success && res.data != null) {
        _accounts = res.data!;
      } else {
        _accountsError = res.message ?? 'Erro ao listar as contas';
      }
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadSettings(), _loadAccounts()]);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
      _loadAccounts();
    });
  }

  // ─── Estatísticas / filtro (mesma régua do web) ──────────────────────────

  ({int total, int managedFree, int blocked, int common}) get _stats {
    final nonMaster = _accounts.where((a) => !a.isMaster).toList();
    final managed = nonMaster.where((a) => a.isManaged).toList();
    final blocked = managed.where((a) => a.isBlocked).length;
    return (
      total: nonMaster.length,
      managedFree: managed.length - blocked,
      blocked: blocked,
      common: nonMaster.where((a) => !a.isManaged).length,
    );
  }

  List<OwnerAccount> get _visibleAccounts {
    return _accounts.where((a) {
      switch (_filter) {
        case BillingAccountFilter.all:
          return true;
        case BillingAccountFilter.managed:
          return !a.isMaster && a.isManaged && !a.isBlocked;
        case BillingAccountFilter.blocked:
          return !a.isMaster && a.isBlocked;
        case BillingAccountFilter.common:
          return !a.isMaster && !a.isManaged;
      }
    }).toList();
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<bool> _confirm({
    required String title,
    required String message,
    required String okLabel,
  }) async {
    final danger = PlatformAdminUi.rose(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: Text(message, style: const TextStyle(height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: danger),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applyEnforcement(bool enabled) async {
    setState(() => _savingFlag = true);
    final res = await PlatformAdminService.instance
        .setBillingEnforcement(enabled, graceDays: _graceDays);
    if (!mounted) return;
    setState(() {
      _savingFlag = false;
      if (res.success && res.data != null) _settings = res.data;
    });
    _toast(
      res.success
          ? (enabled
              ? 'Cobrança LIGADA. Contas gerenciadas entram no período de graça.'
              : 'Cobrança DESLIGADA. Contas gerenciadas seguem isentas.')
          : (res.message ?? 'Erro ao atualizar a flag de cobrança'),
    );
  }

  Future<void> _toggleEnforcement(bool checked) async {
    if (checked) {
      final ok = await _confirm(
        title: 'Ligar a cobrança do sistema?',
        message:
            'Todas as contas gerenciadas que ainda não assinaram terão $_graceDays '
            'dia(s) de graça e depois serão bloqueadas até assinar no Asaas. '
            'Contas comuns já precisam de assinatura. Deseja continuar?',
        okLabel: 'Ligar cobrança',
      );
      if (!ok) return;
      await _applyEnforcement(true);
    } else {
      await _applyEnforcement(false);
    }
  }

  Future<void> _saveGraceDays() async {
    final enabled = _settings?.billingEnforcementEnabled ?? false;
    setState(() => _savingFlag = true);
    final res = await PlatformAdminService.instance
        .setBillingEnforcement(enabled, graceDays: _graceDays);
    if (!mounted) return;
    setState(() {
      _savingFlag = false;
      if (res.success && res.data != null) _settings = res.data;
    });
    _toast(res.success
        ? 'Parâmetros salvos.'
        : (res.message ?? 'Erro ao salvar os parâmetros'));
  }

  Future<void> _changeRegime(OwnerAccount account, BillingRegime regime) async {
    if (regime == account.billingRegime) return;
    setState(() => _busyAccountId = account.id);
    final res = await PlatformAdminService.instance
        .setAccountBillingRegime(account.id, regime);
    if (!mounted) return;
    setState(() => _busyAccountId = null);
    _toast(res.success
        ? '${account.name} agora é conta ${regime == BillingRegime.managed ? 'Gerenciada (tech)' : 'Comum (assina)'}.'
        : (res.message ?? 'Erro ao alterar o regime da conta'));
    if (res.success) await _loadAccounts();
  }

  /// Flag por conta: cobrar=true → `until = agora` (bloqueia até assinar);
  /// cobrar=false → `until = null` (liberada por tempo indefinido).
  Future<void> _applyAccountBilling(OwnerAccount account, bool cobrar) async {
    setState(() => _busyAccountId = account.id);
    final res = await PlatformAdminService.instance
        .setManagedUntil(account.id, cobrar ? DateTime.now() : null);
    if (!mounted) return;
    setState(() => _busyAccountId = null);
    _toast(res.success
        ? (cobrar
            ? 'Cobrança ativada para ${account.name} — precisa assinar.'
            : '${account.name} liberada (isenta por tempo indefinido).')
        : (res.message ?? 'Erro ao alterar a cobrança da conta'));
    if (res.success) await _loadAccounts();
  }

  Future<void> _changeAccountBilling(OwnerAccount account, bool cobrar) async {
    if (cobrar) {
      // Bloquear é destrutivo (corta o acesso da empresa toda) → confirmar.
      final ok = await _confirm(
        title: 'Cobrar de ${account.name}?',
        message:
            'A conta perde a isenção agora e o titular precisará assinar para '
            'continuar usando — o acesso da equipe fica suspenso até a '
            'assinatura. Deseja continuar?',
        okLabel: 'Cobrar agora',
      );
      if (!ok) return;
      await _applyAccountBilling(account, true);
    } else {
      await _applyAccountBilling(account, false);
    }
  }

  Future<void> _openScheduleSheet(OwnerAccount account) async {
    final accent = PlatformAdminUi.violet(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _ScheduleTrialSheet(
        account: account,
        accent: accent,
        onSave: (until) async {
          final res = await PlatformAdminService.instance
              .setManagedUntil(account.id, until);
          if (!mounted) return false;
          _toast(res.success
              ? (until != null
                  ? 'Fim do trial de ${account.name} agendado para ${_dateFmt.format(until.toLocal())}.'
                  : 'Prazo removido — ${account.name} fica livre por tempo indefinido.')
              : (res.message ?? 'Erro ao agendar o fim do trial'));
          if (res.success) await _loadAccounts();
          return res.success;
        },
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!PlatformAdminUi.isMasterUser) {
      return const AppScaffold(
        title: 'Cobrança do sistema',
        showBottomNavigation: false,
        body: MasterDeniedView(),
      );
    }
    final accent = PlatformAdminUi.violet(context);
    return AppScaffold(
      title: 'Cobrança do sistema',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: accent,
        onRefresh: _refreshAll,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(context, accent),
                        const SizedBox(height: 16),
                        _buildFlagCard(context),
                        const SizedBox(height: _kSectionGap),
                        MasterSearchField(
                          controller: _searchController,
                          hint: 'Buscar por nome ou e-mail…',
                          accent: accent,
                          onChanged: _onSearchChanged,
                        ),
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
                    child: _buildActivePanel(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, Color accent) {
    final stats = _stats;
    final emerald = PlatformAdminUi.emerald(context);
    final rose = PlatformAdminUi.rose(context);
    final sky = PlatformAdminUi.sky(context);
    final enforcementOn = _settings?.billingEnforcementEnabled ?? false;

    return MasterHero(
      eyebrow: 'MASTER · PLATAFORMA',
      accent: accent,
      dotColor: enforcementOn ? rose : emerald,
      countText: '${stats.total}',
      unitText: stats.total == 1 ? 'conta titular' : 'contas titulares',
      subtitle: enforcementOn
          ? 'Cobrança global LIGADA — gerenciadas sem assinatura entram no período de graça.'
          : 'Contas gerenciadas (time tech) usam sem assinar; comuns precisam assinar antes de usar.',
      loading: _accountsLoading && !_accountsLoaded,
      kpis: [
        MasterHeroKpi(
          icon: LucideIcons.shieldCheck,
          label: 'GERENCIADAS',
          value: '${stats.managedFree}',
          sub: 'livres agora',
          tone: emerald,
        ),
        MasterHeroKpi(
          icon: LucideIcons.ban,
          label: 'COBRANDO',
          value: '${stats.blocked}',
          sub: 'bloqueadas',
          tone: rose,
        ),
        MasterHeroKpi(
          icon: LucideIcons.creditCard,
          label: 'COMUNS',
          value: '${stats.common}',
          sub: 'assinam',
          tone: sky,
        ),
      ],
    );
  }

  // ─── Flag global de cobrança ─────────────────────────────────────────────

  Widget _buildFlagCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final on = _settings?.billingEnforcementEnabled ?? false;
    final tone =
        on ? PlatformAdminUi.rose(context) : PlatformAdminUi.emerald(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final dirty = _settings != null && _graceDays != _settings!.billingGraceDays;

    if (_settingsLoading && _settings == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(18),
          boxShadow: ThemeHelpers.cardShadow(context),
        ),
        child: Row(
          children: const [
            SkeletonBox(width: 44, height: 44, borderRadius: 14),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 140, height: 15),
                  SizedBox(height: 8),
                  SkeletonText(width: double.infinity, height: 12),
                ],
              ),
            ),
            SizedBox(width: 12),
            SkeletonBox(width: 46, height: 28, borderRadius: 999),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
        border: Border.all(
          color: tone.withValues(alpha: isDark ? 0.28 : 0.18),
        ),
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
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Icon(
                  on ? LucideIcons.zap : LucideIcons.shieldCheck,
                  color: tone,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            on ? 'Cobrança ligada' : 'Cobrança desligada',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        MasterMiniPill(
                          label: on ? 'Ativa' : 'Inativa',
                          color: tone,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      on
                          ? 'Ligada em ${_settings?.billingEnforcementEnabledAt != null ? _dateTimeFmt.format(_settings!.billingEnforcementEnabledAt!.toLocal()) : '—'}'
                          : 'Gerenciadas usam o sistema sem assinar até você ligar.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: on,
                activeTrackColor: tone,
                onChanged: _savingFlag ? null : _toggleEnforcement,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(LucideIcons.hourglass, size: 14, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dias de graça após ligar',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _GraceStepper(
                value: _graceDays,
                enabled: !_savingFlag,
                onChanged: (v) => setState(() => _graceDays = v),
              ),
              if (dirty) ...[
                const SizedBox(width: 8),
                _savingFlag
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _saveGraceDays,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: PlatformAdminUi.violet(context),
                        ),
                        child: const Text(
                          'Salvar',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─── Abas flush ──────────────────────────────────────────────────────────

  Color _filterTone(BuildContext context, BillingAccountFilter f) {
    switch (f) {
      case BillingAccountFilter.all:
        return PlatformAdminUi.violet(context);
      case BillingAccountFilter.managed:
        return PlatformAdminUi.emerald(context);
      case BillingAccountFilter.blocked:
        return PlatformAdminUi.rose(context);
      case BillingAccountFilter.common:
        return PlatformAdminUi.sky(context);
    }
  }

  IconData _filterIcon(BillingAccountFilter f) {
    switch (f) {
      case BillingAccountFilter.all:
        return LucideIcons.users;
      case BillingAccountFilter.managed:
        return LucideIcons.shieldCheck;
      case BillingAccountFilter.blocked:
        return LucideIcons.ban;
      case BillingAccountFilter.common:
        return LucideIcons.creditCard;
    }
  }

  String _filterLabel(BillingAccountFilter f) {
    switch (f) {
      case BillingAccountFilter.all:
        return 'Todas';
      case BillingAccountFilter.managed:
        return 'Gerenciadas';
      case BillingAccountFilter.blocked:
        return 'Cobrando';
      case BillingAccountFilter.common:
        return 'Comuns';
    }
  }

  int _filterCount(BillingAccountFilter f) {
    final stats = _stats;
    switch (f) {
      case BillingAccountFilter.all:
        return stats.total;
      case BillingAccountFilter.managed:
        return stats.managedFree;
      case BillingAccountFilter.blocked:
        return stats.blocked;
      case BillingAccountFilter.common:
        return stats.common;
    }
  }

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          for (final f in BillingAccountFilter.values)
            Expanded(
              child: MasterFlushTab(
                icon: _filterIcon(f),
                label: _filterLabel(f),
                count: _filterCount(f),
                tone: _filterTone(context, f),
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      BillingAccountFilter f) {
    switch (f) {
      case BillingAccountFilter.all:
        return (
          icon: LucideIcons.users,
          eyebrow: 'TODAS',
          title: 'Contas e regime de cobrança',
          hint: 'Titulares da plataforma — mude regime, cobre ou agende o trial.',
        );
      case BillingAccountFilter.managed:
        return (
          icon: LucideIcons.shieldCheck,
          eyebrow: 'GERENCIADAS',
          title: 'Livres (time tech)',
          hint: 'Usam o sistema sem assinar, por prazo definido ou indefinido.',
        );
      case BillingAccountFilter.blocked:
        return (
          icon: LucideIcons.ban,
          eyebrow: 'COBRANDO',
          title: 'Bloqueadas até assinar',
          hint: 'Perderam a isenção — o acesso volta quando assinarem no Asaas.',
        );
      case BillingAccountFilter.common:
        return (
          icon: LucideIcons.creditCard,
          eyebrow: 'COMUNS',
          title: 'Assinam para usar',
          hint: 'Contas no fluxo normal de assinatura, sem isenção da plataforma.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    final tone = _filterTone(context, _filter);
    final meta = _panelMeta(_filter);
    final visible = _visibleAccounts;

    Widget child;
    if (_accountsLoading && _accounts.isEmpty) {
      child = const MasterCardSkeleton(rows: 4);
    } else if (_accountsError != null && _accounts.isEmpty) {
      child = MasterErrorState(message: _accountsError!, onRetry: _loadAccounts);
    } else if (visible.isEmpty) {
      final hasSearch = _appliedSearch.isNotEmpty;
      child = MasterEmptyState(
        icon: hasSearch ? LucideIcons.searchX : LucideIcons.userX,
        title: hasSearch ? 'Nada encontrado' : 'Nenhuma conta aqui',
        body: hasSearch
            ? 'Nenhuma conta corresponde a "$_appliedSearch".'
            : 'Não há contas neste segmento no momento.',
        tone: tone,
      );
    } else {
      var animIndex = 0;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final account in visible)
            _AccountCard(
              key: ValueKey('acc-${account.id}'),
              account: account,
              busy: _busyAccountId == account.id,
              onChangeRegime: (r) => _changeRegime(account, r),
              onToggleBilling: (cobrar) =>
                  _changeAccountBilling(account, cobrar),
              onSchedule: () => _openScheduleSheet(account),
            ).animate(key: ValueKey('acc-anim-${account.id}')).fadeIn(
                  delay:
                      Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                  duration: 220.ms,
                ),
        ],
      );
    }

    return Column(
      key: ValueKey('panel-${_filter.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MasterPanelHeader(
          icon: meta.icon,
          eyebrow: meta.eyebrow,
          title: meta.title,
          hint: meta.hint,
          tone: tone,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_filter.name}')).fadeIn(duration: 240.ms);
  }
}

// ─── Stepper de dias de graça ────────────────────────────────────────────────

class _GraceStepper extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _GraceStepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final border = ThemeHelpers.borderColor(context);

    Widget btn(IconData icon, VoidCallback? onTap) {
      return InkResponse(
        radius: 16,
        onTap: enabled ? onTap : null,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: border),
          ),
          child: Icon(icon, size: 14, color: secondary),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(LucideIcons.minus, value > 0 ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
        btn(LucideIcons.plus, () => onChanged(value + 1)),
      ],
    );
  }
}

// ─── Card de conta ───────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final OwnerAccount account;
  final bool busy;
  final ValueChanged<BillingRegime> onChangeRegime;
  final ValueChanged<bool> onToggleBilling;
  final VoidCallback onSchedule;

  const _AccountCard({
    super.key,
    required this.account,
    required this.busy,
    required this.onChangeRegime,
    required this.onToggleBilling,
    required this.onSchedule,
  });

  Color _tone(BuildContext context) {
    if (account.isMaster) return PlatformAdminUi.amber(context);
    if (!account.isManaged) return PlatformAdminUi.sky(context);
    if (account.isBlocked) return PlatformAdminUi.rose(context);
    return PlatformAdminUi.emerald(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: busy ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MasterInitialsAvatar(initials: account.initials, tone: tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                MasterMiniPill(
                  label: account.role.toUpperCase(),
                  color: tone,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Situação (pill semântica, mesma leitura do web)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (account.isMaster)
                  MasterMiniPill(
                    label: 'Sempre liberado',
                    color: tone,
                    icon: LucideIcons.shieldCheck,
                  )
                else if (!account.isManaged)
                  MasterMiniPill(
                    label: 'Precisa assinar',
                    color: tone,
                    icon: LucideIcons.creditCard,
                  )
                else if (account.isBlocked)
                  MasterMiniPill(
                    label: 'Cobrança ativa',
                    color: tone,
                    icon: LucideIcons.ban,
                  )
                else
                  MasterMiniPill(
                    label: account.managedBillingUntil != null
                        ? 'Livre até ${_dateFmt.format(account.managedBillingUntil!.toLocal())}'
                        : 'Livre (indefinido)',
                    color: tone,
                    icon: LucideIcons.shieldCheck,
                  ),
                if (!account.isMaster)
                  _RegimeToggle(
                    regime: account.billingRegime,
                    tone: tone,
                    enabled: !busy,
                    onChanged: onChangeRegime,
                  ),
              ],
            ),
            if (!account.isMaster && account.isManaged) ...[
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.7),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    LucideIcons.ban,
                    size: 14,
                    color: account.isBlocked
                        ? PlatformAdminUi.rose(context)
                        : secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Cobrar',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: account.isBlocked
                          ? PlatformAdminUi.rose(context)
                          : secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch.adaptive(
                      value: account.isBlocked,
                      activeTrackColor: PlatformAdminUi.rose(context),
                      onChanged:
                          busy ? null : (v) => onToggleBilling(v),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: busy ? null : onSchedule,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: PlatformAdminUi.violet(context),
                      backgroundColor: PlatformAdminUi.violet(context)
                          .withValues(alpha: isDark ? 0.14 : 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(LucideIcons.calendarClock, size: 15),
                    label: const Text(
                      'Agendar',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Toggle Gerenciada/Comum ─────────────────────────────────────────────────

class _RegimeToggle extends StatelessWidget {
  final BillingRegime regime;
  final Color tone;
  final bool enabled;
  final ValueChanged<BillingRegime> onChanged;

  const _RegimeToggle({
    required this.regime,
    required this.tone,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    Widget option(String label, bool active, VoidCallback onTap) {
      return InkWell(
        onTap: enabled && !active ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? tone : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active
                  ? Colors.white
                  : ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option('Gerenciada', regime == BillingRegime.managed,
              () => onChanged(BillingRegime.managed)),
          option('Comum', regime == BillingRegime.selfServe,
              () => onChanged(BillingRegime.selfServe)),
        ],
      ),
    );
  }
}

// ─── Sheet: agendar fim do trial ─────────────────────────────────────────────

class _ScheduleTrialSheet extends StatefulWidget {
  final OwnerAccount account;
  final Color accent;
  final Future<bool> Function(DateTime? until) onSave;

  const _ScheduleTrialSheet({
    required this.account,
    required this.accent,
    required this.onSave,
  });

  @override
  State<_ScheduleTrialSheet> createState() => _ScheduleTrialSheetState();
}

class _ScheduleTrialSheetState extends State<_ScheduleTrialSheet> {
  DateTime? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final until = widget.account.managedBillingUntil;
    if (until != null && until.isAfter(DateTime.now())) {
      _selected = until.toLocal();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: _selected != null && _selected!.isAfter(now)
          ? _selected!
          : now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: 'Fim do trial',
      confirmText: 'Selecionar',
      cancelText: 'Cancelar',
    );
    if (picked == null || !mounted) return;
    setState(() => _selected = picked);
  }

  Future<void> _save({required bool remove}) async {
    if (_saving) return;
    setState(() => _saving = true);
    // Data escolhida = fim do dia; null = sem prazo (indefinido).
    final until = remove
        ? null
        : (_selected != null
            ? DateTime(_selected!.year, _selected!.month, _selected!.day, 23,
                59, 59)
            : null);
    if (!remove && until == null) {
      setState(() => _saving = false);
      return;
    }
    final ok = await widget.onSave(until);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accent;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasCurrent = widget.account.managedBillingUntil != null;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.3)),
                      ),
                      child: Icon(LucideIcons.calendarClock,
                          color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agendar fim do trial',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Defina a data em que o período gratuito termina. O titular '
                  'recebe avisos automáticos 7, 3 e 1 dia antes e, ao fim, o '
                  'acesso é bloqueado até assinar. Sem data = livre por tempo '
                  'indefinido.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _saving ? null : _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                      color: accent.withValues(alpha: isDark ? 0.1 : 0.05),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.calendar, size: 17, color: accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selected != null
                                ? _dateFmt.format(_selected!)
                                : 'Selecionar a data do fim do trial',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _selected != null
                                  ? ThemeHelpers.textColor(context)
                                  : secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(LucideIcons.chevronDown,
                            size: 16, color: secondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (hasCurrent)
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _saving ? null : () => _save(remove: true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: secondary,
                            side: BorderSide(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text(
                            'Remover prazo',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    if (hasCurrent) const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving || _selected == null
                            ? null
                            : () => _save(remove: false),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Salvar agendamento',
                                style:
                                    TextStyle(fontWeight: FontWeight.w900),
                              ),
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
}
