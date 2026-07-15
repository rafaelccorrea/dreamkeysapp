import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/visit_report_model.dart';
import '../services/visit_report_service.dart';

/// Abre o seletor de **clientes** (busca por nome/CPF em `GET /clients`).
/// Retorna `null` se o usuário fechar sem escolher.
Future<ClientPickOption?> showClientPicker(BuildContext context) {
  return showModalBottomSheet<ClientPickOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _EntityPickerSheet<ClientPickOption>(
      title: 'Selecionar cliente',
      hint: 'Buscar por nome ou CPF…',
      icon: LucideIcons.userRound,
      emptyText: 'Nenhum cliente encontrado.',
      search: (term) async {
        final res = await VisitReportService.instance.searchClients(term);
        return res.success ? (res.data ?? const []) : const [];
      },
      titleOf: (c) => c.name,
      subtitleOf: (c) =>
          (c.cpf ?? '').isNotEmpty ? 'CPF ${c.cpf}' : (c.phone ?? ''),
    ),
  );
}

/// Abre o seletor de **imóveis** (busca por nome/código/CEP em
/// `GET /properties`). Retorna `null` se o usuário fechar sem escolher.
Future<PropertyPickOption?> showPropertyPicker(BuildContext context) {
  return showModalBottomSheet<PropertyPickOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _EntityPickerSheet<PropertyPickOption>(
      title: 'Selecionar imóvel',
      hint: 'Buscar por nome, código ou CEP…',
      icon: LucideIcons.building2,
      emptyText: 'Nenhum imóvel encontrado.',
      search: (term) async {
        final res = await VisitReportService.instance.searchProperties(term);
        return res.success ? (res.data ?? const []) : const [];
      },
      titleOf: (p) => p.title.isNotEmpty ? p.title : p.address,
      subtitleOf: (p) {
        final bits = <String>[
          if ((p.code ?? '').isNotEmpty) 'CÓD ${p.code}',
          if (p.address.isNotEmpty && p.title.isNotEmpty) p.address,
        ];
        return bits.join(' · ');
      },
    ),
  );
}

/// Sheet genérico de busca + lista — mesma gramática dos modais do app
/// (grabber, header com glyph tonal, campo de busca flush, resultados).
class _EntityPickerSheet<T> extends StatefulWidget {
  final String title;
  final String hint;
  final IconData icon;
  final String emptyText;
  final Future<List<T>> Function(String term) search;
  final String Function(T) titleOf;
  final String Function(T) subtitleOf;

  const _EntityPickerSheet({
    required this.title,
    required this.hint,
    required this.icon,
    required this.emptyText,
    required this.search,
    required this.titleOf,
    required this.subtitleOf,
  });

  @override
  State<_EntityPickerSheet<T>> createState() => _EntityPickerSheetState<T>();
}

class _EntityPickerSheetState<T> extends State<_EntityPickerSheet<T>> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<T> _results = const [];
  bool _loading = true;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _run(String term) async {
    final seq = ++_requestSeq;
    setState(() => _loading = true);
    final results = await widget.search(term);
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _loading = false;
      _results = results;
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _run(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 10, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: ThemeHelpers.cardBackgroundColor(context),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.search, size: 17, color: secondary),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          onChanged: _onChanged,
                          cursorColor: accent,
                          style: TextStyle(
                            color: ThemeHelpers.textColor(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.hint,
                            hintStyle: TextStyle(
                              color: secondary.withValues(alpha: 0.75),
                              fontWeight: FontWeight.w500,
                              fontSize: 13.5,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_controller.text.isNotEmpty)
                        InkResponse(
                          radius: 16,
                          onTap: () {
                            _controller.clear();
                            _onChanged('');
                            setState(() {});
                          },
                          child:
                              Icon(LucideIcons.x, size: 15, color: secondary),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: accent),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.searchX,
                                      size: 30, color: secondary),
                                  const SizedBox(height: 10),
                                  Text(
                                    widget.emptyText,
                                    textAlign: TextAlign.center,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: secondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: EdgeInsets.fromLTRB(
                              20,
                              4,
                              20,
                              12 + MediaQuery.paddingOf(context).bottom,
                            ),
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final item = _results[i];
                              final subtitle = widget.subtitleOf(item);
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      Navigator.of(context).pop(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 4),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: ThemeHelpers.borderLightColor(
                                              context),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(widget.icon,
                                            size: 17,
                                            color: secondary.withValues(
                                                alpha: 0.8)),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.titleOf(item),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: ThemeHelpers
                                                      .textColor(context),
                                                ),
                                              ),
                                              if (subtitle.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  subtitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: secondary,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Icon(LucideIcons.chevronRight,
                                            size: 16, color: secondary),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
