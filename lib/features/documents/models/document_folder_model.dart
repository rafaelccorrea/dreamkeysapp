/// Pasta de documentos do CRM (uma por card/negócio) — espelho de
/// `imobx-front/src/types/documentFolder.ts`.
library;

enum DocumentFolderStatus {
  draft('draft', 'Rascunho'),
  collecting('collecting', 'Coletando'),
  incomplete('incomplete', 'Incompleta'),
  pendingReview('pending_review', 'Em revisão'),
  complete('complete', 'Completa');

  final String value;
  final String label;

  const DocumentFolderStatus(this.value, this.label);

  static DocumentFolderStatus fromString(String? v) =>
      DocumentFolderStatus.values.firstWhere(
        (e) => e.value == v,
        orElse: () => DocumentFolderStatus.draft,
      );
}

enum DocumentFolderItemStatus {
  missing('missing', 'Faltando'),
  uploaded('uploaded', 'Enviado'),
  pendingReview('pending_review', 'Em revisão'),
  approved('approved', 'Aprovado'),
  rejected('rejected', 'Rejeitado');

  final String value;
  final String label;

  const DocumentFolderItemStatus(this.value, this.label);

  /// Rótulo exibido no painel do card: o web mostra "Aprovado" também para
  /// `uploaded` (upload interno já nasce aprovado).
  String get uiLabel =>
      this == DocumentFolderItemStatus.uploaded ? 'Aprovado' : label;

  static DocumentFolderItemStatus fromString(String? v) =>
      DocumentFolderItemStatus.values.firstWhere(
        (e) => e.value == v,
        orElse: () => DocumentFolderItemStatus.missing,
      );
}

/// Visibilidade da lista devolvida pelo back (`visibilityScope`).
enum FolderListVisibilityScope {
  all,
  team,
  personal;

  static FolderListVisibilityScope fromString(String? v) {
    switch (v) {
      case 'all':
        return FolderListVisibilityScope.all;
      case 'team':
        return FolderListVisibilityScope.team;
      default:
        return FolderListVisibilityScope.personal;
    }
  }

  /// Mesmo texto do `scopeLabel` do web.
  String get label {
    switch (this) {
      case FolderListVisibilityScope.all:
        return 'Você está vendo todas as pastas da empresa.';
      case FolderListVisibilityScope.team:
        return 'Você está vendo pastas da sua equipe (membros e negociações '
            'vinculadas).';
      case FolderListVisibilityScope.personal:
        return 'Você está vendo pastas em que enviou documentos ou está '
            'vinculado como pessoa envolvida no card.';
    }
  }
}

class DocumentFolderItemDocument {
  final String id;
  final String originalName;
  final String? status;
  final String? fileUrl;
  final String? mimeType;

  DocumentFolderItemDocument({
    required this.id,
    required this.originalName,
    this.status,
    this.fileUrl,
    this.mimeType,
  });

  factory DocumentFolderItemDocument.fromJson(Map<String, dynamic> j) {
    return DocumentFolderItemDocument(
      id: j['id']?.toString() ?? '',
      originalName: j['originalName']?.toString() ?? '',
      status: j['status']?.toString(),
      fileUrl: j['fileUrl']?.toString(),
      mimeType: j['mimeType']?.toString(),
    );
  }
}

class DocumentFolderItem {
  final String id;
  final String folderId;
  final String documentType;
  final String label;
  final bool required;
  final int order;
  final DocumentFolderItemStatus status;
  final String? documentId;
  final String? notes;
  final DocumentFolderItemDocument? document;

  DocumentFolderItem({
    required this.id,
    required this.folderId,
    required this.documentType,
    required this.label,
    required this.required,
    required this.order,
    required this.status,
    this.documentId,
    this.notes,
    this.document,
  });

  bool get isDone =>
      status == DocumentFolderItemStatus.approved ||
      status == DocumentFolderItemStatus.uploaded;

  factory DocumentFolderItem.fromJson(Map<String, dynamic> j) {
    final doc = j['document'];
    return DocumentFolderItem(
      id: j['id']?.toString() ?? '',
      folderId: j['folderId']?.toString() ?? '',
      documentType: j['documentType']?.toString() ?? 'other',
      label: j['label']?.toString() ?? '',
      required: j['required'] == true,
      order: int.tryParse(j['order']?.toString() ?? '') ?? 0,
      status: DocumentFolderItemStatus.fromString(j['status']?.toString()),
      documentId: j['documentId']?.toString(),
      notes: j['notes']?.toString(),
      document: doc is Map
          ? DocumentFolderItemDocument.fromJson(Map<String, dynamic>.from(doc))
          : null,
    );
  }
}

