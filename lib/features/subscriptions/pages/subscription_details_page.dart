import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/subscription_models.dart';
import '../services/subscriptions_service.dart';
import '../widgets/subscription_widgets.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);
final DateFormat _date = DateFormat('dd/MM/yyyy', 'pt_BR');

/// **Detalhe de assinatura — gestão master**
/// (`/subscription/manage/:id`) — paridade com o `SubscriptionDetailsPage`
/// do web (rota MasterRoute `/subscription-management/:subscriptionId`).
///
/// A lista passa o [AdminSubscriptionItem] via `arguments` (como o web faz
/// via `location.state`); o uso detalhado vem de
/// `GET /subscriptions/admin/:id/usage`. Ações master: estender vigência,
/// suspender/reativar, cancelar e editar observações/término.
class SubscriptionDetailsPage extends StatefulWidget {
  const SubscriptionDetailsPage({
    super.key,
    required this.subscriptionId,
    this.initialItem,
  });

  final String subscriptionId;
  final AdminSubscriptionItem? initialItem;

  @override
  State<SubscriptionDetailsPage> createState() =>
      _SubscriptionDetailsPageState();
}

class _SubscriptionDetailsPageState extends State<SubscriptionDetailsPage> {
  static const double _kPadH = 16;

  AdminSubscriptionItem? _item;
  SubscriptionUsage? _usage;
  bool _loadingUsage = true;
  String? _usageError;
  bool _acting = false;

  bool get _isMaster =>
      ModuleAccessService.instance.userRole?.toLowerCase().trim() == 'master';

  String get _status => _usage?.status.trim().isNotEmpty == true
      ? _usage!.status
      : (_item?.status ?? 'inactive');

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    if (_isMaster) _loadUsage();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Future<void> _loadUsage() async {
    setState(() {
      _loadingUsage = true;
      _usageError = null;
    });
    final res = await SubscriptionsService.instance
        .getSubscriptionUsageById(widget.subscriptionId);
    if (!mounted) return;
    setState(() {
      _loadingUsage = false;
      if (res.success && res.data != null) {
        _usage = res.data;
      } else {
        _usageError = res.message ?? 'Erro ao carregar uso da assinatura';
      }
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : null,
      ),
    );
  }

  // ─── Ações master ─────────────────────────────────────────────────────────

  Future<void> _extend(int days, String reason) async {
    setState(() => _acting = true);
    final res = await SubscriptionsService.instance.extendSubscription(
      widget.subscriptionId,
      days: days,
      reason: reason.trim().isEmpty ? null : reason.trim(),
    );
    if (!mounted) return;
    setState(() => _acting = false);
    if (res.success) {
      _snack('Assinatura estendida por $days dia${days == 1 ? '' : 's'}.');
      _loadUsage();
    } else {
      _snack(res.message ?? 'Erro ao estender assinatura', error: true);
    }
  }

  Future<void> _manage(String action, String reason, String notes) async {
    setState(() => _acting = true);
    final res = await SubscriptionsService.instance.manageSubscription(
      subscriptionId: widget.subscriptionId,
      action: action,
      reason: reason,
      notes: notes,
    );
    if (!mounted) return;
    setState(() => _acting = false);
    if (res.success) {
      _snack(switch (action) {
        'activate' => 'Assinatura reativada.',
        'suspend' => 'Assinatura suspensa.',
        _ => 'Assinatura cancelada.',
      });
      _loadUsage();
    } else {
      _snack(res.message ?? 'Erro ao executar ação', error: true);
    }
  }

  Future<void> _update({String? notes, DateTime? endDate}) async {
    setState(() => _acting = true);
    final res = await SubscriptionsService.instance.updateSubscription(
      widget.subscriptionId,
      notes: notes,
      endDate: endDate,
    );
    if (!mounted) return;
    setState(() => _acting = false);
    if (res.success) {
      _snack('Assinatura atualizada.');
      _loadUsage();
    } else {
      _snack(res.message ?? 'Erro ao atualizar assinatura', error: true);
    }
  }

  // ─── Sheets ───────────────────────────────────────────────────────────────

