import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';
import '../services/team_service.dart';
import '../../../shared/services/secure_storage_service.dart';

/// Controller para gerenciar estado do Kanban
class KanbanController extends ChangeNotifier {
  KanbanController._();

  static final KanbanController instance = KanbanController._();

  static final Map<String, bool> _bulkLeaderEligibilityCache = {};

  final KanbanService _kanbanService = KanbanService.instance;
  final TeamService _teamService = TeamService.instance;

  Timer? _boardFilterDebounce;

  // Estado
  KanbanBoard? _board;
  bool _loading = false;
  String? _error;
  String? _teamId;
  String? _projectId;
  List<KanbanProject> _projects = [];
  bool _loadingProjects = false;
  /// Equipes onde o usuário pode ver funis (`GET /kanban/teams` — igual ao web).
  List<KanbanTeam> _kanbanTeams = [];

  // Filtros
  String? _searchQuery;
  KanbanPriority? _filterPriority;
  String? _filterAssigneeId;
  int _filterClearGeneration = 0;

  // Seleção em massa / exclusão em lote — paridade `useCanBulkDeleteCards` + KanbanBoard web.
  bool _bulkSelectionActive = false;
  final Set<String> _bulkSelectedTaskIds = <String>{};
  bool _bulkDeleteEligible = false;
  bool _bulkDeleteEligibilityLoading = false;
  String? _bulkBoardContextKey;
  bool _bulkDeleting = false;
  bool _lastProjectHydrated = false;

  // ── Paginação por coluna ────────────────────────────────────────────
  /// Estado de paginação por coluna. Inicializado quando `loadBoard`
  /// retorna e usado por `loadMoreTasksForColumn`.
  ///
  /// O board (`getBoard`) traz só `perColumnLimit` cards (default 12)
  /// por coluna. Pra carregar os próximos, chamamos
  /// `GET /kanban/columns/:id/tasks?page=N&limit=12` e fazemos append no
  /// `_board.tasks`. O `_columnPagination[columnId]` mantém qual a
  /// próxima página, total de páginas (descoberto após 1ª chamada
  /// paginada), e flags de loading/hasMore.
  static const int _kColumnPageSize = 12;
  final Map<String, ColumnPagination> _columnPagination = {};

  // Getters
  KanbanBoard? get board => _board;
  bool get loading => _loading;

  /// Exibe skeleton enquanto o quadro inicial não existe (resolver equipe antes do board).
  bool get shouldShowKanbanSkeleton =>
      _loading || (_board == null && _error == null);

  String? get error => _error;
  String? get teamId => _teamId;
  String? get projectId => _projectId;
  List<KanbanProject> get projects => _projects;
  bool get loadingProjects => _loadingProjects;

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

  bool get bulkSelectionActive => _bulkSelectionActive;

  int get bulkSelectedCount => _bulkSelectedTaskIds.length;

  bool get bulkDeleting => _bulkDeleting;

  bool get bulkDeleteEligibilityLoading => _bulkDeleteEligibilityLoading;

  /// Pode usar o fluxo de exclusão em massa (role ou líder da equipe do funil).
  bool get canBulkDelete => _bulkDeleteEligible;

  /// Entrada na UI: permissão na API já liberada + regra de negócio resolvida.
  bool get showBulkSelectionEntry =>
      (permissions?.canDeleteTasks ?? false) &&
      !_bulkDeleteEligibilityLoading &&
      _bulkDeleteEligible;

  bool isBulkTaskSelected(String taskId) => _bulkSelectedTaskIds.contains(taskId);

