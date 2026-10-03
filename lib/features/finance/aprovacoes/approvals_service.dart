import '../core/finance_api_client.dart';
import '../core/finance_config.dart';
import '../core/finance_errors.dart';
import '../core/finance_format.dart';
import '../meu_financeiro/models/meu_financeiro_models.dart';
import '../meu_financeiro/services/meu_financeiro_service.dart';
import 'approvals_models.dart';

/// Central de Aprovações — só a sub-aba "Meu aval" (`approvalsApi.ts`).
class ApprovalsService {
  ApprovalsService({FinanceApiClient? client}) : _clientOverride = client;

  static final ApprovalsService instance = ApprovalsService();

  final FinanceApiClient? _clientOverride;
  FinanceApiClient get _client => _clientOverride ?? FinanceApiClient.instance;

  /// Contagem do "Meu aval" (`porSituacao.MEU_AVAL`). Nunca em cache.
  Future<Section<int>> meuAvalCount() async {
    final res = await _client.get<Map<String, dynamic>>('/approvals/summary');
    if (res.success && res.data != null) {
      final s = res.data!['porSituacao'];
      final n = s is Map ? (s['MEU_AVAL'] as num?)?.toInt() : null;
      return Section.ok(n ?? 0);
    }
    return Section.fail(res.financeError);
  }

  Future<Section<FinancePage<ApprovalItem>>> queue({
    int page = 1,
    String? search,
  }) async {
    final res = await _client.get<dynamic>(
      '/approvals/queue',
      query: meuAvalQuery(page: page, search: search),
    );
    if (res.success) {
      return Section.ok(FinancePage.parse(res.data, ApprovalItem.fromJson));
    }
    return Section.fail(res.financeError);
  }

  Future<Section<ApprovalItemDetail>> item(String source, String id) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/approvals/item',
      query: {'source': source, 'id': id},
    );
    if (res.success && res.data != null) {
      return Section.ok(ApprovalItemDetail.fromJson(res.data!));
    }
    return Section.fail(res.financeError);
  }

  /// Aprovar/recusar em lote, em fatias de 10 (em sequência). Falha de
  /// uma fatia inteira marca cada item dela.
  Future<BulkResult> bulk({
    required bool approve,
    required List<({String source, String id, bool confirmarDuplicidade})> items,
    String? reason,
  }) async {
    var out = const BulkResult();
    for (final fatia in fatiasDoLote(items)) {
      final res = await _client.post<dynamic>(
        '/approvals/bulk',
        body: {
          'action': approve ? 'approve' : 'reprove',
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          'items': [
            for (final i in fatia)
              {
                'source': i.source,
                'id': i.id,
                if (i.confirmarDuplicidade) 'confirmarDuplicidade': true,
              },
          ],
        },
        timeout: FinanceConfig.longTimeout,
      );
      if (res.success) {
        out = out.merge(BulkResult.fromJson(res.data));
      } else {
        final e = res.financeError!;
        final msg = e.kind == FinanceErrorKind.conflict
            ? 'Já decidida por outra pessoa. Atualize a fila.'
            : e.message;
        out = out.merge(
          BulkResult(
            failed: [
              for (final i in fatia)
                BulkFailure(source: i.source, id: i.id, error: msg, code: e.code),
            ],
          ),
        );
      }
    }
    return out;
  }

  /// Dados do adiantamento e, com o `brokerId` dele, o saldo do corretor
  /// ignorando este pedido (o saldo depende do 1º — única cascata, como o
  /// modal do web).
  Future<({Map<String, dynamic>? advance, Map<String, dynamic>? balance, FinanceError? error})>
  advanceForApproval(String advanceId) async {
    final adv = await _client.get<Map<String, dynamic>>(
      '/commission-advances/${Uri.encodeComponent(advanceId)}',
    );
    if (!adv.success || adv.data == null) {
      return (advance: null, balance: null, error: adv.financeError);
    }
    final brokerId = adv.data!['brokerId']?.toString();
    Map<String, dynamic>? bal;
    if (brokerId != null && brokerId.isNotEmpty) {
      final b = await _client.get<Map<String, dynamic>>(
        '/commission-advances/broker-balance/${Uri.encodeComponent(brokerId)}',
        query: {'ignoreAdvanceId': advanceId},
      );
      if (b.success) bal = b.data;
    }
    return (advance: adv.data, balance: bal, error: null);
  }

  Future<FinanceError?> approveAdvance(
    String id, {
    required double feePercent,
    String? capOverrideReason,
  }) async {
    final r = (capOverrideReason ?? '').trim();
    final res = await _client.post<dynamic>(
      '/commission-advances/${Uri.encodeComponent(id)}/approve',
      body: {'feePercent': feePercent, if (r.isNotEmpty) 'capOverrideReason': r},
    );
    return res.success ? null : res.financeError;
  }
}

/// Leitura do saldo do corretor (`broker-balance`).
({double aReceber, double saldoLivre}) leSaldo(Map<String, dynamic>? b) => (
  aReceber: financeNum(b?['aReceber']),
  saldoLivre: financeNum(b?['saldoLivre']),
);
