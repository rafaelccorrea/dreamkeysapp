// Modelos do módulo de Tickets/Suporte — espelham `types/tickets.ts` do
// imobx-front e as entities do microserviço `intellisys-tickets`. O app
// consome a API via proxy do core (`/tickets-proxy/*`).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

String? _toStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

/// Status do ticket (1:1 com `TicketStatus` do backend).
enum TicketStatus {
  open,
  inProgress,
  waiting,
  resolved,
  closed,
  unknown;

  static TicketStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'open':
        return TicketStatus.open;
      case 'in_progress':
        return TicketStatus.inProgress;
      case 'waiting':
        return TicketStatus.waiting;
      case 'resolved':
        return TicketStatus.resolved;
      case 'closed':
        return TicketStatus.closed;
      default:
        return TicketStatus.unknown;
    }
  }

  String get apiValue {
    switch (this) {
      case TicketStatus.open:
        return 'open';
      case TicketStatus.inProgress:
        return 'in_progress';
      case TicketStatus.waiting:
        return 'waiting';
      case TicketStatus.resolved:
        return 'resolved';
      case TicketStatus.closed:
        return 'closed';
      case TicketStatus.unknown:
        return 'open';
    }
  }

  String get label {
    switch (this) {
      case TicketStatus.open:
        return 'Aberto';
      case TicketStatus.inProgress:
        return 'Em andamento';
      case TicketStatus.waiting:
        return 'Aguardando você';
      case TicketStatus.resolved:
        return 'Resolvido';
      case TicketStatus.closed:
        return 'Fechado';
      case TicketStatus.unknown:
        return 'Ticket';
    }
  }

  /// Ainda em atendimento (aparece na aba "Ativos").
  bool get isActive =>
      this == TicketStatus.open || this == TicketStatus.inProgress;

  /// Encerrado (resolvido ou fechado).
  bool get isFinished =>
      this == TicketStatus.resolved || this == TicketStatus.closed;
}

/// Cor semântica do status — verde = resolvido, âmbar = esperando o
/// solicitante, azul = em andamento, neutro = fechado.
Color ticketStatusColor(BuildContext context, TicketStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case TicketStatus.open:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case TicketStatus.inProgress:
      return isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    case TicketStatus.waiting:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case TicketStatus.resolved:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case TicketStatus.closed:
    case TicketStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData ticketStatusIcon(TicketStatus status) {
  switch (status) {
    case TicketStatus.open:
      return LucideIcons.inbox;
    case TicketStatus.inProgress:
      return LucideIcons.wrench;
    case TicketStatus.waiting:
      return LucideIcons.clock3;
    case TicketStatus.resolved:
      return LucideIcons.circleCheckBig;
    case TicketStatus.closed:
      return LucideIcons.archive;
    case TicketStatus.unknown:
      return LucideIcons.ticket;
  }
}

/// Prioridade do ticket — definida pela equipe de tecnologia, não pelo
/// solicitante (o app só exibe).
enum TicketPriority {
  low,
  medium,
  high,
  urgent;

  static TicketPriority fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'low':
        return TicketPriority.low;
      case 'high':
        return TicketPriority.high;
      case 'urgent':
        return TicketPriority.urgent;
      case 'medium':
      default:
        return TicketPriority.medium;
    }
  }

  String get label {
    switch (this) {
      case TicketPriority.low:
        return 'Baixa';
      case TicketPriority.medium:
        return 'Média';
      case TicketPriority.high:
        return 'Alta';
      case TicketPriority.urgent:
        return 'Urgente';
    }
  }
}

