import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

class PdRankingTab {
  final String label;
  final List<ProposalsRankingItem> items;
  final bool showAvatar;

  const PdRankingTab(this.label, this.items, {this.showAvatar = false});
}

/// Rankings comerciais (ranqueados por valor finalizado). Abas com
/// sublinhado; mostra os 5 primeiros e abre o restante no próprio lugar.
class PdRankingBoard extends StatefulWidget {
  const PdRankingBoard({super.key, required this.tabs});

  final List<PdRankingTab> tabs;

  @override
  State<PdRankingBoard> createState() => _PdRankingBoardState();
}

class _PdRankingBoardState extends State<PdRankingBoard> {
  static const int _collapsed = 5;
  int _tab = 0;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    if (widget.tabs.isEmpty) {
      return const PdEmptyLine('Sem dados de ranking no período.');
    }
    final tabIndex = _tab.clamp(0, widget.tabs.length - 1).toInt();
    final tab = widget.tabs[tabIndex];
    final items = tab.items;
    final shown = _expanded ? items : items.take(_collapsed).toList();
    final maxValor = items.fold<double>(0, (m, i) => math.max(m, i.valor));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                InkWell(
                  onTap: () => setState(() {
                    _tab = i;
                    _expanded = false;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    margin: const EdgeInsets.only(right: 18),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2.5,
                          color: i == tabIndex ? t.accent : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      widget.tabs[i].label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: i == tabIndex ? t.text : t.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const PdHairline(),
        if (items.isEmpty)
          const PdEmptyLine('Ninguém com propostas neste recorte.')
        else ...[
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const PdHairline(indent: 34),
            _row(context, t, i + 1, shown[i], maxValor, tab.showAvatar),
          ],
          if (items.length > _collapsed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: t.text,
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? 'Mostrar só os 5 primeiros'
                      : 'Ver todos os ${items.length}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _row(
    BuildContext context,
    PdTones t,
    int position,
    ProposalsRankingItem item,
    double maxValor,
    bool showAvatar,
  ) {
    final isTop = position == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$position',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: isTop ? t.accent : t.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (showAvatar) ...[
            _Avatar(label: item.label, url: item.avatar),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label.isEmpty ? 'Sem identificação' : item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isTop ? FontWeight.w800 : FontWeight.w700,
                    letterSpacing: -0.2,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 5),
                PdMeter(
                  fraction: maxValor == 0 ? 0 : item.valor / maxValor,
                  color: isTop ? t.accent : t.accent.withValues(alpha: 0.45),
                  height: 4,
                ),
                const SizedBox(height: 4),
                Text(
                  '${pdInt.format(item.finalizadas)}/${pdInt.format(item.total)} '
                  'finalizadas · ${pdPercent(item.taxaConversao)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                pdBrlCompact.format(item.valor),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: isTop ? t.accent : t.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, this.url});

  final String label;
  final String? url;

  String get _initials {
    final parts =
        label.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final a = parts.first[0];
    final b = parts.length > 1 ? parts.last[0] : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final u = url;
    return CircleAvatar(
      radius: 15,
      backgroundColor: ThemeHelpers.borderLightColor(context),
      foregroundImage:
          (u != null && u.startsWith('http')) ? NetworkImage(u) : null,
      onForegroundImageError:
          (u != null && u.startsWith('http')) ? (_, _) {} : null,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: t.muted,
        ),
      ),
    );
  }
}
