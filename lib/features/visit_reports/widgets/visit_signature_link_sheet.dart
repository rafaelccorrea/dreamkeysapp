import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/visit_report_model.dart';
import '../services/visit_report_service.dart';

/// Monta a mensagem enviada ao cliente com o link público de assinatura.
String visitShareMessage(VisitReport report, String url) {
  final name = report.clientLabel;
  return 'Olá, $name! Segue o link para você conferir os imóveis visitados e '
      'assinar o relatório de visita: $url';
}

/// Abre o WhatsApp (wa.me) com a mensagem do link de assinatura. Se o
/// telefone do cliente estiver disponível, direciona a conversa; senão abre
/// o compositor para escolher o contato.
Future<bool> shareVisitLinkOnWhatsApp(
  VisitReport report,
  String url,
) async {
  final message = Uri.encodeComponent(visitShareMessage(report, url));

  String? phoneDigits;
  final contact =
      await VisitReportService.instance.getClientContact(report.clientId);
  final rawPhone = contact?.phone ?? '';
  if (rawPhone.isNotEmpty) {
    var digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10 && !digits.startsWith('55')) {
      digits = '55$digits';
    }
    if (digits.length >= 12) phoneDigits = digits;
  }

  final uri = Uri.parse(
    phoneDigits != null
        ? 'https://wa.me/$phoneDigits?text=$message'
        : 'https://wa.me/?text=$message',
  );
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Bottom-sheet do link de assinatura — mostra o link gerado com ações de
/// enviar pelo WhatsApp e copiar (paridade com o `LinkModal` do web).
class VisitSignatureLinkSheet extends StatelessWidget {
  final VisitReport report;
  final VisitSignatureLink link;

  const VisitSignatureLinkSheet({
    super.key,
    required this.report,
    required this.link,
  });

  static Future<void> show(
    BuildContext context, {
    required VisitReport report,
    required VisitSignatureLink link,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => VisitSignatureLinkSheet(report: report, link: link),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: blue.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: secondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: blue.withValues(alpha: isDark ? 0.18 : 0.1),
                      border: Border.all(color: blue.withValues(alpha: 0.3)),
                    ),
                    child: Icon(LucideIcons.link, color: blue, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Link de assinatura',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          link.expiresAt != null
                              ? 'Válido até ${DateFormat('dd/MM/yyyy', 'pt_BR').format(link.expiresAt!.toLocal())}'
                              : 'Envie ao cliente para confirmar e assinar.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.045)
                      : Colors.black.withValues(alpha: 0.03),
                  border: Border.all(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
                child: Text(
                  link.url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok =
                            await shareVisitLinkOnWhatsApp(report, link.url);
                        if (!ok) {
                          messenger.showSnackBar(
                            const SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content:
                                  Text('Não foi possível abrir o WhatsApp.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(LucideIcons.messageCircle, size: 17),
                      label: const Text(
                        'WhatsApp',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                            ClipboardData(text: link.url));
                        messenger.showSnackBar(
                          const SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text('Link copiado!'),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.copy, size: 16),
                      label: const Text(
                        'Copiar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        side: BorderSide(color: blue.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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
    );
  }
}
