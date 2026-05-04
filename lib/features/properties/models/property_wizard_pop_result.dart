/// Resultado opcional ao fechar [CreatePropertyPage] (`Navigator.pop`).
/// Mantém informação suficiente para a lista atualizar como no fluxo web
/// (voltar focado ao imóvel / fila de aprovação).
class PropertyWizardPopResult {
  const PropertyWizardPopResult({
    this.propertyId,
    this.savedDraft = false,
    this.showApprovalShortcut = false,
  });

  /// Imóvel recém criado/atualizado.
  final String? propertyId;

  /// Equivalente ao “Salvar como rascunho” enviando ao servidor (web volta ao edit).
  final bool savedDraft;

  /// Paridade CreatePropertyPage web → `/properties/pending-approvals` após criar sem rascunho
  /// quando a empresa exige aprovação ou autorização do proprietário.
  final bool showApprovalShortcut;
}
