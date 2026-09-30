import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../models/client_model.dart';
import '../utils/client_phone_rules.dart';
import 'client_date_field.dart';

/// Formulário do cônjuge — mesmos campos e regras do `SpouseForm` do web
/// (`components/modals/SpouseForm.tsx`): nome e CPF obrigatórios (CPF com
/// dígito verificador), telefones que não podem repetir os do cliente,
/// dados profissionais, renda e observações.
class SpouseForm extends StatefulWidget {
  final Spouse? initialSpouse;

  /// Salva no back; devolve `true` quando deu certo (o form fecha).
  final Future<bool> Function(Spouse) onSave;
  final VoidCallback? onCancel;

  /// Telefones do cliente (`clientContactPhones` do web) para barrar
  /// duplicata entre cliente e cônjuge.
  final String? clientPhone;
  final String? clientSecondaryPhone;
  final String? clientWhatsapp;

  const SpouseForm({
    super.key,
    this.initialSpouse,
    required this.onSave,
    this.onCancel,
    this.clientPhone,
    this.clientSecondaryPhone,
    this.clientWhatsapp,
  });

  @override
  State<SpouseForm> createState() => _SpouseFormState();
}

class _SpouseFormState extends State<SpouseForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cpfController = TextEditingController();
  final _rgController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _professionController = TextEditingController();
  final _companyController = TextEditingController();
  final _jobPositionController = TextEditingController();
  final _incomeController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _birthDate;
  DateTime? _jobStartDate;
  bool _isCurrentlyWorking = true;
  bool _isRetired = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSpouse;
    if (s != null) {
      _nameController.text = s.name;
      _cpfController.text = _maskCpf(s.cpf ?? '');
      _rgController.text = s.rg ?? '';
      _emailController.text = s.email ?? '';
      _phoneController.text = ClientPhoneRules.maskAuto(s.phone);
      _whatsappController.text = ClientPhoneRules.maskAuto(s.whatsapp);
      _professionController.text = s.profession ?? '';
      _companyController.text = s.companyName ?? '';
      _jobPositionController.text = s.jobPosition ?? '';
      if (s.monthlyIncome != null) {
        _incomeController.text =
            'R\$ ${s.monthlyIncome!.toStringAsFixed(2).replaceAll('.', ',')}';
      }
      _notesController.text = s.notes ?? '';
      _birthDate = DateTime.tryParse(s.birthDate ?? '');
      _jobStartDate = DateTime.tryParse(s.jobStartDate ?? '');
      _isCurrentlyWorking = s.isCurrentlyWorking ?? true;
      _isRetired = s.isRetired ?? false;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _cpfController,
      _rgController,
      _emailController,
      _phoneController,
      _whatsappController,
      _professionController,
      _companyController,
      _jobPositionController,
      _incomeController,
      _notesController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _maskCpf(String value) {
    final d = value.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return value;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  String? _trimOrNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  double? _parseMoney(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return int.parse(digits) / 100;
  }

  /// Erro de duplicata do web: cai no campo do cônjuge envolvido.
  String? _duplicateError(String field) {
    final dup = ClientPhoneRules.findDuplicate(
      ClientPhoneRules.profileEntries(
        phone: widget.clientPhone,
        secondaryPhone: widget.clientSecondaryPhone,
        whatsapp: widget.clientWhatsapp,
        spousePhone: _phoneController.text,
        spouseWhatsapp: _whatsappController.text,
      ),
    );
    if (dup == null) return null;
    final spouseField = dup.field == 'spousePhone' ||
            dup.duplicateOf == 'spousePhone'
        ? 'phone'
        : (dup.field == 'spouseWhatsapp' || dup.duplicateOf == 'spouseWhatsapp'
            ? 'whatsapp'
            : 'phone');
    return spouseField == field ? dup.message : null;
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final fmt = DateFormat('yyyy-MM-dd');
    final spouse = Spouse(
      id: widget.initialSpouse?.id ?? '',
      name: _nameController.text.trim(),
      cpf: _cpfController.text.replaceAll(RegExp(r'\D'), ''),
      rg: _trimOrNull(_rgController),
      birthDate: _birthDate == null ? null : fmt.format(_birthDate!),
      email: _trimOrNull(_emailController),
      phone: _trimOrNull(_phoneController),
      whatsapp: _trimOrNull(_whatsappController),
      profession: _trimOrNull(_professionController),
      companyName: _trimOrNull(_companyController),
      jobPosition: _trimOrNull(_jobPositionController),
      monthlyIncome: _parseMoney(_incomeController.text),
      jobStartDate:
          _jobStartDate == null ? null : fmt.format(_jobStartDate!),
      isCurrentlyWorking: _isCurrentlyWorking,
      isRetired: _isRetired,
      notes: _trimOrNull(_notesController),
      createdAt: widget.initialSpouse?.createdAt ?? '',
      updatedAt: widget.initialSpouse?.updatedAt ?? '',
    );
    // Quem abriu o form fecha a folha quando o save dá certo.
    await widget.onSave(spouse);
    if (!mounted) return;
    setState(() => _isSaving = false);
  }

  Widget _pair(Widget a, Widget b) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
      ),
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final accent = AppColors.primary.primary;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: accent,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initialSpouse != null;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isEditing ? 'Editar cônjuge' : 'Adicionar cônjuge',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                icon: const Icon(Icons.close_rounded),
                onPressed: _isSaving ? null : widget.onCancel,
              ),
            ],
          ),
          Text(
            'Esses dados alimentam os signatários das fichas.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          _sectionLabel(context, 'Dados pessoais'),
          CustomTextField(
            controller: _nameController,
            label: 'Nome completo *',
            prefixIcon: const Icon(Icons.person_outline),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Nome é obrigatório';
              if (v.length < 3) return 'Mínimo 3 caracteres';
              return null;
            },
          ),
          const SizedBox(height: 12),
          _pair(
            CustomTextField(
              controller: _cpfController,
              label: 'CPF *',
              prefixIcon: const Icon(Icons.fingerprint_rounded),
              keyboardType: TextInputType.number,
              inputFormatters: [CpfInputFormatter()],
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'CPF é obrigatório';
                if (!ClientPhoneRules.isValidCpf(v)) return 'CPF inválido';
                return null;
              },
            ),
            CustomTextField(
              controller: _rgController,
              label: 'RG',
              prefixIcon: const Icon(Icons.credit_card_outlined),
            ),
          ),
          const SizedBox(height: 12),
          ClientDateField(
            label: 'Data de nascimento',
            value: _birthDate,
            icon: Icons.cake_outlined,
            lastDate: DateTime.now(),
            initialPickerDate:
                DateTime.now().subtract(const Duration(days: 365 * 30)),
            onChanged: (d) => setState(() => _birthDate = d),
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: _emailController,
            label: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isNotEmpty && !ClientPhoneRules.isValidEmail(v)) {
                return 'Email inválido';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _pair(
            CustomTextField(
              controller: _phoneController,
              label: 'Telefone',
              prefixIcon: const Icon(Icons.phone_outlined),
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
              validator: (_) => _duplicateError('phone'),
            ),
            CustomTextField(
              controller: _whatsappController,
              label: 'WhatsApp',
              prefixIcon: const Icon(Icons.chat_outlined),
              keyboardType: TextInputType.phone,
              inputFormatters: [PhoneInputFormatter()],
              validator: (_) => _duplicateError('whatsapp'),
            ),
          ),
          const SizedBox(height: 8),
          _sectionLabel(context, 'Dados profissionais'),
          CustomTextField(
            controller: _professionController,
            label: 'Profissão',
            hint: 'Ex: Médico, Professor...',
            prefixIcon: const Icon(Icons.work_outline),
          ),
          const SizedBox(height: 12),
          _pair(
            CustomTextField(
              controller: _companyController,
              label: 'Empresa',
              prefixIcon: const Icon(Icons.business_outlined),
            ),
            CustomTextField(
              controller: _jobPositionController,
              label: 'Cargo',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          _pair(
            CustomTextField(
              controller: _incomeController,
              label: 'Renda mensal',
              hint: 'R\$ 0,00',
              prefixIcon: const Icon(Icons.attach_money_outlined),
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
            ),
            ClientDateField(
              label: 'Início no trabalho',
              value: _jobStartDate,
              icon: Icons.event_available_outlined,
              lastDate: DateTime.now(),
              onChanged: (d) => setState(() => _jobStartDate = d),
            ),
          ),
          const SizedBox(height: 8),
          _switchRow(
            context,
            label: 'Ainda está trabalhando',
            value: _isCurrentlyWorking,
            onChanged: (v) => setState(() => _isCurrentlyWorking = v),
          ),
          _switchRow(
            context,
            label: 'Aposentado(a)',
            value: _isRetired,
            onChanged: (v) => setState(() => _isRetired = v),
          ),
          const SizedBox(height: 8),
          _sectionLabel(context, 'Observações'),
          CustomTextField(
            controller: _notesController,
            hint: 'Observações adicionais...',
            prefixIcon: const Icon(Icons.notes_outlined),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeHelpers.textColor(context),
                    side: BorderSide(color: ThemeHelpers.borderColor(context)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _handleSave,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _isSaving
                        ? 'Salvando…'
                        : (isEditing ? 'Salvar cônjuge' : 'Adicionar cônjuge'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.status.success,
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
