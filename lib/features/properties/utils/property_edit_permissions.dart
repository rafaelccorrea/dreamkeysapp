import '../../../shared/services/property_service.dart' show Property;

/// Espelha as regras do backend (`PropertiesService.assertUserMayEditPropertyEntity`)
/// e do frontend web (`imobx-front/src/utils/propertyEditPermissions.ts`) para
/// decidir se o usuário logado pode editar/excluir um imóvel a partir do mobile.
///
/// Regra resumida (mesma da API):
/// - `master` / `admin` / `manager` sempre podem editar e excluir.
/// - Quem tem qualquer permissão da matriz de aprovação (`property:manage_approval_settings`,
///   `property:approve_availability`, `property:reject_availability`,
///   `property:approve_publication`, `property:reject_publication`) sempre pode.
/// - Após a assinatura da autorização de venda / contrato de agenciamento
///   (`ownerAuthStatus == 'signed'` ou `ownerAuthSignedAt != null`), responsável
///   e captador deixam de editar a ficha — apenas gestão e aprovadores.
/// - Caso contrário, usuário comum só pode editar/excluir se for responsável
///   principal (`responsibleUserId`), captador principal (`capturedById`),
///   responsável adicional (`responsibleUserIds`) ou captador adicional
///   (`capturedByIds`) do cadastro.
/// - Ter apenas `property:update` sem nenhum vínculo nem papel acima NÃO
///   autoriza alterar imóvel de terceiros.

/// Permissões da matriz de aprovação que dão direito a editar qualquer imóvel.
const List<String> propertyApproverMatrixPermissions = [
  'property:manage_approval_settings',
  'property:approve_availability',
  'property:reject_availability',
  'property:approve_publication',
  'property:reject_publication',
];

/// Mensagem padrão exibida quando responsável/captador fica bloqueado após
/// assinatura da autorização de venda / agenciamento. Espelha a string da API.
const String propertyOwnerSignedAgencyEditRestrictionMessage =
    'A autorização de venda do proprietário (contrato de agenciamento) já foi '
    'assinada. Somente gestores, administradores ou usuários com permissão de '
    'aprovação podem editar a ficha.';

/// Mensagem para usuário comum sem vínculo (não é responsável nem captador).
const String propertyNotLinkedEditRestrictionMessage =
    'Sem permissão para alterar este imóvel. Apenas responsáveis ou captadores '
    'do cadastro, gestores, administradores (ou quem tem permissão nas filas '
    'de aprovação) podem alterar.';

/// Roles "de gestão" que sempre podem editar a ficha — inclusive imóveis já
/// aprovados ou com autorização do proprietário assinada.
bool isManagementRole(String? userRole) {
  final r = userRole?.toLowerCase().trim() ?? '';
  return r == 'master' || r == 'admin' || r == 'manager';
}

/// Tem qualquer permissão da matriz de aprovação (gerenciar configurações
/// ou aprovar/rejeitar disponibilidade/publicação).
bool hasPropertyApproverMatrixPermission(
  bool Function(String permission) hasPermission,
) {
  for (final p in propertyApproverMatrixPermissions) {
    if (hasPermission(p)) return true;
  }
  return false;
}

/// Após a assinatura da autorização de venda / contrato de agenciamento,
/// responsáveis e captadores deixam de editar a ficha (só gestão e aprovadores).
bool isPropertyEditLockedForLinkedUsersAfterOwnerSignedAgency(
  Property? property,
) {
  if (property == null) return false;
  if ((property.ownerAuthStatus ?? '').toLowerCase() == 'signed') {
    return true;
  }
  final signedAt = property.ownerAuthSignedAt?.trim() ?? '';
  return signedAt.isNotEmpty;
}

