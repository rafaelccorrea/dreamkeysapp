import 'package:flutter/foundation.dart';

import '../../../shared/services/api_service.dart';
import '../../../shared/services/purchase_proposals_service.dart';

/// Base das fichas de proposta (`purchaseProposalsApi.baseUrl` do web).
const String _kPropostasBase = '/sistema/fichas-proposta';

/// Sufixo do vínculo proposta → ficha de venda.
const String _kVincularFichaVenda = 'vincular-ficha-venda';

/// Web: `purchaseProposalsApi.list({ limit: 100, status: 'finalized' })`.
const int _kCandidatasLimit = 100;
const String _kCandidatasStatus = 'finalized';

/// "Preencher a partir de uma proposta" da ficha de venda — as três chamadas
/// que o web faz em `CreateSaleFormPage.tsx`:
///
///  - candidatas: propostas **finalizadas** que ainda **não** têm ficha de
///    venda vinculada (`SelectPropostaModal` filtra `!p.saleFormId`);
///  - detalhe completo da escolhida (`getById`) para o pré-preenchimento;
///  - vínculo depois de criar a ficha (`PATCH …/:id/vincular-ficha-venda`).
///
/// Nunca lança: toda falha volta como [ApiResponse.error].
class SaleFormProposalLinkService {
  SaleFormProposalLinkService._();
  static final SaleFormProposalLinkService instance =
      SaleFormProposalLinkService._();

  final ApiService _api = ApiService.instance;

  /// Propostas que podem originar uma ficha de venda. [search] vai para o
  /// back (o web não tem busca; aqui ela alcança além das 100 primeiras).
  Future<ApiResponse<List<PurchaseProposal>>> listarCandidatas({
    String? search,
  }) async {
    try {
      final qp = <String, String>{
        'page': '1',
        'limit': '$_kCandidatasLimit',
        'status': _kCandidatasStatus,
      };
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) qp['search'] = s;
      final res = await _api.get<dynamic>(
        _kPropostasBase,
        queryParameters: qp,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar propostas.',
          statusCode: res.statusCode,
        );
      }
      final root = res.data;
      final raw = root is Map ? root['data'] : root;
      if (raw is! List) {
        return ApiResponse.error(
          message: 'Formato de resposta inválido.',
          statusCode: res.statusCode,
        );
      }
      final itens = raw
          .whereType<Map>()
          .map((m) => PurchaseProposal.fromJson(Map<String, dynamic>.from(m)))
          .where((p) => p.id.isNotEmpty && !propostaJaVinculada(p))
          .toList();
      return ApiResponse.success(data: itens, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('[SALE_FORM_PROPOSAL] listarCandidatas: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Detalhe completo (`GET /sistema/fichas-proposta/:id`).
  Future<ApiResponse<PurchaseProposal>> carregar(String id) async {
    try {
      final res = await _api.get<dynamic>('$_kPropostasBase/$id');
      final data = res.data;
      if (!res.success || data is! Map) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar proposta.',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(
        data: PurchaseProposal.fromJson(Map<String, dynamic>.from(data)),
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('[SALE_FORM_PROPOSAL] carregar: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// `PATCH /sistema/fichas-proposta/:id/vincular-ficha-venda`
  /// com `{ saleFormId }` (`null` desfaz o vínculo, como no web).
  Future<ApiResponse<void>> vincularFichaVenda(
    String proposalId,
    String? saleFormId,
  ) async {
    try {
      final res = await _api.patch<dynamic>(
        '$_kPropostasBase/$proposalId/$_kVincularFichaVenda',
        body: {'saleFormId': saleFormId},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Não foi possível vincular a proposta.',
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.success(statusCode: res.statusCode);
    } catch (e) {
      debugPrint('[SALE_FORM_PROPOSAL] vincularFichaVenda: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}

/// Web: `propostas.filter(p => !p.saleFormId)`. Também olha a relação
/// `saleForm` (quando o back a devolve populada) — mesmo significado.
bool propostaJaVinculada(PurchaseProposal p) {
  final sid = (p.raw['saleFormId'] ?? '').toString().trim();
  if (sid.isNotEmpty) return true;
  final sf = p.raw['saleForm'];
  return sf is Map && (sf['id'] ?? '').toString().trim().isNotEmpty;
}
