/// Modelos de dados do sistema Kanban
library;

import '../../../shared/utils/avatar_url_resolver.dart';

/// Prioridade da tarefa
enum KanbanPriority {
  low,
  medium,
  high,
  urgent;

  String get label {
    switch (this) {
      case KanbanPriority.low:
        return 'Baixa';
      case KanbanPriority.medium:
        return 'Média';
      case KanbanPriority.high:
        return 'Alta';
      case KanbanPriority.urgent:
        return 'Urgente';
    }
  }

  String get color {
    switch (this) {
      case KanbanPriority.low:
        return '#64748B';
      case KanbanPriority.medium:
        return '#3B82F6';
      case KanbanPriority.high:
        return '#F59E0B';
      case KanbanPriority.urgent:
        return '#EF4444';
    }
  }
}

/// Status do projeto
enum KanbanProjectStatus {
  active,
  completed,
  archived,
  cancelled;

  String get label {
    switch (this) {
      case KanbanProjectStatus.active:
        return 'Ativo';
      case KanbanProjectStatus.completed:
        return 'Concluído';
      case KanbanProjectStatus.archived:
        return 'Arquivado';
      case KanbanProjectStatus.cancelled:
        return 'Cancelado';
    }
  }
}

/// Motivos de perda — mesmos valores de `LossReason` no CRM web (`imobx` / `imobx-front`).
enum KanbanLossReason {
  alugouEmOutroLugar('alugou_em_outro_lugar', 'Alugou em outro lugar'),
  aluguel('aluguel', 'Aluguel'),
  atendidoPorOutroCorretor('atendido_por_outro_corretor', 'Atendido p/ outro corretor'),
  clicouErrado('clicou_errado', 'Clicou errado'),
  cliqueDuplicado('clique_duplicado', 'Clique duplicado'),
  clienteEmAtendimentoAtivo('cliente_em_atendimento_ativo', 'Cliente em atendimento ativo'),
  comprouEmOutroLugar('comprou_em_outro_lugar', 'Comprou em outro lugar'),
  curriculo('curriculo', 'Currículo'),
  desistiuDaCaptacao('desistiu_da_captacao', 'Desistiu da captação'),
  desistiuDaCompra('desistiu_da_compra', 'Desistiu da compra'),
  desistiuDeAlugar('desistiu_de_alugar', 'Desistiu de Alugar'),
  fechouComOutroCorretorDaEquipe(
    'fechou_com_outro_corretor_da_equipe',
    'Fechou com Outro Corretor da Equipe',
  ),
  financeiro('financeiro', 'Financeiro'),
  fornecedor('fornecedor', 'Fornecedor'),
  imovelJaCadastrado('imovel_ja_cadastrado', 'Imóvel ja cadastrado'),
  naoConseguiuContatoTelExiste(
    'nao_conseguiu_contato_tel_existe',
    'Não conseguiu contato (tel existe)',
  ),
  naoELead('nao_e_lead', 'Não é lead'),
  naoSeEnquadra('nao_se_enquadra', 'Não se enquadra'),
  parceriaDeNegocios('parceria_de_negocios', 'Parceria de negócios'),
  parouDeResponder('parou_de_responder', 'Parou de responder'),
  restricao('restricao', 'Restrição'),
  semFormaDeContatoTelNaoExiste(
    'sem_forma_de_contato_tel_nao_existe',
    'Sem forma de contato (tel não existe)',
  ),
  semInteresseImovelEmMarilia(
    'sem_interesse_imovel_em_marilia',
    'Sem interesse imóvel em Marília',
  ),
  semInteresse('sem_interesse', 'Sem interesse');

  const KanbanLossReason(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static KanbanLossReason? tryParse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    for (final e in KanbanLossReason.values) {
      if (e.apiValue == s) return e;
    }
    return null;
  }
}

/// Corpo de `POST /kanban/tasks/:id/transfer` — alinhado a `TransferTaskDto` no backend.
class KanbanTransferTaskPayload {
  final String toProjectId;
  final String transferDate;
  final String preService;
  final String? toColumnId;
  final String? assignedToId;
  final String? notes;

  KanbanTransferTaskPayload({
    required this.toProjectId,
    required this.transferDate,
    required this.preService,
    this.toColumnId,
    this.assignedToId,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'toProjectId': toProjectId,
      'transferDate': transferDate,
      'preService': preService,
      if (toColumnId != null && toColumnId!.trim().isNotEmpty)
        'toColumnId': toColumnId,
      if (assignedToId != null && assignedToId!.trim().isNotEmpty)
        'assignedToId': assignedToId,
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    };
  }
}

/// Coluna do Kanban
class KanbanColumn {
  final String id;
  final String title;
  final String? description;
  final String? color;
  final int position;
  final bool isActive;
  final String teamId;
  final String createdById;
  final DateTime createdAt;
  final DateTime updatedAt;

  KanbanColumn({
    required this.id,
    required this.title,
    this.description,
    this.color,
    required this.position,
    required this.isActive,
    required this.teamId,
    required this.createdById,
    required this.createdAt,
    required this.updatedAt,
  });

