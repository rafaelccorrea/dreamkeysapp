import 'package:Intellisys/features/proposals/utils/proposal_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// P2 — rascunho local da proposta (espelho de `isBlankProposalDraft` e do
/// `getInitialState` do web).
void main() {
  group('proposalDraftIsBlank', () {
    test('formulário inicial (validade 5, entrega 30, nacionalidade) é branco',
        () {
      expect(
        proposalDraftIsBlank({
          'validityDays': '5',
          'deliveryDays': '30',
          'buyerNationality': 'Brasileiro(a)',
          'ownerNationality': 'Brasileiro(a)',
          'buyerName': '',
          'proposalDate': '',
        }),
        isTrue,
      );
    });

    test('só a equipe escolhida continua em branco (web ignora teamId)', () {
      expect(proposalDraftIsBlank({'teamId': 't-1', 'buyerName': ''}), isTrue);
    });

    test('qualquer campo preenchido deixa de ser branco', () {
      expect(proposalDraftIsBlank({'buyerName': 'Ana'}), isFalse);
      expect(proposalDraftIsBlank({'validityDays': '10'}), isFalse);
      expect(proposalDraftIsBlank({'proposalDate': '2026-10-03'}), isFalse);
    });

    test('usuário vinculado conta como preenchimento', () {
      expect(
        proposalDraftIsBlank({'buyerName': ''}, linkedUserIds: const ['u1']),
        isFalse,
      );
    });
  });

  group('encode/decode', () {
    test('ida e volta preserva campos, aba e vinculados', () {
      final json = proposalDraftEncode(
        campos: {'buyerName': 'Ana', 'proposalDate': '2026-10-01'},
        tab: 2,
        linkedUserIds: const ['u1', 'u2'],
      );
      final d = proposalDraftDecode(json);
      expect(d.campo('buyerName'), 'Ana');
      expect(d.data('proposalDate'), DateTime(2026, 10, 1));
      expect(d.tab, 2);
      expect(d.linkedUserIds, ['u1', 'u2']);
    });

    test('campo ausente volta com o valor inicial do formulário', () {
      final d = proposalDraftDecode({'campos': <String, dynamic>{}});
      expect(d.campo('validityDays'), '5');
      expect(d.campo('deliveryDays'), '30');
      expect(d.campo('buyerNationality'), 'Brasileiro(a)');
      expect(d.campo('buyerName'), '');
    });

    test('JSON torto não quebra: aba inválida vira 0, lista vira vazia', () {
      final d = proposalDraftDecode({
        'campos': 'x',
        'tab': 9,
        'linkedUserIds': 'nao-lista',
      });
      expect(d.campos, isEmpty);
      expect(d.tab, 0);
      expect(d.linkedUserIds, isEmpty);
    });

    test('nascimento igual a hoje é descartado (sanitizeBirthDateValue)', () {
      final hoje = DateTime(2026, 10, 3);
      final d = proposalDraftDecode({
        'campos': {'buyerBirth': '2026-10-03', 'ownerBirth': '1980-05-02'},
      });
      expect(d.nascimento('buyerBirth', hoje: hoje), isNull);
      expect(d.nascimento('ownerBirth', hoje: hoje), DateTime(1980, 5, 2));
    });

    test('resumo do diálogo traz proponente e imóvel', () {
      expect(
        proposalDraftResumo({
          'campos': {'buyerName': 'Ana', 'propAddress': 'Rua A'},
        }),
        'Proponente: Ana · Imóvel: Rua A',
      );
      expect(proposalDraftResumo({'campos': <String, dynamic>{}}), '');
    });
  });
}
