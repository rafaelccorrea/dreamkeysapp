import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import 'api_service.dart';

class SaleChecklistListItem {
  final String id;
  final String status;
  final String type;
  final String? notes;
  final int itemsCount;

  SaleChecklistListItem({
    required this.id,
    required this.status,
    required this.type,
    this.notes,
    required this.itemsCount,
  });

  factory SaleChecklistListItem.fromJson(Map<String, dynamic> j) {
    final items = j['items'];
    final n = items is List ? items.length : 0;
    return SaleChecklistListItem(
      id: j['id']?.toString() ?? '',
      status: j['status']?.toString() ?? '',
      type: j['type']?.toString() ?? '',
      notes: j['notes']?.toString(),
      itemsCount: n,
    );
  }
}

/// Checklists de venda/locação — `GET /sale-checklists`.
class SaleChecklistsService {
  SaleChecklistsService._();
  static final SaleChecklistsService instance = SaleChecklistsService._();
  final ApiService _api = ApiService.instance;

  Future<ApiResponse<List<SaleChecklistListItem>>> listChecklists({
    String? propertyId,
    String? clientId,
  }) async {
    try {
      final qp = <String, String>{};
      if (propertyId != null && propertyId.isNotEmpty) {
        qp['propertyId'] = propertyId;
      }
      if (clientId != null && clientId.isNotEmpty) {
        qp['clientId'] = clientId;
      }
      final res = await _api.get<List<dynamic>>(
        ApiConstants.saleChecklists,
        queryParameters: qp.isEmpty ? null : qp,
      );
      if (!res.success || res.data == null) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao listar checklists',
          statusCode: res.statusCode,
        );
      }
      final list = res.data!
          .map(
            (e) => SaleChecklistListItem.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      return ApiResponse.success(data: list, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('❌ [CHECKLISTS] $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }
}
