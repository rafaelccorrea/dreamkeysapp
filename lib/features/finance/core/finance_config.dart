/// Configuração do cliente do microserviço Financeiro (NestJS sob `/api/v1`).
///
/// A base de produção é a mesma do `VITE_FINANCEIRO_API_URL` do web
/// (`intellisys-CRM/.env.production:11`). Para apontar para outro ambiente:
/// `flutter run --dart-define=FINANCE_API_BASE_URL=https://.../api/v1`.
library;

class FinanceConfig {
  FinanceConfig._();

  static const String baseUrl = String.fromEnvironment(
    'FINANCE_API_BASE_URL',
    defaultValue: 'https://api.financeiro.intellisysbr.com/api/v1',
  );

  /// Teto padrão de uma chamada (regra de ouro do `intellisys-CRM/CLAUDE.md`).
  static const Duration timeout = Duration(seconds: 30);

  /// Criar solicitação (POST /requests) pode demorar mais.
  static const Duration longTimeout = Duration(seconds: 120);

  /// Upload de anexo.
  static const Duration uploadTimeout = Duration(seconds: 90);

  /// Módulo da empresa que libera o Financeiro (sem bypass de papel).
  static const String moduleCode = 'financial_management';

  /// Cabeçalhos do contrato do PIN (`finance-pin.regras.ts:14,17`).
  static const String pinHeader = 'X-Finance-Pin';
  static const String pinRenewedHeader = 'x-finance-pin-token';
  static const String companyHeader = 'X-Company-ID';

  /// Código do 428 que pede o PIN (`finance-pin.regras.ts:30`).
  static const String pinRequiredCode = 'FINANCE_PIN_REQUIRED';
}
