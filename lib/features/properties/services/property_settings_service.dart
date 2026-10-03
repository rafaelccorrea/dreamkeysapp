import 'package:flutter/foundation.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/utils/avatar_url_resolver.dart';
import '../../../shared/utils/role_access_rules.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Configurações de imóveis — paridade com as telas do web:
//
//   /properties/form-settings           PropertyFormSettingsPage.tsx
//   /properties/approval-settings       PropertyApprovalSettingsPage.tsx
//   /properties/protected-fields-config PropertyProtectedFieldsConfigPage.tsx
//   /properties/owner-data-visibility   OwnerDataVisibilityConfigPage.tsx
//
// Contrato (intellisys-CRM-Back):
//   GET   /properties/approval-settings            manage_approval_settings
//   PATCH /properties/approval-settings            manage_approval_settings
//   GET   /properties/form-settings                view|create|update
//   GET   /properties/approvers?type=              manage_approval_settings
//   GET   /properties/approvers/authorized-users   manage_approval_settings
//   POST  /properties/approvers                    manage_approval_settings
//   POST  /properties/approvers/revoke-user-permission
//   DELETE /properties/approvers/:configId
//   PUT   /properties/approvers/quorum-settings
//   GET|POST|PATCH|DELETE /property-catalog        (escrita: manage_approval_settings)
//   GET   /protected-owner-data/users|scope        admin/master OU view_protected_owner_data
//   POST|DELETE /protected-owner-data/users/:id    só admin/master (@Roles)
//   GET   /users/company-members/simple            membros ATIVOS da empresa
// ═══════════════════════════════════════════════════════════════════════════

// ─── Leitura tolerante ──────────────────────────────────────────────────────

Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Objeto direto ou envelope `{ data: {...} }`.
Map<String, dynamic>? _unwrap(dynamic raw) {
  final m = _asMap(raw);
  if (m == null) return null;
  final inner = _asMap(m['data']);
  if (inner != null && m['id'] == null) return inner;
  return m;
}

/// Lista direta ou dentro de `data`/`items`/`results`.
List<dynamic> _asList(dynamic raw) {
  if (raw is List) return raw;
  final m = _asMap(raw);
  if (m != null) {
    for (final key in const ['data', 'items', 'results']) {
      final v = m[key];
      if (v is List) return v;
    }
  }
  return const <dynamic>[];
}

String? _text(dynamic v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty || t == 'null' ? null : t;
}

int _int(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.toInt() ?? fallback;
  }
  return fallback;
}

bool? _boolOrNull(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.trim().toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return null;
}

bool _bool(dynamic v, {bool fallback = false}) => _boolOrNull(v) ?? fallback;

DateTime? _date(dynamic v) {
  final t = _text(v);
  return t == null ? null : DateTime.tryParse(t);
}

