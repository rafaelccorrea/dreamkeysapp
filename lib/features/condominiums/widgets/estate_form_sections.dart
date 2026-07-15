import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/cep_service.dart';
import '../../../shared/utils/input_formatters.dart';
import 'estate_filters_sheet.dart' show kEstateUfs;
import 'estate_shared.dart';

/// Controllers + estado do formulário de condomínio/empreendimento
/// (campos idênticos nos dois módulos — o empreendimento adiciona
/// complemento e material da equipe).
class EstateFormData {
  final name = TextEditingController();
  final description = TextEditingController();
  final zipCode = TextEditingController();
  final street = TextEditingController();
  final number = TextEditingController();
  final complement = TextEditingController();
  final neighborhood = TextEditingController();
  final city = TextEditingController();
  String? uf;
  final phone = TextEditingController();
  final email = TextEditingController();
  final cnpj = TextEditingController();
  final website = TextEditingController();
  bool isActive = true;

  void dispose() {
    name.dispose();
    description.dispose();
    zipCode.dispose();
    street.dispose();
    number.dispose();
    complement.dispose();
    neighborhood.dispose();
    city.dispose();
    phone.dispose();
    email.dispose();
    cnpj.dispose();
    website.dispose();
  }

  /// "Endereço" resumido — mesma composição do web
  /// (`rua, bairro, cidade - UF`) feita no submit.
  String composedAddress() {
    final left = [
      street.text.trim(),
      neighborhood.text.trim(),
    ].where((s) => s.isNotEmpty).join(', ');
    final cityUf = [
      city.text.trim(),
      (uf ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' - ');
    return [left, cityUf].where((s) => s.isNotEmpty).join(', ');
  }

  /// Payload de create/update (chaves do `CreateCondominiumDto` /
  /// `CreateEmpreendimentoDto`).
  Map<String, dynamic> buildPayload({bool includeComplement = false}) {
    String? opt(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    final payload = <String, dynamic>{
      'name': name.text.trim(),
      'address': composedAddress(),
      'street': street.text.trim(),
      'number': number.text.trim(),
      'neighborhood': neighborhood.text.trim(),
      'city': city.text.trim(),
      'state': (uf ?? '').trim(),
      'zipCode': zipCode.text.trim(),
    };
    if (includeComplement) {
      final c = opt(complement);
      if (c != null) payload['complement'] = c;
    }
    void put(String key, String? value) {
      if (value != null) payload[key] = value;
    }

    put('description', opt(description));
    put('phone', opt(phone));
    put('email', opt(email));
    put('cnpj', opt(cnpj));
    put('website', opt(website));
    return payload;
  }
}

/// Seções compartilhadas do formulário: Identificação, Endereço (CEP →
/// ViaCEP com autofill) e Contato. Campos filled, 2 colunas quando couber.
class EstateFormSections extends StatefulWidget {
  final EstateFormData data;
  final Color accent;
  final bool showComplement;
  final String nameLabel;
  final String nameHint;

  const EstateFormSections({
    super.key,
    required this.data,
    required this.accent,
    this.showComplement = false,
    required this.nameLabel,
    required this.nameHint,
  });

  @override
  State<EstateFormSections> createState() => _EstateFormSectionsState();
}

class _EstateFormSectionsState extends State<EstateFormSections> {
  bool _cepLoading = false;
  String? _cepError;
  String _lastSearchedCep = '';

  EstateFormData get d => widget.data;

  Future<void> _maybeSearchCep(String raw) async {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8 || digits == _lastSearchedCep) return;
    _lastSearchedCep = digits;
    setState(() {
      _cepLoading = true;
      _cepError = null;
    });
    final address = await CepService.instance.searchCep(digits);
    if (!mounted) return;
    setState(() {
      _cepLoading = false;
      if (address == null) {
        _cepError = 'CEP não encontrado — preencha o endereço manualmente.';
        return;
      }
      if ((address.street ?? '').isNotEmpty) d.street.text = address.street!;
      if ((address.neighborhood ?? '').isNotEmpty) {
        d.neighborhood.text = address.neighborhood!;
      }
      if ((address.city ?? '').isNotEmpty) d.city.text = address.city!;
      final st = (address.state ?? '').toUpperCase();
      if (kEstateUfs.contains(st)) d.uf = st;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EstateSectionHeader(
          tone: accent,
          label: 'Identificação',
          hint: 'Como o cadastro aparece nas listagens e nos imóveis.',
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: d.name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: '${widget.nameLabel} *',
            hintText: widget.nameHint,
          ),
          validator: (v) => (v ?? '').trim().isEmpty
              ? '${widget.nameLabel} é obrigatório'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: d.description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Descrição',
            hintText: 'Diferenciais, estrutura, observações…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),
        _sectionDivider(context),
        EstateSectionHeader(
          tone: EstateTones.blue(context),
          label: 'Endereço',
          hint: 'Informe o CEP para preencher automaticamente.',
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: d.zipCode,
                keyboardType: TextInputType.number,
                inputFormatters: [CepInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'CEP *',
                  hintText: '00000-000',
                  suffixIcon: _cepLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Icon(LucideIcons.mapPinned,
                          size: 17,
                          color: ThemeHelpers.textSecondaryColor(context)),
                ),
                onChanged: _maybeSearchCep,
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.isEmpty) return 'CEP é obrigatório';
                  if (digits.length != 8) return 'CEP deve ter 8 dígitos';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: d.number,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Número *',
                  hintText: 'Ex.: 120',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Número é obrigatório' : null,
              ),
            ),
          ],
        ),
        if (_cepError != null) ...[
          const SizedBox(height: 6),
          Text(
            _cepError!,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: EstateTones.amber(context),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: d.street,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Rua / Logradouro *',
          ),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Rua/Logradouro é obrigatório' : null,
        ),
        if (widget.showComplement) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: d.complement,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Complemento',
              hintText: 'Torre, bloco, sala…',
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: d.neighborhood,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Bairro *'),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Bairro é obrigatório' : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: d.city,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cidade *'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Cidade é obrigatória' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                // A key força o rebuild quando o CEP preenche a UF —
                // FormField mantém estado interno e ignoraria o novo valor.
                key: ValueKey('uf-${d.uf ?? ''}'),
                initialValue: d.uf,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'UF *'),
                items: [
                  for (final uf in kEstateUfs)
                    DropdownMenuItem(value: uf, child: Text(uf)),
                ],
                onChanged: (v) => setState(() => d.uf = v),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'UF é obrigatória' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionDivider(context),
        EstateSectionHeader(
          tone: EstateTones.green(context),
          label: 'Contato',
          hint: 'Dados opcionais de contato e identificação fiscal.',
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: d.phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  hintText: '(00) 00000-0000',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: d.cnpj,
                keyboardType: TextInputType.number,
                inputFormatters: [CnpjInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'CNPJ',
                  hintText: '00.000.000/0000-00',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: d.email,
          keyboardType: TextInputType.emailAddress,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
          ],
          decoration: const InputDecoration(
            labelText: 'E-mail',
            hintText: 'contato@exemplo.com.br',
          ),
          validator: (v) {
            final value = (v ?? '').trim();
            if (value.isEmpty) return null;
            final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
            return ok ? null : 'E-mail inválido';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: d.website,
          keyboardType: TextInputType.url,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
          ],
          decoration: const InputDecoration(
            labelText: 'Site',
            hintText: 'https://…',
          ),
        ),
      ],
    );
  }

  Widget _sectionDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        height: 1,
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
      ),
    );
  }
}

/// Tema local dos campos — visual filled coeso com o wizard da ficha de venda.
ThemeData estateFormTheme(BuildContext context, Color accent) {
  final base = Theme.of(context);
  final isDark = base.brightness == Brightness.dark;
  final fill = isDark
      ? Colors.white.withValues(alpha: 0.045)
      : Colors.black.withValues(alpha: 0.025);
  final muted = ThemeHelpers.textSecondaryColor(context);
  OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(primary: accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.18),
      selectionHandleColor: accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      labelStyle:
          TextStyle(color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
      floatingLabelStyle:
          TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13.5),
      hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
      border: b(Colors.transparent, 0),
      enabledBorder: b(Colors.transparent, 0),
      focusedBorder: b(accent, 1.6),
      errorBorder: b(EstateTones.danger(context).withValues(alpha: 0.7), 1.2),
      focusedErrorBorder: b(EstateTones.danger(context), 1.6),
    ),
  );
}
