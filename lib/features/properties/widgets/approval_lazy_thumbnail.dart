import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';

/// Cache in-memory simples (URL por propertyId) para evitar N requisições
/// repetidas quando a fila for re-renderizada. Como o backend não devolve
/// `images`/`mainImage` nos endpoints da fila, resolvemos a foto via
/// `GET /properties/:id` sob demanda (paridade visual com a tela de
/// detalhes do imóvel).
class _ThumbnailCache {
  static final Map<String, _CacheEntry> _entries = {};

  static _CacheEntry get(String id) =>
      _entries.putIfAbsent(id, () => _CacheEntry());

  static void put(String id, String? url) {
    final entry = get(id);
    entry.url = url;
    entry.resolved = true;
    entry.notify();
  }
}

class _CacheEntry extends ChangeNotifier {
  String? url;
  bool resolved = false;
  bool fetching = false;

  void notify() => notifyListeners();
}

/// Thumbnail com **lazy fetch**:
///   1. Se [initialUrl] não for nulo → usa direto (sem rede).
///   2. Senão consulta cache em memória; se já resolvido → usa.
///   3. Senão dispara `getPropertyById(id)` UMA VEZ e atualiza o cache.
///
/// Mostra um placeholder neutro (no estilo `_buildSummaryCard` do
/// dashboard — fundo `borderLightColor` com ícone `home`) durante a
/// resolução; cai num `imageOff` se não houver foto cadastrada.
class ApprovalLazyThumbnail extends StatefulWidget {
  final String propertyId;
  final String? initialUrl;
  final double size;
  final double radius;

  const ApprovalLazyThumbnail({
    super.key,
    required this.propertyId,
    this.initialUrl,
    this.size = 84,
    this.radius = 14,
  });

  @override
  State<ApprovalLazyThumbnail> createState() => _ApprovalLazyThumbnailState();
}

class _ApprovalLazyThumbnailState extends State<ApprovalLazyThumbnail> {
  late final _CacheEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = _ThumbnailCache.get(widget.propertyId);

    // Se já temos URL inicial, popula o cache (atalho).
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      if (!_entry.resolved) {
        _entry.url = widget.initialUrl;
        _entry.resolved = true;
      }
    }

    // Listener pra atualizar quando o cache resolve.
    _entry.addListener(_onCacheChange);

    // Dispara fetch lazy (não bloqueia o build).
    if (!_entry.resolved && !_entry.fetching) {
      _entry.fetching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchImage());
    }
  }

  @override
  void dispose() {
    _entry.removeListener(_onCacheChange);
    super.dispose();
  }

  void _onCacheChange() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchImage() async {
    try {
      final res =
          await PropertyService.instance.getPropertyById(widget.propertyId);
      if (!mounted) return;
      if (res.success && res.data != null) {
        final p = res.data!;
        final url = p.mainImage?.thumbnailUrl ??
            p.mainImage?.url ??
            (p.images != null && p.images!.isNotEmpty
                ? (p.images!.first.thumbnailUrl ?? p.images!.first.url)
                : null);
        _ThumbnailCache.put(widget.propertyId, url);
      } else {
        _ThumbnailCache.put(widget.propertyId, null);
      }
    } catch (_) {
      _ThumbnailCache.put(widget.propertyId, null);
    } finally {
      _entry.fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);

    final url = _entry.url;
    final resolved = _entry.resolved;

    Widget child;
    if (!resolved) {
      child = _ShimmerPlaceholder(
        baseColor: ThemeHelpers.borderLightColor(context),
        highlightColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.55),
      );
    } else if (url != null && url.isNotEmpty) {
      child = Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _ShimmerPlaceholder(
            baseColor: ThemeHelpers.borderLightColor(context),
            highlightColor: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.55),
          );
        },
        errorBuilder: (context, error, stack) => _IconPlaceholder(
          icon: LucideIcons.imageOff,
          color: neutral,
        ),
      );
    } else {
      child = _IconPlaceholder(icon: LucideIcons.home, color: neutral);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ThemeHelpers.borderLightColor(context).withValues(
              alpha: 0.35,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IconPlaceholder extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconPlaceholder({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(child: Icon(icon, size: 26, color: color));
  }
}

class _ShimmerPlaceholder extends StatefulWidget {
  final Color baseColor;
  final Color highlightColor;

  const _ShimmerPlaceholder({
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(_ctrl.value * 2 - 1, 0),
              end: Alignment(_ctrl.value * 2, 0),
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
            ),
          ),
        );
      },
    );
  }
}
