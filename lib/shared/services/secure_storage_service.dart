import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Serviço para armazenamento seguro de credenciais
class SecureStorageService {
  SecureStorageService._();

  static final SecureStorageService instance = SecureStorageService._();
  
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Chaves de armazenamento
  static const String _keyEmail = 'saved_email';
  static const String _keyPassword = 'saved_password';
  static const String _keyBiometricEnabled = 'biometric_enabled';

  /// Salva as credenciais do usuário
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    try {
      await _storage.write(key: _keyEmail, value: email);
      await _storage.write(key: _keyPassword, value: password);
      await _storage.write(key: _keyBiometricEnabled, value: 'true');
      debugPrint('✅ [SECURE_STORAGE] Credenciais salvas com sucesso');
    } catch (e) {
      debugPrint('❌ [SECURE_STORAGE] Erro ao salvar credenciais: $e');
      rethrow;
    }
  }

  /// Recupera o email salvo
  Future<String?> getSavedEmail() async {
    try {
      return await _storage.read(key: _keyEmail);
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao ler email: $e');
      return null;
    }
  }

  /// Recupera a senha salva
  Future<String?> getSavedPassword() async {
    try {
      return await _storage.read(key: _keyPassword);
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao ler senha: $e');
      return null;
    }
  }

  /// Verifica se a biometria está habilitada
  Future<bool> isBiometricEnabled() async {
    try {
      final value = await _storage.read(key: _keyBiometricEnabled);
      return value == 'true';
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao verificar biometria habilitada: $e');
      return false;
    }
  }

  /// Remove as credenciais salvas
  Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _keyEmail);
      await _storage.delete(key: _keyPassword);
      await _storage.delete(key: _keyBiometricEnabled);
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao limpar credenciais: $e');
    }
  }

  /// Verifica se existem credenciais salvas
  Future<bool> hasSavedCredentials() async {
    try {
      final email = await getSavedEmail();
      final password = await getSavedPassword();
      return email != null && email.isNotEmpty && password != null && password.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao verificar credenciais salvas: $e');
      return false;
    }
  }
}