Color ticketPriorityColor(BuildContext context, TicketPriority priority) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (priority) {
    case TicketPriority.urgent:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case TicketPriority.high:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case TicketPriority.medium:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case TicketPriority.low:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

/// Categoria do ticket (1:1 com o backend).
enum TicketCategory {
  bug,
  featureRequest,
  question,
  improvement,
  financial,
  other;

  static TicketCategory fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'bug':
        return TicketCategory.bug;
      case 'feature_request':
        return TicketCategory.featureRequest;
      case 'improvement':
        return TicketCategory.improvement;
      case 'financial':
        return TicketCategory.financial;
      case 'other':
        return TicketCategory.other;
      case 'question':
      default:
        return TicketCategory.question;
    }
  }

  String get apiValue {
    switch (this) {
      case TicketCategory.bug:
        return 'bug';
      case TicketCategory.featureRequest:
        return 'feature_request';
      case TicketCategory.question:
        return 'question';
      case TicketCategory.improvement:
        return 'improvement';
      case TicketCategory.financial:
        return 'financial';
      case TicketCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case TicketCategory.bug:
        return 'Erro / Bug';
      case TicketCategory.featureRequest:
        return 'Nova funcionalidade';
      case TicketCategory.question:
        return 'Dúvida';
      case TicketCategory.improvement:
        return 'Melhoria';
      case TicketCategory.financial:
        return 'Financeiro';
      case TicketCategory.other:
        return 'Outro';
    }
  }

  /// Descrição curta usada na abertura do ticket.
  String get hint {
    switch (this) {
      case TicketCategory.bug:
        return 'Algo quebrou ou não funciona como deveria';
      case TicketCategory.featureRequest:
        return 'Sugestão de algo novo no sistema';
      case TicketCategory.question:
        return 'Dúvida sobre como usar uma tela ou recurso';
      case TicketCategory.improvement:
        return 'Algo funciona, mas poderia ser melhor';
      case TicketCategory.financial:
        return 'Cobrança, plano ou pagamento';
      case TicketCategory.other:
        return 'Nenhuma das opções acima';
    }
  }

  /// Categorias que exigem ao menos um print na abertura (paridade web).
  bool get requiresAttachment =>
      this == TicketCategory.bug || this == TicketCategory.improvement;
}

Color ticketCategoryColor(BuildContext context, TicketCategory category) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (category) {
    case TicketCategory.bug:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case TicketCategory.featureRequest:
      return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case TicketCategory.question:
      return isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    case TicketCategory.improvement:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case TicketCategory.financial:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case TicketCategory.other:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData ticketCategoryIcon(TicketCategory category) {
  switch (category) {
    case TicketCategory.bug:
      return LucideIcons.bug;
    case TicketCategory.featureRequest:
      return LucideIcons.sparkles;
    case TicketCategory.question:
      return LucideIcons.circleHelp;
    case TicketCategory.improvement:
      return LucideIcons.trendingUp;
    case TicketCategory.financial:
      return LucideIcons.dollarSign;
    case TicketCategory.other:
      return LucideIcons.tag;
  }
}

/// Status do SLA de primeira resposta (calculado pelo backend).
enum TicketSlaStatus {
  pending,
  onTime,
  warning,
  late,
  unknown;

  static TicketSlaStatus fromRaw(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return TicketSlaStatus.pending;
      case 'on_time':
        return TicketSlaStatus.onTime;
      case 'warning':
        return TicketSlaStatus.warning;
      case 'late':
        return TicketSlaStatus.late;
      default:
        return TicketSlaStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case TicketSlaStatus.pending:
        return 'Aguardando resposta';
      case TicketSlaStatus.onTime:
        return 'No prazo';
      case TicketSlaStatus.warning:
        return 'Atenção';
      case TicketSlaStatus.late:
        return 'Estourado';
      case TicketSlaStatus.unknown:
        return '';
    }
  }
}

/// Anexo de um ticket ou de uma mensagem.
class TicketAttachment {
  final String id;
  final String? ticketId;
  final String? commentId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final DateTime? createdAt;

  const TicketAttachment({
    required this.id,
    this.ticketId,
    this.commentId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.createdAt,
  });

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  factory TicketAttachment.fromJson(Map<String, dynamic> json) {
    return TicketAttachment(
      id: json['id']?.toString() ?? '',
      ticketId: _toStringOrNull(json['ticketId']),
      commentId: _toStringOrNull(json['commentId']),
      fileName: json['fileName']?.toString() ?? 'anexo',
      mimeType: json['mimeType']?.toString() ?? '',
      sizeBytes: _toInt(json['sizeBytes']),
      createdAt: _toDate(json['createdAt']),
    );
  }

