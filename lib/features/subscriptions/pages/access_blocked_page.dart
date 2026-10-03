import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/subscription_access_gate.dart';
import '../../../shared/services/subscription_service.dart';

/// Tela de acesso bloqueado — três casos, decididos pelo
/// [SubscriptionAccessGate] (NEW-01 e NEW-02 da paridade de 03/10/2026):
///
/// - **Assinatura necessária** (titular): paridade com o
///   `SubscriptionRequiredModal` do web. Mantém o acesso mínimo para ver os
///   planos, a assinatura, abrir chamado e editar o perfil; o pagamento em si
///   acontece no painel web.
/// - **Sistema indisponível** (colaborador): paridade com
///   `/system-unavailable` — só o titular resolve.
/// - **Plano sem CRM** (sem CRM e sem Financeiro): o back recusa as rotas de
///   CRM. Com o Financeiro (plano "só Financeiro"), o app abre direto no Meu
///   Financeiro (`AccessGateDecision.financeOnly`) e esta tela só aparece se
///   alguém navegar até ela.
class AccessBlockedPage extends StatefulWidget {
  final AccessGateDecision decision;

  const AccessBlockedPage({super.key, required this.decision});

  @override
  State<AccessBlockedPage> createState() => _AccessBlockedPageState();
}

class _AccessBlockedPageState extends State<AccessBlockedPage> {
  static const String _webPanelBase = 'https://intellisysbr.com/sistema';

  bool _checking = false;
  bool _leaving = false;

  SubscriptionAccessInfo? get _info => SubscriptionAccessGate.instance.info;

