import 'package:flutter/material.dart';

/// Rota nomeada que dispara um FLUXO em vez de uma tela (03/10/2026).
///
/// Deep link, push e notificação navegam só por `pushNamed(rota)`. Alguns
/// destinos do web são fluxos com passos antes da tela — "Nova ficha a partir
/// da proposta" (carrega a proposta e abre o formulário preenchido) e "Nova
/// proposta" (escolha do tipo). Esta rota-ponte se retira da pilha no
/// primeiro quadro e chama [action] com o contexto do `Navigator`, que
/// continua montado depois do `pop`.
///
/// Sem rota abaixo (app aberto a frio direto no link), troca a ponte por
/// [fallbackRoute] antes de rodar a ação — a pilha nunca fica vazia.
class RouteActionLauncher extends StatefulWidget {
  const RouteActionLauncher({
    super.key,
    required this.action,
    required this.fallbackRoute,
  });

  final Future<void> Function(BuildContext navigatorContext) action;
  final String fallbackRoute;

  @override
  State<RouteActionLauncher> createState() => _RouteActionLauncherState();
}

class _RouteActionLauncherState extends State<RouteActionLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      } else {
        nav.pushReplacementNamed(widget.fallbackRoute);
      }
      widget.action(nav.context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
