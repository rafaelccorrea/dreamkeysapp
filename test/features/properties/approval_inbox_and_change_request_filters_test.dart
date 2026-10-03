import 'package:flutter_test/flutter_test.dart';
import 'package:Intellisys/features/properties/models/approval_chat_inbox_item.dart';
import 'package:Intellisys/features/properties/models/property_change_request.dart';
import 'package:Intellisys/features/properties/utils/change_request_filters.dart';

void main() {
  group('ApprovalChatInboxItem', () {
    test('lê o formato do back (array direto ou { data })', () {
      final raw = [
        {
          'propertyId': 'p1',
          'propertyTitle': 'Casa Azul',
          'propertyCode': 'C-10',
          'approvalContext': 'publication',
          'messageCount': 4,
          'unreadCount': '2',
          'isViewed': false,
          'lastViewedAt': null,
          'lastMessageAt': '2026-10-03T12:00:00.000Z',
          'lastPreview': 'Pode publicar?',
          'lastUserName': 'Ana',
        },
        {'propertyId': '', 'propertyTitle': 'sem id'},
        'lixo',
        {
          'propertyId': 'p2',
          'propertyTitle': 'Apto',
          'approvalContext': 'qualquer',
          'unreadCount': -3,
        },
      ];
      final items = ApprovalChatInboxItem.listFrom(raw);
      expect(items.length, 2);
      expect(items[0].isPublication, isTrue);
      expect(items[0].unreadCount, 2);
      expect(items[0].hasUnread, isTrue);
      expect(items[0].isViewed, isFalse);
      expect(items[0].lastMessageAt, isNotNull);
      expect(items[0].previewLine, 'Ana: Pode publicar?');
      expect(items[0].key, 'p1::publication');
      // Contexto desconhecido conta como cadastro; contador negativo vira 0.
      expect(items[1].approvalContext, 'availability');
      expect(items[1].unreadCount, 0);
      expect(items[1].previewLine, 'Sem mensagens');

      expect(ApprovalChatInboxItem.listFrom({'data': raw}).length, 2);
      expect(ApprovalChatInboxItem.listFrom(null), isEmpty);
    });

    test('prévia cai para o código quando não há mensagem', () {
      const it = ApprovalChatInboxItem(
        propertyId: 'p',
        propertyTitle: 'T',
        approvalContext: 'availability',
        propertyCode: 'X1',
      );
      expect(it.previewLine, 'Cód. X1');
    });

    test('total de não lidas, busca local e marcar como vista', () {
      const a = ApprovalChatInboxItem(
        propertyId: 'a',
        propertyTitle: 'Casa no Lago',
        approvalContext: 'availability',
        unreadCount: 3,
        lastPreview: 'falta foto',
      );
      const b = ApprovalChatInboxItem(
        propertyId: 'b',
        propertyTitle: 'Sala comercial',
        approvalContext: 'publication',
        propertyCode: 'SC-9',
        unreadCount: 1,
        lastUserName: 'Bruno',
      );
      expect(ApprovalChatInboxItem.totalUnread([a, b]), 4);
      expect(ApprovalChatInboxItem.filter([a, b], '  '), [a, b]);
      expect(ApprovalChatInboxItem.filter([a, b], 'FOTO'), [a]);
      expect(ApprovalChatInboxItem.filter([a, b], 'sc-9'), [b]);
      expect(ApprovalChatInboxItem.filter([a, b], 'bruno'), [b]);
      final seen = a.markedAsSeen();
      expect(seen.unreadCount, 0);
      expect(seen.isViewed, isTrue);
      expect(seen.key, a.key);
    });
  });

  group('formatApprovalInboxTime', () {
    final now = DateTime(2026, 10, 3, 15, 30);
    test('agora, minutos, hora, ontem, data', () {
      expect(formatApprovalInboxTime(null, now: now), '');
      expect(
        formatApprovalInboxTime(now.subtract(const Duration(seconds: 20)),
            now: now),
        'agora',
      );
      expect(
        formatApprovalInboxTime(now.subtract(const Duration(minutes: 12)),
            now: now),
        '12 min',
      );
      expect(formatApprovalInboxTime(DateTime(2026, 10, 3, 9, 5), now: now),
          '09:05');
      expect(formatApprovalInboxTime(DateTime(2026, 10, 2, 22), now: now),
          'ontem');
      expect(formatApprovalInboxTime(DateTime(2026, 7, 1), now: now), '01/07');
      expect(formatApprovalInboxTime(DateTime(2025, 12, 31), now: now),
          '31/12/25');
    });
  });

  group('filtros das solicitações de edição', () {
    test('rótulo do imóvel', () {
      expect(
        changeRequestPropertyLabel(
          const ChangeRequestPropertyRef(id: '1', title: 'Casa', code: 'C1'),
        ),
        'Casa (C1)',
      );
      expect(
        changeRequestPropertyLabel(
          const ChangeRequestPropertyRef(id: '1', title: ' ', code: 'C1'),
        ),
        'Cód. C1',
      );
      expect(
        changeRequestPropertyLabel(
          const ChangeRequestPropertyRef(id: '1', title: ''),
        ),
        'Imóvel',
      );
    });

    test('opções sem repetição e em ordem alfabética', () {
      final opts = changeRequestPropertyOptions(const [
        ChangeRequestPropertyRef(id: '2', title: 'beta'),
        ChangeRequestPropertyRef(id: '1', title: 'Alfa'),
        ChangeRequestPropertyRef(id: '2', title: 'beta'),
        ChangeRequestPropertyRef(id: ' ', title: 'vazio'),
      ]);
      expect(opts.map((e) => e.id), ['1', '2']);
    });
  });
}
