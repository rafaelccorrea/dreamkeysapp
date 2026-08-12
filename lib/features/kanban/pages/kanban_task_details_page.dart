import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';
import '../widgets/task_details_modal.dart';

/// Página deep-link para uma **negociação (card do funil)**.
///
/// Recebe um `taskId` e:
///   1. Busca os dados completos via `KanbanService.getTaskById`.
///   2. Carregado, renderiza a própria [TaskDetailsPage] no lugar — nada de
///      abrir sheet por cima. Como a tela de detalhes já traz o seu chrome
///      (back + título do lead), o voltar entrega o usuário direto na origem
///      (ex.: lista global de tarefas), sem pilha intermediária.
///   3. Enquanto carrega — ou se falhar — mostra os estados desta casca.
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
  // O código HTTP acompanha a mensagem: 403 (card de outro funil) e 404 (card
  // apagado) pedem respostas diferentes de uma queda de servidor.
  int _errorStatus = 0;
  Object? _errorDetail;
  KanbanTask? _task;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
      _errorDetail = null;
    });
    final res = await KanbanService.instance.getTaskById(widget.taskId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _task = res.data;
        _error = null;
        _errorStatus = 0;
        _errorDetail = null;
      } else {
        _error = res.message ?? 'Não foi possível abrir esta negociação.';
        _errorStatus = res.statusCode;
        _errorDetail = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Carregado: a tela de detalhes ASSUME a rota (ela já é a tela completa,
    // com o seu próprio AppScaffold) — nada de casca em volta, senão o back
    // precisaria de dois toques.
    final task = _task;
    if (task != null) return TaskDetailsPage(task: task);

    return AppScaffold(
      title: 'Negociação',
      showBottomNavigation: false,
      showDrawer: false,
      body: _loading ? _buildLoading(context) : _buildError(context),
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
    return AppErrorState.fromApi(
      message: _error,
      statusCode: _errorStatus,
      error: _errorDetail,
      onRetry: _load,
      secondaryLabel: 'Voltar',
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}
