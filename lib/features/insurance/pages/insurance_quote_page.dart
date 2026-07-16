import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/insurance_models.dart';
import '../services/insurance_service.dart';
import '../widgets/insurance_quote_card.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Tela **Seguros** — cotação de seguro fiança locatícia (paridade com
/// `InsuranceQuotePage.tsx` do imobx-front). Fluxo em 3 passos: dados da
/// locação → comparação de cotações → contratação. Sem `rentalId` (aberta
/// pelo menu) a contratação fica indisponível — a apólice nasce vinculada a
/// uma locação.
///
/// Gate (paridade `rentals.routes.tsx`): módulo `rental_management` +
/// permissão `insurance:create_quote`.
class InsuranceQuotePage extends StatefulWidget {
  final String? rentalId;

  const InsuranceQuotePage({super.key, this.rentalId});

  @override
  State<InsuranceQuotePage> createState() => _InsuranceQuotePageState();
}

class _InsuranceQuotePageState extends State<InsuranceQuotePage> {
  static const double _kPadH = 16;
  static const double _kPadBottom = 88;

  // Permissões (strings exatas do web — rentals.routes.tsx).
  static const String _permCreateQuote = 'insurance:create_quote';
  static const String _moduleRental = 'rental_management';

  int _step = 0;

  // Busca de cliente.
  final TextEditingController _cpfController = TextEditingController();
  InsuranceClient? _client;
  bool _searchingClient = false;
  String? _clientError;

  // Busca de imóvel.
  final TextEditingController _propertyCodeController =
      TextEditingController();
  InsuranceProperty? _property;
  bool _searchingProperty = false;
  String? _propertyError;

  // Dados da locação.
  final TextEditingController _rentController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  // Onde cotar.
  bool _quoteAll = true;
  InsuranceProvider _selectedProvider = InsuranceProvider.pottencial;

  // Cotação em andamento + resultados.
  bool _quoting = false;
  List<InsuranceQuote> _quotes = const [];
  InsuranceQuote? _selectedQuote;

  // Contratação.
  bool _contracting = false;
  InsurancePolicy? _policy;

  bool get _canQuote =>
      ModuleAccessService.instance.hasCompanyModule(_moduleRental) &&
      ModuleAccessService.instance.hasPermission(_permCreateQuote);

  bool get _formReady =>
      _client != null &&
      _property != null &&
      _rentValue > 0 &&
      _startDate != null &&
      _endDate != null;

  double get _rentValue {
    final digits = _rentController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return (int.tryParse(digits) ?? 0) / 100.0;
  }

