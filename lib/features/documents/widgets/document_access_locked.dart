import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

/// Por que a tela está travada — muda o selo e a cor; o texto vem de quem
/// chama.
enum DocumentLockReason {
  /// Falta módulo/permissão: violeta, a mesma família do erro de permissão
  /// do app (`AppErrorState`) — só um administrador resolve.
  permission,

  /// O documento não foi encontrado (removido ou fora do alcance): neutro.
  unavailable,
}

/// Estado de tela bloqueada do módulo de documentos — cadeado com o motivo,
/// no lugar de deixar o usuário descobrir pelo 403 da API. O web barra as
/// mesmas rotas com `ModuleRoute('document_management')` + a permissão.
///
/// Estrutura igual à do estado de erro do app: selo tonal, título, motivo e
/// o próximo passo destacado numa faixa ([hint]) — quem lê sabe o que houve
/// e quem libera, sem botão de "tentar de novo" que não resolveria nada.
class DocumentAccessLocked extends StatelessWidget {
  final String title;
  final String message;

  /// Próximo passo (quem libera / o que fazer). `null` esconde a faixa.
  final String? hint;
  final DocumentLockReason reason;

  const DocumentAccessLocked({
    super.key,
    this.title = 'Acesso restrito',
    this.message =
        'Você não tem permissão para acessar os documentos desta empresa.',
    this.hint = 'Peça a um administrador da empresa para liberar o acesso.',
    this.reason = DocumentLockReason.permission,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final permission = reason == DocumentLockReason.permission;
    final tone = permission
        ? (dark ? AppColors.status.purpleDarkMode : AppColors.status.purple)
        : muted;
    final next = hint?.trim() ?? '';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: dark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: tone.withValues(alpha: 0.30)),
                ),
                child: Icon(
                  permission
                      ? Icons.lock_outline_rounded
                      : Icons.search_off_rounded,
                  size: 26,
                  color: tone,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted,
                  height: 1.45,
                ),
              ),
              if (next.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: dark ? 0.12 : 0.07),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: tone.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: tone,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          next,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            color: text.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
