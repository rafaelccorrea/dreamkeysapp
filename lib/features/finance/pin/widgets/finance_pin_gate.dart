import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/subscription_access_gate.dart';
import '../../core/finance_pin_store.dart';
import '../../core/finance_visibility.dart';
import '../services/finance_pin_service.dart';
import 'finance_pin_view.dart';

/// Portão de toda tela `/financeiro/*` (paridade com `FinancePinGate.tsx`).
///
/// 1. Módulo `financial_management` na empresa (sem bypass de papel).
/// 2. PIN: na ENTRADA, só o PIN (a tela embaixo chamaria a API ao montar);
///    DEPOIS do primeiro desbloqueio, quando vence, volta do segundo plano ou
///    o back responde 428, o PIN aparece POR CIMA da tela, sem desmontá-la —
///    formulário e rolagem preservados.
/// 3. Toque/rolagem com token de mais de 10 min renova o token.
class FinancePinGate extends StatefulWidget {
  final Widget child;

  const FinancePinGate({super.key, required this.child});

  @override
  State<FinancePinGate> createState() => _FinancePinGateState();
}

class _FinancePinGateState extends State<FinancePinGate> {
  final FinancePinStore _store = FinancePinStore.instance;
  bool _moduleChecked = false;
  bool _childMounted = false;

  @override
  void initState() {
    super.initState();
    FinancePinService.instance.attach();
    unawaited(_checkModule());
  }

  Future<void> _checkModule() async {
    await _store.ensureLoaded();
    final mas = ModuleAccessService.instance;
    // Login bloqueado (plano só Financeiro) não roda a inicialização de
    // permissões — garante a empresa aqui.
    if (mas.selectedCompany == null) {
      try {
        await mas.initialize();
      } catch (_) {}
    }
    if (mounted) setState(() => _moduleChecked = true);
  }

  void _exit() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushNamedAndRemoveUntil(AppRoutes.home, (r) => false);
    }
  }

  bool get _canExit {
    if (Navigator.of(context).canPop()) return true;
    // Plano só Financeiro: não há "fora" para onde voltar.
    return SubscriptionAccessGate.instance.decision !=
        AccessGateDecision.financeOnly;
  }

  @override
  Widget build(BuildContext context) {
    if (!_moduleChecked) return const _GateLoading();
    final hasModule = companyHasFinanceModule(
      ModuleAccessService.instance.selectedCompany?.availableModules,
    );
    if (hasModule == false) {
      return _NoFinanceModule(onExit: _canExit ? _exit : null);
    }

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final unlocked = _store.isUnlocked;
        if (unlocked) _childMounted = true;
        final pin = FinancePinView(
          key: const ValueKey('finance-pin'),
          onExit: _canExit ? _exit : null,
        );
        if (!_childMounted) {
          // Entrada: só o PIN, a tela ainda não montou.
          return Scaffold(body: pin);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            // A tela fica montada (estado preservado) e para de animar
            // enquanto trancada.
            TickerMode(
              enabled: unlocked,
              child: ExcludeSemantics(
                excluding: !unlocked,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => unawaited(_store.touch()),
                  onPointerSignal: (_) => unawaited(_store.touch()),
                  child: widget.child,
                ),
              ),
            ),
            if (!unlocked) Positioned.fill(child: Scaffold(body: pin)),
          ],
        );
      },
    );
  }
}

class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: DecoratedBox(
        decoration: ThemeHelpers.shellBackgroundDecoration(context),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: isDark
                ? AppColors.primary.primaryDarkMode
                : AppColors.primary.primary,
          ),
        ),
      ),
    );
  }
}

/// Empresa sem o módulo Financeiro — aviso claro, nunca "sem permissão".
class _NoFinanceModule extends StatelessWidget {
  final VoidCallback? onExit;

  const _NoFinanceModule({this.onExit});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    return Scaffold(
      body: DecoratedBox(
        decoration: ThemeHelpers.shellBackgroundDecoration(context),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(LucideIcons.landmark, color: accent, size: 32),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Esta empresa não tem o Financeiro',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'O módulo Financeiro não está habilitado no plano da '
                    'empresa selecionada. Troque de empresa no seu perfil ou '
                    'fale com o suporte para habilitar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  if (onExit != null) ...[
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: onExit,
                      style: FilledButton.styleFrom(backgroundColor: accent),
                      child: const Text('Voltar'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
