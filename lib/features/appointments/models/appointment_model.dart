/// Modelo de dados para Agendamento
class Appointment {
  final String id;
  final String title;
  final String? description;
  final AppointmentType type;
  final AppointmentStatus status;
  final AppointmentVisibility visibility;
  final DateTime startDate;
  final DateTime endDate;
  final String? location;
  final String? notes;
  final String color;
  final bool isRecurring;
  final String userId;
  final String companyId;
  final String? propertyId;
  final String? clientId;
  final List<String> participantIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Relacionamentos (opcionais)
  final Map<String, dynamic>? property;
  final Map<String, dynamic>? client;
  final Map<String, dynamic>? user;
  final List<AppointmentInvite>? invites;
  final List<Participant>? participants;

  Appointment({
    required this.id,
    required this.title,
    this.description,
    required this.type,
    required this.status,
    required this.visibility,
    required this.startDate,
    required this.endDate,
    this.location,
    this.notes,
    required this.color,
    this.isRecurring = false,
    required this.userId,
    required this.companyId,
    this.propertyId,
    this.clientId,
    this.participantIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.property,
    this.client,
    this.user,
    this.invites,
    this.participants,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      type: AppointmentType.fromString(json['type']?.toString() ?? 'visit'),
      status: AppointmentStatus.fromString(json['status']?.toString() ?? 'scheduled'),
      visibility: AppointmentVisibility.fromString(json['visibility']?.toString() ?? 'private'),
      startDate: DateTime.parse(json['startDate'].toString()),
      endDate: DateTime.parse(json['endDate'].toString()),
      location: json['location']?.toString(),
      notes: json['notes']?.toString(),
      color: json['color']?.toString() ?? '#3B82F6',
      isRecurring: json['isRecurring'] as bool? ?? false,
      userId: json['userId']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? '',
      propertyId: json['propertyId']?.toString(),
      clientId: json['clientId']?.toString(),
      participantIds: json['participantIds'] != null
          ? List<String>.from((json['participantIds'] as List).map((e) => e.toString()))
          : [],
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      property: json['property'] as Map<String, dynamic>?,
      client: json['client'] as Map<String, dynamic>?,
      user: json['user'] as Map<String, dynamic>?,
      invites: json['invites'] != null
          ? (json['invites'] as List).map((e) => AppointmentInvite.fromJson(e as Map<String, dynamic>)).toList()
          : null,
      participants: json['participants'] != null
          ? (json['participants'] as List).map((e) => Participant.fromJson(e as Map<String, dynamic>)).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.value,
      'status': status.value,
      'visibility': visibility.value,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'location': location,
      'notes': notes,
      'color': color,
      'isRecurring': isRecurring,
      'userId': userId,
      'companyId': companyId,
      'propertyId': propertyId,
      'clientId': clientId,
      'participantIds': participantIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Appointment copyWith({
    String? id,
    String? title,
    String? description,
    AppointmentType? type,
    AppointmentStatus? status,
    AppointmentVisibility? visibility,
    DateTime? startDate,
    DateTime? endDate,
    String? location,
    String? notes,
    String? color,
    bool? isRecurring,
    String? userId,
    String? companyId,
    String? propertyId,
    String? clientId,
    List<String>? participantIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? property,
    Map<String, dynamic>? client,
    Map<String, dynamic>? user,
    List<AppointmentInvite>? invites,
    List<Participant>? participants,
  }) {
    return Appointment(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      status: status ?? this.status,
      visibility: visibility ?? this.visibility,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      color: color ?? this.color,
      isRecurring: isRecurring ?? this.isRecurring,
      userId: userId ?? this.userId,
      companyId: companyId ?? this.companyId,
      propertyId: propertyId ?? this.propertyId,
      clientId: clientId ?? this.clientId,
      participantIds: participantIds ?? this.participantIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      property: property ?? this.property,
      client: client ?? this.client,
      user: user ?? this.user,
      invites: invites ?? this.invites,
      participants: participants ?? this.participants,
    );
  }
}

/// Tipos de Agendamento
enum AppointmentType {
  visit('visit', 'Visita'),
  meeting('meeting', 'Reunião'),
  inspection('inspection', 'Vistoria'),
  documentation('documentation', 'Documentação'),
  maintenance('maintenance', 'Manutenção'),
  marketing('marketing', 'Marketing'),
  training('training', 'Treinamento'),
  other('other', 'Outro');

  final String value;
  final String label;

  const AppointmentType(this.value, this.label);

  static AppointmentType fromString(String? value) {
    if (value == null) return AppointmentType.visit;
    try {
      return AppointmentType.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return AppointmentType.visit;
    }
  }
}

/// Status de Agendamento
enum AppointmentStatus {
  scheduled('scheduled', 'Agendado'),
  confirmed('confirmed', 'Confirmado'),
  inProgress('in_progress', 'Em andamento'),
  completed('completed', 'Concluído'),
  cancelled('cancelled', 'Cancelado'),
  noShow('no_show', 'Não compareceu');

  final String value;
  final String label;

  const AppointmentStatus(this.value, this.label);

  static AppointmentStatus fromString(String? value) {
    if (value == null) return AppointmentStatus.scheduled;
    try {
      return AppointmentStatus.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return AppointmentStatus.scheduled;
    }
  }
}

/// Níveis de Visibilidade
enum AppointmentVisibility {
  public('public', 'Público'),
  private('private', 'Privado'),
  team('team', 'Equipe');

  final String value;
  final String label;

  const AppointmentVisibility(this.value, this.label);

  static AppointmentVisibility fromString(String? value) {
    if (value == null) return AppointmentVisibility.private;
    try {
      return AppointmentVisibility.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return AppointmentVisibility.private;
    }
  }
}

/// Modelo de Participante
class Participant {
  final String id;
  final String name;
  final String email;
  final String? avatar;
  final String? phone;
  final String role;

  Participant({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    this.phone,
    required this.role,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatar: json['avatar']?.toString(),
      phone: json['phone']?.toString(),
      role: json['role']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatar': avatar,
      'phone': phone,
      'role': role,
    };
  }
}

/// Modelo de Convite de Agendamento
class AppointmentInvite {
  final String id;
  final String appointmentId;
  final String inviterUserId;
  final String invitedUserId;
  final String companyId;
  final InviteStatus status;
  final String? message;
  final DateTime? respondedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Relacionamentos
  final Map<String, dynamic>? appointment;
  final Map<String, dynamic>? inviter;
  final Map<String, dynamic>? invitedUser;

  AppointmentInvite({
    required this.id,
    required this.appointmentId,
    required this.inviterUserId,
    required this.invitedUserId,
    required this.companyId,
    required this.status,
    this.message,
    this.respondedAt,
    required this.createdAt,
    required this.updatedAt,
    this.appointment,
    this.inviter,
    this.invitedUser,
  });

  factory AppointmentInvite.fromJson(Map<String, dynamic> json) {
    return AppointmentInvite(
      id: json['id']?.toString() ?? '',
      appointmentId: json['appointmentId']?.toString() ?? '',
      inviterUserId: json['inviterUserId']?.toString() ?? '',
      invitedUserId: json['invitedUserId']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? '',
      status: InviteStatus.fromString(json['status']?.toString() ?? 'pending'),
      message: json['message']?.toString(),
      respondedAt: json['respondedAt'] != null
          ? DateTime.parse(json['respondedAt'].toString())
          : null,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      appointment: json['appointment'] as Map<String, dynamic>?,
      inviter: json['inviter'] as Map<String, dynamic>?,
      invitedUser: json['invitedUser'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'appointmentId': appointmentId,
      'inviterUserId': inviterUserId,
      'invitedUserId': invitedUserId,
      'companyId': companyId,
      'status': status.value,
      'message': message,
      'respondedAt': respondedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Status de Convite
enum InviteStatus {
  pending('pending', 'Pendente'),
  accepted('accepted', 'Aceito'),
  declined('declined', 'Recusado'),
  cancelled('cancelled', 'Cancelado');

  final String value;
  final String label;

  const InviteStatus(this.value, this.label);

  static InviteStatus fromString(String? value) {
    if (value == null) return InviteStatus.pending;
    try {
      return InviteStatus.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return InviteStatus.pending;
    }
  }
}

/// Dados para criar agendamento
class CreateAppointmentData {
  final String title;
  final String? description;
  final AppointmentType type;
  final AppointmentStatus? status;
  final AppointmentVisibility? visibility;
  final DateTime startDate;
  final DateTime endDate;
  final String? location;
  final String? notes;
  final String? color;
  final bool? isRecurring;
  final String? propertyId;
  final String? clientId;
  final List<String>? participantIds;
  final List<String>? inviteUserIds;

  CreateAppointmentData({
    required this.title,
    this.description,
    required this.type,
    this.status,
    this.visibility,
    required this.startDate,
    required this.endDate,
    this.location,
    this.notes,
    this.color,
    this.isRecurring,
    this.propertyId,
    this.clientId,
    this.participantIds,
    this.inviteUserIds,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (description != null) 'description': description,
      'type': type.value,
      if (status != null) 'status': status!.value,
      if (visibility != null) 'visibility': visibility!.value,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      if (location != null) 'location': location,
      if (notes != null) 'notes': notes,
      if (color != null) 'color': color,
      if (isRecurring != null) 'isRecurring': isRecurring,
      if (propertyId != null) 'propertyId': propertyId,
      if (clientId != null) 'clientId': clientId,
      if (participantIds != null) 'participantIds': participantIds,
      if (inviteUserIds != null) 'inviteUserIds': inviteUserIds,
    };
  }
}

/// Dados para atualizar agendamento
class UpdateAppointmentData {
  final String? title;
  final String? description;
  final AppointmentType? type;
  final AppointmentStatus? status;
  final AppointmentVisibility? visibility;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? location;
  final String? notes;
  final String? color;
  final bool? isRecurring;
  final String? propertyId;
  final String? clientId;
  final List<String>? participantIds;
  final List<String>? inviteUserIds;

  UpdateAppointmentData({
    this.title,
    this.description,
    this.type,
    this.status,
    this.visibility,
    this.startDate,
    this.endDate,
    this.location,
    this.notes,
    this.color,
    this.isRecurring,
    this.propertyId,
    this.clientId,
    this.participantIds,
    this.inviteUserIds,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (description != null) map['description'] = description;
    if (type != null) map['type'] = type!.value;
    if (status != null) map['status'] = status!.value;
    if (visibility != null) map['visibility'] = visibility!.value;
    if (startDate != null) map['startDate'] = startDate!.toIso8601String();
    if (endDate != null) map['endDate'] = endDate!.toIso8601String();
    if (location != null) map['location'] = location;
    if (notes != null) map['notes'] = notes;
    if (color != null) map['color'] = color;
    if (isRecurring != null) map['isRecurring'] = isRecurring;
    if (propertyId != null) map['propertyId'] = propertyId;
    if (clientId != null) map['clientId'] = clientId;
    if (participantIds != null) map['participantIds'] = participantIds;
    if (inviteUserIds != null) map['inviteUserIds'] = inviteUserIds;
    return map;
  }
}

/// Resposta de lista de agendamentos
class AppointmentListResponse {
  final List<Appointment> appointments;
  final PaginationInfo pagination;

  AppointmentListResponse({
    required this.appointments,
    required this.pagination,
  });

  factory AppointmentListResponse.fromJson(Map<String, dynamic> json) {
    return AppointmentListResponse(
      appointments: (json['appointments'] as List<dynamic>?)
              ?.map((e) => Appointment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pagination: PaginationInfo.fromJson(json['pagination'] as Map<String, dynamic>),
    );
  }
}

/// Informações de paginação
class PaginationInfo {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  PaginationInfo({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory PaginationInfo.fromJson(Map<String, dynamic> json) {
    return PaginationInfo(
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 10,
      total: (json['total'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
    );
  }
}


