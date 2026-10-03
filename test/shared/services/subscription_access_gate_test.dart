import 'package:Intellisys/shared/services/company_service.dart';
import 'package:Intellisys/shared/services/subscription_access_gate.dart';
import 'package:Intellisys/shared/services/subscription_service.dart';
import 'package:Intellisys/shared/utils/crm_product_access.dart';
import 'package:flutter_test/flutter_test.dart';

SubscriptionAccessInfo _info({
  bool hasAccess = false,
  String status = 'none',
  String? billingRegime,
  bool authoritative = true,
}) {
  return SubscriptionAccessInfo(
    hasAccess: hasAccess,
    status: status,
    canAccessFeatures: hasAccess,
    isExpired: status == 'expired',
    isSuspended: status == 'suspended',
    billingRegime: billingRegime,
    isAuthoritative: authoritative,
  );
}

/// NEW-01 (paridade 03/10/2026): decisão de acesso pela assinatura, espelho do
/// `SubscriptionGuardNew.tsx` do web + `/system-unavailable`.
void main() {
  group('decideSubscriptionAccess', () {
    test('com acesso → libera', () {
      expect(
        decideSubscriptionAccess(
          role: 'user',
          owner: false,
          info: _info(hasAccess: true, status: 'active'),
        ),
        AccessGateDecision.allow,
      );
    });

    test('master sempre passa', () {
      expect(
        decideSubscriptionAccess(role: 'master', owner: true, info: _info()),
        AccessGateDecision.allow,
      );
    });

    test('sem dado autoritativo (queda/timeout) nunca bloqueia', () {
      expect(
        decideSubscriptionAccess(
          role: 'user',
          owner: false,
          info: _info(authoritative: false),
        ),
        AccessGateDecision.allow,
      );
      expect(
        decideSubscriptionAccess(role: 'admin', owner: true, info: null),
        AccessGateDecision.allow,
      );
    });

    test('titular gerenciado com trial vencido → aviso de assinatura', () {
      expect(
        decideSubscriptionAccess(
          role: 'admin',
          owner: true,
          info: _info(status: 'none', billingRegime: 'managed'),
        ),
        AccessGateDecision.subscriptionRequired,
      );
    });

    test('titular gerenciado com assinatura suspensa → aviso de assinatura', () {
      expect(
        decideSubscriptionAccess(
          role: 'admin',
          owner: true,
          info: _info(status: 'suspended', billingRegime: 'managed'),
        ),
        AccessGateDecision.subscriptionRequired,
      );
    });

    test('titular gerenciado em estado transitório → não bloqueia', () {
      expect(
        decideSubscriptionAccess(
          role: 'admin',
          owner: true,
          info: _info(status: 'active', billingRegime: 'managed'),
        ),
        AccessGateDecision.allow,
      );
    });

    test('titular self-serve sem acesso → aviso de assinatura', () {
      expect(
        decideSubscriptionAccess(
          role: 'admin',
          owner: true,
          info: _info(status: 'expired', billingRegime: 'self_serve'),
        ),
        AccessGateDecision.subscriptionRequired,
      );
    });

    test('colaborador da conta bloqueada → sistema indisponível', () {
      expect(
        decideSubscriptionAccess(
          role: 'user',
          owner: false,
          info: _info(status: 'none'),
        ),
        AccessGateDecision.systemUnavailable,
      );
      // Admin que não é dono também não pode assinar.
      expect(
        decideSubscriptionAccess(
          role: 'admin',
          owner: false,
          info: _info(status: 'suspended'),
        ),
        AccessGateDecision.systemUnavailable,
      );
    });
  });

  group('SubscriptionAccessGate.isRouteAllowed', () {
    test('titular bloqueado: assinatura, chamados e perfil liberados', () {
      const d = AccessGateDecision.subscriptionRequired;
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/subscription'), isTrue);
      expect(
        SubscriptionAccessGate.isRouteAllowed(d, '/subscription/plans'),
        isTrue,
      );
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/tickets/new'), isTrue);
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/profile'), isTrue);
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/login'), isTrue);
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/home'), isFalse);
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/properties'), isFalse);
    });

    test('colaborador bloqueado: só perfil/preferências', () {
      const d = AccessGateDecision.systemUnavailable;
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/profile'), isTrue);
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/subscription'), isFalse);
      expect(SubscriptionAccessGate.isRouteAllowed(d, '/home'), isFalse);
    });

    test('sem bloqueio: tudo liberado', () {
      expect(
        SubscriptionAccessGate.isRouteAllowed(
          AccessGateDecision.allow,
          '/kanban',
        ),
        isTrue,
      );
    });
  });

  group('isSubscriptionGuardForbidden', () {
    const msg =
        'Acesso negado: sua assinatura está suspensa, cancelada ou expirada. Entre em contato com o suporte.';

    test('reconhece o 403 do SubscriptionGuard', () {
      expect(isSubscriptionGuardForbidden(403, {'message': msg}), isTrue);
    });

    test('ignora outros 403 e outros status', () {
      expect(
        isSubscriptionGuardForbidden(403, {
          'message': 'Assinatura do documento pendente',
        }),
        isFalse,
      );
      expect(isSubscriptionGuardForbidden(400, {'message': msg}), isFalse);
    });
  });

  group('CompanyService.choosePreferredCompany com plano só Financeiro', () {
    Company c(String id, {bool matrix = false, List<String> modules = const []}) =>
        Company(id: id, name: id, isMatrix: matrix, availableModules: modules);

    test('prefere a empresa com CRM mesmo se a matriz não tiver', () {
      final chosen = CompanyService.choosePreferredCompany([
        c('fin', matrix: true, modules: ['financial_management']),
        c('crm', modules: ['kanban_management']),
      ]);
      expect(chosen?.id, 'crm');
    });

    test('sem nenhuma com CRM, mantém a regra da matriz', () {
      final chosen = CompanyService.choosePreferredCompany([
        c('a', modules: ['financial_management']),
        c('b', matrix: true, modules: ['financial_management']),
      ]);
      expect(chosen?.id, 'b');
    });
  });

  group('hasCrmProduct / companyLacksCrmProduct (NEW-02)', () {
    test('plano só Financeiro não tem CRM', () {
      const modules = [
        'user_management',
        'company_management',
        'team_management',
        'financial_management',
      ];
      expect(hasCrmProduct(modules), isFalse);
      expect(companyLacksCrmProduct(modules), isTrue);
    });

    test('empresa com módulo de CRM tem CRM', () {
      const modules = ['user_management', 'kanban_management'];
      expect(hasCrmProduct(modules), isTrue);
      expect(companyLacksCrmProduct(modules), isFalse);
    });

    test('add-on e módulo oculto não contam como CRM', () {
      expect(hasCrmProduct(['rental_management', 'whatsapp_ai']), isFalse);
      expect(hasCrmProduct(['gamification', 'MCMV']), isFalse);
    });

    test('lista vazia/nula não bloqueia (legado); master passa', () {
      expect(companyLacksCrmProduct(const []), isFalse);
      expect(companyLacksCrmProduct(null), isFalse);
      expect(
        companyLacksCrmProduct(const ['financial_management'], role: 'master'),
        isFalse,
      );
    });
  });
}
