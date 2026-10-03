import 'package:flutter/material.dart';

import '../services/property_owner_check_service.dart';
import 'property_duplicate_sheet.dart';

/// Portão "proprietário já cadastrado" — `runOwnerExistingGate` do web
/// (`CreatePropertyPage.tsx` ~4145): ao sair da etapa do Proprietário no
/// CADASTRO, consulta `POST /properties/owner-check` e, havendo imóveis do
/// mesmo CPF/CNPJ ou telefone, mostra a lista ("Voltar e revisar" /
/// "Continuar cadastro"). Quem decide seguir não é perguntado de novo para
/// os mesmos dados (chave nome|telefone|documento). Falha na checagem não
/// trava: avisa e segue, como o web.
class PropertyOwnerGate {
  PropertyOwnerGate({PropertyOwnerCheckService? service})
      : _service = service ?? PropertyOwnerCheckService.instance;

  final PropertyOwnerCheckService _service;
  String? _ackKey;
  bool _running = false;

  Future<bool> run(
    BuildContext context, {
    required String ownerName,
    required String ownerPhone,
    required String ownerDocument,
  }) async {
    if (_running) return false;
    final ackKey = buildOwnerAckKey(
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      ownerDocument: ownerDocument,
    );
    if (_ackKey == ackKey) return true;

    final payload = buildOwnerCheckPayload(
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      ownerDocument: ownerDocument,
    );
    if ((payload['ownerName'] as String).isEmpty ||
        (payload['ownerPhone'] as String).isEmpty) {
      return true;
    }

    _running = true;
    try {
      final res = await _service.check(payload);
      if (!context.mounted) return false;
      if (!res.success || res.data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Não foi possível verificar imóveis do proprietário. '
              'Você pode continuar o cadastro.',
            ),
          ),
        );
        return true;
      }
      if (!res.data!.hasExisting) return true;

      final seguir = await showPropertyOwnerExistingSheet(
        context: context,
        ownerName: payload['ownerName'] as String,
        matches: res.data!.properties,
      );
      if (!seguir) return false;
      _ackKey = ackKey;
      return true;
    } finally {
      _running = false;
    }
  }
}