  void _openExtendSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    _showActionSheet(
      _ExtendSheet(
        tone: blue,
        onConfirm: (days, reason) => _extend(days, reason),
      ),
    );
  }

  void _openManageSheet(String action) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (tone, title, hint, cta, icon) = switch (action) {
      'activate' => (
          isDark ? AppColors.status.greenDarkMode : AppColors.status.green,
          'Reativar assinatura',
          'A conta volta a ter acesso imediato ao sistema.',
          'Reativar',
          LucideIcons.play,
        ),
      'suspend' => (
          isDark ? AppColors.status.warningDarkMode : AppColors.status.warning,
          'Suspender assinatura',
          'O acesso é pausado até a reativação — nada é excluído.',
          'Suspender',
          LucideIcons.pause,
        ),
      _ => (
          isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
          'Cancelar assinatura',
          'Encerra a assinatura em definitivo. Esta ação notifica o titular.',
          'Cancelar assinatura',
          LucideIcons.ban,
        ),
    };
    _showActionSheet(
      _ManageSheet(
        tone: tone,
        title: title,
        hint: hint,
        cta: cta,
        icon: icon,
        onConfirm: (reason, notes) => _manage(action, reason, notes),
      ),
    );
  }

  void _openEditSheet() {
    _showActionSheet(
      _EditSheet(
        tone: _accent(context),
        initialNotes: _item?.notes ?? '',
        initialEndDate: _usage?.endDate ?? _item?.endDate,
        onConfirm: (notes, endDate) => _update(notes: notes, endDate: endDate),
      ),
    );
  }

  void _showActionSheet(Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => sheet,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isMaster) {
      return const AppScaffold(
        title: 'Assinatura',
        showBottomNavigation: false,
        body: SubsDeniedView(
          message: 'O detalhe de assinaturas é exclusivo do perfil master.',
        ),
      );
    }

    return AppScaffold(
      title: 'Assinatura',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: _loadUsage,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_kPadH, 10, _kPadH, 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 20),
                    _buildUsageSection(context),
                    const SizedBox(height: 20),
                    _buildInfoSection(context),
                    const SizedBox(height: 20),
                    _buildActionsSection(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = subscriptionStatusColor(context, _status);

    final planName = _usage?.planName.trim().isNotEmpty == true
        ? _usage!.planName
        : (_item?.planName ?? 'Assinatura');
    final planType = _usage?.planType.trim().isNotEmpty == true
        ? _usage!.planType
        : (_item?.planType ?? '');
    final price = _usage?.monthlyPrice ?? _item?.price ?? 0;
    final userLine = [
      if ((_item?.userName ?? '').trim().isNotEmpty && _item?.userName != '—')
        _item!.userName.trim(),
      if ((_item?.userEmail ?? '').trim().isNotEmpty) _item!.userEmail.trim(),
    ].join(' · ');

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
                color: tone,
                boxShadow: [
                  BoxShadow(
                    color: tone.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'GESTÃO MASTER',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _accent(context),
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
              ),
              child: Icon(planTypeIcon(planType), color: tone, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    planName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.4,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SubsStatusPill(status: _status, compact: true),
                      Text(
                        '${_money.format(price)}/mês',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  if (userLine.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(LucideIcons.userRound,
                            size: 12, color: secondary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            userLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUsageSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    Widget child;
    if (_loadingUsage) {
      child = Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            const SkeletonText(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            const SkeletonBox(height: 6, borderRadius: 999),
            const SizedBox(height: 16),
          ],
        ],
      );
    } else if (_usageError != null) {
      child = SubsErrorState(message: _usageError!, onRetry: _loadUsage);
    } else if (_usage == null) {
      child = SubsEmptyState(
        icon: LucideIcons.gauge,
        title: 'Uso indisponível',
        body: 'Esta assinatura não retornou métricas de uso.',
        tone: blue,
      );
    } else {
      final u = _usage!;
      final meters = <Widget>[
        if (u.companies != null)
          UsageMeterTile(
            icon: LucideIcons.building2,
            label: 'Empresas',
            metric: u.companies!,
          ),
        if (u.users != null)
          UsageMeterTile(
            icon: LucideIcons.users,
            label: 'Usuários',
            metric: u.users!,
          ),
        if (u.properties != null)
          UsageMeterTile(
            icon: LucideIcons.house,
            label: 'Imóveis',
            metric: u.properties!,
          ),
        if (u.storage != null)
          UsageMeterTile(
            icon: LucideIcons.hardDrive,
            label: 'Armazenamento',
            metric: u.storage!,
            unit: 'GB',
          ),
        if (u.apiCalls != null)
          UsageMeterTile(
            icon: LucideIcons.zap,
            label: 'Chamadas de API no mês',
            metric: u.apiCalls!,
          ),
        if (u.aiTokens != null)
          UsageMeterTile(
            icon: LucideIcons.brainCircuit,
            label: 'Tokens de IA',
            metric: u.aiTokens!,
          ),
      ];
      child = meters.isEmpty
          ? SubsEmptyState(
              icon: LucideIcons.gauge,
              title: 'Sem métricas',
              body: 'O plano desta conta não expõe limites mensuráveis.',
              tone: blue,
            )
          : Column(children: meters);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SubsPanelHeader(
          icon: LucideIcons.gauge,
          eyebrow: 'CONSUMO',
          title: 'Uso e limites',
          hint: 'Quanto do plano esta conta já consumiu.',
          tone: blue,
        ),
        const SizedBox(height: 10),
        child,
      ],
    ).animate().fadeIn(duration: 240.ms);
  }

  Widget _buildInfoSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final u = _usage;
    final item = _item;

    final start = u?.startDate ?? item?.startDate;
    final end = u?.endDate ?? item?.endDate;
    final notes = item?.notes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SubsPanelHeader(
          icon: LucideIcons.fileText,
          eyebrow: 'CONTRATO',
          title: 'Informações da assinatura',
          hint: 'Vigência, cobrança e observações internas.',
          tone: purple,
        ),
        const SizedBox(height: 10),
        if (start != null)
          SubsInfoRow(
            label: 'Início da vigência',
            value: _date.format(start.toLocal()),
            icon: LucideIcons.calendarPlus,
          ),
        if (end != null)
          SubsInfoRow(
            label: 'Término da vigência',
            value: _date.format(end.toLocal()),
            icon: LucideIcons.calendarClock,
            emphasize: true,
          ),
        if (u != null && u.endDate != null)
          SubsInfoRow(
            label: 'Dias restantes',
            value: '${u.daysRemaining}',
            icon: LucideIcons.clock,
          ),
        if (item?.nextBillingDate != null)
          SubsInfoRow(
            label: 'Próxima cobrança',
            value: _date.format(item!.nextBillingDate!.toLocal()),
            icon: LucideIcons.banknote,
          ),
        if (u?.isTrialActive == true && u?.trialEndsAt != null)
          SubsInfoRow(
            label: 'Teste grátis até',
            value: _date.format(u!.trialEndsAt!.toLocal()),
            icon: LucideIcons.rocket,
          ),
        if (item?.createdAt != null)
          SubsInfoRow(
            label: 'Criada em',
            value: _date.format(item!.createdAt!.toLocal()),
            icon: LucideIcons.calendarPlus,
          ),
        if ((notes ?? '').trim().isNotEmpty)
          SubsInfoRow(
            label: 'Observações',
            value: notes!.trim(),
            icon: LucideIcons.notebookPen,
          ),
      ],
    );
  }

  Widget _buildActionsSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final red = isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final status = _status.toLowerCase().trim();
    final isActive = status == 'active';
    final isCancelled = status == 'cancelled';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SubsPanelHeader(
          icon: LucideIcons.wrench,
          eyebrow: 'AÇÕES MASTER',
          title: 'Gerenciar esta assinatura',
          hint: 'As mudanças valem imediatamente e notificam o titular.',
          tone: accent,
        ),
        const SizedBox(height: 12),
        _actionTile(
          context,
          icon: LucideIcons.calendarPlus,
          tone: blue,
          title: 'Estender vigência',
          subtitle: 'Adicione dias ao término atual da assinatura.',
          onTap: _acting ? null : _openExtendSheet,
        ),
        if (!isCancelled)
          _actionTile(
            context,
            icon: isActive ? LucideIcons.pause : LucideIcons.play,
            tone: isActive ? amber : green,
            title: isActive ? 'Suspender' : 'Reativar',
            subtitle: isActive
                ? 'Pausa o acesso da conta sem excluir dados.'
                : 'Restaura o acesso imediato da conta.',
            onTap: _acting
                ? null
                : () => _openManageSheet(isActive ? 'suspend' : 'activate'),
          ),
        _actionTile(
          context,
          icon: LucideIcons.pencil,
          tone: accent,
          title: 'Editar contrato',
          subtitle: 'Ajuste observações internas e a data de término.',
          onTap: _acting ? null : _openEditSheet,
        ),
        if (!isCancelled)
          _actionTile(
            context,
            icon: LucideIcons.ban,
            tone: red,
            title: 'Cancelar assinatura',
            subtitle: 'Encerra a assinatura em definitivo.',
            onTap: _acting ? null : () => _openManageSheet('cancel'),
          ),
        if (_acting)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child:
                    CircularProgressIndicator(strokeWidth: 2.2, color: accent),
              ),
            ),
          ),
      ],
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              boxShadow: ThemeHelpers.cardShadow(context),
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                    ),
                    child: Icon(icon, color: tone, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 17,
                    color: secondary.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sheet: estender vigência ─────────────────────────────────────────────────

class _ExtendSheet extends StatefulWidget {
  const _ExtendSheet({required this.tone, required this.onConfirm});

  final Color tone;
  final void Function(int days, String reason) onConfirm;

  @override
  State<_ExtendSheet> createState() => _ExtendSheetState();
}

class _ExtendSheetState extends State<_ExtendSheet> {
  static const _presets = [7, 15, 30, 60, 90];
  int _days = 30;
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = widget.tone;
    return _SheetShell(
      icon: LucideIcons.calendarPlus,
      tone: tone,
      title: 'Estender vigência',
      hint: 'Os dias são somados ao término atual da assinatura.',
      cta: 'Estender $_days dias',
      onConfirm: () {
        Navigator.of(context).pop();
        widget.onConfirm(_days, _reasonController.text);
      },
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in _presets)
              InkWell(
                onTap: () => setState(() => _days = d),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  decoration: BoxDecoration(
                    color: _days == d
                        ? tone.withValues(alpha: isDark ? 0.18 : 0.1)
                        : (isDark
                            ? AppColors.background.backgroundTertiaryDarkMode
                            : AppColors.background.backgroundTertiary),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _days == d
                          ? tone
                          : ThemeHelpers.borderLightColor(context),
                      width: _days == d ? 1.2 : 1,
                    ),
                  ),
                  child: Text(
                    '$d dias',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _days == d
                          ? tone
                          : ThemeHelpers.textColor(context)
                              .withValues(alpha: 0.82),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _SheetTextField(
          controller: _reasonController,
          tone: tone,
          icon: LucideIcons.notebookPen,
          hint: 'Motivo (opcional)…',
        ),
      ],
    );
  }
}

