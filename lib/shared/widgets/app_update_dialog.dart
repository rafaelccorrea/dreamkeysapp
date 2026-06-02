import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helpers.dart';
import '../services/app_update_service.dart';

/// Checa atualização e, se houver, mostra um aviso dispensável ("soft").
Future<void> maybePromptAppUpdate(
  BuildContext context, {
  bool force = false,
}) async {
  final info = await AppUpdateService.instance.checkForUpdate(force: force);
  if (info == null || !context.mounted) return;
  await showAppUpdateDialog(context, info);
}

/// Abre o link público do TestFlight (instala/atualiza o app beta).
Future<bool> openTestFlightUpdateUrl([String? url]) async {
  final uri = Uri.tryParse(
    (url != null && url.isNotEmpty)
        ? url
        : AppUpdateService.defaultTestFlightUrl,
  );
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdateInfo info,
) async {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final accent =
      isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      color: accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Atualização no TestFlight',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(ctx),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Há uma versão mais recente (${info.latestLabel}). '
                'Você está na ${info.currentLabel}. '
                'Toque em Atualizar para abrir o TestFlight e instalar o build novo.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(ctx),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Agora não',
                      style: TextStyle(
                        color: ThemeHelpers.textSecondaryColor(ctx),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await openTestFlightUpdateUrl(info.updateUrl);
                    },
                    icon: const Icon(Icons.flight_takeoff_rounded, size: 18),
                    label: const Text(
                      'Atualizar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