  @override
  void initState() {
    super.initState();
    // Num login bloqueado o fluxo para antes da inicialização de permissões,
    // e as telas de assinatura checam o papel (admin/master) por aqui.
    if (ModuleAccessService.instance.userRole == null) {
      ModuleAccessService.instance.initialize();
    }
  }

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    SubscriptionService.instance.clearCache();
    final decision = await SubscriptionAccessGate.instance.evaluate();
    if (!mounted) return;
    setState(() => _checking = false);
    final target = SubscriptionAccessGate.routeFor(decision) ?? AppRoutes.home;
    if (decision == widget.decision) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O acesso continua bloqueado.')),
      );
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
  }

  Future<void> _logout() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await AuthService.instance.logout();
    } catch (_) {
      // O logout limpa a sessão local mesmo se a API falhar.
    }
    SubscriptionAccessGate.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.login,
      (route) => false,
    );
  }

  Future<void> _openWeb(String path) async {
    final ok = await launchUrl(
      Uri.parse('$_webPanelBase$path'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o painel web.')),
      );
    }
  }

  void _go(String route) => Navigator.of(context).pushNamed(route);

  // ─── Conteúdo por caso ──────────────────────────────────────────────────

  IconData get _icon {
    switch (widget.decision) {
      case AccessGateDecision.subscriptionRequired:
        return LucideIcons.creditCard;
      case AccessGateDecision.systemUnavailable:
        return LucideIcons.cloudOff;
      case AccessGateDecision.crmNotIncluded:
        return LucideIcons.layers;
      case AccessGateDecision.financeOnly:
        return LucideIcons.wallet;
      case AccessGateDecision.allow:
        return LucideIcons.circleCheck;
    }
  }

  String get _title {
    switch (widget.decision) {
      case AccessGateDecision.subscriptionRequired:
        return (_info?.status ?? 'none') == 'none'
            ? 'Escolha um plano para continuar'
            : 'Sua assinatura precisa de atenção';
      case AccessGateDecision.systemUnavailable:
        return 'Sistema indisponível';
      case AccessGateDecision.crmNotIncluded:
        return 'O plano da empresa não inclui o CRM';
      case AccessGateDecision.financeOnly:
        return 'Sua empresa usa o Financeiro';
      case AccessGateDecision.allow:
        return 'Acesso liberado';
    }
  }

  String get _message {
    switch (widget.decision) {
      case AccessGateDecision.subscriptionRequired:
        final reason = _info?.reason?.trim();
        final status = (_info?.status ?? 'none').toLowerCase();
        final base = (reason != null && reason.isNotEmpty)
            ? reason
            : status == 'none'
            ? 'O período de avaliação terminou e a conta ainda não tem uma assinatura ativa.'
            : 'A assinatura está suspensa, expirada ou inativa.';
        return '$base\n\nVocê ainda pode ver os planos e a sua assinatura, '
            'abrir um chamado (por exemplo, para pedir um backup) e editar o '
            'seu perfil. A contratação e o pagamento são feitos no painel web.';
      case AccessGateDecision.systemUnavailable:
        return 'O acesso da sua empresa está temporariamente suspenso por '
            'causa da assinatura. Fale com o administrador da conta para '
            'regularizar — assim que ele resolver, toque em "Verificar de novo".';
      case AccessGateDecision.crmNotIncluded:
        return 'O plano da sua empresa não inclui o CRM nem o Financeiro. '
            'Use o painel web para o que estiver contratado. Para usar o CRM '
            '(funil, imóveis, clientes, agenda, WhatsApp), fale com o seu '
            'gestor ou com o suporte.';
      case AccessGateDecision.financeOnly:
        return 'O plano da empresa inclui só o Financeiro. Para usar o CRM '
            '(funil, imóveis, clientes, agenda, WhatsApp), fale com o seu '
            'gestor ou com o suporte.';
      case AccessGateDecision.allow:
        return '';
    }
  }

  List<_BlockedAction> get _actions {
    switch (widget.decision) {
      case AccessGateDecision.subscriptionRequired:
        return [
          _BlockedAction(
            icon: LucideIcons.sparkles,
            label: 'Ver planos',
            hint: 'Compare e escolha o plano',
            onTap: () => _go(AppRoutes.subscriptionPlans),
            primary: true,
          ),
          _BlockedAction(
            icon: LucideIcons.receiptText,
            label: 'Minha assinatura',
            hint: 'Status, cobrança e uso',
            onTap: () => _go(AppRoutes.mySubscription),
          ),
          _BlockedAction(
            icon: LucideIcons.externalLink,
            label: 'Assinar pelo painel web',
            hint: 'Pagamento e cartão',
            onTap: () => _openWeb('/subscription-plans'),
          ),
          _BlockedAction(
            icon: LucideIcons.lifeBuoy,
            label: 'Abrir chamado',
            hint: 'Suporte, backup dos dados',
            onTap: () => _go(AppRoutes.tickets),
          ),
          _BlockedAction(
            icon: LucideIcons.user,
            label: 'Meu perfil',
            hint: 'Dados pessoais',
            onTap: () => _go(AppRoutes.profile),
          ),
        ];
      case AccessGateDecision.systemUnavailable:
        return [
          _BlockedAction(
            icon: LucideIcons.user,
            label: 'Meu perfil',
            hint: 'Dados pessoais',
            onTap: () => _go(AppRoutes.profile),
          ),
        ];
      case AccessGateDecision.crmNotIncluded:
        return [
          _BlockedAction(
            icon: LucideIcons.externalLink,
            label: 'Abrir o painel web',
            hint: 'Financeiro e configurações',
            onTap: () => _openWeb(''),
            primary: true,
          ),
          _BlockedAction(
            icon: LucideIcons.lifeBuoy,
            label: 'Abrir chamado',
            hint: 'Falar com o suporte',
            onTap: () => _go(AppRoutes.tickets),
          ),
          _BlockedAction(
            icon: LucideIcons.user,
            label: 'Meu perfil',
            hint: 'Dados pessoais',
            onTap: () => _go(AppRoutes.profile),
          ),
        ];
      case AccessGateDecision.financeOnly:
        return [
          _BlockedAction(
            icon: LucideIcons.wallet,
            label: 'Abrir o Meu Financeiro',
            hint: 'Comissões, repasses e adiantamentos',
            onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
              SubscriptionAccessGate.financeHomeRoute,
              (route) => false,
            ),
            primary: true,
          ),
          _BlockedAction(
            icon: LucideIcons.user,
            label: 'Meu perfil',
            hint: 'Dados pessoais',
            onTap: () => _go(AppRoutes.profile),
          ),
        ];
      case AccessGateDecision.allow:
        return const [];
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: Stack(
          children: [
            Positioned(
              top: -120,
              right: -80,
              child: _Glow(color: accent.withValues(alpha: 0.18), size: 320),
            ),
            Positioned(
              bottom: -140,
              left: -100,
              child: _Glow(color: accent.withValues(alpha: 0.10), size: 300),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [accent, accent.withValues(alpha: 0.65)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(_icon, color: Colors.white, size: 38),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: isDark ? 0.35 : 0.6,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final action in _actions) ...[
                        _ActionTile(action: action, accent: accent),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _checking ? null : _retry,
                              icon: _checking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(LucideIcons.refreshCw, size: 18),
                              label: const Text('Verificar de novo'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _leaving ? null : _logout,
                              icon: const Icon(LucideIcons.logOut, size: 18),
                              label: const Text('Sair'),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.error,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedAction {
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  final bool primary;

  const _BlockedAction({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.primary = false,
  });
}

class _ActionTile extends StatelessWidget {
  final _BlockedAction action;
  final Color accent;

  const _ActionTile({required this.action, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primary = action.primary;
    final fg = primary ? Colors.white : scheme.onSurface;

    return Material(
      color: primary ? accent : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary
                      ? Colors.white.withValues(alpha: 0.18)
                      : accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  action.icon,
                  size: 20,
                  color: primary ? Colors.white : accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: primary
                            ? Colors.white.withValues(alpha: 0.85)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: primary
                    ? Colors.white.withValues(alpha: 0.9)
                    : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
