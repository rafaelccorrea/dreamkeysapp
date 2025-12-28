import 'package:flutter/foundation.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';
import '../../../shared/services/secure_storage_service.dart';

/// Controller para gerenciar estado do Kanban
class KanbanController extends ChangeNotifier {
  KanbanController._();

  static final KanbanController instance = KanbanController._();

  final KanbanService _kanbanService = KanbanService.instance;

  // Estado
  KanbanBoard? _board;
  bool _loading = false;
  String? _error;
  String? _teamId;
  String? _projectId;

  // Getters
  KanbanBoard? get board => _board;
  bool get loading => _loading;
  String? get error => _error;
  String? get teamId => _teamId;
  String? get projectId => _projectId;

  List<KanbanColumn> get columns {
    if (_board == null) return [];
    final sorted = List<KanbanColumn>.from(_board!.columns)
      ..sort((a, b) => a.position.compareTo(b.position));
    return sorted;
  }

  List<KanbanTask> get tasks {
    return _board?.tasks ?? [];
  }

  List<KanbanTask> getTasksForColumn(String columnId) {
    return tasks
        .where((task) => task.columnId == columnId)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  KanbanPermissions? get permissions => _board?.permissions;

  /// Carrega o quadro Kanban
  Future<void> loadBoard({String? teamId, String? projectId}) async {
    _updateState(
      loading: true,
      error: null,
    );

    try {
      // Se não fornecido, usar companyId como teamId
      if (teamId == null) {
        final companyId = await SecureStorageService.instance.getCompanyId();
        if (companyId == null || companyId.isEmpty) {
          _updateState(
            error: 'Nenhuma empresa selecionada',
            loading: false,
          );
          return;
        }
        teamId = companyId;
      }

      _teamId = teamId;
      _projectId = projectId;

      final response = await _kanbanService.getBoard(
        _teamId!,
        projectId: _projectId,
      );

      if (response.success && response.data != null) {
        _updateState(
          board: response.data!,
          loading: false,
        );
      } else {
        _updateState(
          error: response.message ?? 'Erro ao carregar quadro Kanban',
          loading: false,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [KANBAN_CTRL] Erro ao carregar quadro: $e');
      debugPrint('📚 [KANBAN_CTRL] StackTrace: $stackTrace');
      _updateState(
        error: 'Erro ao carregar quadro: ${e.toString()}',
        loading: false,
      );
    }
  }

  /// Cria uma coluna
  Future<bool> createColumn(CreateColumnDto dto) async {
    try {
      final response = await _kanbanService.createColumn(dto);

      if (response.success && response.data != null) {
        // Recarregar quadro
        await loadBoard(teamId: _teamId, projectId: _projectId);
        return true;
      } else {
        _error = response.message ?? 'Erro ao criar coluna';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] Erro ao criar coluna: $e');
      _error = 'Erro ao criar coluna: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Atualiza uma coluna
  Future<bool> updateColumn(String id, UpdateColumnDto dto) async {
    try {
      final response = await _kanbanService.updateColumn(id, dto);

      if (response.success && response.data != null) {
        // Atualizar localmente
        if (_board != null) {
          final index = _board!.columns.indexWhere((c) => c.id == id);
          if (index != -1) {
            _board = KanbanBoard(
              columns: [
                ..._board!.columns.sublist(0, index),
                response.data!,
                ..._board!.columns.sublist(index + 1),
              ],
              tasks: _board!.tasks,
              projects: _board!.projects,
              permissions: _board!.permissions,
              team: _board!.team,
            );
            notifyListeners();
          }
        }
        return true;
      } else {
        _error = response.message ?? 'Erro ao atualizar coluna';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] Erro ao atualizar coluna: $e');
      _error = 'Erro ao atualizar coluna: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Deleta uma coluna
  Future<bool> deleteColumn(String id) async {
    try {
      final response = await _kanbanService.deleteColumn(id);

      if (response.success) {
        // Recarregar quadro
        await loadBoard(teamId: _teamId, projectId: _projectId);
        return true;
      } else {
        _error = response.message ?? 'Erro ao deletar coluna';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] Erro ao deletar coluna: $e');
      _error = 'Erro ao deletar coluna: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Reordena colunas
  Future<bool> reorderColumns(List<String> columnIds) async {
    if (_teamId == null) return false;

    try {
      final response = await _kanbanService.reorderColumns(
        _teamId!,
        columnIds,
        projectId: _projectId,
      );

      if (response.success) {
        // Recarregar quadro
        await loadBoard(teamId: _teamId, projectId: _projectId);
        return true;
      } else {
        _error = response.message ?? 'Erro ao reordenar colunas';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] Erro ao reordenar colunas: $e');
      _error = 'Erro ao reordenar colunas: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Cria uma tarefa
  Future<bool> createTask(CreateTaskDto dto) async {
    try {
      final response = await _kanbanService.createTask(dto);

      if (response.success && response.data != null) {
        // Recarregar quadro
        await loadBoard(teamId: _teamId, projectId: _projectId);
        return true;
      } else {
        _error = response.message ?? 'Erro ao criar tarefa';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] Erro ao criar tarefa: $e');
      _error = 'Erro ao criar tarefa: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Atualiza uma tarefa
  Future<bool> updateTask(String id, UpdateTaskDto dto) async {
    try {
      final response = await _kanbanService.updateTask(id, dto);

      if (response.success && response.data != null) {
        // Atualizar localmente
        if (_board != null) {
          final index = _board!.tasks.indexWhere((t) => t.id == id);
          if (index != -1) {
            _board = KanbanBoard(
              columns: _board!.columns,
              tasks: [
                ..._board!.tasks.sublist(0, index),
                response.data!,
                ..._board!.tasks.sublist(index + 1),
              ],
              projects: _board!.projects,
              permissions: _board!.permissions,
              team: _board!.team,
            );
            notifyListeners();
          }
        }
        return true;
      } else {
        _error = response.message ?? 'Erro ao atualizar tarefa';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] Erro ao atualizar tarefa: $e');
      _error = 'Erro ao atualizar tarefa: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Deleta uma tarefa
  Future<bool> deleteTask(String id) async {
    try {
      final response = await _kanbanService.deleteTask(id);

      if (response.success) {
        // Recarregar quadro
        await loadBoard(teamId: _teamId, projectId: _projectId);
        return true;
      } else {
        _error = response.message ?? 'Erro ao deletar tarefa';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] Erro ao deletar tarefa: $e');
      _error = 'Erro ao deletar tarefa: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Move uma tarefa
  Future<bool> moveTask({
    required String taskId,
    required String targetColumnId,
    required int targetPosition,
  }) async {
    try {
      // Optimistic update
      if (_board != null) {
        final taskIndex = _board!.tasks.indexWhere((t) => t.id == taskId);
        if (taskIndex != -1) {
          final task = _board!.tasks[taskIndex];
          final updatedTask = task.copyWith(
            columnId: targetColumnId,
            position: targetPosition,
          );

          _board = KanbanBoard(
            columns: _board!.columns,
            tasks: [
              ..._board!.tasks.sublist(0, taskIndex),
              updatedTask,
              ..._board!.tasks.sublist(taskIndex + 1),
            ],
            projects: _board!.projects,
            permissions: _board!.permissions,
            team: _board!.team,
          );
          notifyListeners();
        }
      }

      final response = await _kanbanService.moveTask(
        MoveTaskDto(
          taskId: taskId,
          targetColumnId: targetColumnId,
          targetPosition: targetPosition,
        ),
      );

      if (response.success) {
        // Recarregar para garantir sincronização
        await loadBoard(teamId: _teamId, projectId: _projectId);
        return true;
      } else {
        // Rollback em caso de erro
        await loadBoard(teamId: _teamId, projectId: _projectId);
        _error = response.message ?? 'Erro ao mover tarefa';
        notifyListeners();
        return false;
      }
    } catch (e) {
      // Rollback em caso de exceção
      await loadBoard(teamId: _teamId, projectId: _projectId);
      debugPrint('❌ [KANBAN_CTRL] Erro ao mover tarefa: $e');
      _error = 'Erro ao mover tarefa: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Atualiza estado interno
  void _updateState({
    KanbanBoard? board,
    bool? loading,
    String? error,
    String? teamId,
    String? projectId,
  }) {
    if (board != null) _board = board;
    if (loading != null) _loading = loading;
    if (error != null) _error = error;
    if (teamId != null) _teamId = teamId;
    if (projectId != null) _projectId = projectId;
    notifyListeners();
  }

  /// Limpa estado
  void clear() {
    _board = null;
    _loading = false;
    _error = null;
    _teamId = null;
    _projectId = null;
    notifyListeners();
  }
}

