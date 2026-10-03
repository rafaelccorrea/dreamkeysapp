/// Status da integração Autentique da empresa — espelho do
/// `useAutentiqueStatus` do web: bloqueia os botões de "enviar para
/// assinatura" quando a integração não está ativa.
///
/// Regra do web: enquanto carrega OU se a consulta falhar, NÃO bloqueia
/// (`blocked = !loading && status != null && !active`) — só bloqueia quando
/// o back respondeu e disse que está inativa.
library;

import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Texto do web (`AUTENTIQUE_INACTIVE_MESSAGE`).
const String kAutentiqueInactiveMessage =
    'Integração Autentique não está ativa para esta empresa. Um gestor '
    'precisa configurar a API key em Integrações → Autentique para liberar '
    'o envio para assinatura.';

/// `true` = bloquear o envio. [raw] nulo (falha / sem resposta) não bloqueia.
bool autentiqueBlockedFrom(Map<String, dynamic>? raw) {
  if (raw == null) return false;
  final inner = raw['data'] is Map
      ? Map<String, dynamic>.from(raw['data'] as Map)
      : raw;
  final a = inner['active'];
  final active = a == true || a == 1 || a?.toString().toLowerCase() == 'true';
  return !active;
}

class AutentiqueStatusService {
  AutentiqueStatusService._();
  static final AutentiqueStatusService instance = AutentiqueStatusService._();

  static const String _endpoint = '/integrations/autentique/status';

  /// `GET /integrations/autentique/status` (qualquer usuário autenticado; o
  /// `x-company-id` vai no header). Falha → `false` (não bloqueia).
  Future<bool> isBlocked() async {
    try {
      final res = await ApiService.instance.get<Map<String, dynamic>>(_endpoint);
      if (!res.success || res.data == null) return false;
      return autentiqueBlockedFrom(res.data);
    } catch (e) {
      debugPrint('[AUTENTIQUE] status: $e');
      return false;
    }
  }
}