List<String> _strings(dynamic v) {
  if (v is! List) return const <String>[];
  final out = <String>[];
  for (final e in v) {
    final t = _text(e);
    if (t != null && !out.contains(t)) out.add(t);
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════
// Modelos
// ═══════════════════════════════════════════════════════════════════════════

/// Destino dos imóveis de quem é desativado
/// (`onDeactivateUserResponsibleAssignTo`).
enum SuccessionTarget {
  companyOwner('company_owner'),
  user('user');

  const SuccessionTarget(this.api);
  final String api;

  static SuccessionTarget parse(dynamic v) =>
      _text(v)?.toLowerCase() == 'user'
          ? SuccessionTarget.user
          : SuccessionTarget.companyOwner;
}

/// O que acontece com a captação de quem é desativado
/// (`onDeactivateUserCaptorAction`).
enum CaptorAction {
  remove('remove'),
  keep('keep');

  const CaptorAction(this.api);
  final String api;

  static CaptorAction parse(dynamic v) =>
      _text(v)?.toLowerCase() == 'keep' ? CaptorAction.keep : CaptorAction.remove;
}

/// `GET /properties/approval-settings` — a linha inteira de
/// `property_approval_settings` da empresa (`ApprovalSettingsFull` do web).
class PropertyApprovalSettingsFull {
  const PropertyApprovalSettingsFull({
    this.id = '',
    this.requireApprovalToBeAvailable = false,
    this.requireApprovalToPublishOnSite = false,
    this.requireOwnerAuthorizationToBeAvailable = false,
    this.applyWatermarkToImages = true,
    this.preservePublicationOnEdit = true,
    this.approversEnabled = false,
    this.minApprovalsAvailability = 1,
    this.minApprovalsPublication = 1,
    this.protectedFieldsEnabled = false,
    this.protectedFields = const <String>[],
    this.propertyFormRequiredFields = const <String>[],
    this.propertyFormAllowedTeamIds = const <String>[],
    this.onDeactivateAssignTo = SuccessionTarget.companyOwner,
    this.onDeactivateUserId,
    this.onDeactivateCaptorAction = CaptorAction.remove,
  });

  final String id;
  final bool requireApprovalToBeAvailable;
  final bool requireApprovalToPublishOnSite;
  final bool requireOwnerAuthorizationToBeAvailable;
  final bool applyWatermarkToImages;

  /// Ausente no back antigo → `true` (o `?? true` do web).
  final bool preservePublicationOnEdit;
  final bool approversEnabled;
  final int minApprovalsAvailability;
  final int minApprovalsPublication;
  final bool protectedFieldsEnabled;
  final List<String> protectedFields;
  final List<String> propertyFormRequiredFields;
  final List<String> propertyFormAllowedTeamIds;
  final SuccessionTarget onDeactivateAssignTo;
  final String? onDeactivateUserId;
  final CaptorAction onDeactivateCaptorAction;

  /// Alguma regra do fluxo ligada (o selo "Aprovações ativas" do web).
  bool get anyActive =>
      requireApprovalToBeAvailable ||
      requireApprovalToPublishOnSite ||
      requireOwnerAuthorizationToBeAvailable ||
      approversEnabled ||
      protectedFieldsEnabled;

  factory PropertyApprovalSettingsFull.fromJson(Map<String, dynamic> json) {
    return PropertyApprovalSettingsFull(
      id: _text(json['id']) ?? '',
      requireApprovalToBeAvailable: _bool(json['requireApprovalToBeAvailable']),
      requireApprovalToPublishOnSite:
          _bool(json['requireApprovalToPublishOnSite']),
      requireOwnerAuthorizationToBeAvailable:
          _bool(json['requireOwnerAuthorizationToBeAvailable']),
      applyWatermarkToImages:
          _bool(json['applyWatermarkToImages'], fallback: true),
      preservePublicationOnEdit:
          _bool(json['preservePublicationOnEdit'], fallback: true),
      approversEnabled: _bool(json['approversEnabled']),
      minApprovalsAvailability:
          _int(json['minApprovalsAvailability'], fallback: 1),
      minApprovalsPublication:
          _int(json['minApprovalsPublication'], fallback: 1),
      protectedFieldsEnabled: _bool(json['protectedFieldsEnabled']),
      protectedFields: _strings(json['protectedFields']),
      propertyFormRequiredFields: _strings(json['propertyFormRequiredFields']),
      propertyFormAllowedTeamIds: _strings(json['propertyFormAllowedTeamIds']),
      onDeactivateAssignTo:
          SuccessionTarget.parse(json['onDeactivateUserResponsibleAssignTo']),
      onDeactivateUserId: _text(json['onDeactivateUserResponsibleUserId']),
      onDeactivateCaptorAction:
          CaptorAction.parse(json['onDeactivateUserCaptorAction']),
    );
  }

  PropertyApprovalSettingsFull copyWith({
    bool? requireApprovalToBeAvailable,
    bool? requireApprovalToPublishOnSite,
    bool? requireOwnerAuthorizationToBeAvailable,
    bool? applyWatermarkToImages,
    bool? preservePublicationOnEdit,
    bool? approversEnabled,
    int? minApprovalsAvailability,
    int? minApprovalsPublication,
    bool? protectedFieldsEnabled,
    List<String>? protectedFields,
  }) {
    return PropertyApprovalSettingsFull(
      id: id,
      requireApprovalToBeAvailable:
          requireApprovalToBeAvailable ?? this.requireApprovalToBeAvailable,
      requireApprovalToPublishOnSite:
          requireApprovalToPublishOnSite ?? this.requireApprovalToPublishOnSite,
      requireOwnerAuthorizationToBeAvailable:
          requireOwnerAuthorizationToBeAvailable ??
              this.requireOwnerAuthorizationToBeAvailable,
      applyWatermarkToImages:
          applyWatermarkToImages ?? this.applyWatermarkToImages,
      preservePublicationOnEdit:
          preservePublicationOnEdit ?? this.preservePublicationOnEdit,
      approversEnabled: approversEnabled ?? this.approversEnabled,
      minApprovalsAvailability:
          minApprovalsAvailability ?? this.minApprovalsAvailability,
      minApprovalsPublication:
          minApprovalsPublication ?? this.minApprovalsPublication,
      protectedFieldsEnabled:
          protectedFieldsEnabled ?? this.protectedFieldsEnabled,
      protectedFields: protectedFields ?? this.protectedFields,
      propertyFormRequiredFields: propertyFormRequiredFields,
      propertyFormAllowedTeamIds: propertyFormAllowedTeamIds,
      onDeactivateAssignTo: onDeactivateAssignTo,
      onDeactivateUserId: onDeactivateUserId,
      onDeactivateCaptorAction: onDeactivateCaptorAction,
    );
  }
}

/// Equipe do seletor do cadastro (`{ id, name, color }`).
class PropertySettingsTeam {
  const PropertySettingsTeam({
    required this.id,
    required this.name,
    this.color,
  });

  final String id;
  final String name;

  /// Hex `#RRGGBB` (o back manda `#6366f1` quando a equipe não tem cor).
  final String? color;

  factory PropertySettingsTeam.fromJson(Map<String, dynamic> json) {
    return PropertySettingsTeam(
      id: _text(json['id']) ?? '',
      name: _text(json['name']) ?? 'Equipe',
      color: _text(json['color']),
    );
  }
}

/// `GET /properties/form-settings` — o que o editor de regras precisa.
class PropertyFormSettingsBundle {
  const PropertyFormSettingsBundle({
    this.requiredFields = const <String>[],
    this.allowedTeamIds = const <String>[],
    this.teams = const <PropertySettingsTeam>[],
    this.allCompanyTeams = const <PropertySettingsTeam>[],
  });

  final List<String> requiredFields;
  final List<String> allowedTeamIds;

  /// Equipes que aparecem hoje no seletor.
  final List<PropertySettingsTeam> teams;

  /// Todas as equipes ativas da empresa (só para quem gerencia).
  final List<PropertySettingsTeam> allCompanyTeams;

  /// As equipes que o editor lista — todas da empresa quando vierem (igual
  /// ao web), senão as do seletor.
  List<PropertySettingsTeam> get editableTeams =>
      allCompanyTeams.isNotEmpty ? allCompanyTeams : teams;

  factory PropertyFormSettingsBundle.fromJson(Map<String, dynamic> json) {
    List<PropertySettingsTeam> teamsOf(dynamic v) => _asList(v)
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(PropertySettingsTeam.fromJson)
        .where((t) => t.id.isNotEmpty)
        .toList();
    return PropertyFormSettingsBundle(
      requiredFields: _strings(json['propertyFormRequiredFields']),
      allowedTeamIds: _strings(json['propertyFormAllowedTeamIds']),
      teams: teamsOf(json['teams']),
      allCompanyTeams: teamsOf(json['allCompanyTeams']),
    );
  }
}

/// Membro ativo da empresa (`GET /users/company-members/simple`) ou usuário
/// habilitado (`GET /protected-owner-data/users`).
class PropertySettingsMember {
  const PropertySettingsMember({
    required this.id,
    required this.name,
    this.email = '',
    this.role,
    this.avatar,
    this.enabledAt,
  });

  final String id;
  final String name;
  final String email;

  /// Papel cru (`master`, `admin`, `manager`, `user`) — pode vir vazio.
  final String? role;
  final String? avatar;

  /// Quando a permissão de ver o proprietário foi concedida (só na lista de
  /// habilitados; nulo em concessões antigas).
  final DateTime? enabledAt;

  factory PropertySettingsMember.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['user']);
    final src = user ?? json;
    return PropertySettingsMember(
      id: _text(json['id']) ?? _text(src['id']) ?? '',
      name: _text(src['name']) ?? _text(json['name']) ?? 'Usuário',
      email: _text(src['email']) ?? _text(json['email']) ?? '',
      role: _text(src['role']) ?? _text(json['role']),
      avatar: AvatarUrlResolver.resolve(
        _text(src['avatar']) ?? _text(json['avatar']),
      ),
      enabledAt: _date(json['enabledAt']),
    );
  }
}

