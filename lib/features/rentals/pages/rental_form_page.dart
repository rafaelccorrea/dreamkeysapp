import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../clients/models/client_model.dart';
import '../../clients/services/client_service.dart';
import '../models/rental_models.dart';
import '../services/rental_service.dart';
import '../widgets/rental_property_picker.dart';

/// Formulário de locação — criar (`/rentals/create`) e editar
/// (`/rentals/:id/edit`). Fiel ao `CreateRentalPage.tsx` do web: dados do
/// inquilino (com busca de cliente por CPF/CNPJ), dados do contrato (imóvel +
/// período + vencimento), valores (mensal, caução, multa/juros) e opções
/// (gerar pagamentos, boleto por email). Antes de salvar valida a
/// disponibilidade do imóvel no período (`/rental/check-availability`).
class RentalFormPage extends StatefulWidget {
  final String? rentalId;

  const RentalFormPage({super.key, this.rentalId});

  @override
  State<RentalFormPage> createState() => _RentalFormPageState();
}

class _RentalFormPageState extends State<RentalFormPage> {
  static const double _kPagePadH = 16;

  bool get _isEdit => widget.rentalId != null;

  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();

  // Inquilino
  final _documentController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  // Contrato
  String _propertyId = '';
  String _propertyLabel = '';
  String? _propertyCode;
  DateTime? _startDate;
  DateTime? _endDate;
  final _dueDayController = TextEditingController(text: '5');

  // Valores
  final _monthlyValueController = TextEditingController();
  final _depositController = TextEditingController();
  final _lateFeeController = TextEditingController();
  final _interestController = TextEditingController();

  // Opções
  final _observationsController = TextEditingController();
  bool _autoGeneratePayments = true;
  bool _sendBilletByEmail = false;

  bool _loadingRental = false;
  String? _loadError;
  bool _saving = false;
  bool _searchingClient = false;
  bool _requireApproval = false;

  static final DateFormat _display = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final DateFormat _api = DateFormat('yyyy-MM-dd');

  ModuleAccessService get _access => ModuleAccessService.instance;

