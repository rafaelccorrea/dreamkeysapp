import '../../../core/constants/app_permissions.dart';
import '../../../shared/services/module_access_service.dart';

/// Regras de acesso do check-in — espelho do web e do back (03/10/2026,
/// checkin-04/05 e transv-08):
///
/// - Módulo: o `CheckInController` do back tem `@RequireModule(VISIT_REPORT)`
///   e o web só monta `/check-in` dentro de `ModuleRoute visit_report`
///   (`kanban.routes.tsx`, `useCheckInStatus`). Empresa sem o módulo toma 403.
/// - Permissão: o `PermissionsGuard` do back só dá bypass a master e admin —
///   gestor (`manager`) precisa da permissão explícita. Por isso aqui NÃO se
///   usa o `hasPermission` do `ModuleAccessService`, que libera `manager`.
/// - Histórico (`/check-in/list`): `check_in:view` (PermissionRoute do web).
/// - Gestão: admin/master ou `check_in:manage_settings` (`CheckInPage.tsx`).
class CheckInAccess {
  CheckInAccess._();

  static const String module = 'visit_report';

  static String get _role =>
      ModuleAccessService.instance.userRole?.toLowerCase().trim() ?? '';

  static bool get _isMaster => _role == 'master';

  /// Master e admin: bypass do `PermissionsGuard` do back.
  static bool get _hasRoleBypass => _role == 'master' || _role == 'admin';

  static bool _explicit(String permission) => ModuleAccessService
      .instance
      .userPermissionNames
      .contains(permission);

  /// Empresa tem o módulo `visit_report` (master passa).
  static bool get moduleAvailable =>
      _isMaster ||
      ModuleAccessService.instance.companyModules.contains(module);

  /// Item "Check-in" no menu: módulo + alguma permissão de check-in.
  static bool get canSeeCheckIn =>
      moduleAvailable &&
      (_hasRoleBypass ||
          _explicit(AppPermissions.checkInDo) ||
          _explicit(AppPermissions.checkInView) ||
          _explicit(AppPermissions.checkInManageSettings));

  /// Histórico de check-ins (`GET /check-in/list` exige `check_in:view`).
  static bool get canViewHistory =>
      _hasRoleBypass || _explicit(AppPermissions.checkInView);

  /// Gestão (agir sobre o check-in de outras pessoas, configurações).
  static bool get canManage =>
      _hasRoleBypass || _explicit(AppPermissions.checkInManageSettings);
}