// ─── Sheet: suspender / reativar / cancelar ──────────────────────────────────

class _ManageSheet extends StatefulWidget {
  const _ManageSheet({
    required this.tone,
    required this.title,
    required this.hint,
    required this.cta,
    required this.icon,
    required this.onConfirm,
  });

  final Color tone;
  final String title;
  final String hint;
  final String cta;
  final IconData icon;
  final void Function(String reason, String notes) onConfirm;

  @override
  State<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends State<_ManageSheet> {
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      icon: widget.icon,
      tone: widget.tone,
      title: widget.title,
      hint: widget.hint,
      cta: widget.cta,
      onConfirm: () {
        Navigator.of(context).pop();
        widget.onConfirm(_reasonController.text, _notesController.text);
      },
      children: [
        _SheetTextField(
          controller: _reasonController,
          tone: widget.tone,
          icon: LucideIcons.circleAlert,
          hint: 'Motivo…',
        ),
        const SizedBox(height: 10),
        _SheetTextField(
          controller: _notesController,
          tone: widget.tone,
          icon: LucideIcons.notebookPen,
          hint: 'Observações internas (opcional)…',
          maxLines: 3,
        ),
      ],
    );
  }
}

// ─── Sheet: editar contrato (notas + término) ────────────────────────────────