/// Tipo de aprovador (`ApproverConfigType` do back).
enum ApproverType {
  availability('availability', 'Disponibilidade'),
  publication('publication', 'Publicação'),
  editRequest('edit_request', 'Alteração de dados');

  const ApproverType(this.api, this.label);
  final String api;
  final String label;

  static ApproverType? parse(dynamic v) {
    final t = _text(v)?.toLowerCase();
    for (final e in ApproverType.values) {
      if (e.api == t) return e;
    }
    return null;
  }
}

/// Item de `GET /properties/approvers` (`ApproverConfig` do web).
class PropertyApproverConfig {
  const PropertyApproverConfig({
    required this.id,
    required this.userId,
    required this.type,
    this.userName = 'Usuário',
    this.userEmail = '',
    this.userAvatar,
    this.isRequired = false,
    this.displayOrder = 0,
  });

  final String id;
  final String userId;
  final ApproverType type;
  final String userName;
  final String userEmail;
  final String? userAvatar;
  final bool isRequired;
  final int displayOrder;

  factory PropertyApproverConfig.fromJson(
    Map<String, dynamic> json, {
    ApproverType fallbackType = ApproverType.availability,
  }) {
    final user = _asMap(json['user']);
    return PropertyApproverConfig(
      id: _text(json['id']) ?? '',
      userId: _text(json['userId']) ?? _text(user?['id']) ?? '',
      type: ApproverType.parse(json['approvalType']) ?? fallbackType,
      userName: _text(user?['name']) ?? 'Usuário',
      userEmail: _text(user?['email']) ?? '',
      userAvatar: AvatarUrlResolver.resolve(_text(user?['avatar'])),
      isRequired: _bool(json['isRequired']),
      displayOrder: _int(json['displayOrder']),
    );
  }
}

/// `GET /properties/approvers/authorized-users` — quem pode aprovar cada
/// fila (permissão direta ou lista de aprovadores).
class PropertyAuthorizedApprovers {
  const PropertyAuthorizedApprovers({
    this.availability = const <PropertySettingsMember>[],
    this.publication = const <PropertySettingsMember>[],
  });

  final List<PropertySettingsMember> availability;
  final List<PropertySettingsMember> publication;

  bool get isEmpty => availability.isEmpty && publication.isEmpty;

  factory PropertyAuthorizedApprovers.fromJson(Map<String, dynamic> json) {
    List<PropertySettingsMember> of(dynamic v) => _asList(v)
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(PropertySettingsMember.fromJson)
        .where((u) => u.id.isNotEmpty)
        .toList();
    return PropertyAuthorizedApprovers(
      availability: of(json['availability']),
      publication: of(json['publication']),
    );
  }
}

/// Tipo de item do catálogo extra do cadastro.
enum CatalogKind {
  room('room'),
  infrastructure('infrastructure');

  const CatalogKind(this.api);
  final String api;

  static CatalogKind? parse(dynamic v) {
    final t = _text(v)?.toLowerCase();
    if (t == 'room') return CatalogKind.room;
    if (t == 'infrastructure') return CatalogKind.infrastructure;
    return null;
  }
}

/// Item de `GET /property-catalog`.
class PropertyCatalogEntry {
  const PropertyCatalogEntry({
    required this.id,
    required this.kind,
    required this.name,
    this.sortOrder = 0,
  });

  final String id;
  final CatalogKind kind;
  final String name;
  final int sortOrder;

  static PropertyCatalogEntry? tryParse(dynamic raw) {
    final json = _asMap(raw);
    if (json == null) return null;
    final id = _text(json['id']);
    final kind = CatalogKind.parse(json['kind']);
    final name = _text(json['name']);
    if (id == null || kind == null || name == null) return null;
    return PropertyCatalogEntry(
      id: id,
      kind: kind,
      name: name,
      sortOrder: _int(json['sortOrder']),
    );
  }
}

/// `GET /protected-owner-data/scope` — alcance da regra (aditivo; 404 em
/// back antigo vira `null` na tela).
class OwnerDataScope {
  const OwnerDataScope({
    this.restrictedProperties = 0,
    this.responsibleId,
    this.responsibleName,
  });

