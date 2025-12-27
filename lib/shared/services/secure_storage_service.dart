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
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyCompanyId = 'dream_keys_selected_company_id';

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

  /// Salva o token de acesso
  Future<void> saveAccessToken(String token) async {
    try {
      await _storage.write(key: _keyAccessToken, value: token);
      debugPrint('✅ [SECURE_STORAGE] Token de acesso salvo com sucesso');
    } catch (e) {
      debugPrint('❌ [SECURE_STORAGE] Erro ao salvar token de acesso: $e');
      rethrow;
    }
  }

  /// Recupera o token de acesso
  Future<String?> getAccessToken() async {
    try {
      return await _storage.read(key: _keyAccessToken);
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao ler token de acesso: $e');
      return null;
    }
  }

  /// Salva o refresh token
  Future<void> saveRefreshToken(String refreshToken) async {
    try {
      await _storage.write(key: _keyRefreshToken, value: refreshToken);
      debugPrint('✅ [SECURE_STORAGE] Refresh token salvo com sucesso');
    } catch (e) {
      debugPrint('❌ [SECURE_STORAGE] Erro ao salvar refresh token: $e');
      rethrow;
    }
  }

  /// Recupera o refresh token
  Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _keyRefreshToken);
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao ler refresh token: $e');
      return null;
    }
  }

  /// Salva ambos os tokens
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      await saveAccessToken(accessToken);
      await saveRefreshToken(refreshToken);
      debugPrint('✅ [SECURE_STORAGE] Tokens salvos com sucesso');
    } catch (e) {
      debugPrint('❌ [SECURE_STORAGE] Erro ao salvar tokens: $e');
      rethrow;
    }
  }

  /// Remove os tokens salvos
  Future<void> clearTokens() async {
    try {
      await _storage.delete(key: _keyAccessToken);
      await _storage.delete(key: _keyRefreshToken);
      debugPrint('✅ [SECURE_STORAGE] Tokens removidos');
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao limpar tokens: $e');
    }
  }

  /// Verifica se existe token salvo
  Future<bool> hasSavedToken() async {
    try {
      final token = await getAccessToken();
      return token != null && token.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao verificar token salvo: $e');
      return false;
    }
  }

  /// Salva o Company ID selecionado
  Future<void> saveCompanyId(String companyId) async {
    try {
      await _storage.write(key: _keyCompanyId, value: companyId);
      debugPrint('✅ [SECURE_STORAGE] Company ID salvo: $companyId');
    } catch (e) {
      debugPrint('❌ [SECURE_STORAGE] Erro ao salvar Company ID: $e');
      rethrow;
    }
  }

  /// Recupera o Company ID selecionado
  Future<String?> getCompanyId() async {
    try {
      return await _storage.read(key: _keyCompanyId);
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao ler Company ID: $e');
      return null;
    }
  }

  /// Remove o Company ID selecionado
  Future<void> clearCompanyId() async {
    try {
      await _storage.delete(key: _keyCompanyId);
      debugPrint('✅ [SECURE_STORAGE] Company ID removido');
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao limpar Company ID: $e');
    }
  }

  /// Limpa todos os dados de autenticação (tokens, credenciais e Company ID)
  Future<void> clearAllAuthData() async {
    try {
      await clearTokens();
      await clearCredentials();
      await clearCompanyId();
      debugPrint('✅ [SECURE_STORAGE] Todos os dados de autenticação removidos');
    } catch (e) {
      debugPrint('⚠️ [SECURE_STORAGE] Erro ao limpar dados de autenticação: $e');
    }
  }
}

