import '../../../shared/services/property_service.dart';

// "Ficha adicional" do cadastro — espelho de `buildCreatePropertyApiPayload.ts`
// (web) para os campos opcionais da etapa "Características" (CreatePropertyPage
// case 2) e a linha premium da etapa "Site". Nomes e limites conferidos no
// Create/UpdatePropertyDto do back (`create-property.dto.ts:889-1097`,
// `update-property.dto.ts:808-1015`; `rooms` em :309 / :281).

/// Chaves de texto, na ordem da tela do web.
class PropertyExtraTextKey {
  static const rooms = 'rooms';
  static const builtYear = 'builtYear';
  static const alternativeCode = 'alternativeCode';
  static const unitFloor = 'unitFloor';
  static const floors = 'floors';
  static const buildings = 'buildings';
  static const elevators = 'elevators';
  static const sunPosition = 'sunPosition';
  static const propertySituation = 'propertySituation';
  static const lotArea = 'lotArea';
  static const lotMeasureType = 'lotMeasureType';
  static const propertyUnity = 'propertyUnity';
  static const visitTime = 'visitTime';
  static const siteContact = 'siteContact';
  static const ownersPercentage = 'ownersPercentage';
  static const ownersRate = 'ownersRate';
  static const houseRules = 'houseRules';
  static const nearby = 'nearby';
  static const siteMetaDescription = 'siteMetaDescription';

  static const all = <String>[
    rooms,
    builtYear,
    alternativeCode,
    unitFloor,
    floors,
    buildings,
    elevators,
    sunPosition,
    propertySituation,
    lotArea,
    lotMeasureType,
    propertyUnity,
    visitTime,
    siteContact,
    ownersPercentage,
    ownersRate,
    houseRules,
    nearby,
    siteMetaDescription,
  ];

  /// Inteiros (parseInt do web).
  static const ints = <String>{
    rooms,
    builtYear,
    unitFloor,
    floors,
    buildings,
    elevators,
  };

  /// Decimais.
  static const decimals = <String>{lotArea, ownersPercentage, ownersRate};
}

/// Marcadores (checkbox do web), com o rótulo exato da tela.
class PropertyExtraFlag {
  final String key;
  final String label;
  const PropertyExtraFlag(this.key, this.label);

  /// `isSitePremiumLine` mora na etapa Site (não nesta lista).
  static const fichaFlags = <PropertyExtraFlag>[
    PropertyExtraFlag('isHighStandard', 'Alto padrão'),
    PropertyExtraFlag('hasPlaque', 'Com placa'),
    PropertyExtraFlag('hasExclusivity', 'Exclusividade'),
    PropertyExtraFlag('isPrivate', 'Privado (não divulgar)'),
    PropertyExtraFlag('bail', 'Aceita caução'),
    PropertyExtraFlag('suretyBond', 'Aceita fiança'),
    PropertyExtraFlag('bondApplication', 'Aplicação fiança'),
    PropertyExtraFlag('credpagoGuarantee', 'Garantia CredPago'),
    PropertyExtraFlag('guarantor', 'Aceita fiador'),
  ];

  static const sitePremiumLine = 'isSitePremiumLine';

  static List<String> get allKeys => [
        for (final f in fichaFlags) f.key,
        sitePremiumLine,
      ];
}

/// `@MaxLength` dos textos no DTO (o web usa os mesmos `maxLength`).
const Map<String, int> kPropertyExtraMaxLength = {
  PropertyExtraTextKey.alternativeCode: 50,
  PropertyExtraTextKey.sunPosition: 50,
  PropertyExtraTextKey.propertySituation: 100,
  PropertyExtraTextKey.lotMeasureType: 255,
  PropertyExtraTextKey.propertyUnity: 50,
  PropertyExtraTextKey.visitTime: 255,
  PropertyExtraTextKey.siteContact: 255,
};

/// Tipos que contam SALAS no lugar de quartos (`contaSalas` do web,
/// `types/property.ts:726`: só "Comercial").
bool propertyTypeCountsRooms(String? type) => type == 'commercial';

/// Número digitado no app: aceita "120.5", "120,5" e "1.200,50".
double? parseDecimalInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
  }
  return double.tryParse(t);
}

/// Valor do servidor → texto do campo (sem ".0" sobrando).
String formatDecimalForInput(num? v) {
  if (v == null) return '';
  final d = v.toDouble();
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d.toString();
}

/// Estado bruto da ficha adicional (o que está nos campos).
class PropertyExtraFieldValues {
  /// Texto de cada [PropertyExtraTextKey].
  final Map<String, String> texts;

  /// Valor de cada [PropertyExtraFlag] (inclui `isSitePremiumLine`).
  final Map<String, bool> flags;

  const PropertyExtraFieldValues({
    this.texts = const {},
    this.flags = const {},
  });

  String text(String key) => (texts[key] ?? '').trim();
  bool flag(String key) => flags[key] ?? false;

