import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/mcmv_models.dart';
import '../services/mcmv_service.dart';
import '../widgets/mcmv_common.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Tela **Detalhe do lead MCMV** — todas as seções do web
/// (`MCMVLeadDetailsPage`) em layout flush de seções (padrão Perfil):
/// hero com identidade + score, ações de contato no topo, seções Contato /
/// Perfil MCMV / Andamento / Avaliação e as mesmas ações de status do web
/// (capturar, contactado → qualificado → converter, perder, avaliar).
class McmvLeadDetailsPage extends StatefulWidget {
  final String leadId;

  /// Lead vindo da listagem (evita a varredura paginada — o backend não expõe
  /// `GET /mcmv/leads/:id`). Se nulo, a página busca sozinha.
  final McmvLead? initialLead;

  const McmvLeadDetailsPage({
    super.key,
    required this.leadId,
    this.initialLead,
  });

  @override
  State<McmvLeadDetailsPage> createState() => _McmvLeadDetailsPageState();
}

class _McmvLeadDetailsPageState extends State<McmvLeadDetailsPage> {
  static const double _kPadH = 16;

  McmvLead? _lead;
  bool _loading = false;
  bool _processing = false;
  String? _error;

  bool get _canView =>
      mcmvModuleEnabled() &&
      ModuleAccessService.instance.hasPermission(McmvPermissions.leadView);
  bool get _canCapture =>
      ModuleAccessService.instance.hasPermission(McmvPermissions.leadCapture);
  bool get _canUpdate =>
      ModuleAccessService.instance.hasPermission(McmvPermissions.leadUpdate);
  bool get _canConvert =>
      ModuleAccessService.instance.hasPermission(McmvPermissions.leadConvert);
  bool get _canRate =>
      ModuleAccessService.instance.hasPermission(McmvPermissions.leadRate);

