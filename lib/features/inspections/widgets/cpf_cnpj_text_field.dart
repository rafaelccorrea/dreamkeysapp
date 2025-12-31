import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/utils/input_formatters.dart';

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
    final text = _controller.text;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Se tem mais de 11 dígitos, é CNPJ
    final wasCpf = _isCpf;
    _isCpf = digits.length <= 11;
    
    // Se mudou o tipo, reaplica a máscara
    if (wasCpf != _isCpf && digits.isNotEmpty) {
      final masked = _isCpf ? Masks.cpf(digits) : Masks.cnpj(digits);
      if (masked != text) {
        _controller.value = TextEditingValue(
          text: masked,
          selection: TextSelection.collapsed(offset: masked.length),
        );
      }
    }
  }

  TextInputFormatter _getFormatter() {
    return _isCpf ? CpfInputFormatter() : CnpjInputFormatter();
  }

  String? Function(String?)? _buildValidator() {
    if (widget.validator != null) {
      return widget.validator;
    }

    return (String? value) {
      if (widget.required && (value == null || value.trim().isEmpty)) {
        return 'Campo obrigatório';
      }

      if (value != null && value.trim().isNotEmpty) {
        final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length <= 11) {
          // Validação básica de CPF (11 dígitos)
          if (digits.length != 11) {
            return 'CPF deve ter 11 dígitos';
          }
        } else {
          // Validação básica de CNPJ (14 dígitos)
          if (digits.length != 14) {
            return 'CNPJ deve ter 14 dígitos';
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
          keyboardType: TextInputType.number,
          validator: _buildValidator(),
          onChanged: (value) {
            // Aplicar máscara
            final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
            final masked = digits.length <= 11 
                ? Masks.cpf(digits) 
                : Masks.cnpj(digits);
            
            if (masked != value) {
              _controller.value = TextEditingValue(
                text: masked,
                selection: TextSelection.collapsed(offset: masked.length),
              );
            }
            
            widget.onChanged?.call(masked);
          },
          enabled: widget.enabled,
          focusNode: widget.focusNode,
          readOnly: widget.readOnly,
          inputFormatters: [_getFormatter()],
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: widget.hint ?? (_isCpf ? '000.000.000-00' : '00.000.000/0000-00'),
            errorText: widget.errorText,
            suffixIcon: Icon(
              _isCpf ? Icons.person : Icons.business,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}
