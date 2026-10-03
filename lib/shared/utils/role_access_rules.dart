/// Bypass de papel — espelho EXATO dos guards do back (transv-03/transv-04,
/// paridade 03/10/2026). Antes o app liberava tudo para master, admin e
/// manager (permissão E módulo), e o gestor/admin via botões e menus que o
/// back recusava com 403.
///
/// - `PermissionsGuard` (`intellisys-CRM-Back/src/auth/permissions.guard.ts`):
///   master passa em tudo; admin passa em tudo menos `user:create`; manager
///   só passa sem permissão explícita em [kManagerBypassPermissions] (cada
///   requisito precisa estar nessa lista).
/// - `ModuleAccessGuard` + `CompaniesService.checkModuleAccess`: só master
///   ignora o módulo; admin e manager dependem de `availableModules`.
library;

/// Permissões que o admin NÃO herda pelo papel.
const Set<String> kAdminExplicitPermissions = {'user:create'};

/// Permissões que o manager herda pelo papel (back, `PermissionsGuard`).
const Set<String> kManagerBypassPermissions = {
  'performance:view_company',
  'property:update',
  'property:delete',
  'property:approve_publication',
  'property:reject_publication',
};

String _norm(String? role) => (role ?? '').trim().toLowerCase();

/// O papel libera [permission] sem ela estar na lista do usuário?
bool roleBypassesPermission(String? role, String permission) {
  switch (_norm(role)) {
    case 'master':
      return true;
    case 'admin':
      return !kAdminExplicitPermissions.contains(permission);
    case 'manager':
      return kManagerBypassPermissions.contains(permission);
    default:
      return false;
  }
}

/// O papel ignora o módulo da empresa? (só master, como no back)
bool roleBypassesModule(String? role) => _norm(role) == 'master';

/// Papel com bypass amplo ANTES de a empresa carregar — usado só enquanto
/// os módulos ainda não chegaram, para não esconder a tela inteira de quem
/// tem acesso (o back continua sendo quem decide).
bool roleIsElevated(String? role) {
  final r = _norm(role);
  return r == 'master' || r == 'admin' || r == 'manager';
}
