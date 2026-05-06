import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

/// Resultado do bottom sheet de aprovação de publicação no site (com toggle
/// opcional de marca d'água nas imagens, conforme `applyWatermarkToImages`
/// das settings da empresa).
class ApprovePublicationResult {
  final bool applyWatermark;

  const ApprovePublicationResult({required this.applyWatermark});
}

/// Bottom sheet para coletar o **motivo da recusa** (disponibilidade ou
/// publicação). O backend exige `reason` não vazio — o botão de confirmar
/// só habilita quando há texto.
Future<String?> showRejectReasonSheet({
  required BuildContext context,
  required String title,
  String? propertySubtitle,
  String confirmLabel = 'Recusar',
  String hint = 'Explique para o responsável o que precisa ser ajustado.',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return _RejectReasonSheet(
        title: title,
        propertySubtitle: propertySubtitle,
        confirmLabel: confirmLabel,
        hint: hint,
      );
    },
  );
}

class _RejectReasonSheet extends StatefulWidget {
  final String title;
  final String? propertySubtitle;
  final String confirmLabel;
  final String hint;

  const _RejectReasonSheet({
    required this.title,
    required this.propertySubtitle,
    required this.confirmLabel,
    required this.hint,
  });

  @override
  State<_RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<_RejectReasonSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;

  bool get _canSubmit => _controller.text.trim().isNotEmpty && !_submitting;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(LucideIcons.alertTriangle,
                      color: danger, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      if (widget.propertySubtitle != null &&
                          widget.propertySubtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            widget.propertySubtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: 500,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Motivo da recusa…',
                filled: true,
                fillColor: ThemeHelpers.backgroundColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: ThemeHelpers.borderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: ThemeHelpers.borderColor(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: danger, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  onPressed: _canSubmit
                      ? () {
                          setState(() => _submitting = true);
                          Navigator.of(context).pop(_controller.text.trim());
                        }
                      : null,
                  icon: const Icon(LucideIcons.xCircle, size: 18),
                  label: Text(widget.confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet para confirmar a aprovação da **publicação no site** com
/// opção de aplicar marca d'água nas imagens. Só faz sentido abrir quando
/// `applyWatermarkToImages` está ligado nas settings da empresa.
Future<ApprovePublicationResult?> showApprovePublicationSheet({
  required BuildContext context,
  required String propertyTitle,
  required bool watermarkConfigured,
}) {
  return showModalBottomSheet<ApprovePublicationResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return _ApprovePublicationSheet(
        propertyTitle: propertyTitle,
        watermarkConfigured: watermarkConfigured,
      );
    },
  );
}

class _ApprovePublicationSheet extends StatefulWidget {
  final String propertyTitle;
  final bool watermarkConfigured;

  const _ApprovePublicationSheet({
    required this.propertyTitle,
    required this.watermarkConfigured,
  });

  @override
  State<_ApprovePublicationSheet> createState() =>
      _ApprovePublicationSheetState();
}

class _ApprovePublicationSheetState extends State<_ApprovePublicationSheet> {
  late bool _applyWatermark = widget.watermarkConfigured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ok = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ok.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.checkCircle2, color: ok, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aprovar publicação no site',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        widget.propertyTitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.watermarkConfigured)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ok.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ok.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aplicar marca d\'água nas imagens',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'A logomarca da empresa será inserida nas fotos antes de irem para o site.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _applyWatermark,
                    activeThumbColor: ok,
                    onChanged: (v) => setState(() => _applyWatermark = v),
                  ),
                ],
              ),
            )
          else
            Text(
              'Confirmar publicação deste imóvel no site público da empresa?',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ok,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                ),
                onPressed: () => Navigator.of(context).pop(
                  ApprovePublicationResult(applyWatermark: _applyWatermark),
                ),
                icon: const Icon(LucideIcons.checkCircle2, size: 18),
                label: const Text('Aprovar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
