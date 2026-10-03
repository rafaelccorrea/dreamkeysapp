import '../../../shared/services/purchase_proposals_service.dart';

/// Regras da edição e do atalho da linha da ficha de proposta — funções puras
/// (testáveis) que espelham o back e o web.

/// Edição recusada pelo back (`purchase-proposals.service.ts`, `update`:
/// excluída, finalizada e cancelada levam 400). `null` = pode editar.
///
/// O web abria a edição de proposta finalizada e prometia "reiniciar as
/// assinaturas" ao salvar, mas o `PATCH` vem antes do reinício e o back o
/// recusa — o fluxo nunca chegava ao fim. Agora os dois clientes param aqui.
String? proposalEdicaoBloqueada({
  required ProposalStatus status,
  DateTime? deletedAt,
}) {
  if (deletedAt != null) return 'Proposta excluída não pode ser editada.';
  switch (status) {
    case ProposalStatus.finalized:
      return 'Proposta finalizada não pode ser editada.';
    case ProposalStatus.canceled:
      return 'Proposta cancelada não pode ser editada.';
    case ProposalStatus.processing:
      return null;
  }
}

/// O que o atalho da linha faz (web `PurchaseProposalsPage.tsx`, botão da
/// linha): enviar a etapa 1, abrir as assinaturas da etapa 2 ou continuar o
/// preenchimento na EDIÇÃO.
enum ProposalAtalhoTipo { enviar, assinaturasProprietario, continuar }

class ProposalAtalho {
  const ProposalAtalho(this.tipo, {this.etapa});
  final ProposalAtalhoTipo tipo;

  /// Etapa FORÇADA nas assinaturas (o web passa `etapa: 1` / `etapa: 2`, não
  /// a etapa atual da proposta). `null` no "Continuar" (abre a edição).
  final int? etapa;
}

/// Atalho da linha com as mesmas condições do web. `null` = sem atalho
/// (sem `proposal:update`, fora de andamento ou excluída).
ProposalAtalho? proposalAtalhoDaLinha(
  PurchaseProposal p, {
  required bool canUpdate,
}) {
  if (!canUpdate ||
      p.status != ProposalStatus.processing ||
      p.deletedAt != null) {
    return null;
  }
  final maxLiberada = p.maxEtapaLiberadaParaEnvio;
  if ((maxLiberada ?? p.etapa.number) < 2) {
    return const ProposalAtalho(ProposalAtalhoTipo.enviar, etapa: 1);
  }
  // Web: `etapa2EnviadaParaAssinatura ?? (etapa === 2 && processing)`.
  final flag = p.raw['etapa2EnviadaParaAssinatura'];
  final etapa2Enviada = flag is bool ? flag : p.etapa.number == 2;
  if ((maxLiberada ?? 2) == 2 && etapa2Enviada) {
    return const ProposalAtalho(
      ProposalAtalhoTipo.assinaturasProprietario,
      etapa: 2,
    );
  }
  return const ProposalAtalho(ProposalAtalhoTipo.continuar);
}

/// `getReinicioDecision` do web: editar dado de etapa já concluída
/// (assinatura digital ou anexo aprovado) pede confirmação e reinicia o
/// fluxo de assinaturas. Proposta finalizada não entra aqui: a edição dela
/// está bloqueada ([proposalEdicaoBloqueada]).
({bool needsReinicio, List<String> etapas}) proposalReinicioDecision({
  required Map<String, String> atual1,
  required Map<String, String>? carregado1,
  required Map<String, String> atual2,
  required Map<String, String>? carregado2,
  required Map<int, bool> concluidas,
}) {
  if (carregado1 == null) return (needsReinicio: false, etapas: const []);
  final alterou1 = !_mesmoMapa(atual1, carregado1);
  final alterou2 = !_mesmoMapa(atual2, carregado2);
  final violou1 = alterou1 && (concluidas[1] ?? false);
  final violou2 = alterou2 && (concluidas[2] ?? false);
  return (
    needsReinicio: violou1 || violou2,
    etapas: [
      if (violou1) 'Etapa 1 (comprador, proposta e imóvel)',
      if (violou2) 'Etapa 2 (proprietário)',
    ],
  );
}

bool _mesmoMapa(Map<String, String> a, Map<String, String>? b) {
  if (b == null || a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Mensagem do web quando o ViaCEP falha (`fetchAddressByZipCode` relança
/// tudo como "Erro ao buscar CEP").
const String kProposalCepErro = 'Erro ao buscar CEP';

/// Gatilho do CEP automático (`useCepAutofill` do web): dispara ao completar
/// 8 dígitos, não repete o mesmo CEP — mas libera de novo quando o campo
/// fica incompleto (apagou/redigitou) ou quando a busca falhou.
class ProposalCepGate {
  String _ultimo = '';

  /// Os 8 dígitos a buscar, ou `null` quando não deve buscar. [force] (a
  /// lupa) ignora a repetição.
  String? gatilho(String raw, {bool force = false}) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length != 8) {
      if (d.length < 8) _ultimo = '';
      return null;
    }
    if (!force && d == _ultimo) return null;
    _ultimo = d;
    return d;
  }

  /// Busca falhou: permite tentar o mesmo CEP de novo.
  void falhou() => _ultimo = '';
}
