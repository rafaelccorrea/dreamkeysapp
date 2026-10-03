import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../core/finance_errors.dart';
import '../../core/finance_visibility.dart';
import '../services/finance_biometric_service.dart';
import '../services/finance_pin_service.dart';

/// Perfil → "Destravar o Financeiro com digital/rosto" (liga/desliga).
///
/// Só aparece com o módulo Financeiro na empresa e biometria cadastrada no
/// aparelho. Ligar pede o PIN uma vez (conferido no back) para guardá-lo.
class FinanceBiometricTile extends StatefulWidget {
  const FinanceBiometricTile({super.key});

  @override
  State<FinanceBiometricTile> createState() => _FinanceBiometricTileState();
}

class _FinanceBiometricTileState extends State<FinanceBiometricTile> {
  final FinanceBiometricService _bio = FinanceBiometricService.instance;
  bool _supported = false;
  bool _enabled = false;
  bool _busy = false;
  String _label = 'biometria';

  @override
  void initState() {
    super.initState();
    _bio.addListener(_load);
    unawaited(_load());
  }

  @override
  void dispose() {
    _bio.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final supported = await _bio.isSupported();
    final enabled = supported && await _bio.isEnabled();
    final label = supported ? await _bio.label() : 'biometria';
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _enabled = enabled;
      _label = label;
    });
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    if (!on) {
      setState(() => _busy = true);
      await _bio.disable();
      if (mounted) setState(() => _busy = false);
      _snack('Biometria do Financeiro desligada.');
      return;
    }
    final pin = await _askPin();
    if (pin == null || !mounted) return;
    setState(() => _busy = true);
    final res = await FinancePinService.instance.verify(pin);
    if (!mounted) return;
    if (res.success) {
      final ok = await _bio.enable(pin);
      if (mounted) setState(() => _busy = false);
      _snack(
        ok
            ? 'Pronto: o Financeiro destrava com $_label.'
            : 'Não deu para ligar a biometria agora.',
      );
      return;
    }
    setState(() => _busy = false);
    final e = res.error;
    if (e is FinanceError && e.statusCode == 404) {
      _snack('Você ainda não tem PIN. Abra o Meu Financeiro para criar.');
    } else {
      _snack(res.message ?? 'Não deu para conferir o PIN.');
    }
  }

  Future<String?> _askPin() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirme seu PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Digite o PIN do Financeiro para guardá-lo com segurança '
              'neste aparelho.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              enableSuggestions: false,
              autocorrect: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, letterSpacing: 14),
              decoration: const InputDecoration(counterText: ''),
              onSubmitted: (v) {
                if (v.length == 4) Navigator.of(ctx).pop(v);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.length == 4) Navigator.of(ctx).pop(ctrl.text);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFinance =
        companyHasFinanceModule(ModuleAccessService.instance.companyModules) ==
        true;
    if (!_supported || !hasFinance) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _label == 'Face ID'
                  ? LucideIcons.scanFace
                  : LucideIcons.fingerprint,
              size: 19,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destravar o Financeiro com $_label',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'O PIN fica guardado neste aparelho; a $_label só o libera.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _enabled,
            activeTrackColor: accent,
            onChanged: _busy ? null : _toggle,
          ),
        ],
      ),
    );
  }
}
