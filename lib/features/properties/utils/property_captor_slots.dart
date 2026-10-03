import '../../../shared/utils/property_finalidade.dart';

/// Captação por papel — porte de `CaptorRoleSlots.tsx` (web) e de
/// `splitCaptorsByRole` / `buildCreatePropertyApiPayload.ts`.
///
/// Regra de produto (web, 2026-08-25): a FINALIDADE manda. Imóvel de venda
/// exige um captador de venda; de locação, um de locação; "ambos" exige os
/// dois. A mesma pessoa pode ocupar os dois papéis, e sempre há pelo menos
/// um captador.
enum CaptorRole {
  venda('venda', 'venda'),
  locacao('locacao', 'locação');

  const CaptorRole(this.value, this.label);

  /// Valor do `captorAssignments[].role` no back.
  final String value;

  /// Rótulo em minúsculas para frases ("captador de locação").
  final String label;
}

/// Papéis que a finalidade exige. Sem finalidade, nenhum (os slots ficam
/// "Defina a finalidade", como no web).
List<CaptorRole> captorRolesRequiredBy(PropertyFinalidade? f) {
  switch (f) {
    case PropertyFinalidade.venda:
      return const [CaptorRole.venda];
    case PropertyFinalidade.locacao:
      return const [CaptorRole.locacao];
    case PropertyFinalidade.ambos:
      return const [CaptorRole.venda, CaptorRole.locacao];
    case null:
      return const [];
  }
}

/// Estado de validação dos slots — `evaluateCaptorSlots` do web.
class CaptorSlotsEvaluation {
  final bool valid;
  final bool finalidadeMissing;
  final List<CaptorRole> missingRoles;
  final bool anyCaptor;

  const CaptorSlotsEvaluation({
    required this.valid,
    required this.finalidadeMissing,
    required this.missingRoles,
    required this.anyCaptor,
  });

  /// Itens faltantes na mesma redação da lista de pendências do web
  /// (`CreatePropertyPage.tsx` ~3907-3920).
  List<String> get missingLabels => [
        if (finalidadeMissing) 'Finalidade',
        for (final r in missingRoles)
          r == CaptorRole.venda ? 'Captador de venda' : 'Captador de locação',
        if (!anyCaptor && missingRoles.isEmpty) 'Captador(es)',
      ];
}

CaptorSlotsEvaluation evaluateCaptorSlots({
  required PropertyFinalidade? finalidade,
  required List<String> saleIds,
  required List<String> rentIds,
}) {
  final has = {
    CaptorRole.venda: saleIds.isNotEmpty,
    CaptorRole.locacao: rentIds.isNotEmpty,
  };
  final missing =
      captorRolesRequiredBy(finalidade).where((r) => !has[r]!).toList();
  final any = saleIds.isNotEmpty || rentIds.isNotEmpty;
  final finalidadeMissing = finalidade == null;
  return CaptorSlotsEvaluation(
    valid: !finalidadeMissing && missing.isEmpty && any,
    finalidadeMissing: finalidadeMissing,
    missingRoles: missing,
    anyCaptor: any,
  );
}

String _finalidadeFrase(PropertyFinalidade f) => switch (f) {
      PropertyFinalidade.ambos => 'venda e locação',
      PropertyFinalidade.venda => 'venda',
      PropertyFinalidade.locacao => 'locação',
    };

/// Texto da "régua de regra" sob os slots (mesmas frases do web).
String captorRuleMessage(
  CaptorSlotsEvaluation e,
  PropertyFinalidade? finalidade,
) {
  if (e.finalidadeMissing || finalidade == null) {
    return 'Escolha a finalidade: ela define se o imóvel precisa de captador '
        'de venda, de locação ou dos dois. A mesma pessoa pode ocupar os dois '
        'papéis.';
  }
  if (e.missingRoles.isNotEmpty) {
    final falta = e.missingRoles.length == 2
        ? 'um captador de venda e um de locação'
        : 'um captador de ${e.missingRoles.first.label}';
    return 'Imóvel para ${_finalidadeFrase(finalidade)} precisa de $falta.';
  }
  if (!e.anyCaptor) return 'Selecione pelo menos um captador.';
  return 'Captação completa para ${_finalidadeFrase(finalidade)}.';
}

