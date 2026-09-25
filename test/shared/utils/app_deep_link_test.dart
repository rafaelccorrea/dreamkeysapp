import 'package:Intellisys/core/routes/app_routes.dart';
import 'package:Intellisys/shared/utils/app_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Casos das notificações de FICHA DE VENDA (25/09/2026): link externo do
/// Autentique abre fora do app; assinou/recusou/finalizada abrem o detalhe.
void main() {
  group('AppDeepLink.resolveTarget — ficha de venda', () {
    test('assine: actionUrl externo (Autentique) vira link externo', () {
      final target = AppDeepLink.resolveTarget(
        actionUrl: 'https://assina.ae/abc123',
        entityType: 'sale_form_signature',
        entityId: 'sig-1',
        metadata: {
          'saleFormId': 'sf-1',
          'formNumber': 42,
          'signatureId': 'sig-1',
          'signatureUrl': 'https://assina.ae/abc123',
          'externo': true,
        },
      );
      expect(target, isA<AppDeepLinkExternal>());
      expect(
        (target as AppDeepLinkExternal).uri.toString(),
        'https://assina.ae/abc123',
      );
    });

    test('assine via push (sem metadata): host de terceiro basta', () {
      final target = AppDeepLink.targetFromPushData({
        'actionUrl': 'https://app.autentique.com.br/assinar/xyz',
        'entityType': 'sale_form_signature',
        'entityId': 'sig-1',
      });
      expect(target, isA<AppDeepLinkExternal>());
    });

    test('externo=true com signatureUrl vence mesmo com actionUrl relativo',
        () {
      final target = AppDeepLink.resolveTarget(
        actionUrl: '/fichas-venda/detalhes/sf-1',
        metadata: {
          'externo': 'true',
          'signatureUrl': 'https://assina.ae/qwe',
        },
      );
      expect(target, isA<AppDeepLinkExternal>());
    });

    test('assinou/recusou: actionUrl /fichas-venda/detalhes/:id → detalhe', () {
      final target = AppDeepLink.resolveTarget(
        actionUrl: '/fichas-venda/detalhes/sf-9',
        entityType: 'sale_form_signature',
        entityId: 'sig-9',
        metadata: {'saleFormId': 'sf-9', 'externo': false},
      );
      expect(target, isA<AppDeepLinkRoute>());
      expect(
        (target as AppDeepLinkRoute).route,
        AppRoutes.saleFormDetails('sf-9'),
      );
    });

    test('finalizada: actionUrl com prefixo /sistema e entityType sale_form',
        () {
      final target = AppDeepLink.resolveTarget(
        actionUrl:
            'https://intellisysbr.com/sistema/fichas-venda/detalhes/sf-3',
        entityType: 'sale_form',
        entityId: 'sf-3',
      );
      expect(target, isA<AppDeepLinkRoute>());
      expect(
        (target as AppDeepLinkRoute).route,
        AppRoutes.saleFormDetails('sf-3'),
      );
    });

    test('URL absoluta do SPA continua resolvendo por path (não é externa)',
        () {
      final target = AppDeepLink.resolveTarget(
        actionUrl: 'https://intellisysbr.com/kanban/task/t-1',
      );
      expect(target, isA<AppDeepLinkRoute>());
      expect(
        (target as AppDeepLinkRoute).route,
        AppRoutes.kanbanTaskDetails('t-1'),
      );
    });
  });

  group('AppDeepLink.resolve — rotas da ficha de venda', () {
    test('/fichas-venda/:id curto → detalhe', () {
      expect(
        AppDeepLink.resolve(actionUrl: '/fichas-venda/sf-2'),
        AppRoutes.saleFormDetails('sf-2'),
      );
    });

    test('/fichas-venda/nova e /fichas-venda/dashboard → lista', () {
      expect(
        AppDeepLink.resolve(actionUrl: '/fichas-venda/nova?propostaId=p-1'),
        AppRoutes.saleForms,
      );
      expect(
        AppDeepLink.resolve(actionUrl: '/fichas-venda/dashboard'),
        AppRoutes.saleForms,
      );
    });

    test('entidade sale_form_signature sem saleFormId → sem destino', () {
      expect(
        AppDeepLink.resolve(
          entityType: 'sale_form_signature',
          entityId: 'sig-1',
        ),
        isNull,
      );
    });

    test('entidade sale_form_signature com saleFormId → detalhe', () {
      expect(
        AppDeepLink.resolve(
          entityType: 'sale_form_signature',
          entityId: 'sig-1',
          metadata: {'saleFormId': 'sf-1'},
        ),
        AppRoutes.saleFormDetails('sf-1'),
      );
    });

    test('resolve() nunca devolve link externo', () {
      expect(
        AppDeepLink.resolve(actionUrl: 'https://assina.ae/abc123'),
        isNull,
      );
    });
  });

  group('AppDeepLink.isSystemHost', () {
    test('domínios do sistema e rede local', () {
      expect(AppDeepLink.isSystemHost('intellisysbr.com'), isTrue);
      expect(AppDeepLink.isSystemHost('www.intellisysbr.com'), isTrue);
      expect(AppDeepLink.isSystemHost('api.dreamkeys.com.br'), isTrue);
      expect(AppDeepLink.isSystemHost('localhost'), isTrue);
      expect(AppDeepLink.isSystemHost('192.168.0.10'), isTrue);
    });

    test('terceiros', () {
      expect(AppDeepLink.isSystemHost('assina.ae'), isFalse);
      expect(AppDeepLink.isSystemHost('app.autentique.com.br'), isFalse);
      expect(AppDeepLink.isSystemHost('intellisysbr.com.evil.io'), isFalse);
    });
  });
}
