import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';

/// Controller para gerenciar estado do Kanban
class KanbanController extends ChangeNotifier {
  KanbanController._();

  static final KanbanController instance = KanbanController._();

  final KanbanService _kanbanService = KanbanService.instance;

  Timer? _boardFilterDebounce;

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
  /// Paginação de GET `/kanban/my-boards` (não baixamos todos os funis de uma vez).
  static const int _myBoardsPageSize = 24;
  int _myBoardsLastPageLoaded = 0;
  int _myBoardsTotalPages = 1;
  bool _loadingMoreTeams = false;
  KanbanTeam? _selectedTeam;

  // Filtros
  String? _searchQuery;
  KanbanPriority? _filterPriority;
  String? _filterAssigneeId;
  int _filterClearGeneration = 0;

  // Getters
  KanbanBoard? get board => _board;
  bool get loading => _loading;

  /// Exibe skeleton enquanto o quadro inicial não existe (inclui `loadTeams()` antes da API do board).
  bool get shouldShowKanbanSkeleton =>
      _loading || (_board == null && _error == null);

  String? get error => _error;
  String? get teamId => _teamId;
  String? get projectId => _projectId;
  List<KanbanProject> get projects => _projects;
  bool get loadingProjects => _loadingProjects;
  List<KanbanTeam> get teams => _teams;
  bool get loadingTeams => _loadingTeams;
  /// Ainda há páginas de funis em `/kanban/my-boards` para carregar sob demanda.
  bool get teamsHasMore =>
      _myBoardsLastPageLoaded > 0 &&
      _myBoardsLastPageLoaded < _myBoardsTotalPages;
  bool get loadingMoreTeams => _loadingMoreTeams;
  KanbanTeam? get selectedTeam => _selectedTeam;

  List<KanbanColumn> get columns {
    if (_board == null) return [];
    final sorted = List<KanbanColumn>.from(_board!.columns)
      ..sort((a, b) => a.position.compareTo(b.position));
    return sorted;
  }

  /// Colunas exibidas: API ou três etapas padrão refinadas até o servidor enviar o quadro.
  List<KanbanColumn> get displayColumns {
    if (_board == null) return const [];
    final fromApi = columns;
    if (fromApi.isNotEmpty) return fromApi;
    final seed =
        (_teamId != null && _teamId!.isNotEmpty)
            ? _teamId!
            : (_board!.team?.id ?? '');
    return KanbanSyntheticColumns.triple(seedTeamKey: seed);
  }

  KanbanTeam? _pickPreferredDefaultTeam(List<KanbanTeam> teams) {
    if (teams.isEmpty) return null;
    KanbanTeam? exactWorkspace;
    KanbanTeam? fuzzy;
    for (final t in teams) {
      final n = t.name.toLowerCase().trim();
      if (n == 'meu workspace') {
        exactWorkspace = t;
        break;
      }
    }
    if (exactWorkspace != null) return exactWorkspace;

    for (final t in teams) {
      final n = t.name.toLowerCase().trim();
      if (n.contains('meu workspace') ||
          (n.contains('workspace') && n.contains('meu'))) {
        return t;
      }
      if (n.contains('pessoal') || n.contains('workspace')) {
        fuzzy ??= t;
      }
    }
    return fuzzy ?? teams.first;
  }

  List<KanbanTeam> _dedupeTeamsKeepingOrder(Iterable<KanbanTeam> source) {
    final seen = <String>{};
    return source.where((t) => t.id.isNotEmpty && seen.add(t.id)).toList();
  }

  /// Coloca o funil preferido (ex.: Meu Workspace) no topo só entre os já carregados.
  void _orderTeamsPreferredFirst(List<KanbanTeam> teams) {
    final pick = _pickPreferredDefaultTeam(teams);
    if (pick == null) return;
    final i = teams.indexWhere((t) => t.id == pick.id);
    if (i > 0) {
      teams.removeAt(i);
      teams.insert(0, pick);
    }
  }

  List<KanbanTask> get tasks {
    return _board?.tasks ?? [];
  }

  /// Estado de filtros (espelho do que vai para `getBoard`) — uso no hero / UI.
  String? get searchQuery => _searchQuery;
  KanbanPriority? get filterPriority => _filterPriority;
  String? get filterAssigneeId => _filterAssigneeId;