  bool get _canSubmit => _isEdit
      ? _access.hasPermission(RentalPermissions.update)
      : _access.hasPermission(RentalPermissions.create);

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadRental();
    } else if (_access.hasPermission(RentalPermissions.manageWorkflows)) {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _documentController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _dueDayController.dispose();
    _monthlyValueController.dispose();
    _depositController.dispose();
    _lateFeeController.dispose();
    _interestController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final res = await RentalService.instance.getRequireApprovalToCreate();
    if (!mounted) return;
    if (res.success && res.data == true) {
      setState(() => _requireApproval = true);
    }
  }

  Future<void> _loadRental() async {
    setState(() {
      _loadingRental = true;
      _loadError = null;
    });
    final res = await RentalService.instance.getById(widget.rentalId!);
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() {
        _loadingRental = false;
        _loadError = res.message ?? 'Erro ao carregar locação';
      });
      return;
    }
    final rental = res.data!;
    setState(() {
      _loadingRental = false;
      _documentController.text = _maskDocument(rental.tenantDocument);
      _nameController.text = rental.tenantName;
      _phoneController.text =
          rental.tenantPhone == null ? '' : Masks.phone(rental.tenantPhone!);
      _emailController.text = rental.tenantEmail ?? '';
      _propertyId = rental.propertyId;
      _propertyLabel = rental.property?.title ?? 'Imóvel vinculado';
      _propertyCode = rental.property?.code;
      _startDate = rental.startDate?.toLocal();
      _endDate = rental.endDate?.toLocal();
      _dueDayController.text = '${rental.dueDay}';
      _monthlyValueController.text =
          CurrencyInputFormatter.format(rental.monthlyValue);
      _depositController.text = (rental.depositValue ?? 0) > 0
          ? CurrencyInputFormatter.format(rental.depositValue)
          : '';
      _lateFeeController.text = rental.lateFeePercent == null
          ? ''
          : _trimPercent(rental.lateFeePercent!);
      _interestController.text = rental.interestPerMonthPercent == null
          ? ''
          : _trimPercent(rental.interestPerMonthPercent!);
      _observationsController.text = rental.observations ?? '';
      _autoGeneratePayments = rental.autoGeneratePayments;
      _sendBilletByEmail = false;
    });
  }

  static String _trimPercent(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return s.endsWith(',00') ? s.substring(0, s.length - 3) : s;
  }

  static String _maskDocument(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 11) return Masks.cpf(digits);
    return Masks.cnpj(digits);
  }

  double _parseMoney(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return (int.tryParse(digits) ?? 0) / 100.0;
  }

  double? _parsePercent(String text) {
    final t = text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    return v.clamp(0, 100).toDouble();
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _searchClient() async {
    final digits = _documentController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 11) {
      _snack('Digite um CPF/CNPJ válido para buscar o cliente.', error: true);
      return;
    }
    setState(() => _searchingClient = true);
    final res = await ClientService.instance.getClients(
      filters: ClientSearchFilters(document: digits, limit: 10),
    );
    if (!mounted) return;
    setState(() => _searchingClient = false);
    final list = res.success ? (res.data?.data ?? const <Client>[]) : const <Client>[];
    if (list.isEmpty) {
      _snack(
        res.success
            ? 'Cliente não encontrado.'
            : (res.message ?? 'Erro ao buscar cliente.'),
        error: true,
      );
      return;
    }
    final client = list.first;
    setState(() {
      if (client.name.trim().isNotEmpty) _nameController.text = client.name;
      if (client.email.trim().isNotEmpty) _emailController.text = client.email;
      if (client.phone.trim().isNotEmpty) {
        _phoneController.text = Masks.phone(client.phone);
      }
    });
    _snack('Cliente encontrado! Dados preenchidos.');
  }

  Future<void> _pickProperty() async {
    final property = await showRentalPropertyPicker(context);
    if (property == null || !mounted) return;
    setState(() {
      _propertyId = property.id;
      _propertyLabel = property.title;
      _propertyCode = property.code;
      // Pré-preenche o valor mensal com o preço de aluguel do imóvel
      // (paridade com a busca por código no web) — sem sobrescrever o que o
      // usuário já digitou.
      if (_monthlyValueController.text.trim().isEmpty &&
          (property.rentPrice ?? 0) > 0) {
        _monthlyValueController.text =
            CurrencyInputFormatter.format(property.rentPrice);
      }
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = _isEdit
        ? DateTime(2015)
        : (isStart ? today : (_startDate ?? today));
    final initialCandidate =
        (isStart ? _startDate : _endDate) ?? (isStart ? today : (_startDate ?? today));
    final initial = initialCandidate.isBefore(first) ? first : initialCandidate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
      helpText: isStart ? 'Data de início' : 'Data de término',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && !_endDate!.isAfter(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_propertyId.isEmpty) {
      _snack('Selecione o imóvel da locação.', error: true);
      return;
    }
    if (_startDate == null || _endDate == null) {
      _snack('Informe o período do contrato.', error: true);
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      _snack('A data de término deve ser posterior à de início.', error: true);
      return;
    }

    setState(() => _saving = true);

    // Trava do web: imóvel precisa estar livre no período.
    final availability = await RentalService.instance.checkAvailability(
      propertyId: _propertyId,
      startDate: _api.format(_startDate!),
      endDate: _api.format(_endDate!),
      excludeRentalId: _isEdit ? widget.rentalId : null,
    );
    if (!mounted) return;
    if (availability.success && availability.data == false) {
      setState(() => _saving = false);
      _snack(
        'Este imóvel já possui um aluguel no período informado. '
        'Escolha outras datas ou outro imóvel.',
        error: true,
      );
      return;
    }

    final payload = RentalPayload(
      tenantName: _nameController.text.trim(),
      tenantDocument: _documentController.text.replaceAll(RegExp(r'\D'), ''),
      tenantPhone: _phoneController.text.replaceAll(RegExp(r'\D'), ''),
      tenantEmail: _emailController.text.trim(),
      startDate: _api.format(_startDate!),
      endDate: _api.format(_endDate!),
      monthlyValue: _parseMoney(_monthlyValueController.text),
      dueDay: (int.tryParse(_dueDayController.text) ?? 5).clamp(1, 31),
      propertyId: _propertyId,
      observations: _observationsController.text,
      depositValue: _parseMoney(_depositController.text),
      autoGeneratePayments: _autoGeneratePayments,
      sendBilletByEmail:
          _emailController.text.trim().isNotEmpty && _sendBilletByEmail,
      lateFeePercent: _parsePercent(_lateFeeController.text),
      interestPerMonthPercent: _parsePercent(_interestController.text),
    );

    final res = _isEdit
        ? await RentalService.instance.update(widget.rentalId!, payload)
        : await RentalService.instance.create(payload);
    if (!mounted) return;
    setState(() => _saving = false);

    if (!res.success) {
      _snack(res.message ?? 'Erro ao salvar locação.', error: true);
      return;
    }

    if (!_isEdit && res.data?.status == RentalStatus.pendingApproval) {
      _snack(
        'Locação enviada para aprovação — um usuário com a permissão de '
        'gerenciar fluxos precisará confirmar.',
      );
    } else {
      _snack(_isEdit
          ? 'Locação atualizada com sucesso.'
          : 'Locação criada com sucesso.');
    }
    Navigator.of(context).pop(true);
  }

  void _snack(String message, {bool error = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : null,
      ),
    );
  }

  // ─── Tema dos campos (filled, mesmo DNA da ficha de venda) ───────────────

  ThemeData _formTheme(BuildContext context) {
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
      colorScheme: base.colorScheme.copyWith(primary: _accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _accent,
        selectionColor: _accent.withValues(alpha: 0.18),
        selectionHandleColor: _accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle: TextStyle(
            color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
        floatingLabelStyle: TextStyle(
            color: _accent, fontWeight: FontWeight.w700, fontSize: 13.5),
        hintStyle: TextStyle(
            color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
        prefixStyle: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700),
        suffixStyle: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700),
        errorStyle: const TextStyle(fontSize: 11.5, height: 1.2),
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
        errorBorder: b(
            Theme.of(context).brightness == Brightness.dark
                ? AppColors.status.errorDarkMode
                : AppColors.status.error,
            1.2),
        focusedErrorBorder: b(
            Theme.of(context).brightness == Brightness.dark
                ? AppColors.status.errorDarkMode
                : AppColors.status.error,
            1.6),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Editar Locação' : 'Nova Locação';
    if (!_canSubmit) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        body: _DeniedView(isEdit: _isEdit),
      );
    }
    if (_loadingRental) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        body: _buildSkeleton(context),
      );
    }
    if (_loadError != null) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        body: _buildLoadError(context),
      );
    }
    return AppScaffold(
      title: title,
      showBottomNavigation: false,
      body: Theme(
        data: _formTheme(context),
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                      _kPagePadH, 12, _kPagePadH, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHero(context),
                      if (!_isEdit && _requireApproval) ...[
                        const SizedBox(height: 14),
                        _buildApprovalAlert(context),
                      ],
                      const SizedBox(height: 8),
                      _buildTenantSection(context),
                      _buildContractSection(context),
                      _buildValuesSection(context),
                      _buildOptionsSection(context),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
            _buildSaveBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              _isEdit ? 'EDITAR CONTRATO' : 'NOVO CONTRATO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _isEdit ? 'Atualize o contrato de aluguel' : 'Cadastre uma locação',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _isEdit
              ? 'As alterações valem para as próximas cobranças do contrato.'
              : 'Inquilino, imóvel, período e valores — tudo em uma etapa.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildApprovalAlert(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 18, color: amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pela configuração da empresa, novas locações são criadas como '
              '"Aguardando aprovação" — alguém com a permissão de gerenciar '
              'fluxos precisará confirmar para ativar o contrato e gerar as '
              'cobranças.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Seções ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(
    BuildContext context, {
    required Color tone,
    required IconData icon,
    required String label,
    required String hint,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
            ),
            child: Icon(icon, color: tone, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTenantSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          context,
          tone: tone,
          icon: LucideIcons.user,
          label: 'Inquilino',
          hint: 'Busque pelo CPF/CNPJ para preencher com um cliente da base.',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _documentController,
                keyboardType: TextInputType.number,
                inputFormatters: [_DocumentInputFormatter()],
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.isEmpty) return 'Informe o CPF/CNPJ';
                  if (digits.length != 11 && digits.length != 14) {
                    return 'CPF/CNPJ inválido';
                  }
                  return null;
                },
                style: _fieldStyle(context),
                decoration:
                    const InputDecoration(labelText: 'CPF/CNPJ do inquilino *'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _searchingClient ? null : _searchClient,
                style: OutlinedButton.styleFrom(
                  foregroundColor: tone,
                  side: BorderSide(color: tone.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: _searchingClient
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: tone),
                      )
                    : const Icon(LucideIcons.search, size: 16),
                label: const Text(
                  'Buscar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Informe o nome do inquilino' : null,
          style: _fieldStyle(context),
          decoration: const InputDecoration(labelText: 'Nome completo *'),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneInputFormatter()],
                style: _fieldStyle(context),
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
                  return ok ? null : 'Email inválido';
                },
                style: _fieldStyle(context),
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContractSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasProperty = _propertyId.isNotEmpty;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          context,
          tone: tone,
          icon: LucideIcons.house,
          label: 'Contrato',
          hint: 'Imóvel alugado, período de vigência e dia de vencimento.',
        ),
        // Seletor de imóvel
        InkWell(
          onTap: _pickProperty,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasProperty
                    ? tone.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                  ),
                  child: Icon(
                    hasProperty ? LucideIcons.house : LucideIcons.housePlus,
                    color: tone,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasProperty ? _propertyLabel : 'Selecionar imóvel *',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              hasProperty ? FontWeight.w800 : FontWeight.w600,
                          color: hasProperty
                              ? ThemeHelpers.textColor(context)
                              : secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasProperty
                            ? ((_propertyCode ?? '').isNotEmpty
                                ? 'CÓD $_propertyCode · toque para trocar'
                                : 'Toque para trocar o imóvel')
                            : 'Busque por código, título ou endereço',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 17, color: secondary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Início *',
                value: _startDate,
                display: _display,
                onTap: () => _pickDate(isStart: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateField(
                label: 'Término *',
                value: _endDate,
                display: _display,
                onTap: () => _pickDate(isStart: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _dueDayController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1 || n > 31) return 'Entre 1 e 31';
                  return null;
                },
                style: _fieldStyle(context),
                decoration: const InputDecoration(
                  labelText: 'Dia de vencimento *',
                  hintText: '5',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Dia do mês para o vencimento das parcelas.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    height: 1.35,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildValuesSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          context,
          tone: tone,
          icon: LucideIcons.banknote,
          label: 'Valores',
          hint: 'Aluguel mensal, caução e encargos por atraso (opcionais).',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _monthlyValueController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                validator: (v) =>
                    _parseMoney(v ?? '') <= 0 ? 'Informe o valor' : null,
                style: _fieldStyle(context),
                decoration: const InputDecoration(
                  labelText: 'Valor mensal *',
                  prefixText: 'R\$ ',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _depositController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                style: _fieldStyle(context),
                decoration: const InputDecoration(
                  labelText: 'Depósito/caução',
                  prefixText: 'R\$ ',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _lateFeeController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return null;
                  return _parsePercent(v!) == null ? 'Valor inválido' : null;
                },
                style: _fieldStyle(context),
                decoration: const InputDecoration(
                  labelText: 'Multa em atraso',
                  hintText: 'Ex.: 2',
                  suffixText: '%',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _interestController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return null;
                  return _parsePercent(v!) == null ? 'Valor inválido' : null;
                },
                style: _fieldStyle(context),
                decoration: const InputDecoration(
                  labelText: 'Juros ao mês',
                  hintText: 'Ex.: 1',
                  suffixText: '%',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionsSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final hasEmail = _emailController.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          context,
          tone: tone,
          icon: LucideIcons.settings2,
          label: 'Opções',
          hint: 'Observações do contrato e automações de cobrança.',
        ),
        TextFormField(
          controller: _observationsController,
          maxLines: 4,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: _fieldStyle(context),
          decoration: const InputDecoration(
            labelText: 'Observações',
            hintText: 'Informações adicionais sobre o contrato…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 6),
        _OptionSwitch(
          value: _autoGeneratePayments,
          accent: _accent,
          title: 'Gerar pagamentos automaticamente',
          subtitle:
              'Cria as parcelas mensais com base no período do contrato.',
          onChanged: (v) => setState(() => _autoGeneratePayments = v),
        ),
        if (hasEmail)
          _OptionSwitch(
            value: _sendBilletByEmail,
            accent: _accent,
            title: 'Enviar boleto por email',
            subtitle:
                'Envia a cobrança para ${_emailController.text.trim()}.',
            onChanged: (v) => setState(() => _sendBilletByEmail = v),
          ),
      ],
    );
  }

  TextStyle _fieldStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textColor(context),
          );

  Widget _buildSaveBar(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
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
            flex: 3,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.check, size: 17),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : (_isEdit ? 'Salvar alterações' : 'Criar locação'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Estados de carregamento/erro (edição) ───────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    Widget field() => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SkeletonBox(
              width: double.infinity, height: 50, borderRadius: 14),
        );
    Widget section() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 14),
              child: Row(
                children: [
                  SkeletonBox(width: 38, height: 38, borderRadius: 13),
                  const SizedBox(width: 11),
                  const SkeletonText(width: 150, height: 13),
                ],
              ),
            ),
            field(),
            field(),
          ],
        );
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPagePadH, 16, _kPagePadH, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkeletonText(width: 130, height: 11),
          const SizedBox(height: 10),
          const SkeletonText(width: 230, height: 22),
          section(),
          section(),
          section(),
        ],
      ),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: danger.withValues(alpha: 0.12),
                border: Border.all(color: danger.withValues(alpha: 0.32)),
              ),
              child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadRental,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Campo de data (mesmo visual filled dos inputs) ──────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateFormat display;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.display,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final filled = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, size: 16, color: secondary),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (filled)
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  Text(
                    filled ? display.format(value!) : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          filled ? FontWeight.w700 : FontWeight.w600,
                      color: filled
                          ? ThemeHelpers.textColor(context)
                          : secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Switch de opção (flush, ação no próprio item) ───────────────────────────

class _OptionSwitch extends StatelessWidget {
  final bool value;
  final Color accent;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const _OptionSwitch({
    required this.value,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: value,
              activeTrackColor: accent,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Formatter CPF/CNPJ dinâmico ─────────────────────────────────────────────

class _DocumentInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.length > 14 ? digits.substring(0, 14) : digits;
    final masked =
        limited.length <= 11 ? Masks.cpf(limited) : Masks.cnpj(limited);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class _DeniedView extends StatelessWidget {
  final bool isEdit;
  const _DeniedView({required this.isEdit});

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              isEdit
                  ? 'Você não tem permissão para editar locações.'
                  : 'Você não tem permissão para criar locações.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite o acesso ao administrador da sua empresa.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