  final int restrictedProperties;
  final String? responsibleId;
  final String? responsibleName;

  factory OwnerDataScope.fromJson(Map<String, dynamic> json) {
    final r = _asMap(json['responsible']);
    return OwnerDataScope(
      restrictedProperties: _int(json['restrictedProperties']),
      responsibleId: _text(r?['id']),
      responsibleName: _text(r?['name']),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Regras puras (sem Flutter) — o que os testes seguram
// ═══════════════════════════════════════════════════════════════════════════

/// Um campo configurável do cadastro (`PROPERTY_FORM_FIELD_OPTIONS` do web).
class PropertyFormFieldOption {
  const PropertyFormFieldOption(this.key, this.label, this.chapter);

  final String key;
  final String label;

  /// Índice da etapa do wizard (0 básicas, 1 localização, 2
  /// características, 3 valores, 6 proprietário).
  final int chapter;

  bool get isSystem => PropertyFormRules.systemKeys.contains(key);
}

/// Etapa do cadastro que tem campo configurável.
class PropertyFormChapter {
  const PropertyFormChapter(this.index, this.name, this.short);
  final int index;
  final String name;
  final String short;
}

/// Leitura de exigência de um recorte de campos.
class PropertyFormReading {
  const PropertyFormReading({
    required this.total,
    required this.system,
    required this.extras,
  });

  final int total;
  final int system;
  final int extras;
  int get required => system + extras;
  int get free => total - required;
}

/// Estado editável da tela "Regras do formulário" (`EstadoDasRegras`).
@immutable
class PropertyFormRulesState {
  const PropertyFormRulesState({
    this.extras = const <String>[],
    this.restrictTeams = false,
    this.allowedTeamIds = const <String>[],
    this.successionTarget = SuccessionTarget.companyOwner,
    this.successorId,
    this.captorAction = CaptorAction.remove,
  });

  final List<String> extras;
  final bool restrictTeams;
  final List<String> allowedTeamIds;
  final SuccessionTarget successionTarget;
  final String? successorId;
  final CaptorAction captorAction;

  /// Monta o estado a partir do que o back devolveu (o `carregar` do web).
  factory PropertyFormRulesState.fromServer({
    required PropertyFormSettingsBundle bundle,
    PropertyApprovalSettingsFull? approval,
  }) {
    return PropertyFormRulesState(
      extras: PropertyFormRules.sanitizeExtras(bundle.requiredFields),
      restrictTeams: bundle.allowedTeamIds.isNotEmpty,
      allowedTeamIds: List<String>.from(bundle.allowedTeamIds),
      successionTarget:
          approval?.onDeactivateAssignTo ?? SuccessionTarget.companyOwner,
      successorId: approval?.onDeactivateUserId,
      captorAction: approval?.onDeactivateCaptorAction ?? CaptorAction.remove,
    );
  }

  PropertyFormRulesState copyWith({
    List<String>? extras,
    bool? restrictTeams,
    List<String>? allowedTeamIds,
    SuccessionTarget? successionTarget,
    String? successorId,
    bool clearSuccessor = false,
    CaptorAction? captorAction,
  }) {
    return PropertyFormRulesState(
      extras: extras ?? this.extras,
      restrictTeams: restrictTeams ?? this.restrictTeams,
      allowedTeamIds: allowedTeamIds ?? this.allowedTeamIds,
      successionTarget: successionTarget ?? this.successionTarget,
      successorId: clearSuccessor ? null : (successorId ?? this.successorId),
      captorAction: captorAction ?? this.captorAction,
    );
  }
}

/// Regras da tela "Regras do formulário" — espelho de
/// `regrasDoFormulario.ts` + `propertyFormConfigurableFields.ts` do web.
class PropertyFormRules {
  PropertyFormRules._();

  /// Obrigatórios pelo sistema (travados; nunca vão para a lista da empresa).
  static const Set<String> systemKeys = {
    'teamId',
    'title',
    'description',
    'type',
    'street',
    'number',
    'neighborhood',
    'city',
    'state',
    'zipCode',
    'capturedByIds',
    'ownerName',
    'ownerPhone',
  };

  static const List<PropertyFormChapter> chapters = [
    PropertyFormChapter(0, 'Informações básicas', 'Básicas'),
    PropertyFormChapter(1, 'Localização', 'Localização'),
    PropertyFormChapter(2, 'Características', 'Características'),
    PropertyFormChapter(3, 'Valores', 'Valores'),
    PropertyFormChapter(6, 'Proprietário', 'Proprietário'),
  ];

  static const List<PropertyFormFieldOption> fields = [
    PropertyFormFieldOption('teamId', 'Equipe', 0),
    PropertyFormFieldOption('title', 'Título', 0),
    PropertyFormFieldOption('description', 'Descrição', 0),
    PropertyFormFieldOption('internalNotes', 'Observações internas', 0),
    PropertyFormFieldOption('type', 'Tipo do imóvel', 0),
    PropertyFormFieldOption('street', 'Logradouro', 1),
    PropertyFormFieldOption('number', 'Número', 1),
    PropertyFormFieldOption('complement', 'Complemento', 1),
    PropertyFormFieldOption('neighborhood', 'Bairro', 1),
    PropertyFormFieldOption('sector', 'Setor', 1),
    PropertyFormFieldOption('city', 'Cidade', 1),
    PropertyFormFieldOption('state', 'Estado', 1),
    PropertyFormFieldOption('zipCode', 'CEP', 1),
    PropertyFormFieldOption('totalArea', 'Área total (m²)', 2),
    PropertyFormFieldOption('builtArea', 'Área construída (m²)', 2),
    PropertyFormFieldOption('bedrooms', 'Quartos', 2),
    PropertyFormFieldOption('suites', 'Suítes', 2),
    PropertyFormFieldOption('bathrooms', 'Banheiros', 2),
    PropertyFormFieldOption('parkingSpaces', 'Vagas', 2),
    PropertyFormFieldOption('salePrice', 'Preço de venda', 3),
    PropertyFormFieldOption('rentPrice', 'Preço de aluguel', 3),
    PropertyFormFieldOption('condominiumFee', 'Condomínio', 3),
    PropertyFormFieldOption('iptu', 'IPTU', 3),
    PropertyFormFieldOption('capturedById', 'Captador (principal)', 0),
    PropertyFormFieldOption('capturedByIds', 'Captadores (lista)', 0),
    PropertyFormFieldOption('ownerName', 'Nome do proprietário', 6),
    PropertyFormFieldOption('ownerEmail', 'E-mail do proprietário', 6),
    PropertyFormFieldOption('ownerPhone', 'Telefone do proprietário', 6),
    PropertyFormFieldOption('ownerDocument', 'Documento do proprietário', 6),
    PropertyFormFieldOption('condominiumId', 'Condomínio', 1),
    PropertyFormFieldOption('empreendimentoId', 'Empreendimento', 1),
    PropertyFormFieldOption('features', 'Características', 2),
  ];

  /// Campos de um capítulo (`null` = todos).
  static List<PropertyFormFieldOption> fieldsOf(int? chapter) => chapter == null
      ? List<PropertyFormFieldOption>.from(fields)
      : fields.where((f) => f.chapter == chapter).toList();

  /// Só chaves configuráveis, sem repetição (`limparExtras`).
  static List<String> sanitizeExtras(Iterable<String> keys) {
    final out = <String>[];
    for (final k in keys) {
      final t = k.trim();
      if (t.isEmpty || systemKeys.contains(t) || out.contains(t)) continue;
      out.add(t);
    }
    return out;
  }

  /// `leituraDoCapitulo` — quantos campos o recorte tem, quantos o sistema
  /// exige e quantos extras a empresa marcou.
  static PropertyFormReading reading(int? chapter, List<String> extras) {
    final list = fieldsOf(chapter);
    final system = list.where((f) => f.isSystem).length;
    final ex =
        list.where((f) => !f.isSystem && extras.contains(f.key)).length;
    return PropertyFormReading(total: list.length, system: system, extras: ex);
  }

  /// Destino = usuário específico exige alguém escolhido.
  static bool successionInvalid(PropertyFormRulesState s) =>
      s.successionTarget == SuccessionTarget.user &&
      (s.successorId ?? '').trim().isEmpty;

  /// Quantas equipes aparecem no seletor com a regra atual.
  static int teamsInPicker(PropertyFormRulesState s, int totalTeams) =>
      s.restrictTeams ? s.allowedTeamIds.length : totalTeams;

  /// "Só as marcadas" sem nenhuma marcada.
  static bool noTeamSelected(PropertyFormRulesState s, int totalTeams) =>
      s.restrictTeams && totalTeams > 0 && s.allowedTeamIds.isEmpty;

  /// A frase curta do destino (`rotuloDoDestino`).
  static String successionLabel(
    PropertyFormRulesState s, {
    String? successorName,
  }) {
    if (s.successionTarget == SuccessionTarget.user) {
      return (successorName ?? '').isNotEmpty
          ? successorName!
          : 'usuário a escolher';
    }
    return (successorName ?? '').isNotEmpty
        ? 'dono da empresa (contingência: $successorName)'
        : 'dono da empresa';
  }

  static String captorLabel(CaptorAction a) =>
      a == CaptorAction.remove ? 'sai da captação' : 'segue como captador';

  /// `alteracoes` do web: cada extra ligado/desligado conta 1; a restrição
  /// conta 1; o conjunto de equipes (com restrição nos dois lados) conta 1;
  /// cada regra da sucessão conta 1.
  static int countChanges(
    PropertyFormRulesState? saved,
    PropertyFormRulesState current,
  ) {
    if (saved == null) return 0;
    var n = 0;
    final a = saved.extras.toSet();
    final b = current.extras.toSet();
    n += a.difference(b).length + b.difference(a).length;
    if (saved.restrictTeams != current.restrictTeams) n += 1;
    if (saved.restrictTeams &&
        current.restrictTeams &&
        !_sameSet(saved.allowedTeamIds, current.allowedTeamIds)) {
      n += 1;
    }
    if (saved.successionTarget != current.successionTarget) n += 1;
    if (_nullIfEmpty(saved.successorId) != _nullIfEmpty(current.successorId)) {
      n += 1;
    }
    if (saved.captorAction != current.captorAction) n += 1;
    return n;
  }

  /// Por que não dá para salvar agora (`motivoDeNaoSalvar`); `null` = pode.
  static String? blockReason(
    PropertyFormRulesState? saved,
    PropertyFormRulesState current,
    int totalTeams,
  ) {
    if (noTeamSelected(current, totalTeams)) {
      return 'Marque ao menos uma equipe ou volte para todas';
    }
    if (successionInvalid(current)) return 'Escolha o sucessor dos imóveis';
    if (countChanges(saved, current) == 0) return 'Nada a salvar';
    return null;
  }

  /// Corpo do `PATCH /properties/approval-settings` (o `salvar` do web).
  static Map<String, dynamic> buildPayload(PropertyFormRulesState s) {
    return <String, dynamic>{
      'propertyFormRequiredFields': sanitizeExtras(s.extras),
      'propertyFormAllowedTeamIds':
          s.restrictTeams ? List<String>.from(s.allowedTeamIds) : <String>[],
      'onDeactivateUserResponsibleAssignTo': s.successionTarget.api,
      'onDeactivateUserResponsibleUserId': _nullIfEmpty(s.successorId),
      'onDeactivateUserCaptorAction': s.captorAction.api,
    };
  }

  static bool _sameSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final s = a.toSet();
    return b.every(s.contains);
  }

  static String? _nullIfEmpty(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

/// Payloads e limites das telas de aprovação / campos protegidos.
class PropertyApprovalRules {
  PropertyApprovalRules._();

  /// Total de campos da whitelist de campos protegidos do back
  /// (`PROTECTED_PROPERTY_FIELD_OPTIONS` do web).
  static const int protectedFieldOptionsCount = 24;

  /// Corpo do "Salvar regras" (`saveRules` do web).
  static Map<String, dynamic> rulesPayload(PropertyApprovalSettingsFull s) {
    return <String, dynamic>{
      'requireApprovalToBeAvailable': s.requireApprovalToBeAvailable,
      'requireApprovalToPublishOnSite': s.requireApprovalToPublishOnSite,
      'requireOwnerAuthorizationToBeAvailable':
          s.requireOwnerAuthorizationToBeAvailable,
      'applyWatermarkToImages': s.applyWatermarkToImages,
      'preservePublicationOnEdit': s.preservePublicationOnEdit,
    };
  }

  /// As regras dos interruptores mudaram desde o que foi salvo?
  static bool rulesDirty(
    PropertyApprovalSettingsFull? saved,
    PropertyApprovalSettingsFull current,
  ) {
    if (saved == null) return false;
    final a = rulesPayload(saved);
    final b = rulesPayload(current);
    return a.keys.any((k) => a[k] != b[k]);
  }

  /// Corpo do "Salvar configuração" dos campos protegidos (preserva a lista
  /// legada de campos, como o web).
  static Map<String, dynamic> protectedFieldsPayload({
    required bool enabled,
    required List<String> fields,
  }) {
    return <String, dynamic>{
      'protectedFieldsEnabled': enabled,
      'protectedFields': List<String>.from(fields),
    };
  }

  /// Mínimo de aprovações: inteiro ≥ 1 (o `Math.max(1, …)` do web).
  static int clampMinApprovals(int? value) =>
      (value == null || value < 1) ? 1 : value;

  /// Corpo do `PUT /properties/approvers/quorum-settings` para um tipo.
  static Map<String, dynamic> quorumPayload(ApproverType type, int value) {
    final v = clampMinApprovals(value);
    return type == ApproverType.publication
        ? <String, dynamic>{'minApprovalsPublication': v}
        : <String, dynamic>{'minApprovalsAvailability': v};
  }
}

/// Papéis na tela "Dados do proprietário" (`visibilidadeDoProprietario.ts`).
enum OwnerDataRole { master, admin, manager, user }

class OwnerDataRules {
  OwnerDataRules._();

  static const List<String> hiddenFields = [
    'nome',
    'e-mail',
    'telefone',
    'documento',
    'endereço',
  ];

  static const List<(String, String)> whereItApplies = [
    (
      'Detalhe do imóvel',
      'a ficha abre com os dados do proprietário em "Dados restritos"',
    ),
    ('Listagem', 'colunas e filtros do proprietário não aparecem'),
    ('Exportação', 'a planilha sai sem as colunas do proprietário'),
  ];

  /// Desconhecido vira corretor (`papelDe`).
  static OwnerDataRole roleOf(String? role) {
    switch ((role ?? '').trim().toLowerCase()) {
      case 'master':
        return OwnerDataRole.master;
      case 'admin':
        return OwnerDataRole.admin;
      case 'manager':
        return OwnerDataRole.manager;
      default:
        return OwnerDataRole.user;
    }
  }

  static String roleLabel(OwnerDataRole r, {bool plural = false}) =>
      switch (r) {
        OwnerDataRole.master => plural ? 'Masters' : 'Master',
        OwnerDataRole.admin => plural ? 'Admins' : 'Admin',
        OwnerDataRole.manager => plural ? 'Gestores' : 'Gestor',
        OwnerDataRole.user => plural ? 'Corretores' : 'Corretor',
      };

  /// Admin e master veem pelo papel, sem estar na lista.
  static bool seesByRole(String? role) {
    final r = roleOf(role);
    return r == OwnerDataRole.master || r == OwnerDataRole.admin;
  }

  static Map<OwnerDataRole, int> countByRole(
    Iterable<PropertySettingsMember> users,
  ) {
    final c = {for (final r in OwnerDataRole.values) r: 0};
    for (final u in users) {
      final r = roleOf(u.role);
      c[r] = c[r]! + 1;
    }
    return c;
  }

  /// Busca por nome ou e-mail, sem acento e sem caixa, no papel escolhido
  /// (`null` = todos).
  static List<PropertySettingsMember> filter(
    Iterable<PropertySettingsMember> users,
    String query, {
    OwnerDataRole? role,
  }) {
    final q = fold(query.trim());
    return users
        .where((u) =>
            (role == null || roleOf(u.role) == role) &&
            (q.isEmpty || fold(u.name).contains(q) || fold(u.email).contains(q)))
        .toList();
  }

  static const Map<String, String> _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
    'ç': 'c', 'ñ': 'n',
  };

  /// Minúsculas e sem acento.
  static String fold(String s) {
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      b.write(_accents[ch] ?? ch);
    }
    return b.toString();
  }
}

/// Iniciais para avatar ("Maria Souza" → "MS").
String propertySettingsInitials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Quem abre cada tela — funções puras (papel + permissões explícitas +
/// módulo) para os gates do hub e para os testes.
///
/// Regra do back (`PermissionsGuard`): master passa em tudo, admin em tudo
/// menos `user:create`, gestor só na lista curta de `role_access_rules`
/// (que NÃO inclui `property:manage_approval_settings`). O web esconde
/// "Regras do formulário" com `noRoleBypass`, mas o `hasPermission` dele
/// ainda libera master/admin — então as três telas de regra abrem para
/// master, admin ou quem tem a permissão explícita, igual ao back.
class PropertySettingsGates {
  PropertySettingsGates._();

  static const String moduleId = 'property_management';

  static bool _hasExplicit(List<String> explicit, String permission) =>
      explicit.contains(permission);

  /// `property:manage_approval_settings` com o bypass do back.
  static bool canManageApprovalSettings({
    required String? role,
    required List<String> explicitPermissions,
    required bool moduleAvailable,
  }) {
    if (!moduleAvailable) return false;
    const p = AppPermissions.propertyManageApprovalSettings;
    return roleBypassesPermission(role, p) ||
        _hasExplicit(explicitPermissions, p);
  }

  /// "Dados do proprietário": admin/master OU permissão explícita
  /// `property:view_protected_owner_data` (o `assertCanView` do back).
  static bool canViewOwnerData({
    required String? role,
    required List<String> explicitPermissions,
    required bool moduleAvailable,
  }) {
    if (!moduleAvailable) return false;
    final r = (role ?? '').trim().toLowerCase();
    if (r == 'master' || r == 'admin') return true;
    return _hasExplicit(
      explicitPermissions,
      AppPermissions.propertyViewProtectedOwnerData,
    );
  }

  /// Habilitar/remover na lista: só admin/master (`@Roles` do back).
  static bool canManageOwnerData(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'master' || r == 'admin';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Serviço
// ═══════════════════════════════════════════════════════════════════════════

/// Leitura e escrita das configurações de imóveis. Nenhum método lança:
/// toda falha volta no [ApiResponse] (status 0 = sem conexão, -1 = falha
/// local) com a `message` do servidor quando houver.
class PropertySettingsService {
  PropertySettingsService._();

  static final PropertySettingsService instance = PropertySettingsService._();

  final ApiService _api = ApiService.instance;

  // ─── Regras de aprovação / formulário ─────────────────────────────────

  /// `GET /properties/approval-settings` (manage_approval_settings).
  Future<ApiResponse<PropertyApprovalSettingsFull>> getApprovalSettings() =>
      _getObject(
        '/properties/approval-settings',
        PropertyApprovalSettingsFull.fromJson,
        tag: 'approval-settings',
      );

  /// `PATCH /properties/approval-settings` — só os campos enviados mudam.
  Future<ApiResponse<PropertyApprovalSettingsFull>> updateApprovalSettings(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _api.patch<dynamic>(
        '/properties/approval-settings',
        body: payload,
      );
      if (!res.success) return _fail(res);
      final map = _unwrap(res.data);
      return ApiResponse.success(
        data: map == null ? null : PropertyApprovalSettingsFull.fromJson(map),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SETTINGS] patch approval-settings: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  /// `GET /properties/form-settings` — campos extras, equipes permitidas e
  /// (para quem gerencia) todas as equipes da empresa.
  Future<ApiResponse<PropertyFormSettingsBundle>> getFormSettings() =>
      _getObject(
        '/properties/form-settings',
        PropertyFormSettingsBundle.fromJson,
        tag: 'form-settings',
      );

  // ─── Aprovadores ──────────────────────────────────────────────────────

  /// `GET /properties/approvers?type=`.
  Future<ApiResponse<List<PropertyApproverConfig>>> listApprovers(
    ApproverType type,
  ) async {
    try {
      final res = await _api.get<dynamic>(
        '/properties/approvers',
        queryParameters: {'type': type.api},
      );
      if (!res.success) return _fail(res);
      final list = _asList(res.data)
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map((j) => PropertyApproverConfig.fromJson(j, fallbackType: type))
          .where((a) => a.id.isNotEmpty && a.userId.isNotEmpty)
          .toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      return ApiResponse.success(data: list, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPERTY_SETTINGS] approvers: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  /// `POST /properties/approvers` — adiciona (ou atualiza) e concede as
  /// permissões de aprovar/recusar daquele tipo.
  Future<ApiResponse<void>> upsertApprover({
    required String userId,
    required ApproverType type,
    bool? isRequired,
    int? displayOrder,
  }) =>
      _write('POST', '/properties/approvers', {
        'userId': userId,
        'approvalType': type.api,
        'isRequired': ?isRequired,
        if (displayOrder != null) 'displayOrder': displayOrder < 0 ? 0 : displayOrder,
      });

  /// `DELETE /properties/approvers/:configId`.
  Future<ApiResponse<void>> removeApprover(String configId) =>
      _write('DELETE', '/properties/approvers/$configId', null);

  /// `POST /properties/approvers/revoke-user-permission` — tira da lista e
  /// revoga as permissões diretas daquele tipo.
  Future<ApiResponse<void>> revokeUserApprovalPermission({
    required String userId,
    required ApproverType type,
  }) =>
      _write('POST', '/properties/approvers/revoke-user-permission', {
        'userId': userId,
        'approvalType': type.api,
      });

  /// `PUT /properties/approvers/quorum-settings` — devolve as configurações
  /// atualizadas.
  Future<ApiResponse<PropertyApprovalSettingsFull>> updateQuorumSettings(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _api.put<dynamic>(
        '/properties/approvers/quorum-settings',
        body: payload,
      );
      if (!res.success) return _fail(res);
      final map = _unwrap(res.data);
      return ApiResponse.success(
        data: map == null ? null : PropertyApprovalSettingsFull.fromJson(map),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SETTINGS] quorum: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  /// `GET /properties/approvers/authorized-users`.
  Future<ApiResponse<PropertyAuthorizedApprovers>> listAuthorizedApprovers() =>
      _getObject(
        '/properties/approvers/authorized-users',
        PropertyAuthorizedApprovers.fromJson,
        tag: 'authorized-users',
      );

  // ─── Membros ──────────────────────────────────────────────────────────

  /// `GET /users/company-members/simple` — membros ATIVOS da empresa.
  Future<ApiResponse<List<PropertySettingsMember>>> listCompanyMembers() =>
      _getMembers('/users/company-members/simple', tag: 'company-members');

  // ─── Catálogo extra do cadastro ───────────────────────────────────────

  /// `GET /property-catalog`.
  Future<ApiResponse<List<PropertyCatalogEntry>>> listCatalog() async {
    try {
      final res = await _api.get<dynamic>('/property-catalog');
      if (!res.success) return _fail(res);
      final list = _asList(res.data)
          .map(PropertyCatalogEntry.tryParse)
          .whereType<PropertyCatalogEntry>()
          .toList();
      return ApiResponse.success(data: list, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPERTY_SETTINGS] catalog: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  /// `POST /property-catalog` `{ kind, name }` (nome até 80, único por tipo).
  Future<ApiResponse<PropertyCatalogEntry>> createCatalogItem(
    CatalogKind kind,
    String name,
  ) =>
      _catalogWrite(
        'POST',
        '/property-catalog',
        {'kind': kind.api, 'name': name.trim()},
      );

  /// `PATCH /property-catalog/:id` `{ name }`.
  Future<ApiResponse<PropertyCatalogEntry>> renameCatalogItem(
    String id,
    String name,
  ) =>
      _catalogWrite('PATCH', '/property-catalog/$id', {'name': name.trim()});

  /// `DELETE /property-catalog/:id`.
  Future<ApiResponse<void>> deleteCatalogItem(String id) =>
      _write('DELETE', '/property-catalog/$id', null);

  // ─── Dados do proprietário (restritos) ────────────────────────────────

  /// `GET /protected-owner-data/users` (`{ data: [...] }`).
  Future<ApiResponse<List<PropertySettingsMember>>> listOwnerDataUsers() =>
      _getMembers('/protected-owner-data/users', tag: 'owner-data users');

  /// `GET /protected-owner-data/scope` — 404 em back antigo.
  Future<ApiResponse<OwnerDataScope>> getOwnerDataScope() => _getObject(
        '/protected-owner-data/scope',
        OwnerDataScope.fromJson,
        tag: 'owner-data scope',
      );

  /// `POST /protected-owner-data/users/:userId` (só admin/master).
  Future<ApiResponse<void>> enableOwnerDataUser(String userId) =>
      _write('POST', '/protected-owner-data/users/$userId', null);

  /// `DELETE /protected-owner-data/users/:userId` (só admin/master).
  Future<ApiResponse<void>> disableOwnerDataUser(String userId) =>
      _write('DELETE', '/protected-owner-data/users/$userId', null);

  // ─── Internos ─────────────────────────────────────────────────────────

  Future<ApiResponse<T>> _getObject<T>(
    String endpoint,
    T Function(Map<String, dynamic>) parse, {
    required String tag,
  }) async {
    try {
      final res = await _api.get<dynamic>(endpoint);
      if (!res.success) return _fail(res);
      final map = _unwrap(res.data);
      if (map == null) {
        return ApiResponse.error(
          message: 'Resposta inesperada do servidor.',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: parse(map), statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPERTY_SETTINGS] $tag: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  Future<ApiResponse<List<PropertySettingsMember>>> _getMembers(
    String endpoint, {
    required String tag,
  }) async {
    try {
      final res = await _api.get<dynamic>(endpoint);
      if (!res.success) return _fail(res);
      final list = _asList(res.data)
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(PropertySettingsMember.fromJson)
          .where((u) => u.id.isNotEmpty)
          .toList()
        ..sort((a, b) => OwnerDataRules.fold(a.name)
            .compareTo(OwnerDataRules.fold(b.name)));
      return ApiResponse.success(data: list, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [PROPERTY_SETTINGS] $tag: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  Future<ApiResponse<PropertyCatalogEntry>> _catalogWrite(
    String method,
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final res = await _send(method, endpoint, body);
    if (!res.success) return _fail(res);
    return ApiResponse.success(
      data: PropertyCatalogEntry.tryParse(_unwrap(res.data)),
      statusCode: res.statusCode,
    );
  }

  Future<ApiResponse<void>> _write(
    String method,
    String endpoint,
    Map<String, dynamic>? body,
  ) async {
    final res = await _send(method, endpoint, body);
    if (!res.success) return _fail(res);
    return ApiResponse.success(statusCode: res.statusCode);
  }

  Future<ApiResponse<dynamic>> _send(
    String method,
    String endpoint,
    Map<String, dynamic>? body,
  ) async {
    try {
      switch (method) {
        case 'PATCH':
          return await _api.patch<dynamic>(endpoint, body: body);
        case 'PUT':
          return await _api.put<dynamic>(endpoint, body: body);
        case 'DELETE':
          return await _api.delete<dynamic>(endpoint, body: body);
        default:
          return await _api.post<dynamic>(endpoint, body: body);
      }
    } catch (e) {
      debugPrint('❌ [PROPERTY_SETTINGS] $method $endpoint: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  ApiResponse<T> _fail<T>(ApiResponse<dynamic> res) => ApiResponse<T>.error(
        message: res.message ?? '',
        statusCode: res.statusCode,
        data: res.error,
      );
}
