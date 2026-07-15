import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';

/// Regras de senha — espelham EXATAMENTE o backend
/// (`RegisterWithConfirmationDto`): mínimo 8 caracteres com maiúscula,
/// minúscula, número e caractere especial do conjunto `@ $ ! % * ? &`.
///
/// Paridade com `PasswordChecklist.tsx` do `imobx-front`.
class PasswordRule {
  final String id;
  final String label;
  final bool Function(String value) test;

  const PasswordRule({
    required this.id,
    required this.label,
    required this.test,
  });
}

final List<PasswordRule> passwordRules = [
  PasswordRule(
    id: 'length',
    label: 'Pelo menos 8 caracteres',
    test: (v) => v.length >= 8,
  ),
  PasswordRule(
    id: 'upper',
    label: 'Uma letra maiúscula (A–Z)',
    test: (v) => RegExp(r'[A-Z]').hasMatch(v),
  ),
  PasswordRule(
    id: 'lower',
    label: 'Uma letra minúscula (a–z)',
    test: (v) => RegExp(r'[a-z]').hasMatch(v),
  ),
  PasswordRule(
    id: 'number',
    label: 'Um número (0–9)',
    test: (v) => RegExp(r'\d').hasMatch(v),
  ),
  PasswordRule(
    id: 'special',
    label: r'Um caractere especial (@ $ ! % * ? &)',
    test: (v) => RegExp(r'[@$!%*?&]').hasMatch(v),
  ),
];

/// `true` quando a senha cumpre TODAS as regras do backend.
bool isRegisterPasswordValid(String value) {
  return passwordRules.every((rule) => rule.test(value));
}

/// Checklist de senha com medidor de força — vive logo abaixo do campo de
/// senha na tela de registro. Verde = requisito cumprido (cor por
/// significado), âmbar = força média, vermelho = fraca.
class PasswordChecklist extends StatelessWidget {
  final String value;

  const PasswordChecklist({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = isDark
        ? AppColors.message.successTextDarkMode
        : AppColors.message.successText;
    final weak = isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final medium = AppColors.status.warning;
    final muted =
        isDark ? AppColors.text.textLightDarkMode : AppColors.text.textLight;
    final track = isDark
        ? AppColors.border.borderDarkMode
        : AppColors.border.border;

    final results = passwordRules
        .map((rule) => (rule: rule, met: rule.test(value)))
        .toList();
    final metCount = results.where((r) => r.met).length;
    final total = results.length;
    final hasInput = value.isNotEmpty;
    final ratio = metCount / total;

    final strengthLabel = !hasInput
        ? ''
        : ratio < 0.6
            ? 'Fraca'
            : ratio < 1
                ? 'Média'
                : 'Forte';
    final strengthColor = ratio < 0.6 ? weak : (ratio < 1 ? medium : ok);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Medidor de força em segmentos + rótulo.
          Row(
            children: [
              Expanded(
                child: Row(
                  children: List.generate(total, (i) {
                    final filled = hasInput && i < metCount;
                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        height: 4,
                        margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                        decoration: BoxDecoration(
                          color: filled ? strengthColor : track,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              if (strengthLabel.isNotEmpty) ...[
                const SizedBox(width: 10),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: strengthColor,
                    letterSpacing: 0.2,
                  ),
                  child: Text(strengthLabel),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Lista de requisitos.
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: results.map((r) {
              final color = r.met ? ok : muted;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: r.met
                          ? ok.withValues(alpha: 0.14)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: r.met ? ok : track,
                        width: 1.2,
                      ),
                    ),
                    child: r.met
                        ? Icon(Icons.check_rounded, size: 10, color: ok)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    r.rule.label,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: r.met ? FontWeight.w500 : FontWeight.w400,
                      color: color,
                      height: 1.2,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
