import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../core/finance_access.dart';
import '../../core/finance_deep_link.dart';
import '../../core/finance_format.dart';
import '../../meu_financeiro/widgets/meu_financeiro_widgets.dart';
import '../finance_notifications_controller.dart';

/// Sino do Financeiro (barra das telas do módulo). Liga o controlador
/// (REST + socket) na primeira montagem.
class FinanceBellButton extends StatefulWidget {
  const FinanceBellButton({super.key});

  @override
  State<FinanceBellButton> createState() => _FinanceBellButtonState();
}

class _FinanceBellButtonState extends State<FinanceBellButton> {
  final FinanceNotificationsController _c =
      FinanceNotificationsController.instance;

  @override
  void initState() {
    super.initState();
    _c.start();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (!_c.visible) return const SizedBox.shrink();
        final n = _c.unread;
        return IconButton(
          tooltip: 'Avisos do Financeiro',
          onPressed: () => showFinanceNotificationsSheet(context),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            child: Icon(
              LucideIcons.bell,
              size: 20,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        );
      },
    );
  }
}

/// Lista de avisos do Financeiro com deep links.
Future<void> showFinanceNotificationsSheet(BuildContext context) {
  final c = FinanceNotificationsController.instance;
  c.refresh();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scroll) => ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final items = c.items;
          final secondary = ThemeHelpers.textSecondaryColor(ctx);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Avisos do Financeiro',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (c.unread > 0)
                      TextButton(
                        onPressed: c.markAllRead,
                        child: const Text('Marcar todas como lidas'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? ListView(
                        controller: scroll,
                        children: [
                          FinanceEmpty(
                            icon: LucideIcons.bellOff,
                            text: c.loading
                                ? 'Carregando…'
                                : 'Nenhum aviso do Financeiro.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (ctx, i) {
                          final n = items[i];
                          final rota = _rotaDe(n);
                          return Material(
                            color: n.read
                                ? Colors.transparent
                                : financeAccent(ctx).withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _abrir(context, ctx, n, rota),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 5),
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: n.read
                                              ? Colors.transparent
                                              : financeAccent(ctx),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n.title,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: n.read
                                                  ? FontWeight.w600
                                                  : FontWeight.w800,
                                              color: ThemeHelpers.textColor(ctx),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            n.message,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              height: 1.35,
                                              color: secondary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatFinanceDateTime(
                                              n.createdAt,
                                              pattern: 'dd/MM HH:mm',
                                            ),
                                            style: TextStyle(fontSize: 11, color: secondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (rota != null)
                                      Icon(
                                        LucideIcons.chevronRight,
                                        size: 16,
                                        color: secondary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

String? _rotaDe(FinanceNotification n) {
  final mas = ModuleAccessService.instance;
  final podeAprovar = canSeeParaAprovar(
    crmRole: mas.userRole,
    hasFinancialAccess: mas.hasPermission('financial:access'),
    me: FinanceNotificationsController.instance.me,
  );
  return financeNotificationRoute(n, podeAprovar: podeAprovar);
}

Future<void> _abrir(
  BuildContext pageContext,
  BuildContext sheetContext,
  FinanceNotification n,
  String? rota,
) async {
  FinanceNotificationsController.instance.markRead(n.id);
  if (rota == null) return;
  final match = matchFinanceRoute(rota);
  if (match.kind == FinanceRouteKind.webOnly) {
    await showFinanceWebOnlyDialog(sheetContext, match.webLabel);
    return;
  }
  Navigator.of(sheetContext).pop();
  if (pageContext.mounted) Navigator.of(pageContext).pushNamed(rota);
}

/// Aviso claro para o que só existe no web.
Future<void> showFinanceWebOnlyDialog(BuildContext context, String? label) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(LucideIcons.monitor),
      title: const Text('Disponível só no computador'),
      content: Text(
        '${label ?? 'Esta tela do Financeiro'} ainda não existe no app. Abra o '
        'Financeiro pelo navegador (intellisysbr.com) para ver e resolver '
        'este aviso.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );
}
