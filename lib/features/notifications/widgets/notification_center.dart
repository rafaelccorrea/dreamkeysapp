import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../controllers/notification_controller.dart';
import 'notification_list.dart';

/// Botão sino com badge + abertura do **modal bottom sheet** premium de
/// notificações.
///
/// **Mudança de design** (em relação à versão anterior baseada em overlay
/// ancorado):
/// - Antes: dropdown de 360×480 ancorado no botão, com gradients, glows,
///   ShaderMask, textura de pontos, 3 sombras coloridas competindo entre
///   si. Ficava "sujo" visualmente e travava em telas pequenas.
/// - Agora: `showModalBottomSheet` clean — drag handle, header editorial,
///   ação primária "Marcar todas" como botão sólido, lista ocupando o
///   resto. Padrão moderno mobile (Apple/iOS, Linear, Notion).
///
/// O badge no botão (contador vermelho) e o ícone do sino com glow quando
/// há não lidas continuam — é o que o usuário vê no AppBar e precisa
/// chamar atenção.
class NotificationCenter extends StatefulWidget {
  final bool embedded;

  /// Tamanho reduzido para a cápsula do toolbar minimalista.
  final bool compactToolbar;

  const NotificationCenter({
    super.key,
    this.embedded = false,
    this.compactToolbar = false,
  });

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  Future<void> _openSheet() async {
    final controller =
        Provider.of<NotificationController>(context, listen: false);

    // Força um refresh ao abrir — garante que o usuário veja o estado
    // mais recente do servidor (e qualquer marcação remota feita por
    // outro device aparece corretamente).
    // ignore: unawaited_futures
    controller.loadNotifications(reset: true);
    // ignore: unawaited_futures
    controller.refreshUnreadCount();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (_) => const _NotificationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<NotificationController>(
      builder: (context, controller, child) {
        final unreadCount = controller.unreadCount;
        final hasUnread = unreadCount > 0;
        final compact = widget.compactToolbar;
        final dim = compact ? 40.0 : 46.0;
        final iconSize = compact ? 20.0 : 22.0;
        const accentRed = Color(0xFFEF4444);

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Tooltip(
              message: 'Notificações',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: dim,
                    height: dim,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        width: 1.5,
                        color: hasUnread
                            ? accentRed.withValues(alpha: 0.5)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : AppColors.border.border),
                      ),
                      boxShadow: [
                        if (hasUnread)
                          BoxShadow(
                            color: accentRed.withValues(alpha: 0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        else
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.2 : 0.04,
                            ),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                      ],
                    ),
                    child: Icon(
                      hasUnread
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_outlined,
                      size: iconSize,
                      color: hasUnread
                          ? accentRed
                          : ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? AppColors.background.backgroundDarkMode
                          : theme.scaffoldBackgroundColor,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentRed.withValues(alpha: 0.45),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Sheet propriamente dito.
///
/// Estrutura:
/// 1. Drag handle no topo (toque + arrasto para fechar)
/// 2. Header editorial: eyebrow `INBOX`, título "Notificações", linha
///    contextual (X não lidas / Tudo em dia)
/// 3. Botão "Marcar todas" só aparece quando há não lidas
/// 4. Botão fechar circular discreto à direita
/// 5. Lista preenche o resto, scrollável
///
/// Altura inicial: 70% da tela. Pode ser arrastado pra subir até 92%
/// (`DraggableScrollableSheet`-like comportamento via `initialChildSize`).
class _NotificationSheet extends StatelessWidget {
  const _NotificationSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = ThemeHelpers.cardBackgroundColor(context);
    final viewportHeight = MediaQuery.sizeOf(context).height;

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 24,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Container(
          constraints: BoxConstraints(maxHeight: viewportHeight * 0.92),
          decoration: BoxDecoration(
            color: cardBg,
            border: Border(
              top: BorderSide(
                color: ThemeHelpers.borderLightColor(context),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderLightColor(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),

                // Header
                const _SheetHeader(),

                // Divisor sutil
                Container(
                  height: 1,
                  margin: const EdgeInsets.only(top: 4, bottom: 0),
                  color: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: isDark ? 0.4 : 0.6),
                ),

                // Lista
                const Expanded(
                  child: NotificationList(embedded: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Consumer<NotificationController>(
      builder: (context, controller, _) {
        final unread = controller.unreadCount;
        final contextLine = unread > 0
            ? '$unread ${unread == 1 ? 'não lida' : 'não lidas'}'
            : 'Tudo em dia';

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'INBOX',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Notificações',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ThemeHelpers.textColor(context),
                            height: 1.05,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            // Bolinha contextual: vermelha pulsante quando
                            // tem não-lidas, verde fixa quando "tudo em dia".
                            _ContextDot(
                              color: unread > 0
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF22C55E),
                              pulse: unread > 0,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                contextLine,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(
                                      context),
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Botão fechar circular discreto
                  _CloseChip(),
                ],
              ),

              // Botão "Marcar todas" — full width, só quando há não-lidas
              if (unread > 0) ...[
                const SizedBox(height: 14),
                _MarkAllAction(
                  onPressed: () async {
                    await controller.markAllAsRead();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ContextDot extends StatefulWidget {
  const _ContextDot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<_ContextDot> createState() => _ContextDotState();
}

class _ContextDotState extends State<_ContextDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.5),
            blurRadius: 6,
          ),
        ],
      ),
    );
    if (!widget.pulse) return dot;
    return ScaleTransition(scale: _scale, child: dot);
  }
}

class _CloseChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            border: Border.all(
              color: ThemeHelpers.borderLightColor(context),
            ),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ),
    );
  }
}

class _MarkAllAction extends StatelessWidget {
  const _MarkAllAction({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.18 : 0.10),
                accent.withValues(alpha: isDark ? 0.08 : 0.04),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.4 : 0.28),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.done_all_rounded, size: 18, color: accent),
              const SizedBox(width: 10),
              Text(
                'Marcar todas como lidas',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
