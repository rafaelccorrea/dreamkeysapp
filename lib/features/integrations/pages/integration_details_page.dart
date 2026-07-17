import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/integration_model.dart';
import '../services/integrations_service.dart';
import '../widgets/integration_card.dart' show integrationStatusColor;
import '../widgets/integration_logo.dart';

/// Caminho da configuração completa no painel web, por integração.
/// Mostrado no card "Configuração completa" como orientação.
const Map<String, String> _kWebConfigPath = {
  'whatsapp': 'Integrações → WhatsApp → Configurações',
  'whatsapp-lead-claim': 'Integrações → WhatsApp → Atribuição por grupo',
  'chat-pro': 'Integrações → ChatPro (Sparks)',
  'meta-campaign': 'Integrações → Campanhas META',
  'system-campaigns': 'Integrações → Campanhas do Sistema',
  'google-ads': 'Integrações → Google Ads',
  'ga4': 'Integrações → Google Analytics 4',
  'grupo-zap': 'Integrações → Portal Grupo ZAP',
  'properties-api': 'Integrações → API de Imóveis',
  'chaves-na-mao': 'Integrações → Portal Chaves na Mão',
  'imovelweb': 'Integrações → Imovelweb / Wimoveis / Casa Mineira',
  'custom-leads': 'Integrações → Webhook de Leads',
  'ficha-webhooks': 'Integrações → Webhook de Fichas',
  'autentique': 'Integrações → Autentique',
};

/// **Detalhe da integração** (`/integrations/:key`) — versão mobile do card
/// expandido do hub web: hero flush com glyph na cor da marca, status pill,
/// informações de conexão vindas do payload real e ações leves (ativar/
/// desativar e testar conexão) quando o backend expõe endpoint próprio.
/// Configurações pesadas apontam para o painel web.
class IntegrationDetailsPage extends StatefulWidget {
  final String integrationKey;

  const IntegrationDetailsPage({super.key, required this.integrationKey});

  @override
  State<IntegrationDetailsPage> createState() => _IntegrationDetailsPageState();
}

class _IntegrationDetailsPageState extends State<IntegrationDetailsPage> {
  static const double _kPadH = 16;

  final IntegrationsService _service = IntegrationsService.instance;

  IntegrationDef? get _def => IntegrationCatalog.byKey(widget.integrationKey);

  bool _loading = true;
  String? _error;
  IntegrationStatusData? _status;

  bool _toggling = false;
  bool _testing = false;
  IntegrationTestResult? _testResult;

  bool get _canView {
    final def = _def;
    if (def == null) return false;
    final svc = ModuleAccessService.instance;
    final hasModule = IntegrationPermissions.hubModules.any(
      svc.hasCompanyModule,
    );
    return hasModule && svc.hasAnyPermission(def.viewPermissions);
  }

  bool get _canManage {
    final def = _def;
    if (def == null) return false;
    return ModuleAccessService.instance.hasAnyPermission(
      def.managePermissions,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Color _emerald(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;

  Color _amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;

  Color _danger(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.errorDarkMode
          : AppColors.status.error;

  // ─── Dados ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final def = _def;
    if (def == null || !_canView) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _service.fetchStatus(def.key);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _status = res.data;
      } else {
        _error = res.message ?? 'Erro ao carregar o status da integração';
      }
    });
  }

