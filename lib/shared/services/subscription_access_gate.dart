import 'package:flutter/foundation.dart';

import '../../core/navigation/app_navigator.dart';
import '../utils/crm_product_access.dart';
import '../utils/jwt_utils.dart';
import 'company_service.dart';
import 'secure_storage_service.dart';
import 'subscription_service.dart';

/// Desfecho da checagem de acesso (assinatura + produto CRM) na entrada do app.
enum AccessGateDecision {
  /// Segue normalmente.
  allow,

  /// Titular (owner admin/master) sem assinatura válida: vê o aviso de
  /// assinatura com acesso mínimo (planos, minha assinatura, chamados,
  /// perfil) — paridade com o `SubscriptionRequiredModal` /
  /// `/subscription-management` do web (`SubscriptionGuardNew.tsx`).
  subscriptionRequired,

  /// Colaborador de conta sem assinatura válida: "Sistema indisponível",
  /// como o `/system-unavailable` do web.
  systemUnavailable,

  /// Empresa sem o produto CRM e SEM o módulo Financeiro: o back recusa as
  /// rotas de CRM com 403 (`CrmProductAccessInterceptor`) e não há o que
  /// mostrar — aviso "plano não inclui o CRM".
  crmNotIncluded,

  /// Plano "só Financeiro" (sem CRM, com `financial_management`): o app abre
  /// direto no Meu Financeiro (decisão do Edson, 03/10/2026). As rotas de
  /// CRM continuam fechadas (cairiam em 403).
  financeOnly,
}

/// Decisão PURA do produto da empresa (testável): sem CRM e com o módulo
/// Financeiro → [AccessGateDecision.financeOnly]; sem CRM e sem Financeiro →
/// [AccessGateDecision.crmNotIncluded]; com CRM (ou lista desconhecida,
/// ou master) → [AccessGateDecision.allow].
AccessGateDecision decideProductAccess(
  Iterable<String>? modules, {
  String? role,
}) {
  if (!companyLacksCrmProduct(modules, role: role)) {
    return AccessGateDecision.allow;
  }
  final hasFinance = modules!.any(
    (m) => m.trim().toLowerCase() == 'financial_management',
  );
  return hasFinance
      ? AccessGateDecision.financeOnly
      : AccessGateDecision.crmNotIncluded;
}

/// Status que o web considera bloqueio DEFINITIVO de conta gerenciada
/// (`SubscriptionGuardNew.tsx`, `DEFINITIVE_BLOCK_STATUSES`).
const Set<String> kDefinitiveBlockStatuses = {
  'none',
  'suspended',
  'expired',
  'cancelled',
  'inactive',
};

/// Mensagem do `SubscriptionGuard` do back (403) — usada para reagir a um
/// bloqueio que aparece no meio da sessão. Comparação por trecho específico:
/// "assinatura" sozinho também quer dizer assinatura de documento.
const String kSubscriptionGuardMessageFragment =
    'sua assinatura está suspensa, cancelada ou expirada';

/// Decisão PURA de acesso pela assinatura (testável).
///
/// - Sem dado autoritativo (queda/timeout) → nunca bloqueia.
/// - Master da plataforma → sempre passa (o back também libera).
/// - `hasAccess` → passa.
/// - Titular de conta gerenciada (`billingRegime == managed`): só bloqueia
///   em estado terminal (mesma trava do web contra estados transitórios).
/// - Demais titulares → aviso de assinatura.
/// - Colaborador → sistema indisponível.
AccessGateDecision decideSubscriptionAccess({
  required String? role,
  required bool owner,
  required SubscriptionAccessInfo? info,
}) {
  final normalizedRole = (role ?? '').trim().toLowerCase();
  if (normalizedRole == 'master') return AccessGateDecision.allow;
  if (info == null || !info.isAuthoritative) return AccessGateDecision.allow;
  if (info.hasAccess) return AccessGateDecision.allow;

  final isOwner =
      owner && (normalizedRole == 'admin' || normalizedRole == 'master');
  if (isOwner) {
    final isManaged =
        (info.billingRegime ?? '').trim().toLowerCase() == 'managed';
    if (isManaged &&
        !kDefinitiveBlockStatuses.contains(info.status.trim().toLowerCase())) {
      return AccessGateDecision.allow;
    }
    return AccessGateDecision.subscriptionRequired;
  }
  return AccessGateDecision.systemUnavailable;
}

