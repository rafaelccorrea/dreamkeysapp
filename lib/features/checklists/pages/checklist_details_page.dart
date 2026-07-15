import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/checklist_models.dart';
import '../services/checklist_service.dart';
import '../widgets/checklist_card.dart';

/// Detalhe do checklist — progresso no topo, itens marcáveis **no próprio
/// item** (toque no círculo alterna concluído; toque no chip de status abre
/// as demais opções) e seções flush de imóvel/cliente/observações.
class ChecklistDetailsPage extends StatefulWidget {
  final String checklistId;

  const ChecklistDetailsPage({super.key, required this.checklistId});

  @override
  State<ChecklistDetailsPage> createState() => _ChecklistDetailsPageState();
}

class _ChecklistDetailsPageState extends State<ChecklistDetailsPage> {
  Checklist? _checklist;
  bool _loading = true;
  String? _error;
  final Set<String> _updatingItems = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await ChecklistService.instance.getById(widget.checklistId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _checklist = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar checklist';
      }
    });
  }

  Future<void> _setItemStatus(
      ChecklistItem item, ChecklistStatus status) async {
    if (_updatingItems.contains(item.id) || item.status == status) return;
    setState(() => _updatingItems.add(item.id));
    final res = await ChecklistService.instance.updateItemStatus(
      widget.checklistId,
      itemId: item.id,
      status: status,
    );
    if (!mounted) return;
    setState(() {
      _updatingItems.remove(item.id);
      if (res.success && res.data != null) {
        _checklist = res.data!;
      }
    });
    if (!res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao atualizar item'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  void _toggleItem(ChecklistItem item) {
    _setItemStatus(
      item,
      item.isCompleted ? ChecklistStatus.pending : ChecklistStatus.completed,
    );
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.of(context)
        .pushNamed('/checklists/${widget.checklistId}/edit');
    if (changed == true) _load(silent: true);
  }

  Future<void> _confirmDelete() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover checklist'),
        content: const Text(
          'Tem certeza que deseja remover este checklist? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await ChecklistService.instance.delete(widget.checklistId);
    if (!mounted) return;
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao remover checklist'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return AppScaffold(
      title: 'Checklist',
      showBottomNavigation: false,
      actions: _checklist == null
          ? null
          : [
              IconButton(
                tooltip: 'Editar',
                onPressed: _openEdit,
                icon: Icon(LucideIcons.pencil, size: 19, color: secondary),
              ),
              IconButton(
                tooltip: 'Remover',
                onPressed: _confirmDelete,
                icon: Icon(LucideIcons.trash2, size: 19, color: secondary),
              ),
            ],
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: () => _load(silent: true),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _checklist == null) return _buildSkeleton(context);
    if (_error != null && _checklist == null) {
      return _buildError(context, _error!);
    }
    final c = _checklist!;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(context, c),
          const SizedBox(height: 20),
          _buildProgress(context, c),
          const SizedBox(height: 24),
          _sectionHeader(
            context,
            icon: LucideIcons.listChecks,
            eyebrow: 'ITENS',
            title: 'Itens do checklist',
            hint: 'Toque no círculo para concluir; no chip para outros status.',
            tone: _accent(context),
          ),
          const SizedBox(height: 6),
          for (final item in c.items) _buildItemRow(context, item),
          const SizedBox(height: 24),
          _buildInfoSection(context, c),
          if ((c.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionHeader(
              context,
              icon: LucideIcons.fileText,
              eyebrow: 'OBSERVAÇÕES',
              title: 'Observações gerais',
              hint: 'Anotações registradas neste processo.',
              tone: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.status.purpleDarkMode
                  : AppColors.status.purple,
            ),
            const SizedBox(height: 10),
            Text(
              c.notes!.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.45,
                  ),
            ),
          ],
        ],
      ).animate().fadeIn(duration: 240.ms),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, Checklist c) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = checklistStatusColor(context, c.status);
    final accent = _accent(context);

    final title = (c.propertyTitle ?? '').trim().isNotEmpty
        ? c.propertyTitle!.trim()
        : 'Imóvel não especificado';

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
              'CHECKLIST · ${c.type.label.toUpperCase()}',
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
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                border: Border.all(color: tone.withValues(alpha: 0.3)),
              ),
              child: Icon(checklistTypeIcon(c.type), color: tone, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.4,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _pill(context, c.status.label, tone),
                      if ((c.clientName ?? '').trim().isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.user, size: 12, color: secondary),
                            const SizedBox(width: 4),
                            Text(
                              c.clientName!.trim(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Progresso ───────────────────────────────────────────────────────────

  Widget _buildProgress(BuildContext context, Checklist c) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final stats = c.stats;
    final pct = stats.completionPercentage.clamp(0, 100).toDouble();
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final tone = pct >= 100 ? emerald : (pct > 0 ? blue : amber);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${pct.round()}%',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                height: 1.0,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '${stats.completedItems} de ${stats.totalItems} '
                'ite${stats.totalItems == 1 ? 'm' : 'ns'} concluído'
                '${stats.completedItems == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 8,
            backgroundColor:
                ThemeHelpers.borderLightColor(context).withValues(alpha: 0.8),
            valueColor: AlwaysStoppedAnimation<Color>(tone),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _progressBit(context, LucideIcons.circleCheck,
                '${stats.completedItems} concluídos', emerald),
            _progressBit(context, LucideIcons.play,
                '${stats.inProgressItems} em andamento', blue),
            _progressBit(context, LucideIcons.circleDashed,
                '${stats.pendingItems} pendentes', amber),
          ],
        ),
      ],
    );
  }

  Widget _progressBit(
      BuildContext context, IconData icon, String text, Color tone) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: tone),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  // ─── Item marcável ───────────────────────────────────────────────────────

  Widget _buildItemRow(BuildContext context, ChecklistItem item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = checklistStatusColor(context, item.status);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final updating = _updatingItems.contains(item.id);
    final done = item.isCompleted;
    final dateFmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

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
          // Toggle no próprio item: círculo de conclusão.
          InkResponse(
            radius: 22,
            onTap: updating ? null : () => _toggleItem(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? emerald : Colors.transparent,
                border: Border.all(
                  color: done
                      ? emerald
                      : secondary.withValues(alpha: 0.55),
                  width: 1.8,
                ),
              ),
              child: updating
                  ? Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: done ? Colors.white : tone,
                      ),
                    )
                  : done
                      ? const Icon(Icons.check_rounded,
                          size: 17, color: Colors.white)
                      : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: done
                        ? secondary
                        : ThemeHelpers.textColor(context),
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: secondary,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
                if ((item.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.description!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      height: 1.35,
                    ),
                  ),
                ],
                if (item.requiredDocuments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final doc in item.requiredDocuments)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: ThemeHelpers.borderColor(context),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.fileText,
                                  size: 11, color: secondary),
                              const SizedBox(width: 4),
                              Text(
                                doc,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (item.estimatedDays != null ||
                    item.completedAt != null ||
                    (item.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (item.estimatedDays != null)
                        _metaBit(
                          context,
                          LucideIcons.clock3,
                          '${item.estimatedDays} dia${item.estimatedDays == 1 ? '' : 's'} previstos',
                        ),
                      if (item.completedAt != null)
                        _metaBit(
                          context,
                          LucideIcons.circleCheck,
                          'Concluído em ${dateFmt.format(item.completedAt!.toLocal())}',
                        ),
                    ],
                  ),
                ],
                if ((item.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.notes!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary.withValues(alpha: 0.9),
                      fontStyle: FontStyle.italic,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Chip de status abre as demais opções (em andamento / pulado).
          PopupMenuButton<ChecklistStatus>(
            enabled: !updating,
            tooltip: 'Alterar status',
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (s) => _setItemStatus(item, s),
            itemBuilder: (ctx) => [
              for (final s in const [
                ChecklistStatus.pending,
                ChecklistStatus.inProgress,
                ChecklistStatus.completed,
                ChecklistStatus.skipped,
              ])
                PopupMenuItem<ChecklistStatus>(
                  value: s,
                  child: Row(
                    children: [
                      Icon(
                        checklistStatusIcon(s),
                        size: 16,
                        color: checklistStatusColor(ctx, s),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.label,
                        style: TextStyle(
                          fontWeight: item.status == s
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: tone.withValues(alpha: isDark ? 0.4 : 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.status.label,
                    style: TextStyle(
                      color: tone,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(LucideIcons.chevronDown, size: 12, color: tone),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaBit(BuildContext context, IconData icon, String text) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11.5, color: secondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: secondary,
          ),
        ),
      ],
    );
  }

  // ─── Informações ─────────────────────────────────────────────────────────

  Widget _buildInfoSection(BuildContext context, Checklist c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final fmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          context,
          icon: LucideIcons.info,
          eyebrow: 'INFORMAÇÕES',
          title: 'Detalhes do processo',
          hint: 'Vínculos e datas deste checklist.',
          tone: blue,
        ),
        const SizedBox(height: 6),
        if ((c.propertyTitle ?? '').trim().isNotEmpty)
          _infoRow(context, LucideIcons.building2, 'Imóvel',
              c.propertyTitle!.trim()),
        if ((c.propertyCode ?? '').trim().isNotEmpty)
          _infoRow(context, LucideIcons.hash, 'Código', c.propertyCode!.trim()),
        if ((c.clientName ?? '').trim().isNotEmpty)
          _infoRow(context, LucideIcons.user, 'Cliente', c.clientName!.trim()),
        if ((c.clientPhone ?? '').trim().isNotEmpty)
          _infoRow(
              context, LucideIcons.phone, 'Telefone', c.clientPhone!.trim()),
        if ((c.clientEmail ?? '').trim().isNotEmpty)
          _infoRow(context, LucideIcons.mail, 'E-mail', c.clientEmail!.trim()),
        if ((c.responsibleUserName ?? '').trim().isNotEmpty)
          _infoRow(context, LucideIcons.userCheck, 'Responsável',
              c.responsibleUserName!.trim()),
        if (c.startedAt != null)
          _infoRow(context, LucideIcons.calendarDays, 'Iniciado em',
              fmt.format(c.startedAt!.toLocal())),
        if (c.completedAt != null)
          _infoRow(context, LucideIcons.circleCheck, 'Concluído em',
              fmt.format(c.completedAt!.toLocal())),
      ],
    );
  }

  Widget _infoRow(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: secondary),
          const SizedBox(width: 8),
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

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String eyebrow,
    required String title,
    required String hint,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(icon, color: tone, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
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
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pill(BuildContext context, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
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

  // ─── Estados ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Row(
          children: [
            SkeletonBox(width: 46, height: 46, borderRadius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonText(width: double.infinity, height: 20),
                  SizedBox(height: 8),
                  SkeletonText(width: 140, height: 14, borderRadius: 999),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SkeletonText(width: 110, height: 34),
        const SizedBox(height: 12),
        const SkeletonText(width: double.infinity, height: 8, borderRadius: 999),
        const SizedBox(height: 28),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 26, height: 26, borderRadius: 999),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: double.infinity, height: 15),
                      SizedBox(height: 6),
                      SkeletonText(width: 180, height: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const SkeletonText(width: 70, height: 22, borderRadius: 999),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 40),
      children: [
        Column(
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
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _load(),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ],
    );
  }
}
