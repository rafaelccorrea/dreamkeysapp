import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/widgets/skeleton_box.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Abre o seletor de imóvel em bottom-sheet (busca por título/código) e
/// devolve a [Property] escolhida — usado no formulário de locação e no
/// filtro do dashboard.
Future<Property?> showRentalPropertyPicker(BuildContext context) {
  return showModalBottomSheet<Property>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => const _RentalPropertyPickerSheet(),
  );
}

class _RentalPropertyPickerSheet extends StatefulWidget {
  const _RentalPropertyPickerSheet();

  @override
  State<_RentalPropertyPickerSheet> createState() =>
      _RentalPropertyPickerSheetState();
}

class _RentalPropertyPickerSheetState
    extends State<_RentalPropertyPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<Property> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final q = _searchController.text.trim();
    final res = await PropertyService.instance.getProperties(
      page: 1,
      limit: 30,
      filters: q.isEmpty ? null : PropertyFilters(search: q),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _items = res.data!.data;
      } else {
        _error = res.message ?? 'Erro ao carregar imóveis';
      }
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
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
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 4, 10, 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom:
                        BorderSide(color: ThemeHelpers.borderLightColor(context)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: isDark ? 0.20 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(LucideIcons.building2,
                          color: _accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selecionar imóvel',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Busque por título, código ou endereço',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: fieldFill,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: ThemeHelpers.borderLightColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.search, size: 17, color: secondary),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          autofocus: false,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textColor(context),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Código, título, endereço…',
                            hintStyle: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: secondary.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _load();
                            setState(() {});
                          },
                          child: Icon(Icons.close_rounded,
                              size: 18, color: secondary),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _buildBody(context, scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ScrollController scrollController) {
    if (_loading) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: List.generate(
          6,
          (_) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SkeletonBox(width: 44, height: 44, borderRadius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: double.infinity, height: 14),
                      SizedBox(height: 7),
                      SkeletonText(width: 140, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_error != null) {
      return _StateMessage(
        icon: LucideIcons.cloudOff,
        title: _error!,
        actionLabel: 'Tentar novamente',
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return _StateMessage(
        icon: LucideIcons.searchX,
        title: 'Nenhum imóvel encontrado',
        subtitle: _searchController.text.trim().isEmpty
            ? 'Cadastre um imóvel para vinculá-lo à locação.'
            : 'Nenhum resultado para "${_searchController.text.trim()}".',
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _items.length,
      itemBuilder: (context, index) => _buildItem(context, _items[index]),
    );
  }

  Widget _buildItem(BuildContext context, Property property) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final location = [
      if (property.neighborhood.trim().isNotEmpty) property.neighborhood.trim(),
      if (property.city.trim().isNotEmpty)
        property.state.trim().isNotEmpty
            ? '${property.city.trim()} - ${property.state.trim()}'
            : property.city.trim(),
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(property),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _accent.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(color: _accent.withValues(alpha: 0.28)),
                ),
                child: Icon(LucideIcons.house, color: _accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if ((property.code ?? '').trim().isNotEmpty)
                          'CÓD ${property.code!.trim()}',
                        if (location.isNotEmpty) location,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if ((property.rentPrice ?? 0) > 0) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money.format(property.rentPrice),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: emerald,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'aluguel',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StateMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34, color: secondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.4,
              ),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(LucideIcons.refreshCw, size: 15),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