  @override
  void dispose() {
    _cpfController.dispose();
    _propertyCodeController.dispose();
    _rentController.dispose();
    super.dispose();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : null,
      ),
    );
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _searchClient() async {
    final digits = _cpfController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 11) {
      setState(() => _clientError = 'Informe um CPF válido (11 dígitos).');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searchingClient = true;
      _clientError = null;
      _client = null;
    });
    final res = await InsuranceService.instance.searchClientByCpf(digits);
    if (!mounted) return;
    setState(() {
      _searchingClient = false;
      if (res.success && res.data != null) {
        _client = res.data;
      } else {
        _clientError = res.statusCode == 404
            ? 'Nenhum cliente com esse CPF. Cadastre-o em Clientes primeiro.'
            : (res.message ?? 'Erro ao buscar cliente');
      }
    });
  }

  Future<void> _searchProperty() async {
    final code = _propertyCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _propertyError = 'Digite o código ou ID do imóvel.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searchingProperty = true;
      _propertyError = null;
      _property = null;
    });
    final res = await InsuranceService.instance.getPropertyByCode(code);
    if (!mounted) return;
    setState(() {
      _searchingProperty = false;
      if (res.success && res.data != null) {
        _property = res.data;
        final rent = res.data!.monthlyRent;
        if (rent != null && rent > 0 && _rentController.text.isEmpty) {
          _rentController.text = CurrencyInputFormatter.format(rent);
        }
      } else {
        _propertyError = res.message ?? 'Imóvel não encontrado';
      }
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ??
        (isStart ? now : (_startDate?.add(const Duration(days: 365)) ?? now));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      locale: const Locale('pt', 'BR'),
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

  Future<void> _submitQuote() async {
    if (!_formReady) {
      _snack('Busque o cliente e o imóvel e preencha os dados da locação.',
          error: true);
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      _snack('A data de término deve ser depois do início.', error: true);
      return;
    }

    final apiDate = DateFormat('yyyy-MM-dd');
    final request = InsuranceQuoteRequest(
      provider: _quoteAll ? null : _selectedProvider,
      propertyAddress: _property!.address,
      propertyValue: _property!.value,
      monthlyRent: _rentValue,
      tenantName: _client!.name,
      tenantDocument: _client!.document,
      tenantEmail: _client!.email,
      tenantPhone: _client!.phone,
      rentalStartDate: apiDate.format(_startDate!),
      rentalEndDate: apiDate.format(_endDate!),
      rentalId: widget.rentalId,
    );

    setState(() {
      _quoting = true;
      _quotes = const [];
      _selectedQuote = null;
    });

    if (_quoteAll) {
      final res = await InsuranceService.instance.createQuoteAll(request);
      if (!mounted) return;
      setState(() => _quoting = false);
      if (res.success && res.data != null) {
        final ok = res.data!.where((q) => q.isCompleted).length;
        setState(() {
          _quotes = res.data!;
          _step = 1;
        });
        _snack(ok > 0
            ? '$ok cotaç${ok == 1 ? 'ão recebida' : 'ões recebidas'} com sucesso!'
            : 'Nenhuma seguradora retornou cotação válida.');
      } else {
        _snack(res.message ?? 'Erro ao criar cotações', error: true);
      }
    } else {
      final res = await InsuranceService.instance.createQuote(request);
      if (!mounted) return;
      setState(() => _quoting = false);
      if (res.success && res.data != null) {
        setState(() {
          _quotes = [res.data!];
          _step = 1;
        });
        _snack(res.data!.isCompleted
            ? 'Cotação realizada com sucesso!'
            : 'A seguradora não retornou cotação válida.');
      } else {
        _snack(res.message ?? 'Erro ao criar cotação', error: true);
      }
    }
  }

  Future<void> _contract() async {
    final quote = _selectedQuote;
    final rentalId = widget.rentalId;
    if (quote == null || rentalId == null || rentalId.isEmpty) return;
    setState(() => _contracting = true);
    final res = await InsuranceService.instance.createPolicy(
      quoteId: quote.id,
      rentalId: rentalId,
    );
    if (!mounted) return;
    setState(() => _contracting = false);
    if (res.success && res.data != null) {
      setState(() {
        _policy = res.data;
        _step = 2;
      });
    } else {
      _snack(res.message ?? 'Erro ao contratar seguro', error: true);
    }
  }

  void _restart() {
    setState(() {
      _step = 0;
      _quotes = const [];
      _selectedQuote = null;
      _policy = null;
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canQuote) {
      return const AppScaffold(
        title: 'Seguros',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }

    return AppScaffold(
      title: 'Seguros',
      showBottomNavigation: false,
      body: Theme(
        data: _formTheme(context),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 0),
                child: _buildHero(context),
              ),
              const SizedBox(height: 14),
              _buildStepRail(context),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(_kPadH, 16, _kPadH, _kPadBottom),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: _quoting
                      ? _buildQuotingView(context)
                      : switch (_step) {
                          0 => _buildFormStep(context),
                          1 => _buildResultsStep(context),
                          _ => _buildSuccessStep(context),
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tema local dos campos — filled, foco no tom da marca (mesma gramática
  /// dos steps da ficha de venda).
  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final accent = _accent(context);
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle: TextStyle(
            color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
        floatingLabelStyle: TextStyle(
            color: accent, fontWeight: FontWeight.w700, fontSize: 13.5),
        hintStyle: TextStyle(
            color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
        prefixStyle: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700),
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(accent, 1.6),
      ),
    );
  }

  // ─── Hero flush ──────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final textColor = ThemeHelpers.textColor(context);
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
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'SEGURO FIANÇA',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Cotação de seguro',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: textColor,
            letterSpacing: -0.6,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Compare as seguradoras integradas e escolha a melhor '
          'proteção para a locação.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ─── Rail de passos (flush, sublinhado) ──────────────────────────────────

  Widget _buildStepRail(BuildContext context) {
    final steps = [
      (icon: LucideIcons.clipboardPen, label: 'Dados'),
      (icon: LucideIcons.scale, label: 'Cotações'),
      (icon: LucideIcons.shieldCheck, label: 'Contratação'),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPadH - 8),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: _StepTab(
                icon: steps[i].icon,
                label: steps[i].label,
                index: i,
                current: _step,
                accent: _accent(context),
                // Voltar para o formulário é permitido; avançar não.
                onTap: i == 0 && _step == 1 ? () => setState(() => _step = 0) : null,
              ),
            ),
        ],
      ),
    );
  }

  // ─── Passo 0 — formulário ────────────────────────────────────────────────

  Widget _buildFormStep(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final purple =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final accent = _accent(context);

    return Column(
      key: const ValueKey('step-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          tone: blue,
          icon: LucideIcons.userSearch,
          eyebrow: 'INQUILINO',
          title: 'Quem vai alugar',
          hint: 'Busque o cliente pelo CPF — precisa estar cadastrado.',
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _cpfController,
                keyboardType: TextInputType.number,
                inputFormatters: [CpfInputFormatter()],
                onSubmitted: (_) => _searchClient(),
                decoration: const InputDecoration(
                  labelText: 'CPF do inquilino',
                  hintText: '000.000.000-00',
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SearchButton(
              tone: blue,
              loading: _searchingClient,
              onTap: _searchClient,
            ),
          ],
        ),
        if (_clientError != null) ...[
          const SizedBox(height: 8),
          _InlineNotice(text: _clientError!, kind: _NoticeKind.error),
        ],
        if (_client != null) ...[
          const SizedBox(height: 10),
          _FoundCard(
            icon: LucideIcons.userCheck,
            title: _client!.name,
            lines: [
              'CPF ${Masks.cpf(_client!.document)}',
              if (_client!.email != null) _client!.email!,
              if (_client!.phone != null) _client!.phone!,
            ],
          ),
        ],
        const SizedBox(height: 22),
        _SectionHeader(
          tone: purple,
          icon: LucideIcons.house,
          eyebrow: 'IMÓVEL',
          title: 'O que será alugado',
          hint: 'Busque pelo código do imóvel ou pelo ID.',
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _propertyCodeController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchProperty(),
                decoration: const InputDecoration(
                  labelText: 'Código do imóvel',
                  hintText: 'Ex.: AP0123',
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SearchButton(
              tone: purple,
              loading: _searchingProperty,
              onTap: _searchProperty,
            ),
          ],
        ),
        if (_propertyError != null) ...[
          const SizedBox(height: 8),
          _InlineNotice(text: _propertyError!, kind: _NoticeKind.error),
        ],
        if (_property != null) ...[
          const SizedBox(height: 10),
          _FoundCard(
            icon: LucideIcons.houseWifi,
            title: _property!.address,
            lines: [
              if (_property!.code != null) 'Código ${_property!.code}',
              'Valor ${_money.format(_property!.value)}',
            ],
          ),
        ],
        const SizedBox(height: 22),
        _SectionHeader(
          tone: amber,
          icon: LucideIcons.calendarRange,
          eyebrow: 'LOCAÇÃO',
          title: 'Condições do contrato',
          hint: 'Valor mensal e vigência da locação a segurar.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _rentController,
          keyboardType: TextInputType.number,
          inputFormatters: [CurrencyInputFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Aluguel mensal',
            prefixText: 'R\$ ',
            hintText: '0,00',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Início',
                value: _startDate,
                onTap: () => _pickDate(isStart: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateField(
                label: 'Término',
                value: _endDate,
                onTap: () => _pickDate(isStart: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionHeader(
          tone: accent,
          icon: LucideIcons.building2,
          eyebrow: 'SEGURADORAS',
          title: 'Onde cotar',
          hint: 'Cote em todas de uma vez ou escolha uma seguradora.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ModeChip(
              label: 'Todas as seguradoras',
              icon: LucideIcons.layers,
              selected: _quoteAll,
              tone: accent,
              onTap: () => setState(() => _quoteAll = true),
            ),
            _ModeChip(
              label: 'Uma seguradora',
              icon: LucideIcons.crosshair,
              selected: !_quoteAll,
              tone: accent,
              onTap: () => setState(() => _quoteAll = false),
            ),
          ],
        ),
        if (!_quoteAll) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in InsuranceProvider.selectable)
                _ProviderChip(
                  provider: p,
                  selected: _selectedProvider == p,
                  onTap: () => setState(() => _selectedProvider = p),
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _formReady ? _submitQuote : null,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: accent.withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: -0.1,
              ),
            ),
            icon: const Icon(LucideIcons.scale, size: 18),
            label: Text(
              _quoteAll
                  ? 'Cotar em todas as seguradoras'
                  : 'Cotar na ${_selectedProvider.label}',
            ),
          ),
        ),
        if (!_formReady) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Busque o cliente e o imóvel e preencha valor e vigência.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    ).animate(key: const ValueKey('step-form')).fadeIn(duration: 220.ms);
  }

  // ─── Cotando… (sem pulse — progresso flush por seguradora) ───────────────

  Widget _buildQuotingView(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final providers = _quoteAll
        ? InsuranceProvider.selectable
        : <InsuranceProvider>[_selectedProvider];

    return Column(
      key: const ValueKey('step-quoting'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          _quoteAll
              ? 'Consultando as seguradoras…'
              : 'Consultando ${_selectedProvider.label}…',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Isso pode levar alguns segundos.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: secondary),
        ),
        const SizedBox(height: 20),
        for (final p in providers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: p.brandColor.withValues(alpha: 0.12),
                    border: Border.all(
                      color: p.brandColor.withValues(alpha: 0.35),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    p.monogram,
                    style: TextStyle(
                      color: p.brandColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 3.5,
                          color: p.brandColor,
                          backgroundColor:
                              p.brandColor.withValues(alpha: 0.14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ).animate(key: const ValueKey('step-quoting')).fadeIn(duration: 220.ms);
  }

  // ─── Passo 1 — comparação ────────────────────────────────────────────────

  Widget _buildResultsStep(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(context);
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final completed = _quotes.where((q) => q.isCompleted).toList()
      ..sort((a, b) => a.monthlyPremium.compareTo(b.monthlyPremium));
    final failed = _quotes.where((q) => !q.isCompleted).toList();
    final hasRental = widget.rentalId != null && widget.rentalId!.isNotEmpty;

    return Column(
      key: const ValueKey('step-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          tone: accent,
          icon: LucideIcons.scale,
          eyebrow: 'COMPARAÇÃO',
          title: 'Cotações recebidas',
          hint: completed.isEmpty
              ? 'Nenhuma seguradora retornou cotação válida.'
              : '${completed.length} de ${_quotes.length} seguradora'
                  '${_quotes.length == 1 ? '' : 's'} responderam — '
                  'toque para selecionar.',
        ),
        const SizedBox(height: 14),
        if (completed.isEmpty)
          _EmptyQuotes(onRetry: () => setState(() => _step = 0))
        else
          for (var i = 0; i < completed.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InsuranceQuoteCard(
                quote: completed[i],
                selected: _selectedQuote?.id == completed[i].id,
                isBestPrice: i == 0 && completed.length > 1,
                onTap: () => setState(() => _selectedQuote = completed[i]),
              )
                  .animate(key: ValueKey('q-${completed[i].id}'))
                  .fadeIn(
                    delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                    duration: 220.ms,
                  ),
            ),
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 4),
          _InlineNotice(
            kind: _NoticeKind.warning,
            text: 'Sem resposta: '
                '${failed.map((q) => q.provider.label).join(', ')}.',
          ),
        ],
        const SizedBox(height: 20),
        if (completed.isNotEmpty) ...[
          if (hasRental)
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _selectedQuote == null || _contracting
                    ? null
                    : _contract,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: accent.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                icon: _contracting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.shieldCheck, size: 18),
                label: Text(
                  _contracting
                      ? 'Contratando…'
                      : 'Contratar seguro selecionado',
                ),
              ),
            )
          else
            _InlineNotice(
              kind: _NoticeKind.info,
              text: 'A cotação foi registrada. Para contratar a apólice, '
                  'abra a cotação a partir da locação no painel — a apólice '
                  'nasce vinculada ao contrato.',
            ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: () => setState(() => _step = 0),
          style: OutlinedButton.styleFrom(
            foregroundColor: amber,
            side: BorderSide(color: amber.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(LucideIcons.pencilLine, size: 16),
          label: const Text('Ajustar dados e cotar novamente'),
        ),
      ],
    ).animate(key: const ValueKey('step-results')).fadeIn(duration: 220.ms);
  }

  // ─── Passo 2 — sucesso ───────────────────────────────────────────────────

  Widget _buildSuccessStep(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final policy = _policy;

    return Column(
      key: const ValueKey('step-success'),
      children: [
        const SizedBox(height: 26),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [
              green.withValues(alpha: 0.2),
              green.withValues(alpha: 0.07),
            ]),
            border: Border.all(color: green.withValues(alpha: 0.4)),
          ),
          child: Icon(LucideIcons.shieldCheck, color: green, size: 34),
        ),
        const SizedBox(height: 18),
        Text(
          'Seguro contratado!',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          policy != null && policy.policyNumber.isNotEmpty
              ? 'Apólice ${policy.policyNumber} emitida pela '
                  '${policy.provider.label}.'
              : 'A apólice foi emitida e vinculada à locação.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            height: 1.45,
          ),
        ),
        if (policy != null && policy.monthlyPremium > 0) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: green.withValues(alpha: isDark ? 0.12 : 0.07),
              border: Border.all(color: green.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Text(
                  'PRÊMIO MENSAL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: green,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _money.format(policy.monthlyPremium),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 26),
        OutlinedButton.icon(
          onPressed: _restart,
          style: OutlinedButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(LucideIcons.rotateCcw, size: 16),
          label: const Text('Nova cotação'),
        ),
      ],
    ).animate(key: const ValueKey('step-success')).fadeIn(duration: 260.ms);
  }
}