  bool get hasActiveBoardFilters =>
      (_searchQuery != null && _searchQuery!.trim().isNotEmpty) ||
      _filterPriority != null ||
      (_filterAssigneeId != null && _filterAssigneeId!.trim().isNotEmpty);

  /// Incrementado em [clearFilters]; permite reset estável dos campos locais em [KanbanFilters].
  int get filterClearGeneration => _filterClearGeneration;

  List<KanbanTask> getTasksForColumn(String columnId) {
    final filteredTasks = tasks
        .where((task) => task.columnId == columnId)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return filteredTasks;
  }

  KanbanPermissions? get permissions => _board?.permissions;
  KanbanTeam? get team => _board?.team;

  /// Ao abrir a página: primeiro frame já mostra skeleton se ainda não há quadro nem erro.
  void markKanbanEnteringIfNeeded() {
    if (_board != null || _error != null) return;
    if (!_loading) {
      _loading = true;
      notifyListeners();
    }
  }

  /// Carrega o quadro Kanban (teamId vindo de `/kanban/my-boards` quando possível;
  /// filtros e `perColumnLimit` alinhados ao front Intellisys).
  Future<void> loadBoard({
    String? teamId,
    String? projectId,
    bool recovery404 = false,
  }) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== INICIANDO loadBoard ==========');
    debugPrint('🚀 [KANBAN_CTRL] Parâmetros recebidos:');
    debugPrint('🚀 [KANBAN_CTRL] - teamId: $teamId');
    debugPrint('🚀 [KANBAN_CTRL] - projectId: $projectId');
    debugPrint('🚀 [KANBAN_CTRL] - Estado atual:');
    debugPrint('🚀 [KANBAN_CTRL]   - _teamId: $_teamId');
    debugPrint('🚀 [KANBAN_CTRL]   - _projectId: $_projectId');

    _updateState(loading: true, clearError: true);

