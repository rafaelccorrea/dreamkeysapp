import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/utils/masks.dart';

/// Campo de texto que aplica máscara de CPF ou CNPJ automaticamente
class CpfCnpjTextField extends StatefulWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool enabled;
  final FocusNode? focusNode;
  final bool readOnly;
  final String? errorText;
  final bool required;

  const CpfCnpjTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.focusNode,
    this.readOnly = false,
    this.errorText,
    this.required = false,
  });

  @override
  State<CpfCnpjTextField> createState() => _CpfCnpjTextFieldState();
}

class _CpfCnpjTextFieldState extends State<CpfCnpjTextField> {
  late TextEditingController _controller;
  bool _isCpf = true; // Assume CPF inicialmente

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _isCpf = Masks.isCpfDocument(_controller.text);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  void _onTextChanged() {
    final isCpf = Masks.isCpfDocument(_controller.text);
    if (isCpf != _isCpf && mounted) setState(() => _isCpf = isCpf);
  }

  TextInputFormatter _getFormatter() => _CpfCnpjInputFormatter();

  String? Function(String?)? _buildValidator() {
    if (widget.validator != null) {
      return widget.validator;
    }

    return (String? value) {
      if (widget.required && (value == null || value.trim().isEmpty)) {
        return 'Campo obrigatório';
      }

      if (value != null && value.trim().isNotEmpty) {
        final clean = Masks.unmaskCnpj(value);
        if (Masks.isCpfDocument(value)) {
          // Validação básica de CPF (11 dígitos)
          if (clean.length != 11) {
            return 'CPF deve ter 11 dígitos';
          }
        } else {
          // Validação básica de CNPJ (14 caracteres, aceita alfanumérico)
          if (clean.length != 14) {
            return 'CNPJ deve ter 14 caracteres';
          }
        }
      }

      return null;
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: _controller,
          // Teclado com letras: o CNPJ alfanumérico (2026) tem letras nos 12
          // primeiros caracteres.
          keyboardType: TextInputType.visiblePassword,
          textCapitalization: TextCapitalization.characters,
          validator: _buildValidator(),
          // A máscara já foi aplicada pelo formatter.
          onChanged: (value) => widget.onChanged?.call(value),
          enabled: widget.enabled,
          focusNode: widget.focusNode,
          readOnly: widget.readOnly,
          inputFormatters: [_getFormatter()],
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText:
                widget.hint ??
                (_isCpf ? '000.000.000-00' : 'XX.XXX.XXX/XXXX-00'),
            errorText: widget.errorText,
            suffixIcon: Icon(_isCpf ? Icons.person : Icons.business, size: 20),
          ),
        ),
      ],
    );
  }
}

/// Máscara dinâmica CPF ↔ CNPJ — com letra ou mais de 11 caracteres vira
/// CNPJ (inclusive o alfanumérico de 2026).
class _CpfCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final masked = Masks.cpfOrCnpj(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