/// Mensagem do bloqueio ao avançar a etapa 1 (SnackBar).
String captorValidationMessage(CaptorSlotsEvaluation e) =>
    'Falta preencher: ${e.missingLabels.join(', ')}.';

/// Captador como vem do `GET /properties/:id` (`captors[]`, uma entrada por
/// usuário e papel).
typedef CaptorRef = ({String id, String? role});

/// Reparte os captadores da API nos dois slots pelo papel — porte de
/// `splitCaptorsByRole` (web). Resposta sem `role` cai no fallback: todos os
/// captadores vão para os slots que a [finalidadeGravada] exige — ou para os
/// dois, sem finalidade gravada.
({List<String> sale, List<String> rent}) splitCaptorsByRole({
  required List<CaptorRef> captors,
  required List<String> allIds,
  required PropertyFinalidade? finalidadeGravada,
}) {
  final sale = <String>[];
  final rent = <String>[];
  void add(List<String> l, String id) {
    if (!l.contains(id)) l.add(id);
  }

  var sawRole = false;
  for (final c in captors) {
    if (c.id.isEmpty) continue;
    if (c.role == CaptorRole.venda.value) {
      add(sale, c.id);
      sawRole = true;
    } else if (c.role == CaptorRole.locacao.value) {
      add(rent, c.id);
      sawRole = true;
    }
  }
  if (!sawRole) {
    final f = finalidadeGravada;
    final wantSale = f == null || f.anunciaVenda;
    final wantRent = f == null || f.anunciaLocacao;
    for (final id in allIds) {
      if (wantSale) add(sale, id);
      if (wantRent) add(rent, id);
    }
  } else {
    // Captador conhecido sem papel (linha antiga): cai em venda para não sumir.
    for (final id in allIds) {
      if (!sale.contains(id) && !rent.contains(id)) add(sale, id);
    }
  }
  return (sale: sale, rent: rent);
}

/// IDs de captadores do imóvel carregado, na ordem do back: `captors`,
/// depois `capturedByIds`, depois o legado `capturedById` — mesma prioridade
/// de `resolvePropertyCaptors` (web).
List<String> loadedCaptorIds({
  required List<CaptorRef> captors,
  required List<String>? capturedByIds,
  required String? capturedById,
}) {
  final out = <String>[];
  void add(String? id) {
    final v = id?.trim() ?? '';
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }

  for (final id in capturedByIds ?? const <String>[]) {
    add(id);
  }
  for (final c in captors) {
    add(c.id);
  }
  if (out.isEmpty) add(capturedById);
  return out;
}

/// União ordenada dos slots — vira `capturedByIds` (o primeiro é o
/// `capturedById` principal), como `applyCaptorSlots` no web.
List<String> captorUnion(List<String> saleIds, List<String> rentIds) {
  final out = <String>[];
  for (final id in [...saleIds, ...rentIds]) {
    if (id.isNotEmpty && !out.contains(id)) out.add(id);
  }
  return out;
}

/// `captorAssignments`: uma entrada por (usuário, papel).
List<Map<String, String>> captorAssignmentsOf(
  List<String> saleIds,
  List<String> rentIds,
) =>
    [
      for (final id in saleIds) {'userId': id, 'role': CaptorRole.venda.value},
      for (final id in rentIds)
        {'userId': id, 'role': CaptorRole.locacao.value},
    ];

bool _sameSet(List<String> a, List<String> b) =>
    a.toSet().length == b.toSet().length && a.toSet().containsAll(b);

