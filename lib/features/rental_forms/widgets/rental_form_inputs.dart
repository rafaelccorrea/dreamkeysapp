import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';

/// Widgets de entrada da ficha de locação — mesmo vocabulário visual dos
/// steps da ficha de venda (campos filled herdados do tema local do editor,
/// chips tonais, bandas de seção com divisória).

/// Banda de seção — título em caps + linha (idêntica ao `_Band` da ficha de
/// venda), com hint opcional abaixo.
class RentalSectionBand extends StatelessWidget {
  const RentalSectionBand({
    super.key,
    required this.title,
    this.hint,
    this.icon,
  });

  final String title;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon ?? LucideIcons.fileText, size: 14, color: muted),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          if (hint != null && hint!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Select tolerante — se o valor salvo não estiver nas opções (dado legado),
/// ele entra como opção extra para não ser perdido; opção vazia limpa.
class RentalSelectField extends StatelessWidget {
  const RentalSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.required = false,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final items = <String>[
      '',
      ...options,
      if (value.isNotEmpty && !options.contains(value)) value,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: items.contains(value) ? value : '',
        isExpanded: true,
        icon: Icon(LucideIcons.chevronDown, size: 18, color: muted),
        borderRadius: BorderRadius.circular(14),
        dropdownColor: ThemeHelpers.cardBackgroundColor(context),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
        items: [
          for (final o in items)
            DropdownMenuItem(
              value: o,
              child: Text(
                o.isEmpty ? '—' : o,
                overflow: TextOverflow.ellipsis,
                style: o.isEmpty
                    ? TextStyle(color: muted, fontWeight: FontWeight.w500)
                    : null,
              ),
            ),
        ],
        onChanged: enabled ? (v) => onChanged(v ?? '') : null,
        decoration: InputDecoration(labelText: required ? '$label *' : label),
      ),
    );
  }
}

/// Multi-seleção como chips — valor salvo é o join `', '` (paridade com o
/// `normalizedSelectValue` do web).
class RentalMultiSelectField extends StatelessWidget {
  const RentalMultiSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.accent,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String value;
  final List<String> options;
  final Color accent;
  final ValueChanged<String> onChanged;
  final bool enabled;

  Set<String> get _selected => value
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final selected = _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: muted,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                _MultiChip(
                  label: o,
                  selected: selected.contains(o),
                  accent: accent,
                  onTap: enabled
                      ? () {
                          final next = {...selected};
                          if (!next.add(o)) next.remove(o);
                          final ordered =
                              options.where(next.contains).toList();
                          onChanged(ordered.join(', '));
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MultiChip extends StatelessWidget {
  const _MultiChip({
    required this.label,
    required this.selected,
    required this.accent,
    this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(LucideIcons.check, size: 13, color: accent),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: selected ? accent : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox de confirmação — valor salvo `'Aceito'` | `''` (paridade web).
class RentalCheckboxField extends StatelessWidget {
  const RentalCheckboxField({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.enabled = true,
    this.required = false,
  });

  final String label;
  final String value;
  final Color accent;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final checked = value == 'Aceito';
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: enabled ? () => onChanged(checked ? '' : 'Aceito') : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: checked ? accent.withValues(alpha: 0.07) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: checked
                  ? accent.withValues(alpha: 0.5)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: checked ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: checked
                        ? accent
                        : ThemeHelpers.borderColor(context),
                    width: 1.6,
                  ),
                ),
                child: checked
                    ? const Icon(LucideIcons.check,
                        size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  required ? '$label *' : label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.3,
                    color: checked ? ThemeHelpers.textColor(context) : muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha da lista de moradores maiores de 18 anos.
class MoradorEntry {
  MoradorEntry({String nome = '', String telefone = '', String cpf = ''})
      : nome = TextEditingController(text: nome),
        telefone = TextEditingController(text: telefone),
        cpf = TextEditingController(text: cpf);

  final TextEditingController nome;
  final TextEditingController telefone;
  final TextEditingController cpf;

  bool get isEmpty =>
      nome.text.trim().isEmpty &&
      telefone.text.trim().isEmpty &&
      cpf.text.trim().isEmpty;

  Map<String, String> toJson() => {
        'nome': nome.text.trim(),
        'telefone': telefone.text.trim(),
        'cpf': cpf.text.trim(),
      };

  void dispose() {
    nome.dispose();
    telefone.dispose();
    cpf.dispose();
  }
}

/// Editor da lista dinâmica de moradores (JSON `[{nome, telefone, cpf}]` na
/// chave `moradoresAdultosLista` — paridade com o web). Recrie com uma `key`
/// nova ao recarregar a ficha para re-hidratar do payload.
class MoradoresEditor extends StatefulWidget {
  const MoradoresEditor({
    super.key,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.enabled = true,
  });

  /// JSON serializado atual (ou vazio).
  final String value;
  final Color accent;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<MoradoresEditor> createState() => _MoradoresEditorState();
}

class _MoradoresEditorState extends State<MoradoresEditor> {
  final List<MoradorEntry> _rows = [];

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _hydrate() {
    final raw = widget.value.trim();
    if (raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          for (final item in parsed) {
            if (item is Map) {
              _rows.add(MoradorEntry(
                nome: (item['nome'] ?? '').toString(),
                telefone: (item['telefone'] ?? '').toString(),
                cpf: (item['cpf'] ?? '').toString(),
              ));
            }
          }
        }
      } catch (_) {
        // JSON legado inválido → começa vazio.
      }
    }
    if (_rows.isEmpty) _rows.add(MoradorEntry());
  }

  void _emit() {
    widget.onChanged(jsonEncode([for (final r in _rows) r.toJson()]));
  }

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              'MORADORES MAIORES DE 18 ANOS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: muted,
              ),
            ),
          ),
          for (var i = 0; i < _rows.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rows[i].nome,
                          enabled: widget.enabled,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => _emit(),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText: 'Nome do morador ${i + 1}',
                          ),
                        ),
                      ),
                      if (widget.enabled && _rows.length > 1) ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _rows.removeAt(i).dispose();
                              });
                              _emit();
                            },
                            child:
                                Icon(LucideIcons.trash2, size: 17, color: muted),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rows[i].telefone,
                          enabled: widget.enabled,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [PhoneInputFormatter()],
                          onChanged: (_) => _emit(),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          decoration:
                              const InputDecoration(labelText: 'Telefone'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _rows[i].cpf,
                          enabled: widget.enabled,
                          keyboardType: TextInputType.number,
                          inputFormatters: [CpfInputFormatter()],
                          onChanged: (_) => _emit(),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(labelText: 'CPF'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          if (widget.enabled)
            GestureDetector(
              onTap: () {
                setState(() => _rows.add(MoradorEntry()));
                _emit();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: widget.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.plus, size: 15, color: widget.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Adicionar morador',
                      style: TextStyle(
                        color: widget.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
