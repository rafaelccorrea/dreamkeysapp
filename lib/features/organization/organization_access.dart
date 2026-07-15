import '../../shared/services/module_access_service.dart';

/// Acesso do domínio **Organização** (Unidades, Hierarquia, Backups).
///
/// Strings 1:1 com o web (`imobx-front/src/components/layout/Drawer.tsx` e
/// `imobx/src/enums/permission.enum.ts`). Mantidas privadas à feature — a
/// fiação central (drawer/app_permissions) é feita fora daqui.
class OrganizationAccess {
  OrganizationAccess._();

  // ─── Permissões (permission.enum.ts) ─────────────────────────────────────
  static const String unitView = 'unit:view';
  static const String unitManage = 'unit:manage';
  static const String backupView = 'backup:view';

  // ─── Módulos da empresa ───────────────────────────────────────────────────
  static const String moduleTeamManagement = 'team_management';
  static const String moduleUserManagement = 'user_management';

  /// Unidades: módulo `team_management` + `unit:view` (paridade Drawer web).
  static bool canViewUnits() =>
      ModuleAccessService.instance.hasCompanyModule(moduleTeamManagement) &&
      ModuleAccessService.instance.hasPermission(unitView);

  /// CRUD de unidades exige `unit:manage` (guard do `UnitsController`).
  static bool canManageUnits() =>
      ModuleAccessService.instance.hasPermission(unitManage);

  /// Hierarquia: módulo `user_management` + role admin/master
  /// (paridade `canManageHierarchy` + `roleRequired` do Drawer web).
  static bool canViewHierarchy() {
    final role = ModuleAccessService.instance.userRole?.toLowerCase();
    final roleOk = role == 'admin' || role == 'master';
    return roleOk &&
        ModuleAccessService.instance.hasCompanyModule(moduleUserManagement);
  }

  /// Backups: permissão `backup:view` (o web usa `noRoleBypass`; aqui o
  /// `hasPermission` tem bypass de role — o backend continua sendo a
  /// autoridade e nega com 403 quando a permissão real não existir).
  static bool canViewBackups() =>
      ModuleAccessService.instance.hasPermission(backupView);
}