class DocumentFolderRef {
  final String id;
  final String name;

  DocumentFolderRef({required this.id, required this.name});

  static DocumentFolderRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return DocumentFolderRef(
      id: id,
      name: (raw['name'] ?? raw['title'] ?? '').toString(),
    );
  }
}

class DocumentFolderTask {
  final String id;
  final String title;
  final String? clientId;
  final String? assignedToId;
  final DocumentFolderRef? client;
  final DocumentFolderRef? assignedTo;
  final List<DocumentFolderRef> involvedUsers;

  DocumentFolderTask({
    required this.id,
    required this.title,
    this.clientId,
    this.assignedToId,
    this.client,
    this.assignedTo,
    this.involvedUsers = const [],
  });

  factory DocumentFolderTask.fromJson(Map<String, dynamic> j) {
    final inv = j['involvedUsers'];
    return DocumentFolderTask(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      clientId: j['clientId']?.toString(),
      assignedToId: j['assignedToId']?.toString(),
      client: DocumentFolderRef.fromJson(j['client']),
      assignedTo: DocumentFolderRef.fromJson(j['assignedTo']),
      involvedUsers: inv is List
          ? inv
              .map(DocumentFolderRef.fromJson)
              .whereType<DocumentFolderRef>()
              .toList()
          : const [],
    );
  }
}

class DocumentFolder {
  final String id;
  final String kanbanTaskId;
  final String? empreendimentoId;
  final DocumentFolderStatus status;
  final String? incorporadoraStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<DocumentFolderItem> items;
  final DocumentFolderRef? empreendimento;
  final DocumentFolderTask? kanbanTask;

  DocumentFolder({
    required this.id,
    required this.kanbanTaskId,
    this.empreendimentoId,
    required this.status,
    this.incorporadoraStatus,
    this.createdAt,
    this.updatedAt,
    required this.items,
    this.empreendimento,
    this.kanbanTask,
  });

  factory DocumentFolder.fromJson(Map<String, dynamic> j) {
    // Remove duplicatas (join do TypeORM com envolvidos) e ordena — igual ao
    // `normalizeFolderItems` do web.
    final byId = <String, DocumentFolderItem>{};
    final rawItems = j['items'];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          final it = DocumentFolderItem.fromJson(Map<String, dynamic>.from(e));
          byId[it.id] = it;
        }
      }
    }
    final items = byId.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final task = j['kanbanTask'];
    return DocumentFolder(
      id: j['id']?.toString() ?? '',
      kanbanTaskId: j['kanbanTaskId']?.toString() ?? '',
      empreendimentoId: j['empreendimentoId']?.toString(),
      status: DocumentFolderStatus.fromString(j['status']?.toString()),
      incorporadoraStatus: j['incorporadoraStatus']?.toString(),
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? ''),
      items: items,
      empreendimento: DocumentFolderRef.fromJson(j['empreendimento']),
      kanbanTask: task is Map
          ? DocumentFolderTask.fromJson(Map<String, dynamic>.from(task))
          : null,
    );
  }

  int get requiredCount => items.where((i) => i.required).length;

  int get approvedRequiredCount =>
      items.where((i) => i.required && i.isDone).length;

  /// Status derivado dos itens (corrige status gravado desatualizado) —
  /// `computeEffectiveFolderStatus` do web.
  DocumentFolderStatus get effectiveStatus {
    if (items.isEmpty) return status;
    final required = items.where((i) => i.required).toList();
    final uploaded =
        items.where((i) => i.status != DocumentFolderItemStatus.missing).length;
    if (uploaded == 0) return DocumentFolderStatus.collecting;
    if (required.any((i) => i.status == DocumentFolderItemStatus.missing)) {
      return DocumentFolderStatus.incomplete;
    }
    if (required.any((i) => i.status == DocumentFolderItemStatus.rejected)) {
      return DocumentFolderStatus.incomplete;
    }
    if (required.isNotEmpty && required.every((i) => i.isDone)) {
      return DocumentFolderStatus.complete;
    }
    if (required
        .any((i) => i.status == DocumentFolderItemStatus.pendingReview)) {
      return DocumentFolderStatus.pendingReview;
    }
    return status;
  }

  int get progressPct => requiredCount == 0
      ? 0
      : ((approvedRequiredCount / requiredCount) * 100).round();
}

class DocumentFolderListResult {
  final List<DocumentFolder> data;
  final int total;
  final int page;
  final int limit;
  final FolderListVisibilityScope visibilityScope;

  DocumentFolderListResult({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.visibilityScope,
  });

  int get totalPages {
    if (limit <= 0) return 1;
    final pages = (total / limit).ceil();
    return pages < 1 ? 1 : pages;
  }
}
