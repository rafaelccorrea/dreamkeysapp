import '../../../shared/services/secure_storage_service.dart';
import '../meu_financeiro/services/meu_financeiro_service.dart';
import '../solicitacoes/models/request_models.dart';
import 'finance_api_client.dart';

/// Cadastros do Financeiro (empresas, categorias, centros de custo,
/// fornecedores, tipos de solicitação) com cache de 60 s por empresa.
/// CADASTRO, não valor — saldo/status/valor nunca passam por aqui.
class FinanceCadastros {
  FinanceCadastros({FinanceApiClient? client}) : _clientOverride = client;

  static final FinanceCadastros instance = FinanceCadastros();

  final FinanceApiClient? _clientOverride;
  FinanceApiClient get _client => _clientOverride ?? FinanceApiClient.instance;

  static const Duration ttl = Duration(seconds: 60);
  final Map<String, (DateTime, Object)> _cache = {};
  final Map<String, Future<Section<Object>>> _inFlight = {};

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  Future<Section<T>> _cached<T extends Object>(
    String path,
    Map<String, Object?>? query,
    T Function(dynamic) parse,
  ) async {
    final company = await SecureStorageService.instance.getCompanyId() ?? '';
    final key = '$company|$path|${query ?? ''}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < ttl) {
      return Section.ok(hit.$2 as T);
    }
    final fut = _inFlight[key] ??= () async {
      final res = await _client.get<dynamic>(path, query: query);
      if (res.success) {
        final v = parse(res.data);
        _cache[key] = (DateTime.now(), v);
        return Section<Object>.ok(v);
      }
      return Section<Object>.fail(res.financeError);
    }().whenComplete(() => _inFlight.remove(key));
    final r = await fut;
    return r.ok ? Section.ok(r.data as T) : Section.fail(r.error);
  }

  Future<Section<List<FinanceRef>>> companies() =>
      _cached('/companies', {'operational': 1}, FinanceRef.list);

  Future<Section<List<FinanceRef>>> categories() =>
      _cached('/requests/categories', null, FinanceRef.list);

  Future<Section<List<FinanceRef>>> costCenters() =>
      _cached('/financial/cost-centers', null, FinanceRef.list);

  Future<Section<List<FinanceRef>>> suppliers() =>
      _cached('/financial/suppliers', null, FinanceRef.list);

  Future<Section<RequestTiposCatalog>> tipos() => _cached(
    '/request-tipos',
    null,
    (d) => RequestTiposCatalog.fromJson(
      d is Map ? d.map((k, v) => MapEntry(k.toString(), v)) : const {},
    ),
  );

  /// Cartões da empresa (só quando o meio é cartão de crédito).
  Future<Section<List<FinanceRef>>> creditCards(String companyId) =>
      _cached('/financial/credit-cards', {'companyId': companyId}, (d) {
        return FinanceRef.list(d).map((c) {
          final last = c.raw['lastDigits']?.toString();
          return FinanceRef(
            c.id,
            last == null || last.isEmpty ? c.name : '${c.name} •••• $last',
            c.raw,
          );
        }).toList();
      });
}
