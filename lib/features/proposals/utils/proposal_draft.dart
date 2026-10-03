/// Rascunho local da ficha de PROPOSTA ("Retomar rascunho") — serializador
/// próprio da tela de criação, gravado pelo `FichaDraftStore` com o tipo
/// `'proposta'` (mesma chave por usuário e empresa da venda).
///
/// Espelho do web (`CreatePurchaseProposalPage.tsx:920-1039`):
///   - o rascunho guarda o `formData` inteiro + `linkedUserIds` + a aba;
///   - "em branco" = igual ao formulário inicial, IGNORANDO a equipe
///     (`isBlankProposalDraft` → `formularioIgualAoInicial(..., ['teamId'])`)
///     e sem usuários vinculados;
///   - ao restaurar, nascimento igual a hoje é descartado
///     (`sanitizeBirthDateValue`).
library;

/// Tipo no `FichaDraftStore`.
const String kProposalDraftTipo = 'proposta';

/// Formulário inicial (`initialFormData` do web) — só o que não é vazio.
/// Todo campo ausente daqui começa como `''`.
const Map<String, String> kProposalDraftInitial = {
  'validityDays': '5',
  'deliveryDays': '30',
  'buyerNationality': 'Brasileiro(a)',
  'ownerNationality': 'Brasileiro(a)',
};

/// Campos que não contam para "tem algo preenchido" (web: `['teamId']`).
const Set<String> kProposalDraftIgnoredKeys = {'teamId'};

/// Rascunho em branco: todos os campos iguais ao inicial (exceto a equipe) e
/// nenhum usuário vinculado.
bool proposalDraftIsBlank(
  Map<String, String> campos, {
  List<String> linkedUserIds = const [],
}) {
  if (linkedUserIds.isNotEmpty) return false;
  for (final e in campos.entries) {
    if (kProposalDraftIgnoredKeys.contains(e.key)) continue;
    final inicial = kProposalDraftInitial[e.key] ?? '';
    if (e.value.trim() != inicial) return false;
  }
  return true;
}

/// Monta o JSON do rascunho.
Map<String, dynamic> proposalDraftEncode({
  required Map<String, String> campos,
  required int tab,
  required List<String> linkedUserIds,
}) =>
    {
      'tab': tab,
      'linkedUserIds': List<String>.from(linkedUserIds),
      'campos': Map<String, String>.from(campos),
    };

/// Rascunho lido, já normalizado.
class ProposalDraftData {
  const ProposalDraftData({
    required this.campos,
    required this.tab,
    required this.linkedUserIds,
  });

  final Map<String, String> campos;
  final int tab;
  final List<String> linkedUserIds;

  String campo(String k) => campos[k] ?? kProposalDraftInitial[k] ?? '';

  /// Data `yyyy-MM-dd` do rascunho (`null` se vazia/ilegível).
  DateTime? data(String k) {
    final s = campo(k).trim();
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  /// Nascimento: igual a hoje vira vazio (web `sanitizeBirthDateValue`).
  DateTime? nascimento(String k, {DateTime? hoje}) {
    final d = data(k);
    if (d == null) return null;
    final h = hoje ?? DateTime.now();
    if (d.year == h.year && d.month == h.month && d.day == h.day) return null;
    return d;
  }
}

/// Lê o JSON gravado (tolerante: tipos errados viram vazio).
ProposalDraftData proposalDraftDecode(Map<String, dynamic> d) {
  final raw = d['campos'];
  final campos = <String, String>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      if (v == null) return;
      campos[k.toString()] = v.toString();
    });
  }
  final linked = d['linkedUserIds'];
  final tab = d['tab'];
  return ProposalDraftData(
    campos: campos,
    tab: tab is int && tab >= 0 && tab <= 3 ? tab : 0,
    linkedUserIds: linked is List
        ? [
            for (final x in linked)
              if (x != null && x.toString().trim().isNotEmpty) x.toString(),
          ]
        : const [],
  );
}

/// Resumo para o diálogo "Retomar rascunho": proponente e imóvel.
String proposalDraftResumo(Map<String, dynamic> d) {
  final p = proposalDraftDecode(d);
  final nome = p.campo('buyerName').trim();
  final end = p.campo('propAddress').trim();
  return [
    if (nome.isNotEmpty) 'Proponente: $nome',
    if (end.isNotEmpty) 'Imóvel: $end',
  ].join(' · ');
}