  /// Preenche a partir do imóvel carregado (edição). Ausente = vazio/false,
  /// igual ao web (`?? false`, `|| ''`).
  factory PropertyExtraFieldValues.fromProperty(Property p) {
    final a = p.additionalInfo;
    String n(num? v) => v == null ? '' : formatDecimalForInput(v);
    String s(String? v) => v ?? '';
    final builtYear = a?.builtYear;
    return PropertyExtraFieldValues(
      texts: {
        PropertyExtraTextKey.rooms: n(a?.rooms),
        // O web mostra vazio para 0 (inválido no DTO, Min 1800).
        PropertyExtraTextKey.builtYear:
            builtYear == null || builtYear == 0 ? '' : n(builtYear),
        PropertyExtraTextKey.alternativeCode: s(a?.alternativeCode),
        PropertyExtraTextKey.unitFloor: n(a?.unitFloor),
        PropertyExtraTextKey.floors: n(a?.floors),
        PropertyExtraTextKey.buildings: n(a?.buildings),
        PropertyExtraTextKey.elevators: n(a?.elevators),
        PropertyExtraTextKey.sunPosition: s(a?.sunPosition),
        PropertyExtraTextKey.propertySituation: s(a?.propertySituation),
        // `formatAreaFromNumber` do web: 0 vira vazio.
        PropertyExtraTextKey.lotArea:
            (a?.lotArea ?? 0) == 0 ? '' : n(a?.lotArea),
        PropertyExtraTextKey.lotMeasureType: s(a?.lotMeasureType),
        PropertyExtraTextKey.propertyUnity: s(a?.propertyUnity),
        PropertyExtraTextKey.visitTime: s(a?.visitTime),
        PropertyExtraTextKey.siteContact: s(a?.siteContact),
        PropertyExtraTextKey.ownersPercentage: n(a?.ownersPercentage),
        PropertyExtraTextKey.ownersRate: n(a?.ownersRate),
        PropertyExtraTextKey.houseRules: s(a?.houseRules),
        PropertyExtraTextKey.nearby: s(a?.nearby),
        PropertyExtraTextKey.siteMetaDescription: s(a?.siteMetaDescription),
      },
      flags: {
        'isHighStandard': a?.isHighStandard ?? false,
        'hasPlaque': a?.hasPlaque ?? false,
        'hasExclusivity': a?.hasExclusivity ?? false,
        'isPrivate': a?.isPrivate ?? false,
        'bail': a?.bail ?? false,
        'suretyBond': a?.suretyBond ?? false,
        'bondApplication': a?.bondApplication ?? false,
        'credpagoGuarantee': a?.credpagoGuarantee ?? false,
        'guarantor': a?.guarantor ?? false,
        PropertyExtraFlag.sitePremiumLine: p.isSitePremiumLine ?? false,
      },
    );
  }

  /// Rascunho local (mesmo mapa do auto-save do wizard). Chave própria para
  /// não colidir com os campos que já existem.
  static const draftKey = 'extraFicha';

  Map<String, dynamic> toDraft() => {
        'texts': Map<String, String>.from(texts),
        'flags': Map<String, bool>.from(flags),
      };

  static PropertyExtraFieldValues? fromDraft(dynamic raw) {
    if (raw is! Map) return null;
    final t = raw['texts'];
    final f = raw['flags'];
    return PropertyExtraFieldValues(
      texts: {
        if (t is Map)
          for (final e in t.entries)
            if (PropertyExtraTextKey.all.contains(e.key.toString()))
              e.key.toString(): e.value?.toString() ?? '',
      },
      flags: {
        if (f is Map)
          for (final e in f.entries)
            if (PropertyExtraFlag.allKeys.contains(e.key.toString()))
              e.key.toString(): e.value == true,
      },
    );
  }

  /// Algum campo preenchido/marcado (abre a seção recolhida).
  bool get hasAnyValue =>
      texts.values.any((v) => v.trim().isNotEmpty) ||
      flags.entries
          .where((e) => e.key != PropertyExtraFlag.sitePremiumLine)
          .any((e) => e.value);

  /// Quantos campos da ficha estão preenchidos (selo da seção).
  int get filledCount =>
      texts.entries
          .where((e) => e.key != PropertyExtraTextKey.rooms)
          .where((e) => e.value.trim().isNotEmpty)
          .length +
      PropertyExtraFlag.fichaFlags.where((f) => flag(f.key)).length;

  /// Valor que vai à API para [key]; `null` = limpar; [_omit] = não mandar.
  Object? _apiValue(String key) {
    final t = text(key);
    if (t.isEmpty) return _omit;
    switch (key) {
      case PropertyExtraTextKey.builtYear:
        final n = int.tryParse(t);
        if (n == null) return _omit;
        // Igual ao web: fora do intervalo da API vai null (nunca 0).
        if (n < 1800 || n > 2100) return null;
        return n;
      case PropertyExtraTextKey.rooms:
      case PropertyExtraTextKey.unitFloor:
      case PropertyExtraTextKey.floors:
      case PropertyExtraTextKey.buildings:
      case PropertyExtraTextKey.elevators:
        final n = int.tryParse(t);
        return n ?? _omit;
      case PropertyExtraTextKey.lotArea:
      case PropertyExtraTextKey.ownersPercentage:
      case PropertyExtraTextKey.ownersRate:
        final d = parseDecimalInput(t);
        return d ?? _omit;
      default:
        return t;
    }
  }

