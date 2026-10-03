// Título determinístico do imóvel — espelho de `utils/propertyFallbackTitle.ts`
// do web (que por sua vez espelha o fallback local do back,
// `AiService.generateTitle`). Usado quando a geração por IA não responde
// (timeout, 429, rede): o título é obrigatório na criação e, sem isto, o
// corretor fica preso na revisão sem conseguir finalizar o cadastro.

const Map<String, String> _typeLabel = {
  'house': 'Casa',
  'apartment': 'Apartamento',
  'commercial': 'Imóvel Comercial',
  'office': 'Sala Comercial',
  'store': 'Loja',
  'warehouse': 'Galpão',
  'townhouse': 'Sobrado',
  'penthouse': 'Cobertura',
  'studio': 'Studio',
  'loft': 'Loft',
  'kitnet': 'Kitnet',
  'duplex': 'Duplex',
  'triplex': 'Triplex',
  'farm': 'Fazenda',
  'land': 'Terreno',
  'rural': 'Propriedade Rural',
};

/// Tipos em que a metragem vale mais como gancho do que o número de quartos.
const List<String> _landLikeTypes = ['land', 'rural', 'farm'];

/// Tipos em que "N qts" faz sentido no título.
const List<String> _residentialHookTypes = [
  'house',
  'apartment',
  'townhouse',
  'penthouse',
  'studio',
  'loft',
  'kitnet',
  'duplex',
  'triplex',
];

/// Mensagens do web (`fallbackTitleAfterAiMiss`).
const String kFallbackTitleAiMissMessage =
    'A IA não respondeu com um título. Montamos um com os dados do imóvel — '
    'você pode ajustar na revisão.';
const String kFallbackTitleMissingDataMessage =
    'Faltam dados para a IA gerar o título. Montamos um com o que já foi '
    'preenchido — você pode ajustar na revisão.';

/// Título do rascunho quando não há nem tipo nem cidade (web
/// `handleCreateProperty`).
const String kDraftTitlePlaceholder = 'Rascunho de imóvel';

/// Descrição do rascunho sem descrição (web
/// `applyRemoteDraftCreatePlaceholders`) — o back exige `description`.
const String kDraftDescriptionPlaceholder =
    'Cadastro em andamento. Preencha os dados e finalize o cadastro.';

String _stripRedundantCondominiumSuffix(String name) {
  return name
      .trim()
      .replaceAll(
        RegExp(r'\s*[-–—|]\s*Condomínio\s+Residencial\s*$', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'\s*[-–—|]\s*Condomínio\s+Fechado\s*$', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'\s+Condomínio\s+Residencial\s*$', caseSensitive: false),
        '',
      )
      .trim();
}

String _fmtArea(double v) {
  // `${120}` no JS sai "120"; `${120.5}` sai "120.5".
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

String? _pickShortTitleHook({
  required String type,
  required List<String> features,
  int? bedrooms,
  int? parkingSpaces,
  double? totalArea,
}) {
  final f = features.map((e) => e.toLowerCase()).toList();
  bool has(RegExp re) => f.any(re.hasMatch);

  if (has(RegExp(r'\bpiscina\b'))) return 'Piscina';
  if (has(RegExp(r'\bchurrasqueira\b')) || has(RegExp(r'\bchurrasco\b'))) {
    return 'Churrasqueira';
  }
  if (has(RegExp(r'\b(suítes?|suite)\b'))) return 'Suítes';
  if (has(RegExp(r'\bvaranda\s+gourmet\b'))) return 'Varanda gourmet';
  if (has(RegExp(r'\bmobiliad'))) return 'Mobiliado';
  if (has(RegExp(r'\bquintal\b'))) return 'Quintal';

  if (_landLikeTypes.contains(type) && totalArea != null && totalArea > 0) {
    return '${_fmtArea(totalArea)} m²';
  }
  if (bedrooms != null && bedrooms > 0 && _residentialHookTypes.contains(type)) {
    return '$bedrooms qts';
  }
  if (parkingSpaces != null && parkingSpaces > 0) {
    return parkingSpaces == 1 ? '1 vaga' : '$parkingSpaces vagas';
  }
  return null;
}

/// Corta o título no limite, preferindo quebrar em " · " (nunca passa de 255,
/// o limite do banco).
String truncatePropertyTitle(String title, {int maxLen = 100}) {
  final limit = maxLen < 255 ? maxLen : 255;
  final t = title.trim();
  if (t.length <= limit) return t;
  final slice = t.substring(0, limit);
  final lastSep = slice.lastIndexOf(' · ');
  return (lastSep > 24 ? slice.substring(0, lastSep) : slice).trim();
}

/// Monta o título com os dados do cadastro. Devolve '' quando não há nem
/// tipo nem cidade (aí não dá para montar nada útil).
String buildFallbackPropertyTitle({
  String? type,
  String? city,
  String? neighborhood,
  String? condominiumName,
  String? empreendimentoName,
  int? bedrooms,
  int? parkingSpaces,
  double? totalArea,
  List<String> features = const [],
  bool mcmvEligible = false,
}) {
  final rawType = (type ?? '').trim().toLowerCase();
  final c = (city ?? '').trim();
  final n = (neighborhood ?? '').trim();
  if (rawType.isEmpty && c.isEmpty) return '';

  final label = rawType.isEmpty ? 'Imóvel' : (_typeLabel[rawType] ?? 'Imóvel');
  final condoRaw = (condominiumName ?? '').trim();
  final empRaw = (empreendimentoName ?? '').trim();
  final condo = condoRaw.isEmpty ? '' : _stripRedundantCondominiumSuffix(condoRaw);
  final emp = empRaw.isEmpty ? '' : _stripRedundantCondominiumSuffix(empRaw);
  final hook = _pickShortTitleHook(
    type: rawType,
    features: features,
    bedrooms: bedrooms,
    parkingSpaces: parkingSpaces,
    totalArea: totalArea,
  );
  final loc = n.isNotEmpty ? (c.isNotEmpty ? '$n, $c' : n) : c;

  final bits = <String>[
    if (condo.isNotEmpty || emp.isNotEmpty) condo.isNotEmpty ? condo : emp,
    label,
    ?hook,
    if (loc.isNotEmpty) loc,
    if (mcmvEligible) 'MCMV',
  ];
  return truncatePropertyTitle(bits.join(' · '));
}
