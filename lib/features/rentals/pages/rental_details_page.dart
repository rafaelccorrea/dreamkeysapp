import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/rental_models.dart';
import '../services/rental_service.dart';
import '../widgets/rental_status_ui.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Abas do detalhe da locação.
enum _DetailTab { summary, payments, history, comments }

/// Tela de **detalhe da locação** (`/rentals/:id`) — paridade com
/// `RentalDetailsPage.tsx`: resumo do contrato (inquilino, imóvel, valores),
/// parcelas com ações (marcar pago, boleto/PIX, excluir, gerar/adicionar),
/// histórico de ações e comentários. Ações do contrato (editar, alterar
/// status, aprovar/rejeitar, excluir) ficam no menu do topo e no banner.
class RentalDetailsPage extends StatefulWidget {
  final String rentalId;

  /// `'payments'` abre direto na aba de pagamentos (deep-link da lista).
  final String? initialTab;

  const RentalDetailsPage({super.key, required this.rentalId, this.initialTab});

  @override
  State<RentalDetailsPage> createState() => _RentalDetailsPageState();
}

class _RentalDetailsPageState extends State<RentalDetailsPage> {
  static const double _kPagePadH = 16;

  Rental? _rental;
  bool _loading = true;
  String? _error;

  _DetailTab _activeTab = _DetailTab.summary;

  // Pagamentos
  List<RentalPayment> _payments = const [];
  bool _paymentsLoading = false;
  bool _paymentsLoaded = false;
  String? _paymentsError;
  bool _generating = false;

  // Histórico
  List<RentalHistoryEntry> _history = const [];
  bool _historyLoading = false;
  bool _historyLoaded = false;
  String? _historyError;
  int _historyPage = 1;
  int _historyTotalPages = 1;
  bool _historyLoadingMore = false;

  // Comentários
  List<RentalCommentEntry> _comments = const [];
  bool _commentsLoading = false;
  bool _commentsLoaded = false;
  String? _commentsError;
  int _commentsPage = 1;
  int _commentsTotalPages = 1;
  bool _commentsLoadingMore = false;
  final TextEditingController _commentController = TextEditingController();
  bool _sendingComment = false;

  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final DateFormat _dateTimeFmt =
      DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
  static final DateFormat _monthFmt = DateFormat('MMMM yyyy', 'pt_BR');

  ModuleAccessService get _access => ModuleAccessService.instance;
  bool get _canUpdate => _access.hasPermission(RentalPermissions.update);
  bool get _canDelete => _access.hasPermission(RentalPermissions.delete);
  bool get _canManagePayments =>
      _access.hasPermission(RentalPermissions.managePayments);
  bool get _canManageWorkflows =>
      _access.hasPermission(RentalPermissions.manageWorkflows);

