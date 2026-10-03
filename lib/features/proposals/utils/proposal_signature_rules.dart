/// Regras puras do fluxo de assinaturas da PROPOSTA — espelho do web
/// (`ProposalSignaturesModalPrivate.tsx`, `PropostaAnexosModalPrivate.tsx`),
/// separadas da tela para teste.
library;

// Rótulo do status da assinatura: `ProposalSignature.statusLabel`
// (shared/services/purchase_proposals_service.dart), igual ao web.

/// Mensagem depois que a ficha física da [etapa] foi aprovada (no upload por
/// gestor ou na aprovação): anuncia a PRÓXIMA etapa liberada, como o web
/// (`PropostaAnexosModalPrivate.tsx:479-486` e `:502-506`).
String proposalAnexoAprovadoMsg(int etapa, {bool noUpload = false}) {
  if (noUpload) {
    return etapa < 3
        ? 'Anexo enviado e aprovado. Etapa ${etapa + 1} liberada.'
        : 'Anexo enviado e aprovado.';
  }
  return etapa < 3
      ? 'Anexo aprovado. Etapa ${etapa + 1} liberada.'
      : 'Anexo aprovado. Etapa liberada.';
}

// Disponibilidade do reenvio pelo WhatsApp: `ProposalWhatsappEnvio` +
// `PurchaseProposalsService.getWhatsappEnvio`.

/// Resumo honesto do `POST …/reenviar-whatsapp` (`{sent, skippedNoPhone,
/// failed}`): só diz "enviado" quando algo saiu de fato.
String proposalWhatsappResumo(Map<String, dynamic>? r) {
  int n(String k) {
    final v = r?[k];
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  }

  final parts = <String>[
    if (n('sent') > 0) '${n('sent')} enviado(s) pelo WhatsApp',
    if (n('skippedNoPhone') > 0) '${n('skippedNoPhone')} sem telefone',
    if (n('failed') > 0) '${n('failed')} falha(s)',
  ];
  return parts.isEmpty ? 'Nenhuma mensagem enviada.' : parts.join(' · ');
}

/// Proposta com algum documento já assinado no Autentique — aí o PDF pode
/// sair junto com o(s) assinado(s) num .zip (`GET :id/pdf`, padrão
/// `incluirAutentique`).
bool proposalTemAssinado(Iterable<String> statuses) =>
    statuses.any((s) => s.trim().toLowerCase() == 'signed');

/// Aprovar/rejeitar a ficha física: gestor, anexo `pending_approval` e — como
/// no web, onde a ação só existe no modal de Anexos, que só abre com etapa
/// disponível para anexo — ao menos uma etapa ainda disponível.
bool proposalPodeDecidirAnexo({
  required bool isGestor,
  required String status,
  required List<int> etapasDisponiveis,
}) =>
    isGestor &&
    status.trim().toLowerCase() == 'pending_approval' &&
    etapasDisponiveis.isNotEmpty;
