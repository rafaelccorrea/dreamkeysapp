import 'package:flutter/material.dart';

import '../../../core/theme/theme_helpers.dart';

/// Estado de tela bloqueada do módulo de documentos — cadeado com o motivo,
/// no lugar de deixar o usuário descobrir pelo 403 da API. O web barra as
/// mesmas rotas com `ModuleRoute('document_management')` + a permissão.
class DocumentAccessLocked extends StatelessWidget {
  final String title;
  final String message;

  const DocumentAccessLocked({
    super.key,
    this.title = 'Acesso restrito',
    this.message =
        'Você não tem permissão para acessar os documentos desta empresa. '
            'Peça a um administrador para liberar o acesso.',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 44, color: muted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
