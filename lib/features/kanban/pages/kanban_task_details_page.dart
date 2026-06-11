import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/utils/recent_nav_helper.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';
import '../widgets/task_details_modal.dart';

/// Página deep-link para uma **negociação (card do funil)**.
///
/// Recebe um `taskId` e:
///   1. Busca os dados completos via `KanbanService.getTaskById`.
///   2. Abre o `TaskDetailsModal` automaticamente em modal bottom sheet.
///   3. Quando o modal fecha, esta página também fecha — entregando o
///      usuário de volta na origem (ex.: lista global de tarefas).
///
/// Paridade com a rota `/kanban/task/:taskId` do `imobx-front`.
class KanbanTaskDetailsPage extends StatefulWidget {
  final String taskId;

  const KanbanTaskDetailsPage({super.key, required this.taskId});

  @override
  State<KanbanTaskDetailsPage> createState() => _KanbanTaskDetailsPageState();
}

class _KanbanTaskDetailsPageState extends State<KanbanTaskDetailsPage> {
  bool _loading = true;
  String? _error;
  KanbanTask? _task;
  bool _modalOpened = false;

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
    final res = await KanbanService.instance.getTaskById(widget.taskId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _task = res.data;
        unawaited(
          RecentNavHelper.trackKanbanTask(_task!.id, _task!.title),
        );
      } else {
        _error = res.message ?? 'Não foi possível abrir esta negociação.';
      }
    });

    // Abre o modal logo após o frame da página renderizar.
    if (_task != null && !_modalOpened) {
      _modalOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTaskModal();
      });
    }
  }

  Future<void> _openTaskModal() async {
    if (_task == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: false,
      builder: (sheetContext) => TaskDetailsModal(task: _task!),
    );
    // Quando o modal fecha, voltamos pra origem (ex.: lista de tarefas).
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Negociação',
      showBottomNavigation: false,
      body: _loading
          ? _buildLoading(context)
          : _error != null
              ? _buildError(context)
              : const SizedBox.shrink(),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final accent = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
          ),
          const SizedBox(height: 18),
          Text(
            'Abrindo negociação…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: danger.withValues(alpha: 0.12),
                border: Border.all(color: danger.withValues(alpha: 0.32)),
              ),
              child: Icon(LucideIcons.alertTriangle, color: danger, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              'Não foi possível abrir',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.arrowLeft, size: 16),
                  label: const Text('Voltar'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
