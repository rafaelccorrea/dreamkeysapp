import 'package:flutter_test/flutter_test.dart';

import 'package:Intellisys/features/sale_forms/sale_form_audit_display.dart';
import 'package:Intellisys/features/sale_forms/sale_form_list_display.dart';
import 'package:Intellisys/features/sale_forms/widgets/sale_form_row_rules.dart';
import 'package:Intellisys/features/sale_forms/widgets/sale_form_signature_lock_sheet.dart';
import 'package:Intellisys/features/sale_forms/widgets/sale_forms_filters_sheet.dart';
import 'package:Intellisys/shared/services/sale_forms_service.dart';

SaleForm _f(Map<String, dynamic> m) => SaleForm({'id': 'x', ...m});

SaleFormSignatureLockItem _item(String id) => SaleFormSignatureLockItem(
      saleFormId: id,
      formNumber: id,
      daysPending: 3,
      notificationCount: 1,
    );

void main() {
  group('V-A1 bloqueio das assinaturas', () {
    test('cancelada, finalizada, excluída e sem update bloqueiam', () {
      expect(
        saleFormSignaturesBlockReason(_f({'status': 'canceled'}),
            canUpdate: true),
        contains('cancelada'),
      );
      expect(
        saleFormSignaturesBlockReason(_f({'status': 'finalized'}),
            canUpdate: true),
        contains('finalizada'),
      );
      expect(
        saleFormSignaturesBlockReason(
            _f({'status': 'processing', 'deletedAt': '2026-10-01'}),
            canUpdate: true),
        contains('excluída'),
      );
      expect(
        saleFormSignaturesBlockReason(_f({'status': 'processing'}),
            canUpdate: false),
        contains('permissão'),
      );
    });
    test('aguardando/em processamento com update liberam', () {
      expect(
        saleFormSignaturesBlockReason(_f({'status': 'waiting_for_signature'}),
            canUpdate: true),
        isNull,
      );
      expect(
        saleFormSignaturesBlockReason(_f({'status': 'processing'}),
            canUpdate: true),
        isNull,
      );
    });
  });

  group('V-A7 trava depois da recusa', () {
    final atual = SaleFormSignatureLockStatus(
      blocked: true,
      maxNotifications: 3,
      thresholdDays: 2,
      items: [_item('a'), _item('b')],
    );
    test('consulta ok sem bloqueio fecha', () {
      expect(
        signatureLockAposRecusa(
          atual: atual,
          recusadaId: 'a',
          consulta: const SaleFormSignatureLockStatus(
            blocked: false,
            maxNotifications: 3,
            thresholdDays: 2,
            items: [],
          ),
          consultaOk: true,
        ),
        isNull,
      );
    });
    test('consulta ok bloqueada usa o que o back devolveu', () {
      final r = signatureLockAposRecusa(
        atual: atual,
        recusadaId: 'a',
        consulta: SaleFormSignatureLockStatus(
          blocked: true,
          maxNotifications: 3,
          thresholdDays: 2,
          items: [_item('b'), _item('c')],
        ),
        consultaOk: true,
      );
      expect(r!.items.map((i) => i.saleFormId), ['b', 'c']);
    });
    test('falha de rede: lista local sem a recusada', () {
      final r = signatureLockAposRecusa(
        atual: atual,
        recusadaId: 'a',
        consulta: null,
        consultaOk: false,
      );
      expect(r!.items.map((i) => i.saleFormId), ['b']);
    });
    test('V-A6 ir para a ficha: edição só com update', () {
      expect(signatureLockIrParaFichaAbreEdicao(canUpdate: true), isTrue);
      expect(signatureLockIrParaFichaAbreEdicao(canUpdate: false), isFalse);
    });
  });

  group('V-A8/V-A9 Raio-X', () {
    test('frases de "sem mudança" iguais ao web', () {
      expect(saleFormAuditNoChangeText('linked_users_add', 0),
          startsWith('Nenhum dado do formulário foi alterado.'));
      expect(saleFormAuditNoChangeText('update', 2),
          startsWith('Não há mudanças visíveis'));
      expect(saleFormAuditNoChangeText('update', 0),
          'Nenhuma alteração de campo neste evento.');
    });
    test('JSON técnico sem addedUserIds', () {
      final j = saleFormAuditMetadataJson({
        'formNumber': 'FV-1',
        'addedUserIds': ['u1'],
      });
      expect(j, contains('"formNumber": "FV-1"'));
      expect(j, isNot(contains('addedUserIds')));
    });
    test('autor: nome ou Sistema (e-mail à parte)', () {
      final e = SaleFormAuditEntry.fromJson({
        'id': '1',
        'action': 'update',
        'userEmail': 'a@b.com',
      });
      expect(e.autor, 'Sistema');
      expect(e.userEmail, 'a@b.com');
      expect(e.temInfoExtra, isFalse);
    });
  });

  group('V-L6/V-L5 filtros e exportação', () {
    test('filtro abre com data da venda = hoje quando não há', () {
      final r = saleFormsFiltroDataVendaInicial(
        const SaleFormFilters(),
        DateTime(2026, 10, 3, 15, 30),
      );
      expect(r.from, DateTime(2026, 10, 3));
      expect(r.to, DateTime(2026, 10, 3));
    });
    test('exportação: userIds só com view_all; ordem por criação', () {
      const base = SaleFormFilters(userIds: ['u1'], sortBy: 'buyerName');
      final sem = saleFormsExportFilters(base, search: ' x ', canViewAll: false);
      expect(sem.userIds, isEmpty);
      expect(sem.search, 'x');
      expect(sem.sortBy, 'createdAt');
      expect(sem.sortOrder, 'DESC');
      final com = saleFormsExportFilters(base,
          search: '', canViewAll: true, deletedOnly: true);
      expect(com.userIds, ['u1']);
      expect(com.listDeletedOnly, isTrue);
      expect(com.search, isNull);
    });
  });

  group('lista/detalhe', () {
    test('V-L7 salvo em (web formatarSalvoEm)', () {
      final agora = DateTime(2026, 10, 3, 11);
      expect(fichaRascunhoSalvoEm(DateTime(2026, 10, 3, 9, 5), agora),
          'hoje às 09:05');
      expect(fichaRascunhoSalvoEm(DateTime(2026, 10, 2, 18, 40), agora),
          'ontem às 18:40');
      expect(fichaRascunhoSalvoEm(DateTime(2026, 9, 28, 9, 5), agora),
          'em 28/09 às 09:05');
    });
    test('V-A10 unidades compartilhadas', () {
      expect(saleFormSharedUnitsText(['b'], {'a': 'A'}), isNull);
      expect(saleFormSharedUnitsText(const [], {'a': 'A', 'b': 'B'}),
          'Nenhuma — visível apenas para a unidade responsável');
      expect(saleFormSharedUnitsText(['b'], {'a': 'A', 'b': 'B'}), 'B');
    });
    test('V-L10/V-A11 rótulos iguais ao web', () {
      final f = _f({'status': 'canceled', 'distratoAbertoEm': '2026-10-01'});
      expect(f.statusLabel, 'Em distrato — aguardando anexo no Financeiro');
      expect(f.statusShortLabel, 'Em distrato');
      expect(
        SaleFormAttachment.fromJson({'id': '1', 'status': 'pending_approval'})
            .statusLabel,
        'Pendente',
      );
    });
    test('V-L2 vendedor da linha em lançamento', () {
      final f = _f({
        'saleFormType': 'lancamento',
        'empreendimentoData': {'incorporadora': 'Inc X'},
      });
      expect(saleFormSellerListLabel(f), 'Inc X');
    });
  });
}