  static List<TicketAttachment> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => TicketAttachment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// Mensagem da conversa do ticket.
class TicketComment {
  final String id;
  final String ticketId;
  final String? authorName;
  final bool isFromUniao;
  final String body;
  final DateTime? createdAt;
  final List<TicketAttachment> attachments;

  const TicketComment({
    required this.id,
    required this.ticketId,
    this.authorName,
    required this.isFromUniao,
    required this.body,
    this.createdAt,
    this.attachments = const [],
  });

  factory TicketComment.fromJson(Map<String, dynamic> json) {
    return TicketComment(
      id: json['id']?.toString() ?? '',
      ticketId: json['ticketId']?.toString() ?? '',
      authorName: _toStringOrNull(json['authorName']),
      isFromUniao: json['isFromUniao'] == true,
      body: json['body']?.toString() ?? '',
      createdAt: _toDate(json['createdAt']),
      attachments: TicketAttachment.listFrom(json['attachments']),
    );
  }
}

/// Item do histórico de status.
class TicketStatusHistoryItem {
  final String id;
  final TicketStatus? fromStatus;
  final TicketStatus toStatus;
  final String? changedByName;
  final DateTime? createdAt;

  const TicketStatusHistoryItem({
    required this.id,
    this.fromStatus,
    required this.toStatus,
    this.changedByName,
    this.createdAt,
  });

