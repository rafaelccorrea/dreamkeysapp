import 'package:Intellisys/features/properties/services/property_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PropertyApprovalSettingsFull.fromJson', () {
    test('lê strings numéricas, booleanos em texto e listas sujas', () {
      final s = PropertyApprovalSettingsFull.fromJson({
        'id': 'abc',
        'requireApprovalToBeAvailable': 'true',
        'requireApprovalToPublishOnSite': 1,
        'requireOwnerAuthorizationToBeAvailable': null,
        'applyWatermarkToImages': false,
        'approversEnabled': '1',
        'minApprovalsAvailability': '3',
        'minApprovalsPublication': 2.0,
        'protectedFieldsEnabled': true,
        'protectedFields': ['salePrice', null, '', 'salePrice', 'iptu'],
        'propertyFormRequiredFields': ['bedrooms'],
        'propertyFormAllowedTeamIds': ['t1', 't2'],
        'onDeactivateUserResponsibleAssignTo': 'user',
        'onDeactivateUserResponsibleUserId': 'u9',
        'onDeactivateUserCaptorAction': 'keep',
      });
      expect(s.id, 'abc');
      expect(s.requireApprovalToBeAvailable, isTrue);
      expect(s.requireApprovalToPublishOnSite, isTrue);
      expect(s.requireOwnerAuthorizationToBeAvailable, isFalse);
      expect(s.applyWatermarkToImages, isFalse);
      expect(s.approversEnabled, isTrue);
      expect(s.minApprovalsAvailability, 3);
      expect(s.minApprovalsPublication, 2);
      expect(s.protectedFields, ['salePrice', 'iptu']);
      expect(s.onDeactivateAssignTo, SuccessionTarget.user);
      expect(s.onDeactivateUserId, 'u9');
      expect(s.onDeactivateCaptorAction, CaptorAction.keep);
      expect(s.anyActive, isTrue);
    });

    test('padrões quando o corpo vem vazio', () {
      final s = PropertyApprovalSettingsFull.fromJson(const {});
      expect(s.applyWatermarkToImages, isTrue);
      expect(s.preservePublicationOnEdit, isTrue);
      expect(s.minApprovalsAvailability, 1);
      expect(s.onDeactivateAssignTo, SuccessionTarget.companyOwner);
      expect(s.onDeactivateCaptorAction, CaptorAction.remove);
      expect(s.onDeactivateUserId, isNull);
      expect(s.anyActive, isFalse);
    });
  });

  group('outros modelos', () {
    test('form-settings usa todas as equipes da empresa quando vierem', () {
      final b = PropertyFormSettingsBundle.fromJson({
        'propertyFormRequiredFields': ['bedrooms'],
        'propertyFormAllowedTeamIds': [],
        'teams': [
          {'id': 't1', 'name': 'A', 'color': '#ff0000'},
        ],
        'allCompanyTeams': [
          {'id': 't1', 'name': 'A'},
          {'id': 't2', 'name': 'B'},
          {'name': 'sem id'},
        ],
      });
      expect(b.editableTeams.map((t) => t.id), ['t1', 't2']);
      expect(b.teams.single.color, '#ff0000');

      final semTodas = PropertyFormSettingsBundle.fromJson({
        'teams': [
          {'id': 't1', 'name': 'A'},
        ],
      });
      expect(semTodas.editableTeams.single.id, 't1');
    });

    test('aprovador lê o usuário aninhado e o tipo', () {
      final a = PropertyApproverConfig.fromJson({
        'id': 'c1',
        'userId': 'u1',
        'approvalType': 'edit_request',
        'isRequired': 'true',
        'displayOrder': '2',
        'user': {'id': 'u1', 'name': 'Ana', 'email': 'ana@x.com'},
      });
      expect(a.type, ApproverType.editRequest);
      expect(a.userName, 'Ana');
      expect(a.isRequired, isTrue);
      expect(a.displayOrder, 2);

      final semTipo = PropertyApproverConfig.fromJson(
        {'id': 'c2', 'user': {'id': 'u2'}},
        fallbackType: ApproverType.publication,
      );
      expect(semTipo.type, ApproverType.publication);
      expect(semTipo.userId, 'u2');
      expect(semTipo.userName, 'Usuário');
    });

    test('autorizados, catálogo, escopo e membro', () {
      final auth = PropertyAuthorizedApprovers.fromJson({
        'availability': [
          {'id': 'u1', 'name': 'Ana'},
        ],
        'publication': null,
      });
      expect(auth.availability.single.name, 'Ana');
      expect(auth.publication, isEmpty);
      expect(auth.isEmpty, isFalse);

      expect(
        PropertyCatalogEntry.tryParse(
          {'id': 'i1', 'kind': 'room', 'name': 'Lavabo', 'sortOrder': '4'},
        )?.sortOrder,
        4,
      );
      expect(PropertyCatalogEntry.tryParse({'id': 'i1', 'kind': 'x'}), isNull);
      expect(PropertyCatalogEntry.tryParse('lixo'), isNull);

      final scope = OwnerDataScope.fromJson({
        'restrictedProperties': '12',
        'responsible': {'id': 'r1', 'name': 'União Imobiliária'},
      });
      expect(scope.restrictedProperties, 12);
      expect(scope.responsibleName, 'União Imobiliária');

      final m = PropertySettingsMember.fromJson({
        'id': 'u1',
        'name': 'Bruno',
        'email': 'b@x.com',
        'role': 'manager',
        'enabledAt': '2026-09-24T10:00:00.000Z',
      });
      expect(m.role, 'manager');
      expect(m.enabledAt, isNotNull);
    });
  });

  group('PropertyFormRules', () {
    test('sanitizeExtras tira chaves do sistema, vazias e repetidas', () {
      expect(
        PropertyFormRules.sanitizeExtras(
          ['title', 'bedrooms', ' ', 'bedrooms', 'iptu', 'ownerName'],
        ),
        ['bedrooms', 'iptu'],
      );
    });

    test('catálogo tem 32 campos e 13 do sistema', () {
      expect(PropertyFormRules.fields, hasLength(32));
      expect(PropertyFormRules.fields.where((f) => f.isSystem), hasLength(13));
      final r = PropertyFormRules.reading(null, ['bedrooms', 'iptu']);
      expect(r.total, 32);
      expect(r.system, 13);
      expect(r.extras, 2);
      expect(r.required, 15);
      expect(r.free, 17);
      final valores = PropertyFormRules.reading(3, ['iptu', 'bedrooms']);
      expect(valores.total, 4);
      expect(valores.extras, 1);
    });

    const base = PropertyFormRulesState(
      extras: ['bedrooms'],
      restrictTeams: true,
      allowedTeamIds: ['t1', 't2'],
    );

    test('countChanges segue o alteracoes do web', () {
      expect(PropertyFormRules.countChanges(null, base), 0);
      expect(PropertyFormRules.countChanges(base, base), 0);
      // mesmo conjunto em outra ordem não conta
      expect(
        PropertyFormRules.countChanges(
          base,
          base.copyWith(allowedTeamIds: ['t2', 't1']),
        ),
        0,
      );
      final mudou = base.copyWith(
        extras: ['iptu'], // -bedrooms +iptu = 2
        allowedTeamIds: ['t1'], // conjunto = 1
        successionTarget: SuccessionTarget.user, // 1
        successorId: 'u1', // 1
        captorAction: CaptorAction.keep, // 1
      );
      expect(PropertyFormRules.countChanges(base, mudou), 6);
      // desligar a restrição conta 1 (o conjunto não conta junto)
      expect(
        PropertyFormRules.countChanges(
          base,
          base.copyWith(restrictTeams: false, allowedTeamIds: const []),
        ),
        1,
      );
    });

    test('blockReason: equipe, sucessor e nada a salvar', () {
      final semEquipe = base.copyWith(allowedTeamIds: const []);
      expect(
        PropertyFormRules.blockReason(base, semEquipe, 3),
        'Marque ao menos uma equipe ou volte para todas',
      );
      // sem equipes na empresa a restrição vazia não trava
      expect(PropertyFormRules.blockReason(base, semEquipe, 0), isNull);

      final semSucessor =
          base.copyWith(successionTarget: SuccessionTarget.user);
      expect(
        PropertyFormRules.blockReason(base, semSucessor, 3),
        'Escolha o sucessor dos imóveis',
      );
      expect(PropertyFormRules.blockReason(base, base, 3), 'Nada a salvar');
      expect(
        PropertyFormRules.blockReason(
          base,
          semSucessor.copyWith(successorId: 'u1'),
          3,
        ),
        isNull,
      );
    });

    test('buildPayload monta o PATCH do web', () {
      final p = PropertyFormRules.buildPayload(
        base.copyWith(extras: ['title', 'bedrooms', 'bedrooms']),
      );
      expect(p, {
        'propertyFormRequiredFields': ['bedrooms'],
        'propertyFormAllowedTeamIds': ['t1', 't2'],
        'onDeactivateUserResponsibleAssignTo': 'company_owner',
        'onDeactivateUserResponsibleUserId': null,
        'onDeactivateUserCaptorAction': 'remove',
      });
      final livre = PropertyFormRules.buildPayload(
        base.copyWith(
          restrictTeams: false,
          successionTarget: SuccessionTarget.user,
          successorId: ' u7 ',
          captorAction: CaptorAction.keep,
        ),
      );
      expect(livre['propertyFormAllowedTeamIds'], isEmpty);
      expect(livre['onDeactivateUserResponsibleAssignTo'], 'user');
      expect(livre['onDeactivateUserResponsibleUserId'], 'u7');
      expect(livre['onDeactivateUserCaptorAction'], 'keep');
    });

    test('fromServer e rótulos', () {
      final s = PropertyFormRulesState.fromServer(
        bundle: PropertyFormSettingsBundle.fromJson({
          'propertyFormRequiredFields': ['title', 'iptu'],
          'propertyFormAllowedTeamIds': ['t1'],
        }),
        approval: PropertyApprovalSettingsFull.fromJson({
          'onDeactivateUserResponsibleAssignTo': 'company_owner',
          'onDeactivateUserResponsibleUserId': 'u3',
        }),
      );
      expect(s.extras, ['iptu']);
      expect(s.restrictTeams, isTrue);
      expect(s.successorId, 'u3');
      expect(
        PropertyFormRules.successionLabel(s, successorName: 'Ana'),
        'dono da empresa (contingência: Ana)',
      );
      expect(
        PropertyFormRules.successionLabel(
          s.copyWith(successionTarget: SuccessionTarget.user, clearSuccessor: true),
        ),
        'usuário a escolher',
      );
      expect(PropertyFormRules.teamsInPicker(s, 5), 1);
      expect(
        PropertyFormRules.teamsInPicker(s.copyWith(restrictTeams: false), 5),
        5,
      );
    });
  });

  group('PropertyApprovalRules', () {
    test('rulesPayload leva só os 5 interruptores', () {
      final s = PropertyApprovalSettingsFull.fromJson({
        'requireApprovalToBeAvailable': true,
        'approversEnabled': true,
      });
      expect(PropertyApprovalRules.rulesPayload(s), {
        'requireApprovalToBeAvailable': true,
        'requireApprovalToPublishOnSite': false,
        'requireOwnerAuthorizationToBeAvailable': false,
        'applyWatermarkToImages': true,
        'preservePublicationOnEdit': true,
      });
      expect(PropertyApprovalRules.rulesDirty(s, s), isFalse);
      expect(
        PropertyApprovalRules.rulesDirty(
          s,
          s.copyWith(applyWatermarkToImages: false),
        ),
        isTrue,
      );
      // votação não é "regra" do botão Salvar regras
      expect(
        PropertyApprovalRules.rulesDirty(s, s.copyWith(approversEnabled: false)),
        isFalse,
      );
    });

    test('quórum nunca abaixo de 1', () {
      expect(PropertyApprovalRules.clampMinApprovals(null), 1);
      expect(PropertyApprovalRules.clampMinApprovals(0), 1);
      expect(PropertyApprovalRules.clampMinApprovals(-4), 1);
      expect(PropertyApprovalRules.clampMinApprovals(3), 3);
      expect(
        PropertyApprovalRules.quorumPayload(ApproverType.availability, 0),
        {'minApprovalsAvailability': 1},
      );
      expect(
        PropertyApprovalRules.quorumPayload(ApproverType.publication, 2),
        {'minApprovalsPublication': 2},
      );
    });

    test('campos protegidos preservam a lista', () {
      expect(
        PropertyApprovalRules.protectedFieldsPayload(
          enabled: true,
          fields: const ['salePrice'],
        ),
        {
          'protectedFieldsEnabled': true,
          'protectedFields': ['salePrice'],
        },
      );
    });
  });

  group('OwnerDataRules', () {
    const users = [
      PropertySettingsMember(id: '1', name: 'Ângela Souza', email: 'a@x.com', role: 'admin'),
      PropertySettingsMember(id: '2', name: 'Bruno', email: 'bruno@x.com', role: 'manager'),
      PropertySettingsMember(id: '3', name: 'Caio', email: 'caio@x.com'),
      PropertySettingsMember(id: '4', name: 'Dora', email: 'dora@x.com', role: 'MASTER'),
    ];

    test('papel desconhecido vira corretor; admin/master veem pelo papel', () {
      expect(OwnerDataRules.roleOf(null), OwnerDataRole.user);
      expect(OwnerDataRules.roleOf('MASTER'), OwnerDataRole.master);
      expect(OwnerDataRules.seesByRole('admin'), isTrue);
      expect(OwnerDataRules.seesByRole('manager'), isFalse);
      final c = OwnerDataRules.countByRole(users);
      expect(c[OwnerDataRole.master], 1);
      expect(c[OwnerDataRole.admin], 1);
      expect(c[OwnerDataRole.manager], 1);
      expect(c[OwnerDataRole.user], 1);
      expect(OwnerDataRules.roleLabel(OwnerDataRole.user, plural: true),
          'Corretores');
    });

    test('busca sem acento e sem caixa, por nome ou e-mail e papel', () {
      expect(OwnerDataRules.filter(users, 'angela').single.id, '1');
      expect(OwnerDataRules.filter(users, 'BRUNO@').single.id, '2');
      expect(OwnerDataRules.filter(users, ''), hasLength(4));
      expect(
        OwnerDataRules.filter(users, '', role: OwnerDataRole.user).single.id,
        '3',
      );
      expect(OwnerDataRules.fold('Ação É'), 'acao e');
    });

    test('iniciais', () {
      expect(propertySettingsInitials('Maria da Silva'), 'MS');
      expect(propertySettingsInitials('ana'), 'AN');
      expect(propertySettingsInitials('  '), '?');
    });
  });

  group('PropertySettingsGates', () {
    const perm = 'property:manage_approval_settings';

    test('regras: master/admin pelo papel, gestor só com a permissão', () {
      bool can(String? role, List<String> p, {bool module = true}) =>
          PropertySettingsGates.canManageApprovalSettings(
            role: role,
            explicitPermissions: p,
            moduleAvailable: module,
          );
      expect(can('master', const []), isTrue);
      expect(can('admin', const []), isTrue);
      expect(can('manager', const []), isFalse);
      expect(can('manager', const [perm]), isTrue);
      expect(can('user', const []), isFalse);
      expect(can('user', const [perm]), isTrue);
      expect(can('admin', const [], module: false), isFalse);
    });

    test('dados do proprietário: admin/master OU permissão explícita', () {
      bool can(String? role, List<String> p, {bool module = true}) =>
          PropertySettingsGates.canViewOwnerData(
            role: role,
            explicitPermissions: p,
            moduleAvailable: module,
          );
      expect(can('Admin', const []), isTrue);
      expect(can('master', const []), isTrue);
      expect(can('manager', const []), isFalse);
      expect(can('user', const ['property:view_protected_owner_data']), isTrue);
      expect(can('master', const [], module: false), isFalse);
      expect(PropertySettingsGates.canManageOwnerData('admin'), isTrue);
      expect(PropertySettingsGates.canManageOwnerData('manager'), isFalse);
    });
  });
}
