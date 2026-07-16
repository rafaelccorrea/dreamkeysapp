import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/notifications/app_toast.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/cep_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/loading_overlay.dart';
import '../models/onboarding_models.dart';
import '../services/onboarding_service.dart';
import '../utils/document_input.dart';
import '../widgets/onboarding_text_field.dart';

/// Wizard de criação da primeira empresa — paridade com
/// `CreateFirstCompanyPage.tsx` do `imobx-front` (3 passos: identidade,
/// contato e endereço). Destrava o app: ao concluir, grava o `companyId`
/// selecionado e navega para a Home.
///
/// Tela pós-login SEM drawer/bottom nav (o usuário ainda não tem empresa,
/// então os módulos do menu nem existem) — mas com o mesmo fundo de shell
/// e a gramática flush do cânone (eyebrow + título + chips de progresso,
/// conteúdo nas margens, card sem borda lateral, sombras neutras).
class CreateFirstCompanyPage extends StatefulWidget {
  const CreateFirstCompanyPage({super.key});

  @override
  State<CreateFirstCompanyPage> createState() => _CreateFirstCompanyPageState();
}

class _StepMeta {
  final String short;
  final String title;
  final String subtitle;
  final IconData icon;

  const _StepMeta({
    required this.short,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

const List<_StepMeta> _steps = [
  _StepMeta(
    short: 'Identidade',
    title: 'Identidade da empresa',
    subtitle: 'Conte como sua imobiliária se chama e o seu CNPJ.',
    icon: Icons.business_rounded,
  ),
  _StepMeta(
    short: 'Contato',
    title: 'Informações de contato',
    subtitle: 'Por onde clientes e a plataforma entram em contato com você.',
    icon: Icons.alternate_email_rounded,
  ),
  _StepMeta(
    short: 'Endereço',
    title: 'Endereço da sede',
    subtitle: 'Informe o CEP para completar o endereço automaticamente.',
    icon: Icons.location_on_outlined,
  ),
];

class _CreateFirstCompanyPageState extends State<CreateFirstCompanyPage> {
  // Uma key de Form por passo — só o passo visível é validado.
  final List<GlobalKey<FormState>> _stepKeys = [
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
  ];

  // Passo 1 — identidade
  final _nameController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _corporateNameController = TextEditingController();

  // Passo 2 — contato
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  // Passo 3 — endereço
  final _zipCodeController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _complementController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();

  int _currentStep = 0;
  bool _isSubmitting = false;
  bool _isSearchingCep = false;
  bool _hasExistingCompany = false;
  String? _error;
  String _lastSearchedCep = '';

  @override
  void initState() {
    super.initState();
    // Paridade com o web: se o owner já tem empresa, o formulário trava e
    // oferecemos o caminho para o painel (evita empresa duplicada).
    _checkExistingCompany();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cnpjController.dispose();
    _corporateNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _zipCodeController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingCompany() async {
    final hasCompany =
        await OnboardingService.instance.userAlreadyHasCompany();
    if (mounted && hasCompany) {
      setState(() => _hasExistingCompany = true);
    }
  }

  // ── Navegação entre passos ───────────────────────────────────────────────

  void _handleNext() {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (_stepKeys[_currentStep].currentState?.validate() != true) return;
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    }
  }

  void _handleBack() {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      if (_currentStep > 0) _currentStep--;
    });
  }

  void _goToDashboard() {
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  // ── CEP → ViaCEP autofill ────────────────────────────────────────────────

  Future<void> _onZipCodeChanged(String value) async {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 8 || digits == _lastSearchedCep) return;
    _lastSearchedCep = digits;

    setState(() => _isSearchingCep = true);
    final address = await CepService.instance.searchCep(digits);
    if (!mounted) return;

    setState(() => _isSearchingCep = false);
    if (address == null) return;

    // Preenche apenas o que veio — sem apagar o que o usuário já digitou.
    if ((address.street ?? '').isNotEmpty) {
      _streetController.text = address.street!;
    }
    if ((address.neighborhood ?? '').isNotEmpty) {
      _neighborhoodController.text = address.neighborhood!;
    }
    if ((address.city ?? '').isNotEmpty) {
      _cityController.text = address.city!;
    }
    if ((address.state ?? '').isNotEmpty) {
      _stateController.text = address.state!.toUpperCase();
    }
  }

  // ── Submissão ────────────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    if (_hasExistingCompany) {
      setState(() => _error = 'Você já possui uma empresa cadastrada.');
      return;
    }
    setState(() => _error = null);
    if (_stepKeys[_currentStep].currentState?.validate() != true) return;

