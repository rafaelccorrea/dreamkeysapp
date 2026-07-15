import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/auth_service.dart';
import '../../../shared/services/company_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/onboarding_models.dart';

/// Serviço do onboarding — registro de conta com confirmação de email e
/// criação da primeira empresa.
///
/// Paridade com o `imobx-front`:
///   - `authApi.registerWithConfirmation` → `POST /auth/register-with-confirmation`
///   - `authApi.confirmRegistration`      → `POST /auth/confirm-registration`
///   - `companyApi.createCompany`         → `POST /companies`
///
/// Observações de infraestrutura:
///   - Rotas `/auth/*` não recebem `X-Company-ID` (regra do `ApiService`).
///   - `POST /companies` tem Company ID OPCIONAL no interceptor — essencial
///     aqui, pois o usuário ainda NÃO tem empresa selecionada.
///   - NÃO usamos `GET /companies/has-companies`: no app essa rota exigiria
///     `X-Company-ID` (bloqueio do interceptor para quem ainda não tem
///     empresa). A checagem equivalente é via `CompanyService.getCompanies()`.
class OnboardingService {
  OnboardingService._();

  static final OnboardingService instance = OnboardingService._();
  final ApiService _api = ApiService.instance;

  // Endpoints (constantes privadas — fiação central pode promover depois).
  static const String _registerWithConfirmationEndpoint =
      '/auth/register-with-confirmation';
  static const String _confirmRegistrationEndpoint =
      '/auth/confirm-registration';
  static const String _companiesEndpoint = '/companies';

  /// `POST /auth/register-with-confirmation` — cria a conta e dispara o
  /// email com o link de confirmação (a conta só é ativada após o clique).
  Future<ApiResponse<RegisterConfirmationInfo>> registerAccount(
    RegisterAccountRequest request,
  ) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _registerWithConfirmationEndpoint,
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: RegisterConfirmationInfo.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar conta. Tente novamente.',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ONBOARDING] registerAccount: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /auth/confirm-registration` — confirma a conta a partir do token
  /// recebido por email (usado quando o link abre o app via deep link).
  Future<ApiResponse<ConfirmRegistrationResult>> confirmRegistration(
    String token,
  ) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _confirmRegistrationEndpoint,
        body: {'token': token},
      );

      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: ConfirmRegistrationResult.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao confirmar registro.',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ONBOARDING] confirmRegistration: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /companies` — cria a primeira empresa do owner autenticado.
  ///
  /// Em caso de sucesso, grava o `companyId` selecionado no storage seguro
  /// (paridade com `setSelectedCompanyId` do web) e tenta renovar o token
  /// (best-effort, como o web faz para o JWT refletir a nova empresa).
  Future<ApiResponse<CreatedCompany>> createFirstCompany(
    CreateFirstCompanyRequest request,
  ) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        _companiesEndpoint,
        body: request.toJson(),
      );

      if (response.success && response.data != null) {
        final company = CreatedCompany.fromJson(response.data!);

        if (company.id.isNotEmpty) {
          await SecureStorageService.instance.saveCompanyId(company.id);
          debugPrint(
            '✅ [ONBOARDING] Empresa criada e selecionada: ${company.id} (${company.name})',
          );
        }

        // Refresh best-effort: se falhar, a empresa JÁ foi criada — o token
        // atual continua válido e o app segue normalmente.
        try {
          await AuthService.instance.refreshToken();
        } catch (e) {
          debugPrint(
            '⚠️ [ONBOARDING] Empresa criada, mas refresh do token falhou: $e',
          );
        }

        return ApiResponse.success(
          data: company,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar empresa. Tente novamente.',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [ONBOARDING] createFirstCompany: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Verifica se o usuário autenticado já possui empresa (fallback do fluxo
  /// de erro do web: se o POST falhar mas a empresa existir, seguimos em
  /// frente). Usa `GET /companies` — Company ID opcional no interceptor.
  Future<bool> userAlreadyHasCompany() async {
    try {
      final response = await CompanyService.instance.getCompanies();
      final companies = response.data;
      if (response.success && companies != null && companies.isNotEmpty) {
        final preferred = CompanyService.choosePreferredCompany(companies);
        if (preferred != null) {
          await SecureStorageService.instance.saveCompanyId(preferred.id);
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ [ONBOARDING] userAlreadyHasCompany: $e');
      return false;
    }
  }
}
