import 'package:flutter/foundation.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';
import '../services/team_service.dart';
import '../../../shared/services/secure_storage_service.dart';

/// Controller para gerenciar estado do Kanban
class KanbanController extends ChangeNotifier {
  KanbanController._();

  static final KanbanController instance = KanbanController._();

  final KanbanService _kanbanService = KanbanService.instance;
  final TeamService _teamService = TeamService.instance;

  // Estado
  KanbanBoard? _board;
  bool _loading = false;
  String? _error;
  String? _teamId;
  String? _projectId;
  List<KanbanProject> _projects = [];
  bool _loadingProjects = false;
  List<KanbanTeam> _teams = [];
  bool _loadingTeams = false;
  KanbanTeam? _selectedTeam;

  // Filtros
  String? _searchQuery;
  KanbanPriority? _filterPriority;
  String? _filterAssigneeId;

  // Getters
  KanbanBoard? get board => _board;
  bool get loading => _loading;
  String? get error => _error;
  String? get teamId => _teamId;
  String? get projectId => _projectId;
  List<KanbanProject> get projects => _projects;
  bool get loadingProjects => _loadingProjects;
  List<KanbanTeam> get teams => _teams;
  bool get loadingTeams => _loadingTeams;
  KanbanTeam? get selectedTeam => _selectedTeam;

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
    var filteredTasks = tasks
        .where((task) => task.columnId == columnId)
        .toList();

