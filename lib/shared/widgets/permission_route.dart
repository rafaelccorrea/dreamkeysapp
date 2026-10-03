import 'package:flutter/material.dart';
import '../services/module_access_service.dart';
import 'app_error_state.dart';

/// Wrapper de rota que verifica módulo e permissões antes de renderizar.
/// Similar ao `ModuleRoute` + `PermissionRoute` do web.
///
/// Sem acesso, mostra o estado de "sem permissão"/"fora do plano" em vez da
/// tela — que só daria 403 (transv-25, 03/10/2026). Antes devolvia uma tela
/// em branco.
class PermissionRoute extends StatelessWidget {
  final Widget child;
  final String? permission;
  final List<String>? permissions;
  final bool requireAll;

  /// Módulo da empresa exigido (`ModuleRoute requiredModule` do web).
  final String? module;

  const PermissionRoute({
    super.key,
    required this.child,
    this.permission,
    this.permissions,
    this.requireAll = false,
    this.module,
  }) : assert(
          permission != null || permissions != null || module != null,
          'Deve fornecer permission, permissions ou module',
        );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModuleAccessService.instance,
      builder: (context, _) {
        final moduleAccess = ModuleAccessService.instance;

        final moduleOk =
            module == null || moduleAccess.isModuleAvailableForCompany(module!);

        bool permissionOk = true;
        if (permission != null) {
          permissionOk = moduleAccess.hasPermission(permission!);
        } else if (permissions != null && permissions!.isNotEmpty) {
          permissionOk = requireAll
              ? moduleAccess.hasAllPermissions(permissions!)
              : moduleAccess.hasAnyPermission(permissions!);
        }

        if (moduleOk && permissionOk) return child;

        // Mesmas frases do back (ModuleAccessGuard / PermissionsGuard).
        final message = !moduleOk
            ? 'Este recurso não está incluído no plano atual da empresa. Para liberá-lo, fale com o seu gestor ou com o suporte.'
            : 'Você não tem permissão para acessar esta tela. Para liberar o acesso, fale com o seu gestor ou com o suporte.';
        return Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            child: AppErrorState.fromApi(message: message, statusCode: 403),
          ),
        );
      },
    );
  }
}
