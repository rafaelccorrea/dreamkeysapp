import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

/// Verde de confirmação da casa (aprovar/confirmar/enviar).
const Color kApprovalGreen = Color(0xFF059669);

/// Item do menu de "mais ações" (3 pontinhos) da fila de aprovação.
///
/// [tone] pinta o ícone/rótulo — use a cor com **significado**: verde para
/// confirmar, âmbar para pendência, vermelho **só** quando destrutivo
/// ([danger] `true`). Sem [tone] o item sai neutro.
class ApprovalMenuAction {
  final IconData icon;
  final String label;
  final String? hint;
  final Color? tone;
  final bool danger;
  final bool enabled;

  /// Executado depois do sheet fechar — evita empurrar rota/sheet durante o
  /// pop (a transição some quando isso acontece).
  final VoidCallback onTap;

  const ApprovalMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.tone,
    this.danger = false,
    this.enabled = true,
  });
}

/// Bottom sheet de **mais ações** de um item da fila (anatomia da casa:
/// grabber 42×4, ícone tonal + eyebrow + título + fechar, divisor em gradiente
/// e lista de ações separadas por hairline — sem card dentro de card).
Future<void> showApprovalActionsSheet({
  required BuildContext context,
  required String eyebrow,
  required String title,
  String? subtitle,
  required Color tone,
  required IconData icon,
  required List<ApprovalMenuAction> actions,
}) {
  final visible = actions.where((a) => a.enabled || a.hint != null).toList();
  if (visible.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _ApprovalActionsSheet(
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      tone: tone,
      icon: icon,
      actions: visible,
    ),
  );
}

