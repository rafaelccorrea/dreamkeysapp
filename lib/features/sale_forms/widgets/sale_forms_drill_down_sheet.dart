import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../pages/sale_form_detail_page.dart';
import 'fichas_filters_kit.dart';

/// Lista de fichas de um recorte do painel — `FichasListDrawer` do web:
/// recorte fixo (sem filtros editáveis), 20 por página (aqui rolando),
/// ordenado pela criação. Tocar numa ficha abre o detalhe.
Future<void> showSaleFormsDrillDownSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required SaleFormFilters filters,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) =>
        _DrillDownSheet(title: title, subtitle: subtitle, filters: filters),
  );
}

class _DrillDownSheet extends StatefulWidget {
  const _DrillDownSheet({
    required this.title,
    required this.subtitle,
    required this.filters,
  });

  final String title;
  final String? subtitle;
  final SaleFormFilters filters;

  @override
  State<_DrillDownSheet> createState() => _DrillDownSheetState();
}

class _DrillDownSheetState extends State<_DrillDownSheet> {
  final List<SaleForm> _items = [];
  int _total = 0;
  int _page = 0;
  int _totalPages = 1;
  bool _loading = false;
  String? _error;
  int _seq = 0;

  static final NumberFormat _brl = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _total = 0;
      _page = 0;
      _totalPages = 1;
      _error = null;
    });
    await _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || _page >= _totalPages) return;
    final seq = ++_seq;
    setState(() => _loading = true);
    final res = await SaleFormsService.instance.list(
      filters: widget.filters.copyWith(page: _page + 1),
    );
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        final d = res.data!;
        _items.addAll(d.items);
        _total = d.total;
        _page = d.page;
        _totalPages = d.totalPages < 1 ? 1 : d.totalPages;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar as fichas deste recorte';
      }
    });
  }

  void _openDetail(SaleForm f) {
    if (f.id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SaleFormDetailPage(saleFormId: f.id),
      ),
    );
  }

  String _countLine() {
    if (_loading && _items.isEmpty) return 'Carregando fichas…';
    if (_total == 0) return 'Nenhuma ficha encontrada';
    return '$_total ficha${_total == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = FichasFilterTones.brand(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return FichasSheetShell(
      header: Container(
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(LucideIcons.receiptText, size: 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _countLine(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Recarregar',
              onPressed: _loading ? null : _reload,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
            ),
            IconButton(
              tooltip: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
      body: _body(context),
      footer: _footer(context),
    );
  }

  Widget _body(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    if (_loading && _items.isEmpty) {
      return ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: SkeletonBox(height: 74, borderRadius: 14),
            ),
        ],
      );
    }
    if (_items.isEmpty) {
      final err = _error != null;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              err ? LucideIcons.circleAlert : LucideIcons.receiptText,
              size: 30,
              color: secondary,
            ),
            const SizedBox(height: 10),
            Text(
              err ? 'Não foi possível carregar' : 'Nenhuma ficha neste recorte',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              err
                  ? _error!
                  : 'Não há fichas que correspondam ao item tocado no painel '
                        'para o período selecionado.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: secondary,
                height: 1.35,
              ),
            ),
            if (err) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(LucideIcons.refreshCw, size: 15),
                label: const Text('Tentar de novo'),
              ),
            ],
          ],
        ),
      );
    }
    final hasMore = _page < _totalPages;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (hasMore &&
            !_loading &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 120) {
          _loadNext();
        }
        return false;
      },
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: _items.length + (hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _loadNext,
                        child: const Text('Carregar mais'),
                      ),
              ),
            );
          }
          return _row(ctx, _items[i]);
        },
      ),
    );
  }

  Color _statusColor(SaleFormStatus s) {
    switch (s) {
      case SaleFormStatus.finalized:
        return const Color(0xFF10B981);
      case SaleFormStatus.waitingForSignature:
        return const Color(0xFFF59E0B);
      case SaleFormStatus.processing:
        return const Color(0xFF3B82F6);
      case SaleFormStatus.canceled:
        return const Color(0xFFEF4444);
    }
  }

  Widget _row(BuildContext context, SaleForm f) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final color = _statusColor(f.status);
    final buyer =
        f.buyerName ??
        f.sellerName ??
        (f.formNumber.isEmpty
            ? 'Ficha sem comprador'
            : 'Ficha ${f.formNumber}');
    final value = (f.saleValue ?? 0) > 0
        ? _brl.format(f.saleValue)
        : 'Sem valor';
    final created = f.createdAt == null
        ? null
        : DateFormat('dd/MM/yyyy').format(f.createdAt!.toLocal());
    final meta = [value, ?created, ?f.creatorName].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _openDetail(f),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ThemeHelpers.borderLightColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${f.formNumber.isEmpty ? '—' : f.formNumber}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: secondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                f.statusLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        buyer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final mq = MediaQuery.of(context);
    final accent = FichasFilterTones.brand(context);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + mq.padding.bottom),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            _total == 0 ? '0 de 0' : '${_items.length} de $_total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.pushNamed(AppRoutes.saleForms);
            },
            icon: Icon(LucideIcons.externalLink, size: 15, color: accent),
            label: Text(
              'Abrir lista completa',
              style: TextStyle(fontWeight: FontWeight.w800, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}
