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
    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyBiometricEnabled, value: 'true');
  }

  /// Recupera o email salvo
  Future<String?> getSavedEmail() async {
    return await _storage.read(key: _keyEmail);
  }

  /// Recupera a senha salva
  Future<String?> getSavedPassword() async {
    return await _storage.read(key: _keyPassword);
  }

  /// Verifica se a biometria está habilitada
  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _keyBiometricEnabled);
    return value == 'true';
  }

  /// Remove as credenciais salvas
  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyEmail);
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keyBiometricEnabled);
  }

  /// Verifica se existem credenciais salvas
  Future<bool> hasSavedCredentials() async {
    final email = await getSavedEmail();
    final password = await getSavedPassword();
    return email != null && email.isNotEmpty && password != null && password.isNotEmpty;
  }
}