    // Aplicar filtro de busca
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      final query = _searchQuery!.toLowerCase();
      filteredTasks = filteredTasks.where((task) {
        final titleMatch = task.title.toLowerCase().contains(query);
        final descriptionMatch =
            task.description?.toLowerCase().contains(query) ?? false;
        return titleMatch || descriptionMatch;
      }).toList();
    }

    // Aplicar filtro de prioridade
    if (_filterPriority != null) {
      filteredTasks = filteredTasks
          .where((task) => task.priority == _filterPriority)
          .toList();
    }

    // Aplicar filtro de responsável
    if (_filterAssigneeId != null && _filterAssigneeId!.isNotEmpty) {
      filteredTasks = filteredTasks
          .where((task) => task.assignedToId == _filterAssigneeId)
          .toList();
    }

    // Ordenar por posição
    filteredTasks.sort((a, b) => a.position.compareTo(b.position));
    return filteredTasks;
  }

  KanbanPermissions? get permissions => _board?.permissions;
  KanbanTeam? get team => _board?.team;

  /// Carrega o quadro Kanban
  Future<void> loadBoard({String? teamId, String? projectId}) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== INICIANDO loadBoard ==========');
    debugPrint('🚀 [KANBAN_CTRL] Parâmetros recebidos:');
    debugPrint('🚀 [KANBAN_CTRL] - teamId: $teamId');
    debugPrint('🚀 [KANBAN_CTRL] - projectId: $projectId');
    debugPrint('🚀 [KANBAN_CTRL] - Estado atual:');
    debugPrint('🚀 [KANBAN_CTRL]   - _teamId: $_teamId');
    debugPrint('🚀 [KANBAN_CTRL]   - _projectId: $_projectId');
    debugPrint('🚀 [KANBAN_CTRL]   - _loading: $_loading');

    _updateState(loading: true, error: null);

    try {
      // Se não fornecido, tentar obter times primeiro
      if (teamId == null) {
        debugPrint(
          '📋 [KANBAN_CTRL] ⚠️ teamId não fornecido, tentando obter times...',
        );

        // Primeiro, tentar listar times disponíveis
        debugPrint('📋 [KANBAN_CTRL] Chamando getTeams()...');
        final teamsResponse = await _teamService.getTeams();
        debugPrint('📋 [KANBAN_CTRL] Resposta getTeams:');
        debugPrint('📋 [KANBAN_CTRL]   - success: ${teamsResponse.success}');
        debugPrint(
          '📋 [KANBAN_CTRL]   - statusCode: ${teamsResponse.statusCode}',
        );
        debugPrint(
          '📋 [KANBAN_CTRL]   - data: ${teamsResponse.data?.length ?? 0} times',
        );

        if (teamsResponse.success &&
            teamsResponse.data != null &&
            teamsResponse.data!.isNotEmpty) {
          // Usar o primeiro time disponível
          final firstTeam = teamsResponse.data!.first;
          teamId = firstTeam.id;
          _selectedTeam = firstTeam;
          _teams = teamsResponse.data!;
          debugPrint('📋 [KANBAN_CTRL] ✅ Time encontrado!');
          debugPrint(
            '📋 [KANBAN_CTRL]   - Time: ${firstTeam.name} (${firstTeam.id})',
          );
          debugPrint(
            '📋 [KANBAN_CTRL]   - Total de times: ${teamsResponse.data!.length}',
          );
        } else {
          // Se não tiver times, tentar workspace pessoal
          debugPrint(
            '📋 [KANBAN_CTRL] ⚠️ Nenhum time encontrado, tentando workspace pessoal...',
          );
          final personalResponse = await _kanbanService.getPersonalWorkspace();
          debugPrint('📋 [KANBAN_CTRL] Resposta getPersonalWorkspace:');
          debugPrint(
            '📋 [KANBAN_CTRL]   - success: ${personalResponse.success}',
          );
          debugPrint(
            '📋 [KANBAN_CTRL]   - statusCode: ${personalResponse.statusCode}',
          );
          debugPrint(
            '📋 [KANBAN_CTRL]   - data: ${personalResponse.data?.length ?? 0} projetos',
          );

          if (personalResponse.success &&
              personalResponse.data != null &&
              personalResponse.data!.isNotEmpty) {
            // Usar o primeiro projeto pessoal como referência para obter teamId
            final personalProject = personalResponse.data!.first;
            teamId = personalProject.teamId;
            debugPrint('📋 [KANBAN_CTRL] ✅ Workspace pessoal encontrado!');
            debugPrint(
              '📋 [KANBAN_CTRL]   - Projeto: ${personalProject.name} (${personalProject.id})',
            );
            debugPrint('📋 [KANBAN_CTRL]   - teamId: $teamId');
          } else {
            // Se não tiver workspace pessoal, tentar usar companyId
            debugPrint(
              '📋 [KANBAN_CTRL] ⚠️ Workspace pessoal não encontrado, tentando companyId...',
            );
            final companyId = await SecureStorageService.instance
                .getCompanyId();
            debugPrint('📋 [KANBAN_CTRL] companyId obtido: $companyId');

            if (companyId == null || companyId.isEmpty) {
              debugPrint(
                '📋 [KANBAN_CTRL] ❌ Nenhuma equipe ou empresa encontrada',
              );
              _updateState(
                error:
                    'Nenhuma equipe ou empresa selecionada. Crie um workspace pessoal primeiro.',
                loading: false,
              );
              return;
            }
            teamId = companyId;
            debugPrint(
              '📋 [KANBAN_CTRL] ⚠️ Usando companyId como teamId: $teamId',
            );
          }
        }
      }

      _teamId = teamId;
      _projectId = projectId;

      debugPrint(
        '📋 [KANBAN_CTRL] ========== CHAMANDO API getBoard ==========',
      );
      debugPrint('📋 [KANBAN_CTRL] Parâmetros finais:');
      debugPrint('📋 [KANBAN_CTRL] - teamId: $_teamId');
      debugPrint('📋 [KANBAN_CTRL] - projectId: $_projectId');
      debugPrint('📋 [KANBAN_CTRL] - projectId é null? ${_projectId == null}');
      debugPrint(
        '📋 [KANBAN_CTRL] - projectId está vazio? ${_projectId?.isEmpty ?? true}',
      );

      final response = await _kanbanService.getBoard(
        _teamId!,
        projectId: _projectId,
      );

      debugPrint('📋 [KANBAN_CTRL] ========== RESPOSTA getBoard ==========');
      debugPrint('📋 [KANBAN_CTRL] - success: ${response.success}');
      debugPrint('📋 [KANBAN_CTRL] - statusCode: ${response.statusCode}');
      debugPrint('📋 [KANBAN_CTRL] - message: ${response.message}');
      debugPrint('📋 [KANBAN_CTRL] - data é null? ${response.data == null}');

      if (response.success && response.data != null) {
        final board = response.data!;
        debugPrint('📋 [KANBAN_CTRL] ✅ Quadro carregado com sucesso!');
        debugPrint('📋 [KANBAN_CTRL]   - Colunas: ${board.columns.length}');
        debugPrint('📋 [KANBAN_CTRL]   - Tarefas: ${board.tasks.length}');
        debugPrint(
          '📋 [KANBAN_CTRL]   - Projetos: ${board.projects?.length ?? 0}',
        );
        debugPrint(
          '📋 [KANBAN_CTRL]   - Equipe: ${board.team?.name ?? "não informada"} (${board.team?.id ?? "sem ID"})',
        );
        debugPrint(
          '📋 [KANBAN_CTRL]   - Permissões: ${board.permissions != null ? "sim" : "não"}',
        );

        _updateState(board: board, loading: false);

        // Carregar projetos após carregar o quadro
        if (_teamId != null) {
          debugPrint('📋 [KANBAN_CTRL] Carregando projetos da equipe...');
          await loadProjects(teamId: _teamId);
        }
      } else {
        // Se erro 403, tentar workspace pessoal
        if (response.statusCode == 403) {
          debugPrint(
            '📋 [KANBAN_CTRL] ⚠️ Erro 403: Sem acesso à equipe. Tentando workspace pessoal...',
          );
          final personalResponse = await _kanbanService.getPersonalWorkspace();
          if (personalResponse.success &&
              personalResponse.data != null &&
              personalResponse.data!.isNotEmpty) {
            final personalProject = personalResponse.data!.first;
            final personalTeamId = personalProject.teamId;
            debugPrint(
              '📋 [KANBAN_CTRL] ✅ Tentando com workspace pessoal, teamId: $personalTeamId',
            );

            final personalBoardResponse = await _kanbanService.getBoard(
              personalTeamId,
              projectId: _projectId,
            );

            if (personalBoardResponse.success &&
                personalBoardResponse.data != null) {
              _teamId = personalTeamId;
              _updateState(board: personalBoardResponse.data!, loading: false);
              debugPrint(
                '📋 [KANBAN_CTRL] ✅ Quadro pessoal carregado com sucesso!',
              );
              return;
            }
          }
        }

        debugPrint(
          '📋 [KANBAN_CTRL] ❌ Erro ao carregar quadro: ${response.message}',
        );
        _updateState(
          error: response.message ?? 'Erro ao carregar quadro Kanban',
          loading: false,
        );
      }

      debugPrint('📋 [KANBAN_CTRL] ========== FIM loadBoard ==========');
    } catch (e, stackTrace) {
      debugPrint('❌ [KANBAN_CTRL] ========== EXCEÇÃO em loadBoard ==========');
      debugPrint('❌ [KANBAN_CTRL] Erro: $e');
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
    debugPrint('🚀 [KANBAN_CTRL] ========== INICIANDO createTask ==========');
    debugPrint('🚀 [KANBAN_CTRL] DTO recebido:');
    debugPrint('🚀 [KANBAN_CTRL]   - title: ${dto.title}');
    debugPrint(
      '🚀 [KANBAN_CTRL]   - description: ${dto.description ?? "null"}',
    );
    debugPrint('🚀 [KANBAN_CTRL]   - columnId: ${dto.columnId}');
    debugPrint(
      '🚀 [KANBAN_CTRL]   - priority: ${dto.priority?.name ?? "null"}',
    );
    debugPrint(
      '🚀 [KANBAN_CTRL]   - assignedToId: ${dto.assignedToId ?? "null"}',
    );
    debugPrint(
      '🚀 [KANBAN_CTRL]   - dueDate: ${dto.dueDate?.toIso8601String() ?? "null"}',
    );
    debugPrint('🚀 [KANBAN_CTRL]   - projectId: ${dto.projectId ?? "null"}');
    debugPrint('🚀 [KANBAN_CTRL]   - tags: ${dto.tags ?? "null"}');
    debugPrint('🚀 [KANBAN_CTRL] Estado atual:');
    debugPrint('🚀 [KANBAN_CTRL]   - _teamId: $_teamId');
    debugPrint('🚀 [KANBAN_CTRL]   - _projectId: $_projectId');
    debugPrint('🚀 [KANBAN_CTRL]   - Total de projetos: ${_projects.length}');

    // projectId é obrigatório - garantir que sempre haja um
    String? finalProjectId = dto.projectId ?? _projectId;

    // Se ainda não tiver projectId, tentar usar o primeiro projeto disponível
    if (finalProjectId == null || finalProjectId.isEmpty) {
      debugPrint(
        '🚀 [KANBAN_CTRL] ⚠️ projectId não fornecido, buscando primeiro projeto disponível...',
      );

      // Se não tiver projetos carregados, tentar carregar
      if (_projects.isEmpty && _teamId != null) {
        debugPrint(
          '🚀 [KANBAN_CTRL] Nenhum projeto carregado, carregando projetos...',
        );
        await loadProjects(teamId: _teamId);
      }

      // Tentar workspace pessoal se não tiver projetos da equipe
      if (_projects.isEmpty) {
        debugPrint(
          '🚀 [KANBAN_CTRL] ⚠️ Nenhum projeto da equipe, tentando workspace pessoal...',
        );
        final personalResponse = await _kanbanService.getPersonalWorkspace();
        if (personalResponse.success &&
            personalResponse.data != null &&
            personalResponse.data!.isNotEmpty) {
          _projects = personalResponse.data!;
          debugPrint(
            '🚀 [KANBAN_CTRL] ✅ ${_projects.length} projetos pessoais carregados',
          );
          for (var i = 0; i < _projects.length; i++) {
            final p = _projects[i];
            debugPrint(
              '🚀 [KANBAN_CTRL]   [$i] ${p.name} (ID: ${p.id}) - Status: ${p.status.name}',
            );
          }
        }
      }

      // Usar o primeiro projeto ativo disponível
      final activeProjects = _projects
          .where((p) => p.status == KanbanProjectStatus.active)
          .toList();
      if (activeProjects.isNotEmpty) {
        finalProjectId = activeProjects.first.id;
        debugPrint(
          '🚀 [KANBAN_CTRL] ✅ Usando primeiro projeto ativo: ${activeProjects.first.name}',
        );
        debugPrint(
          '🚀 [KANBAN_CTRL]   - ID do projeto (campo "id"): ${activeProjects.first.id}',
        );
      } else if (_projects.isNotEmpty) {
        // Se não tiver projetos ativos, usar o primeiro disponível
        finalProjectId = _projects.first.id;
        debugPrint(
          '🚀 [KANBAN_CTRL] ⚠️ Usando primeiro projeto disponível: ${_projects.first.name}',
        );
        debugPrint(
          '🚀 [KANBAN_CTRL]   - ID do projeto (campo "id"): ${_projects.first.id}',
        );
      } else {
        debugPrint(
          '🚀 [KANBAN_CTRL] ❌ Nenhum projeto disponível para criar tarefa',
        );
        _error = 'Nenhum projeto disponível. Crie um projeto primeiro.';
        notifyListeners();
        return false;
      }
    }

    // Criar DTO com projectId garantido
    final dtoWithProject = CreateTaskDto(
      title: dto.title,
      description: dto.description,
      columnId: dto.columnId,
      priority: dto.priority,
      assignedToId: dto.assignedToId,
      dueDate: dto.dueDate,
      projectId: finalProjectId,
      tags: dto.tags,
    );

    debugPrint(
      '🚀 [KANBAN_CTRL] DTO final com projectId: ${dtoWithProject.projectId}',
    );
    debugPrint(
      '🚀 [KANBAN_CTRL] JSON a ser enviado: ${dtoWithProject.toJson()}',
    );

    try {
      debugPrint('🚀 [KANBAN_CTRL] Chamando _kanbanService.createTask()...');
      final response = await _kanbanService.createTask(dtoWithProject);

      debugPrint('🚀 [KANBAN_CTRL] ========== RESPOSTA createTask ==========');
      debugPrint('🚀 [KANBAN_CTRL]   - success: ${response.success}');
      debugPrint('🚀 [KANBAN_CTRL]   - statusCode: ${response.statusCode}');
      debugPrint('🚀 [KANBAN_CTRL]   - message: ${response.message}');
      debugPrint('🚀 [KANBAN_CTRL]   - data é null? ${response.data == null}');

      if (response.success && response.data != null) {
        final task = response.data!;
        debugPrint('🚀 [KANBAN_CTRL] ✅ Tarefa criada com sucesso!');
        debugPrint('🚀 [KANBAN_CTRL]   - ID: ${task.id}');
        debugPrint('🚀 [KANBAN_CTRL]   - Título: ${task.title}');
        debugPrint('🚀 [KANBAN_CTRL]   - Coluna: ${task.columnId}');
        debugPrint('🚀 [KANBAN_CTRL]   - Posição: ${task.position}');
        debugPrint('🚀 [KANBAN_CTRL] Recarregando quadro...');

        // Recarregar quadro
        await loadBoard(teamId: _teamId, projectId: _projectId);

        debugPrint(
          '🚀 [KANBAN_CTRL] ========== FIM createTask (SUCESSO) ==========',
        );
        return true;
      } else {
        debugPrint(
          '🚀 [KANBAN_CTRL] ❌ Erro ao criar tarefa: ${response.message}',
        );
        _error = response.message ?? 'Erro ao criar tarefa';
        notifyListeners();
        debugPrint(
          '🚀 [KANBAN_CTRL] ========== FIM createTask (ERRO) ==========',
        );
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [KANBAN_CTRL] ========== EXCEÇÃO em createTask ==========');
      debugPrint('❌ [KANBAN_CTRL] Erro: $e');
      debugPrint('📚 [KANBAN_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao criar tarefa: ${e.toString()}';
      notifyListeners();
      debugPrint(
        '🚀 [KANBAN_CTRL] ========== FIM createTask (EXCEÇÃO) ==========',
      );
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
    // Salvar estado anterior para rollback
    KanbanBoard? previousBoard;
    if (_board != null) {
      previousBoard = KanbanBoard(
        columns: _board!.columns,
        tasks: List<KanbanTask>.from(_board!.tasks),
        projects: _board!.projects,
        permissions: _board!.permissions,
        team: _board!.team,
      );
    }

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
        // Não recarregar - o estado já foi atualizado otimisticamente
        // Apenas notificar que está tudo ok
        return true;
      } else {
        // Rollback em caso de erro
        if (previousBoard != null) {
          _board = previousBoard;
          notifyListeners();
        }
        _error = response.message ?? 'Erro ao mover tarefa';
        notifyListeners();
        return false;
      }
    } catch (e) {
      // Rollback em caso de exceção
      if (previousBoard != null) {
        _board = previousBoard;
        notifyListeners();
      }
      debugPrint('❌ [KANBAN_CTRL] Erro ao mover tarefa: $e');
      _error = 'Erro ao mover tarefa: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Carrega times disponíveis
  Future<void> loadTeams() async {
    debugPrint('🚀 [KANBAN_CTRL] ========== INICIANDO loadTeams ==========');

    _loadingTeams = true;
    notifyListeners();

    try {
      debugPrint('🚀 [KANBAN_CTRL] Chamando getTeams()...');
      final response = await _teamService.getTeams();

      debugPrint('🚀 [KANBAN_CTRL] Resposta getTeams:');
      debugPrint('🚀 [KANBAN_CTRL]   - success: ${response.success}');
      debugPrint('🚀 [KANBAN_CTRL]   - statusCode: ${response.statusCode}');
      debugPrint(
        '🚀 [KANBAN_CTRL]   - data: ${response.data?.length ?? 0} times',
      );

      if (response.success && response.data != null) {
        _teams = response.data!;
        debugPrint('📋 [KANBAN_CTRL] ✅ ${_teams.length} times carregados');
        for (var i = 0; i < _teams.length; i++) {
          final t = _teams[i];
          debugPrint('📋 [KANBAN_CTRL]   [$i] ${t.name} (${t.id})');
        }
      } else {
        _teams = [];
        debugPrint('📋 [KANBAN_CTRL] ⚠️ Nenhum time encontrado');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [KANBAN_CTRL] ========== EXCEÇÃO em loadTeams ==========');
      debugPrint('❌ [KANBAN_CTRL] Erro: $e');
      debugPrint('📚 [KANBAN_CTRL] StackTrace: $stackTrace');
      _teams = [];
    } finally {
      _loadingTeams = false;
      notifyListeners();
      debugPrint('📋 [KANBAN_CTRL] ========== FIM loadTeams ==========');
    }
  }

  /// Seleciona um time
  Future<void> selectTeam(KanbanTeam? team) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== selectTeam ==========');
    debugPrint(
      '🚀 [KANBAN_CTRL] Time selecionado: ${team?.name} (${team?.id})',
    );
    debugPrint(
      '🚀 [KANBAN_CTRL] Time anterior: ${_selectedTeam?.name} (${_selectedTeam?.id})',
    );

    _selectedTeam = team;

    // Recarregar projetos e quadro com o novo time
    if (team != null) {
      debugPrint(
        '🚀 [KANBAN_CTRL] Recarregando projetos e quadro com novo time...',
      );
      await loadProjects(teamId: team.id);
      await loadBoard(teamId: team.id, projectId: _projectId);
    } else {
      debugPrint('🚀 [KANBAN_CTRL] Time desmarcado');
    }

    debugPrint('🚀 [KANBAN_CTRL] ========== FIM selectTeam ==========');
  }

  /// Carrega projetos disponíveis
  Future<void> loadProjects({String? teamId}) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== INICIANDO loadProjects ==========');
    debugPrint('🚀 [KANBAN_CTRL] Parâmetro teamId: $teamId');
    debugPrint('🚀 [KANBAN_CTRL] _teamId atual: $_teamId');

    if (teamId == null) {
      teamId = _teamId;
      debugPrint('🚀 [KANBAN_CTRL] Usando _teamId: $teamId');
    }

    _loadingProjects = true;
    notifyListeners();
    debugPrint('🚀 [KANBAN_CTRL] Estado _loadingProjects: true');

    try {
      final List<KanbanProject> allProjects = [];

      // SEMPRE carregar projetos pessoais primeiro (sempre existe)
      debugPrint(
        '📋 [KANBAN_CTRL] Carregando projetos pessoais (sempre existe)...',
      );
      final personalResponse = await _kanbanService.getPersonalWorkspace();
      debugPrint('📋 [KANBAN_CTRL] Resposta getPersonalWorkspace:');
      debugPrint('📋 [KANBAN_CTRL]   - success: ${personalResponse.success}');
      debugPrint(
        '📋 [KANBAN_CTRL]   - data: ${personalResponse.data?.length ?? 0} projetos',
      );

      if (personalResponse.success && personalResponse.data != null) {
        allProjects.addAll(personalResponse.data!);
        debugPrint(
          '📋 [KANBAN_CTRL] ✅ ${personalResponse.data!.length} projetos pessoais carregados',
        );
        for (var i = 0; i < personalResponse.data!.length; i++) {
          final p = personalResponse.data![i];
          debugPrint(
            '📋 [KANBAN_CTRL]   [Pessoal $i] ${p.name} (${p.id}) - Status: ${p.status.name} - Tarefas: ${p.taskCount}',
          );
        }
      }

      // Carregar projetos de TODAS as equipes (não apenas do time selecionado)
      // Primeiro, garantir que os times estão carregados
      if (_teams.isEmpty) {
        debugPrint('📋 [KANBAN_CTRL] Times não carregados, carregando...');
        await loadTeams();
      }

      // Carregar projetos de cada equipe
      for (final team in _teams) {
        // Pular o time "Pessoal" pois já carregamos projetos pessoais
        if (team.name.toLowerCase().contains('pessoal')) {
          debugPrint(
            '📋 [KANBAN_CTRL] Pulando time "Pessoal" (já carregado projetos pessoais)',
          );
          continue;
        }

        debugPrint(
          '🚀 [KANBAN_CTRL] Carregando projetos da equipe: ${team.name} (${team.id})...',
        );
        final response = await _kanbanService.getProjectsByTeam(team.id);

        debugPrint('🚀 [KANBAN_CTRL] Resposta getProjectsByTeam:');
        debugPrint('🚀 [KANBAN_CTRL]   - success: ${response.success}');
        debugPrint('🚀 [KANBAN_CTRL]   - statusCode: ${response.statusCode}');
        debugPrint('🚀 [KANBAN_CTRL]   - message: ${response.message}');
        debugPrint(
          '🚀 [KANBAN_CTRL]   - data: ${response.data?.length ?? 0} projetos',
        );

        if (response.success && response.data != null) {
          allProjects.addAll(response.data!);
          debugPrint(
            '📋 [KANBAN_CTRL] ✅ ${response.data!.length} projetos da equipe "${team.name}" carregados',
          );
          for (var i = 0; i < response.data!.length; i++) {
            final p = response.data![i];
            debugPrint(
              '📋 [KANBAN_CTRL]   [${team.name} $i] ${p.name} (${p.id}) - Status: ${p.status.name} - Tarefas: ${p.taskCount}',
            );
          }
        }
      }

      // Remover duplicatas (caso algum projeto apareça em ambos)
      final uniqueProjects = <String, KanbanProject>{};
      for (final project in allProjects) {
        if (!uniqueProjects.containsKey(project.id)) {
          uniqueProjects[project.id] = project;
        }
      }

      _projects = uniqueProjects.values.toList();
      debugPrint(
        '📋 [KANBAN_CTRL] ✅ Total de ${_projects.length} projetos únicos carregados (pessoais + equipe)',
      );

      // Selecionar automaticamente o primeiro projeto se não houver projeto selecionado
      if (_projectId == null && _projects.isNotEmpty) {
        final firstProject = _projects.first;
        _projectId = firstProject.id;
        debugPrint(
          '📋 [KANBAN_CTRL] ✅ Projeto selecionado automaticamente: ${firstProject.name} (${firstProject.id})',
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
        '❌ [KANBAN_CTRL] ========== EXCEÇÃO em loadProjects ==========',
      );
      debugPrint('❌ [KANBAN_CTRL] Erro: $e');
      debugPrint('📚 [KANBAN_CTRL] StackTrace: $stackTrace');
      _projects = [];
    } finally {
      _loadingProjects = false;
      notifyListeners();
      debugPrint('📋 [KANBAN_CTRL] ========== FIM loadProjects ==========');
      debugPrint('📋 [KANBAN_CTRL] Total de projetos: ${_projects.length}');
    }
  }

  /// Seleciona um projeto
  Future<void> selectProject(String? projectId) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== selectProject ==========');
    debugPrint('🚀 [KANBAN_CTRL] Projeto selecionado: $projectId');
    debugPrint('🚀 [KANBAN_CTRL] Projeto anterior: $_projectId');
    debugPrint('🚀 [KANBAN_CTRL] teamId atual: $_teamId');

    _projectId = projectId;

    // Encontrar o projeto selecionado para obter o teamId correto
    String? projectTeamId;
    if (projectId != null) {
      final selectedProject = _projects.firstWhere(
        (p) => p.id == projectId,
        orElse: () => _projects.first,
      );
      projectTeamId = selectedProject.teamId;
      debugPrint(
        '🚀 [KANBAN_CTRL] Projeto encontrado: ${selectedProject.name} (teamId: $projectTeamId)',
      );
    }

    // Usar o teamId do projeto, ou o teamId atual como fallback
    final teamIdToUse = projectTeamId ?? _teamId;

    // Recarregar o quadro com o projeto selecionado
    if (teamIdToUse != null) {
      debugPrint(
        '🚀 [KANBAN_CTRL] Recarregando quadro com novo projeto (teamId: $teamIdToUse)...',
      );
      await loadBoard(teamId: teamIdToUse, projectId: _projectId);
    } else {
      debugPrint(
        '🚀 [KANBAN_CTRL] ⚠️ teamId é null, não é possível recarregar',
      );
    }

    debugPrint('🚀 [KANBAN_CTRL] ========== FIM selectProject ==========');
  }

  /// Aplica filtros nas tarefas
  void applyFilters({
    String? searchQuery,
    KanbanPriority? priority,
    String? assigneeId,
  }) {
    _searchQuery = searchQuery;
    _filterPriority = priority;
    _filterAssigneeId = assigneeId;
    notifyListeners();
  }

  /// Limpa todos os filtros
  void clearFilters() {
    _searchQuery = null;
    _filterPriority = null;
    _filterAssigneeId = null;
    notifyListeners();
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
