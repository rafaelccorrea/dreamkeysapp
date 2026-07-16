import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/visit_report_access.dart';
import '../models/visit_report_model.dart';
import '../services/visit_report_service.dart';
import '../widgets/visit_report_card.dart'
    show VisitDateLeaf, visitStatusColor;
import '../widgets/visit_signature_link_sheet.dart';

/// Detalhe do **relatório de visita** — seções read-rich (assinatura, imóveis
/// visitados, detalhes, observações) + ações: compartilhar o link público de
/// assinatura via WhatsApp, copiar link e gerar/regenerar link.
class VisitReportDetailPage extends StatefulWidget {
  final String reportId;

  const VisitReportDetailPage({super.key, required this.reportId});

  @override
  State<VisitReportDetailPage> createState() => _VisitReportDetailPageState();
}

class _VisitReportDetailPageState extends State<VisitReportDetailPage> {
  VisitReport? _report;
  bool _loading = true;
  String? _error;
  bool _linkBusy = false;

  bool get _canUpdate =>
      ModuleAccessService.instance.hasPermission(VisitReportAccess.update);
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission(VisitReportAccess.delete);

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

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
    final res = await VisitReportService.instance.getById(widget.reportId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _report = res.data;
      } else {
        _error = res.message ?? 'Relatório não encontrado.';
      }
    });
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<VisitSignatureLink?> _resolveLink({bool allowGenerate = false}) async {
    final r = _report;
    if (r == null) return null;
    setState(() => _linkBusy = true);
    VisitSignatureLink? link;
    String? failMessage;

    if (r.hasActiveLink) {
      final res = await VisitReportService.instance.getSignatureLink(r.id);
      if (res.success && res.data != null && res.data!.url.isNotEmpty) {
        link = res.data;
      } else {
        failMessage = res.message;
      }
    }
    if (link == null && allowGenerate && !r.isSigned && _canUpdate) {
      final res =
          await VisitReportService.instance.generateSignatureLink(r.id);
      if (res.success && res.data != null && res.data!.url.isNotEmpty) {
        link = res.data;
        failMessage = null;
        _load();
      } else {
        failMessage = res.message;
      }
    }

    if (mounted) {
      setState(() => _linkBusy = false);
      if (link == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(failMessage ?? 'Link expirado ou não encontrado.'),
        ));
      }
    }
    return link;
  }

  Future<void> _generateLink() async {
    final r = _report;
    if (r == null || r.isSigned) return;
    setState(() => _linkBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    final res = await VisitReportService.instance.generateSignatureLink(r.id);
    if (!mounted) return;
    setState(() => _linkBusy = false);
    if (res.success && res.data != null && res.data!.url.isNotEmpty) {
      await _load();
      if (!mounted) return;
      await VisitSignatureLinkSheet.show(
        context,
        report: _report ?? r,
        link: res.data!,
      );
    } else {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(res.message ?? 'Erro ao gerar link.'),
      ));
    }
  }

  Future<void> _shareWhatsApp() async {
    final r = _report;
    if (r == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final link = await _resolveLink(allowGenerate: true);
    if (link == null || !mounted) return;
    final ok = await shareVisitLinkOnWhatsApp(r, link.url);
    if (!ok && mounted) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Não foi possível abrir o WhatsApp.'),
      ));
    }
  }

  Future<void> _copyLink() async {
    final messenger = ScaffoldMessenger.of(context);
    final link = await _resolveLink();
    if (link == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: link.url));
    messenger.showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Link copiado!'),
    ));
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.of(context)
        .pushNamed(VisitReportRoutes.edit(widget.reportId));
    if (changed == true && mounted) _load();
  }

  Future<void> _confirmDelete() async {
    final r = _report;
    if (r == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Excluir relatório',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        content: Text(
          'O relatório de visita de ${r.clientLabel} será excluído. '
          'Esta ação não pode ser desfeita.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final res = await VisitReportService.instance.remove(r.id);
    if (!mounted) return;
    if (res.success) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Relatório excluído.'),
      ));
      navigator.pop(true);
    } else {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(res.message ?? 'Erro ao excluir.'),
      ));
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Relatório de visita',
      showBottomNavigation: false,
      actions: [
        if (_report != null && _canUpdate)
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(LucideIcons.penLine, size: 20),
            onPressed: _openEdit,
          ),
        if (_report != null && _canDelete)
          IconButton(
            tooltip: 'Excluir',
            icon: const Icon(LucideIcons.trash2, size: 20),
            onPressed: _confirmDelete,
          ),
      ],
      body: _loading
          ? _buildSkeleton()
          : _error != null
              ? _buildError(context)
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: _buildContent(context, _report!),
                ),
    );
  }

  Widget _buildContent(BuildContext context, VisitReport r) {
    final theme = Theme.of(context);
    final tone = visitStatusColor(context, r.signatureStatus);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final dateTimeFmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
    final longDateFmt = DateFormat("EEEE, d 'de' MMMM 'de' y", 'pt_BR');

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho — glyph tonal + cliente + pills.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Folhinha da data da visita — mesma identidade de agenda da
              // listagem (status fica na pill e no painel de assinatura).
              VisitDateLeaf(date: r.visitDate, tone: _accent, width: 54),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.clientLabel,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill(context, r.signatureStatus.label, tone),
                        _pill(
                          context,
                          '${r.properties.length} imóve${r.properties.length == 1 ? 'l' : 'is'}',
                          secondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Row(
              children: [
                Icon(LucideIcons.calendarDays, size: 13, color: secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.visitDate != null
                        ? 'Visita em ${longDateFmt.format(r.visitDate!)}'
                        : 'Data da visita não informada',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Assinatura do cliente ──────────────────────────────────────
          _sectionEyebrow(context, LucideIcons.signature,
              'ASSINATURA DO CLIENTE', tone),
          const SizedBox(height: 10),
          _signaturePanel(context, r, tone, dateFmt, dateTimeFmt),

          const SizedBox(height: 24),

          // ── Imóveis visitados ──────────────────────────────────────────
          _sectionEyebrow(context, LucideIcons.building2, 'IMÓVEIS VISITADOS',
              _accent),
          const SizedBox(height: 6),
          if (r.properties.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nenhum imóvel registrado.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            for (var i = 0; i < r.properties.length; i++)
              _propertyRow(context, i, r.properties[i]),

          const SizedBox(height: 24),

          // ── Detalhes ───────────────────────────────────────────────────
          _sectionEyebrow(
              context, LucideIcons.clipboardList, 'DETALHES', secondary),
          const SizedBox(height: 4),
          if ((r.createdByName ?? '').isNotEmpty)
            _detailRow(context, 'Corretor', r.createdByName!,
                icon: LucideIcons.userRound),
          if ((r.kanbanTaskTitle ?? '').isNotEmpty)
            _detailRow(context, 'Negociação', r.kanbanTaskTitle!,
                icon: LucideIcons.kanban),
          if (r.createdAt != null)
            _detailRow(
                context, 'Criado em', dateTimeFmt.format(r.createdAt!.toLocal())),
          if (r.updatedAt != null)
            _detailRow(context, 'Atualizado em',
                dateTimeFmt.format(r.updatedAt!.toLocal())),

          if ((r.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionEyebrow(
                context, LucideIcons.penLine, 'OBSERVAÇÕES', secondary),
            const SizedBox(height: 8),
            Text(
              r.notes!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Painel da assinatura — cor por significado: âmbar aguardando, verde
  /// assinado, neutro expirado. Ações principais no próprio painel.
  Widget _signaturePanel(
    BuildContext context,
    VisitReport r,
    Color tone,
    DateFormat dateFmt,
    DateFormat dateTimeFmt,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    final String title;
    final String body;
    if (r.isSigned) {
      title = 'Relatório assinado';
      final who = (r.signerName ?? '').isNotEmpty ? r.signerName! : r.clientLabel;
      body = r.signedAt != null
          ? 'Assinado por $who em ${dateTimeFmt.format(r.signedAt!.toLocal())}.'
          : 'Assinado por $who.';
    } else if (r.hasActiveLink) {
      title = 'Aguardando assinatura';
      body =
          'O link foi gerado e expira em ${dateFmt.format(r.signatureExpiresAt!.toLocal())}. Envie ao cliente para confirmar os imóveis visitados e assinar.';
    } else if (r.signatureStatus == VisitSignatureStatus.expired) {
      title = 'Link expirado';
      body =
          'O link de assinatura venceu sem ser assinado. Gere um novo link e reenvie ao cliente.';
    } else {
      title = 'Nenhum link ativo';
      body =
          'Gere o link público de assinatura e envie ao cliente pelo WhatsApp.';
    }

    final canSendLink = !r.isSigned;
    final hasLink = r.hasActiveLink;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: tone.withValues(alpha: isDark ? 0.1 : 0.06),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
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
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (canSendLink) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _linkBusy ? null : _shareWhatsApp,
                    icon: _linkBusy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.messageCircle, size: 16),
                    label: const Text(
                      'WhatsApp',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                if (hasLink) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _linkBusy ? null : _copyLink,
                      icon: const Icon(LucideIcons.copy, size: 15),
                      label: const Text(
                        'Copiar link',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        side:
                            BorderSide(color: blue.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_canUpdate) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _linkBusy ? null : _generateLink,
                  icon: const Icon(LucideIcons.rotateCw, size: 14),
                  label: Text(
                    hasLink ? 'Gerar novo link' : 'Gerar link de assinatura',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: secondary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _propertyRow(
      BuildContext context, int index, VisitReportProperty p) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withValues(alpha: isDark ? 0.18 : 0.1),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.address.isNotEmpty ? p.address : 'Endereço não informado',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    height: 1.3,
                  ),
                ),
                if ((p.reference ?? '').isNotEmpty ||
                    (p.propertyCode ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if ((p.reference ?? '').isNotEmpty) p.reference!,
                      if ((p.propertyCode ?? '').isNotEmpty)
                        'CÓD ${p.propertyCode}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if ((p.propertyId ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Icon(LucideIcons.link, size: 13, color: secondary),
            ),
        ],
      ),
    );
  }

  Widget _sectionEyebrow(
      BuildContext context, IconData icon, String label, Color tone) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 13, color: tone),
        const SizedBox(width: 6),
        Text(
          label,
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
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(BuildContext context, String label, String value,
      {IconData? icon}) {
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

  Widget _pill(BuildContext context, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  /// Skeleton fiel: cabeçalho com glyph + painel de assinatura + linhas.
  Widget _buildSkeleton() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 54, height: 62, borderRadius: 14),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 180, height: 20),
                    SizedBox(height: 8),
                    SkeletonText(width: 130, height: 14, borderRadius: 999),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SkeletonBox(
              width: double.infinity, height: 140, borderRadius: 16),
          const SizedBox(height: 24),
          const SkeletonText(width: 150, height: 12),
          const SizedBox(height: 14),
          for (var i = 0; i < 3; i++) ...[
            Row(
              children: const [
                SkeletonBox(width: 26, height: 26, borderRadius: 999),
                SizedBox(width: 11),
                Expanded(child: SkeletonText(height: 14)),
              ],
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: danger.withValues(alpha: 0.12),
                border: Border.all(color: danger.withValues(alpha: 0.32)),
              ),
              child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              _error ?? 'Relatório não encontrado.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
