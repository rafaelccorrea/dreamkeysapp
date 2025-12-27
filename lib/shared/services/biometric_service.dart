import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

/// Serviço para autenticação biométrica
class BiometricService {
  BiometricService._();

  static final BiometricService instance = BiometricService._();
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Verifica se o dispositivo suporta biometria
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  /// Verifica se há biometria disponível e configurada
  Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  /// Lista os tipos de biometria disponíveis
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Verifica se há biometria configurada no dispositivo
  Future<bool> hasBiometrics() async {
    try {
      final isSupported = await isDeviceSupported();
      final canCheck = await canCheckBiometrics();
      final available = await getAvailableBiometrics();
      return isSupported && canCheck && available.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Realiza a autenticação biométrica
  Future<bool> authenticate({
    String reason = 'Autentique-se para continuar',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    try {
      // Verifica se há biometria disponível
      if (!await hasBiometrics()) {
        return false;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          biometricOnly: true, // Apenas biometria, sem fallback para PIN/senha
        ),
      );

      return didAuthenticate;
    } on PlatformException catch (e) {
      // Trata erros específicos da plataforma
      if (e.code == 'NotAvailable') {
        // Biometria não disponível
        return false;
      } else if (e.code == 'NotEnrolled') {
        // Biometria não configurada
        return false;
      } else if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        // Muitas tentativas falhadas
        return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Obtém uma descrição amigável do tipo de biometria disponível
  Future<String> getBiometricTypeDescription() async {
    final available = await getAvailableBiometrics();
    
    if (available.isEmpty) {
      return 'Biometria';
    }

    // Prioriza Face ID, depois Fingerprint
    if (available.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (available.contains(BiometricType.fingerprint)) {
      return 'Impressão Digital';
    } else if (available.contains(BiometricType.iris)) {
      return 'Íris';
    } else if (available.contains(BiometricType.strong)) {
      return 'Biometria';
    } else {
      return 'Biometria';
    }
  }
}





