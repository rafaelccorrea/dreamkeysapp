import '../../../../shared/services/api_service.dart';
import '../../core/finance_api_client.dart';
import '../../core/finance_errors.dart';
import '../../core/finance_me.dart';
import '../models/drill_models.dart';
import '../models/meu_financeiro_models.dart';

/// Filtros da lista "por visão" (`/proximos`).
class ProximosQuery {
  final FinanceVisao visao;
  final int page;
  final int pageSize;
  final String? search;
  final String? status;
  final String? from;
  final String? to;
  final String? brokerId;

  const ProximosQuery({
    this.visao = FinanceVisao.aReceber,
    this.page = 1,
    this.pageSize = 6,
    this.search,
    this.status,
    this.from,
    this.to,
    this.brokerId,
  });

  Map<String, Object?> toQuery() => {
    'page': page,
    'pageSize': pageSize,
    'sortBy': visao.sortBy,
    'sortDir': visao.sortDir,
    'visao': visao.api,
    'search': search,
    'status': status,
    'from': from,
    'to': to,
    'brokerId': brokerId,
  };
}

/// Filtros de "Minhas vendas".
class VendasQuery {
  final int page;
  final int pageSize;
  final String? search;
  final VendaSituacao situacao;
  final String? brokerId;

  const VendasQuery({
    this.page = 1,
    this.pageSize = 8,
    this.search,
    this.situacao = VendaSituacao.todas,
    this.brokerId,
  });

  Map<String, Object?> toQuery() => {
    'page': page,
    'pageSize': pageSize,
    'search': search,
    'situacao': situacao.api,
    'brokerId': brokerId,
  };
}

/// Resultado de uma seção: dado OU erro (uma seção que falha não derruba as
/// outras).
class Section<T> {
  final T? data;
  final FinanceError? error;
  const Section.ok(this.data) : error = null;
  const Section.fail(this.error) : data = null;
  bool get ok => error == null;
}

/// Tudo o que o Meu Financeiro mostra na montagem.
class MeuFinanceiroSnapshot {
  final Section<BrokerDashboardSummary> summary;
  final Section<FinancePage<BrokerProximo>> proximos;
  final Section<FinancePage<BrokerVenda>> vendas;
  final Section<FinancePage<CommissionAdvance>> advances;
  final Section<FinancePage<RequestSummary>> requests;
  final Section<FinanceMe?> me;
  final Section<FinancePage<AssinaturaFicha>> assinaturas;
  final DateTime loadedAt;

  const MeuFinanceiroSnapshot({
    required this.summary,
    required this.proximos,
    required this.vendas,
    required this.advances,
    required this.requests,
    required this.me,
    this.assinaturas = const Section.ok(null),
    required this.loadedAt,
  });
}

/// Endpoints do Meu Financeiro (`MeuFinanceiroPage.tsx`). Saldo, status e
/// valor NUNCA em cache — cada abertura/atualização vai ao back.
class MeuFinanceiroService {
  MeuFinanceiroService({
    FinanceApiClient? client,
    Future<ApiResponse<FinanceMe?>> Function()? meLoader,
  }) : _clientOverride = client,
       _meLoader = meLoader;

  static final MeuFinanceiroService instance = MeuFinanceiroService();

  final FinanceApiClient? _clientOverride;
  final Future<ApiResponse<FinanceMe?>> Function()? _meLoader;

  FinanceApiClient get _client => _clientOverride ?? FinanceApiClient.instance;