  @override
  void initState() {
    super.initState();
    if (widget.initialTab == 'payments') _activeTab = _DetailTab.payments;
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Color _accentColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await RentalService.instance.getById(widget.rentalId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _rental = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar locação';
      }
    });
    if (_rental != null && _activeTab == _DetailTab.payments) {
      _loadPayments();
    }
  }

  Future<void> _refreshAll() async {
    await _load();
    if (!mounted) return;
    switch (_activeTab) {
      case _DetailTab.payments:
        await _loadPayments();
        break;
      case _DetailTab.history:
        await _loadHistory();
        break;
      case _DetailTab.comments:
        await _loadComments();
        break;
      case _DetailTab.summary:
        break;
    }
  }

  Future<void> _loadPayments() async {
    setState(() {
      _paymentsLoading = true;
      _paymentsError = null;
    });
    final res = await RentalService.instance.getPayments(widget.rentalId);
    if (!mounted) return;
    setState(() {
      _paymentsLoading = false;
      _paymentsLoaded = true;
      if (res.success && res.data != null) {
        _payments = res.data!;
      } else {
        _paymentsError = res.message ?? 'Erro ao carregar pagamentos';
      }
    });
  }

  Future<void> _loadHistory({bool more = false}) async {
    if (more) {
      if (_historyLoadingMore || _historyPage >= _historyTotalPages) return;
      setState(() => _historyLoadingMore = true);
    } else {
      setState(() {
        _historyLoading = true;
        _historyError = null;
      });
    }
    final page = more ? _historyPage + 1 : 1;
    final res =
        await RentalService.instance.getHistory(widget.rentalId, page: page);
    if (!mounted) return;
    setState(() {
      _historyLoading = false;
      _historyLoadingMore = false;
      _historyLoaded = true;
      if (res.success && res.data != null) {
        _history = more ? [..._history, ...res.data!.items] : res.data!.items;
        _historyPage = res.data!.page;
        _historyTotalPages = res.data!.totalPages;
      } else if (!more) {
        _historyError = res.message ?? 'Erro ao carregar histórico';
      }
    });
  }

  Future<void> _loadComments({bool more = false}) async {
    if (more) {
      if (_commentsLoadingMore || _commentsPage >= _commentsTotalPages) return;
      setState(() => _commentsLoadingMore = true);
    } else {
      setState(() {
        _commentsLoading = true;
        _commentsError = null;
      });
    }
    final page = more ? _commentsPage + 1 : 1;
    final res =
        await RentalService.instance.getComments(widget.rentalId, page: page);
    if (!mounted) return;
    setState(() {
      _commentsLoading = false;
      _commentsLoadingMore = false;
      _commentsLoaded = true;
      if (res.success && res.data != null) {
        _comments =
            more ? [..._comments, ...res.data!.items] : res.data!.items;
        _commentsPage = res.data!.page;
        _commentsTotalPages = res.data!.totalPages;
      } else if (!more) {
        _commentsError = res.message ?? 'Erro ao carregar comentários';
      }
    });
  }

  void _selectTab(_DetailTab tab) {
    if (tab == _activeTab) return;
    setState(() => _activeTab = tab);
    switch (tab) {
      case _DetailTab.payments:
        if (!_paymentsLoaded && !_paymentsLoading) _loadPayments();
        break;
      case _DetailTab.history:
        if (!_historyLoaded && !_historyLoading) _loadHistory();
        break;
      case _DetailTab.comments:
        if (!_commentsLoaded && !_commentsLoading) _loadComments();
        break;
      case _DetailTab.summary:
        break;
    }
  }

  // ─── Ações do contrato ───────────────────────────────────────────────────

  void _openEdit() {
    Navigator.of(context)
        .pushNamed('/rentals/${widget.rentalId}/edit')
        .then((_) => _load());
  }

  Future<void> _approve() async {
    final rental = _rental;
    if (rental == null) return;
    final ok = await _confirmDialog(
      title: 'Aprovar locação',
      message: 'Deseja aprovar a locação de "${rental.tenantName}"? O aluguel '
          'será ativado e os pagamentos serão gerados conforme a configuração.',
      confirmLabel: 'Aprovar',
      icon: LucideIcons.check,
      destructive: false,
    );
    if (ok != true || !mounted) return;
    final res = await RentalService.instance.approve(widget.rentalId);
    if (!mounted) return;
    _snack(
      res.success
          ? 'Locação aprovada com sucesso.'
          : (res.message ?? 'Erro ao aprovar locação.'),
      error: !res.success,
    );
    if (res.success) _refreshAll();
  }

  Future<void> _reject() async {
    final rental = _rental;
    if (rental == null) return;
    final ok = await _confirmDialog(
      title: 'Rejeitar locação',
      message:
          'Tem certeza que deseja rejeitar a locação de "${rental.tenantName}"?',
      confirmLabel: 'Rejeitar',
      icon: LucideIcons.x,
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final res = await RentalService.instance.reject(widget.rentalId);
    if (!mounted) return;
    _snack(
      res.success
          ? 'Locação rejeitada.'
          : (res.message ?? 'Erro ao rejeitar locação.'),
      error: !res.success,
    );
    if (res.success) _refreshAll();
  }

  Future<void> _delete() async {
    final rental = _rental;
    if (rental == null) return;
    final ok = await _confirmDialog(
      title: 'Excluir locação',
      message: 'Tem certeza que deseja excluir a locação de '
          '"${rental.tenantName}"? As cobranças pendentes serão canceladas no '
          'gateway e todos os pagamentos removidos. Esta ação não poderá ser '
          'desfeita.',
      confirmLabel: 'Excluir',
      icon: LucideIcons.trash2,
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final res = await RentalService.instance.delete(widget.rentalId);
    if (!mounted) return;
    if (res.success) {
      _snack('Locação excluída.');
      Navigator.of(context).pop(true);
    } else {
      _snack(res.message ?? 'Erro ao excluir locação.', error: true);
    }
  }

  Future<void> _changeStatus() async {
    final rental = _rental;
    if (rental == null) return;
    final selected = await showModalBottomSheet<RentalStatus>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _StatusSheet(current: rental.status),
    );
    if (selected == null || selected == rental.status || !mounted) return;
    final res =
        await RentalService.instance.updateStatus(widget.rentalId, selected);
    if (!mounted) return;
    _snack(
      res.success
          ? 'Status alterado para "${selected.label}".'
          : (res.message ?? 'Erro ao alterar status.'),
      error: !res.success,
    );
    if (res.success) _refreshAll();
  }

  // ─── Ações de pagamento ──────────────────────────────────────────────────

  Future<void> _markPaymentPaid(RentalPayment payment) async {
    final ok = await _confirmDialog(
      title: 'Marcar como pago',
      message: 'Confirmar o recebimento da parcela de '
          '${_referenceLabel(payment.referenceMonth)} '
          '(${_money.format(payment.value)})? Esta ação não poderá ser '
          'desfeita.',
      confirmLabel: 'Marcar pago',
      icon: LucideIcons.circleCheckBig,
      destructive: false,
    );
    if (ok != true || !mounted) return;
    final res = await RentalService.instance
        .markPaymentAsPaid(widget.rentalId, payment);
    if (!mounted) return;
    _snack(
      res.success
          ? 'Parcela marcada como paga.'
          : (res.message ?? 'Erro ao atualizar a parcela.'),
      error: !res.success,
    );
    if (res.success) {
      _loadPayments();
      _load();
    }
  }

  Future<void> _deletePayment(RentalPayment payment) async {
    final ok = await _confirmDialog(
      title: 'Excluir parcela',
      message: 'Excluir a parcela de ${_referenceLabel(payment.referenceMonth)} '
          '(${_money.format(payment.value)})? Se houver cobrança no gateway, '
          'ela será cancelada.',
      confirmLabel: 'Excluir',
      icon: LucideIcons.trash2,
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final res =
        await RentalService.instance.deletePayment(widget.rentalId, payment.id);
    if (!mounted) return;
    _snack(
      res.success
          ? 'Parcela excluída.'
          : (res.message ?? 'Erro ao excluir parcela.'),
      error: !res.success,
    );
    if (res.success) _loadPayments();
  }

  Future<void> _generatePayments() async {
    setState(() => _generating = true);
    final res = await RentalService.instance.generatePayments(widget.rentalId);
    if (!mounted) return;
    setState(() => _generating = false);
    _snack(
      res.success
          ? 'Parcelas geradas com sucesso.'
          : (res.message ?? 'Erro ao gerar parcelas.'),
      error: !res.success,
    );
    if (res.success) _loadPayments();
  }

  Future<void> _addPayment() async {
    final rental = _rental;
    if (rental == null) return;
    final result = await showModalBottomSheet<_NewPaymentData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _AddPaymentSheet(rental: rental),
    );
    if (result == null || !mounted) return;
    final res = await RentalService.instance.addPayment(
      widget.rentalId,
      dueDate: result.dueDate,
      value: result.value,
      referenceMonth: result.referenceMonth,
      observations: result.observations,
    );
    if (!mounted) return;
    _snack(
      res.success
          ? 'Parcela adicionada.'
          : (res.message ?? 'Erro ao adicionar parcela.'),
      error: !res.success,
    );
    if (res.success) _loadPayments();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _snack('Não foi possível abrir o link.', error: true);
    }
  }

  void _copyPix(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _snack('Código PIX copiado!');
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingComment = true);
    final res =
        await RentalService.instance.addComment(widget.rentalId, text);
    if (!mounted) return;
    setState(() => _sendingComment = false);
    if (res.success) {
      _commentController.clear();
      _snack('Comentário adicionado.');
      _loadComments();
    } else {
      _snack(res.message ?? 'Erro ao adicionar comentário.', error: true);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _referenceLabel(String referenceMonth) {
    final parts = referenceMonth.split('-');
    if (parts.length >= 2) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null && m >= 1 && m <= 12) {
        final label = _monthFmt.format(DateTime(y, m));
        return label[0].toUpperCase() + label.substring(1);
      }
    }
    return referenceMonth.isEmpty ? 'Parcela' : referenceMonth;
  }

  void _snack(String message, {bool error = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : null,
      ),
    );
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required bool destructive,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = destructive
        ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
        : (isDark ? AppColors.status.greenDarkMode : AppColors.status.green);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tone, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: ThemeHelpers.textColor(ctx),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: ThemeHelpers.textSecondaryColor(ctx),
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(ctx),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: tone,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Detalhe da Locação',
      showBottomNavigation: false,
      actions: [
        if (_rental != null &&
            (_canUpdate || _canDelete || _canManageWorkflows))
          _buildTopMenu(context),
      ],
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _refreshAll,
        child: _loading
            ? _buildSkeleton(context)
            : _error != null
                ? _buildError(context)
                : _buildContent(context),
      ),
    );
  }

  Widget _buildTopMenu(BuildContext context) {
    final rental = _rental!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    return PopupMenuButton<String>(
      tooltip: 'Ações',
      position: PopupMenuPosition.under,
      color: ThemeHelpers.cardBackgroundColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
      ),
      icon: Icon(LucideIcons.ellipsisVertical,
          size: 20, color: ThemeHelpers.textColor(context)),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            _openEdit();
            break;
          case 'status':
            _changeStatus();
            break;
          case 'approve':
            _approve();
            break;
          case 'reject':
            _reject();
            break;
          case 'delete':
            _delete();
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (rental.isPendingApproval && _canManageWorkflows) ...[
          _menuItem(ctx, 'approve', LucideIcons.check, 'Aprovar locação',
              color: green),
          _menuItem(ctx, 'reject', LucideIcons.x, 'Rejeitar locação',
              color: danger),
        ],
        if (_canUpdate) ...[
          _menuItem(ctx, 'edit', LucideIcons.pencil, 'Editar contrato'),
          _menuItem(
              ctx, 'status', LucideIcons.refreshCcw, 'Alterar status'),
        ],
        if (_canDelete)
          _menuItem(ctx, 'delete', LucideIcons.trash2, 'Excluir locação',
              color: danger),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final fg = color ?? ThemeHelpers.textColor(context);
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(_kPagePadH, 10, _kPagePadH, 0),
                child: _buildHero(context),
              ),
              const SizedBox(height: 14),
              _buildTabsRail(context),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(_kPagePadH, 14, _kPagePadH, 88),
                child: _buildActivePanel(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final rental = _rental!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = rentalStatusColor(context, rental.status);
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    final propertyLine = [
      if ((rental.property?.title ?? '').trim().isNotEmpty)
        rental.property!.title.trim(),
      if ((rental.property?.code ?? '').trim().isNotEmpty)
        'CÓD ${rental.property!.code!.trim()}',
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
            Expanded(
              child: Text(
                'CONTRATO DE LOCAÇÃO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          rental.tenantName.trim().isNotEmpty
              ? rental.tenantName.trim()
              : 'Inquilino não especificado',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        if (propertyLine.isNotEmpty) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(LucideIcons.house, size: 13, color: secondary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  propertyLine,
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
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            RentalStatusPill(
              label: rental.status.label,
              color: tone,
              icon: rentalStatusIcon(rental.status),
            ),
            RentalStatusPill(
              label: rental.autoGeneratePayments
                  ? 'Geração automática'
                  : 'Cobrança manual',
              color: rental.autoGeneratePayments
                  ? (isDark
                      ? AppColors.status.greenDarkMode
                      : AppColors.status.green)
                  : secondary,
              icon: rental.autoGeneratePayments
                  ? LucideIcons.zap
                  : LucideIcons.hand,
            ),
            if (rental.isExpiringSoon)
              RentalStatusPill(
                label: 'Vence em breve',
                color: amber,
                icon: LucideIcons.calendarClock,
              ),
          ],
        ),
        const SizedBox(height: 18),
        _buildKpiStrip(context),
        if (rental.isPendingApproval && _canManageWorkflows) ...[
          const SizedBox(height: 16),
          _buildApprovalBanner(context),
        ],
      ],
    );
  }

  Widget _buildKpiStrip(BuildContext context) {
    final rental = _rental!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final fmtShort = DateFormat('dd/MM/yy', 'pt_BR');

    final period = rental.startDate != null && rental.endDate != null
        ? '${fmtShort.format(rental.startDate!.toLocal())} → ${fmtShort.format(rental.endDate!.toLocal())}'
        : '—';
    final remaining = rental.endDate == null
        ? 'período do contrato'
        : (() {
            final days =
                rental.endDate!.difference(DateTime.now()).inDays;
            if (days < 0) return 'contrato encerrado';
            if (days == 0) return 'termina hoje';
            return 'faltam $days dia${days == 1 ? '' : 's'}';
          })();

    final blocks = <Widget>[
      _kpiBlock(context, LucideIcons.banknote, 'VALOR/MÊS',
          _money.format(rental.monthlyValue), 'vencimento dia ${rental.dueDay}',
          emerald),
      _kpiBlock(context, LucideIcons.calendarRange, 'PERÍODO', period,
          remaining, blue),
      _kpiBlock(
          context,
          LucideIcons.shieldCheck,
          'CAUÇÃO',
          (rental.depositValue ?? 0) > 0
              ? _money.format(rental.depositValue)
              : '—',
          (rental.depositValue ?? 0) > 0 ? 'depósito de garantia' : 'sem caução',
          amber),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: divider,
              ),
            Expanded(child: blocks[i]),
          ],
        ],
      ),
    );
  }

  Widget _kpiBlock(BuildContext context, IconData icon, String label,
      String value, String sub, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: tone),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: 1.2,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: -0.4,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondary,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            width: 18,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalBanner(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.hourglass, size: 16, color: amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Esta locação aguarda a sua aprovação',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _approve,
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(LucideIcons.check, size: 15),
                  label: const Text('Aprovar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: danger,
                    side: BorderSide(color: danger.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(LucideIcons.x, size: 15),
                  label: const Text('Rejeitar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Abas flush ──────────────────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabs = <(_DetailTab, IconData, String, Color)>[
      (
        _DetailTab.summary,
        LucideIcons.fileText,
        'Resumo',
        _accentColor(context)
      ),
      (
        _DetailTab.payments,
        LucideIcons.wallet,
        'Parcelas',
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green
      ),
      (
        _DetailTab.history,
        LucideIcons.history,
        'Histórico',
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue
      ),
      (
        _DetailTab.comments,
        LucideIcons.messageSquare,
        'Notas',
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          for (final (tab, icon, label, tone) in tabs)
            Expanded(
              child: _FlushTab(
                icon: icon,
                label: label,
                tone: tone,
                selected: _activeTab == tab,
                onTap: () => _selectTab(tab),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivePanel(BuildContext context) {
    Widget child;
    switch (_activeTab) {
      case _DetailTab.summary:
        child = _buildSummary(context);
        break;
      case _DetailTab.payments:
        child = _buildPayments(context);
        break;
      case _DetailTab.history:
        child = _buildHistory(context);
        break;
      case _DetailTab.comments:
        child = _buildComments(context);
        break;
    }
    return child
        .animate(key: ValueKey('panel-${_activeTab.name}'))
        .fadeIn(duration: 240.ms);
  }

  // ─── Resumo ──────────────────────────────────────────────────────────────

  Widget _buildSummary(BuildContext context) {
    final rental = _rental!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final property = rental.property;

    String percent(double? v) => v == null
        ? '—'
        : '${v.toStringAsFixed(2).replaceAll('.', ',').replaceAll(RegExp(r',00$'), '')}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummarySection(
          tone: blue,
          icon: LucideIcons.user,
          label: 'Inquilino',
          rows: [
            ('Nome', rental.tenantName, null),
            ('Documento', rental.tenantDocumentMasked, null),
            if ((rental.tenantPhone ?? '').isNotEmpty)
              ('Telefone', rental.tenantPhoneMasked, LucideIcons.phone),
            if ((rental.tenantEmail ?? '').trim().isNotEmpty)
              ('Email', rental.tenantEmail!.trim(), LucideIcons.mail),
          ],
        ),
        _SummarySection(
          tone: purple,
          icon: LucideIcons.house,
          label: 'Imóvel',
          rows: [
            ('Título', property?.title ?? 'Não especificado', null),
            if ((property?.code ?? '').isNotEmpty)
              ('Código', property!.code!, null),
            if (property != null) ('Tipo', property.typeLabel, null),
            if ((property?.locationLabel ?? '') != '' &&
                property?.locationLabel != null)
              ('Endereço', property!.locationLabel!, LucideIcons.mapPin),
            if ((property?.bedrooms ?? 0) > 0)
              ('Quartos', '${property!.bedrooms}', null),
            if ((property?.bathrooms ?? 0) > 0)
              ('Banheiros', '${property!.bathrooms}', null),
            if ((property?.parkingSpaces ?? 0) > 0)
              ('Vagas', '${property!.parkingSpaces}', null),
            if ((property?.totalArea ?? 0) > 0)
              ('Área total', '${property!.totalArea!.toStringAsFixed(0)} m²',
                  null),
          ],
        ),
        _SummarySection(
          tone: emerald,
          icon: LucideIcons.banknote,
          label: 'Contrato e valores',
          rows: [
            ('Valor mensal', _money.format(rental.monthlyValue), null),
            (
              'Depósito/caução',
              (rental.depositValue ?? 0) > 0
                  ? _money.format(rental.depositValue)
                  : '—',
              null
            ),
            (
              'Início',
              rental.startDate == null
                  ? '—'
                  : _dateFmt.format(rental.startDate!.toLocal()),
              null
            ),
            (
              'Término',
              rental.endDate == null
                  ? '—'
                  : _dateFmt.format(rental.endDate!.toLocal()),
              null
            ),
            ('Dia de vencimento', 'Dia ${rental.dueDay}', null),
            ('Multa em atraso', percent(rental.lateFeePercent), null),
            ('Juros ao mês', percent(rental.interestPerMonthPercent), null),
            (
              'Criado em',
              rental.createdAt == null
                  ? '—'
                  : _dateFmt.format(rental.createdAt!.toLocal()),
              null
            ),
          ],
        ),
        if ((rental.observations ?? '').trim().isNotEmpty)
          _SummarySection(
            tone: ThemeHelpers.textSecondaryColor(context),
            icon: LucideIcons.notebookPen,
            label: 'Observações',
            child: Text(
              rental.observations!.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.45,
                  ),
            ),
          ),
      ],
    );
  }

  // ─── Parcelas ────────────────────────────────────────────────────────────

  Widget _buildPayments(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

    if (_paymentsLoading && _payments.isEmpty) {
      return _listSkeleton();
    }
    if (_paymentsError != null && _payments.isEmpty) {
      return _panelError(context, _paymentsError!, _loadPayments);
    }

    final paid = _payments.where((p) => p.isPaid).length;
    final late = _payments.where((p) => p.isLate).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Parcelas do contrato',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _payments.isEmpty
                        ? 'Nenhuma parcela gerada ainda.'
                        : '$paid de ${_payments.length} paga${paid == 1 ? '' : 's'}'
                            '${late > 0 ? ' · $late em atraso' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (_canManagePayments && _payments.isNotEmpty)
              _SmallActionButton(
                icon: LucideIcons.plus,
                label: 'Parcela',
                tone: emerald,
                onTap: _addPayment,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_payments.isEmpty)
          _buildPaymentsEmpty(context)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in _payments) _buildPaymentRow(context, p),
            ],
          ),
      ],
    );
  }

  Widget _buildPaymentsEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                emerald.withValues(alpha: 0.18),
                emerald.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: emerald.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.wallet, color: emerald, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'Nenhuma parcela gerada',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Gere as parcelas mensais do período do contrato ou adicione '
            'uma parcela avulsa.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
          if (_canManagePayments) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _generating ? null : _generatePayments,
                  style: FilledButton.styleFrom(
                    backgroundColor: emerald,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  icon: _generating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.sparkles, size: 15),
                  label: Text(
                    _generating ? 'Gerando…' : 'Gerar parcelas',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _addPayment,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: emerald,
                    side: BorderSide(color: emerald.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: const Text('Avulsa',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentRow(BuildContext context, RentalPayment payment) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final effectiveStatus = payment.isLate && !payment.isPaid
        ? RentalPaymentStatus.overdue
        : payment.status;
    final tone = rentalPaymentStatusColor(context, effectiveStatus);

    final dueLabel = payment.dueDate == null
        ? 'Sem vencimento'
        : 'Vence ${_dateFmt.format(payment.dueDate!.toLocal())}';
    final paidLabel = payment.paymentDate == null
        ? null
        : 'Pago em ${_dateFmt.format(payment.paymentDate!.toLocal())}';

    final hasInvoice = (payment.asaasInvoiceUrl ?? '').isNotEmpty;
    final hasSlip = (payment.asaasBankSlipUrl ?? '').isNotEmpty;
    final hasPix = (payment.asaasPixCopyPaste ?? '').isNotEmpty;
    final showMenu = _canManagePayments || hasInvoice || hasSlip || hasPix;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
              border: Border.all(color: tone.withValues(alpha: 0.28)),
            ),
            child:
                Icon(rentalPaymentStatusIcon(effectiveStatus), color: tone, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _referenceLabel(payment.referenceMonth),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  paidLabel ?? dueLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: payment.isLate && !payment.isPaid
                        ? danger
                        : secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((payment.observations ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    payment.observations!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                RentalStatusPill(
                  label: effectiveStatus.label,
                  color: tone,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money.format(payment.value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: payment.isPaid
                      ? tone
                      : ThemeHelpers.textColor(context),
                  letterSpacing: -0.3,
                ),
              ),
              if (payment.isPaid &&
                  payment.paidValue != null &&
                  payment.paidValue != payment.value)
                Text(
                  'pago ${_money.format(payment.paidValue)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontSize: 10,
                  ),
                ),
              if (showMenu) _buildPaymentMenu(context, payment),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMenu(BuildContext context, RentalPayment payment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final hasInvoice = (payment.asaasInvoiceUrl ?? '').isNotEmpty;
    final hasSlip = (payment.asaasBankSlipUrl ?? '').isNotEmpty;
    final hasPix = (payment.asaasPixCopyPaste ?? '').isNotEmpty;

    return PopupMenuButton<String>(
      tooltip: 'Ações da parcela',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      color: ThemeHelpers.cardBackgroundColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
      ),
      icon: Icon(LucideIcons.ellipsisVertical, size: 17, color: secondary),
      onSelected: (v) {
        switch (v) {
          case 'paid':
            _markPaymentPaid(payment);
            break;
          case 'invoice':
            _openUrl(payment.asaasInvoiceUrl!);
            break;
          case 'slip':
            _openUrl(payment.asaasBankSlipUrl!);
            break;
          case 'pix':
            _copyPix(payment.asaasPixCopyPaste!);
            break;
          case 'delete':
            _deletePayment(payment);
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (_canManagePayments && !payment.isPaid)
          _menuItem(ctx, 'paid', LucideIcons.circleCheckBig,
              'Marcar como pago',
              color: green),
        if (hasInvoice)
          _menuItem(ctx, 'invoice', LucideIcons.externalLink, 'Abrir fatura'),
        if (hasSlip)
          _menuItem(ctx, 'slip', LucideIcons.fileText, 'Abrir boleto'),
        if (hasPix)
          _menuItem(ctx, 'pix', LucideIcons.copy, 'Copiar código PIX'),
        if (_canManagePayments && !payment.isPaid)
          _menuItem(ctx, 'delete', LucideIcons.trash2, 'Excluir parcela',
              color: danger),
      ],
    );
  }

  // ─── Histórico ───────────────────────────────────────────────────────────

  Widget _buildHistory(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    if (_historyLoading && _history.isEmpty) return _listSkeleton();
    if (_historyError != null && _history.isEmpty) {
      return _panelError(context, _historyError!, _loadHistory);
    }
    if (_history.isEmpty) {
      return _panelEmpty(
        context,
        icon: LucideIcons.history,
        tone: blue,
        title: 'Sem eventos ainda',
        body: 'As ações realizadas neste contrato aparecem aqui.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _history.length; i++)
          _buildHistoryRow(context, _history[i], i == _history.length - 1),
        if (_historyPage < _historyTotalPages)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(
              child: _historyLoadingMore
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: blue),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _loadHistory(more: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        side:
                            BorderSide(color: blue.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(LucideIcons.chevronDown, size: 16),
                      label: const Text('Carregar mais'),
                    ),
            ),
          )
        else if (_history.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(
              child: Text(
                'Fim do histórico',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryRow(
      BuildContext context, RentalHistoryEntry entry, bool isLast) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: blue,
                  boxShadow: [
                    BoxShadow(
                        color: blue.withValues(alpha: 0.4), blurRadius: 5),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.only(top: 4),
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.actionLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.2,
                    ),
                  ),
                  if ((entry.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      entry.description!.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    [
                      if ((entry.userName ?? '').trim().isNotEmpty)
                        entry.userName!.trim(),
                      if (entry.createdAt != null)
                        _dateTimeFmt.format(entry.createdAt!.toLocal()),
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
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

  // ─── Comentários ─────────────────────────────────────────────────────────

  Widget _buildComments(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    Widget composer = Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: fieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: 'Escreva um comentário…',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: secondary.withValues(alpha: 0.85),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: _commentController.text.trim().isEmpty
                ? purple.withValues(alpha: 0.25)
                : purple,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: _sendingComment || _commentController.text.trim().isEmpty
                  ? null
                  : _sendComment,
              child: SizedBox(
                width: 40,
                height: 40,
                child: _sendingComment
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.sendHorizontal,
                        size: 17, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );

    Widget body;
    if (_commentsLoading && _comments.isEmpty) {
      body = _listSkeleton();
    } else if (_commentsError != null && _comments.isEmpty) {
      body = _panelError(context, _commentsError!, _loadComments);
    } else if (_comments.isEmpty) {
      body = _panelEmpty(
        context,
        icon: LucideIcons.messageSquare,
        tone: purple,
        title: 'Sem comentários',
        body: 'Registre observações internas sobre este contrato.',
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in _comments) _buildCommentRow(context, c, purple),
          if (_commentsPage < _commentsTotalPages)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: _commentsLoadingMore
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: purple),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _loadComments(more: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: purple,
                          side: BorderSide(
                              color: purple.withValues(alpha: 0.45)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(LucideIcons.chevronDown, size: 16),
                        label: const Text('Carregar mais'),
                      ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        composer,
        const SizedBox(height: 16),
        body,
      ],
    );
  }

  Widget _buildCommentRow(
      BuildContext context, RentalCommentEntry comment, Color tone) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final initial = (comment.userName ?? '?').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
              border: Border.all(color: tone.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                initial.isEmpty ? '?' : initial[0].toUpperCase(),
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (comment.userName ?? 'Usuário').trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    if (comment.createdAt != null)
                      Text(
                        _dateTimeFmt.format(comment.createdAt!.toLocal()),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary.withValues(alpha: 0.85),
                          fontSize: 10.5,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Estados genéricos ───────────────────────────────────────────────────

  Widget _listSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 42, height: 42, borderRadius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 120, height: 14),
                    SizedBox(height: 8),
                    SkeletonText(width: double.infinity, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 64, height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelEmpty(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String title,
    required String body,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                tone.withValues(alpha: 0.18),
                tone.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: tone.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: tone, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelError(
      BuildContext context, String message, VoidCallback onRetry) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
      child: Column(
        children: [
          Icon(LucideIcons.cloudOff, color: danger, size: 30),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
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

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPagePadH, 14, _kPagePadH, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 170, height: 11),
          const SizedBox(height: 12),
          const SkeletonText(width: 230, height: 24),
          const SizedBox(height: 8),
          const SkeletonText(width: 180, height: 13),
          const SizedBox(height: 12),
          Row(
            children: const [
              SkeletonText(width: 84, height: 22, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonText(width: 120, height: 22, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: 60, height: 9),
                      SizedBox(height: 8),
                      SkeletonText(width: 90, height: 18),
                      SizedBox(height: 6),
                      SkeletonText(width: 70, height: 9),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          SkeletonBox(width: double.infinity, height: 44, borderRadius: 12),
          const SizedBox(height: 20),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SkeletonBox(width: 42, height: 42, borderRadius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: double.infinity, height: 14),
                        SizedBox(height: 8),
                        SkeletonText(width: 150, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 60),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _error ?? 'Erro ao carregar locação',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ),
      ],
    );
  }
}

// ─── Aba flush (sublinhado) ──────────────────────────────────────────────────

class _FlushTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _FlushTab({
    required this.icon,
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? tone : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.12),
        highlightColor: tone.withValues(alpha: 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? tone : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Seção do resumo (rows label/valor) ──────────────────────────────────────

class _SummarySection extends StatelessWidget {
  final Color tone;
  final IconData icon;
  final String label;
  final List<(String, String, IconData?)>? rows;
  final Widget? child;

  const _SummarySection({
    required this.tone,
    required this.icon,
    required this.label,
    this.rows,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: tone),
              const SizedBox(width: 7),
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone,
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
                    color: ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (child != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: child!,
            )
          else
            for (final (rowLabel, rowValue, rowIcon)
                in rows ?? const <(String, String, IconData?)>[])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rowIcon != null) ...[
                      Icon(rowIcon, size: 13, color: secondary),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        rowLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        rowValue,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w800,
                        ),
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

// ─── Botão de ação pequeno (painel) ──────────────────────────────────────────

class _SmallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;

  const _SmallActionButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tone),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet de alteração de status ────────────────────────────────────────────

class _StatusSheet extends StatelessWidget {
  final RentalStatus current;

  const _StatusSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Center(
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Text(
                'Alterar status do contrato',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'O status controla cobranças e alertas da locação.',
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
            for (final status in RentalStatus.selectable)
              _statusOption(context, status),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _statusOption(BuildContext context, RentalStatus status) {
    final theme = Theme.of(context);
    final tone = rentalStatusColor(context, status);
    final isDark = theme.brightness == Brightness.dark;
    final selected = status == current;
    return InkWell(
      onTap: () => Navigator.of(context).pop(status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: selected ? tone.withValues(alpha: isDark ? 0.1 : 0.06) : null,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
              ),
              child: Icon(rentalStatusIcon(status), color: tone, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            if (selected) Icon(LucideIcons.check, size: 18, color: tone),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet de nova parcela ───────────────────────────────────────────────────

class _NewPaymentData {
  final String referenceMonth;
  final String dueDate;
  final double value;
  final String? observations;

  const _NewPaymentData({
    required this.referenceMonth,
    required this.dueDate,
    required this.value,
    this.observations,
  });
}

class _AddPaymentSheet extends StatefulWidget {
  final Rental rental;

  const _AddPaymentSheet({required this.rental});

  @override
  State<_AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends State<_AddPaymentSheet> {
  late DateTime _referenceMonth;
  DateTime? _dueDate;
  final _valueController = TextEditingController();
  final _obsController = TextEditingController();

  static final DateFormat _display = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final DateFormat _monthDisplay = DateFormat('MMMM yyyy', 'pt_BR');
  static final DateFormat _api = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _referenceMonth = DateTime(now.year, now.month + 1);
    final lastDay =
        DateTime(_referenceMonth.year, _referenceMonth.month + 1, 0).day;
    _dueDate = DateTime(_referenceMonth.year, _referenceMonth.month,
        widget.rental.dueDay.clamp(1, lastDay));
    if (widget.rental.monthlyValue > 0) {
      _valueController.text =
          CurrencyInputFormatter.format(widget.rental.monthlyValue);
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  double get _value {
    final digits = _valueController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return (int.tryParse(digits) ?? 0) / 100.0;
  }

  bool get _canSubmit => _value > 0 && _dueDate != null;

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _referenceMonth,
      firstDate: DateTime(DateTime.now().year, DateTime.now().month),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
      helpText: 'Mês de referência',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _referenceMonth = DateTime(picked.year, picked.month);
      final lastDay =
          DateTime(_referenceMonth.year, _referenceMonth.month + 1, 0).day;
      _dueDate = DateTime(_referenceMonth.year, _referenceMonth.month,
          widget.rental.dueDay.clamp(1, lastDay));
    });
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _dueDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
      helpText: 'Data de vencimento',
    );
    if (picked == null || !mounted) return;
    setState(() => _dueDate = picked);
  }

  void _submit() {
    if (!_canSubmit) return;
    final month =
        '${_referenceMonth.year.toString().padLeft(4, '0')}-${_referenceMonth.month.toString().padLeft(2, '0')}';
    Navigator.of(context).pop(_NewPaymentData(
      referenceMonth: month,
      dueDate: _api.format(_dueDate!),
      value: _value,
      observations: _obsController.text.trim().isEmpty
          ? null
          : _obsController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final mq = MediaQuery.of(context);
    final monthLabel = _monthDisplay.format(_referenceMonth);

    Widget pickField({
      required IconData icon,
      required String label,
      required String value,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          decoration: BoxDecoration(
            color: fieldFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: emerald.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: emerald),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronDown, size: 15, color: secondary),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.backgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: emerald.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(LucideIcons.walletCards,
                          color: emerald, size: 18),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nova parcela',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Adiciona uma cobrança avulsa a este contrato.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                pickField(
                  icon: LucideIcons.calendarDays,
                  label: 'MÊS DE REFERÊNCIA',
                  value: monthLabel[0].toUpperCase() + monthLabel.substring(1),
                  onTap: _pickMonth,
                ),
                const SizedBox(height: 10),
                pickField(
                  icon: LucideIcons.calendarClock,
                  label: 'VENCIMENTO',
                  value:
                      _dueDate == null ? 'Selecionar' : _display.format(_dueDate!),
                  onTap: _pickDueDate,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: fieldFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: ThemeHelpers.borderLightColor(context)),
                  ),
                  child: TextField(
                    controller: _valueController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      prefixText: 'R\$ ',
                      prefixStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                      labelText: 'Valor da parcela',
                      labelStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: fieldFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: ThemeHelpers.borderLightColor(context)),
                  ),
                  child: TextField(
                    controller: _obsController,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ThemeHelpers.textColor(context),
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      labelText: 'Observações (opcional)',
                      labelStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: emerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text(
                    'Adicionar parcela',
                    style: TextStyle(fontWeight: FontWeight.w800),
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
