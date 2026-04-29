import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

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
    bool stickyAuth = true,
  }) async {
    try {
      debugPrint('🔐 [BIOMETRIC_SERVICE] Iniciando autenticação...');
      debugPrint('🔐 [BIOMETRIC_SERVICE] Reason: $reason');
      
      final hasBiometricsResult = await hasBiometrics();
      debugPrint('🔐 [BIOMETRIC_SERVICE] hasBiometrics: $hasBiometricsResult');
      
      if (!hasBiometricsResult) {
        debugPrint('❌ [BIOMETRIC_SERVICE] Biometria não disponível');
        return false;
      }

      debugPrint('🔐 [BIOMETRIC_SERVICE] Chamando _localAuth.authenticate...');
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: stickyAuth,
      );

      debugPrint('🔐 [BIOMETRIC_SERVICE] Resultado da autenticação: $didAuthenticate');
      return didAuthenticate;
    } on LocalAuthException catch (e) {
      debugPrint('❌ [BIOMETRIC_SERVICE] LocalAuthException: ${e.code.name} - ${e.description}');
      switch (e.code) {
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          debugPrint('❌ [BIOMETRIC_SERVICE] Biometria não disponível');
          return false;
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noCredentialsSet:
          debugPrint('❌ [BIOMETRIC_SERVICE] Biometria não configurada');
          return false;
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          debugPrint('❌ [BIOMETRIC_SERVICE] Biometria bloqueada');
          return false;
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.userRequestedFallback:
          debugPrint('ℹ️ [BIOMETRIC_SERVICE] Autenticação cancelada');
          return false;
        default:
          debugPrint('❌ [BIOMETRIC_SERVICE] Erro: ${e.code.name}');
          return false;
      }
    } on PlatformException catch (e) {
      debugPrint('❌ [BIOMETRIC_SERVICE] PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e, stackTrace) {
      debugPrint('❌ [BIOMETRIC_SERVICE] Erro genérico: $e');
      debugPrint('📚 [BIOMETRIC_SERVICE] StackTrace: $stackTrace');
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





