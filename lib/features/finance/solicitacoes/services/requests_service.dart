import 'dart:convert';

import '../../../../shared/services/api_service.dart';
import '../../core/finance_api_client.dart';
import '../../core/finance_config.dart';
import '../../core/finance_errors.dart';
import '../../meu_financeiro/models/meu_financeiro_models.dart';
import '../../meu_financeiro/services/meu_financeiro_service.dart';
import '../models/request_models.dart';
import '../models/request_rules.dart';

/// Filtros da lista "Minhas solicitações" (visão pessoal: sem `alvoTipo`).
class RequestsQuery {
  final int page;
  final int pageSize;
  final String? search;
  final String? status;
  final String? type;
  final String? from;
  final String? to;

  const RequestsQuery({
    this.page = 1,
    this.pageSize = 20,
    this.search,
    this.status,
    this.type,
    this.from,
    this.to,
  });

  Map<String, Object?> toQuery({bool paged = true}) => {
    if (paged) 'page': page,
    if (paged) 'pageSize': pageSize,
    'search': search,
    if (paged) 'status': status,
    'type': type,
    'from': from,
    'to': to,
  };
}

/// Desfecho do POST /requests.
sealed class CriacaoResultado {
  const CriacaoResultado();
}

class CriacaoOk extends CriacaoResultado {
  final FinanceRequest request;
  final String? avisoLancamento;

  /// Entrou, mas o app só soube ao reconferir (timeout/409).
  final bool reconciliada;
  const CriacaoOk(this.request, {this.avisoLancamento, this.reconciliada = false});
}

class CriacaoFalhou extends CriacaoResultado {
  final FinanceError error;
  const CriacaoFalhou(this.error);
}

/// Endpoints de Solicitações (`requests.controller.ts`). Valor/status nunca
/// em cache.
class RequestsService {
  RequestsService({FinanceApiClient? client}) : _clientOverride = client;

  static final RequestsService instance = RequestsService();

  final FinanceApiClient? _clientOverride;
  FinanceApiClient get _client => _clientOverride ?? FinanceApiClient.instance;

  Future<Section<FinancePage<FinanceRequest>>> list(RequestsQuery q) async {
    final res = await _client.get<dynamic>('/requests', query: q.toQuery());
    if (res.success) {
      return Section.ok(FinancePage.parse(res.data, FinanceRequest.fromJson));
    }
    return Section.fail(res.financeError);
  }