  List<KanbanTask> getTasksForColumn(String columnId) {
    final filteredTasks = tasks
        .where((task) => task.columnId == columnId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filteredTasks;
  }

  KanbanPermissions? get permissions => _board?.permissions;
  KanbanTeam? get team => _board?.team;

  /// Equipes com funis Kanban conforme permissão (`GET /kanban/teams?onlyWithProjects=true`).
  Future<bool> loadKanbanTeams({bool reset = false}) async {
    if (reset) _kanbanTeams = [];
    final response =
        await _kanbanService.getKanbanTeams(onlyWithProjects: true);
    if (response.success && response.data != null) {
      _kanbanTeams = _dedupeTeamsKeepingOrder(response.data!);
      _orderTeamsPreferredFirst(_kanbanTeams);
      notifyListeners();
      return _kanbanTeams.isNotEmpty;
    }
    _kanbanTeams = [];
    notifyListeners();
    return false;
  }

  /// Lista unificada de funis (`ProjectSelect`): equipes permitidas + pessoais + sem equipe.
  ///
  /// Otimização: as 3 chamadas (`getProjectsByTeams`, `getPersonalWorkspace`,
  /// `getProjectsWithoutTeam`) são totalmente independentes — antes rodavam
  /// sequencialmente (~3x latência). Agora vão em paralelo via `Future.wait`.
  Future<void> loadAccessibleProjects({
    bool refreshKanbanTeams = false,
  }) async {
    debugPrint(
      '🚀 [KANBAN_CTRL] ========== INICIANDO loadAccessibleProjects ==========',
    );
    _loadingProjects = true;
    notifyListeners();
    try {
      if (_kanbanTeams.isEmpty || refreshKanbanTeams) {
        await loadKanbanTeams(reset: refreshKanbanTeams);
      }

      final byId = <String, KanbanProject>{};
      final teamIds =
          _kanbanTeams.map((t) => t.id).where((id) => id.isNotEmpty).toList();

      // Roda os 3 fetches em paralelo. Cada um tolera falha
      // individualmente para não derrubar a lista combinada.
      final batchFuture = teamIds.isNotEmpty
          ? _kanbanService.getProjectsByTeams(teamIds)
          : Future.value(null);
      final personalFuture = _kanbanService.getPersonalWorkspace();
      final orphanFuture = _kanbanService.getProjectsWithoutTeam();

      final results = await Future.wait<dynamic>([
        batchFuture,
        personalFuture,
        orphanFuture,
      ]);

      final batchResp = results[0];
      final personalResp = results[1];
      final orphanResp = results[2];

      if (batchResp != null &&
          batchResp.success == true &&
          batchResp.data != null) {
        for (final p in batchResp.data! as List<KanbanProject>) {
          if (p.id.isNotEmpty) byId[p.id] = p;
        }
      } else if (batchResp != null) {
        debugPrint(
          '📋 [KANBAN_CTRL] getProjectsByTeams: ${batchResp.message}',
        );
      }

      if (personalResp.success && personalResp.data != null) {
        for (final p in personalResp.data! as List<KanbanProject>) {
          if (p.id.isNotEmpty) byId[p.id] = p;
        }
      }

      if (orphanResp.success && orphanResp.data != null) {
        for (final p in orphanResp.data! as List<KanbanProject>) {
          if (p.id.isNotEmpty) byId[p.id] = p;
        }
      }

      final merged = byId.values.toList()
        ..sort((a, b) {
          final ap = a.isPersonal == true ? 0 : 1;
          final bp = b.isPersonal == true ? 0 : 1;
          if (ap != bp) return ap.compareTo(bp);
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      _projects = merged;
      _assignDefaultWorkspaceIfUnset(_projects);
      debugPrint(
        '📋 [KANBAN_CTRL] ✅ ${_projects.length} funil(is) na lista combinada',
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [KANBAN_CTRL] loadAccessibleProjects: $e');
      debugPrint('📚 [KANBAN_CTRL] $stackTrace');
      _projects = [];
    } finally {
      _loadingProjects = false;
      notifyListeners();
      debugPrint(
        '📋 [KANBAN_CTRL] ========== FIM loadAccessibleProjects ==========',
      );
    }
  }

  /// Funil padrão: workspace pessoal / “Meu workspace”, nunca visão agregada.
  KanbanProject? _pickDefaultWorkspaceProject(List<KanbanProject> projects) {
    if (projects.isEmpty) return null;

    KanbanProject? personalActive;
    for (final p in projects) {
      if (p.isPersonal == true && p.status == KanbanProjectStatus.active) {
        personalActive = p;
        break;
      }
    }
    if (personalActive != null) return personalActive;

    for (final p in projects) {
      if (p.isPersonal == true) return p;
    }

    final wsTeam = _pickPreferredDefaultTeam(_kanbanTeams);
    if (wsTeam != null) {
      for (final p in projects) {
        if (p.teamId == wsTeam.id && p.status == KanbanProjectStatus.active) {
          return p;
        }
      }
      for (final p in projects) {
        if (p.teamId == wsTeam.id) return p;
      }
    }

    for (final p in projects) {
      if (p.status == KanbanProjectStatus.active) return p;
    }
    return projects.first;
  }

  /// Garante [_projectId] (e [_teamId] coerente) quando ainda não há funil escolhido.
  void _assignDefaultWorkspaceIfUnset(List<KanbanProject> merged) {
    if (merged.isEmpty) return;
    final current = _projectId?.trim();
    if (current != null &&
        current.isNotEmpty &&
        merged.any((p) => p.id == current)) {
      return;
    }
    final def = _pickDefaultWorkspaceProject(merged);
    if (def == null || def.id.isEmpty) return;
    _projectId = def.id;
    if (def.teamId.trim().isNotEmpty) {
      _teamId = def.teamId;
    }
  }

  /// Antes do getBoard: não existe “todos os funis”; exige um funil — padrão workspace.
  Future<void> _ensureDefaultWorkspaceFunnel() async {
    if (_projectId != null && _projectId!.trim().isNotEmpty) return;
    await loadAccessibleProjects();
  }

  /// Restaura o último funil selecionado salvo localmente (escopo por empresa).
  Future<void> _hydrateLastSelectedProjectIfNeeded() async {
    if (_lastProjectHydrated) return;
    _lastProjectHydrated = true;
    try {
      final companyId = await SecureStorageService.instance.getCompanyId();
      final persisted = await SecureStorageService.instance.getLastKanbanProjectId(
        companyId: companyId,
      );
      if (persisted != null && persisted.isNotEmpty) {
        _projectId = persisted;
      }
    } catch (e) {
      debugPrint('⚠️ [KANBAN_CTRL] Falha ao restaurar último funil: $e');
    }
  }

  /// Ao abrir a página: primeiro frame já mostra skeleton se ainda não há quadro nem erro.
  void markKanbanEnteringIfNeeded() {
    if (_board != null || _error != null) return;
    if (!_loading) {
      _loading = true;
      notifyListeners();
    }
  }

  /// Carrega o quadro Kanban (teamId resolvido via `GET /kanban/teams` quando necessário;
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
      await _hydrateLastSelectedProjectIfNeeded();
      String? resolvedTeamId = teamId ?? _teamId;

      // Descobrir equipe (paridade web: `GET /kanban/teams?onlyWithProjects=true`).
      if (resolvedTeamId == null || resolvedTeamId.isEmpty) {
        debugPrint(
          '📋 [KANBAN_CTRL] ⚠️ teamId não definido — carregando equipes do Kanban…',
        );
        if (_kanbanTeams.isEmpty) {
          await loadKanbanTeams();
        }
        if (_kanbanTeams.isNotEmpty) {
          final preferred = _pickPreferredDefaultTeam(_kanbanTeams);
          resolvedTeamId = (preferred ?? _kanbanTeams.first).id;
          debugPrint(
            '📋 [KANBAN_CTRL] ✅ Equipe inicial: ${preferred?.name ?? _kanbanTeams.first.name}',
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
      if (projectId != null && projectId.trim().isNotEmpty) {
        _projectId = projectId;
      }

      await _ensureDefaultWorkspaceFunnel();
      _syncBulkBoardContext();

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

        // Otimização: a lista de funis e o eligibility check de bulk
        // delete são independentes do board renderizado. Antes rodavam
        // sequencialmente DEPOIS do board pintar, segurando o "loading"
        // do project-selector mais tempo do que precisava. Agora vão em
        // paralelo — sem await — para que a UI já reaja.
        // (Errors são tolerados internamente em cada método.)
        if (_teamId != null) {
          // ignore: unawaited_futures
          loadAccessibleProjects();
        }
        // ignore: unawaited_futures
        refreshBulkDeleteEligibility();
      } else {
        if (response.statusCode == 404 && !recovery404) {
          debugPrint(
            '📋 [KANBAN_CTRL] ⚠️ 404 Equipe não encontrada — re-sincronizando equipes (/kanban/teams)...',
          );
          final badTeamId = _teamId;
          await loadKanbanTeams(reset: true);
          KanbanTeam? pick;
          for (final t in _kanbanTeams) {
            if (t.id != badTeamId) {
              pick = t;
              break;
            }
          }
          if (pick != null) {
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
              await loadAccessibleProjects();
              await refreshBulkDeleteEligibility();
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

  /// Cria uma tarefa. Retorna a tarefa criada ou `null` em caso de erro.
  Future<KanbanTask?> createTask(CreateTaskDto dto) async {
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
    debugPrint('🚀 [KANBAN_CTRL]   - tagIds: ${dto.tagIds ?? "null"}');
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
      if (_projects.isEmpty) {
        debugPrint(
          '🚀 [KANBAN_CTRL] Lista de funis vazia, carregando catálogo acessível...',
        );
        await loadAccessibleProjects();
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
        _error =
            'Nenhum funil disponível para criar o card. Crie ou peça acesso a um funil no CRM.';
        notifyListeners();
        return null;
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
      tagIds: dto.tagIds,
      totalValue: dto.totalValue,
      clientId: dto.clientId,
      propertyId: dto.propertyId,
      source: dto.source,
      mediaSource: dto.mediaSource,
      campaign: dto.campaign,
      metaCampaignId: dto.metaCampaignId,
      systemCampaignId: dto.systemCampaignId,
      metaFormId: dto.metaFormId,
      internalNotes: dto.internalNotes,
      contacts: dto.contacts,
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
        return task;
      } else {
        debugPrint(
          '🚀 [KANBAN_CTRL] ❌ Erro ao criar tarefa: ${response.message}',
        );
        _error = response.message ?? 'Erro ao criar tarefa';
        notifyListeners();
        debugPrint(
          '🚀 [KANBAN_CTRL] ========== FIM createTask (ERRO) ==========',
        );
        return null;
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
      return null;
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

  /// Marca resultado (ganho / perda / reabrir). Recarrega o quadro em caso de sucesso.
  Future<bool> markTaskResult(
    String taskId, {
    required String result,
    String? lossReason,
    String? notes,
  }) async {
    try {
      final response = await _kanbanService.markTaskResult(
        taskId,
        result: result,
        lossReason: lossReason,
        notes: notes,
      );

      if (response.success) {
        await loadBoard(teamId: _teamId, projectId: _projectId);
        return true;
      }
      _error = response.message ?? 'Erro ao marcar resultado';
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] markTaskResult: $e');
      _error = 'Erro ao marcar resultado: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Transfere o card para outro funil. Recarrega o quadro em caso de sucesso.
  Future<bool> transferTask(
    String taskId,
    KanbanTransferTaskPayload payload,
  ) async {
    try {
      final response = await _kanbanService.transferTask(taskId, payload);

      if (response.success) {
        await loadBoard(teamId: _teamId, projectId: _projectId);
        return true;
      }
      _error = response.message ?? 'Erro ao transferir tarefa';
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] transferTask: $e');
      _error = 'Erro ao transferir tarefa: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Move uma tarefa.
  ///
  /// `fromColumnId` é obrigatório no backend (validado via `@IsUUID`). Quando
  /// não passado, recuperamos a partir do snapshot da tarefa no board para
  /// manter o contrato sem fricção em chamadas legadas.
  Future<bool> moveTask({
    required String taskId,
    required String targetColumnId,
    required int targetPosition,
    String? fromColumnId,
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

    String? originColumnId = fromColumnId;

    try {
      // Optimistic update + descoberta automática do fromColumnId quando o
      // chamador não passou explicitamente (alinhado ao DTO obrigatório do
      // backend).
      if (_board != null) {
        final taskIndex = _board!.tasks.indexWhere((t) => t.id == taskId);
        if (taskIndex != -1) {
          final task = _board!.tasks[taskIndex];
          originColumnId ??= task.columnId;
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

      if (originColumnId == null || originColumnId.isEmpty) {
        if (previousBoard != null) {
          _board = previousBoard;
          notifyListeners();
        }
        _error = 'Coluna de origem da tarefa não identificada.';
        notifyListeners();
        return false;
      }

      final response = await _kanbanService.moveTask(
        MoveTaskDto(
          taskId: taskId,
          fromColumnId: originColumnId,
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

  /// Seleciona um funil (sempre um UUID concreto — não há “todos os funis”).
  Future<void> selectProject(String projectId) async {
    debugPrint('🚀 [KANBAN_CTRL] ========== selectProject ==========');
    debugPrint('🚀 [KANBAN_CTRL] Projeto selecionado: $projectId');
    debugPrint('🚀 [KANBAN_CTRL] Projeto anterior: $_projectId');
    debugPrint('🚀 [KANBAN_CTRL] teamId atual: $_teamId');

    if (projectId.trim().isEmpty) return;
    _projectId = projectId;
    final companyId = await SecureStorageService.instance.getCompanyId();
    await SecureStorageService.instance.saveLastKanbanProjectId(
      projectId: projectId,
      companyId: companyId,
    );

    // Encontrar o projeto selecionado para obter o teamId correto
    String? projectTeamId;
    final idx = _projects.indexWhere((p) => p.id == projectId);
    if (idx != -1) {
      projectTeamId = _projects[idx].teamId;
      debugPrint(
        '🚀 [KANBAN_CTRL] Projeto encontrado: ${_projects[idx].name} (teamId: $projectTeamId)',
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

  void _syncBulkBoardContext() {
    final key = '${_teamId ?? ''}|${_projectId ?? ''}';
    if (_bulkBoardContextKey != null &&
        _bulkBoardContextKey != key &&
        (_bulkSelectionActive || _bulkSelectedTaskIds.isNotEmpty)) {
      _bulkSelectionActive = false;
      _bulkSelectedTaskIds.clear();
    }
    _bulkBoardContextKey = key;
  }

  bool _isBulkTeamQueryId(String? id) {
    if (id == null) return false;
    final t = id.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    if (lower == 'undefined' || lower == 'null') return false;
    if (lower.startsWith('personal')) return false;
    return true;
  }

  Set<String> _teamIdsEligibleForBulk() {
    final out = <String>{};
    void addMaybe(String? id) {
      if (!_isBulkTeamQueryId(id)) return;
      out.add(id!.trim());
    }

    addMaybe(_teamId);
    addMaybe(_board?.team?.id);
    final ix = _projects.indexWhere((p) => p.id == (_projectId ?? ''));
    if (ix >= 0) {
      final p = _projects[ix];
      addMaybe(p.teamId);
      final extra = p.teamIds;
      if (extra != null) {
        for (final x in extra) {
          addMaybe(x);
        }
      }
    }
    return out;
  }

  Future<(String?, String?)> _jwtSubAndRole() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) return (null, null);
      final parts = token.split('.');
      if (parts.length != 3) return (null, null);
      var output = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (output.length % 4) {
        case 2:
          output += '==';
          break;
        case 3:
          output += '=';
          break;
      }
      final jsonBytes = base64Decode(output);
      final decoded = utf8.decode(jsonBytes);
      final map = jsonDecode(decoded);
      if (map is! Map) return (null, null);
      final m = Map<String, dynamic>.from(map);
      final sub = m['sub']?.toString() ??
          m['userId']?.toString() ??
          m['id']?.toString();
      final role = m['role']?.toString();
      return (sub, role);
    } catch (e) {
      debugPrint('⚠️ [KANBAN_CTRL] JWT parse: $e');
      return (null, null);
    }
  }

  /// Atualiza se o usuário pode usar exclusão em massa (`master` / `admin` / `manager` ou `leader`).
  Future<void> refreshBulkDeleteEligibility() async {
    final canDeleteTasks = permissions?.canDeleteTasks ?? false;
    if (!canDeleteTasks) {
      _bulkDeleteEligible = false;
      _bulkDeleteEligibilityLoading = false;
      exitBulkSelectionMode();
      notifyListeners();
      return;
    }

    final claims = await _jwtSubAndRole();
    final userId = claims.$1 ?? '';
    final role = claims.$2?.toLowerCase().trim() ?? '';

    if (userId.isEmpty) {
      _bulkDeleteEligible = false;
      _bulkDeleteEligibilityLoading = false;
      exitBulkSelectionMode();
      notifyListeners();
      return;
    }

    if (role == 'master' || role == 'admin' || role == 'manager') {
      _bulkDeleteEligible = true;
      _bulkDeleteEligibilityLoading = false;
      notifyListeners();
      return;
    }

    final teamIds = _teamIdsEligibleForBulk().toList()..sort();

    if (teamIds.isEmpty) {
      _bulkDeleteEligible = false;
      _bulkDeleteEligibilityLoading = false;
      exitBulkSelectionMode();
      notifyListeners();
      return;
    }

    final cacheKey = '$userId::${teamIds.join(',')}';
    final cached = KanbanController._bulkLeaderEligibilityCache[cacheKey];
    if (cached != null) {
      _bulkDeleteEligible = cached;
      _bulkDeleteEligibilityLoading = false;
      if (!cached) exitBulkSelectionMode();
      notifyListeners();
      return;
    }

    _bulkDeleteEligibilityLoading = true;
    notifyListeners();

    var leader = false;
    try {
      for (final tid in teamIds) {
        final resp = await _teamService.getTeamMembers(tid);
        if (!resp.success || resp.data == null) continue;
        for (final m in resp.data!) {
          if (m.memberUserId == userId && m.role.trim() == 'leader') {
            leader = true;
            break;
          }
        }
        if (leader) break;
      }
    } catch (_) {
      leader = false;
    }

    KanbanController._bulkLeaderEligibilityCache[cacheKey] = leader;
    _bulkDeleteEligible = leader;
    _bulkDeleteEligibilityLoading = false;
    if (!leader) exitBulkSelectionMode();
    notifyListeners();
  }

  void exitBulkSelectionMode() {
    if (!_bulkSelectionActive && _bulkSelectedTaskIds.isEmpty) return;
    _bulkSelectionActive = false;
    _bulkSelectedTaskIds.clear();
    notifyListeners();
  }

  void setBulkSelectionActive(bool value) {
    if (_bulkDeleting) return;
    if (value &&
        (!(permissions?.canDeleteTasks ?? false) || !_bulkDeleteEligible)) {
      return;
    }
    if (_bulkSelectionActive == value) return;
    if (!value) {
      _bulkSelectedTaskIds.clear();
    }
    _bulkSelectionActive = value;
    notifyListeners();
  }

  void toggleBulkTaskSelection(String taskId) {
    if (!_bulkSelectionActive || taskId.isEmpty || _bulkDeleting) return;
    if (_bulkSelectedTaskIds.contains(taskId)) {
      _bulkSelectedTaskIds.remove(taskId);
    } else {
      _bulkSelectedTaskIds.add(taskId);
    }
    notifyListeners();
  }

  void clearBulkTaskSelection() {
    if (_bulkSelectedTaskIds.isEmpty) return;
    _bulkSelectedTaskIds.clear();
    notifyListeners();
  }

  /// Seleciona todos os cards do quadro corrente (lista já filtrada pela API).
  void bulkSelectAllCurrentTasks() {
    if (!_bulkSelectionActive || _bulkDeleting) return;
    _bulkSelectedTaskIds
      ..clear()
      ..addAll(tasks.map((t) => t.id));
    notifyListeners();
  }

  /// Exclusão em lote sem recarregar o quadro a cada DELETE.
  ///
  /// Exige a mesma permissão de API que um delete unitário (`canDeleteTasks`);
  /// o modo de seleção na UI permanece atrás de [showBulkSelectionEntry].
  /// Deletes são **sequenciais** para evitar corridas em refresh de token / 401
  /// quando várias requisições terminam ao mesmo tempo.
  Future<bool> bulkDeleteSelectedTasks() async {
    if (!_bulkSelectionActive || _bulkSelectedTaskIds.isEmpty) return false;
    if (!(permissions?.canDeleteTasks ?? false)) {
      _error =
          'Sem permissão para excluir cards. Verifique o perfil no CRM web.';
      notifyListeners();
      return false;
    }

    final ids = _bulkSelectedTaskIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      _error = 'Nenhum id de card válido para excluir.';
      notifyListeners();
      return false;
    }

    _bulkDeleting = true;
    notifyListeners();

    var failures = 0;
    String? lastFailMessage;

    try {
      for (final id in ids) {
        final r = await _kanbanService.deleteTask(id);
        if (!r.success) {
          failures++;
          lastFailMessage = r.message;
        }
      }

      _bulkSelectedTaskIds.clear();
      _bulkSelectionActive = false;

      await loadBoard(teamId: _teamId, projectId: _projectId);
      _bulkDeleting = false;

      if (failures > 0) {
        _error =
            lastFailMessage ?? '$failures exclusão(ões) falhou(ram). Verifique a conexão ou as permissões.';
      } else {
        _error = null;
      }

      notifyListeners();
      return failures == 0;
    } catch (e) {
      _bulkSelectedTaskIds.clear();
      _bulkSelectionActive = false;
      _bulkDeleting = false;

      await loadBoard(teamId: _teamId, projectId: _projectId);

      _error =
          lastFailMessage ?? 'Erro ao excluir em massa: ${e.toString()}';
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
    bool clearError = false,
  }) {
    if (board != null) {
      _board = board;
      // Reseta a paginação por coluna toda vez que o board é recarregado
      // (ex.: troca de funil, refresh manual, recovery de 404). Sem isso,
      // os contadores de página ficavam fora de sincronia com o novo
      // conjunto de cards e o "Carregar mais" duplicava ou parava cedo.
      _resetColumnPagination(board);
    }
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
    _projects = [];
    _kanbanTeams = [];
    _bulkSelectionActive = false;
    _bulkSelectedTaskIds.clear();
    _bulkDeleteEligible = false;
    _bulkDeleteEligibilityLoading = false;
    _bulkBoardContextKey = null;
    _bulkDeleting = false;
    _lastProjectHydrated = false;
    _columnPagination.clear();
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────
  // PAGINAÇÃO POR COLUNA
  // ───────────────────────────────────────────────────────────────────

  /// Inicializa o estado de paginação após `loadBoard` ou refresh.
  ///
  /// Heurística: se uma coluna chegou com **exatamente** `_kColumnPageSize`
  /// cards no board inicial, assumimos que pode haver mais e marcamos
  /// `hasMore = true`. Se chegou com menos, certamente não há mais.
  /// O `totalPages` real só é descoberto após a primeira chamada
  /// paginada — antes disso, deixamos `hasMore` como otimista (true).
  void _resetColumnPagination(KanbanBoard board) {
    _columnPagination.clear();
    final byColumn = <String, int>{};
    for (final t in board.tasks) {
      byColumn.update(t.columnId, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final col in board.columns) {
      final loaded = byColumn[col.id] ?? 0;
      _columnPagination[col.id] = ColumnPagination(
        currentPage: 1,
        loadedCount: loaded,
        // Se chegou exatamente o page size, há chance de ter mais.
        // Se chegou menos, não há mais.
        hasMore: loaded >= _kColumnPageSize,
      );
    }
  }

  /// Status de paginação de uma coluna (UI usa `hasMore` + `loadingMore`
  /// pra renderizar o botão "Carregar mais" e o spinner).
  ColumnPagination columnPaginationFor(String columnId) {
    return _columnPagination[columnId] ??
        ColumnPagination(
          currentPage: 1,
          loadedCount: 0,
          hasMore: false,
        );
  }

  /// Carrega a próxima página de tasks da coluna e adiciona ao board.
  ///
  /// Chama `GET /kanban/columns/:id/tasks?page=N&limit=12` e faz append
  /// dos cards novos em `_board.tasks` (deduplicando por id).
  Future<void> loadMoreTasksForColumn(String columnId) async {
    final state = _columnPagination[columnId];
    if (state == null || !state.hasMore || state.loadingMore) return;
    if (_board == null) return;
    final teamId = _teamId;
    if (teamId == null || teamId.isEmpty) return;

    state.loadingMore = true;
    notifyListeners();

    try {
      final nextPage = state.currentPage + 1;
      final res = await _kanbanService.getColumnTasks(
        columnId: columnId,
        teamId: teamId,
        projectId: _projectId,
        page: nextPage,
        limit: _kColumnPageSize,
      );

      if (res.success && res.data != null) {
        final pageData = res.data!;
        final existingIds =
            _board!.tasks.map((t) => t.id).toSet();
        final newOnes = pageData.tasks
            .where((t) => !existingIds.contains(t.id))
            .toList();
        _board!.tasks.addAll(newOnes);

        state.currentPage = pageData.page;
        state.loadedCount += newOnes.length;
        // `totalPages` confiável vem aqui — atualizamos o `hasMore`.
        state.hasMore = pageData.page < pageData.totalPages;
      } else {
        // Falha na página → marca como sem-mais pra não loopar.
        state.hasMore = false;
      }
    } catch (e) {
      debugPrint('❌ [KANBAN_CTRL] loadMoreTasksForColumn($columnId): $e');
      state.hasMore = false;
    } finally {
      state.loadingMore = false;
      notifyListeners();
    }
  }
}

/// Estado de paginação por coluna do board Kanban.
///
/// Exposto publicamente porque a UI precisa ler `hasMore` e `loadingMore`
/// pra renderizar o botão "Carregar mais" e o spinner inline.
class ColumnPagination {
  int currentPage;
  int loadedCount;
  bool hasMore;
  bool loadingMore = false;

  ColumnPagination({
    required this.currentPage,
    required this.loadedCount,
    required this.hasMore,
  });
}