    try {
      String? resolvedTeamId = teamId ?? _teamId;

      // Descobrir equipe usando a mesma regra que o sistema web (funis permitidos).
      if (resolvedTeamId == null || resolvedTeamId.isEmpty) {
        debugPrint(
          '📋 [KANBAN_CTRL] ⚠️ teamId não definido — usando caches /fallbacks…',
        );
        if (_teams.isEmpty) {
          await loadTeams();
        }
        if (_teams.isNotEmpty) {
          _selectedTeam ??= _pickPreferredDefaultTeam(_teams);
          resolvedTeamId = (_selectedTeam ?? _teams.first).id;
          debugPrint(
            '📋 [KANBAN_CTRL] ✅ Time definido pelo my-boards: ${_selectedTeam?.name}',
          );
        }
      }

      if (resolvedTeamId == null || resolvedTeamId.isEmpty) {
        debugPrint(
          '📋 [KANBAN_CTRL] ⚠️ Nenhum funil listado — tentando workspace pessoal...',
        );
        final personalResponse = await _kanbanService.getPersonalWorkspace();
        if (personalResponse.success &&
            personalResponse.data != null &&
            personalResponse.data!.isNotEmpty) {
          final personalProject = personalResponse.data!.first;
          resolvedTeamId = personalProject.teamId;
          debugPrint(
            '📋 [KANBAN_CTRL] ✅ Workspace pessoal: $resolvedTeamId',
          );
        } else {
          debugPrint(
            '📋 [KANBAN_CTRL] ⚠️ Sem funil listado nem workspace pessoal.',
          );
          _updateState(
            error:
                'Nenhum funil (equipe) disponível nesta empresa ou sem workspace pessoal. '
                'Peça inclusão nas equipes ou crie/use um funil pessoal pelo CRM web.',
            loading: false,
          );
          return;
        }
      }

      _teamId = resolvedTeamId;
      if (projectId != null) {
        _projectId = projectId;
      }

      debugPrint(
        '📋 [KANBAN_CTRL] ========== CHAMANDO API getBoard ==========',
      );
      debugPrint('📋 [KANBAN_CTRL] - teamId: $_teamId');
      debugPrint('📋 [KANBAN_CTRL] - projectId: $_projectId');
      debugPrint('📋 [KANBAN_CTRL] - search: $_searchQuery');
      debugPrint('📋 [KANBAN_CTRL] - priority: $_filterPriority');

      final response = await _kanbanService.getBoard(
        _teamId!,
        projectId: _projectId,
        search: _searchQuery,
        priority: _filterPriority,
        assignedToId: _filterAssigneeId,
      );

      debugPrint('📋 [KANBAN_CTRL] ========== RESPOSTA getBoard ==========');
      debugPrint('📋 [KANBAN_CTRL] - success: ${response.success}');
      debugPrint('📋 [KANBAN_CTRL] - statusCode: ${response.statusCode}');

      if (response.success && response.data != null) {
        final board = response.data!;
        debugPrint('📋 [KANBAN_CTRL] ✅ Quadro carregado');
        debugPrint(
          '📋 [KANBAN_CTRL]   - Colunas: ${board.columns.length}, Tarefas: ${board.tasks.length}',
        );

        _updateState(board: board, loading: false);

        if (_teamId != null) {
          await loadProjects(teamId: _teamId);
        }
      } else {
        if (response.statusCode == 404 && !recovery404) {
          debugPrint(
            '📋 [KANBAN_CTRL] ⚠️ 404 Equipe não encontrada — re-sincronizando funis (/my-boards)...',
          );
          final badTeamId = _teamId;
          await loadTeams();
          KanbanTeam? pick;
          for (final t in _teams) {
            if (t.id != badTeamId) {
              pick = t;
              break;
            }
          }
          if (pick != null) {
            _selectedTeam = pick;
            await loadBoard(
              teamId: pick.id,
              projectId: projectId ?? _projectId,
              recovery404: true,
            );
            return;
          }
          final personalResponse = await _kanbanService.getPersonalWorkspace();
          if (personalResponse.success &&
              personalResponse.data != null &&
              personalResponse.data!.isNotEmpty) {
            final pid = personalResponse.data!.first.teamId;
            if (pid != badTeamId && pid.isNotEmpty) {
              await loadBoard(
                teamId: pid,
                projectId: projectId ?? _projectId,
                recovery404: true,
              );
              return;
            }
          }
        }

        final is403Project =
            response.statusCode == 403 &&
            _projectId != null &&
            _projectId!.isNotEmpty;

        if (response.statusCode == 403) {
          debugPrint(
            '📋 [KANBAN_CTRL] ⚠️ 403 — tentando workspace pessoal...',
          );
          final personalResponse = await _kanbanService.getPersonalWorkspace();
          if (personalResponse.success &&
              personalResponse.data != null &&
              personalResponse.data!.isNotEmpty) {
            final personalProject = personalResponse.data!.first;
            final personalTeamId = personalProject.teamId;
            final personalBoardResponse = await _kanbanService.getBoard(
              personalTeamId,
              projectId: _projectId,
              search: _searchQuery,
              priority: _filterPriority,
              assignedToId: _filterAssigneeId,
            );
            if (personalBoardResponse.success &&
                personalBoardResponse.data != null) {
              _teamId = personalTeamId;
              _updateState(board: personalBoardResponse.data!, loading: false);
              await loadProjects(teamId: _teamId);
              return;
            }
          }
        }

        final fallbackMsg = is403Project
            ? 'Você não tem acesso a este funil. Peça a um líder para incluir você numa das equipes vinculadas a ele.'
            : (response.message ?? 'Erro ao carregar quadro Kanban');

        debugPrint('📋 [KANBAN_CTRL] ❌ $fallbackMsg');
        _updateState(error: fallbackMsg, loading: false);
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

  /// Carrega apenas a **primeira página** de funis (`/kanban/my-boards`).
  /// Use [loadMoreTeams] no seletor para páginas seguintes — evita puxar centenas de funis de uma vez.
  Future<void> loadTeams({bool reset = true}) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== INICIANDO loadTeams (my-boards pg1) ==========');

    _loadingTeams = true;
    final previousSelectionId =
        reset ? (_selectedTeam?.id ?? _teamId) : null;
    if (reset) {
      _myBoardsLastPageLoaded = 0;
      _myBoardsTotalPages = 1;
      _teams = [];
    }
    notifyListeners();

    try {
      final response = await _kanbanService.getMyBoardsPage(
        page: 1,
        limit: _myBoardsPageSize,
      );

      debugPrint('🚀 [KANBAN_CTRL] my-boards pg1 — success: ${response.success}');

      if (response.success && response.data != null) {
        final dto = response.data!;
        final fromSlots =
            dto.boards.map((s) => s.team).where((t) => t.id.isNotEmpty);
        _teams = _dedupeTeamsKeepingOrder(fromSlots);
        _orderTeamsPreferredFirst(_teams);

        _myBoardsLastPageLoaded = dto.page;
        _myBoardsTotalPages = dto.totalPages < 1 ? 1 : dto.totalPages;

        _selectedTeam = null;
        if (previousSelectionId != null) {
          for (final t in _teams) {
            if (t.id == previousSelectionId) {
              _selectedTeam = t;
              break;
            }
          }
        }
        _selectedTeam ??=
            _teams.isNotEmpty ? _pickPreferredDefaultTeam(_teams) : null;
        debugPrint(
          '📋 [KANBAN_CTRL] ✅ ${_teams.length} funis (página $_myBoardsLastPageLoaded/$_myBoardsTotalPages)',
        );
      } else {
        _teams = [];
        debugPrint(
          '📋 [KANBAN_CTRL] ⚠️ my-boards vazio ou erro: ${response.message}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [KANBAN_CTRL] EXCEÇÃO em loadTeams: $e');
      debugPrint('📚 [KANBAN_CTRL] StackTrace: $stackTrace');
      _teams = [];
    } finally {
      _loadingTeams = false;
      notifyListeners();
      debugPrint('📋 [KANBAN_CTRL] ========== FIM loadTeams ==========');
    }
  }

  /// Próxima página de funis (chamado ao rolar o seletor ou em “carregar mais”).
  Future<void> loadMoreTeams() async {
    if (!teamsHasMore || _loadingMoreTeams || _loadingTeams) return;

    final nextPage = _myBoardsLastPageLoaded + 1;
    if (nextPage > _myBoardsTotalPages) return;

    _loadingMoreTeams = true;
    notifyListeners();

    try {
      final response = await _kanbanService.getMyBoardsPage(
        page: nextPage,
        limit: _myBoardsPageSize,
      );

      if (response.success && response.data != null) {
        final dto = response.data!;
        final incoming =
            dto.boards.map((s) => s.team).where((t) => t.id.isNotEmpty);
        for (final t in incoming) {
          if (_teams.every((x) => x.id != t.id)) {
            _teams.add(t);
          }
        }
        _myBoardsLastPageLoaded = dto.page;
        _myBoardsTotalPages = dto.totalPages < 1 ? 1 : dto.totalPages;
        debugPrint(
          '📋 [KANBAN_CTRL] ✅ +funis página $nextPage → total ${_teams.length}',
        );
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] loadMoreTeams: $e');
    } finally {
      _loadingMoreTeams = false;
      notifyListeners();
    }
  }

  /// Seleciona um funil (equipe). Zera o projeto para evitar 403 ao misturar equipes.
  Future<void> selectTeam(KanbanTeam? team) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== selectTeam ==========');
    debugPrint(
      '🚀 [KANBAN_CTRL] Time selecionado: ${team?.name} (${team?.id})',
    );
    debugPrint(
      '🚀 [KANBAN_CTRL] Time anterior: ${_selectedTeam?.name} (${_selectedTeam?.id})',
    );

    if (team == null) {
      _selectedTeam = null;
      debugPrint('🚀 [KANBAN_CTRL] Time desmarcado');
      debugPrint('🚀 [KANBAN_CTRL] ========== FIM selectTeam ==========');
      notifyListeners();
      return;
    }

    final same = _selectedTeam?.id == team.id;
    _selectedTeam = team;
    if (same) {
      debugPrint('🚀 [KANBAN_CTRL] Mesmo funil — ignorando recarga');
      debugPrint('🚀 [KANBAN_CTRL] ========== FIM selectTeam ==========');
      return;
    }

    _projectId = null;
    debugPrint(
      '🚀 [KANBAN_CTRL] Recarregando projetos e quadro com novo funil…',
    );
    await loadProjects(teamId: team.id);
    await loadBoard(teamId: team.id, projectId: null);

    debugPrint('🚀 [KANBAN_CTRL] ========== FIM selectTeam ==========');
  }

  /// Carrega projetos só do funil atual — evita N requisições (uma por equipe).
  Future<void> loadProjects({String? teamId}) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== INICIANDO loadProjects ==========');
    debugPrint('🚀 [KANBAN_CTRL] Parâmetro teamId: $teamId');
    debugPrint('🚀 [KANBAN_CTRL] _teamId atual: $_teamId');

    teamId ??= _teamId ?? _selectedTeam?.id;
    debugPrint('🚀 [KANBAN_CTRL] teamId efetivo: $teamId');

    _loadingProjects = true;
    notifyListeners();
    debugPrint('🚀 [KANBAN_CTRL] Estado _loadingProjects: true');

    try {
      if (teamId == null || teamId.isEmpty) {
        _projects = [];
        debugPrint('📋 [KANBAN_CTRL] Sem teamId — lista de projetos vazia');
        return;
      }

      KanbanTeam? team;
      for (final t in _teams) {
        if (t.id == teamId) {
          team = t;
          break;
        }
      }
      team ??= _board?.team?.id == teamId ? _board!.team : _selectedTeam;

      final nameLower = (team?.name ?? '').toLowerCase();
      final usePersonalList =
          nameLower.contains('pessoal') && !nameLower.contains('workspace');

      if (usePersonalList) {
        debugPrint(
          '📋 [KANBAN_CTRL] Funil pessoal — getPersonalWorkspace()',
        );
        final personalResponse = await _kanbanService.getPersonalWorkspace();
        if (personalResponse.success && personalResponse.data != null) {
          _projects = List<KanbanProject>.from(personalResponse.data!);
          debugPrint(
            '📋 [KANBAN_CTRL] ✅ ${_projects.length} projetos (pessoal)',
          );
        } else {
          _projects = [];
          debugPrint(
            '📋 [KANBAN_CTRL] ⚠️ Pessoal vazio: ${personalResponse.message}',
          );
        }
      } else {
        debugPrint(
          '📋 [KANBAN_CTRL] getProjectsByTeam($teamId)…',
        );
        final response = await _kanbanService.getProjectsByTeam(teamId);
        if (response.success && response.data != null) {
          _projects = List<KanbanProject>.from(response.data!);
          debugPrint(
            '📋 [KANBAN_CTRL] ✅ ${_projects.length} projetos do funil atual',
          );
        } else {
          _projects = [];
          debugPrint(
            '📋 [KANBAN_CTRL] ⚠️ Projetos: ${response.message}',
          );
        }
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
      final idx = _projects.indexWhere((p) => p.id == projectId);
      if (idx != -1) {
        projectTeamId = _projects[idx].teamId;
        debugPrint(
          '🚀 [KANBAN_CTRL] Projeto encontrado: ${_projects[idx].name} (teamId: $projectTeamId)',
        );
      }
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

  /// Filtros reenviados à API (`KanbanBoardFiltersDto`) como no Intellisys.
  void applyFilters({
    String? searchQuery,
    KanbanPriority? priority,
    String? assigneeId,
  }) {
    final trimmed = searchQuery?.trim();
    _searchQuery = trimmed == null || trimmed.isEmpty ? null : trimmed;
    _filterPriority = priority;
    _filterAssigneeId =
        assigneeId != null && assigneeId.isEmpty ? null : assigneeId;
    notifyListeners();

    _boardFilterDebounce?.cancel();
    final delayMs =
        (_searchQuery != null && _searchQuery!.trim().isNotEmpty) ? 420 : 0;
    _boardFilterDebounce = Timer(Duration(milliseconds: delayMs), () {
      if (_teamId == null) return;
      loadBoard(teamId: _teamId, projectId: _projectId);
    });
  }

  void clearFilters() {
    _boardFilterDebounce?.cancel();
    _searchQuery = null;
    _filterPriority = null;
    _filterAssigneeId = null;
    _filterClearGeneration++;
    notifyListeners();
    if (_teamId != null) {
      loadBoard(teamId: _teamId, projectId: _projectId);
    }
  }

  /// Atualiza estado interno
  void _updateState({
    KanbanBoard? board,
    bool? loading,
    String? error,
    String? teamId,
    String? projectId,
    bool clearError = false,
  }) {
    if (board != null) _board = board;
    if (loading != null) _loading = loading;
    if (clearError) _error = null;
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
    _teams = [];
    _myBoardsLastPageLoaded = 0;
    _myBoardsTotalPages = 1;
    _loadingMoreTeams = false;
    notifyListeners();
  }
}
