import 'package:flutter/material.dart';
import '../services/module_access_service.dart';

/// Guard que verifica módulo e mostra conteúdo apenas se disponível
/// Similar ao ModuleGuard do React
class ModuleGuard extends StatelessWidget {
  final Widget child;
  final String module;
  final Widget? fallback;

  const ModuleGuard({
    super.key,
    required this.child,
    required this.module,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final moduleAccess = ModuleAccessService.instance;
    final isAvailable = moduleAccess.isModuleAvailableForCompany(module) &&
        moduleAccess.hasPermissionForModule(module);

    if (!isAvailable) {
      return fallback ?? const SizedBox.shrink();
    }

    return child;
  }
}




