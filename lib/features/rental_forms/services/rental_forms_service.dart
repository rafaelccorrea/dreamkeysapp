import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../models/rental_form_model.dart';

/// Service de Fichas de Locação — espelha `rentalApplicationFormsApi.ts`
/// (imobx-front). Em produção o web usa a MESMA base da API principal
/// (`VITE_RENTAL_API_URL` não é definido no `.env.production`, então
/// `RENTAL_API_BASE_URL` cai em `https://api.dreamkeys.com.br`) — logo o app
/// consome pelos mesmos endpoints via [ApiService].
class RentalFormsService {
  RentalFormsService._();
  static final RentalFormsService instance = RentalFormsService._();

  final ApiService _api = ApiService.instance;

  // Endpoints (constantes privadas — a fiação central pode promovê-las ao
  // `api_constants.dart` depois; ver manifest).
  static const String _base = '/sistema/fichas-locacao';
  static String _byId(String id) => '$_base/$id';
  static String _linkPublico(String id) => '$_base/$id/link-publico';
  static String _revogarLinkPublico(String id) =>
      '$_base/$id/revogar-link-publico';
  static String _assinaturaLink(String id) => '$_base/$id/assinatura-link';

  /// Origem do painel web em produção (deploy Hostinger com base `/sistema`).
  /// É onde vive a página pública `PublicFichaLocacaoPage`.
  static const String _publicWebBase = 'https://intellisysbr.com/sistema';

  /// URL pública para o cliente preencher a ficha — paridade com o
  /// `buildPublicUrl` do editor web.
  static String publicUrl(
    String token, {
    RentalPublicLinkType type = RentalPublicLinkType.completa,
  }) {
    final suffix = type == RentalPublicLinkType.completa
        ? ''
        : '?tipo=${Uri.encodeQueryComponent(type.apiValue)}';
    return '$_publicWebBase/ficha-locacao/${Uri.encodeComponent(token)}$suffix';
  }

  /// Link de assinatura inválido/interno (bug antigo do backend) — paridade
  /// com `isInvalidInternalSignatureUrl` do web. A assinatura válida é sempre
  /// externa (Autentique).
  static bool isInvalidSignatureUrl(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return true;
    return v.contains('/sistema/ficha-locacao/') ||
        v.contains('/sistema/ficha-locacao-assinar/') ||
        v.contains('https://https//') ||
        v.contains('https:https://');
  }

  /// `GET /sistema/fichas-locacao?page&limit&search` →
  /// `{ data, total, page, limit }`.
  Future<ApiResponse<RentalFormListResult>> list({
    int page = 1,
    int limit = 100,
    String? search,
  }) async {
    try {
      final qp = <String, String>{'page': '$page', 'limit': '$limit'};
      final s = search?.trim();
      if (s != null && s.isNotEmpty) qp['search'] = s;

      final res = await _api.get<Map<String, dynamic>>(
        _base,
        queryParameters: qp,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar fichas de locação',
          statusCode: res.statusCode,
        );
      }
      final root = res.data!;
      final raw = root['data'];
      if (raw is! List) {
        return ApiResponse.error(
          message: 'Formato de resposta inválido',
          statusCode: res.statusCode,
        );
      }
      final items = raw
          .whereType<Map>()
          .map((m) => RentalForm.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      return ApiResponse.success(
        data: RentalFormListResult(
          items: items,
          total: _int(root['total']) ?? items.length,
          page: _int(root['page']) ?? page,
          limit: _int(root['limit']) ?? limit,
        ),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [RENTAL_FORMS] list: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `POST /sistema/fichas-locacao` — cria a ficha (rascunho) e devolve o DTO.
  Future<ApiResponse<RentalForm>> create({
    String? title,
    Map<String, dynamic>? payload,
    List<String>? involvedUserIds,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (title != null && title.trim().isNotEmpty) body['title'] = title.trim();
      if (payload != null) body['payload'] = payload;
      if (involvedUserIds != null) body['involvedUserIds'] = involvedUserIds;

      final res = await _api.post<Map<String, dynamic>>(_base, body: body);
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao criar ficha de locação',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: RentalForm.fromJson(_unwrap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [RENTAL_FORMS] create: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `GET /sistema/fichas-locacao/:id`.
  Future<ApiResponse<RentalForm>> getById(String id) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(_byId(id));
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Ficha não encontrada ou sem permissão',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: RentalForm.fromJson(_unwrap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [RENTAL_FORMS] getById: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `PATCH /sistema/fichas-locacao/:id` — título, payload, status e/ou
  /// envolvidos. `status: pending` reabre uma ficha finalizada/aguardando.
  Future<ApiResponse<RentalForm>> update(
    String id, {
    String? title,
    Map<String, dynamic>? payload,
    RentalFormStatus? status,
    List<String>? involvedUserIds,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (payload != null) body['payload'] = payload;
      if (status != null) body['status'] = status.apiValue;
      if (involvedUserIds != null) body['involvedUserIds'] = involvedUserIds;

      final res =
          await _api.patch<Map<String, dynamic>>(_byId(id), body: body);
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao salvar ficha de locação',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: RentalForm.fromJson(_unwrap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [RENTAL_FORMS] update: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `DELETE /sistema/fichas-locacao/:id`.
  Future<ApiResponse<void>> deleteForm(String id) async {
    try {
      final res = await _api.delete(_byId(id));
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao excluir ficha de locação',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [RENTAL_FORMS] delete: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `POST /:id/link-publico {expirationDays}` → `{token, expiresAt}`.
  Future<ApiResponse<RentalPublicLink>> generatePublicLink(
    String id, {
    int expirationDays = 30,
  }) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        _linkPublico(id),
        body: {'expirationDays': expirationDays},
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Não foi possível gerar o link público',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: RentalPublicLink.fromJson(_unwrap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [RENTAL_FORMS] generatePublicLink: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `POST /:id/revogar-link-publico`.
  Future<ApiResponse<void>> revokePublicLink(String id) async {
    try {
      final res = await _api.post(_revogarLinkPublico(id));
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao revogar link público',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [RENTAL_FORMS] revokePublicLink: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `POST /:id/assinatura-link` — finaliza a ficha (status →
  /// `awaiting_signature`) e devolve o link de assinatura (Autentique).
  Future<ApiResponse<RentalSignatureLink>> generateSignatureLink(
    String id,
  ) async {
    try {
      final res =
          await _api.post<Map<String, dynamic>>(_assinaturaLink(id));
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message:
              res.message ?? 'Não foi possível gerar o link de assinatura',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: RentalSignatureLink.fromJson(_unwrap(res.data!)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [RENTAL_FORMS] generateSignatureLink: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Alguns endpoints do backend embrulham em `{ data: {...} }` — tolera ambos.
Map<String, dynamic> _unwrap(Map<String, dynamic> root) {
  final data = root['data'];
  if (data is Map && (data['id'] != null || data['token'] != null)) {
    return Map<String, dynamic>.from(data);
  }
  return root;
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
