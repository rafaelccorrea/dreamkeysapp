import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../models/client_model.dart';
import '../utils/client_phone_rules.dart';
import 'client_date_field.dart';
import 'client_form_kit.dart';

/// Formulário do cônjuge — mesmos campos e regras do `SpouseForm` do web
/// (`components/modals/SpouseForm.tsx`): nome e CPF obrigatórios (CPF com
/// dígito verificador), telefones que não podem repetir os do cliente,
/// dados profissionais, renda e observações.
///
/// Feito para morar numa folha de baixo com altura limitada: cabeçalho e
/// botões fixos, só o miolo rola. Em tela baixa com teclado aberto os botões
/// descem para o fim da rolagem (fixos, espremeriam os campos até sumir).
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
        // Máscara padrão de dinheiro (`1.234,56` + prefixo "R$ " no campo).
        _incomeController.text = CurrencyInputFormatter.format(
          (s.monthlyIncome! * 100).round() / 100,
        );
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

  // ───────────────────────── Layout ─────────────────────────

  Widget _buildHeader(BuildContext context, bool isEditing) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = clientFormAccent(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.people_outline, size: 20, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isEditing ? 'Editar cônjuge' : 'Adicionar cônjuge',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Nome e CPF são obrigatórios. Esses dados alimentam '
                        'os signatários das fichas.',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  icon: Icon(Icons.close_rounded, color: muted),
                  onPressed: _isSaving ? null : widget.onCancel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions({required bool isEditing, required bool framed}) {
    return ClientFormActionBar(
      confirmLabel: isEditing ? 'Salvar cônjuge' : 'Adicionar cônjuge',
      confirmIcon: Icons.check_rounded,
      confirmColor: clientFormSuccess(context),
      onConfirm: _handleSave,
      onCancel: widget.onCancel,
      busy: _isSaving,
      framed: framed,
      horizontalPadding: 20,
    );
  }

  List<Widget> _buildFields() {
    return [
      const ClientFormBand(
        'Dados pessoais',
        icon: Icons.person_outline,
        topSpacing: 16,
      ),
      ClientFormField(
        controller: _nameController,
        label: 'Nome completo',
        isRequired: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        validator: (value) {
          final v = value?.trim() ?? '';
          if (v.isEmpty) return 'Nome é obrigatório';
          if (v.length < 3) return 'Mínimo 3 caracteres';
          return null;
        },
      ),
      const SizedBox(height: 12),
      ClientFormRow2(
        minColumnWidth: 140,
        left: ClientFormField(
          controller: _cpfController,
          label: 'CPF',
          isRequired: true,
          keyboardType: TextInputType.number,
          inputFormatters: [CpfInputFormatter()],
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty) return 'CPF é obrigatório';
            if (!ClientPhoneRules.isValidCpf(v)) return 'CPF inválido';
            return null;
          },
        ),
        right: ClientFormField(
          controller: _rgController,
          label: 'RG',
        ),
      ),
      const SizedBox(height: 12),
      ClientFormField(
        controller: _emailController,
        label: 'E-mail',
        keyboardType: TextInputType.emailAddress,
        validator: (value) {
          final v = value?.trim() ?? '';
          if (v.isNotEmpty && !ClientPhoneRules.isValidEmail(v)) {
            return 'E-mail inválido';
          }
          return null;
        },
      ),
      const SizedBox(height: 12),
      ClientFormRow2(
        minColumnWidth: 150,
        left: ClientFormField(
          controller: _phoneController,
          label: 'Telefone',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneInputFormatter()],
          validator: (_) => _duplicateError('phone'),
        ),
        right: ClientFormField(
          controller: _whatsappController,
          label: 'WhatsApp',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneInputFormatter()],
          validator: (_) => _duplicateError('whatsapp'),
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
        pickYearFirst: true,
        onChanged: (d) => setState(() => _birthDate = d),
      ),
      const ClientFormBand(
        'Dados profissionais',
        icon: Icons.work_outline,
      ),
      ClientFormField(
        controller: _professionController,
        label: 'Profissão',
        hint: 'Ex.: médica, professor',
      ),
      const SizedBox(height: 12),
      ClientFormRow2(
        minColumnWidth: 120,
        left: ClientFormField(
          controller: _companyController,
          label: 'Empresa',
        ),
        right: ClientFormField(
          controller: _jobPositionController,
          label: 'Cargo',
        ),
      ),
      const SizedBox(height: 12),
      ClientFormRow2(
        minColumnWidth: 175,
        left: ClientFormField(
          controller: _incomeController,
          label: 'Renda mensal',
          hint: '0,00',
          prefixText: 'R\$ ',
          keyboardType: TextInputType.number,
          inputFormatters: [CurrencyInputFormatter()],
        ),
        right: ClientDateField(
          label: 'Início no trabalho',
          value: _jobStartDate,
          icon: Icons.event_available_outlined,
          lastDate: DateTime.now(),
          onChanged: (d) => setState(() => _jobStartDate = d),
        ),
      ),
      const SizedBox(height: 8),
      ClientSwitchRow(
        icon: Icons.work_history_outlined,
        title: 'Ainda está trabalhando',
        value: _isCurrentlyWorking,
        onChanged: (v) => setState(() => _isCurrentlyWorking = v),
      ),
      ClientSwitchRow(
        icon: Icons.work_off_outlined,
        title: 'Aposentado(a)',
        value: _isRetired,
        onChanged: (v) => setState(() => _isRetired = v),
      ),
      const ClientFormBand('Observações', icon: Icons.notes_outlined),
      ClientFormField(
        controller: _notesController,
        label: 'Anotações',
        hint: 'Algo importante sobre o cônjuge',
        maxLines: 3,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialSpouse != null;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final cramped = keyboard > 0 && media.size.height - keyboard < 420;

    return Theme(
      data: clientFormTheme(context),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, isEditing),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._buildFields(),
                    if (cramped) ...[
                      const SizedBox(height: 20),
                      _buildActions(isEditing: isEditing, framed: false),
                    ],
                  ],
                ),
              ),
            ),
            if (!cramped) _buildActions(isEditing: isEditing, framed: true),
          ],
        ),
      ),
    );
  }
}