  void _toast(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            ok ? AppColors.status.success : AppColors.status.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── Ações leves ──────────────────────────────────────────────────────────

  Future<void> _onToggle(bool value) async {
    final def = _def;
    if (def == null || _toggling) return;

    // Desativar merece confirmação — pode parar sincronização em produção.
    if (!value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final danger = _danger(ctx);
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text(
              'Desativar integração?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            content: Text(
              'A sincronização de "${def.name}" será interrompida para toda a '
              'empresa até que alguém a reative.',
              style: const TextStyle(height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: danger),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Desativar'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }

    setState(() => _toggling = true);
    final res = await _service.setActive(def.key, value);
    if (!mounted) return;
    setState(() => _toggling = false);
    if (res.success) {
      _toast(
        value ? 'Integração ativada com sucesso.' : 'Integração desativada.',
        ok: true,
      );
      await _load();
    } else {
      _toast(
        res.message ??
            (value
                ? 'Erro ao ativar a integração'
                : 'Erro ao desativar a integração'),
        ok: false,
      );
    }
  }

  Future<void> _onTest() async {
    final def = _def;
    if (def == null || _testing) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final res = await _service.testConnection(def.key);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = res.success && res.data != null
          ? res.data
          : IntegrationTestResult(
              ok: false,
              message: res.message ?? 'Falha no teste de conexão.',
            );
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final def = _def;
    if (def == null) {
      return AppScaffold(
        title: 'Integração',
        showBottomNavigation: false,
        body: _MessageView(
          icon: LucideIcons.searchX,
          title: 'Integração não encontrada',
          body:
              'O endereço "/integrations/${widget.integrationKey}" não '
              'corresponde a nenhuma integração disponível.',
        ),
      );
    }
    if (!_canView) {
      return AppScaffold(
        title: def.name,
        showBottomNavigation: false,
        body: const _MessageView(
          icon: LucideIcons.lock,
          title: 'Sem acesso a esta integração',
          body:
              'Solicite ao administrador a permissão de visualização desta '
              'integração para a sua conta.',
        ),
      );
    }

    return AppScaffold(
      title: def.name,
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 88),
                child: _loading
                    ? _buildSkeleton(context)
                    : _error != null
                        ? _buildError(context, _error!)
                        : _buildContent(context, def),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, IntegrationDef def) {
    final st = _status ??
        IntegrationStatusData(key: def.key, configured: false);
    final configured = st.configured;
    final infoRows = buildIntegrationInfoRows(def, st);
    // Toggle leve só quando já EXISTE config salva no backend (evita criar
    // configuração vazia pelo app); Autentique exige a API key já salva.
    final showToggle = def.supportsToggle &&
        _canManage &&
        st.raw.isNotEmpty &&
        (def.key != 'autentique' || asBool(st.raw['hasApiKey']));
    final showTest = def.supportsTest && _canManage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHero(context, def, st),
        const SizedBox(height: 18),
        _buildFeatureChips(context, def),
        if (def.steps.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionHeader(tone: def.accent, label: 'COMO FUNCIONA'),
          const SizedBox(height: 12),
          _buildSteps(context, def),
        ],
        const SizedBox(height: 22),
        _SectionHeader(
          tone: integrationStatusColor(context, configured),
          label: 'INFORMAÇÕES DE CONEXÃO',
        ),
        const SizedBox(height: 10),
        _buildInfoCard(context, def, st, infoRows),
        if (showToggle || showTest) ...[
          const SizedBox(height: 22),
          _SectionHeader(tone: def.accent, label: 'AÇÕES RÁPIDAS'),
          const SizedBox(height: 10),
          _buildActionsCard(context, def, st,
              showToggle: showToggle, showTest: showTest),
        ],
        const SizedBox(height: 22),
        _SectionHeader(
          tone: ThemeHelpers.textSecondaryColor(context),
          label: 'CONFIGURAÇÃO COMPLETA',
        ),
        const SizedBox(height: 10),
        _buildWebGuidanceCard(context, def),
      ],
    ).animate().fadeIn(duration: 240.ms);
  }

  // ─── Hero flush ───────────────────────────────────────────────────────────

  Widget _buildHero(
    BuildContext context,
    IntegrationDef def,
    IntegrationStatusData st,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final configured = st.configured;
    final tone = integrationStatusColor(context, configured);
    final category = def.category;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow: dot na cor da categoria + rótulo da categoria.
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: category.color,
                boxShadow: [
                  BoxShadow(
                    color: category.color.withValues(alpha: 0.45),
                    blurRadius: 7,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              category.label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: def.accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntegrationLogo(def: def, size: 56, radius: 16),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      height: 1.1,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    def.tagline,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Chips de status (pill + flag ativa quando o payload diferencia).
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Pill(
              label: configured ? 'Conectada' : 'Pendente',
              color: tone,
              icon: configured
                  ? LucideIcons.circleCheckBig
                  : LucideIcons.hourglass,
            ),
            if (st.active != null && st.active != configured)
              _Pill(
                label: st.active! ? 'Ativa' : 'Desativada',
                color: st.active! ? _emerald(context) : _amber(context),
                icon: st.active! ? LucideIcons.power : LucideIcons.powerOff,
              ),
          ],
        ),
        const SizedBox(height: 14),
        // Uma linha só de contexto — o passo a passo vive em "Como funciona".
        Text(
          st.statusLine ?? def.descriptionFor(configured),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureChips(BuildContext context, IntegrationDef def) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final f in def.features)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              border: Border.all(
                color: ThemeHelpers.borderLightColor(context),
              ),
            ),
            child: Text(
              f,
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
      ],
    );
  }

  // ─── "Como funciona" — passos curtos e específicos (flush, sem parágrafo) ─

  /// 3-4 passos de uma linha cada, com trilho conector na cor da marca —
  /// substitui o antigo texto longo padrão que o dono achou "extenso".
  Widget _buildSteps(BuildContext context, IntegrationDef def) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = def.accent;
    final steps = def.steps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Trilho: ícone do passo + conector vertical até o próximo.
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          color: accent
                              .withValues(alpha: isDark ? 0.18 : 0.10),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Icon(steps[i].icon, size: 14, color: accent),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin:
                                const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color:
                                  accent.withValues(alpha: isDark ? 0.28 : 0.18),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 5,
                      bottom: i < steps.length - 1 ? 14 : 0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            steps[i].text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Informações de conexão ───────────────────────────────────────────────

  Color _infoTone(BuildContext context, InfoTone tone) {
    switch (tone) {
      case InfoTone.good:
        return _emerald(context);
      case InfoTone.warn:
        return _amber(context);
      case InfoTone.bad:
        return _danger(context);
      case InfoTone.neutral:
        return ThemeHelpers.textColor(context);
    }
  }

  Widget _buildInfoCard(
    BuildContext context,
    IntegrationDef def,
    IntegrationStatusData st,
    List<IntegrationInfoRow> rows,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: ThemeHelpers.cardBackgroundColor(context),
          boxShadow: ThemeHelpers.cardShadow(context),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.info, size: 18, color: secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhum detalhe de conexão disponível para o seu perfil.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.6),
              ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    rows[i].icon ?? LucideIcons.dot,
                    size: 15,
                    color: rows[i].tone == InfoTone.neutral
                        ? secondary
                        : _infoTone(context, rows[i].tone),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rows[i].label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _infoTone(context, rows[i].tone),
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Ações rápidas ────────────────────────────────────────────────────────

  Widget _buildActionsCard(
    BuildContext context,
    IntegrationDef def,
    IntegrationStatusData st, {
    required bool showToggle,
    required bool showTest,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald = _emerald(context);
    final isActive = st.active ?? st.configured;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        children: [
          if (showToggle)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isActive ? LucideIcons.power : LucideIcons.powerOff,
                    size: 18,
                    color: isActive ? emerald : secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Integração ativa',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _toggling
                              ? 'Aplicando alteração…'
                              : isActive
                                  ? 'Desligue para pausar a sincronização.'
                                  : 'Ligue para retomar a sincronização.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _toggling
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      : Switch.adaptive(
                          value: isActive,
                          activeColor: emerald,
                          onChanged: _onToggle,
                        ),
                ],
              ),
            ),
          if (showToggle && showTest)
            Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.6),
            ),
          if (showTest) ...[
            Material(
              color: Colors.transparent,
              borderRadius: showToggle
                  ? const BorderRadius.vertical(bottom: Radius.circular(16))
                  : BorderRadius.circular(16),
              child: InkWell(
                borderRadius: showToggle
                    ? const BorderRadius.vertical(
                        bottom: Radius.circular(16))
                    : BorderRadius.circular(16),
                onTap: _testing ? null : _onTest,
                splashColor: def.accent.withValues(alpha: 0.1),
                highlightColor: def.accent.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(LucideIcons.activity,
                          size: 18, color: def.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Testar conexão',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: ThemeHelpers.textColor(context),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _testing
                                  ? 'Validando credenciais com o provedor…'
                                  : 'Valida as credenciais direto no provedor.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2),
                            )
                          : Icon(
                              LucideIcons.chevronRight,
                              size: 18,
                              color: secondary.withValues(alpha: 0.7),
                            ),
                    ],
                  ),
                ),
              ),
            ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _buildTestResultBanner(context, _testResult!),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestResultBanner(
    BuildContext context,
    IntegrationTestResult result,
  ) {
    final theme = Theme.of(context);
    final tone = result.ok ? _emerald(context) : _danger(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: tone.withValues(alpha: 0.1),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.ok ? LucideIcons.circleCheckBig : LucideIcons.circleAlert,
            size: 16,
            color: tone,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              result.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).moveY(begin: 4, end: 0);
  }

  // ─── Orientação: configuração completa no painel web ─────────────────────

  Widget _buildWebGuidanceCard(BuildContext context, IntegrationDef def) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = _accentColor(context);
    final path = _kWebConfigPath[def.key] ?? 'Integrações → ${def.name}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Icon(LucideIcons.monitor, color: accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configure pelo painel web',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Credenciais, tokens, webhooks e demais ajustes desta '
                      'integração são feitos no painel web do Intellisys.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              border: Border.all(
                color: ThemeHelpers.borderLightColor(context),
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.mousePointerClick,
                    size: 14, color: secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Estados ──────────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SkeletonText(width: 130, height: 11, borderRadius: 999),
        SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 56, height: 56, borderRadius: 16),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 190, height: 22),
                  SizedBox(height: 8),
                  SkeletonText(width: 140, height: 13),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            SkeletonBox(width: 96, height: 24, borderRadius: 999),
            SizedBox(width: 8),
            SkeletonBox(width: 76, height: 24, borderRadius: 999),
          ],
        ),
        SizedBox(height: 16),
        SkeletonText(width: double.infinity, height: 13),
        SizedBox(height: 7),
        SkeletonText(width: 230, height: 13),
        SizedBox(height: 26),
        SkeletonText(width: 130, height: 11, borderRadius: 999),
        SizedBox(height: 12),
        Row(
          children: [
            SkeletonBox(width: 28, height: 28, borderRadius: 9),
            SizedBox(width: 11),
            Expanded(child: SkeletonText(width: double.infinity, height: 12)),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            SkeletonBox(width: 28, height: 28, borderRadius: 9),
            SizedBox(width: 11),
            Expanded(child: SkeletonText(width: double.infinity, height: 12)),
          ],
        ),
        SizedBox(height: 26),
        SkeletonText(width: 170, height: 11, borderRadius: 999),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 168, borderRadius: 16),
        SizedBox(height: 26),
        SkeletonText(width: 120, height: 11, borderRadius: 999),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 118, borderRadius: 16),
      ],
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    final danger = _danger(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 4),
      child: Column(
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
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// ─── Cabeçalho flush de seção (dot + label + divisória) ──────────────────────

class _SectionHeader extends StatelessWidget {
  final Color tone;
  final String label;

  const _SectionHeader({required this.tone, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(2.5),
            boxShadow: [
              BoxShadow(color: tone.withValues(alpha: 0.35), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Pill genérica do hero ────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _Pill({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── View de mensagem (não encontrada / sem acesso) ──────────────────────────

class _MessageView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _MessageView({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