  /// Campos da CRIAÇÃO — mesma forma do `buildCreatePropertyApiPayload` do
  /// web: marcadores sempre (false por padrão); texto/número só preenchido.
  /// `isSitePremiumLine` só vai com o imóvel no site (o web trava a chave
  /// sem publicação).
  Map<String, dynamic> createApiFields({required bool publishToSite}) {
    final out = <String, dynamic>{};
    for (final f in PropertyExtraFlag.fichaFlags) {
      out[f.key] = flag(f.key);
    }
    out[PropertyExtraFlag.sitePremiumLine] =
        publishToSite && flag(PropertyExtraFlag.sitePremiumLine);
    for (final key in PropertyExtraTextKey.all) {
      final v = _apiValue(key);
      if (!identical(v, _omit)) out[key] = v;
    }
    return out;
  }

  /// Campos da EDIÇÃO — só o que mudou em relação a [loaded] (o PATCH não
  /// apaga o que a pessoa não tocou nem abre solicitação de alteração à
  /// toa). Campo esvaziado vai `null` (o DTO aceita e limpa).
  Map<String, dynamic> editApiFields(
    PropertyExtraFieldValues loaded, {
    required bool publishToSite,
  }) {
    final out = <String, dynamic>{};
    for (final f in PropertyExtraFlag.fichaFlags) {
      if (flag(f.key) != loaded.flag(f.key)) out[f.key] = flag(f.key);
    }
    final premium = publishToSite && flag(PropertyExtraFlag.sitePremiumLine);
    if (premium != loaded.flag(PropertyExtraFlag.sitePremiumLine)) {
      out[PropertyExtraFlag.sitePremiumLine] = premium;
    }
    for (final key in PropertyExtraTextKey.all) {
      final cur = _apiValue(key);
      final old = loaded._apiValue(key);
      final curN = identical(cur, _omit) ? null : cur;
      final oldN = identical(old, _omit) ? null : old;
      if (!_sameApiValue(curN, oldN)) out[key] = curN;
    }
    return out;
  }

  /// Limites do DTO (o back recusa com 400 no fim do cadastro). O web só
  /// limita o tamanho dos textos; aqui o aviso chega antes, na etapa.
  String? validationError() {
    String? intRange(String key, String label, int min, int max) {
      final t = text(key);
      if (t.isEmpty) return null;
      final n = int.tryParse(t);
      if (n == null) return '$label: informe um número inteiro.';
      if (n < min || n > max) return '$label: use um valor entre $min e $max.';
      return null;
    }

    String? pct(String key, String label) {
      final t = text(key);
      if (t.isEmpty) return null;
      final d = parseDecimalInput(t);
      if (d == null) return '$label: informe um número.';
      if (d < 0 || d > 100) return '$label: use um valor entre 0 e 100.';
      return null;
    }

    final rooms = text(PropertyExtraTextKey.rooms);
    if (rooms.isNotEmpty && int.tryParse(rooms) == null) {
      return 'Salas: informe um número inteiro.';
    }
    final year = text(PropertyExtraTextKey.builtYear);
    if (year.isNotEmpty) {
      final n = int.tryParse(year);
      if (n == null || n < 1800 || n > 2100) {
        return 'Ano de construção: use um ano entre 1800 e 2100.';
      }
    }
    final checks = <String?>[
      intRange(PropertyExtraTextKey.unitFloor, 'Andar (unidade)', -5, 9999),
      intRange(PropertyExtraTextKey.floors, 'Andares (edifício)', 0, 200),
      intRange(PropertyExtraTextKey.buildings, 'Blocos / torres', 0, 100),
      intRange(PropertyExtraTextKey.elevators, 'Elevadores', 0, 100),
      pct(PropertyExtraTextKey.ownersPercentage, '% proprietário (repasse)'),
      pct(PropertyExtraTextKey.ownersRate, 'Taxa / rateio proprietário'),
    ];
    for (final c in checks) {
      if (c != null) return c;
    }
    final lot = text(PropertyExtraTextKey.lotArea);
    if (lot.isNotEmpty) {
      final d = parseDecimalInput(lot);
      if (d == null || d < 0 || d > 99999999.99) {
        return 'Área do lote: informe um valor até 99.999.999,99 m².';
      }
    }
    for (final e in kPropertyExtraMaxLength.entries) {
      if (text(e.key).length > e.value) {
        return 'Um campo da ficha adicional passou de ${e.value} caracteres.';
      }
    }
    return null;
  }
}

const Object _omit = Object();

bool _sameApiValue(Object? a, Object? b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  return a == b;
}