  Future<Section<BrokerDashboardSummary>> summary({String? brokerId}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/repasses/broker-dashboard',
      query: {'brokerId': brokerId},
    );
    if (res.success && res.data != null) {
      return Section.ok(BrokerDashboardSummary.fromJson(res.data!));
    }
    return Section.fail(res.financeError);
  }

  Future<Section<FinancePage<BrokerProximo>>> proximos(ProximosQuery q) async {
    final res = await _client.get<dynamic>(
      '/repasses/broker-dashboard/proximos',
      query: q.toQuery(),
    );
    if (res.success) {
      return Section.ok(FinancePage.parse(res.data, BrokerProximo.fromJson));
    }
    return Section.fail(res.financeError);
  }

  Future<Section<FinancePage<BrokerVenda>>> vendas(VendasQuery q) async {
    final res = await _client.get<dynamic>(
      '/repasses/broker-dashboard/vendas',
      query: q.toQuery(),
    );
    if (res.success) {
      return Section.ok(FinancePage.parse(res.data, BrokerVenda.fromJson));
    }
    return Section.fail(res.financeError);
  }

  Future<Section<FinancePage<CommissionAdvance>>> advances({
    int page = 1,
    int pageSize = 5,
    String? brokerId,
    String? search,
  }) async {
    final res = await _client.get<dynamic>(
      '/commission-advances',
      query: {
        'page': page,
        'pageSize': pageSize,
        'brokerId': brokerId,
        'search': search,
      },
    );
    if (res.success) {
      return Section.ok(
        FinancePage.parse(res.data, CommissionAdvance.fromJson),
      );
    }
    return Section.fail(res.financeError);
  }

  Future<Section<FinancePage<RequestSummary>>> requests({
    int page = 1,
    int pageSize = 5,
  }) async {
    final res = await _client.get<dynamic>(
      '/requests',
      query: {'page': page, 'pageSize': pageSize},
    );
    if (res.success) {
      return Section.ok(FinancePage.parse(res.data, RequestSummary.fromJson));
    }
    return Section.fail(res.financeError);
  }

  /// Fichas aguardando a assinatura do corretor (`/assinaturas`, pageSize 5).
  Future<Section<FinancePage<AssinaturaFicha>>> assinaturas({
    int page = 1,
    int pageSize = 5,
    String? brokerId,
  }) async {
    final res = await _client.get<dynamic>(
      '/repasses/broker-dashboard/assinaturas',
      query: {'page': page, 'pageSize': pageSize, 'brokerId': brokerId},
    );
    if (res.success) {
      return Section.ok(FinancePage.parse(res.data, AssinaturaFicha.fromJson));
    }
    return Section.fail(res.financeError);
  }

  /// Consulta da venda (somente leitura) — tocar numa venda/repasse/ficha.
  Future<Section<VendaConsulta>> vendaConsulta(String saleId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/repasses/broker-dashboard/vendas/${Uri.encodeComponent(saleId)}',
    );
    if (res.success && res.data != null) {
      return Section.ok(VendaConsulta.fromJson(res.data!));
    }
    return Section.fail(res.financeError);
  }

  /// "De onde vem este repasse".
  Future<Section<RepasseOrigem>> origem(String repasseId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/repasses/${Uri.encodeComponent(repasseId)}/origem',
    );
    if (res.success && res.data != null) {
      return Section.ok(RepasseOrigem.fromJson(res.data!));
    }
    return Section.fail(res.financeError);
  }

  Future<Section<FinanceMe?>> me() async {
    final res = await (_meLoader ?? FinanceMeService.instance.load)();
    if (res.success) return Section.ok(res.data);
    return Section.fail(res.financeError);
  }

  /// Montagem: TUDO EM PARALELO, sem cascata (regra de ouro de latência —
  /// o tempo até o primeiro dado é o da chamada mais lenta, não a soma).
  /// `/requests` vai junto mesmo antes de saber se a tela é liberada: quem
  /// decide mostrar é a página, com o `/auth/me` que chega no mesmo lote.
  Future<MeuFinanceiroSnapshot> loadAll({
    required ProximosQuery proximosQuery,
    required VendasQuery vendasQuery,
    String? brokerId,
  }) async {
    final results = await Future.wait<Object>([
      summary(brokerId: brokerId),
      proximos(proximosQuery),
      vendas(vendasQuery),
      advances(brokerId: brokerId),
      requests(),
      me(),
      // Em paralelo (sem esperar o resumo dizer que há fichas): a seção só
      // aparece com `aguardandoAssinatura.count > 0`.
      assinaturas(brokerId: brokerId),
    ]);
    return MeuFinanceiroSnapshot(
      summary: results[0] as Section<BrokerDashboardSummary>,
      proximos: results[1] as Section<FinancePage<BrokerProximo>>,
      vendas: results[2] as Section<FinancePage<BrokerVenda>>,
      advances: results[3] as Section<FinancePage<CommissionAdvance>>,
      requests: results[4] as Section<FinancePage<RequestSummary>>,
      me: results[5] as Section<FinanceMe?>,
      assinaturas: results[6] as Section<FinancePage<AssinaturaFicha>>,
      loadedAt: DateTime.now(),
    );
  }
}
