import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/cep_service.dart';
import '../utils/property_extra_fields.dart';
import '../utils/property_owner_address.dart';

// Campos do wizard que vieram do web na paridade de imóveis (imoveis-13):
// "Ficha adicional" da etapa Características, a linha premium da etapa Site
// e o endereço estruturado do proprietário. A lógica (payload, diff da
// edição, rascunho) mora em `utils/property_extra_fields.dart` e
// `utils/property_owner_address.dart`; aqui ficam só os controllers e a UI.

/// Estado editável da ficha adicional (textos + marcadores).
class PropertyExtraFieldsController extends ChangeNotifier {
  PropertyExtraFieldsController() {
    for (final c in _texts.values) {
      c.addListener(notifyListeners);
    }
  }

  final Map<String, TextEditingController> _texts = {
    for (final k in PropertyExtraTextKey.all) k: TextEditingController(),
  };
  final Map<String, bool> _flags = {};

  TextEditingController text(String key) => _texts[key]!;

  /// Campo "Salas" (imóvel comercial) — fica no lugar de "Quartos".
  TextEditingController get rooms => _texts[PropertyExtraTextKey.rooms]!;

  bool flag(String key) => _flags[key] ?? false;

  void setFlag(String key, bool value) {
    if (flag(key) == value) return;
    _flags[key] = value;
    notifyListeners();
  }

  PropertyExtraFieldValues get values => PropertyExtraFieldValues(
        texts: {for (final e in _texts.entries) e.key: e.value.text},
        flags: Map<String, bool>.from(_flags),
      );

  void load(PropertyExtraFieldValues v) {
    for (final e in _texts.entries) {
      final next = v.texts[e.key] ?? '';
      if (e.value.text != next) e.value.text = next;
    }
    _flags
      ..clear()
      ..addAll(v.flags);
    notifyListeners();
  }

  void clear() => load(const PropertyExtraFieldValues());

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.removeListener(notifyListeners);
      c.dispose();
    }
    super.dispose();
  }
}

/// Estado editável do endereço do proprietário.
class PropertyOwnerAddressController extends ChangeNotifier {
  PropertyOwnerAddressController() {
    for (final c in _all) {
      c.addListener(notifyListeners);
    }
  }

  final zipCode = TextEditingController();
  final street = TextEditingController();
  final number = TextEditingController();
  final complement = TextEditingController();
  final neighborhood = TextEditingController();
  final city = TextEditingController();
  final state = TextEditingController();

  List<TextEditingController> get _all =>
      [zipCode, street, number, complement, neighborhood, city, state];

  PropertyOwnerAddressValues get values => PropertyOwnerAddressValues(
        zipCode: zipCode.text,
        street: street.text,
        number: number.text,
        complement: complement.text,
        neighborhood: neighborhood.text,
        city: city.text,
        state: state.text,
      );

  void load(PropertyOwnerAddressValues v) {
    void set(TextEditingController c, String s) {
      if (c.text != s) c.text = s;
    }

    set(zipCode, v.zipCode);
    set(street, v.street);
    set(number, v.number);
    set(complement, v.complement);
    set(neighborhood, v.neighborhood);
    set(city, v.city);
    set(state, v.state);
  }

  void clear() => load(const PropertyOwnerAddressValues());

  @override
  void dispose() {
    for (final c in _all) {
      c.removeListener(notifyListeners);
      c.dispose();
    }
    super.dispose();
  }
}

/// Rótulo + campo no mesmo molde do `_buildFormField` do wizard.
class _WizField extends StatelessWidget {
  const _WizField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
    this.readOnly = false,
    this.suffix,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;
  final bool readOnly;
  final Widget? suffix;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textSecondaryColor(context),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 2 : null,
          validator: validator,
          readOnly: readOnly,
          textCapitalization: textCapitalization,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            suffixIcon: suffix,
            filled: readOnly ? true : null,
          ),
        ),
      ],
    );
  }
}

/// Dois campos lado a lado; empilha em tela estreita ou fonte grande.
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);
  final Widget a;
  final Widget? b;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final escala = MediaQuery.textScalerOf(context).scale(1);
        final lado = c.maxWidth / escala >= 300;
        if (b == null) return a;
        if (!lado) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 12), b!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b!),
          ],
        );
      },
    );
  }
}

String? _extraValidator(String key, String? v) =>
    PropertyExtraFieldValues(texts: {key: v ?? ''}).validationError();

