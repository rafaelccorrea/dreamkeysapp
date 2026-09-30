import 'package:flutter/foundation.dart';

import '../../../../shared/services/api_service.dart';

/// Dados do setup público de 2FA (POST /auth/2fa/setup).
class TwoFactorSetupData {
  final String secret;

  /// `data:image/png;base64,...` gerado pelo back — renderizado direto,
  /// sem depender de pacote de QR.
  final String qrCodeDataUrl;

  const TwoFactorSetupData({required this.secret, required this.qrCodeDataUrl});
}

/// Setup de 2FA ANTES do login — mesmo fluxo do web
/// (twoFactorAuthApi.startPublicSetup / verifyPublicSetup): quando a empresa
/// exige 2FA e o usuário ainda não configurou, ele gera o segredo com
/// e-mail + senha, confirma com o código TOTP e então segue o login.
class TwoFactorSetupService {
  TwoFactorSetupService._();

  static final TwoFactorSetupService instance = TwoFactorSetupService._();
  final ApiService _api = ApiService.instance;

  static const String _setupPath = '/auth/2fa/setup';
  static const String _verifySetupPath = '/auth/2fa/verify-setup';

  /// Back responde `{ success, data: { secret, qrCodeDataUrl } }`.
  Future<ApiResponse<TwoFactorSetupData>> startSetup({
    required String email,
    required String password,
  }) async {
    try {
      // `retryOn401: false`: rota pública (e-mail + senha, sem sessão). O 401
      // aqui é "senha errada" — sem isto o ApiService tentaria renovar uma
      // sessão que não existe e jogaria a pessoa no login sem a mensagem.
      final res = await _api.post<dynamic>(
        _setupPath,
        body: {'email': email, 'password': password},
        retryOn401: false,
      );
      if (res.success && res.data is Map) {
        final root = Map<String, dynamic>.from(res.data as Map);
        final data = root['data'] is Map
            ? Map<String, dynamic>.from(root['data'] as Map)
            : root;
        final secret = data['secret']?.toString() ?? '';
        final qr = data['qrCodeDataUrl']?.toString() ?? '';
        if (secret.isEmpty && qr.isEmpty) {
          return ApiResponse.error(
            message: 'Resposta de configuração do 2FA sem QR Code',
            statusCode: res.statusCode,
          );
        }
        return ApiResponse.success(
          data: TwoFactorSetupData(secret: secret, qrCodeDataUrl: qr),
          statusCode: res.statusCode,
        );
      }
      // Mesma mensagem do web quando a rota pública não existe no servidor.
      if (res.statusCode == 404) {
        return ApiResponse.error(
          message:
              'Configuração pública de 2FA indisponível no servidor. Solicite '
              'ao administrador a ativação ou tente novamente mais tarde.',
          statusCode: 404,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Falha ao iniciar configuração do 2FA.',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('[2FA_SETUP] Erro ao iniciar setup: $e');
      return ApiResponse.error(
        message: 'Falha ao iniciar configuração do 2FA.',
        statusCode: 0,
      );
    }
  }

  /// Back responde `{ success, data: { enabled } }`. Devolve `true` só quando
  /// o 2FA ficou ativo.
  Future<ApiResponse<bool>> verifySetup({
    required String email,
    required String password,
    required String code,
  }) async {
    try {
      final res = await _api.post<dynamic>(
        _verifySetupPath,
        body: {'email': email, 'password': password, 'code': code},
        retryOn401: false,
      );
      if (res.success && res.data is Map) {
        final root = Map<String, dynamic>.from(res.data as Map);
        final data = root['data'] is Map
            ? Map<String, dynamic>.from(root['data'] as Map)
            : root;
        return ApiResponse.success(
          data: data['enabled'] == true,
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Não foi possível verificar o código.',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('[2FA_SETUP] Erro ao verificar setup: $e');
      return ApiResponse.error(
        message: 'Não foi possível verificar o código.',
        statusCode: 0,
      );
    }
  }
}
