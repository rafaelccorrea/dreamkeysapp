import '../../../shared/services/property_service.dart';

// Endereço estruturado do proprietário — espelho do web
// (`CreatePropertyPage.tsx` etapa Proprietário + `buildCreatePropertyApiPayload.ts`
// :311-318). Nomes do payload: ownerZipCode, ownerStreet, ownerNumber,
// ownerComplement, ownerNeighborhood, ownerCity, ownerState. O `ownerAddress`
// (texto legado) é montado a partir deles, igual ao `useEffect` do web
// (:3019-3046).

class PropertyOwnerAddressValues {
  final String zipCode;
  final String street;
  final String number;
  final String complement;
  final String neighborhood;
  final String city;
  final String state;

  const PropertyOwnerAddressValues({
    this.zipCode = '',
    this.street = '',
    this.number = '',
    this.complement = '',
    this.neighborhood = '',
    this.city = '',
    this.state = '',
  });

  static const apiKeys = <String>[
    'ownerZipCode',
    'ownerStreet',
    'ownerNumber',
    'ownerComplement',
    'ownerNeighborhood',
    'ownerCity',
    'ownerState',
  ];

  factory PropertyOwnerAddressValues.fromOwner(PropertyOwner? o) {
    if (o == null) return const PropertyOwnerAddressValues();
    return PropertyOwnerAddressValues(
      zipCode: maskOwnerCep(o.zipCode ?? ''),
      street: o.street ?? '',
      number: o.number ?? '',
      complement: o.complement ?? '',
      neighborhood: o.neighborhood ?? '',
      city: o.city ?? '',
      state: o.state ?? '',
    );
  }

  /// Chave no mapa do rascunho local.
  static const draftKey = 'ownerAddressParts';

  Map<String, String> toDraft() => {
        'zipCode': zipCode,
        'street': street,
        'number': number,
        'complement': complement,
        'neighborhood': neighborhood,
        'city': city,
        'state': state,
      };

  static PropertyOwnerAddressValues? fromDraft(dynamic raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k]?.toString() ?? '';
    return PropertyOwnerAddressValues(
      zipCode: s('zipCode'),
      street: s('street'),
      number: s('number'),
      complement: s('complement'),
      neighborhood: s('neighborhood'),
      city: s('city'),
      state: s('state'),
    );
  }

  String get zipDigits => zipCode.replaceAll(RegExp(r'\D'), '');

  bool get isEmpty =>
      zipDigits.isEmpty &&
      street.trim().isEmpty &&
      number.trim().isEmpty &&
      complement.trim().isEmpty &&
      neighborhood.trim().isEmpty &&
      city.trim().isEmpty &&
      state.trim().isEmpty;

  /// Valores que vão à API (texto aparado; CEP só dígitos; UF maiúscula).
  Map<String, String> get _api => {
        'ownerZipCode': zipDigits,
        'ownerStreet': street.trim(),
        'ownerNumber': number.trim(),
        'ownerComplement': complement.trim(),
        'ownerNeighborhood': neighborhood.trim(),
        'ownerCity': city.trim(),
        'ownerState': state.trim().toUpperCase(),
      };

  /// Texto legado `ownerAddress`, montado como no web. Sem nenhuma parte
  /// preenchida, mantém o [legacy] que já existia (cadastro antigo).
  String composeLegacy(String legacy) {
    final parts = <String>[
      street.trim(),
      if (number.trim().isNotEmpty) 'nº ${number.trim()}',
      complement.trim(),
      neighborhood.trim(),
      city.trim(),
      state.trim().toUpperCase(),
      zipCode.trim(),
    ].where((p) => p.isNotEmpty).toList();
    final computed = parts.join(', ');
    if (computed.trim().isEmpty && legacy.trim().isNotEmpty) {
      return legacy.trim();
    }
    return computed;
  }

  /// Criação: só as partes preenchidas (vazio não vai).
  Map<String, dynamic> createApiFields() => {
        for (final e in _api.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };

  /// Edição: só o que mudou; parte apagada vai `null`.
  Map<String, dynamic> editApiFields(PropertyOwnerAddressValues loaded) {
    final cur = _api;
    final old = loaded._api;
    return {
      for (final k in apiKeys)
        if (cur[k] != old[k]) k: cur[k]!.isEmpty ? null : cur[k],
    };
  }
}

/// 00000-000 (aceita parcial enquanto digita).
String maskOwnerCep(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  final digits = d.length > 8 ? d.substring(0, 8) : d;
  if (digits.length <= 5) return digits;
  return '${digits.substring(0, 5)}-${digits.substring(5)}';
}

/// Endereço para exibir no detalhe: as partes estruturadas quando houver,
/// senão o texto legado. '' = nada a mostrar.
String ownerAddressDisplay(PropertyOwner? o) {
  if (o == null) return '';
  final parts = PropertyOwnerAddressValues.fromOwner(o);
  if (parts.isEmpty) return (o.address ?? '').trim();
  final line1 = [
    parts.street.trim(),
    if (parts.number.trim().isNotEmpty) 'nº ${parts.number.trim()}',
    parts.complement.trim(),
  ].where((p) => p.isNotEmpty).join(', ');
  final cityUf = [
    parts.city.trim(),
    parts.state.trim().toUpperCase(),
  ].where((p) => p.isNotEmpty).join('/');
  final line2 = [
    parts.neighborhood.trim(),
    cityUf,
  ].where((p) => p.isNotEmpty).join(' — ');
  final cep = parts.zipDigits.isEmpty ? '' : 'CEP ${maskOwnerCep(parts.zipDigits)}';
  return [line1, line2, cep].where((p) => p.isNotEmpty).join('\n');
}