/// "Ficha adicional (importação / detalhes)" — mesmos campos, rótulos e
/// limites do web (`CreatePropertyPage.tsx` :7294-7432). Tudo opcional;
/// começa recolhida e abre sozinha quando já há algo preenchido.
class PropertyExtraFichaFields extends StatefulWidget {
  const PropertyExtraFichaFields({
    super.key,
    required this.controller,
    required this.accent,
  });

  final PropertyExtraFieldsController controller;
  final Color accent;

  @override
  State<PropertyExtraFichaFields> createState() =>
      _PropertyExtraFichaFieldsState();
}

class _PropertyExtraFichaFieldsState extends State<PropertyExtraFichaFields> {
  late bool _open = widget.controller.values.hasAnyValue;

  PropertyExtraFieldsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant PropertyExtraFichaFields old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // Rascunho/edição carregados depois do primeiro build: abre se veio dado.
    if (!_open && _c.values.hasAnyValue) _open = true;
    setState(() {});
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    bool integer = false,
    bool signed = false,
    bool decimal = false,
    int maxLines = 1,
  }) {
    final maxLength = kPropertyExtraMaxLength[key];
    return _WizField(
      controller: _c.text(key),
      label: label,
      hint: hint,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: integer
          ? TextInputType.numberWithOptions(signed: signed)
          : decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      inputFormatters: integer
          ? [
              FilteringTextInputFormatter.allow(
                signed ? RegExp(r'^-?\d*') : RegExp(r'\d*'),
              ),
            ]
          : decimal
              ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'))]
              : null,
      textCapitalization: integer || decimal
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      validator: (v) => _extraValidator(key, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final filled = _c.values.filledCount;
    final accent = widget.accent;

    final header = Material(
      color: accent.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(Icons.post_add_rounded, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _open ? 'Ocultar campos' : 'Mostrar campos opcionais',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              if (filled > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    filled == 1 ? '1 preenchido' : '$filled preenchidos',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more_rounded, color: accent),
              ),
            ],
          ),
        ),
      ),
    );

    if (!_open) return header;

    const gap = SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in PropertyExtraFlag.fichaFlags)
              FilterChip(
                label: Text(f.label),
                selected: _c.flag(f.key),
                showCheckmark: true,
                onSelected: (v) => _c.setFlag(f.key, v),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _Pair(
          _field(PropertyExtraTextKey.builtYear, 'Ano de construção',
              hint: 'ex: 2015', integer: true),
          _field(PropertyExtraTextKey.alternativeCode, 'Código alternativo',
              hint: 'Legado'),
        ),
        gap,
        _Pair(
          _field(PropertyExtraTextKey.unitFloor, 'Andar (unidade)',
              integer: true, signed: true),
          _field(PropertyExtraTextKey.floors, 'Andares (edifício)',
              integer: true),
        ),
        gap,
        _Pair(
          _field(PropertyExtraTextKey.buildings, 'Blocos / torres',
              integer: true),
          _field(PropertyExtraTextKey.elevators, 'Elevadores', integer: true),
        ),
        gap,
        _Pair(
          _field(PropertyExtraTextKey.sunPosition, 'Posição solar',
              hint: 'Nascente, poente...'),
          _field(PropertyExtraTextKey.propertySituation, 'Situação do imóvel',
              hint: 'Na planta, pronto...'),
        ),
        gap,
        _Pair(
          _field(PropertyExtraTextKey.lotArea, 'Área do lote (m²)',
              decimal: true),
          _field(PropertyExtraTextKey.lotMeasureType, 'Medida do lote',
              hint: 'm², ha ou "Frente 37 m, Fundo 36,1"'),
        ),
        gap,
        _Pair(
          _field(PropertyExtraTextKey.propertyUnity,
              'Unidade (nº / identificador)'),
          _field(PropertyExtraTextKey.visitTime, 'Horário de visita'),
        ),
        gap,
        _Pair(
          _field(PropertyExtraTextKey.siteContact,
              'Contato (site / divulgação)'),
          _field(PropertyExtraTextKey.ownersPercentage,
              '% proprietário (repasse)',
              decimal: true),
        ),
        gap,
        _Pair(
          _field(PropertyExtraTextKey.ownersRate, 'Taxa / rateio proprietário',
              decimal: true),
          null,
        ),
        gap,
        _field(PropertyExtraTextKey.houseRules, 'Regras da casa',
            hint: 'Restrições informadas na migração...', maxLines: 3),
        gap,
        _field(PropertyExtraTextKey.nearby, 'Pontos próximos', maxLines: 3),
        gap,
        _field(PropertyExtraTextKey.siteMetaDescription,
            'Meta description (SEO site)',
            maxLines: 3),
        const SizedBox(height: 6),
        Text(
          'Campos extras gravados no banco após migração de sistemas legados. Opcionais.',
          style: theme.textTheme.bodySmall?.copyWith(color: secondary),
        ),
      ],
    );
  }
}