// ─── Aba de passo (flush, sublinhado — sem pills) ─────────────────────────────

class _StepTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final Color accent;
  final VoidCallback? onTap;

  const _StepTab({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final done = index < current;
    final active = index == current;
    final fg = active
        ? accent
        : done
            ? green
            : ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.1),
        highlightColor: accent.withValues(alpha: 0.05),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(done ? LucideIcons.check : icon, size: 15, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      '${index + 1}. $label',
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            active ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              decoration: BoxDecoration(
                color: active
                    ? accent
                    : done
                        ? green.withValues(alpha: 0.55)
                        : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Cabeçalho de seção (dot + eyebrow + título + hint) ───────────────────────

class _SectionHeader extends StatelessWidget {
  final Color tone;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String hint;

  const _SectionHeader({
    required this.tone,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(icon, color: tone, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Botão de busca quadrado (acompanha o campo) ──────────────────────────────

class _SearchButton extends StatelessWidget {
  final Color tone;
  final bool loading;
  final VoidCallback onTap;

  const _SearchButton({
    required this.tone,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 50,
      height: 50,
      child: Material(
        color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: tone,
                    ),
                  )
                : Icon(LucideIcons.search, size: 19, color: tone),
          ),
        ),
      ),
    );
  }
}

// ─── Card "encontrado" (verde = ok, sem borda lateral) ────────────────────────

class _FoundCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;

  const _FoundCard({
    required this.icon,
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: green.withValues(alpha: 0.35)),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: green.withValues(alpha: isDark ? 0.18 : 0.1),
            ),
            child: Icon(icon, color: green, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.15,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Text(
                      l,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Icon(LucideIcons.circleCheck, size: 18, color: green),
        ],
      ),
    );
  }
}

