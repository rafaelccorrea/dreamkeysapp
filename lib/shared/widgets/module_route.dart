import 'package:flutter/material.dart';
import '../services/module_access_service.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';

/// Wrapper de rota que verifica módulo antes de renderizar
/// Similar ao ModuleRoute do React
class ModuleRoute extends StatelessWidget {
  final Widget child;
  final String requiredModule;
  final String? redirectTo;
  final bool showToast;

  const ModuleRoute({
    super.key,
    required this.child,
    required this.requiredModule,
    this.redirectTo,
    this.showToast = true,
  });

  @override
  Widget build(BuildContext context) {
    final moduleAccess = ModuleAccessService.instance;
    final isAvailable = moduleAccess.isModuleAvailableForCompany(requiredModule);
    final hasPermission = moduleAccess.hasPermissionForModule(requiredModule);

    if (!isAvailable || !hasPermission) {
      // Redirecionar após frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (showToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Módulo não disponível ou sem permissão de acesso',
              ),
              backgroundColor: AppColors.status.error,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }

        final route = redirectTo ?? AppRoutes.home;
        Navigator.of(context).pushNamedAndRemoveUntil(
          route,
          (route) => false,
        );
      });

      // Mostrar loading enquanto redireciona
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return child;
  }
}