    setState(() => _isSubmitting = true);

    final request = CreateFirstCompanyRequest(
      name: _nameController.text,
      cnpj: _cnpjController.text,
      corporateName: _corporateNameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      street: _streetController.text,
      number: _numberController.text,
      complement: _complementController.text,
      neighborhood: _neighborhoodController.text,
      city: _cityController.text,
      state: _stateController.text,
      zipCode: _zipCodeController.text,
    );

    try {
      final response =
          await OnboardingService.instance.createFirstCompany(request);

      if (!mounted) return;

      if (response.success && response.data != null) {
        AppToast.success(
          context,
          'Empresa criada com sucesso!',
          subtitle: 'Bem-vindo ao Intellisys, ${response.data!.name}.',
        );
        _goToDashboard();
        return;
      }

      // Fallback de paridade com o web: se o POST falhou mas a empresa já
      // existe (ex.: retry após timeout), seguimos para o painel.
      final alreadyHas =
          await OnboardingService.instance.userAlreadyHasCompany();
      if (!mounted) return;
      if (alreadyHas) {
        _goToDashboard();
        return;
      }

      setState(() {
        _error = _friendlyError(response.statusCode, response.message);
        _isSubmitting = false;
      });
    } catch (e) {
      debugPrint('💥 [FIRST_COMPANY] Exceção: $e');
      if (mounted) {
        setState(() {
          _error =
              'Falha de conexão com o servidor. Verifique sua internet e tente de novo.';
          _isSubmitting = false;
        });
      }
    }
  }

  /// Mapeia erros como o `onSubmit` do web.
  String _friendlyError(int statusCode, String? message) {
    if (statusCode == 400) {
      return 'Dados inválidos. Verifique os campos.';
    }
    if (statusCode == 403) {
      return message?.isNotEmpty == true
          ? message!
          : 'Sem permissão para criar empresa. Verifique sua assinatura.';
    }
    return message?.isNotEmpty == true
        ? message!
        : 'Erro ao criar empresa. Tente novamente.';
  }

  // ── Validações (espelham o createCompanySchema do web) ───────────────────

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Nome da empresa é obrigatório';
    }
    if (value.trim().length < 2) {
      return 'Nome deve ter pelo menos 2 caracteres';
    }
    return null;
  }

  String? _validateCorporateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Razão social é obrigatória';
    }
    if (value.trim().length < 2) {
      return 'Razão social deve ter pelo menos 2 caracteres';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Telefone é obrigatório';
    }
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10 || digits.length > 11) {
      return 'Telefone deve estar no formato (XX) XXXXX-XXXX';
    }
    return null;
  }

  String? _validateState(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Estado é obrigatório';
    }
    if (value.trim().length != 2) {
      return 'Estado deve ter 2 caracteres';
    }
    return null;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);

    return LoadingOverlay(
      isLoading: _isSubmitting,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: ThemeHelpers.shellBackgroundDecoration(context),
                ),
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHero(isDark),
                            const SizedBox(height: 18),
                            if (_hasExistingCompany) ...[
                              _buildExistingCompanyBanner(isDark),
                              const SizedBox(height: 16),
                            ],
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.04, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: _buildStepCard(isDark),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              _buildErrorBanner(isDark),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _buildActionsBar(isDark, mediaQuery.padding.bottom),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero flush: eyebrow + título + chips de progresso ────────────────────

  Widget _buildHero(bool isDark) {
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'ONBOARDING · EMPRESA',
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: isDark
                    ? AppColors.text.textLightDarkMode
                    : AppColors.text.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        RichText(
          text: TextSpan(
            text: 'Crie sua ',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color:
                  isDark ? AppColors.text.textDarkMode : AppColors.text.text,
              height: 1.15,
            ),
            children: [
              TextSpan(
                text: 'primeira empresa',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Em três passos você configura a imobiliária e libera imóveis, '
          'clientes e relatórios no app.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: isDark
                ? AppColors.text.textSecondaryDarkMode
                : AppColors.text.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        _buildStepChips(isDark),
      ],
    );
  }

  Widget _buildStepChips(bool isDark) {
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final ok = isDark
        ? AppColors.message.successTextDarkMode
        : AppColors.message.successText;
    final muted =
        isDark ? AppColors.text.textLightDarkMode : AppColors.text.textLight;
    final border =
        isDark ? AppColors.border.borderDarkMode : AppColors.border.border;

    return Row(
      children: List.generate(_steps.length, (index) {
        final step = _steps[index];
        final isDone = index < _currentStep;
        final isActive = index == _currentStep;
        final color = isDone ? ok : (isActive ? accent : muted);

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: index == _steps.length - 1 ? 0 : 8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDone || isActive
                        ? color
                        : border.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDone ? Icons.check_circle_rounded : step.icon,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        step.short,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isDone || isActive
                              ? (isDark
                                  ? AppColors.text.textDarkMode
                                  : AppColors.text.text)
                              : muted,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── Card do passo (sem borda lateral, sombra neutra) ─────────────────────

  Widget _buildStepCard(bool isDark) {
    final step = _steps[_currentStep];
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    return Container(
      key: ValueKey('step-$_currentStep'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Form(
        key: _stepKeys[_currentStep],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PASSO ${_currentStep + 1} DE ${_steps.length}',
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              step.title,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? AppColors.text.textDarkMode : AppColors.text.text,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              step.subtitle,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.text.textSecondaryDarkMode
                    : AppColors.text.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            switch (_currentStep) {
              0 => _buildIdentityFields(isDark),
              1 => _buildContactFields(),
              _ => _buildAddressFields(isDark),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityFields(bool isDark) {
    return Column(
      children: [
        OnboardingTextField(
          controller: _nameController,
          label: 'Nome da empresa',
          hint: 'Ex: Imobiliária ABC',
          prefixIcon: Icons.business_rounded,
          enabled: !_hasExistingCompany,
          validator: _validateName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        OnboardingTextField(
          controller: _cnpjController,
          label: 'CNPJ',
          hint: '00.000.000/0001-00',
          prefixIcon: Icons.badge_outlined,
          keyboardType: TextInputType.text,
          maxLength: 18,
          enabled: !_hasExistingCompany,
          inputFormatters: [AlnumCnpjInputFormatter()],
          validator: OnboardingDocumentUtils.validateCnpjField,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        OnboardingTextField(
          controller: _corporateNameController,
          label: 'Razão social',
          hint: 'Ex: ABC Negócios Imobiliários Ltda.',
          prefixIcon: Icons.article_outlined,
          enabled: !_hasExistingCompany,
          validator: _validateCorporateName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Nome jurídico exatamente como no cartão CNPJ '
            '(com Ltda., S.A., ME ou EIRELI, se houver).',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: isDark
                  ? AppColors.text.textLightDarkMode
                  : AppColors.text.textLight,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactFields() {
    return Column(
      children: [
        OnboardingTextField(
          controller: _emailController,
          label: 'E-mail da empresa',
          hint: 'contato@imobiliariaabc.com',
          prefixIcon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          enabled: !_hasExistingCompany,
          validator: Validators.requiredEmail,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        OnboardingTextField(
          controller: _phoneController,
          label: 'Telefone',
          hint: '(11) 99999-9999',
          prefixIcon: Icons.phone_iphone_rounded,
          keyboardType: TextInputType.phone,
          maxLength: 15,
          enabled: !_hasExistingCompany,
          inputFormatters: [PhoneInputFormatter()],
          validator: _validatePhone,
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _buildAddressFields(bool isDark) {
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    return Column(
      children: [
        OnboardingTextField(
          controller: _zipCodeController,
          label: 'CEP',
          hint: '00000-000',
          prefixIcon: Icons.pin_drop_outlined,
          keyboardType: TextInputType.number,
          maxLength: 9,
          enabled: !_hasExistingCompany,
          inputFormatters: [CepInputFormatter()],
          validator: Validators.cep,
          onChanged: _onZipCodeChanged,
          textInputAction: TextInputAction.next,
          suffixIcon: _isSearchingCep
              ? Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        OnboardingTextField(
          controller: _streetController,
          label: 'Rua',
          prefixIcon: Icons.signpost_outlined,
          enabled: !_hasExistingCompany,
          validator: (v) =>
              Validators.required(v, message: 'Rua é obrigatória'),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OnboardingTextField(
                controller: _numberController,
                label: 'Número',
                keyboardType: TextInputType.streetAddress,
                enabled: !_hasExistingCompany,
                validator: (v) =>
                    Validators.required(v, message: 'Número é obrigatório'),
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: OnboardingTextField(
                controller: _complementController,
                label: 'Complemento (opcional)',
                enabled: !_hasExistingCompany,
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        OnboardingTextField(
          controller: _neighborhoodController,
          label: 'Bairro',
          prefixIcon: Icons.map_outlined,
          enabled: !_hasExistingCompany,
          validator: (v) =>
              Validators.required(v, message: 'Bairro é obrigatório'),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: OnboardingTextField(
                controller: _cityController,
                label: 'Cidade',
                enabled: !_hasExistingCompany,
                validator: (v) =>
                    Validators.required(v, message: 'Cidade é obrigatória'),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OnboardingTextField(
                controller: _stateController,
                label: 'UF',
                hint: 'SP',
                maxLength: 2,
                enabled: !_hasExistingCompany,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                  UppercaseInputFormatter(),
                ],
                validator: _validateState,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleSubmit(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Banners ──────────────────────────────────────────────────────────────

  Widget _buildExistingCompanyBanner(bool isDark) {
    final infoColor = AppColors.status.info;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: infoColor.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: infoColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: infoColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Você já possui uma empresa cadastrada',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.text.textDarkMode
                        : AppColors.text.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Para criar uma nova empresa principal, entre em contato com o '
            'suporte. Enquanto isso, acesse o painel normalmente.',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: isDark
                  ? AppColors.text.textSecondaryDarkMode
                  : AppColors.text.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _goToDashboard,
              icon: Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: infoColor,
              ),
              label: Text(
                'Ir para o painel',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: infoColor,
                ),
              ),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(bool isDark) {
    final err =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: err.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: err.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: err),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error ?? '',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: err,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Barra de ações (Voltar / Continuar / Criar empresa) ──────────────────

  Widget _buildActionsBar(bool isDark, double bottomInset) {
    final isLastStep = _currentStep == _steps.length - 1;
    final border =
        isDark ? AppColors.border.borderDarkMode : AppColors.border.border;
    final fg = isDark ? AppColors.text.textDarkMode : AppColors.text.text;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + bottomInset),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed:
                    _isSubmitting || _hasExistingCompany ? null : _handleBack,
                icon: Icon(Icons.arrow_back_rounded, size: 18, color: fg),
                label: Text(
                  'Voltar',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: ThemeHelpers.cardBackgroundColor(context),
                  side: BorderSide(color: border, width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: _buildPrimaryAction(
              isDark: isDark,
              label: isLastStep ? 'Criar empresa' : 'Continuar',
              icon: isLastStep
                  ? Icons.check_rounded
                  : Icons.arrow_forward_rounded,
              onTap: _isSubmitting || _hasExistingCompany
                  ? null
                  : (isLastStep ? _handleSubmit : _handleNext),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction({
    required bool isDark,
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final base =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final dark = isDark
        ? AppColors.primary.primaryDarkDarkMode
        : AppColors.primary.primaryDark;
    final disabled = onTap == null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: disabled
              ? [base.withValues(alpha: 0.55), dark.withValues(alpha: 0.55)]
              : [base, dark],
        ),
        boxShadow: disabled
            ? []
            : [
                BoxShadow(
                  color: base.withValues(alpha: isDark ? 0.45 : 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