// ─── Campo de data (mesmo visual filled) ──────────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(
            LucideIcons.calendar,
            size: 17,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        isEmpty: value == null,
        child: value == null
            ? null
            : Text(
                fmt.format(value!),
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
      ),
    );
  }
}

// ─── Chips (modo de cotação / seguradora) ─────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color tone;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? tone : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: selected
          ? tone.withValues(alpha: isDark ? 0.16 : 0.09)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  final InsuranceProvider provider;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderChip({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = provider.brandColor;
    final fg = selected
        ? ThemeHelpers.textColor(context)
        : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: selected
          ? brand.withValues(alpha: isDark ? 0.14 : 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? brand.withValues(alpha: 0.6)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brand,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                provider.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(LucideIcons.check, size: 13, color: brand),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Avisos inline (erro / atenção / info) ────────────────────────────────────

enum _NoticeKind { error, warning, info }

class _InlineNotice extends StatelessWidget {
  final String text;
  final _NoticeKind kind;

  const _InlineNotice({required this.text, required this.kind});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = switch (kind) {
      _NoticeKind.error =>
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
      _NoticeKind.warning =>
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning,
      _NoticeKind.info =>
        isDark ? AppColors.status.infoDarkMode : AppColors.status.info,
    };
    final icon = switch (kind) {
      _NoticeKind.error => LucideIcons.circleAlert,
      _NoticeKind.warning => LucideIcons.triangleAlert,
      _NoticeKind.info => LucideIcons.info,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sem cotações válidas ─────────────────────────────────────────────────────

class _EmptyQuotes extends StatelessWidget {
  final VoidCallback onRetry;

  const _EmptyQuotes({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                amber.withValues(alpha: 0.18),
                amber.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: amber.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.shieldOff, color: amber, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'Nenhuma cotação válida',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'As seguradoras não retornaram propostas para esses dados. '
            'Revise as informações e tente novamente.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Revisar dados'),
          ),
        ],
      ),
    );
  }
}

// ─── Sem permissão ────────────────────────────────────────────────────────────

class _DeniedView extends StatelessWidget {
  const _DeniedView();

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
              'Você não tem acesso à cotação de seguros.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de cotação de seguros.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
