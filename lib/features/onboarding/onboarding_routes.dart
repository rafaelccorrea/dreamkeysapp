/// Nomes de rota do onboarding — a fiação central registra estes nomes no
/// `AppRoutes.generateRoute` (ver manifest). Mantidos aqui para a feature
/// compilar sem editar `app_routes.dart`.
class OnboardingRoutes {
  OnboardingRoutes._();

  /// Registro de conta (paridade com `/register` do web).
  static const String register = '/register';

  /// Confirmação de email pós-registro (estado aguardando/confirmado).
  static const String registerConfirm = '/register/confirm';

  /// Wizard de criação da primeira empresa (paridade com
  /// `/create-first-company` do web).
  static const String createFirstCompany = '/onboarding/company';
}
