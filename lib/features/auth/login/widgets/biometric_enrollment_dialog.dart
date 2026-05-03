import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/secure_storage_service.dart';

/// Convite pós-login para gravar credenciais e usar biometria nos próximos acessos.
///
/// Retorna `true` se o utilizador aceitou e as credenciais foram guardadas.
Future<bool> showBiometricEnrollmentOffer(
  BuildContext context, {
  required String email,
  required String password,
  required bool biometricHardwareAvailable,
  required String biometricTypeLabel,
}) async {
  if (!biometricHardwareAvailable) return false;
  final storage = SecureStorageService.instance;
  if (await storage.hasSavedCredentials()) return false;
  if (await storage.isBiometricEnrollmentDeclined()) return false;

  if (!context.mounted) return false;

  final accept = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => _BiometricEnrollmentDialog(
          biometricTypeLabel: biometricTypeLabel,
          onActivate: () => Navigator.of(dialogContext).pop(true),
          onNotNow: () => Navigator.of(dialogContext).pop(false),
        ),
      ) ??
      false;

  if (!context.mounted) return false;

  if (accept) {
    await storage.saveCredentials(email: email, password: password);
    return true;
  }
  await storage.setBiometricEnrollmentDeclined(true);
  return false;
}

class _BiometricEnrollmentDialog extends StatelessWidget {
  const _BiometricEnrollmentDialog({
    required this.biometricTypeLabel,
    required this.onActivate,
    required this.onNotNow,
  });

  final String biometricTypeLabel;
  final VoidCallback onActivate;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final fg = isDark ? AppColors.text.textDarkMode : AppColors.text.text;
    final muted = isDark
        ? AppColors.text.textSecondaryDarkMode
        : AppColors.text.textSecondary;
    final cardBg = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : Colors.white;
    final border = isDark
        ? AppColors.border.borderDarkMode.withValues(alpha: 0.55)
        : AppColors.border.border.withValues(alpha: 0.45);

    final isFace = biometricTypeLabel.toLowerCase().contains('face');

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 22),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 32,
                offset: const Offset(0, 18),
                spreadRadius: -8,
              ),
              BoxShadow(
                color: primary.withValues(alpha: isDark ? 0.22 : 0.14),
                blurRadius: 40,
                offset: const Offset(0, 12),
                spreadRadius: -18,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            primary,
                            Color.lerp(primary, const Color(0xFF7C3AED), 0.35)!,
                            const Color(0xFF4F46E5),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: -30,
                      top: -24,
                      child: IgnorePointer(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -40,
                      bottom: -35,
                      child: IgnorePointer(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.18),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Image.asset(
                                      isDark ? AppAssets.logoDark : AppAssets.logoLight,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.lock_rounded,
                                        size: 14,
                                        color: Colors.white.withValues(alpha: 0.92),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Seguro',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white.withValues(alpha: 0.95),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              'Acesso instantâneo',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                                height: 1.25,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              biometricTypeLabel,
                              style: GoogleFonts.poppins(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quer usar $biometricTypeLabel neste aparelho?',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: fg,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Na próxima vez podes entrar sem digitar e-mail e senha — só confirmas com ${isFace ? 'o teu rosto' : 'a tua impressão digital'}.',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w400,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _bullet(
                        Icons.shield_rounded,
                        primary,
                        'Credenciais encriptadas no armazenamento seguro do dispositivo.',
                        fg,
                        muted,
                      ),
                      const SizedBox(height: 10),
                      _bullet(
                        Icons.phonelink_lock_rounded,
                        primary,
                        'Podes remover isto quando fizeres sessão iniciada neste equipamento.',
                        fg,
                        muted,
                      ),
                      const SizedBox(height: 10),
                      _bullet(
                        Icons.fingerprint_rounded,
                        primary,
                        'Opcional — continua sempre a poder usar e-mail e palavra-passe.',
                        fg,
                        muted,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: onActivate,
                          style: FilledButton.styleFrom(
                            elevation: 0,
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isFace ? Icons.face_rounded : Icons.fingerprint_rounded,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              const Text('Sim, ativar'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: onNotNow,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: fg,
                            side: BorderSide(color: border, width: 1.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('Agora não'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _bullet(
    IconData icon,
    Color accent,
    String text,
    Color fg,
    Color muted,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: fg.withValues(alpha: 0.88),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
