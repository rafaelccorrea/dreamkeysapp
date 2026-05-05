/// Paridade com `imobx/src/properties/utils/property-form-config.util.ts`
/// (`isConfigurableFieldPresent` + mensagens de `assertConfigurableFieldsPresent`).

const Set<String> propertyFormConfigurableKeys = {
  'teamId',
  'title',
  'description',
  'internalNotes',
  'type',
  'street',
  'number',
  'complement',
  'neighborhood',
  'sector',
  'city',
  'state',
  'zipCode',
  'totalArea',
  'builtArea',
  'bedrooms',
  'suites',
  'bathrooms',
  'parkingSpaces',
  'salePrice',
  'rentPrice',
  'condominiumFee',
  'iptu',
  'capturedById',
  'capturedByIds',
  'ownerName',
  'ownerEmail',
  'ownerPhone',
  'ownerDocument',
  'condominiumId',
  'empreendimentoId',
  'features',
};

const Map<String, String> propertyFormFieldLabelsPt = {
  'teamId': 'Equipe',
  'title': 'Título',
  'description': 'Descrição',
  'internalNotes': 'Observações internas',
  'type': 'Tipo do imóvel',
  'street': 'Logradouro',
  'number': 'Número',
  'complement': 'Complemento',
  'neighborhood': 'Bairro',
  'sector': 'Setor',
  'city': 'Cidade',
  'state': 'Estado',
  'zipCode': 'CEP',
  'totalArea': 'Área total (m²)',
  'builtArea': 'Área construída (m²)',
  'bedrooms': 'Quartos',
  'suites': 'Suítes',
  'bathrooms': 'Banheiros',
  'parkingSpaces': 'Vagas',
  'salePrice': 'Preço de venda',
  'rentPrice': 'Preço de aluguel',
  'condominiumFee': 'Condomínio',
  'iptu': 'IPTU',
  'capturedById': 'Captador (principal)',
  'capturedByIds': 'Captadores',
  'ownerName': 'Nome do proprietário',
  'ownerEmail': 'E-mail do proprietário',
  'ownerPhone': 'Telefone do proprietário',
  'ownerDocument': 'Documento do proprietário',
  'condominiumId': 'Condomínio',
  'empreendimentoId': 'Empreendimento',
  'features': 'Características',
};

bool _numPresent(dynamic v) {
  if (v == null) return false;
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite;
  }
  if (v is String && v.trim().isNotEmpty) {
    final noThousands = v.replaceAll('.', '');
    final normalized = noThousands.replaceAll(',', '.');
    final n = double.tryParse(normalized);
    return n != null && n.isFinite;
  }
  return false;
}

/// Espelha `isConfigurableFieldPresent` do backend.
bool isConfigurableFieldPresent(String key, Map<String, dynamic> flat) {
  final v = flat[key];
  switch (key) {
    case 'teamId':
    case 'condominiumId':
    case 'empreendimentoId':
      return v is String &&
          v.trim().isNotEmpty &&
          v != '00000000-0000-0000-0000-000000000000';
    case 'capturedByIds':
      return v is List && v.isNotEmpty;
    case 'capturedById':
      return v is String && v.trim().isNotEmpty;
    case 'features':
      return v is List && v.isNotEmpty;
    case 'totalArea':
    case 'builtArea':
    case 'bedrooms':
    case 'suites':
    case 'bathrooms':
    case 'parkingSpaces':
    case 'salePrice':
    case 'rentPrice':
    case 'condominiumFee':
    case 'iptu':
      return _numPresent(v);
    default:
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      return true;
  }
}

/// Retorna a mesma mensagem que o `BadRequestException` do backend, ou `null` se ok.
String? configurableFieldsErrorPt(
  List<String> requiredKeys,
  Map<String, dynamic> flat,
) {
  if (requiredKeys.isEmpty) return null;
  for (final key in requiredKeys) {
    if (!propertyFormConfigurableKeys.contains(key)) continue;
    if (!isConfigurableFieldPresent(key, flat)) {
      final label = propertyFormFieldLabelsPt[key] ?? key;
      return 'Campo obrigatório conforme configuração da empresa: $label';
    }
  }
  return null;
}
