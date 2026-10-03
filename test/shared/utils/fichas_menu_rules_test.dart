import 'package:Intellisys/shared/utils/fichas_menu_rules.dart';
import 'package:flutter_test/flutter_test.dart';

bool Function(String) _perms(Set<String> granted) => granted.contains;

/// M-1/M-2/M-3 (03/10/2026): itens de Fichas no menu com a regra do web.
void main() {
  group('Fichas de venda / Assinaturas pendentes (M-1)', () {
    test('view_team/view_all sem view não mostram (a tela daria sem acesso)',
        () {
      expect(
        FichasMenuRules.canSeeSaleForms(
          hasModule: true,
          has: _perms({
            'sale_form:view_team',
            'sale_form:view_all',
            'sale_form:create',
          }),
        ),
        isFalse,
      );
    });

    test('view + uma ação mostram', () {
      expect(
        FichasMenuRules.canSeeSaleForms(
          hasModule: true,
          has: _perms({'sale_form:view', 'sale_form:export'}),
        ),
        isTrue,
      );
    });

    test('view sem nenhuma ação não mostra (canShowDrawerItem do web)', () {
      expect(
        FichasMenuRules.canSeeSaleForms(
          hasModule: true,
          has: _perms({'sale_form:view'}),
        ),
        isFalse,
      );
    });

    test('sem o módulo sale_forms não mostra', () {
      expect(
        FichasMenuRules.canSeeSaleForms(
          hasModule: false,
          has: (_) => true,
        ),
        isFalse,
      );
    });
  });

  group('Fichas de proposta (M-2)', () {
    test('view_team/view_all sem view não mostram', () {
      expect(
        FichasMenuRules.canSeeProposals(
          hasModule: true,
          has: _perms({
            'proposal:view_team',
            'proposal:view_all',
            'proposal:create',
          }),
        ),
        isFalse,
      );
    });

    test('view + ação mostram', () {
      expect(
        FichasMenuRules.canSeeProposals(
          hasModule: true,
          has: _perms({'proposal:view', 'proposal:create'}),
        ),
        isTrue,
      );
    });
  });

  group('Dashboards (M-3)', () {
    test('só a view_dashboard exata libera', () {
      expect(
        FichasMenuRules.canSeeSaleFormsDashboard(
          hasModule: true,
          has: _perms({'sale_form:view_dashboard'}),
        ),
        isTrue,
      );
      expect(
        FichasMenuRules.canSeeSaleFormsDashboard(
          hasModule: true,
          has: _perms({'sale_form:view', 'sale_form:create'}),
        ),
        isFalse,
      );
      expect(
        FichasMenuRules.canSeeProposalsDashboard(
          hasModule: true,
          has: _perms({'proposal:view_dashboard'}),
        ),
        isTrue,
      );
      expect(
        FichasMenuRules.canSeeProposalsDashboard(
          hasModule: true,
          has: _perms({'proposal:view', 'proposal:update'}),
        ),
        isFalse,
      );
    });

    test('dashboard sem a lista: aparece mesmo sem view (caso do M-3)', () {
      final has = _perms({'sale_form:view_dashboard'});
      expect(
        FichasMenuRules.canSeeSaleForms(hasModule: true, has: has),
        isFalse,
      );
      expect(
        FichasMenuRules.canSeeSaleFormsDashboard(hasModule: true, has: has),
        isTrue,
      );
    });

    test('sem módulo não aparece', () {
      expect(
        FichasMenuRules.canSeeProposalsDashboard(
          hasModule: false,
          has: (_) => true,
        ),
        isFalse,
      );
    });
  });
}