/// Indica se o usuário figura como responsável (principal/adicional) ou
/// captador (principal/adicional) do imóvel.
bool isUserLinkedAsResponsibleOrCaptor(
  Property property,
  String? userId,
) {
  final id = userId?.trim() ?? '';
  if (id.isEmpty) return false;
  if (property.responsibleUserId == id) return true;
  if (property.capturedById == id) return true;
  if (property.responsibleUserIds?.contains(id) == true) return true;
  if (property.capturedByIds?.contains(id) == true) return true;
  return false;
}

/// Resultado da verificação detalhada — útil para também exibir mensagem/tooltip
/// alinhada à API quando o botão estiver desabilitado.
class PropertyEditPermissionResult {
  final bool canEdit;
  final bool isManagement;
  final bool isApprover;
  final bool isLinked;
  final bool ownerSignedLockApplied;

  const PropertyEditPermissionResult({
    required this.canEdit,
    required this.isManagement,
    required this.isApprover,
    required this.isLinked,
    required this.ownerSignedLockApplied,
  });

  /// Quando o motivo é a autorização do proprietário assinada, e o usuário
  /// tinha vínculo com o cadastro, devolvemos a mensagem específica para
  /// orientar o corretor (igual à do backend / web).
  String? get reasonMessage {
    if (canEdit) return null;
    if (ownerSignedLockApplied && isLinked) {
      return propertyOwnerSignedAgencyEditRestrictionMessage;
    }
    return propertyNotLinkedEditRestrictionMessage;
  }
}

/// Computa, com a mesma lógica do backend, se o usuário pode alterar a ficha
/// deste imóvel.
PropertyEditPermissionResult evaluatePropertyEditPermission({
  required Property? property,
  required String? currentUserId,
  required String? userRole,
  required bool Function(String permission) hasPermission,
}) {
  final isManagement = isManagementRole(userRole);
  if (property == null) {
    return PropertyEditPermissionResult(
      canEdit: isManagement,
      isManagement: isManagement,
      isApprover: false,
      isLinked: false,
      ownerSignedLockApplied: false,
    );
  }

  final isApprover = hasPropertyApproverMatrixPermission(hasPermission);
  if (isManagement || isApprover) {
    return PropertyEditPermissionResult(
      canEdit: true,
      isManagement: isManagement,
      isApprover: isApprover,
      isLinked: isUserLinkedAsResponsibleOrCaptor(property, currentUserId),
      ownerSignedLockApplied: false,
    );
  }

  final ownerLocked =
      isPropertyEditLockedForLinkedUsersAfterOwnerSignedAgency(property);
  final linked = isUserLinkedAsResponsibleOrCaptor(property, currentUserId);

  if (ownerLocked) {
    return PropertyEditPermissionResult(
      canEdit: false,
      isManagement: false,
      isApprover: false,
      isLinked: linked,
      ownerSignedLockApplied: true,
    );
  }

  return PropertyEditPermissionResult(
    canEdit: linked,
    isManagement: false,
    isApprover: false,
    isLinked: linked,
    ownerSignedLockApplied: false,
  );
}

/// Atalho booleano: pode alterar a ficha deste imóvel (PATCH/DELETE/status/etc).
bool canUserEditThisPropertyRecord({
  required Property? property,
  required String? currentUserId,
  required String? userRole,
  required bool Function(String permission) hasPermission,
}) {
  return evaluatePropertyEditPermission(
    property: property,
    currentUserId: currentUserId,
    userRole: userRole,
    hasPermission: hasPermission,
  ).canEdit;
}

/// Pode excluir o imóvel: além das regras de edição, é necessário ter a
/// permissão `property:delete` (ou ser gestão, que sempre tem bypass).
bool canUserDeleteThisPropertyRecord({
  required Property? property,
  required String? currentUserId,
  required String? userRole,
  required bool Function(String permission) hasPermission,
}) {
  if (!canUserEditThisPropertyRecord(
    property: property,
    currentUserId: currentUserId,
    userRole: userRole,
    hasPermission: hasPermission,
  )) {
    return false;
  }
  if (isManagementRole(userRole)) return true;
  return hasPermission('property:delete');
}
