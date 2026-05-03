import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../models/client_model.dart';

/// Formulário para criar / editar cônjuge — refinado para o sistema visual
/// usado nas demais telas de clientes.
class SpouseForm extends StatefulWidget {
  final Spouse? initialSpouse;
  final Function(Spouse) onSave;
  final VoidCallback? onCancel;

  const SpouseForm({
    super.key,
    this.initialSpouse,
    required this.onSave,
    this.onCancel,
  });

  @override
  State<SpouseForm> createState() => _SpouseFormState();
}

class _SpouseFormState extends State<SpouseForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cpfController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _rgController = TextEditingController();
  final _birthDateController = TextEditingController();

  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    if (widget.initialSpouse != null) _loadSpouseData();
  }

  void _loadSpouseData() {
    final s = widget.initialSpouse!;
    _nameController.text = s.name;
    _cpfController.text = s.cpf ?? '';
    _phoneController.text = s.phone ?? '';
    _emailController.text = s.email ?? '';
    _rgController.text = s.rg ?? '';
    if (s.birthDate != null) {
      try {
        _birthDate = DateTime.parse(s.birthDate!);
        _birthDateController.text =
            DateFormat('dd/MM/yyyy').format(_birthDate!);
      } catch (e) {
        debugPrint('Erro ao parsear data de nascimento: $e');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cpfController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _rgController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  Future<void> _selectBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ??
          DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;

    final spouse = Spouse(
      id: widget.initialSpouse?.id ?? '',
      name: _nameController.text.trim(),
      cpf: _cpfController.text.trim().isNotEmpty
          ? _cpfController.text.trim().replaceAll(RegExp(r'[^\d]'), '')
          : null,
      phone: _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : null,
      email: _emailController.text.trim().isNotEmpty
          ? _emailController.text.trim()
          : null,
      rg: _rgController.text.trim().isNotEmpty
          ? _rgController.text.trim()
          : null,
      birthDate: _birthDate != null
          ? DateFormat('yyyy-MM-dd').format(_birthDate!)
          : null,
      createdAt:
          widget.initialSpouse?.createdAt ?? DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );

    widget.onSave(spouse);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final isEditing = widget.initialSpouse != null;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [accent, const Color(0xFF7C3AED)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite_outline,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Editar cônjuge' : 'Adicionar cônjuge',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mantenha os dados sincronizados para análise de crédito.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          CustomTextField(
            controller: _nameController,
            label: 'Nome completo *',
            prefixIcon: const Icon(Icons.person_outline),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Nome é obrigatório';
              }
              if (value.trim().length < 2) {
                return 'Mínimo 2 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: _cpfController,
                  label: 'CPF',
                  prefixIcon: const Icon(Icons.fingerprint_rounded),
                  keyboardType: TextInputType.number,
                  inputFormatters: [CpfInputFormatter()],
                  validator: (value) {
                    if (value != null && value.trim().isNotEmpty) {
                      final cpf = value.replaceAll(RegExp(r'[^\d]'), '');
                      if (cpf.length != 11) return 'CPF deve ter 11 dígitos';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: _rgController,
                  label: 'RG',
                  prefixIcon: const Icon(Icons.credit_card_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: _phoneController,
                  label: 'Telefone',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneInputFormatter()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: _emailController,
                  label: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null &&
                        value.trim().isNotEmpty &&
                        !value.contains('@')) {
                      return 'Email inválido';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _birthDateController,
            readOnly: true,
            onTap: _selectBirthDate,
            decoration: InputDecoration(
              labelText: 'Data de nascimento',
              prefixIcon: const Icon(Icons.cake_outlined),
              suffixIcon: _birthDateController.text.isEmpty
                  ? const Icon(Icons.calendar_today_outlined)
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        setState(() {
                          _birthDateController.clear();
                          _birthDate = null;
                        });
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              if (widget.onCancel != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: widget.onCancel != null ? 2 : 1,
                child: FilledButton.icon(
                  onPressed: _handleSave,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    isEditing ? 'Salvar alterações' : 'Adicionar cônjuge',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
