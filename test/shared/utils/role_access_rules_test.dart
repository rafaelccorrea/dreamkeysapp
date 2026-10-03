import 'package:Intellisys/shared/utils/role_access_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// transv-03/transv-04: bypass de papel igual aos guards do back.
void main() {
  group('roleBypassesPermission', () {
    test('master passa em tudo', () {
      expect(roleBypassesPermission('master', 'user:create'), isTrue);
      expect(roleBypassesPermission('MASTER', 'key:view'), isTrue);
    });

    test('admin passa em tudo menos user:create', () {
      expect(roleBypassesPermission('admin', 'key:view'), isTrue);
      expect(roleBypassesPermission('admin', 'user:create'), isFalse);
    });

    test('manager só nas permissões que o back libera', () {
      expect(roleBypassesPermission('manager', 'property:update'), isTrue);
      expect(
        roleBypassesPermission('manager', 'performance:view_company'),
        isTrue,
      );
      expect(roleBypassesPermission('manager', 'key:create'), isFalse);
      expect(roleBypassesPermission('manager', 'calendar:delete'), isFalse);
    });

    test('corretor e papel desconhecido não têm bypass', () {
      expect(roleBypassesPermission('user', 'property:update'), isFalse);
      expect(roleBypassesPermission(null, 'key:view'), isFalse);
    });
  });

  group('roleBypassesModule', () {
    test('só master ignora o módulo da empresa', () {
      expect(roleBypassesModule('master'), isTrue);
      expect(roleBypassesModule('admin'), isFalse);
      expect(roleBypassesModule('manager'), isFalse);
      expect(roleBypassesModule('user'), isFalse);
    });
  });
}