  /// O back ignora `status` aqui (`withStatus:false`).
  Future<Section<RequestsDashboard>> dashboard(RequestsQuery q) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requests/dashboard',
      query: q.toQuery(paged: false),
    );
    if (res.success && res.data != null) {
      return Section.ok(RequestsDashboard.fromJson(res.data!));
    }
    return Section.fail(res.financeError);
  }

  Future<Section<FinanceRequest>> detail(String id) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/requests/${Uri.encodeComponent(id)}',
    );
    if (res.success && res.data != null) {
      return Section.ok(FinanceRequest.fromJson(res.data!));
    }
    return Section.fail(res.financeError);
  }

  Future<FinanceError?> comment(String id, String body) async {
    final res = await _client.post<dynamic>(
      '/requests/${Uri.encodeComponent(id)}/comments',
      body: {'body': body.trim()},
    );
    return res.success ? null : res.financeError;
  }

  Future<FinanceError?> cancel(String id, {String? reason}) async {
    final r = (reason ?? '').trim();
    final res = await _client.patch<dynamic>(
      '/requests/${Uri.encodeComponent(id)}/cancel',
      body: r.isEmpty ? <String, dynamic>{} : {'reason': r},
    );
    return res.success ? null : res.financeError;
  }

  Future<ApiResponse<dynamic>> update(String id, Map<String, dynamic> body) =>
      _client.patch<dynamic>(
        '/requests/${Uri.encodeComponent(id)}',
        body: body,
        timeout: FinanceConfig.longTimeout,
      );

  /// POST /requests (120 s). Timeout ou 409 → reconfere a lista antes de
  /// dizer que falhou (`acharRecemCriada`).
  Future<CriacaoResultado> create(
    Map<String, dynamic> body, {
    DateTime Function()? clock,
  }) async {
    final res = await _client.post<dynamic>(
      '/requests',
      body: body,
      timeout: FinanceConfig.longTimeout,
    );
    if (res.success && res.data is Map) {
      final m = (res.data as Map).map((k, v) => MapEntry(k.toString(), v));
      final aviso = m['avisoLancamento'];
      return CriacaoOk(
        FinanceRequest.fromJson(m),
        avisoLancamento: aviso is String && aviso.trim().isNotEmpty
            ? aviso.trim()
            : (aviso is Map ? aviso['message']?.toString() : null),
      );
    }
    final err = res.financeError!;
    final conferir =
        err.code == 'TIMEOUT' ||
        err.statusCode == 409;
    if (!conferir) return CriacaoFalhou(err);
    final companyId = body['companyId']?.toString() ?? '';
    final lista = await _client.get<dynamic>(
      '/requests',
      query: {'companyId': companyId, 'page': 1, 'pageSize': 20},
    );
    if (lista.success) {
      final rows = FinancePage.parse(lista.data, FinanceRequest.fromJson).data;
      final achou = acharRecemCriada(
        rows,
        title: body['title']?.toString() ?? '',
        amount: (body['amountRequested'] as num?)?.toDouble() ?? 0,
        companyId: companyId,
        now: (clock ?? DateTime.now)(),
      );
      if (achou != null) return CriacaoOk(achou, reconciliada: true);
    }
    return CriacaoFalhou(err);
  }

  /// Envia UM anexo. Time financeiro (multipart 30 MB) → upload +
  /// vínculo; 403/404 cai no base64. Demais → base64 de 5 MB direto
  /// (`POST /requests/:id/attachments/upload`). Devolve `null` (ok) ou o
  /// motivo da falha (vira aviso, não erro).
  Future<String?> uploadAttachment(
    String requestId, {
    required String filename,
    required List<int> bytes,
    required String mimeType,
    required bool multipart,
  }) async {
    final rid = Uri.encodeComponent(requestId);
    if (multipart) {
      final up = await _client.postMultipart<dynamic>(
        '/financial/anexos/upload',
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
        fields: const {'contexto': 'request'},
      );
      if (up.success && up.data is Map) {
        final url = (up.data as Map)['url']?.toString();
        final nome = (up.data as Map)['nomeOriginal']?.toString() ?? filename;
        if (url != null && url.isNotEmpty) {
          final link = await _client.post<dynamic>(
            '/requests/$rid/attachments',
            body: {'name': nome, 'url': url},
          );
          return link.success
              ? null
              : 'Arquivo enviado, mas não vinculado à solicitação — tente '
                    'anexar de novo';
        }
      }
      final code = up.statusCode;
      if (code != 403 && code != 404) {
        return up.financeError?.message ?? 'Falha no envio.';
      }
    }
    if (bytes.length > 5 * 1024 * 1024) {
      return 'Anexos acima de 5 MB em solicitações dependem do perfil '
          'financeiro; reduza o arquivo.';
    }
    final res = await _client.post<dynamic>(
      '/requests/$rid/attachments/upload',
      body: {
        'filename': filename,
        'base64': base64Encode(bytes),
        'mimeType': mimeType,
      },
      timeout: FinanceConfig.uploadTimeout,
    );
    return res.success ? null : (res.financeError?.message ?? 'Falha no envio.');
  }

  Future<FinanceError?> removeAttachment(String requestId, String attId) async {
    final res = await _client.delete<dynamic>(
      '/requests/${Uri.encodeComponent(requestId)}/attachments/${Uri.encodeComponent(attId)}',
    );
    return res.success ? null : res.financeError;
  }
}
