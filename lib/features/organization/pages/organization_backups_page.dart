import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/leads_export_models.dart';
import '../organization_access.dart';
import '../services/leads_export_service.dart';
import '../widgets/org_ui.dart';

enum _BackupsTab { create, activity, backups }

final NumberFormat _intFmt = NumberFormat.decimalPattern('pt_BR');
final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
final DateFormat _dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

String _formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Tela **Backups** — exportação geral de leads com fila de jobs e histórico
/// de backups persistidos (60 dias), paridade com o `LeadsExportPage.tsx`
/// (aba de leads) do painel. Requer `backup:view`.
class OrganizationBackupsPage extends StatefulWidget {
  const OrganizationBackupsPage({super.key});

  @override
  State<OrganizationBackupsPage> createState() =>
      _OrganizationBackupsPageState();
}

class _OrganizationBackupsPageState extends State<OrganizationBackupsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  _BackupsTab _tab = _BackupsTab.create;

  // Nova exportação
  final LeadsExportDraft _draft = LeadsExportDraft();
  final TextEditingController _searchController = TextEditingController();
  bool _submitting = false;

  // Jobs
  List<LeadsExportJob> _jobs = const [];
  bool _jobsLoading = true;
  String? _jobsError;
  Timer? _pollTimer;
  String? _busyJobId;

  // Backups persistidos
  LeadsExportBackupList _backups = LeadsExportBackupList.empty;
  bool _backupsLoading = true;
  String? _backupsError;
  String _scope = 'mine';
  String? _busyBackupId;

  bool get _canView => OrganizationAccess.canViewBackups();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _draft.createdAfter = DateTime(now.year, now.month, 1);
    _draft.createdBefore = DateTime(now.year, now.month, now.day);
    _loadJobs();
    _loadBackups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _accent =>
      _isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

  Color get _amber =>
      _isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

  Color get _blue =>
      _isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

  Color get _danger =>
      _isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

  Color _statusTone(LeadsExportJobStatus status) {
    switch (status) {
      case LeadsExportJobStatus.pending:
        return _amber;
      case LeadsExportJobStatus.processing:
        return _blue;
      case LeadsExportJobStatus.completed:
        return _accent;
      case LeadsExportJobStatus.failed:
        return _danger;
      case LeadsExportJobStatus.cancelled:
      case LeadsExportJobStatus.unknown:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  IconData _statusIcon(LeadsExportJobStatus status) {
    switch (status) {
      case LeadsExportJobStatus.pending:
        return LucideIcons.hourglass;
      case LeadsExportJobStatus.processing:
        return LucideIcons.loader;
      case LeadsExportJobStatus.completed:
        return LucideIcons.circleCheckBig;
      case LeadsExportJobStatus.failed:
        return LucideIcons.circleAlert;
      case LeadsExportJobStatus.cancelled:
      case LeadsExportJobStatus.unknown:
        return LucideIcons.circleX;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadJobs({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _jobsLoading = true;
        _jobsError = null;
      });
    }
    final res = await LeadsExportService.instance.listMyJobs();
    if (!mounted) return;
    setState(() {
      _jobsLoading = false;
      if (res.success && res.data != null) {
        final hadActive = _jobs.any((j) => j.status.isActive);
        _jobs = res.data!;
        _jobsError = null;
        final hasActive = _jobs.any((j) => j.status.isActive);
        // Job acabou de concluir → histórico de backups pode ter mudado.
        if (hadActive && !hasActive) _loadBackups(silent: true);
      } else if (!silent) {
        _jobsError = res.message ?? 'Erro ao carregar exportações';
      }
    });
    _syncPolling();
  }

  Future<void> _loadBackups({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _backupsLoading = true;
        _backupsError = null;
      });
    }
    final res =
        await LeadsExportService.instance.listBackups(scope: _scope, limit: 100);
    if (!mounted) return;
    setState(() {
      _backupsLoading = false;
      if (res.success && res.data != null) {
        _backups = res.data!;
        _backupsError = null;
      } else if (!silent) {
        _backupsError = res.message ?? 'Erro ao carregar backups';
      }
    });
  }

  /// Liga o polling (4s) enquanto houver job vivo; desliga quando não houver.
  void _syncPolling() {
    final hasActive = _jobs.any((j) => j.status.isActive);
    if (hasActive && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        _loadJobs(silent: true);
      });
    } else if (!hasActive && _pollTimer != null) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadJobs(), _loadBackups()]);
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _submitExport() async {
    setState(() => _submitting = true);
    _draft.search = _searchController.text;
    final res = await LeadsExportService.instance.createJob(_draft);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.success) {
      _snack('Exportação enfileirada — acompanhe em "Atividade".');
      setState(() => _tab = _BackupsTab.activity);
      _loadJobs();
    } else {
      _snack(res.message ?? 'Não foi possível enfileirar a exportação');
    }
  }

  Future<void> _cancelJob(LeadsExportJob job) async {
    setState(() => _busyJobId = job.jobId);
    final res = await LeadsExportService.instance.cancelJob(job.jobId);
    if (!mounted) return;
    setState(() => _busyJobId = null);
    _snack(res.success
        ? 'Exportação cancelada.'
        : res.message ?? 'Não foi possível cancelar.');
    if (res.success) _loadJobs(silent: true);
  }

  Future<void> _downloadJob(LeadsExportJob job) async {
    setState(() => _busyJobId = job.jobId);
    final res = await LeadsExportService.instance.downloadJobFile(
      job.jobId,
      fallbackName: job.fileName ?? 'leads_export.${job.format.apiValue}',
    );
    if (!mounted) return;
    setState(() => _busyJobId = null);
    await _openDownloaded(res.success ? res.data : null,
        errorMessage: res.message);
  }

  Future<void> _downloadBackup(LeadsExportBackup backup) async {
    setState(() => _busyBackupId = backup.id);
    final res = await LeadsExportService.instance.downloadBackupFile(
      backup.id,
      fallbackName: backup.fileName,
    );
    if (!mounted) return;
    setState(() => _busyBackupId = null);
    await _openDownloaded(res.success ? res.data : null,
        errorMessage: res.message);
  }

  /// Salva os bytes num ficheiro temporário e abre com o app do sistema
  /// (mesmo padrão do download de PDF das propostas).
  Future<void> _openDownloaded(
    ({List<int> bytes, String fileName})? data, {
    String? errorMessage,
  }) async {
    if (data == null) {
      _snack(errorMessage ?? 'Erro ao baixar arquivo');
      return;
    }
    try {
      final safeName = data.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${Directory.systemTemp.path}/$safeName');
      await file.writeAsBytes(data.bytes, flush: true);
      final ok = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) _snack('Arquivo salvo em ${file.path}');
    } catch (e) {
      if (mounted) _snack('Erro ao abrir arquivo: $e');
    }
  }

  Future<void> _rerunBackup(LeadsExportBackup backup) async {
    setState(() => _busyBackupId = backup.id);
    final res = await LeadsExportService.instance.rerunBackup(backup.id);
    if (!mounted) return;
    setState(() => _busyBackupId = null);
    if (res.success) {
      _snack('Exportação repetida com os mesmos filtros.');
      setState(() => _tab = _BackupsTab.activity);
      _loadJobs();
    } else {
      _snack(res.message ?? 'Erro ao repetir exportação');
    }
  }

  Future<void> _deleteBackup(LeadsExportBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Apagar backup'),
        content: Text(
          'Apagar o backup "${backup.fileName}"? O arquivo não poderá mais '
          'ser baixado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyBackupId = backup.id);
    final res = await LeadsExportService.instance.deleteBackup(backup.id);
    if (!mounted) return;
    setState(() => _busyBackupId = null);
    if (res.success) {
      _snack('Backup apagado.');
      _loadBackups();
    } else {
      _snack(res.message ?? 'Erro ao apagar backup');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Backups',
        showBottomNavigation: false,
        body: OrgDeniedView(
          message: 'Você não tem acesso aos backups.',
          hint: 'Solicite ao administrador o acesso a backups e exportações.',
        ),
      );
    }
    return AppScaffold(
      title: 'Backups',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent,
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
                    child: _buildHero(context),
                  ),
                  const SizedBox(height: _kSectionGap),
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

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final activeJobs = _jobs.where((j) => j.status.isActive).length;
    final totalBackups = _backups.total;
    final totalRows =
        _backups.data.fold<int>(0, (acc, b) => acc + b.totalRows);
    final dot = activeJobs > 0 ? _amber : _accent;
    final subtitle = activeJobs > 0
        ? '$activeJobs exportaç${activeJobs == 1 ? 'ão' : 'ões'} em '
            'andamento agora'
        : 'Exporte a base de leads e guarde backups por até 60 dias.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
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
                'BACKUPS DE LEADS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _accent,
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
                _backupsLoading ? '—' : '$totalBackups',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  totalBackups == 1 ? 'backup guardado' : 'backups guardados',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
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
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          OrgHeroKpiStrip(blocks: [
            OrgHeroKpi(
              icon: LucideIcons.hourglass,
              label: 'NA FILA',
              value: _jobsLoading ? '—' : '$activeJobs',
              sub: 'em andamento',
              tone: _amber,
            ),
            OrgHeroKpi(
              icon: LucideIcons.databaseBackup,
              label: 'BACKUPS',
              value: _backupsLoading ? '—' : '$totalBackups',
              sub: 'disponíveis',
              tone: _accent,
            ),
            OrgHeroKpi(
              icon: LucideIcons.fileSpreadsheet,
              label: 'LEADS',
              value: _backupsLoading
                  ? '—'
                  : NumberFormat.compact(locale: 'pt_BR').format(totalRows),
              sub: 'linhas guardadas',
              tone: _blue,
            ),
          ]),
        ],
      ),
    );
  }

  // ─── Abas ────────────────────────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context) {
    final activeJobs = _jobs.where((j) => j.status.isActive).length;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          Expanded(
            child: OrgFlushTab(
              icon: LucideIcons.filePlus2,
              label: 'Exportar',
              count: 0,
              tone: _accent,
              selected: _tab == _BackupsTab.create,
              onTap: () => setState(() => _tab = _BackupsTab.create),
            ),
          ),
          Expanded(
            child: OrgFlushTab(
              icon: LucideIcons.history,
              label: 'Atividade',
              count: activeJobs,
              tone: _amber,
              selected: _tab == _BackupsTab.activity,
              onTap: () => setState(() => _tab = _BackupsTab.activity),
            ),
          ),
          Expanded(
            child: OrgFlushTab(
              icon: LucideIcons.databaseBackup,
              label: 'Backups',
              count: _backups.total,
              tone: _blue,
              selected: _tab == _BackupsTab.backups,
              onTap: () => setState(() => _tab = _BackupsTab.backups),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Painéis ─────────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final meta = switch (_tab) {
      _BackupsTab.create => (
          icon: LucideIcons.filePlus2,
          eyebrow: 'NOVA EXPORTAÇÃO',
          title: 'Exportar leads',
          hint: 'Escolha o modelo, o formato e o período — a planilha é '
              'gerada em segundo plano.',
          tone: _accent,
        ),
      _BackupsTab.activity => (
          icon: LucideIcons.history,
          eyebrow: 'ATIVIDADE',
          title: 'Fila de exportações',
          hint: 'Acompanhe o progresso, baixe o arquivo ou cancele um job '
              'vivo.',
          tone: _amber,
        ),
      _BackupsTab.backups => (
          icon: LucideIcons.databaseBackup,
          eyebrow: 'HISTÓRICO',
          title: 'Backups guardados',
          hint: 'Exportações concluídas ficam disponíveis por 60 dias.',
          tone: _blue,
        ),
    };

    final child = switch (_tab) {
      _BackupsTab.create => _buildCreatePanel(context),
      _BackupsTab.activity => _buildActivityPanel(context),
      _BackupsTab.backups => _buildBackupsPanel(context),
    };

    return Column(
      key: ValueKey('panel-${_tab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrgPanelHeader(
          icon: meta.icon,
          eyebrow: meta.eyebrow,
          title: meta.title,
          hint: meta.hint,
          tone: meta.tone,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_tab.name}')).fadeIn(duration: 240.ms);
  }

  // ─── Painel: nova exportação ─────────────────────────────────────────────

  Widget _buildCreatePanel(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OrgSubsectionHeader(
          label: 'Modelo da planilha',
          icon: LucideIcons.fileSpreadsheet,
          count: 0,
        ),
        const SizedBox(height: 10),
        _templateCard(
          context,
          template: LeadsExportTemplate.detailed,
          icon: LucideIcons.fileSpreadsheet,
          tone: _accent,
          title: 'Detalhado',
          description: 'Planilha completa: cliente, imóvel, etapa, resultado, '
              'mídias e campos personalizados.',
        ),
        const SizedBox(height: 8),
        _templateCard(
          context,
          template: LeadsExportTemplate.campaign,
          icon: LucideIcons.users2,
          tone: _blue,
          title: 'Campanha (3 colunas)',
          description: 'Enxuto para disparos em massa: NOME, NÚMERO (com DDI '
              'BR) e MÍDIA DE ORIGEM.',
        ),
        const SizedBox(height: 18),
        const OrgSubsectionHeader(
          label: 'Formato do arquivo',
          icon: LucideIcons.fileDown,
          count: 0,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in [LeadsExportFormat.xlsx, LeadsExportFormat.csv])
              OrgChoiceChip(
                label: f.label,
                selected: _draft.format == f,
                accent: _accent,
                icon: LucideIcons.fileDown,
                onTap: () => setState(() => _draft.format = f),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const OrgSubsectionHeader(
          label: 'Período de criação do lead',
          icon: LucideIcons.calendarDays,
          count: 0,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _dateField(
                context,
                label: 'Início',
                value: _draft.createdAfter,
                onPicked: (d) => setState(() => _draft.createdAfter = d),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateField(
                context,
                label: 'Fim',
                value: _draft.createdBefore,
                onPicked: (d) => setState(() => _draft.createdBefore = d),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const OrgSubsectionHeader(
          label: 'Resultado do lead',
          icon: LucideIcons.circleCheckBig,
          count: 0,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OrgChoiceChip(
              label: 'Todos',
              selected: _draft.result == null,
              accent: _accent,
              onTap: () => setState(() => _draft.result = null),
            ),
            for (final r in LeadsResultFilter.values)
              OrgChoiceChip(
                label: r.label,
                selected: _draft.result == r,
                accent: _accent,
                onTap: () => setState(() => _draft.result = r),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const OrgSubsectionHeader(
          label: 'Busca (opcional)',
          icon: LucideIcons.search,
          count: 0,
        ),
        const SizedBox(height: 10),
        OrgSearchField(
          controller: _searchController,
          hint: 'Filtrar por nome, telefone, e-mail…',
          accent: _accent,
          onChanged: (v) => _draft.search = v,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _submitting ? null : _submitExport,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(LucideIcons.hardDriveDownload, size: 17),
          label: Text(
            _submitting ? 'Enfileirando…' : 'Gerar exportação',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'A exportação roda em segundo plano e vira um backup guardado por '
          '60 dias.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _templateCard(
    BuildContext context, {
    required LeadsExportTemplate template,
    required IconData icon,
    required Color tone,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final selected = _draft.template == template;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _draft.template = template),
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected
                ? tone.withValues(alpha: _isDark ? 0.12 : 0.07)
                : ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.5)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected ? null : ThemeHelpers.cardShadow(context),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: tone.withValues(alpha: _isDark ? 0.2 : 0.12),
                ),
                child: Icon(icon, color: tone, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? tone : Colors.transparent,
                  border: Border.all(
                    color:
                        selected ? tone : ThemeHelpers.borderColor(context),
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(LucideIcons.check,
                        size: 12, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onPicked,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2018),
            lastDate: DateTime.now().add(const Duration(days: 1)),
            locale: const Locale('pt', 'BR'),
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.calendarDays, size: 15, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value == null ? 'Qualquer' : _dateFmt.format(value),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (value != null)
                InkResponse(
                  radius: 15,
                  onTap: () => onPicked(null),
                  child: Icon(LucideIcons.x, size: 13, color: secondary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Painel: atividade (jobs) ────────────────────────────────────────────

  Widget _buildActivityPanel(BuildContext context) {
    if (_jobsLoading && _jobs.isEmpty) return _buildJobsSkeleton();
    if (_jobsError != null && _jobs.isEmpty) {
      return OrgErrorState(message: _jobsError!, onRetry: _loadJobs);
    }
    if (_jobs.isEmpty) {
      return OrgEmptyState(
        icon: LucideIcons.history,
        title: 'Nenhuma exportação recente',
        body: 'Dispare uma exportação na aba "Exportar" para acompanhar '
            'aqui.',
        tone: _amber,
        action: OutlinedButton.icon(
          onPressed: () => setState(() => _tab = _BackupsTab.create),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: BorderSide(color: _accent.withValues(alpha: 0.45)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(LucideIcons.filePlus2, size: 16),
          label: const Text('Nova exportação'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _jobs.length; i++)
          _buildJobCard(context, _jobs[i])
              .animate(key: ValueKey('job-${_jobs[i].jobId}'))
              .fadeIn(
                delay: Duration(milliseconds: 30 * i.clamp(0, 12)),
                duration: 220.ms,
              ),
      ],
    );
  }

  Widget _buildJobCard(BuildContext context, LeadsExportJob job) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = _statusTone(job.status);
    final busy = _busyJobId == job.jobId;
    final progress = (job.progress / 100).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: tone.withValues(alpha: _isDark ? 0.18 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.3)),
                ),
                child: Icon(_statusIcon(job.status), color: tone, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${job.template.label} · '
                      '${job.format.apiValue.toUpperCase()}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      job.createdAt == null
                          ? 'Exportação de leads'
                          : _dateTimeFmt.format(job.createdAt!.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OrgMiniPill(
                label: job.status.label,
                tone: tone,
                icon: _statusIcon(job.status),
              ),
            ],
          ),
          if (job.status.isActive) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: job.status == LeadsExportJobStatus.pending
                    ? null
                    : progress,
                minHeight: 6,
                color: tone,
                backgroundColor: tone.withValues(alpha: 0.14),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              job.status == LeadsExportJobStatus.pending
                  ? 'Aguardando a fila…'
                  : '${job.progress.toStringAsFixed(0)}% · '
                      '${_intFmt.format(job.fetched)}'
                      '${job.totalExpected > 0 ? ' de ${_intFmt.format(job.totalExpected)}' : ''} '
                      'leads',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
          if (job.status == LeadsExportJobStatus.completed &&
              job.totalRows > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${_intFmt.format(job.totalRows)} linhas · '
              '${_formatBytes(job.fileSizeBytes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
          if (job.status == LeadsExportJobStatus.failed &&
              (job.error ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              job.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _danger,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
          if (job.status.isActive ||
              job.status == LeadsExportJobStatus.completed) ...[
            const SizedBox(height: 8),
            Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.6),
            ),
            Row(
              children: [
                const Spacer(),
                if (job.status.isActive)
                  TextButton.icon(
                    onPressed: busy ? null : () => _cancelJob(job),
                    style: TextButton.styleFrom(
                      foregroundColor: _danger,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: busy
                        ? SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.8, color: _danger),
                          )
                        : const Icon(LucideIcons.ban, size: 14),
                    label: const Text(
                      'Cancelar',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
                if (job.status == LeadsExportJobStatus.completed)
                  TextButton.icon(
                    onPressed: busy ? null : () => _downloadJob(job),
                    style: TextButton.styleFrom(
                      foregroundColor: _accent,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: busy
                        ? SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.8, color: _accent),
                          )
                        : const Icon(LucideIcons.fileDown, size: 14),
                    label: const Text(
                      'Baixar arquivo',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ] else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ─── Painel: backups guardados ───────────────────────────────────────────

  Widget _buildBackupsPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_backups.canAccessCompanyBackups) ...[
          Wrap(
            spacing: 8,
            children: [
              OrgChoiceChip(
                label: 'Meus backups',
                selected: _scope == 'mine',
                accent: _blue,
                icon: LucideIcons.user,
                onTap: () {
                  if (_scope == 'mine') return;
                  setState(() => _scope = 'mine');
                  _loadBackups();
                },
              ),
              OrgChoiceChip(
                label: 'Toda a empresa',
                selected: _scope == 'company',
                accent: _blue,
                icon: LucideIcons.building2,
                onTap: () {
                  if (_scope == 'company') return;
                  setState(() => _scope = 'company');
                  _loadBackups();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (_backupsLoading && _backups.data.isEmpty)
          _buildJobsSkeleton()
        else if (_backupsError != null && _backups.data.isEmpty)
          OrgErrorState(message: _backupsError!, onRetry: _loadBackups)
        else if (_backups.data.isEmpty)
          OrgEmptyState(
            icon: LucideIcons.packageOpen,
            title: 'Nenhum backup guardado',
            body: _scope == 'company'
                ? 'Nenhuma exportação concluída na empresa nos últimos 60 '
                    'dias.'
                : 'Suas exportações concluídas ficam aqui por 60 dias.',
            tone: _blue,
            action: OutlinedButton.icon(
              onPressed: () => setState(() => _tab = _BackupsTab.create),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.filePlus2, size: 16),
              label: const Text('Nova exportação'),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _backups.data.length; i++)
                _buildBackupCard(context, _backups.data[i])
                    .animate(key: ValueKey('backup-${_backups.data[i].id}'))
                    .fadeIn(
                      delay: Duration(milliseconds: 30 * i.clamp(0, 12)),
                      duration: 220.ms,
                    ),
            ],
          ),
      ],
    );
  }

  Widget _buildBackupCard(BuildContext context, LeadsExportBackup backup) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final busy = _busyBackupId == backup.id;
    final days = backup.daysToExpire;
    final expiring = days != null && days <= 7;

    final metaParts = <String>[
      if (backup.createdAt != null)
        _dateTimeFmt.format(backup.createdAt!.toLocal()),
      '${_intFmt.format(backup.totalRows)} linhas',
      _formatBytes(backup.fileSizeBytes),
      if (_scope == 'company' && (backup.userName ?? '').isNotEmpty)
        'por ${backup.userName}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: _blue.withValues(alpha: _isDark ? 0.18 : 0.1),
                  border: Border.all(color: _blue.withValues(alpha: 0.3)),
                ),
                child: Icon(LucideIcons.fileSpreadsheet,
                    color: _blue, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      backup.label?.trim().isNotEmpty == true
                          ? backup.label!.trim()
                          : backup.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metaParts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OrgMiniPill(
                label: backup.template.label,
                tone: _blue,
                icon: LucideIcons.fileSpreadsheet,
              ),
              OrgMiniPill(
                label: backup.format.apiValue.toUpperCase(),
                tone: ThemeHelpers.textSecondaryColor(context),
              ),
              if (days != null)
                OrgMiniPill(
                  label: days == 0
                      ? 'Expira hoje'
                      : 'Expira em $days dia${days == 1 ? '' : 's'}',
                  tone: expiring ? _amber : secondary,
                  icon: LucideIcons.timerReset,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            color:
                ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => _downloadBackup(backup),
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  visualDensity: VisualDensity.compact,
                ),
                icon: busy
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.8, color: _accent),
                      )
                    : const Icon(LucideIcons.fileDown, size: 14),
                label: const Text(
                  'Baixar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => _rerunBackup(backup),
                style: TextButton.styleFrom(
                  foregroundColor: _blue,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(LucideIcons.rotateCcw, size: 14),
                label: const Text(
                  'Repetir',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: busy ? null : () => _deleteBackup(backup),
                style: TextButton.styleFrom(
                  foregroundColor: _danger,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(LucideIcons.trash2, size: 14),
                label: const Text(
                  'Apagar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Skeleton ────────────────────────────────────────────────────────────

  /// Skeleton fiel aos cards de job/backup (tile + linhas + pills + rodapé).
  Widget _buildJobsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        3,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
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
                  SkeletonBox(width: 42, height: 42, borderRadius: 13),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: 150, height: 15),
                        SizedBox(height: 7),
                        SkeletonText(width: double.infinity, height: 11),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const SkeletonText(width: 68, height: 20, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  SkeletonText(width: 78, height: 20, borderRadius: 999),
                  SizedBox(width: 8),
                  SkeletonText(width: 52, height: 20, borderRadius: 999),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