/// Mesmo critério do back (`sameIdListWithPrimary`): mesmo conjunto e mesmo
/// primeiro (o principal).
bool sameIdListWithPrimary(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return a.isEmpty && b.isEmpty;
  return a.first == b.first && _sameSet(a, b);
}

/// Campos de captação/responsáveis do `POST /properties` — como
/// `buildCreatePropertyApiPayload.ts`: slots → `capturedById`,
/// `capturedByIds` e `captorAssignments`; responsáveis vazios caem no
/// usuário logado.
Map<String, dynamic> captorCreatePayload({
  required List<String> saleIds,
  required List<String> rentIds,
  required List<String> responsibleIds,
  required String currentUserId,
}) {
  // `capturedById` é obrigatório no DTO de criação. Sem slot preenchido (só
  // acontece em rascunho — a etapa 1 barra o cadastro), cai no usuário
  // logado, como o app fazia antes.
  final picked = captorUnion(saleIds, rentIds);
  final union = picked.isNotEmpty ? picked : [currentUserId];
  final assignments = captorAssignmentsOf(saleIds, rentIds);
  return {
    'capturedById': union.first,
    'capturedByIds': union,
    if (assignments.isNotEmpty) 'captorAssignments': assignments,
    'responsibleUserIds':
        responsibleIds.isNotEmpty ? List<String>.from(responsibleIds) : [currentUserId],
  };
}

/// Campos de captação/responsáveis do `PATCH /properties/:id` — SÓ o que
/// mudou (imoveis-04: nunca regravar captadores à toa).
///
/// - Trocou QUEM capta (conjunto ou principal): `capturedById` +
///   `capturedByIds` + `captorAssignments`. É campo protegido: o back pode
///   abrir solicitação de alteração (`pendingChangeRequest`).
/// - Mesmas pessoas, papéis diferentes — ou a finalidade mudou: só
///   `captorAssignments` (reclassificação; o back aplica sem `capturedByIds`).
/// - Responsáveis: só quando mudou o conjunto ou o principal, e nunca vazio
///   (o back ignora lista vazia).
Map<String, dynamic> captorEditPatch({
  required List<String> loadedSale,
  required List<String> loadedRent,
  required List<String> sale,
  required List<String> rent,
  required List<String> loadedResponsibles,
  required List<String> responsibles,
  bool finalidadeChanged = false,
}) {
  final out = <String, dynamic>{};
  final loadedUnion = captorUnion(loadedSale, loadedRent);
  final union = captorUnion(sale, rent);
  final rolesChanged =
      !_sameSet(loadedSale, sale) || !_sameSet(loadedRent, rent);

  if (union.isNotEmpty && !sameIdListWithPrimary(union, loadedUnion)) {
    out['capturedById'] = union.first;
    out['capturedByIds'] = union;
    out['captorAssignments'] = captorAssignmentsOf(sale, rent);
  } else if (union.isNotEmpty && (rolesChanged || finalidadeChanged)) {
    out['captorAssignments'] = captorAssignmentsOf(sale, rent);
  }

  if (responsibles.isNotEmpty &&
      !sameIdListWithPrimary(responsibles, loadedResponsibles)) {
    out['responsibleUserIds'] = List<String>.from(responsibles);
  }
  return out;
}

/// Responsáveis do imóvel carregado: `responsibleUserIds`, senão os ids de
/// `responsibles`, senão o legado `responsibleUserId` (ordem do web).
List<String> loadedResponsibleIds({
  required List<String>? responsibleUserIds,
  required List<String> responsiblesFromList,
  required String? responsibleUserId,
}) {
  final out = <String>[];
  void add(String? id) {
    final v = id?.trim() ?? '';
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }

  for (final id in responsibleUserIds ?? const <String>[]) {
    add(id);
  }
  if (out.isEmpty) {
    for (final id in responsiblesFromList) {
      add(id);
    }
  }
  if (out.isEmpty) add(responsibleUserId);
  return out;
}