/// O 403 é o do `SubscriptionGuard` do back?
bool isSubscriptionGuardForbidden(int statusCode, dynamic body) {
  if (statusCode != 403) return false;
  final message = body is Map ? body['message'] : body;
  final text = (message is List ? message.join(' ') : message?.toString() ?? '')
      .toLowerCase();
  return text.contains(kSubscriptionGuardMessageFragment);
}

/// Estado de acesso da sessão e rotas permitidas quando bloqueado.
///
/// A decisão é tomada no login e no boot (splash). O `AppRoutes` consulta
/// [routeOverride] em toda navegação: com a conta bloqueada, qualquer rota
/// fora da lista permitida abre a tela de bloqueio — assim o drawer, deep
/// links e pushes também não levam a telas que só dariam 403.
class SubscriptionAccessGate {
  SubscriptionAccessGate._();

  static final SubscriptionAccessGate instance = SubscriptionAccessGate._();

  /// Rota da tela de aviso de assinatura (titular).
  static const String subscriptionRequiredRoute = '/subscription-required';

  /// Rota de "Sistema indisponível" (colaborador).
  static const String systemUnavailableRoute = '/system-unavailable';

  /// Rota de "Plano sem CRM".
  static const String crmNotIncludedRoute = '/crm-unavailable';

  /// Plano só Financeiro: a "Home" é o Meu Financeiro.
  static const String financeHomeRoute = '/financeiro/meu-dashboard';

  static const Set<String> _alwaysAllowed = {
    '/',
    '/login',
    '/forgot-password',
    '/forgot-password-confirmation',
    '/reset-password',
    '/two-factor',
    subscriptionRequiredRoute,
    systemUnavailableRoute,
    crmNotIncludedRoute,
  };

  /// Titular bloqueado: o mesmo acesso mínimo do web (assinar, ver a
  /// assinatura, abrir chamado, perfil e preferências).
  static const List<String> _subscriptionAllowedPrefixes = [
    '/subscription',
    '/tickets',
    '/profile',
    '/settings',
    '/help',
  ];

  /// Colaborador bloqueado: só perfil e preferências.
  static const List<String> _systemUnavailableAllowedPrefixes = [
    '/profile',
    '/settings',
  ];

  /// Plano só-Financeiro: rotas de plataforma que o back continua servindo.
  static const List<String> _crmAllowedPrefixes = [
    '/profile',
    '/settings',
    '/tickets',
    '/help',
    '/notifications',
    '/users',
    '/teams',
    '/subscription',
  ];

  /// Plano só Financeiro: as mesmas rotas de plataforma + o Financeiro.
  static const List<String> _financeOnlyAllowedPrefixes = [
    ..._crmAllowedPrefixes,
    '/financeiro',
  ];

  AccessGateDecision _decision = AccessGateDecision.allow;
  SubscriptionAccessInfo? _info;

  AccessGateDecision get decision => _decision;
  SubscriptionAccessInfo? get info => _info;
  bool get isBlocked => _decision != AccessGateDecision.allow;

  /// Rota de destino para a decisão (null = segue o fluxo normal).
  static String? routeFor(AccessGateDecision decision) {
    switch (decision) {
      case AccessGateDecision.allow:
        return null;
      case AccessGateDecision.subscriptionRequired:
        return subscriptionRequiredRoute;
      case AccessGateDecision.systemUnavailable:
        return systemUnavailableRoute;
      case AccessGateDecision.crmNotIncluded:
        return crmNotIncludedRoute;
      case AccessGateDecision.financeOnly:
        return financeHomeRoute;
    }
  }