  factory KanbanColumn.fromJson(Map<String, dynamic> json) {
    return KanbanColumn(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      color: json['color']?.toString(),
      position: json['position'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      teamId: json['teamId']?.toString() ?? '',
      createdById: json['createdById']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'color': color,
      'position': position,
      'isActive': isActive,
      'teamId': teamId,
      'createdById': createdById,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  KanbanColumn copyWith({
    String? id,
    String? title,
    String? description,
    String? color,
    int? position,
    bool? isActive,
    String? teamId,
    String? createdById,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KanbanColumn(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      color: color ?? this.color,
      position: position ?? this.position,
      isActive: isActive ?? this.isActive,
      teamId: teamId ?? this.teamId,
      createdById: createdById ?? this.createdById,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isSyntheticKanbanPlaceholder =>
      id.startsWith(KanbanSyntheticColumns.idPrefix);
}

/// Coluna resumida (`GET /kanban/columns/:teamId/simple?projectId=`) — transferência de card.
class KanbanSimpleColumn {
  final String id;
  final String title;
  final int position;

  const KanbanSimpleColumn({
    required this.id,
    required this.title,
    required this.position,
  });

  factory KanbanSimpleColumn.fromJson(Map<String, dynamic> json) {
    return KanbanSimpleColumn(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      position: json['position'] as int? ?? 0,
    );
  }
}

/// Três etapas padrão (somente UI) quando o backend ainda não devolve colunas —
/// mesmo desenho usado como funil inicial no CRM web.
class KanbanSyntheticColumns {
  KanbanSyntheticColumns._();

  static const String idPrefix = 'kanban_ph_';

  static bool isSynthetic(KanbanColumn column) =>
      column.id.startsWith(idPrefix);

  static bool isSyntheticId(String columnId) =>
      columnId.startsWith(idPrefix);

  static List<KanbanColumn> triple({required String seedTeamKey}) {
    final now = DateTime.now();
    final base = '${seedTeamKey.hashCode.abs()}';
    KanbanColumn one(
      int pos,
      String title,
      String description,
      String colorHex,
    ) {
      return KanbanColumn(
        id: '$idPrefix${base}_$pos',
        title: title,
        description: description,
        color: colorHex,
        position: pos,
        isActive: true,
        teamId: seedTeamKey.isNotEmpty ? seedTeamKey : '—',
        createdById: '',
        createdAt: now,
        updatedAt: now,
      );
    }

    return [
      one(
        0,
        'Novos',
        'Primeiro contato · leads entrando',
        '#3B82F6',
      ),
      one(
        1,
        'Em andamento',
        'Qualificação, visitas e propostas',
        '#F59E0B',
      ),
      one(
        2,
        'Concluídos',
        'Ganhos, perdas arquivadas e follow-up',
        '#10B981',
      ),
    ];
  }
}

/// Remove da interface tags legadas de migração (ex.: importação de sistemas antigos).
abstract final class KanbanUiTagFilter {
  KanbanUiTagFilter._();

  static bool isHidden(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return false;
    if (t.contains('imobzi')) return true;
    if (t.contains('imobiz')) return true;
    return false;
  }

  static List<String> visible(List<String>? tags) {
    if (tags == null || tags.isEmpty) return const [];
    return tags.where((t) => !isHidden(t)).toList();
  }
}

/// Resultado normalizado de uma negociação para filtro/UI.
enum KanbanResultFilter {
  open('open', 'Em aberto'),
  won('won', 'Ganhos'),
  lost('lost', 'Perdidos'),
  cancelled('cancelled', 'Cancelados');

  const KanbanResultFilter(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// Conjunto de filtros do board do Kanban (espelha `KanbanBoardFiltersDto` do
/// backend). Imutável; gera os query params exatos que o board aceita.
class KanbanBoardFilters {
  /// Responsáveis (OR) — query `assignedToIds` (CSV de UUIDs).
  final Set<String> assignedToIds;

  /// Somente leads sem responsável — query `unassigned=true`.
  final bool unassigned;

  /// Tags (OR) — query `tagIds` (CSV de UUIDs).
  final Set<String> tagIds;

  /// Resultado da negociação — query `result`.
  final KanbanResultFilter? result;

  /// Busca textual (título, cliente, telefone…) — query `search`.
  final String? search;

  /// Período de criação — queries `createdAtAfter` / `createdAtBefore`.
  final DateTime? createdAfter;
  final DateTime? createdBefore;

  const KanbanBoardFilters({
    this.assignedToIds = const {},
    this.unassigned = false,
    this.tagIds = const {},
    this.result,
    this.search,
    this.createdAfter,
    this.createdBefore,
  });

  static const empty = KanbanBoardFilters();

  bool get isEmpty =>
      assignedToIds.isEmpty &&
      !unassigned &&
      tagIds.isEmpty &&
      result == null &&
      (search == null || search!.trim().isEmpty) &&
      createdAfter == null &&
      createdBefore == null;

  bool get isNotEmpty => !isEmpty;

  /// Quantidade de filtros ativos (para badges/contadores na UI).
  int get activeCount {
    var n = 0;
    if (assignedToIds.isNotEmpty) n++;
    if (unassigned) n++;
    if (tagIds.isNotEmpty) n++;
    if (result != null) n++;
    if (search != null && search!.trim().isNotEmpty) n++;
    if (createdAfter != null) n++;
    if (createdBefore != null) n++;
    return n;
  }

  KanbanBoardFilters copyWith({
    Set<String>? assignedToIds,
    bool? unassigned,
    Set<String>? tagIds,
    KanbanResultFilter? result,
    bool clearResult = false,
    String? search,
    bool clearSearch = false,
    DateTime? createdAfter,
    bool clearCreatedAfter = false,
    DateTime? createdBefore,
    bool clearCreatedBefore = false,
  }) {
    return KanbanBoardFilters(
      assignedToIds: assignedToIds ?? this.assignedToIds,
      unassigned: unassigned ?? this.unassigned,
      tagIds: tagIds ?? this.tagIds,
      result: clearResult ? null : (result ?? this.result),
      search: clearSearch ? null : (search ?? this.search),
      createdAfter: clearCreatedAfter ? null : (createdAfter ?? this.createdAfter),
      createdBefore:
          clearCreatedBefore ? null : (createdBefore ?? this.createdBefore),
    );
  }

  /// Query params canônicos aceitos por `GET /kanban/board/:teamId`.
  Map<String, String> toQueryParams() {
    final p = <String, String>{};
    if (assignedToIds.isNotEmpty) {
      p['assignedToIds'] = assignedToIds.join(',');
    }
    if (unassigned) p['unassigned'] = 'true';
    if (tagIds.isNotEmpty) p['tagIds'] = tagIds.join(',');
    if (result != null) p['result'] = result!.apiValue;
    final s = search?.trim();
    if (s != null && s.isNotEmpty) p['search'] = s;
    if (createdAfter != null) p['createdAtAfter'] = _ymd(createdAfter!);
    if (createdBefore != null) p['createdAtBefore'] = _ymd(createdBefore!);
    return p;
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Configuração de cadência WhatsApp de uma coluna (espelha
/// `ColumnCadenceConfig` / `UpdateColumnCadenceDto` do backend). Persistida em
/// `kanban_columns.cadenceConfig` e exposta via `GET/PUT /kanban/columns/:id/cadence`.
class KanbanColumnCadenceConfig {
  final bool enabled;

  /// Minutos na coluna antes do 1º envio automático.
  final int sendAfterMinutes;

  /// `official` (template aprovado) | `unofficial` (mensagem livre).
  final String channel;

  /// Mensagem livre — obrigatória quando `channel == unofficial`.
  final String? messageText;

  /// Nome do template — obrigatório quando `channel == official`.
  final String? templateName;
  final String? templateLanguage;
  final List<String> templateBodyParameters;
  final List<String> templateHeaderParameters;

  /// Máximo de envios por ciclo (1 = envia só uma vez).
  final int maxAttempts;

  /// Minutos entre reenvios (quando maxAttempts > 1).
  final int resendIntervalMinutes;

  /// Minutos aguardando resposta após o último envio.
  final int waitReplyMinutes;

  /// `move_column` | `none`.
  final String onNoReplyAction;
  final String? noReplyTargetColumnId;

  /// `stop` | `move_column`.
  final String onReplyAction;
  final String? replyTargetColumnId;

  /// Coluna a que pertence (presente na resposta do GET).
  final String? columnId;

  const KanbanColumnCadenceConfig({
    this.enabled = false,
    this.sendAfterMinutes = 120,
    this.channel = 'official',
    this.messageText = '',
    this.templateName = '',
    this.templateLanguage = 'pt_BR',
    this.templateBodyParameters = const [],
    this.templateHeaderParameters = const [],
    this.maxAttempts = 1,
    this.resendIntervalMinutes = 1440,
    this.waitReplyMinutes = 1440,
    this.onNoReplyAction = 'move_column',
    this.noReplyTargetColumnId,
    this.onReplyAction = 'stop',
    this.replyTargetColumnId,
    this.columnId,
  });

  bool get isOfficial => channel == 'official';

  factory KanbanColumnCadenceConfig.fromJson(Map<String, dynamic> json) {
    List<String> strList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const <String>[];
    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    return KanbanColumnCadenceConfig(
      enabled: json['enabled'] as bool? ?? false,
      sendAfterMinutes: asInt(json['sendAfterMinutes'], 120),
      channel: json['channel']?.toString() ?? 'official',
      messageText: json['messageText']?.toString() ?? '',
      templateName: json['templateName']?.toString() ?? '',
      templateLanguage: json['templateLanguage']?.toString() ?? 'pt_BR',
      templateBodyParameters: strList(json['templateBodyParameters']),
      templateHeaderParameters: strList(json['templateHeaderParameters']),
      maxAttempts: asInt(json['maxAttempts'], 1),
      resendIntervalMinutes: asInt(json['resendIntervalMinutes'], 1440),
      waitReplyMinutes: asInt(json['waitReplyMinutes'], 1440),
      onNoReplyAction: json['onNoReplyAction']?.toString() ?? 'move_column',
      noReplyTargetColumnId: json['noReplyTargetColumnId']?.toString(),
      onReplyAction: json['onReplyAction']?.toString() ?? 'stop',
      replyTargetColumnId: json['replyTargetColumnId']?.toString(),
      columnId: json['columnId']?.toString(),
    );
  }

  /// Payload para o PUT (`UpdateColumnCadenceDto`).
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'sendAfterMinutes': sendAfterMinutes,
      'channel': channel,
      'messageText': messageText ?? '',
      'templateName': templateName ?? '',
      'templateLanguage': templateLanguage ?? 'pt_BR',
      'templateBodyParameters': templateBodyParameters,
      'templateHeaderParameters': templateHeaderParameters,
      'maxAttempts': maxAttempts,
      'resendIntervalMinutes': resendIntervalMinutes,
      'waitReplyMinutes': waitReplyMinutes,
      'onNoReplyAction': onNoReplyAction,
      'noReplyTargetColumnId': noReplyTargetColumnId,
      'onReplyAction': onReplyAction,
      'replyTargetColumnId': replyTargetColumnId,
    };
  }

  KanbanColumnCadenceConfig copyWith({
    bool? enabled,
    int? sendAfterMinutes,
    String? channel,
    String? messageText,
    String? templateName,
    String? templateLanguage,
    List<String>? templateBodyParameters,
    List<String>? templateHeaderParameters,
    int? maxAttempts,
    int? resendIntervalMinutes,
    int? waitReplyMinutes,
    String? onNoReplyAction,
    String? noReplyTargetColumnId,
    bool clearNoReplyTarget = false,
    String? onReplyAction,
    String? replyTargetColumnId,
    bool clearReplyTarget = false,
  }) {
    return KanbanColumnCadenceConfig(
      enabled: enabled ?? this.enabled,
      sendAfterMinutes: sendAfterMinutes ?? this.sendAfterMinutes,
      channel: channel ?? this.channel,
      messageText: messageText ?? this.messageText,
      templateName: templateName ?? this.templateName,
      templateLanguage: templateLanguage ?? this.templateLanguage,
      templateBodyParameters:
          templateBodyParameters ?? this.templateBodyParameters,
      templateHeaderParameters:
          templateHeaderParameters ?? this.templateHeaderParameters,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      resendIntervalMinutes:
          resendIntervalMinutes ?? this.resendIntervalMinutes,
      waitReplyMinutes: waitReplyMinutes ?? this.waitReplyMinutes,
      onNoReplyAction: onNoReplyAction ?? this.onNoReplyAction,
      noReplyTargetColumnId: clearNoReplyTarget
          ? null
          : (noReplyTargetColumnId ?? this.noReplyTargetColumnId),
      onReplyAction: onReplyAction ?? this.onReplyAction,
      replyTargetColumnId: clearReplyTarget
          ? null
          : (replyTargetColumnId ?? this.replyTargetColumnId),
      columnId: columnId,
    );
  }
}

/// Template aprovado do WhatsApp oficial (`GET /whatsapp/templates`).
class WhatsappTemplate {
  final String name;
  final String? language;
  final String? category;
  final String? status;

  const WhatsappTemplate({
    required this.name,
    this.language,
    this.category,
    this.status,
  });

  factory WhatsappTemplate.fromJson(Map<String, dynamic> json) {
    return WhatsappTemplate(
      name: json['name']?.toString() ?? '',
      language: (json['language'] ?? json['languageCode'])?.toString(),
      category: json['category']?.toString(),
      status: json['status']?.toString(),
    );
  }
}

/// Detalhe de uma tag da negociação (espelha `tagDetails` do backend) — traz a
/// cor real configurada na empresa, permitindo colorir o chip igual à web.
class KanbanTagDetail {
  final String id;
  final String name;
  final String? color;
  final String? handle;

  const KanbanTagDetail({
    required this.id,
    required this.name,
    this.color,
    this.handle,
  });

  factory KanbanTagDetail.fromJson(Map<String, dynamic> json) {
    return KanbanTagDetail(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString(),
      handle: json['handle']?.toString(),
    );
  }
}

/// Tarefa do Kanban
class KanbanTask {
  final String id;
  final String title;
  final String? description;
  final String columnId;
  final int position;
  final KanbanPriority? priority;
  final bool isCompleted;
  final String? assignedToId;
  final String createdById;
  final DateTime? dueDate;
  final String? projectId;
  final List<String>? tags;

  /// Tags com cor/handle (preferidas sobre [tags] para renderizar chips).
  final List<KanbanTagDetail>? tagDetails;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Valor total da negociação (R$). Vem no payload do board.
  final double? totalValue;

  /// Cor calculada pelas regras de cor do backend (por tempo no card).
  final String? color;

  /// Cor manual definida no card — tem prioridade sobre [color] e regras.
  final String? cardColor;

  /// Quantas vezes o lead já foi marcado como perdido (recuperação).
  final int? lossMarkCount;

  /// Lead está no pool de recuperação de perdidos.
  final bool? inRecoveryPool;

  /// Cadência WhatsApp ativa na coluna atual do card.
  final bool? cadenceEnabled;

  /// Tentativas de cadência já enviadas no ciclo atual da coluna.
  final int? cadenceAttemptCount;

  /// Máximo de tentativas configurado na coluna (quando a cadência está ativa).
  final int? cadenceMaxAttempts;

  /// Cadência aguardando resposta do lead após o último envio.
  final bool? cadenceAwaitingReply;

  /// `open` | `won` | `lost` | `cancelled` — ausente ou vazio equivale a em aberto.
  final String? result;
  final String? lossReason;
  final String? resultNotes;
  final String? preService;
  final DateTime? transferDate;

  // Relacionamentos populados
  final KanbanUser? assignedTo;
  final KanbanUser? createdBy;
  final KanbanProject? project;
  final int? commentsCount;
  final List<KanbanTaskContactInput>? contacts;

  /// Cliente/lead vinculado à negociação (populado em
  /// `GET /kanban/tasks/:id/fields`). A listagem das colunas não traz o
  /// telefone, por isso o detalhe recarrega os campos completos.
  final String? clientId;
  final KanbanTaskClient? client;

  KanbanTask({
    required this.id,
    required this.title,
    this.description,
    required this.columnId,
    required this.position,
    this.priority,
    required this.isCompleted,
    this.assignedToId,
    required this.createdById,
    this.dueDate,
    this.projectId,
    this.tags,
    this.tagDetails,
    required this.createdAt,
    required this.updatedAt,
    this.totalValue,
    this.color,
    this.cardColor,
    this.lossMarkCount,
    this.inRecoveryPool,
    this.cadenceEnabled,
    this.cadenceAttemptCount,
    this.cadenceMaxAttempts,
    this.cadenceAwaitingReply,
    this.result,
    this.lossReason,
    this.resultNotes,
    this.preService,
    this.transferDate,
    this.assignedTo,
    this.createdBy,
    this.project,
    this.commentsCount,
    this.contacts,
    this.clientId,
    this.client,
  });

  /// Resultado normalizado para regras de UI (igual ao web).
  String get normalizedResult {
    final r = result?.trim().toLowerCase();
    if (r == null || r.isEmpty) return 'open';
    return r;
  }

  bool get hasClosedResult {
    final r = normalizedResult;
    return r == 'won' || r == 'lost' || r == 'cancelled';
  }

  /// Tags exibíveis nos cards e modais (sem marcadores ocultados por [KanbanUiTagFilter]).
  List<String>? get displayTags {
    final list = KanbanUiTagFilter.visible(tags);
    if (list.isEmpty) return null;
    return list;
  }

  /// Tags com cor para os chips do card (sem as ocultas). Prefira sobre
  /// [displayTags] quando o backend enviar `tagDetails`.
  List<KanbanTagDetail>? get displayTagDetails {
    final src = tagDetails;
    if (src == null || src.isEmpty) return null;
    final list =
        src.where((t) => !KanbanUiTagFilter.isHidden(t.name)).toList();
    if (list.isEmpty) return null;
    return list;
  }

  /// Melhor telefone para contato rápido do lead: WhatsApp do cliente,
  /// senão telefone do cliente, senão o 1º contato com telefone.
  String? get contactWhatsapp {
    final w = client?.whatsapp?.trim();
    if (w != null && w.isNotEmpty) return w;
    return contactPhone;
  }

  String? get contactPhone {
    final p = client?.phone?.trim();
    if (p != null && p.isNotEmpty) return p;
    final fromContacts = contacts
        ?.map((c) => c.phone?.trim())
        .firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null);
    return fromContacts;
  }

  /// Está em recuperação de lead perdido?
  bool get isInRecovery =>
      (inRecoveryPool ?? false) || ((lossMarkCount ?? 0) > 0);

  /// Há cadência ativa para exibir indicador no card?
  bool get hasCadence => cadenceEnabled == true;

  factory KanbanTask.fromJson(Map<String, dynamic> json) {
    return KanbanTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      columnId: json['columnId']?.toString() ?? '',
      position: json['position'] as int? ?? 0,
      priority: json['priority'] != null
          ? _parsePriority(json['priority'].toString())
          : null,
      isCompleted: json['isCompleted'] as bool? ?? false,
      assignedToId: json['assignedToId']?.toString(),
      createdById: json['createdById']?.toString() ?? '',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'].toString())
          : null,
      projectId: json['projectId']?.toString(),
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : null,
      tagDetails: json['tagDetails'] is List
          ? (json['tagDetails'] as List)
              .whereType<Map>()
              .map(
                (e) => KanbanTagDetail.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
          : null,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      totalValue: json['totalValue'] != null
          ? (json['totalValue'] as num).toDouble()
          : null,
      color: json['color']?.toString(),
      cardColor: json['cardColor']?.toString(),
      lossMarkCount: json['lossMarkCount'] as int?,
      inRecoveryPool: json['inRecoveryPool'] as bool?,
      cadenceEnabled: json['cadenceEnabled'] as bool?,
      cadenceAttemptCount: json['cadenceAttemptCount'] as int?,
      cadenceMaxAttempts: json['cadenceMaxAttempts'] as int?,
      cadenceAwaitingReply: json['cadenceAwaitingReply'] as bool?,
      result: json['result']?.toString(),
      lossReason: json['lossReason']?.toString(),
      resultNotes: json['resultNotes']?.toString(),
      preService: json['preService']?.toString(),
      transferDate: json['transferDate'] != null
          ? DateTime.tryParse(json['transferDate'].toString())
          : null,
      assignedTo: json['assignedTo'] != null
          ? KanbanUser.fromJson(json['assignedTo'] as Map<String, dynamic>)
          : null,
      createdBy: json['createdBy'] != null
          ? KanbanUser.fromJson(json['createdBy'] as Map<String, dynamic>)
          : null,
      project: json['project'] != null
          ? KanbanProject.fromJson(json['project'] as Map<String, dynamic>)
          : null,
      commentsCount: json['commentsCount'] as int?,
      clientId: json['clientId']?.toString(),
      client: json['client'] is Map
          ? KanbanTaskClient.fromJson(
              Map<String, dynamic>.from(json['client'] as Map),
            )
          : null,
      contacts: json['contacts'] is List
          ? (json['contacts'] as List)
              .whereType<Map>()
              .map(
                (e) => KanbanTaskContactInput.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'columnId': columnId,
      'position': position,
      'priority': priority?.name,
      'isCompleted': isCompleted,
      'assignedToId': assignedToId,
      'createdById': createdById,
      'dueDate': dueDate?.toIso8601String(),
      'projectId': projectId,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (result != null) 'result': result,
      if (lossReason != null) 'lossReason': lossReason,
      if (resultNotes != null) 'resultNotes': resultNotes,
      if (preService != null) 'preService': preService,
      if (transferDate != null) 'transferDate': transferDate!.toIso8601String(),
    };
  }

  KanbanTask copyWith({
    String? id,
    String? title,
    String? description,
    String? columnId,
    int? position,
    KanbanPriority? priority,
    bool? isCompleted,
    String? assignedToId,
    String? createdById,
    DateTime? dueDate,
    String? projectId,
    List<String>? tags,
    List<KanbanTagDetail>? tagDetails,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? totalValue,
    String? color,
    String? cardColor,
    int? lossMarkCount,
    bool? inRecoveryPool,
    bool? cadenceEnabled,
    int? cadenceAttemptCount,
    int? cadenceMaxAttempts,
    bool? cadenceAwaitingReply,
    String? result,
    String? lossReason,
    String? resultNotes,
    String? preService,
    DateTime? transferDate,
    KanbanUser? assignedTo,
    KanbanUser? createdBy,
    KanbanProject? project,
    int? commentsCount,
    List<KanbanTaskContactInput>? contacts,
    String? clientId,
    KanbanTaskClient? client,
  }) {
    return KanbanTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      columnId: columnId ?? this.columnId,
      position: position ?? this.position,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      assignedToId: assignedToId ?? this.assignedToId,
      createdById: createdById ?? this.createdById,
      dueDate: dueDate ?? this.dueDate,
      projectId: projectId ?? this.projectId,
      tags: tags ?? this.tags,
      tagDetails: tagDetails ?? this.tagDetails,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalValue: totalValue ?? this.totalValue,
      color: color ?? this.color,
      cardColor: cardColor ?? this.cardColor,
      lossMarkCount: lossMarkCount ?? this.lossMarkCount,
      inRecoveryPool: inRecoveryPool ?? this.inRecoveryPool,
      cadenceEnabled: cadenceEnabled ?? this.cadenceEnabled,
      cadenceAttemptCount: cadenceAttemptCount ?? this.cadenceAttemptCount,
      cadenceMaxAttempts: cadenceMaxAttempts ?? this.cadenceMaxAttempts,
      cadenceAwaitingReply: cadenceAwaitingReply ?? this.cadenceAwaitingReply,
      result: result ?? this.result,
      lossReason: lossReason ?? this.lossReason,
      resultNotes: resultNotes ?? this.resultNotes,
      preService: preService ?? this.preService,
      transferDate: transferDate ?? this.transferDate,
      assignedTo: assignedTo ?? this.assignedTo,
      createdBy: createdBy ?? this.createdBy,
      project: project ?? this.project,
      commentsCount: commentsCount ?? this.commentsCount,
      contacts: contacts ?? this.contacts,
      clientId: clientId ?? this.clientId,
      client: client ?? this.client,
    );
  }

  static KanbanPriority _parsePriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return KanbanPriority.urgent;
      case 'high':
        return KanbanPriority.high;
      case 'medium':
        return KanbanPriority.medium;
      case 'low':
      default:
        return KanbanPriority.low;
    }
  }
}

/// Cliente/lead vinculado à negociação, populado em
/// `GET /kanban/tasks/:id/fields`. Espelha `KanbanTaskClient` do front web.
class KanbanTaskClient {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? whatsapp;
  final String? secondaryPhone;
  final String? cpf;

  /// `buyer` | `seller` | `tenant`/`renter` | `landlord`/`lessor` | `investor` | ...
  final String? type;

  /// `active` | `inactive` | `contacted` | `interested` | `closed` | ...
  final String? status;
  final String? city;

  const KanbanTaskClient({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.whatsapp,
    this.secondaryPhone,
    this.cpf,
    this.type,
    this.status,
    this.city,
  });

  factory KanbanTaskClient.fromJson(Map<String, dynamic> json) {
    return KanbanTaskClient(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
      secondaryPhone: json['secondaryPhone']?.toString(),
      cpf: json['cpf']?.toString(),
      type: json['type']?.toString(),
      status: json['status']?.toString(),
      city: json['city']?.toString(),
    );
  }

  /// Primeiro número de contato disponível (telefone → whatsapp → secundário).
  String? get primaryPhone {
    for (final p in [phone, whatsapp, secondaryPhone]) {
      if (p != null && p.trim().isNotEmpty) return p.trim();
    }
    return null;
  }
}

/// Projeto do Kanban
class KanbanProject {
  final String id;
  final String name;
  final String? description;
  final KanbanProjectStatus status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String? completedById;
  final String teamId;
  final String createdById;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int taskCount;
  final int? completedTaskCount;
  final bool? isPersonal;
  final double? progress;
  final KanbanUser? createdBy;
  final KanbanUser? completedBy;
  /// Equipes extras do funil (multi-equipe), quando a API envia `teamIds` — mesmo critério do web.
  final List<String>? teamIds;

  KanbanProject({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    this.startDate,
    this.dueDate,
    this.completedAt,
    this.completedById,
    required this.teamId,
    required this.createdById,
    required this.createdAt,
    required this.updatedAt,
    required this.taskCount,
    this.completedTaskCount,
    this.isPersonal,
    this.progress,
    this.createdBy,
    this.completedBy,
    this.teamIds,
  });

  factory KanbanProject.fromJson(Map<String, dynamic> json) {
    return KanbanProject(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      status: _parseStatus(json['status']?.toString() ?? 'active'),
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'].toString())
          : null,
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'].toString())
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'].toString())
          : null,
      completedById: json['completedById']?.toString(),
      teamId: json['teamId']?.toString() ?? '',
      createdById: json['createdById']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      taskCount: json['taskCount'] as int? ?? 0,
      completedTaskCount: json['completedTaskCount'] as int?,
      isPersonal: json['isPersonal'] as bool?,
      progress: (json['progress'] as num?)?.toDouble(),
      createdBy: json['createdBy'] != null
          ? KanbanUser.fromJson(json['createdBy'] as Map<String, dynamic>)
          : null,
      completedBy: json['completedBy'] != null
          ? KanbanUser.fromJson(json['completedBy'] as Map<String, dynamic>)
          : null,
      teamIds: json['teamIds'] != null
          ? List<String>.from(
              (json['teamIds'] as List).map((e) => e.toString()),
            )
          : null,
    );
  }

  static KanbanProjectStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return KanbanProjectStatus.completed;
      case 'archived':
        return KanbanProjectStatus.archived;
      case 'cancelled':
        return KanbanProjectStatus.cancelled;
      case 'active':
      default:
        return KanbanProjectStatus.active;
    }
  }
}

/// Usuário do Kanban
class KanbanUser {
  final String id;
  final String name;
  final String email;
  final String? avatar;

  KanbanUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
  });

  factory KanbanUser.fromJson(Map<String, dynamic> json) {
    return KanbanUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatar: AvatarUrlResolver.resolve(json['avatar']?.toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      if (avatar != null) 'avatar': avatar,
    };
  }
}

/// Permissões do Kanban
class KanbanPermissions {
  final bool canCreateTasks;
  final bool canEditTasks;
  final bool canDeleteTasks;
  final bool canMoveTasks;
  final bool canCreateColumns;
  final bool canEditColumns;
  final bool canDeleteColumns;
  final bool canMarkResult;
  final bool canTransfer;

  KanbanPermissions({
    required this.canCreateTasks,
    required this.canEditTasks,
    required this.canDeleteTasks,
    required this.canMoveTasks,
    required this.canCreateColumns,
    required this.canEditColumns,
    required this.canDeleteColumns,
    required this.canMarkResult,
    required this.canTransfer,
  });

  factory KanbanPermissions.fromJson(Map<String, dynamic> json) {
    final canEdit = json['canEditTasks'] as bool? ?? false;
    return KanbanPermissions(
      canCreateTasks: json['canCreateTasks'] as bool? ?? false,
      canEditTasks: canEdit,
      canDeleteTasks: json['canDeleteTasks'] as bool? ?? false,
      canMoveTasks: json['canMoveTasks'] as bool? ?? false,
      canCreateColumns: json['canCreateColumns'] as bool? ?? false,
      canEditColumns: json['canEditColumns'] as bool? ?? false,
      canDeleteColumns: json['canDeleteColumns'] as bool? ?? false,
      canMarkResult: json['canMarkResult'] as bool? ?? canEdit,
      canTransfer: json['canTransfer'] as bool? ?? canEdit,
    );
  }
}

/// Quadro Kanban completo
class KanbanBoard {
  final List<KanbanColumn> columns;
  final List<KanbanTask> tasks;
  final List<KanbanProject>? projects;
  final KanbanPermissions? permissions;
  final KanbanTeam? team;

  KanbanBoard({
    required this.columns,
    required this.tasks,
    this.projects,
    this.permissions,
    this.team,
  });

  factory KanbanBoard.fromJson(Map<String, dynamic> json) {
    return KanbanBoard(
      columns: (json['columns'] as List<dynamic>?)
              ?.map((e) => KanbanColumn.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tasks: (json['tasks'] as List<dynamic>?)
              ?.map((e) => KanbanTask.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      projects: json['projects'] != null
          ? (json['projects'] as List<dynamic>)
              .map((e) => KanbanProject.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      permissions: json['permissions'] != null
          ? KanbanPermissions.fromJson(
              json['permissions'] as Map<String, dynamic>)
          : null,
      team: json['team'] != null
          ? KanbanTeam.fromJson(json['team'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Página de tasks de uma coluna específica.
///
/// Resposta de `GET /kanban/columns/:columnId/tasks?page=N&limit=M`.
/// Usado para o "Carregar mais" cards dentro de uma coluna do board.
class KanbanColumnTasksPage {
  final List<KanbanTask> tasks;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  KanbanColumnTasksPage({
    required this.tasks,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory KanbanColumnTasksPage.fromJson(Map<String, dynamic> json) {
    final rawTasks = (json['data'] as List<dynamic>?) ?? const [];
    return KanbanColumnTasksPage(
      tasks: rawTasks
          .map((e) => KanbanTask.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? rawTasks.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? rawTasks.length,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
    );
  }

  bool get hasMore => page < totalPages;
}

/// Equipe do Kanban
class KanbanTeam {
  final String id;
  final String name;

  KanbanTeam({
    required this.id,
    required this.name,
  });

  factory KanbanTeam.fromJson(Map<String, dynamic> json) {
    return KanbanTeam(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

/// Item de GET `/kanban/my-boards`: funil (quadro por equipe) com permissões resolvidas.
class KanbanAccessibleFunnelSlot {
  final String teamId;
  final KanbanTeam team;
  final KanbanPermissions? permissions;

  KanbanAccessibleFunnelSlot({
    required this.teamId,
    required this.team,
    this.permissions,
  });

  factory KanbanAccessibleFunnelSlot.fromJson(Map<String, dynamic> json) {
    final teamRaw = json['team'];
    KanbanTeam team;
    if (teamRaw is Map<String, dynamic>) {
      team = KanbanTeam.fromJson(teamRaw);
    } else {
      team = KanbanTeam(id: '', name: '');
    }
    final tid = (json['teamId']?.toString().isNotEmpty == true)
        ? json['teamId'].toString()
        : team.id;
    return KanbanAccessibleFunnelSlot(
      teamId: tid,
      team: KanbanTeam(
        id: team.id.isNotEmpty ? team.id : tid,
        name: team.name,
      ),
      permissions: json['permissions'] is Map<String, dynamic>
          ? KanbanPermissions.fromJson(
              json['permissions'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// Página paginada de `/kanban/my-boards`.
class KanbanMyBoardsPageDto {
  final List<KanbanAccessibleFunnelSlot> boards;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  KanbanMyBoardsPageDto({
    required this.boards,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory KanbanMyBoardsPageDto.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    final list = raw is List
        ? raw
            .map(
              (e) => KanbanAccessibleFunnelSlot.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList()
        : <KanbanAccessibleFunnelSlot>[];
    return KanbanMyBoardsPageDto(
      boards: list,
      total: (json['total'] as num?)?.toInt() ?? list.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
      totalPages: (json['totalPages'] as num?)?.toInt() ??
          (list.isEmpty ? 1 : 1),
    );
  }
}

/// Cliente disponível para vincular a uma negociação (`GET /kanban/projects/:id/clients`).
class KanbanProjectLinkedClient {
  final String id;
  final String name;
  final String? email;
  final String? phone;

  KanbanProjectLinkedClient({
    required this.id,
    required this.name,
    this.email,
    this.phone,
  });

  factory KanbanProjectLinkedClient.fromJson(Map<String, dynamic> json) {
    return KanbanProjectLinkedClient(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
    );
  }
}

/// Imóvel disponível para vincular (`GET /kanban/projects/:id/properties`).
class KanbanProjectLinkedProperty {
  final String id;
  final String title;
  final String? code;
  final String? city;

  KanbanProjectLinkedProperty({
    required this.id,
    required this.title,
    this.code,
    this.city,
  });

  factory KanbanProjectLinkedProperty.fromJson(Map<String, dynamic> json) {
    final title =
        json['title']?.toString() ?? json['name']?.toString() ?? '';
    return KanbanProjectLinkedProperty(
      id: json['id']?.toString() ?? '',
      title: title,
      code: json['code']?.toString(),
      city: json['city']?.toString(),
    );
  }
}

/// Contato da negociação (payload de criação — paridade com `KanbanTaskContactDto` do backend).
class KanbanTaskContactInput {
  String? name;
  String? phone;
  String? email;
  String? jobTitle;
  String? birthDate;

  KanbanTaskContactInput({
    this.name,
    this.phone,
    this.email,
    this.jobTitle,
    this.birthDate,
  });

  factory KanbanTaskContactInput.fromJson(Map<String, dynamic> json) {
    return KanbanTaskContactInput(
      name: json['name']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      jobTitle: json['jobTitle']?.toString() ?? json['role']?.toString(),
      birthDate: json['birthDate']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (name != null && name!.trim().isNotEmpty) {
      m['name'] = name!.trim();
    }
    if (phone != null && phone!.trim().isNotEmpty) {
      m['phone'] = phone!.trim();
    }
    if (email != null && email!.trim().isNotEmpty) {
      m['email'] = email!.trim();
    }
    if (jobTitle != null && jobTitle!.trim().isNotEmpty) {
      m['jobTitle'] = jobTitle!.trim();
    }
    if (birthDate != null && birthDate!.trim().isNotEmpty) {
      m['birthDate'] = birthDate!.trim();
    }
    return m;
  }

  bool get hasAny =>
      (name != null && name!.trim().isNotEmpty) ||
      (phone != null && phone!.trim().isNotEmpty) ||
      (email != null && email!.trim().isNotEmpty) ||
      (jobTitle != null && jobTitle!.trim().isNotEmpty) ||
      (birthDate != null && birthDate!.trim().isNotEmpty);
}

/// DTOs para criação/atualização

class CreateColumnDto {
  final String title;
  final String? description;
  final String? color;
  final String teamId;

  CreateColumnDto({
    required this.title,
    this.description,
    this.color,
    required this.teamId,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (description != null) 'description': description,
      if (color != null) 'color': color,
      'teamId': teamId,
    };
  }
}

class UpdateColumnDto {
  final String? title;
  final String? description;
  final String? color;
  final int? position;

  UpdateColumnDto({
    this.title,
    this.description,
    this.color,
    this.position,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (description != null) map['description'] = description;
    if (color != null) map['color'] = color;
    if (position != null) map['position'] = position;
    return map;
  }
}

class CreateTaskDto {
  final String title;
  final String? description;
  final String columnId;
  final KanbanPriority? priority;
  final String? assignedToId;
  final DateTime? dueDate;
  final String? projectId;
  /// IDs de tags (UUID) — ver `CreateKanbanTaskDto.tagIds` no backend.
  final List<String>? tagIds;
  final double? totalValue;
  final String? clientId;
  final String? propertyId;
  final String? source;
  final String? mediaSource;
  final String? campaign;
  final String? metaCampaignId;
  final String? systemCampaignId;
  final String? metaFormId;
  final String? internalNotes;
  final List<KanbanTaskContactInput>? contacts;

  CreateTaskDto({
    required this.title,
    this.description,
    required this.columnId,
    this.priority,
    this.assignedToId,
    this.dueDate,
    this.projectId,
    this.tagIds,
    this.totalValue,
    this.clientId,
    this.propertyId,
    this.source,
    this.mediaSource,
    this.campaign,
    this.metaCampaignId,
    this.systemCampaignId,
    this.metaFormId,
    this.internalNotes,
    this.contacts,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'title': title,
      'columnId': columnId,
    };

    if (description != null && description!.trim().isNotEmpty) {
      json['description'] = description!.trim();
    }

    if (priority != null) {
      json['priority'] = priority!.name;
    }

    if (assignedToId != null && assignedToId!.trim().isNotEmpty) {
      json['assignedToId'] = assignedToId!.trim();
    }

    if (dueDate != null) {
      final utcDate = DateTime.utc(
        dueDate!.year,
        dueDate!.month,
        dueDate!.day,
        0,
        0,
        0,
      );
      json['dueDate'] = utcDate.toIso8601String();
    }

    if (projectId != null &&
        projectId!.isNotEmpty &&
        projectId!.trim().isNotEmpty) {
      json['projectId'] = projectId!.trim();
    }

    if (tagIds != null && tagIds!.isNotEmpty) {
      json['tagIds'] = tagIds;
    }

    if (totalValue != null) {
      json['totalValue'] = totalValue;
    }

    if (clientId != null && clientId!.trim().isNotEmpty) {
      json['clientId'] = clientId!.trim();
    }

    if (propertyId != null && propertyId!.trim().isNotEmpty) {
      json['propertyId'] = propertyId!.trim();
    }

    if (source != null && source!.trim().isNotEmpty) {
      json['source'] = source!.trim();
    }

    if (mediaSource != null && mediaSource!.trim().isNotEmpty) {
      json['mediaSource'] = mediaSource!.trim();
    }

    if (campaign != null && campaign!.trim().isNotEmpty) {
      json['campaign'] = campaign!.trim();
    }

    if (metaCampaignId != null && metaCampaignId!.trim().isNotEmpty) {
      json['metaCampaignId'] = metaCampaignId!.trim();
    }

    if (systemCampaignId != null && systemCampaignId!.trim().isNotEmpty) {
      json['systemCampaignId'] = systemCampaignId!.trim();
    }

    if (metaFormId != null && metaFormId!.trim().isNotEmpty) {
      json['metaFormId'] = metaFormId!.trim();
    }

    if (internalNotes != null && internalNotes!.trim().isNotEmpty) {
      json['internalNotes'] = internalNotes!.trim();
    }

    if (contacts != null && contacts!.isNotEmpty) {
      final list = contacts!
          .where((c) => c.hasAny)
          .map((c) => c.toJson())
          .where((m) => m.isNotEmpty)
          .toList();
      if (list.isNotEmpty) {
        json['contacts'] = list;
      }
    }

    return json;
  }
}

class UpdateTaskDto {
  final String? title;
  final String? description;
  final String? columnId;
  final int? position;
  final String? priority;
  final String? assignedToId;
  final DateTime? dueDate;
  final String? projectId;
  final List<String>? tags;

  UpdateTaskDto({
    this.title,
    this.description,
    this.columnId,
    this.position,
    this.priority,
    this.assignedToId,
    this.dueDate,
    this.projectId,
    this.tags,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (description != null) map['description'] = description;
    if (columnId != null) map['columnId'] = columnId;
    if (position != null) map['position'] = position;
    if (priority != null) map['priority'] = priority;
    // assignedToId é obrigatório - sempre enviar (não pode ser null)
    if (assignedToId != null && assignedToId!.isNotEmpty) {
      map['assignedToId'] = assignedToId;
    }
    if (dueDate != null) {
      // Formatar como YYYY-MM-DDTHH:MM:SS.000Z (meia-noite UTC)
      final utcDate = DateTime.utc(
        dueDate!.year,
        dueDate!.month,
        dueDate!.day,
      );
      map['dueDate'] = utcDate.toIso8601String();
    }
    if (projectId != null) map['projectId'] = projectId;
    // Tags: enviar array vazio se null, ou a lista se tiver valores
    map['tags'] = tags ?? [];
    return map;
  }
}

class MoveTaskDto {
  final String taskId;
  /// Coluna de origem (atual) da tarefa antes do drop. O backend valida
  /// (`MoveTaskDto.fromColumnId @IsUUID`) e retorna 400 se ausente ou se não
  /// corresponder à `task.columnId` no servidor.
  final String fromColumnId;
  final String targetColumnId;
  final int targetPosition;

  MoveTaskDto({
    required this.taskId,
    required this.fromColumnId,
    required this.targetColumnId,
    required this.targetPosition,
  });

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'fromColumnId': fromColumnId,
      'targetColumnId': targetColumnId,
      'targetPosition': targetPosition,
    };
  }
}

/// Comentário de tarefa
/// Anexo de comentário
class Attachment {
  final String id;
  final String filename;
  final String url;
  final int size;
  final String mimeType;
  final DateTime uploadedAt;

  Attachment({
    required this.id,
    required this.filename,
    required this.url,
    required this.size,
    required this.mimeType,
    required this.uploadedAt,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      size: json['size'] as int? ?? 0,
      mimeType: json['mimeType']?.toString() ?? '',
      uploadedAt: DateTime.parse(json['uploadedAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'url': url,
      'size': size,
      'mimeType': mimeType,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }
}

/// Membro de Projeto (Team Member)
class ProjectMember {
  final String id;
  final String role; // 'member' | 'leader'
  final bool isActive;
  final DateTime createdAt;
  final KanbanUser user;

  ProjectMember({
    required this.id,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.user,
  });

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    return ProjectMember(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'member',
      isActive: json['isActive'] == true,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      user: KanbanUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'user': user.toJson(),
    };
  }

  bool get isLeader => role == 'leader';
}

/// Comentário de tarefa
class KanbanTaskComment {
  final String id;
  final String taskId;
  final String userId;
  final String message;
  final List<Attachment> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Relacionamentos populados
  final KanbanUser? user;

  KanbanTaskComment({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.message,
    required this.attachments,
    required this.createdAt,
    required this.updatedAt,
    this.user,
  });

  factory KanbanTaskComment.fromJson(Map<String, dynamic> json) {
    return KanbanTaskComment(
      id: json['id']?.toString() ?? '',
      taskId: json['taskId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      attachments: json['attachments'] != null
          ? (json['attachments'] as List)
              .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      user: json['user'] != null
          ? KanbanUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'userId': userId,
      'message': message,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Entrada de histórico
class HistoryEntry {
  final String id;
  final String action;
  final KanbanUser? user;
  final HistoryColumn? fromColumn;
  final HistoryColumn? toColumn;
  final String? oldValue;
  final String? newValue;
  final String? description;
  final String? field;
  final String? fieldLabel;
  final DateTime createdAt;

  HistoryEntry({
    required this.id,
    required this.action,
    this.user,
    this.fromColumn,
    this.toColumn,
    this.oldValue,
    this.newValue,
    this.description,
    this.field,
    this.fieldLabel,
    required this.createdAt,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      user: json['user'] != null
          ? KanbanUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      fromColumn: json['fromColumn'] != null
          ? HistoryColumn.fromJson(json['fromColumn'] as Map<String, dynamic>)
          : null,
      toColumn: json['toColumn'] != null
          ? HistoryColumn.fromJson(json['toColumn'] as Map<String, dynamic>)
          : null,
      oldValue: json['oldValue']?.toString(),
      newValue: json['newValue']?.toString(),
      description: json['description']?.toString(),
      field: json['field']?.toString(),
      fieldLabel: json['fieldLabel']?.toString(),
      createdAt: DateTime.parse(json['createdAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action,
      'user': user?.toJson(),
      'fromColumn': fromColumn?.toJson(),
      'toColumn': toColumn?.toJson(),
      'oldValue': oldValue,
      'newValue': newValue,
      'description': description,
      'field': field,
      'fieldLabel': fieldLabel,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// Coluna para histórico (versão simplificada)
class HistoryColumn {
  final String id;
  final String title;
  final String color;

  HistoryColumn({
    required this.id,
    required this.title,
    required this.color,
  });

  factory HistoryColumn.fromJson(Map<String, dynamic> json) {
    return HistoryColumn(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'color': color,
    };
  }
}

/// DTO para criar comentário (não usado - usa FormData diretamente)
/// O comentário é criado via FormData com 'message' e 'files'

/// DTO para criar projeto Kanban
class CreateKanbanProjectDto {
  final String name;
  final String? description;
  final String teamId;
  final String? startDate;
  final String? dueDate;

  CreateKanbanProjectDto({
    required this.name,
    this.description,
    required this.teamId,
    this.startDate,
    this.dueDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'teamId': teamId,
      if (startDate != null) 'startDate': startDate,
      if (dueDate != null) 'dueDate': dueDate,
    };
  }
}

/// DTO para atualizar projeto Kanban
class UpdateKanbanProjectDto {
  final String? name;
  final String? description;
  final String? status;
  final String? startDate;
  final String? dueDate;

  UpdateKanbanProjectDto({
    this.name,
    this.description,
    this.status,
    this.startDate,
    this.dueDate,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (name != null) map['name'] = name;
    if (description != null) map['description'] = description;
    if (status != null) map['status'] = status;
    if (startDate != null) map['startDate'] = startDate;
    if (dueDate != null) map['dueDate'] = dueDate;
    return map;
  }
}