/// Endereço do proprietário (opcional) — mesmos campos do web
/// (`CreatePropertyPage.tsx` :9409-9525): CEP com busca (ViaCEP, o mesmo
/// serviço do endereço do imóvel), UF, rua, número, complemento, bairro e
/// cidade. O que veio do CEP fica travado até trocar o CEP.
class PropertyOwnerAddressFields extends StatefulWidget {
  const PropertyOwnerAddressFields({
    super.key,
    required this.controller,
    this.legacyAddress = '',
    this.cepService,
  });

  final PropertyOwnerAddressController controller;

  /// Texto antigo (`ownerAddress`) de cadastro sem as partes — só exibido.
  final String legacyAddress;

  final CepService? cepService;

  @override
  State<PropertyOwnerAddressFields> createState() =>
      _PropertyOwnerAddressFieldsState();
}

class _PropertyOwnerAddressFieldsState
    extends State<PropertyOwnerAddressFields> {
  bool _loading = false;
  String? _error;
  String _lastLookup = '';

  /// Campos preenchidos pela busca do CEP (ficam só leitura, como no web).
  final Set<TextEditingController> _fromCep = {};

  PropertyOwnerAddressController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.zipCode.addListener(_onZipChanged);
    _lastLookup = _c.values.zipDigits;
  }

  @override
  void dispose() {
    _c.zipCode.removeListener(_onZipChanged);
    super.dispose();
  }

  void _onZipChanged() {
    final digits = _c.values.zipDigits;
    if (digits.length < 8) {
      if (_fromCep.isNotEmpty || _error != null) {
        setState(() {
          _fromCep.clear();
          _error = null;
        });
      }
      _lastLookup = digits;
      return;
    }
    if (digits == _lastLookup) return;
    _lastLookup = digits;
    _lookup(digits);
  }

  Future<void> _lookup(String digits) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final address =
        await (widget.cepService ?? CepService.instance).searchCep(digits);
    if (!mounted || _c.values.zipDigits != digits) return;
    setState(() {
      _loading = false;
      _fromCep.clear();
      if (address == null) {
        _error = 'CEP não encontrado. Preencha o endereço manualmente.';
        return;
      }
      void put(TextEditingController c, String? v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return;
        c.text = t;
        _fromCep.add(c);
      }

      put(_c.street, address.street);
      put(_c.neighborhood, address.neighborhood);
      put(_c.city, address.city);
      put(_c.state, address.state?.toUpperCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const gap = SizedBox(height: 12);
    final legacy = widget.legacyAddress.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Endereço do proprietário',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Opcional. Digite o CEP para completar.',
          style: theme.textTheme.bodySmall?.copyWith(color: secondary),
        ),
        if (legacy.isNotEmpty && _c.values.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Gravado hoje: $legacy',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Pair(
          _WizField(
            controller: _c.zipCode,
            label: 'CEP',
            hint: '00000-000',
            keyboardType: TextInputType.number,
            maxLength: 9,
            inputFormatters: [_OwnerCepFormatter()],
            suffix: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          _WizField(
            controller: _c.state,
            label: 'Estado',
            hint: 'Ex: SP',
            maxLength: 2,
            readOnly: _fromCep.contains(_c.state),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
              _UpperCaseFormatter(),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        gap,
        _Pair(
          _WizField(
            controller: _c.street,
            label: 'Rua / Logradouro',
            hint: 'Ex: Rua das Flores',
            maxLength: 255,
            textCapitalization: TextCapitalization.words,
          ),
          _WizField(
            controller: _c.number,
            label: 'Número',
            hint: 'Ex: 123',
            maxLength: 10,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        gap,
        _Pair(
          _WizField(
            controller: _c.complement,
            label: 'Complemento',
            hint: 'Ex: Apto 42, Bloco B',
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
          ),
          _WizField(
            controller: _c.neighborhood,
            label: 'Bairro',
            hint: 'Ex: Centro',
            maxLength: 100,
            readOnly: _fromCep.contains(_c.neighborhood),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        gap,
        _WizField(
          controller: _c.city,
          label: 'Cidade',
          hint: 'Ex: São Paulo',
          maxLength: 100,
          readOnly: _fromCep.contains(_c.city),
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
  }
}

class _OwnerCepFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = maskOwnerCep(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
