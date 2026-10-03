import '../../../shared/services/property_service.dart';

/// Tom do aviso depois de salvar uma edição.
enum PropertySaveFeedbackTone { success, info, warning }

/// Aviso mostrado depois do `PATCH /properties/:id` — paridade com
/// `CreatePropertyPage.tsx` (web, ~4548-4594). Dois retornos possíveis,
/// nunca juntos:
///
/// a) `resubmittedForApproval`: imóvel recusado editado voltou para a fila
///    (âmbar — algo a aguardar, nunca vermelho);
/// b) `pendingChangeRequest`: campos protegidos viraram solicitação de
///    alteração; o resto foi salvo (informativo).
///
/// Sem nenhum dos dois: "atualizada com sucesso".
class PropertySaveFeedback {
  final String message;
  final PropertySaveFeedbackTone tone;

  const PropertySaveFeedback(this.message, this.tone);

  /// Avisos longos ficam mais tempo na tela (o web usa 12 s).
  bool get isLong => tone != PropertySaveFeedbackTone.success;

  static PropertySaveFeedback afterEdit(Property? updated) {
    final resub = updated?.resubmittedForApproval;
    if (resub != null) {
      final fila = resub.isAvailability
          ? 'aprovação de disponibilidade'
          : 'aprovação de publicação no site';
      final motivo = resub.reason?.trim() ?? '';
      final recusa = motivo.isNotEmpty
          ? 'A recusa «$motivo» foi resolvida e o imóvel'
          : 'A recusa foi resolvida e o imóvel';
      return PropertySaveFeedback(
        'Imóvel reenviado para aprovação. $recusa voltou para a fila de '
        '$fila. Ele fica em nova análise até o aprovador responder.',
        PropertySaveFeedbackTone.warning,
      );
    }
    final pending = updated?.pendingChangeRequest;
    if (pending != null) {
      final labels = pending.fieldLabels.isNotEmpty
          ? pending.fieldLabels
          : pending.fields;
      return PropertySaveFeedback(
        'Alterações enviadas para aprovação. Os campos a seguir aguardam '
        'aprovação em “Alterações de imóveis” e ainda não foram aplicados: '
        '${labels.join(', ')}. Os demais dados foram salvos normalmente.',
        PropertySaveFeedbackTone.info,
      );
    }
    return const PropertySaveFeedback(
      'Propriedade atualizada com sucesso!',
      PropertySaveFeedbackTone.success,
    );
  }
}
