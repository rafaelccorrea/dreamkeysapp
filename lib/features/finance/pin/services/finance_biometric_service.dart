import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../shared/services/biometric_service.dart';
import '../../core/finance_pin_store.dart';

/// Biometria OPCIONAL para destravar o Financeiro (decisão do Edson,
/// 03/10/2026).
///
/// Não existe endpoint de biometria no back: depois do 1º PIN válido, com o
/// aceite da pessoa, o app guarda o PIN no armazenamento seguro (Keychain /
/// Keystore, o mesmo `FlutterSecureStorage` do app). A digital/rosto só
/// LIBERA esse PIN guardado, que continua sendo conferido em
/// `POST /auth/pin/verify` — o back segue com a última palavra (freio de 5
/// erros incluso). Um 422 com o PIN guardado o apaga.
///
/// Chaves por pessoa (`sub` do CRM): outra conta no mesmo aparelho não usa
/// o PIN de ninguém.
class FinanceBiometricService extends ChangeNotifier {
  FinanceBiometricService._();

  static final FinanceBiometricService instance = FinanceBiometricService._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _pinPrefix = 'finance_bio_pin_';
  static const String _declinedPrefix = 'finance_bio_declined_';

  Future<String?> _owner() => FinancePinStore.crmSubject();

  /// O aparelho tem biometria cadastrada?
  Future<bool> isSupported() => BiometricService.instance.hasBiometrics();

  /// "Digital", "Face ID"…
  Future<String> label() async {
    final d = await BiometricService.instance.getBiometricTypeDescription();
    return d == 'Impressão Digital' ? 'digital' : d;
  }

  /// Ligada para a pessoa logada (há PIN guardado)?
  Future<bool> isEnabled() async {
    final owner = await _owner();
    if (owner == null) return false;
    try {
      final v = await _storage.read(key: '$_pinPrefix$owner');
      return v != null && v.length == 4;
    } catch (_) {
      return false;
    }
  }

  /// A pessoa já disse "agora não" ao convite (o convite não volta; dá
  /// para ligar no perfil).
  Future<bool> wasDeclined() async {
    final owner = await _owner();
    if (owner == null) return true;
    try {
      return await _storage.read(key: '$_declinedPrefix$owner') == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> setDeclined() async {
    final owner = await _owner();
    if (owner == null) return;
    try {
      await _storage.write(key: '$_declinedPrefix$owner', value: 'true');
    } catch (_) {}
  }

  /// Guarda o PIN (já conferido pelo back) e liga a biometria.
  Future<bool> enable(String pin) async {
    final owner = await _owner();
    if (owner == null || !RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    try {
      await _storage.write(key: '$_pinPrefix$owner', value: pin);
      await _storage.delete(key: '$_declinedPrefix$owner');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('⚠️ [FINANCE_BIO] Não deu para guardar o PIN: $e');
      return false;
    }
  }

  /// Desliga e apaga o PIN guardado.
  Future<void> disable() async {
    final owner = await _owner();
    if (owner == null) return;
    try {
      await _storage.delete(key: '$_pinPrefix$owner');
    } catch (_) {}
    notifyListeners();
  }

  /// Atualiza o PIN guardado depois de uma redefinição (só se já ligada).
  Future<void> updateIfEnabled(String pin) async {
    if (await isEnabled()) await enable(pin);
  }

  /// Pede a digital/rosto e devolve o PIN guardado (ou `null`: cancelou,
  /// falhou ou não há PIN). O prompt tira o app do primeiro plano em alguns
  /// aparelhos — a trava de segundo plano fica segurada durante ele.
  Future<String?> unlockPin() async {
    final owner = await _owner();
    if (owner == null) return null;
    String? pin;
    try {
      pin = await _storage.read(key: '$_pinPrefix$owner');
    } catch (_) {
      pin = null;
    }
    if (pin == null || pin.length != 4) return null;
    final ok = await FinancePinStore.instance.holdBackgroundLock(
      () => BiometricService.instance.authenticate(
        reason: 'Destrave o Financeiro',
      ),
    );
    return ok ? pin : null;
  }
}
