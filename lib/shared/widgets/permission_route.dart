import 'package:flutter/material.dart';
import '../services/module_access_service.dart';

/// Wrapper de rota que verifica permissões antes de renderizar
/// Similar ao PermissionRoute do React
class PermissionRoute extends StatelessWidget {
  final Widget child;
  final String? permission;
  final List<String>? permissions;
  final bool requireAll;

  const PermissionRoute({
    super.key,
    required this.child,
    this.permission,
    this.permissions,
    this.requireAll = false,
  }) : assert(
          permission != null || permissions != null,
          'Deve fornecer permission ou permissions',
        );

  @override
  Widget build(BuildContext context) {
    final moduleAccess = ModuleAccessService.instance;
    bool hasAccess = false;

    if (permission != null) {
      hasAccess = moduleAccess.hasPermission(permission!);
    } else if (permissions != null && permissions!.isNotEmpty) {
      hasAccess = requireAll
          ? moduleAccess.hasAllPermissions(permissions!)
          : moduleAccess.hasAnyPermission(permissions!);
    }

    // Se não tem acesso, não renderiza nada (retorna null)
    if (!hasAccess) {
      return const SizedBox.shrink();
    }

    return child;
  }
}












