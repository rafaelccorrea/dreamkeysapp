/// Cache de estado em memória para preservar valores entre navegações curtas.
///
/// Quando o usuário sai de uma tela (ex.: troca de tab na bottom navigation)
/// e volta logo depois, queremos que filtros, termos de busca e demais
/// estados temporários sejam restaurados — sem precisar refazer tudo.
///
/// Esta cache:
///   • É um singleton in-memory (não persiste entre restarts do app).
///   • Suporta TTL opcional para expirar entradas antigas automaticamente.
///   • É genérica via `Map<String, dynamic>` indexado por chave.
///
/// Padrão de uso (numa página):
/// ```dart
/// final cache = ScreenStateCache.instance;
///
/// @override
/// void initState() {
///   super.initState();
///   final saved = cache.read<Map<String, dynamic>>('properties:list');
///   if (saved != null) {
///     _searchQuery = saved['search'] as String? ?? '';
///     _filters = saved['filters'] as PropertyFilters?;
///   }
/// }
///
/// void _persist() {
///   cache.save('properties:list', {
///     'search': _searchQuery,
///     'filters': _filters,
///   });
/// }
/// ```
class ScreenStateCache {
  ScreenStateCache._();
  static final ScreenStateCache instance = ScreenStateCache._();

  /// TTL padrão de uma entrada (10 minutos).
  /// Após esse tempo a entrada é descartada na próxima leitura.
  static const Duration defaultTtl = Duration(minutes: 10);

  final Map<String, _CacheEntry> _store = {};

  /// Salva um valor. Se `ttl` for nulo, usa o padrão.
  void save(String key, Object? value, {Duration? ttl}) {
    if (value == null) {
      _store.remove(key);
      return;
    }
    _store[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl ?? defaultTtl),
    );
  }

  /// Lê um valor. Retorna `null` se inexistente, expirado ou se o tipo não bater.
  T? read<T>(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    final dynamic value = entry.value;
    if (value is T) return value;
    return null;
  }

  /// Verifica se há valor válido sem ler.
  bool has(String key) {
    final entry = _store[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _store.remove(key);
      return false;
    }
    return true;
  }

  /// Remove uma entrada explicitamente (ex.: ao fazer logout ou limpar tudo).
  void clear(String key) => _store.remove(key);

  /// Remove todas as entradas (use ao trocar de empresa/usuário).
  void clearAll() => _store.clear();
}

class _CacheEntry {
  _CacheEntry({required this.value, required this.expiresAt});

  final Object value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