  @override
  void initState() {
    super.initState();
    _lead = widget.initialLead;
    if (_lead == null) _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await McmvService.instance.findLeadById(widget.leadId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _lead = res.data;
      } else {
        _error = res.message ?? 'Erro ao carregar lead';
      }
    });
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? danger : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _runAction(
    Future<ApiResponse<McmvLead>> Function() action, {
    required String successMessage,
  }) async {
    setState(() => _processing = true);
    final res = await action();
    if (!mounted) return;
    setState(() => _processing = false);
    if (res.success) {
      if (res.data != null) {
        setState(() => _lead = res.data);
      } else {
        _fetch();
      }
      _snack(successMessage);
    } else {
      _snack(res.message ?? 'Não foi possível concluir a ação', error: true);
    }
  }

  Future<void> _capture() => _runAction(
        () => McmvService.instance.captureLead(widget.leadId),
        successMessage: 'Lead capturado com sucesso!',
      );

  Future<void> _updateStatus(McmvLeadStatus status) => _runAction(
        () => McmvService.instance.updateLeadStatus(widget.leadId, status),
        successMessage: 'Status atualizado com sucesso!',
      );

  Future<void> _markLost() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Marcar como perdido?'),
        content: const Text(
          'O lead sai do fluxo de trabalho. Essa ação não pode ser desfeita '
          'pelo app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Marcar como perdido'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _updateStatus(McmvLeadStatus.lost);
  }

  Future<void> _convert() async {
    setState(() => _processing = true);
    final res =
        await McmvService.instance.convertLeadToClient(widget.leadId);
    if (!mounted) return;
    setState(() => _processing = false);
    if (res.success && res.data != null) {
      if (res.data!.lead != null) {
        setState(() => _lead = res.data!.lead);
      } else {
        _fetch();
      }
      _snack('Lead convertido em cliente com sucesso!');
    } else {
      _snack(res.message ?? 'Erro ao converter lead', error: true);
    }
  }

  Future<void> _openRateSheet() async {
    final result = await showModalBottomSheet<({int rating, String comment})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => const _RateLeadSheet(),
    );
    if (result == null) return;
    await _runAction(
      () => McmvService.instance.rateLead(
        widget.leadId,
        result.rating,
        comment: result.comment.isEmpty ? null : result.comment,
      ),
      successMessage: 'Lead avaliado com sucesso!',
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Lead MCMV',
        showBottomNavigation: false,
        body: McmvDeniedView(
          message: 'Você não tem acesso aos leads do MCMV.',
          permission: McmvPermissions.leadView,
        ),
      );
    }

    Widget body;
    if (_loading && _lead == null) {
      body = _buildSkeleton(context);
    } else if (_error != null && _lead == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 24),
        child: McmvErrorState(message: _error!, onRetry: _fetch),
      );
    } else if (_lead == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 24),
        child: McmvEmptyState(
          icon: LucideIcons.searchX,
          title: 'Lead não encontrado',
          body: 'Esse lead pode ter sido capturado por outra empresa.',
          tone: mcmvAccentColor(context),
        ),
      );
    } else {
      body = _buildContent(context, _lead!);
    }

    return AppScaffold(
      title: 'Lead MCMV',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: mcmvAccentColor(context),
        onRefresh: _fetch,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: body,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, McmvLead lead) {
    final dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 12, _kPadH, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(context, lead),
          const SizedBox(height: 16),
          _buildContactActions(context, lead),
          const SizedBox(height: 22),
          _SectionHeader(
            label: 'Contato',
            icon: LucideIcons.contact,
            tone: mcmvAccentColor(context),
          ),
          _InfoRow(label: 'CPF', value: _maskedCpf(lead.cpf)),
          _InfoRow(label: 'Email', value: _dashIfEmpty(lead.email)),
          _InfoRow(label: 'Telefone', value: _maskedPhone(lead.phone)),
          _InfoRow(
            label: 'Cidade/Estado',
            value: _dashIfEmpty(lead.locationLabel),
            icon: LucideIcons.mapPin,
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Perfil MCMV',
            icon: LucideIcons.house,
            tone: Theme.of(context).brightness == Brightness.dark
                ? AppColors.status.purpleDarkMode
                : AppColors.status.purple,
          ),
          _InfoRow(
            label: 'Renda mensal',
            value: lead.monthlyIncome > 0
                ? _money.format(lead.monthlyIncome)
                : '—',
          ),
          _InfoRow(
            label: 'Tamanho da família',
            value: lead.familySize > 0
                ? '${lead.familySize} pessoa${lead.familySize == 1 ? '' : 's'}'
                : '—',
          ),
          _InfoRow(label: 'Faixa de renda', value: lead.incomeRange.label),
          _EligibleRow(eligible: lead.eligible),
          _ScoreRow(score: lead.score),
          const SizedBox(height: 20),
          _SectionHeader(
            label: 'Andamento',
            icon: LucideIcons.activity,
            tone: mcmvLeadStatusColor(context, lead.status),
          ),
          _StatusRow(status: lead.status),
          _InfoRow(
            label: 'Capturado pela empresa',
            value: lead.isCaptured ? 'Sim' : 'Ainda disponível',
          ),
          if (lead.followUpCount > 0)
            _InfoRow(
              label: 'Follow-ups',
              value: '${lead.followUpCount}',
            ),
          if (lead.lastContactAt != null)
            _InfoRow(
              label: 'Último contato',
              value: dateFmt.format(lead.lastContactAt!.toLocal()),
            ),
          if (lead.createdAt != null)
            _InfoRow(
              label: 'Criado em',
              value: dateFmt.format(lead.createdAt!.toLocal()),
            ),
          if (lead.rating != null) ...[
            const SizedBox(height: 20),
            _SectionHeader(
              label: 'Avaliação',
              icon: LucideIcons.star,
              tone: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.status.warningDarkMode
                  : AppColors.status.warning,
            ),
            _RatingBlock(
              rating: lead.rating!,
              comment: lead.ratingComment,
              ratedAt: lead.ratedAt,
            ),
          ],
          const SizedBox(height: 26),
          _buildActions(context, lead),
        ],
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, McmvLead lead) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = mcmvAccentColor(context);
    final tone = mcmvLeadStatusColor(context, lead.status);
    final scoreTone = mcmvScoreColor(context, lead.score);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

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
              'LEAD MCMV · ${lead.status.label.toUpperCase()}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                lead.name.trim().isEmpty ? 'Lead sem nome' : lead.name.trim(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.6,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Score em destaque — número grande + rótulo.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${lead.score}%',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scoreTone,
                    letterSpacing: -0.8,
                    height: 1.0,
                  ),
                ),
                Text(
                  'SCORE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            McmvStatusPill(label: lead.status.label, color: tone),
            McmvStatusPill(label: lead.incomeRange.label, color: secondary),
            McmvStatusPill(
              label: lead.eligible ? 'Elegível' : 'Não elegível',
              color: lead.eligible ? emerald : danger,
              icon: lead.eligible ? LucideIcons.check : LucideIcons.x,
            ),
            if (lead.isConverted)
              McmvStatusPill(
                label: 'Cliente criado',
                color: emerald,
                icon: LucideIcons.userCheck,
              ),
          ],
        ),
      ],
    );
  }

  // ─── Contato rápido ──────────────────────────────────────────────────────

  Widget _buildContactActions(BuildContext context, McmvLead lead) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final phone = lead.phone.trim();
    final email = lead.email.trim();
    final buttons = <Widget>[];

    if (phone.isNotEmpty) {
      buttons.add(_contactButton(
        context,
        icon: LucideIcons.messageCircle,
        label: 'WhatsApp',
        color: kMcmvWhatsappGreen,
        onTap: () => mcmvLaunchUri(
          context,
          'https://wa.me/${mcmvWhatsappNumber(phone)}',
        ),
      ));
      buttons.add(_contactButton(
        context,
        icon: LucideIcons.phone,
        label: 'Ligar',
        color: kMcmvCallBlue,
        onTap: () => mcmvLaunchUri(context, 'tel:${mcmvOnlyDigits(phone)}'),
      ));
    }
    if (email.isNotEmpty) {
      buttons.add(_contactButton(
        context,
        icon: LucideIcons.mail,
        label: 'Email',
        color: amber,
        onTap: () => mcmvLaunchUri(context, 'mailto:$email'),
      ));
    }
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }

  Widget _contactButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: color.withValues(alpha: isDark ? 0.14 : 0.08),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Ações de status (mesmas regras do web) ──────────────────────────────

  Widget _buildActions(BuildContext context, McmvLead lead) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = mcmvAccentColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    final actions = <Widget>[];

    ButtonStyle filled(Color color) => FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        );
    ButtonStyle outlined(Color color) => OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        );

    // Capturar: lead ainda livre (paridade com o card do web).
    if (!lead.isCaptured && _canCapture) {
      actions.add(FilledButton.icon(
        onPressed: _processing ? null : _capture,
        style: filled(accent),
        icon: const Icon(LucideIcons.userPlus, size: 18),
        label: const Text('Capturar lead',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ));
    }

    if (lead.isCaptured && lead.status.isOpen) {
      if (lead.status == McmvLeadStatus.newLead && _canUpdate) {
        actions.add(FilledButton.icon(
          onPressed:
              _processing ? null : () => _updateStatus(McmvLeadStatus.contacted),
          style: filled(amber),
          icon: const Icon(LucideIcons.phone, size: 18),
          label: const Text('Marcar como contactado',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ));
      }
      if (lead.status == McmvLeadStatus.contacted && _canUpdate) {
        actions.add(FilledButton.icon(
          onPressed:
              _processing ? null : () => _updateStatus(McmvLeadStatus.qualified),
          style: filled(isDark
              ? AppColors.status.purpleDarkMode
              : AppColors.status.purple),
          icon: const Icon(LucideIcons.userCheck, size: 18),
          label: const Text('Marcar como qualificado',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ));
      }
      if (lead.status == McmvLeadStatus.qualified &&
          !lead.isConverted &&
          _canConvert) {
        actions.add(FilledButton.icon(
          onPressed: _processing ? null : _convert,
          style: filled(emerald),
          icon: const Icon(LucideIcons.circleCheckBig, size: 18),
          label: const Text('Converter em cliente',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ));
      }
      if (_canUpdate) {
        actions.add(OutlinedButton.icon(
          onPressed: _processing ? null : _markLost,
          style: outlined(danger),
          icon: const Icon(LucideIcons.xCircle, size: 18),
          label: const Text('Marcar como perdido',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ));
      }
    }

    if (lead.isCaptured && lead.rating == null && _canRate) {
      actions.add(OutlinedButton.icon(
        onPressed: _processing ? null : _openRateSheet,
        style: outlined(amber),
        icon: const Icon(LucideIcons.star, size: 18),
        label: const Text('Avaliar lead',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ));
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          label: 'Ações',
          icon: LucideIcons.zap,
          tone: accent,
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          actions[i],
        ],
        if (_processing) ...[
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child:
                  CircularProgressIndicator(strokeWidth: 2.2, color: accent),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Skeleton fiel ───────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 12, _kPadH, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkeletonText(width: 170, height: 11, borderRadius: 999),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: SkeletonText(width: double.infinity, height: 26)),
              SizedBox(width: 24),
              SkeletonText(width: 60, height: 26),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              SkeletonText(width: 70, height: 20, borderRadius: 999),
              SizedBox(width: 6),
              SkeletonText(width: 64, height: 20, borderRadius: 999),
              SizedBox(width: 6),
              SkeletonText(width: 76, height: 20, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(
                  child:
                      SkeletonBox(width: double.infinity, height: 42,
                          borderRadius: 13)),
              SizedBox(width: 10),
              Expanded(
                  child:
                      SkeletonBox(width: double.infinity, height: 42,
                          borderRadius: 13)),
              SizedBox(width: 10),
              Expanded(
                  child:
                      SkeletonBox(width: double.infinity, height: 42,
                          borderRadius: 13)),
            ],
          ),
          const SizedBox(height: 24),
          for (var s = 0; s < 2; s++) ...[
            const SkeletonText(width: 110, height: 12, borderRadius: 999),
            const SizedBox(height: 14),
            for (var i = 0; i < 4; i++) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  SkeletonText(width: 110, height: 13),
                  SkeletonText(width: 120, height: 13),
                ],
              ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  static String _dashIfEmpty(String v) => v.trim().isEmpty ? '—' : v.trim();

  static String _maskedCpf(String cpf) {
    final digits = mcmvOnlyDigits(cpf);
    return digits.isEmpty ? '—' : Masks.cpf(digits);
  }

  static String _maskedPhone(String phone) {
    final digits = mcmvOnlyDigits(phone);
    return digits.isEmpty ? '—' : Masks.phone(digits);
  }
}

// ─── Blocos de seção/linha ───────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tone;

  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Container(
                height: 1,
                color: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const _InfoRow({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EligibleRow extends StatelessWidget {
  final bool eligible;

  const _EligibleRow({required this.eligible});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = eligible
        ? (isDark ? AppColors.status.greenDarkMode : AppColors.status.green)
        : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Elegível ao programa',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          McmvStatusPill(
            label: eligible ? 'Sim' : 'Não',
            color: tone,
            icon: eligible ? LucideIcons.check : LucideIcons.x,
          ),
        ],
      ),
    );
  }
}

/// Linha do score com barra de progresso semântica.
class _ScoreRow extends StatelessWidget {
  final int score;

  const _ScoreRow({required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = mcmvScoreColor(context, score);
    final clamped = score.clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Score do lead',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: clamped / 100,
                minHeight: 6,
                backgroundColor:
                    ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$clamped%',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final McmvLeadStatus status;

  const _StatusRow({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = mcmvLeadStatusColor(context, status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Status',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          McmvStatusPill(
            label: status.label,
            color: tone,
            icon: mcmvLeadStatusIcon(status),
          ),
        ],
      ),
    );
  }
}

class _RatingBlock extends StatelessWidget {
  final int rating;
  final String? comment;
  final DateTime? ratedAt;

  const _RatingBlock({
    required this.rating,
    this.comment,
    this.ratedAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(
                    LucideIcons.star,
                    size: 18,
                    color: i <= rating
                        ? amber
                        : ThemeHelpers.borderColor(context),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                '$rating/5',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              if (ratedAt != null)
                Text(
                  DateFormat('dd/MM/yyyy', 'pt_BR').format(ratedAt!.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if ((comment ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment!.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Bottom sheet de avaliação ───────────────────────────────────────────────

class _RateLeadSheet extends StatefulWidget {
  const _RateLeadSheet();

  @override
  State<_RateLeadSheet> createState() => _RateLeadSheetState();
}

class _RateLeadSheetState extends State<_RateLeadSheet> {
  int _rating = 0;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: amber.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
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
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: amber.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(LucideIcons.star, color: amber, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Avaliar lead',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Qualidade do lead de 1 a 5 estrelas.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      InkResponse(
                        radius: 26,
                        onTap: () => setState(() => _rating = i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            LucideIcons.star,
                            size: 34,
                            color: i <= _rating
                                ? amber
                                : ThemeHelpers.borderColor(context),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: fieldFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: ThemeHelpers.borderLightColor(context)),
                  ),
                  child: TextField(
                    controller: _commentController,
                    maxLines: 3,
                    maxLength: 1000,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ThemeHelpers.textColor(context),
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      hintText: 'Comentário (opcional)…',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: secondary.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _rating == 0
                      ? null
                      : () => Navigator.of(context).pop((
                            rating: _rating,
                            comment: _commentController.text.trim(),
                          )),
                  style: FilledButton.styleFrom(
                    backgroundColor: amber,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(LucideIcons.star, size: 18),
                  label: Text(
                    _rating == 0
                        ? 'Escolha uma nota'
                        : 'Enviar avaliação ($_rating/5)',
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
