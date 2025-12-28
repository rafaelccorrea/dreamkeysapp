import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/custom_button.dart';
import '../models/client_model.dart';

/// Formulário para criar/editar cônjuge
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
    if (widget.initialSpouse != null) {
      _loadSpouseData();
    }
  }

  void _loadSpouseData() {
    final spouse = widget.initialSpouse!;
    _nameController.text = spouse.name;
    _cpfController.text = spouse.cpf ?? '';
    _phoneController.text = spouse.phone ?? '';
    _emailController.text = spouse.email ?? '';
    _rgController.text = spouse.rg ?? '';
    if (spouse.birthDate != null) {
      try {
        _birthDate = DateTime.parse(spouse.birthDate!);
        _birthDateController.text = DateFormat('dd/MM/yyyy').format(_birthDate!);
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

  Future<void> _selectBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 25)),
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Criar um Spouse temporário com campos mínimos
    // O backend irá gerar id, createdAt e updatedAt
    final spouse = Spouse(
      id: widget.initialSpouse?.id ?? '', // Será gerado pelo backend
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
      createdAt: widget.initialSpouse?.createdAt ?? DateTime.now().toIso8601String(),
      updatedAt: widget.initialSpouse?.updatedAt ?? DateTime.now().toIso8601String(),
    );

    widget.onSave(spouse);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.initialSpouse == null ? 'Adicionar Cônjuge' : 'Editar Cônjuge',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 24),
          CustomTextField(
            controller: _nameController,
            label: 'Nome Completo *',
            prefixIcon: const Icon(Icons.person_outline),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Nome é obrigatório';
              }
              if (value.trim().length < 2) {
                return 'Nome deve ter pelo menos 2 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _cpfController,
            label: 'CPF',
            prefixIcon: const Icon(Icons.badge_outlined),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value != null && value.trim().isNotEmpty) {
                final cpf = value.replaceAll(RegExp(r'[^\d]'), '');
                if (cpf.length != 11) {
                  return 'CPF deve ter 11 dígitos';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _phoneController,
            label: 'Telefone',
            prefixIcon: const Icon(Icons.phone_outlined),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _emailController,
            label: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value != null && value.trim().isNotEmpty) {
                if (!value.contains('@')) {
                  return 'Email inválido';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _rgController,
            label: 'RG',
            prefixIcon: const Icon(Icons.badge_outlined),
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _birthDateController,
            decoration: InputDecoration(
              labelText: 'Data de Nascimento',
              prefixIcon: const Icon(Icons.calendar_today_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: _selectBirthDate,
              ),
            ),
            readOnly: true,
            onTap: _selectBirthDate,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              if (widget.onCancel != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: widget.onCancel != null ? 1 : 1,
                child: CustomButton(
                  text: 'Salvar',
                  icon: Icons.save,
                  onPressed: _handleSave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