class _EditSheet extends StatefulWidget {
  const _EditSheet({
    required this.tone,
    required this.initialNotes,
    required this.initialEndDate,
    required this.onConfirm,
  });

  final Color tone;
  final String initialNotes;
  final DateTime? initialEndDate;
  final void Function(String? notes, DateTime? endDate) onConfirm;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _notesController;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.initialNotes);
    _endDate = widget.initialEndDate;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return _SheetShell(
      icon: LucideIcons.pencil,
      tone: widget.tone,
      title: 'Editar contrato',
      hint: 'Ajuste observações internas e a data de término.',
      cta: 'Salvar alterações',
      onConfirm: () {
        Navigator.of(context).pop();
        // Notas: envia o texto atual (permite limpar com string vazia →
        // omitida pelo service quando null; aqui manda sempre o valor).
        widget.onConfirm(_notesController.text.trim(), _endDate);
      },
      children: [
        InkWell(
          onTap: _pickEndDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.background.backgroundTertiaryDarkMode
                  : AppColors.background.backgroundTertiary,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: ThemeHelpers.borderLightColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        widget.tone.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(LucideIcons.calendarClock,
                      size: 17, color: widget.tone),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _endDate == null
                        ? 'Término da vigência…'
                        : _date.format(_endDate!.toLocal()),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _endDate == null
                          ? secondary.withValues(alpha: 0.9)
                          : ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _SheetTextField(
          controller: _notesController,
          tone: widget.tone,
          icon: LucideIcons.notebookPen,
          hint: 'Observações internas…',
          maxLines: 4,
        ),
      ],
    );
  }
}

// ─── Shell comum dos sheets de ação ──────────────────────────────────────────

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.icon,
    required this.tone,
    required this.title,
    required this.hint,
    required this.cta,
    required this.onConfirm,
    required this.children,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String hint;
  final String cta;
  final VoidCallback onConfirm;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final mq = MediaQuery.of(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: tone.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                        border:
                            Border.all(color: tone.withValues(alpha: 0.3)),
                      ),
                      child: Icon(icon, color: tone, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            hint,
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
                const SizedBox(height: 18),
                ...children,
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: tone,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    cta,
                    style: const TextStyle(fontWeight: FontWeight.w800),
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

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    required this.tone,
    required this.icon,
    required this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final Color tone;
  final IconData icon;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 4 : 0),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: tone),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(vertical: maxLines > 1 ? 10 : 8),
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
