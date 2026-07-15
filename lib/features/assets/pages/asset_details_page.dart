import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../documents/widgets/entity_selector.dart';
import '../models/asset_models.dart';
import '../services/asset_service.dart';
import '../widgets/asset_card.dart';
import '../widgets/user_picker_sheet.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Detalhe do patrimônio — hero com valor e status, ações no próprio item
/// (editar / transferir / dar baixa, gated por permissão), especificações
/// flush e linha do tempo de movimentações.
class AssetDetailsPage extends StatefulWidget {
  final String assetId;

  const AssetDetailsPage({super.key, required this.assetId});

  @override
  State<AssetDetailsPage> createState() => _AssetDetailsPageState();
}

class _AssetDetailsPageState extends State<AssetDetailsPage> {
  Asset? _asset;
  List<AssetMovement> _movements = const [];
  bool _loading = true;
  bool _movementsLoading = true;
  String? _error;

  bool get _canUpdate =>
      ModuleAccessService.instance.hasPermission('asset:update');
  bool get _canTransfer =>
      ModuleAccessService.instance.hasPermission('asset:transfer');
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission('asset:delete');

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
    final res = await AssetService.instance.getById(widget.assetId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _asset = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar patrimônio';
      }
    });
    _loadMovements();
  }

  Future<void> _loadMovements() async {
    setState(() => _movementsLoading = true);
    final res = await AssetService.instance.getMovements(widget.assetId);
    if (!mounted) return;
    setState(() {
      _movementsLoading = false;
      if (res.success && res.data != null) {
        _movements = res.data!;
      }
    });
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.of(context)
        .pushNamed('/assets/${widget.assetId}/edit');
    if (changed == true) _load(silent: true);
  }

  Future<void> _confirmDelete() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dar baixa no item'),
        content: Text(
          'Tem certeza que deseja dar baixa em '
          '"${_asset?.name ?? 'este item'}"? O item sai do acervo ativo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dar baixa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await AssetService.instance.delete(widget.assetId);
    if (!mounted) return;
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao dar baixa no patrimônio'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  Future<void> _openTransfer() async {
    final transferred = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _TransferSheet(assetId: widget.assetId),
    );
    if (transferred == true && mounted) _load(silent: true);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Patrimônio',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: () => _load(silent: true),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _asset == null) return _buildSkeleton(context);
    if (_error != null && _asset == null) return _buildError(context, _error!);
    final a = _asset!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cSpecs =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cHistory =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(context, a),
          const SizedBox(height: 18),
          _buildValueBlock(context, a),
          const SizedBox(height: 16),
          _buildActions(context),
          const SizedBox(height: 24),
          _sectionHeader(
            context,
            icon: LucideIcons.scanBarcode,
            eyebrow: 'ESPECIFICAÇÕES',
            title: 'Detalhes do item',
            hint: 'Dados técnicos, vínculos e localização.',
            tone: cSpecs,
          ),
          const SizedBox(height: 6),
          if (a.brandModelLabel != null)
            _infoRow(context, LucideIcons.tag, 'Marca/Modelo',
                a.brandModelLabel!),
          if ((a.serialNumber ?? '').trim().isNotEmpty)
            _infoRow(context, LucideIcons.scanBarcode, 'Nº de série',
                a.serialNumber!.trim()),
          _infoRow(context, LucideIcons.shapes, 'Categoria', a.category.label),
          if (a.acquisitionDate != null)
            _infoRow(
                context,
                LucideIcons.calendarDays,
                'Aquisição',
                DateFormat('dd/MM/yyyy', 'pt_BR')
                    .format(a.acquisitionDate!.toLocal())),
          if ((a.location ?? '').trim().isNotEmpty)
            _infoRow(
                context, LucideIcons.mapPin, 'Localização', a.location!.trim()),
          if ((a.assignedToUserName ?? '').trim().isNotEmpty)
            _infoRow(context, LucideIcons.userCheck, 'Responsável',
                a.assignedToUserName!.trim()),
          if ((a.propertyTitle ?? '').trim().isNotEmpty)
            _infoRow(
                context,
                LucideIcons.building2,
                'Imóvel',
                (a.propertyCode ?? '').trim().isNotEmpty
                    ? '${a.propertyTitle!.trim()} · CÓD ${a.propertyCode!.trim()}'
                    : a.propertyTitle!.trim()),
          if ((a.createdByName ?? '').trim().isNotEmpty)
            _infoRow(context, LucideIcons.userRound, 'Cadastrado por',
                a.createdByName!.trim()),
          if (a.createdAt != null)
            _infoRow(context, LucideIcons.clock3, 'Cadastrado em',
                DateFormat('dd/MM/yyyy', 'pt_BR').format(a.createdAt!.toLocal())),
          if ((a.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _labelText(context, 'DESCRIÇÃO'),
            const SizedBox(height: 6),
            Text(
              a.description!.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.45,
                  ),
            ),
          ],
          if ((a.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _labelText(context, 'OBSERVAÇÕES'),
            const SizedBox(height: 6),
            Text(
              a.notes!.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.45,
                  ),
            ),
          ],
          const SizedBox(height: 24),
          _sectionHeader(
            context,
            icon: LucideIcons.history,
            eyebrow: 'HISTÓRICO',
            title: 'Movimentações',
            hint: 'Entradas, transferências e mudanças de status.',
            tone: cHistory,
          ),
          const SizedBox(height: 12),
          _buildMovements(context, cHistory),
        ],
      ).animate().fadeIn(duration: 240.ms),
    );
  }

  Widget _labelText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 10,
          ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, Asset a) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = assetStatusColor(context, a.status);
    final accent = _accent(context);

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
              'PATRIMÔNIO · ${a.category.label.toUpperCase()}',
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
              child: Icon(assetCategoryIcon(a.category), color: tone, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
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
                    children: [
                      _pill(context, a.status.label, tone),
                      if (a.brandModelLabel != null)
                        _pill(
                          context,
                          a.brandModelLabel!,
                          ThemeHelpers.textSecondaryColor(context),
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

  Widget _buildValueBlock(BuildContext context, Asset a) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = assetStatusColor(context, a.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VALOR DO BEM',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _money.format(a.value),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Ações no próprio item ───────────────────────────────────────────────

  Widget _buildActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(context);
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final actions = <Widget>[
      if (_canUpdate)
        _actionButton(context, LucideIcons.pencil, 'Editar', accent, _openEdit),
      if (_canTransfer)
        _actionButton(context, LucideIcons.arrowLeftRight, 'Transferir', blue,
            _openTransfer),
      if (_canDelete)
        _actionButton(
            context, LucideIcons.archive, 'Dar baixa', danger, _confirmDelete),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }

  Widget _actionButton(BuildContext context, IconData icon, String label,
      Color tone, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: tone,
        side: BorderSide(color: tone.withValues(alpha: 0.45)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
      ),
    );
  }

  // ─── Movimentações ───────────────────────────────────────────────────────

  Widget _buildMovements(BuildContext context, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    if (_movementsLoading) {
      return Column(
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 34, height: 34, borderRadius: 999),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: 140, height: 14),
                      SizedBox(height: 6),
                      SkeletonText(width: double.infinity, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_movements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(LucideIcons.history, size: 15, color: secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nenhuma movimentação registrada para este item.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
    return Column(
      children: [
        for (var i = 0; i < _movements.length; i++)
          _movementRow(context, _movements[i], tone, fmt,
              isLast: i == _movements.length - 1),
      ],
    );
  }

  Widget _movementRow(BuildContext context, AssetMovement m, Color tone,
      DateFormat fmt,
      {required bool isLast}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final date = m.movementDate ?? m.createdAt;

    final routeBits = <String>[];
    if (m.fromUserName != null || m.toUserName != null) {
      routeBits.add(
          '${m.fromUserName ?? '—'} → ${m.toUserName ?? '—'}');
    }
    if (m.fromPropertyTitle != null || m.toPropertyTitle != null) {
      routeBits.add(
          '${m.fromPropertyTitle ?? '—'} → ${m.toPropertyTitle ?? '—'}');
    }
    if (m.previousStatus != null || m.newStatus != null) {
      routeBits.add(
          '${m.previousStatus?.label ?? '—'} → ${m.newStatus?.label ?? '—'}');
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trilho da timeline: glyph + linha.
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.3)),
                ),
                child: Icon(assetMovementIcon(m.type), color: tone, size: 15),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: tone.withValues(alpha: 0.22),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.type.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (date != null)
                        Text(
                          fmt.format(date.toLocal()),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                    ],
                  ),
                  if (m.reason.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      m.reason.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  for (final bit in routeBits) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(LucideIcons.moveRight, size: 12, color: secondary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            bit,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if ((m.recordedByName ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Registrado por ${m.recordedByName!.trim()}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary.withValues(alpha: 0.85),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers visuais ─────────────────────────────────────────────────────

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
        const SizedBox(height: 20),
        SkeletonBox(width: double.infinity, height: 84, borderRadius: 16),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: SkeletonBox(
                    width: double.infinity, height: 44, borderRadius: 13)),
            const SizedBox(width: 10),
            Expanded(
                child: SkeletonBox(
                    width: double.infinity, height: 44, borderRadius: 13)),
            const SizedBox(width: 10),
            Expanded(
                child: SkeletonBox(
                    width: double.infinity, height: 44, borderRadius: 13)),
          ],
        ),
        const SizedBox(height: 28),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: const [
                SkeletonText(width: 110, height: 13),
                Spacer(),
                SkeletonText(width: 130, height: 13),
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

// ─── Sheet de transferência ──────────────────────────────────────────────────

enum _TransferTarget { user, property }

class _TransferSheet extends StatefulWidget {
  final String assetId;

  const _TransferSheet({required this.assetId});

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();

  _TransferTarget _target = _TransferTarget.user;
  String? _toUserId;
  String? _toUserName;
  String? _toPropertyId;
  String? _toPropertyName;

  bool _saving = false;
  bool _triedSubmit = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_reasonController.text.trim().isEmpty) return false;
    if (_target == _TransferTarget.user) return (_toUserId ?? '').isNotEmpty;
    return (_toPropertyId ?? '').isNotEmpty;
  }

  Future<void> _pickUser() async {
    final picked = await showUserPickerSheet(context, selectedId: _toUserId);
    if (picked == null || picked.id.isEmpty || !mounted) return;
    setState(() {
      _toUserId = picked.id;
      _toUserName = picked.name;
    });
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    if (!_valid) return;
    setState(() => _saving = true);
    final res = await AssetService.instance.transfer(
      widget.assetId,
      toUserId: _target == _TransferTarget.user ? _toUserId : null,
      toPropertyId:
          _target == _TransferTarget.property ? _toPropertyId : null,
      reason: _reasonController.text,
      notes: _notesController.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      Navigator.of(context).pop(true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message ?? 'Erro ao transferir patrimônio'),
        backgroundColor: AppColors.status.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
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
                        color: blue.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(LucideIcons.arrowLeftRight,
                          color: blue, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transferir patrimônio',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mova o item para um colaborador ou imóvel.',
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
                Row(
                  children: [
                    _targetChip(context, _TransferTarget.user, 'Colaborador',
                        LucideIcons.userRound, blue),
                    const SizedBox(width: 10),
                    _targetChip(context, _TransferTarget.property, 'Imóvel',
                        LucideIcons.building2, blue),
                  ],
                ),
                const SizedBox(height: 14),
                if (_target == _TransferTarget.user) ...[
                  InkWell(
                    onTap: _pickUser,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Destinatário *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.person_outline),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        (_toUserName ?? '').isNotEmpty
                            ? _toUserName!
                            : 'Selecionar colaborador',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: (_toUserName ?? '').isNotEmpty
                              ? ThemeHelpers.textColor(context)
                              : secondary,
                        ),
                      ),
                    ),
                  ),
                  if (_triedSubmit && (_toUserId ?? '').isEmpty)
                    _errorHint(context, 'Selecione o colaborador de destino'),
                ] else ...[
                  EntitySelector(
                    type: 'property',
                    selectedId: _toPropertyId,
                    selectedName: _toPropertyName,
                    onSelected: (id, name) => setState(() {
                      _toPropertyId = id;
                      _toPropertyName = name;
                    }),
                  ),
                  if (_triedSubmit && (_toPropertyId ?? '').isEmpty)
                    _errorHint(context, 'Selecione o imóvel de destino'),
                ],
                const SizedBox(height: 14),
                CustomTextField(
                  controller: _reasonController,
                  label: 'Motivo *',
                  hint: 'Ex: Mudança de setor',
                  errorText:
                      _triedSubmit && _reasonController.text.trim().isEmpty
                          ? 'Motivo é obrigatório'
                          : null,
                  onChanged: (_) {
                    if (_triedSubmit) setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _notesController,
                  label: 'Observações',
                  hint: 'Opcional',
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.arrowLeftRight, size: 16),
                  label: Text(
                    _saving ? 'Transferindo…' : 'Confirmar transferência',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorHint(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 13, color: danger),
          const SizedBox(width: 5),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetChip(BuildContext context, _TransferTarget target,
      String label, IconData icon, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selected = _target == target;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _target = target),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
                : fieldFill,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? accent
                  : ThemeHelpers.borderLightColor(context),
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