class _ApprovalActionsSheet extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Color tone;
  final IconData icon;
  final List<ApprovalMenuAction> actions;

  const _ApprovalActionsSheet({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.icon,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ApprovalSheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
          child: ApprovalSheetHeader(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            tone: tone,
            icon: icon,
          ),
        ),
        const SizedBox(height: 14),
        ApprovalSheetDivider(tone: tone),
        Flexible(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++)
                  _ActionRow(
                    action: actions[i],
                    showDivider: i < actions.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final ApprovalMenuAction action;
  final bool showDivider;

  const _ActionRow({required this.action, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final base = action.danger
        ? danger
        : (action.tone ?? ThemeHelpers.textColor(context));
    final enabled = action.enabled;
    final fg = enabled ? base : base.withValues(alpha: 0.38);
    final labelColor = enabled
        ? (action.danger || action.tone != null
            ? base
            : ThemeHelpers.textColor(context))
        : ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () {
                Navigator.of(context).pop();
                // Roda no frame seguinte: abrir outro sheet/rota durante o pop
                // engole a transição.
                Future.microtask(action.onTap);
              }
            : null,
        splashColor: base.withValues(alpha: 0.10),
        highlightColor: base.withValues(alpha: 0.05),
        child: Container(
          decoration: showDivider
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ThemeHelpers.borderLightColor(context)
                          .withValues(alpha: 0.6),
                    ),
                  ),
                )
              : null,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: base.withValues(
                    alpha: enabled ? (isDark ? 0.18 : 0.10) : 0.06,
                  ),
                ),
                child: Icon(action.icon, size: 17, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: labelColor,
                        letterSpacing: -0.1,
                        height: 1.25,
                      ),
                    ),
                    if ((action.hint ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        action.hint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          height: 1.32,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: ThemeHelpers.textSecondaryColor(context)
                        .withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Peças reutilizáveis da anatomia de sheet ───────────────────────────

/// Grabber 42×4 no topo do sheet.
class ApprovalSheetGrabber extends StatelessWidget {
  const ApprovalSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Center(
        child: Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Cabeçalho do sheet: ícone tonal + eyebrow + título (+ subtítulo) + fechar.
class ApprovalSheetHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Color tone;
  final IconData icon;
  final bool canClose;

  const ApprovalSheetHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.tone,
    required this.icon,
    this.subtitle,
    this.canClose = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: tone.withValues(alpha: isDark ? 0.20 : 0.12),
          ),
          child: Icon(icon, color: tone, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.3,
                  height: 1.2,
                  fontSize: 15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if ((subtitle ?? '').isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.32,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (canClose) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            visualDensity: VisualDensity.compact,
            tooltip: 'Fechar',
            icon: Icon(
              LucideIcons.x,
              size: 18,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// Divisor em gradiente que fecha o cabeçalho do sheet.
class ApprovalSheetDivider extends StatelessWidget {
  final Color tone;

  const ApprovalSheetDivider({super.key, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tone.withValues(alpha: 0.30),
            ThemeHelpers.borderLightColor(context).withValues(alpha: 0.25),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

/// Resultado do sheet de confirmação: confirmado + motivo (quando pedido).
class ApprovalConfirmResult {
  final String reason;

  const ApprovalConfirmResult({this.reason = ''});
}

/// Sheet de **confirmação** de ação — usado por toda ação sensível
/// (dispensar assinatura, invalidar, recusar anexo…).
///
/// - [reasonRequired] trava o botão até haver texto (regra do backend).
/// - [danger] pinta o botão de confirmar em vermelho; caso contrário sai no
///   verde de confirmação da casa. "Cancelar" **nunca** é vermelho.
Future<ApprovalConfirmResult?> showApprovalConfirmSheet({
  required BuildContext context,
  required String eyebrow,
  required String title,
  String? subtitle,
  required String message,
  required IconData icon,
  required Color tone,
  String confirmLabel = 'Confirmar',
  IconData confirmIcon = LucideIcons.check,
  bool danger = false,
  bool withReason = false,
  bool reasonRequired = false,
  String reasonLabel = 'Motivo',
  String reasonHint = 'Escreva o motivo…',
}) {
  return showModalBottomSheet<ApprovalConfirmResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ApprovalConfirmSheet(
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      message: message,
      icon: icon,
      tone: tone,
      confirmLabel: confirmLabel,
      confirmIcon: confirmIcon,
      danger: danger,
      withReason: withReason,
      reasonRequired: reasonRequired,
      reasonLabel: reasonLabel,
      reasonHint: reasonHint,
    ),
  );
}

class _ApprovalConfirmSheet extends StatefulWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final String message;
  final IconData icon;
  final Color tone;
  final String confirmLabel;
  final IconData confirmIcon;
  final bool danger;
  final bool withReason;
  final bool reasonRequired;
  final String reasonLabel;
  final String reasonHint;

  const _ApprovalConfirmSheet({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.message,
    required this.icon,
    required this.tone,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.danger,
    required this.withReason,
    required this.reasonRequired,
    required this.reasonLabel,
    required this.reasonHint,
  });

  @override
  State<_ApprovalConfirmSheet> createState() => _ApprovalConfirmSheetState();
}

class _ApprovalConfirmSheetState extends State<_ApprovalConfirmSheet> {
  final TextEditingController _reason = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (widget.withReason && widget.reasonRequired) {
      return _reason.text.trim().isNotEmpty;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmColor = widget.danger ? danger : kApprovalGreen;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ApprovalSheetGrabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
            child: ApprovalSheetHeader(
              eyebrow: widget.eyebrow,
              title: widget.title,
              subtitle: widget.subtitle,
              tone: widget.tone,
              icon: widget.icon,
            ),
          ),
          const SizedBox(height: 14),
          ApprovalSheetDivider(tone: widget.tone),
          Flexible(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.42,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.withReason) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          widget.reasonLabel.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            fontSize: 10,
                          ),
                        ),
                        if (widget.reasonRequired) ...[
                          const SizedBox(width: 5),
                          Text(
                            '*',
                            style: TextStyle(
                              color: danger,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reason,
                      autofocus: widget.reasonRequired,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: widget.reasonHint,
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: ThemeHelpers.backgroundColor(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: widget.tone, width: 1.4),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          ApprovalSheetFooter(
            confirmLabel: widget.confirmLabel,
            confirmIcon: widget.confirmIcon,
            confirmColor: confirmColor,
            submitting: _submitting,
            onConfirm: _canSubmit
                ? () {
                    setState(() => _submitting = true);
                    Navigator.of(context).pop(
                      ApprovalConfirmResult(reason: _reason.text.trim()),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// Rodapé padrão dos sheets de ação: "Cancelar" neutro + confirmar sólido.
class ApprovalSheetFooter extends StatelessWidget {
  final String confirmLabel;
  final IconData confirmIcon;
  final Color confirmColor;
  final bool submitting;
  final VoidCallback? onConfirm;
  final String cancelLabel;

  const ApprovalSheetFooter({
    super.key,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.confirmColor,
    required this.submitting,
    required this.onConfirm,
    this.cancelLabel = 'Cancelar',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed:
                  submitting ? null : () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                // O tema global pinta TextButton de vermelho — forçamos o
                // cinza: "Cancelar" nunca é ação destrutiva.
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(cancelLabel),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: submitting ? null : onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    confirmColor.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(confirmIcon, size: 17),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(confirmLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
