import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helpers.dart';
import '../../shared/services/module_access_service.dart';
import '../sale_forms/ficha_draft_store.dart';
import 'pages/create_proposal_page.dart';
import 'utils/proposal_draft.dart';

/// Resposta do diálogo de rascunho ao tocar "Nova proposta".
enum _EscolhaRascunho { retomar, nova, descartar }

/// "Nova proposta" da lista (web `iniciarNovaProposta`): confere
/// `proposal:create`, pergunta pelo rascunho em aberto e abre a criação.
/// Usado pela lista e pelo deep link `/fichas-proposta/nova`.
Future<void> abrirNovaProposta(BuildContext context) async {
  await abrirNovaPropostaComRetorno(context);
}

/// Igual a [abrirNovaProposta], devolvendo `true` quando a proposta foi
/// criada (a lista recarrega).
Future<bool> abrirNovaPropostaComRetorno(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!ModuleAccessService.instance.hasPermission('proposal:create')) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'Criar fichas de proposta depende de permissão. Peça ao '
          'administrador da empresa.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }
  // "Retomar rascunho" (web `PurchaseProposalsPage`): proposta começada e
  // não criada fica no aparelho; com rascunho em aberto, pergunta antes.
  Map<String, dynamic>? rascunho;
  final draft = await FichaDraftStore.instance.ler(kProposalDraftTipo);
  if (!context.mounted) return false;
  if (draft != null) {
    final escolha = await _perguntarRascunho(context, draft);
    if (escolha == null || !context.mounted) return false;
    if (escolha == _EscolhaRascunho.retomar) {
      rascunho = draft.data;
    } else if (escolha == _EscolhaRascunho.descartar) {
      await FichaDraftStore.instance.limpar(kProposalDraftTipo);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Rascunho descartado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    // "Começar nova": o rascunho fica até a nova ser preenchida (web).
  }
  if (!context.mounted) return false;
  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => CreateProposalPage(rascunho: rascunho)),
  );
  return created == true;
}

/// Diálogo do web "Você tem uma proposta em rascunho": Retomar rascunho /
/// Começar nova (+ Descartar, o ✕ do CTA do web). `null` = fechou.
Future<_EscolhaRascunho?> _perguntarRascunho(
  BuildContext context,
  FichaDraft draft,
) {
  final quando = DateFormat("dd/MM 'às' HH:mm", 'pt_BR').format(draft.savedAt);
  final resumo = proposalDraftResumo(draft.data);
  final accent = Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
  return showDialog<_EscolhaRascunho>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
      icon: Icon(LucideIcons.fileClock, color: accent),
      title: const Text('Você tem uma proposta em rascunho'),
      content: Text(
        'Salva em $quando.${resumo.isEmpty ? '' : '\n$resumo'}\n\n'
        'O que você já preencheu continua salvo. Se começar uma proposta '
        'nova, ela substitui esse rascunho assim que você começar a '
        'preenchê-la.',
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(_EscolhaRascunho.descartar),
          style: TextButton.styleFrom(
            foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
          ),
          child: const Text('Descartar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(_EscolhaRascunho.nova),
          style: TextButton.styleFrom(foregroundColor: accent),
          child: const Text('Começar nova'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(_EscolhaRascunho.retomar),
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: const Text('Retomar rascunho'),
        ),
      ],
    ),
  );
}
