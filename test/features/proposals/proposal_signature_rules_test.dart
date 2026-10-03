import 'package:Intellisys/features/proposals/utils/proposal_signature_rules.dart';
import 'package:Intellisys/shared/services/autentique_status_service.dart';
import 'package:Intellisys/shared/services/purchase_proposals_service.dart';
import 'package:flutter_test/flutter_test.dart';

ProposalSignature _sig(String status) =>
    ProposalSignature(id: 's', etapa: 1, status: status);

void main() {
  group('P10 — rótulo do status da assinatura (web statusLabel)', () {
    test('mesmos rótulos do web', () {
      expect(_sig('signed').statusLabel, 'Assinado');
      expect(_sig('rejected').statusLabel, 'Rejeitado');
      expect(_sig('viewed').statusLabel, 'Visualizado');
      expect(_sig('approved').statusLabel, 'Aprovado');
      expect(_sig('pending').statusLabel, 'Pendente');
      expect(_sig('qualquer').statusLabel, 'Pendente');
      expect(_sig('cancelled').statusLabel, 'Cancelado');
    });
  });

  group('P7 — mensagem de etapa liberada (próxima etapa, como o web)', () {
    test('aprovação do gestor', () {
      expect(proposalAnexoAprovadoMsg(1), 'Anexo aprovado. Etapa 2 liberada.');
      expect(proposalAnexoAprovadoMsg(2), 'Anexo aprovado. Etapa 3 liberada.');
      expect(proposalAnexoAprovadoMsg(3), 'Anexo aprovado. Etapa liberada.');
    });

    test('upload já aprovado', () {
      expect(
        proposalAnexoAprovadoMsg(1, noUpload: true),
        'Anexo enviado e aprovado. Etapa 2 liberada.',
      );
      expect(
        proposalAnexoAprovadoMsg(3, noUpload: true),
        'Anexo enviado e aprovado.',
      );
    });
  });

  group('P3 — reenvio pelo WhatsApp', () {
    test('disponibilidade lida do back (com ou sem envelope data)', () {
      final a = ProposalWhatsappEnvio.fromJson({
        'autoSendEnabled': true,
        'sessionKind': 'unofficial',
        'canResend': true,
      });
      expect(a.canResend, isTrue);
      expect(a.sessionKind, 'unofficial');
      final b = ProposalWhatsappEnvio.fromJson({
        'data': {'autoSendEnabled': true, 'sessionKind': null, 'canResend': false},
      });
      expect(b.canResend, isFalse);
      expect(b.sessionKind, isNull);
    });

    test('resumo só diz "enviado" quando algo saiu', () {
      expect(proposalWhatsappResumo({'sent': 0, 'skippedNoPhone': 0, 'failed': 0}),
          'Nenhuma mensagem enviada.');
      expect(proposalWhatsappResumo({'sent': 0, 'skippedNoPhone': 1}),
          '1 sem telefone');
      expect(proposalWhatsappResumo({'sent': 1}), '1 enviado(s) pelo WhatsApp');
      expect(proposalWhatsappResumo(null), 'Nenhuma mensagem enviada.');
    });
  });

  group('P6 — nova tentativa em 409 DUPLICATE_ENTRY', () {
    test('só em 409 com errorCode DUPLICATE_ENTRY', () {
      expect(
        proposalCreateShouldRetry(false, 409, {'errorCode': 'DUPLICATE_ENTRY'}),
        isTrue,
      );
      expect(
        proposalCreateShouldRetry(
            false, 409, '{"errorCode":"DUPLICATE_ENTRY","message":"x"}'),
        isTrue,
      );
      expect(proposalCreateShouldRetry(false, 409, {'errorCode': 'OUTRO'}),
          isFalse);
      expect(
        proposalCreateShouldRetry(false, 400, {'errorCode': 'DUPLICATE_ENTRY'}),
        isFalse,
      );
      expect(proposalCreateShouldRetry(true, 409, null), isFalse);
      expect(proposalCreateShouldRetry(false, 409, 'texto'), isFalse);
    });
  });

  group('P5 — Autentique inativa trava o envio (useAutentiqueStatus)', () {
    test('bloqueia só quando o back diz inativa', () {
      expect(autentiqueBlockedFrom({'active': false}), isTrue);
      expect(autentiqueBlockedFrom({'active': true}), isFalse);
      expect(autentiqueBlockedFrom({'data': {'active': false}}), isTrue);
      // Falha / sem resposta não bloqueia (igual ao web).
      expect(autentiqueBlockedFrom(null), isFalse);
    });
  });

  group('P8 — PDF + assinado', () {
    test('há assinado quando alguma assinatura está signed', () {
      expect(proposalTemAssinado(['pending', 'SIGNED']), isTrue);
      expect(proposalTemAssinado(['pending', 'viewed']), isFalse);
      expect(proposalTemAssinado(const []), isFalse);
    });
  });
}