  /// Rota liberada para a decisão atual? (pura, testável)
  static bool isRouteAllowed(AccessGateDecision decision, String route) {
    if (decision == AccessGateDecision.allow) return true;
    if (_alwaysAllowed.contains(route)) return true;
    final List<String> prefixes;
    switch (decision) {
      case AccessGateDecision.allow:
        return true;
      case AccessGateDecision.subscriptionRequired:
        prefixes = _subscriptionAllowedPrefixes;
      case AccessGateDecision.systemUnavailable:
        prefixes = _systemUnavailableAllowedPrefixes;
      case AccessGateDecision.crmNotIncluded:
        prefixes = _crmAllowedPrefixes;
      case AccessGateDecision.financeOnly:
        prefixes = _financeOnlyAllowedPrefixes;
    }
    return prefixes.any((p) => route == p || route.startsWith('$p/'));
  }

  /// Rota que deve abrir no lugar de [route] (null = abre a própria).
  String? routeOverride(String? route) {
    if (!isBlocked || route == null) return null;
    if (isRouteAllowed(_decision, route)) return null;
    return routeFor(_decision);
  }

  void clear() {
    _decision = AccessGateDecision.allow;
    _info = null;
  }

  /// Avalia assinatura e produto CRM da sessão atual. Nunca lança: falha de
  /// rede resulta em [AccessGateDecision.allow] (o back continua barrando).
  Future<AccessGateDecision> evaluate({
    String? role,
    bool? owner,
    List<String>? companyModules,
  }) async {
    try {
      final claims = await _tokenClaims();
      final effectiveRole =
          (role ?? claims['role']?.toString() ?? '').trim().toLowerCase();
      final effectiveOwner = owner ?? (claims['owner'] == true);

      final accessResponse =
          await SubscriptionService.instance.checkSubscriptionAccess();
      final info = accessResponse.success ? accessResponse.data : null;
      _info = info;

      var decision = decideSubscriptionAccess(
        role: effectiveRole,
        owner: effectiveOwner,
        info: info,
      );

      if (decision == AccessGateDecision.allow) {
        final modules = companyModules ?? await _selectedCompanyModules();
        decision = decideProductAccess(modules, role: effectiveRole);
      }

      _decision = decision;
      debugPrint('🛂 [ACCESS_GATE] Decisão: $decision (status: ${info?.status})');
      return decision;
    } catch (e) {
      debugPrint('⚠️ [ACCESS_GATE] Falha ao avaliar acesso: $e');
      _decision = AccessGateDecision.allow;
      return AccessGateDecision.allow;
    }
  }

  /// O back respondeu 403 do `SubscriptionGuard` no meio da sessão
  /// (ex.: assinatura suspensa depois do login). Reavalia e, se bloquear,
  /// leva para a tela correspondente — como o interceptor do web.
  bool _handlingForbidden = false;

  Future<void> onSubscriptionForbidden() async {
    if (_handlingForbidden || isBlocked) return;
    _handlingForbidden = true;
    try {
      SubscriptionService.instance.clearCache();
      var decision = await evaluate();
      if (decision == AccessGateDecision.allow) {
        // O check-access liberou mas o guard recusou: segue o web (titular
        // vai para a assinatura; colaborador, para "indisponível").
        final claims = await _tokenClaims();
        final role = claims['role']?.toString().trim().toLowerCase() ?? '';
        if (role == 'master') return;
        final isOwner = claims['owner'] == true &&
            (role == 'admin' || role == 'master');
        decision = isOwner
            ? AccessGateDecision.subscriptionRequired
            : AccessGateDecision.systemUnavailable;
        _decision = decision;
      }
      final target = routeFor(decision);
      final nav = appNavigatorKey.currentState;
      if (target != null && nav != null) {
        nav.pushNamedAndRemoveUntil(target, (route) => false);
      }
    } finally {
      _handlingForbidden = false;
    }
  }

  Future<Map<String, dynamic>> _tokenClaims() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) return const {};
      return JwtUtils.decodeToken(token) ?? const {};
    } catch (_) {
      return const {};
    }
  }

  Future<List<String>?> _selectedCompanyModules() async {
    try {
      final res = await CompanyService.instance.getSelectedCompany();
      return res.success ? res.data?.availableModules : null;
    } catch (_) {
      return null;
    }
  }
}
