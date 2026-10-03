import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/property_list_signals_service.dart';
import '../utils/property_list_signals.dart';

/// Lembrete "Imóveis pendentes de atualização" — paridade com o
/// `StalePropertiesModal.tsx` do web: busca, faixas de urgência, seleção em
/// lote ("Adiar 7 dias"), "Atualizar" abre a ficha na aba Atualizações e
/// "Lembrar depois" esconde por 12h. Abra com [showStalePropertiesReminder].
Future<void> showStalePropertiesReminder(
  BuildContext context, {
  required List<StaleProperty> items,
  required void Function(String propertyId) onOpenUpdates,
}) async {
  if (items.isEmpty) return;
  final service = PropertyListSignalsService.instance;
  // O que sobrar na lista ao fechar vira "lembrar depois" (como o web).
  final remaining = List<StaleProperty>.of(items);
  String? openId;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _StalePropertiesSheet(
      remaining: remaining,
      onOpen: (p) async {
        await service.trackStale([p], StaleTrackingAction.openUpdate);
        remaining.removeWhere((x) => x.id == p.id);
        openId = p.id;
      },
      onSnooze: (list) async {
        await service.trackStale(list, StaleTrackingAction.snoozeWeek);
        final ids = list.map((p) => p.id).toSet();
        remaining.removeWhere((x) => ids.contains(x.id));
      },
    ),
  );
  await service.trackStale(remaining, StaleTrackingAction.remindLater);
  final id = openId;
  if (id != null) onOpenUpdates(id);
}

class _StalePropertiesSheet extends StatefulWidget {
  const _StalePropertiesSheet({
    required this.remaining,
    required this.onOpen,
    required this.onSnooze,
  });

  /// Lista viva (compartilhada com quem abriu o sheet).
  final List<StaleProperty> remaining;
  final Future<void> Function(StaleProperty) onOpen;
  final Future<void> Function(List<StaleProperty>) onSnooze;

  @override
  State<_StalePropertiesSheet> createState() => _StalePropertiesSheetState();
}

class _StalePropertiesSheetState extends State<_StalePropertiesSheet> {
  final TextEditingController _search = TextEditingController();
  StaleUrgency? _urgency;
  final Set<String> _selected = <String>{};
  final DateTime _now = DateTime.now();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Color _tone(StaleUrgency u, bool dark) {
    switch (u) {
      case StaleUrgency.critico:
        return AppColors.status.error;
      case StaleUrgency.alto:
        return AppColors.status.warning;
      case StaleUrgency.atencao:
        return AppColors.primary.primary;
    }
  }

  List<StaleProperty> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = widget.remaining.where((p) {
      if (_urgency != null &&
          StaleUrgency.of(p.daysSince(_now)) != _urgency) {
        return false;
      }
      if (q.isEmpty) return true;
      return [p.title, p.code ?? '', p.address, p.city ?? '']
          .any((s) => s.toLowerCase().contains(q));
    }).toList()
      // Mais antigos primeiro (padrão do web).
      ..sort((a, b) => (a.referenceAt ?? DateTime(0))
          .compareTo(b.referenceAt ?? DateTime(0)));
    return list;
  }

  Future<void> _snoozeSelected() async {
    final list =
        widget.remaining.where((p) => _selected.contains(p.id)).toList();
    if (list.isEmpty) return;
    await widget.onSnooze(list);
    if (!mounted) return;
    setState(_selected.clear);
    if (widget.remaining.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final visible = _visible;
    final total = widget.remaining.length;
    final counts = <StaleUrgency, int>{
      for (final u in StaleUrgency.values) u: 0,
    };
    for (final p in widget.remaining) {
      final u = StaleUrgency.of(p.daysSince(_now));
      counts[u] = counts[u]! + 1;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: secondary.withValues(alpha: 0.32),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Icon(LucideIcons.history, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Imóveis pendentes de atualização',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            total == 1
                                ? '1 imóvel seu está há mais de 14 dias sem atualização na ficha.'
                                : '$total imóveis seus estão há mais de 14 dias sem atualização na ficha.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    hintText: 'Buscar por título, código ou endereço',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _UrgencyChip(
                      label: 'Todos',
                      count: total,
                      tone: accent,
                      active: _urgency == null,
                      onTap: () => setState(() => _urgency = null),
                    ),
                    for (final u in StaleUrgency.values) ...[
                      const SizedBox(width: 8),
                      _UrgencyChip(
                        label: u.label,
                        count: counts[u]!,
                        tone: _tone(u, isDark),
                        active: _urgency == u,
                        onTap: counts[u] == 0
                            ? null
                            : () => setState(
                                  () => _urgency = _urgency == u ? null : u,
                                ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_selected.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selected.length == 1
                              ? '1 selecionado'
                              : '${_selected.length} selecionados',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _snoozeSelected,
                        icon: const Icon(LucideIcons.alarmClockOff, size: 16),
                        label: const Text('Adiar 7 dias'),
                      ),
                      TextButton(
                        onPressed: () => setState(_selected.clear),
                        child: const Text('Limpar'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Flexible(
                child: visible.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.searchX, color: secondary),
                            const SizedBox(height: 8),
                            Text(
                              'Nenhum imóvel encontrado',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ajuste a busca ou o filtro de tempo sem atualização.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: secondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final p = visible[i];
                          final days = p.daysSince(_now);
                          final tone = _tone(StaleUrgency.of(days), isDark);
                          final selected = _selected.contains(p.id);
                          final ref = p.referenceAt;
                          return _StaleRow(
                            property: p,
                            days: days,
                            tone: tone,
                            selected: selected,
                            lastRecord: ref == null
                                ? null
                                : DateFormat('dd/MM/yyyy')
                                    .format(ref.toLocal()),
                            onToggle: () => setState(() {
                              selected
                                  ? _selected.remove(p.id)
                                  : _selected.add(p.id);
                            }),
                            onUpdate: () async {
                              await widget.onOpen(p);
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Toque para selecionar e adiar vários de uma vez.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Lembrar depois'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrgencyChip extends StatelessWidget {
  const _UrgencyChip({
    required this.label,
    required this.count,
    required this.tone,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color tone;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? tone : ThemeHelpers.textSecondaryColor(context);
    return Opacity(
      opacity: onTap == null && !active ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? tone.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? tone : ThemeHelpers.borderColor(context),
              width: 1.2,
            ),
          ),
          child: Text(
            '$label  $count',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _StaleRow extends StatelessWidget {
  const _StaleRow({
    required this.property,
    required this.days,
    required this.tone,
    required this.selected,
    required this.lastRecord,
    required this.onToggle,
    required this.onUpdate,
  });

  final StaleProperty property;
  final int days;
  final Color tone;
  final bool selected;
  final String? lastRecord;
  final VoidCallback onToggle;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final address = property.address;
    return Material(
      color: selected ? accent.withValues(alpha: 0.06) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onToggle,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: selected ? accent : secondary,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                property.title.isEmpty
                                    ? 'Imóvel sem título'
                                    : property.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            if ((property.code ?? '').isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '#${property.code}',
                                style: TextStyle(
                                  color: secondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tone.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: tone.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                '$days ${days == 1 ? 'dia' : 'dias'} sem atualizar',
                                style: TextStyle(
                                  color: tone,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (lastRecord != null)
                              Text(
                                'Último registro: $lastRecord',
                                style: TextStyle(
                                  color: secondary,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: secondary, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: FilledButton(
                      onPressed: onUpdate,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Atualizar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