  factory TicketStatusHistoryItem.fromJson(Map<String, dynamic> json) {
    final fromRaw = _toStringOrNull(json['fromStatus']);
    return TicketStatusHistoryItem(
      id: json['id']?.toString() ?? '',
      fromStatus: fromRaw == null ? null : TicketStatus.fromRaw(fromRaw),
      toStatus: TicketStatus.fromRaw(json['toStatus']?.toString()),
      changedByName: _toStringOrNull(json['changedByName']),
      createdAt: _toDate(json['createdAt']),
    );
  }
}

/// Ticket de suporte.
class Ticket {
  final String id;
  final String companyId;
  final String? companyName;
  final String? createdByName;
  final String? createdByEmail;
  final String title;
  final String description;
  final TicketCategory category;
  final TicketPriority priority;
  final TicketStatus status;
  final String? assignedToUserId;
  final String? assignedToName;
  final String? attendantUserId;
  final String? attendantName;
  final String? developerUserId;
  final String? developerName;
  final DateTime? lastReplyAt;
  final DateTime? firstResponseAt;
  final String? firstResponseByName;
  final int? firstResponseMinutes;
  final int? slaTargetMinutes;
  final TicketSlaStatus slaStatus;
  final DateTime? requesterLastMessageAt;
  final DateTime? attendantLastReplyAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Ticket({
    required this.id,
    required this.companyId,
    this.companyName,
    this.createdByName,
    this.createdByEmail,
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.status,
    this.assignedToUserId,
    this.assignedToName,
    this.attendantUserId,
    this.attendantName,
    this.developerUserId,
    this.developerName,
    this.lastReplyAt,
    this.firstResponseAt,
    this.firstResponseByName,
    this.firstResponseMinutes,
    this.slaTargetMinutes,
    this.slaStatus = TicketSlaStatus.unknown,
    this.requesterLastMessageAt,
    this.attendantLastReplyAt,
    this.resolvedAt,
    this.closedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Ainda sem atendimento (aberto, sem atendente/dev e sem 1ª resposta) —
  /// mesma regra do web: é quando o solicitante ainda pode excluir.
  bool get isUnattended =>
      status == TicketStatus.open &&
      (attendantUserId == null || attendantUserId!.isEmpty) &&
      (developerUserId == null || developerUserId!.isEmpty) &&
      (assignedToUserId == null || assignedToUserId!.isEmpty) &&
      firstResponseAt == null;

  /// Melhor nome do atendente para exibição.
  String? get attendantLabel {
    final a = (attendantName ?? '').trim();
    if (a.isNotEmpty) return a;
    final f = (firstResponseByName ?? '').trim();
    return f.isEmpty ? null : f;
  }

  /// Melhor nome do desenvolvedor para exibição.
  String? get developerLabel {
    final d = (developerName ?? '').trim();
    if (d.isNotEmpty) return d;
    final a = (assignedToName ?? '').trim();
    return a.isEmpty ? null : a;
  }

  factory Ticket.fromJson(Map<String, dynamic> json) {
    int? intOrNull(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return Ticket(
      id: json['id']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? '',
      companyName: _toStringOrNull(json['companyName']),
      createdByName: _toStringOrNull(json['createdByName']),
      createdByEmail: _toStringOrNull(json['createdByEmail']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: TicketCategory.fromRaw(json['category']?.toString()),
      priority: TicketPriority.fromRaw(json['priority']?.toString()),
      status: TicketStatus.fromRaw(json['status']?.toString()),
      assignedToUserId: _toStringOrNull(json['assignedToUserId']),
      assignedToName: _toStringOrNull(json['assignedToName']),
      attendantUserId: _toStringOrNull(json['attendantUserId']),
      attendantName: _toStringOrNull(json['attendantName']),
      developerUserId: _toStringOrNull(json['developerUserId']),
      developerName: _toStringOrNull(json['developerName']),
      lastReplyAt: _toDate(json['lastReplyAt']),
      firstResponseAt: _toDate(json['firstResponseAt']),
      firstResponseByName: _toStringOrNull(json['firstResponseByName']),
      firstResponseMinutes: intOrNull(json['firstResponseMinutes']),
      slaTargetMinutes: intOrNull(json['slaTargetMinutes']),
      slaStatus: TicketSlaStatus.fromRaw(json['responseSlaStatus']?.toString()),
      requesterLastMessageAt: _toDate(json['requesterLastMessageAt']),
      attendantLastReplyAt: _toDate(json['attendantLastReplyAt']),
      resolvedAt: _toDate(json['resolvedAt']),
      closedAt: _toDate(json['closedAt']),
      createdAt: _toDate(json['createdAt']),
      updatedAt: _toDate(json['updatedAt']),
    );
  }
}

/// Resposta de `GET /tickets` (lista paginada).
class TicketListResult {
  final List<Ticket> items;
  final int total;
  final int page;
  final int limit;

  const TicketListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  static const empty = TicketListResult(
    items: [],
    total: 0,
    page: 1,
    limit: 20,
  );

  factory TicketListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final list = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => Ticket.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <Ticket>[];
    return TicketListResult(
      items: list,
      total: _toInt(json['total'], list.length),
      page: _toInt(json['page'], 1),
      limit: _toInt(json['limit'], 20),
    );
  }
}

/// Resposta de `GET /tickets/:id` — ticket + conversa + anexos + histórico.
class TicketDetail {
  final Ticket ticket;
  final List<TicketComment> comments;
  final List<TicketAttachment> attachments;
  final List<TicketStatusHistoryItem> statusHistory;

  const TicketDetail({
    required this.ticket,
    required this.comments,
    required this.attachments,
    required this.statusHistory,
  });

  /// Anexos enviados direto no ticket (fora de mensagens).
  List<TicketAttachment> get rootAttachments =>
      attachments.where((a) => a.commentId == null).toList();

  factory TicketDetail.fromJson(Map<String, dynamic> json) {
    final rawTicket = json['ticket'];
    final ticket = rawTicket is Map
        ? Ticket.fromJson(Map<String, dynamic>.from(rawTicket))
        : Ticket.fromJson(json);
    final rawComments = json['comments'];
    final comments = rawComments is List
        ? rawComments
              .whereType<Map>()
              .map((e) => TicketComment.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <TicketComment>[];
    final rawHistory = json['statusHistory'];
    final history = rawHistory is List
        ? rawHistory
              .whereType<Map>()
              .map(
                (e) => TicketStatusHistoryItem.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : <TicketStatusHistoryItem>[];
    return TicketDetail(
      ticket: ticket,
      comments: comments,
      attachments: TicketAttachment.listFrom(json['attachments']),
      statusHistory: history,
    );
  }
}

/// Aba ativa da lista de tickets.
enum TicketTab { active, waiting, finished }

/// Payload de `POST /tickets`.
class CreateTicketPayload {
  final String title;
  final String description;
  final TicketCategory category;

  const CreateTicketPayload({
    required this.title,
    required this.description,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'category': category.apiValue,
  };
}
