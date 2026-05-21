import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/adaptive_page_route.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/kanban_models.dart';
import '../controllers/kanban_controller.dart';
import '../widgets/create_task_modal.dart';
import '../widgets/edit_task_modal.dart';
import '../widgets/edit_column_modal.dart';
import '../widgets/kanban_filters.dart';
import '../widgets/project_selector.dart';
import '../widgets/kanban_skeleton.dart';
import '../widgets/task_details_modal.dart';

final _compactIntFormatter = NumberFormat.decimalPattern('pt_BR');

// ScrollBehavior customizado para ocultar barras de rolagem
class NoScrollbarScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // Não renderiza a barra de rolagem
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // Não renderiza o indicador de overscroll
  }
}

/// Página principal do Kanban
class KanbanPage extends StatefulWidget {
  const KanbanPage({super.key});

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends State<KanbanPage> {
  static const double _kHeaderPadVTop = 10;
  static const double _kKanbanColumnGap = 8;
  static const double _kKanbanColumnRadius = 14;
  /// Coluna estreita demais prejudica legibilidade; abaixo disso liberamos scroll horizontal.
  static const double _kKanbanMinStretchColumnWidth = 220;
  static const double _kKanbanScrollColumnWidth = 300;

  final ScrollController _horizontalScrollController = ScrollController();

  double _kanbanScreenGutterH(BuildContext context) {
    final p = MediaQuery.paddingOf(context);
    return math.max(math.max(p.left, p.right), 8.0);
  }

  Timer? _autoScrollTimer;
  bool _isDragging = false;
  double _scrollSpeed = 0;

  @override
  void initState() {
    super.initState();
    // Não chamar notifyListeners durante o build do Consumer pai: adiar para o pós-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<KanbanController>();
      c.markKanbanEnteringIfNeeded();
      c.loadBoard();
    });
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_isDragging || !_horizontalScrollController.hasClients) {
        _stopAutoScroll();
        return;
      }
      _performAutoScroll();
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _updateAutoScroll(double dragX) {
    if (!_horizontalScrollController.hasClients) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final scrollPosition = _horizontalScrollController.position;
    final scrollOffset = scrollPosition.pixels;
    final scrollMax = scrollPosition.maxScrollExtent;

    // Zona de ativação do auto-scroll (100px das bordas para detectar melhor)
    const scrollZone = 100.0;
    double newScrollSpeed = 0;

    // Verificar se está próximo da borda esquerda ou parcialmente fora
    if (dragX < scrollZone) {
      if (scrollOffset > 0) {
        // Scroll para a esquerda (valores negativos)
        // Se está fora da tela (dragX < 0), usar velocidade máxima
        if (dragX < 0) {
          newScrollSpeed = -20; // Velocidade máxima quando fora da tela
        } else {
          // Velocidade proporcional à proximidade da borda
          newScrollSpeed = -((scrollZone - dragX) / scrollZone) * 20;
        }
      }
    }
    // Verificar se está próximo da borda direita ou parcialmente fora
    else if (dragX > screenWidth - scrollZone) {
      if (scrollOffset < scrollMax) {
        // Scroll para a direita (valores positivos)
        // Se está fora da tela (dragX > screenWidth), usar velocidade máxima
        if (dragX > screenWidth) {
          newScrollSpeed = 20; // Velocidade máxima quando fora da tela
        } else {
          // Velocidade proporcional à proximidade da borda
          newScrollSpeed =
              ((dragX - (screenWidth - scrollZone)) / scrollZone) * 20;
        }
      }
    }

    _scrollSpeed = newScrollSpeed;

    if (newScrollSpeed != 0 && _autoScrollTimer == null) {
      _startAutoScroll();
    } else if (newScrollSpeed == 0) {
      _stopAutoScroll();
    }
  }

  void _performAutoScroll() {
    if (!_horizontalScrollController.hasClients || _scrollSpeed == 0) {
      _stopAutoScroll();
      return;
    }

    final scrollPosition = _horizontalScrollController.position;
    final scrollOffset = scrollPosition.pixels;
    final scrollMax = scrollPosition.maxScrollExtent;

    double newOffset = scrollOffset + _scrollSpeed;

    // Limitar o scroll aos limites
    newOffset = newOffset.clamp(0.0, scrollMax);

    if (newOffset != scrollOffset) {
      _horizontalScrollController.jumpTo(newOffset);
    } else {
      // Se chegou ao limite, parar o scroll
      _stopAutoScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<KanbanController>(
      builder: (context, controller, _) {
        final theme = Theme.of(context);

        return AppScaffold(
          title: 'Funís • CRM',
          body: controller.shouldShowKanbanSkeleton
              ? const KanbanSkeleton()
              : controller.error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        controller.error!,
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => controller.loadBoard(),
                        child: const Text('Tentar Novamente'),
                      ),
                    ],
                  ),
                )
              : _buildKanbanBoard(controller),
        );
      },
    );
  }

  Widget _kanbanSecondaryLoadBanner(
    BuildContext context,
    KanbanController controller,
    double gutterH,
  ) {
    final theme = Theme.of(context);
    final accent = _kanbanAccentColor(context);
    final msg = 'Carregando funis disponíveis…';
    return Padding(
      padding: EdgeInsets.fromLTRB(gutterH, 6, gutterH, 2),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                height: 3,
                width: 40,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  msg,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.cloud_sync_rounded,
                size: 18,
                color: accent.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cabeçalho do quadro — pequeno meta (etapas/cards) + ações rápidas
  /// (criar, atualizar). Sem chips/pills acima do board.
  Widget _kanbanBoardChromeHeader(
    BuildContext context,
    KanbanController controller,
  ) {
    final theme = Theme.of(context);
    final accent = _kanbanAccentColor(context);
    final canCreateTask = controller.permissions?.canCreateTasks ?? true;
    final cols = controller.displayColumns;
    final totalTasks = controller.tasks.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: accent.withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.view_kanban_rounded, color: accent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'QUADRO',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                          color: accent,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${cols.length}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '· ${_compactIntFormatter.format(totalTasks)} cards',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Ações coladas na margem direita.
          _kanbanIconAction(
            context,
            icon: Icons.refresh_rounded,
            tooltip: 'Atualizar',
            onPressed: () => controller.loadBoard(),
          ),
          if (canCreateTask) ...[
            const SizedBox(width: 8),
            _kanbanCreateButton(
              context,
              onPressed: () =>
                  _openHeroCreateNegotiationModal(context, controller),
            ),
          ],
        ],
      ),
    );
  }

  /// Botão de ação só com ícone (usado pro "Atualizar" no header do quadro).
  /// Versão premium: chip arredondado tintado com a cor do funil e borda fina.
  Widget _kanbanIconAction(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    final accent = _kanbanAccentColor(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        splashColor: accent.withValues(alpha: 0.16),
        highlightColor: accent.withValues(alpha: 0.08),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 19, color: accent),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }

  /// Botão "Criar" — versão premium com gradient diagonal, glow colorido
  /// e tipografia em peso forte. Substitui o antigo `_kanbanQuickAction`
  /// (que era genérico) por algo desenhado pra ser o CTA da tela.
  Widget _kanbanCreateButton(
    BuildContext context, {
    required VoidCallback onPressed,
  }) {
    final accent = _kanbanAccentColor(context);
    final theme = Theme.of(context);
    final accentDeep = HSLColor.fromColor(accent)
        .withLightness(
          (HSLColor.fromColor(accent).lightness * 0.78).clamp(0.0, 1.0),
        )
        .toColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withValues(alpha: 0.18),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent, accentDeep],
            ),
            border: Border.all(
              color: accentDeep.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 7),
                Text(
                  'Criar',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1.1,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKanbanBoard(KanbanController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final compact = w < 360;
        final gutterH = _kanbanScreenGutterH(context);
        final bottomInset = MediaQuery.paddingOf(context).bottom + 8;

        final viewportH = MediaQuery.sizeOf(context).height;
        final bodyMaxH =
            constraints.hasBoundedHeight ? constraints.maxHeight : viewportH;
        final boardViewportH = math
            .max(bodyMaxH * 0.78, viewportH * 0.62)
            .clamp(400.0, 860.0)
            .toDouble();

        final bulkDockOverlap =
            controller.bulkSelectionActive ? 108.0 : 0.0;

        return ScrollConfiguration(
          behavior: NoScrollbarScrollBehavior(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (controller.loadingProjects && controller.board != null)
                    SliverToBoxAdapter(
                      child: _kanbanSecondaryLoadBanner(
                        context,
                        controller,
                        gutterH,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _buildKanbanHero(
                      context,
                      controller,
                      gutterH,
                      compact,
                      w,
                      toolsContinuation:
                          _kanbanToolsContinuation(context, controller),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: compact ? 16 : 22),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutterH,
                        0,
                        gutterH,
                        bottomInset + bulkDockOverlap,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _kanbanBoardChromeHeader(context, controller),
                          SizedBox(
                            height: boardViewportH,
                            child: ClipRect(
                              child: LayoutBuilder(
                                builder: (context, inner) {
                                  return _buildKanbanHorizontalScroll(
                                    context,
                                    controller,
                                    inner.maxWidth,
                                    boardViewportH,
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (controller.bulkSelectionActive)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBulkSelectionDock(context, controller),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKanbanHorizontalScroll(
    BuildContext context,
    KanbanController controller,
    double viewportWidth,
    double height,
  ) {
    final mq = MediaQuery.sizeOf(context);
    var h = height;
    if (!h.isFinite || h <= 0) {
      h = (mq.height * 0.38).clamp(220.0, 640.0);
    }

    final cols = controller.displayColumns;
    if (cols.isEmpty) {
      return SizedBox(
        height: h,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    color: _kanbanAccentColor(context),
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Preparando colunas do quadro…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sincronizando etapas e cards',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final n = cols.length;
    final gapCount = n <= 1 ? 0 : n - 1;
    final totalGapsPx = gapCount * _kKanbanColumnGap;
    final usable = viewportWidth > 0 ? viewportWidth : 0.0;
    final perColIfStretch =
        n > 0 ? (usable - totalGapsPx) / n : _kKanbanScrollColumnWidth;
    final stretch =
        n > 0 && perColIfStretch >= _kKanbanMinStretchColumnWidth;

    if (stretch) {
      return SizedBox(
        height: h,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(n, (i) {
            final column = cols[i];
            final columnTasks = controller.getTasksForColumn(column.id);
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i == n - 1 ? 0 : _kKanbanColumnGap,
                ),
                child: _buildColumn(
                  context,
                  controller,
                  column,
                  columnTasks,
                ),
              ),
            );
          }),
        ),
      );
    }

    final totalWidth =
        n * _kKanbanScrollColumnWidth + gapCount * _kKanbanColumnGap;
    final minRowWidth =
        usable > totalWidth ? usable : totalWidth;

    return SizedBox(
      height: h,
      child: ScrollConfiguration(
        behavior: NoScrollbarScrollBehavior(),
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minRowWidth,
              minHeight: h,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(n, (i) {
                final column = cols[i];
                final columnTasks = controller.getTasksForColumn(column.id);
                return Padding(
                  padding: EdgeInsets.only(
                    right: i == n - 1 ? 0 : _kKanbanColumnGap,
                  ),
                  child: SizedBox(
                    width: _kKanbanScrollColumnWidth,
                    child: _buildColumn(
                      context,
                      controller,
                      column,
                      columnTasks,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Color _kanbanAccentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  Widget _kanbanHeroEyebrow(BuildContext context, bool compact) {
    final accent = _kanbanAccentColor(context);
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.labelSmall?.copyWith(
      letterSpacing: compact ? 1.15 : 2.35,
      fontWeight: FontWeight.w900,
      color: Colors.white,
    );
    final textWidget = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        if (bounds.width <= 0 || bounds.height <= 0) {
          return LinearGradient(colors: [accent]).createShader(
            Rect.fromLTWH(0, 0, 1, 1),
          );
        }
        return LinearGradient(
          colors: [
            accent,
            const Color(0xFFE11D48),
            const Color(0xFF0891B2),
          ],
          stops: const [0.05, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height));
      },
      child: Text(
        'FUNIS · CRM',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: textWidget,
      ),
    );
  }

  Widget _kanbanHeroLeadingIcon(BuildContext context) {
    final accent = _kanbanAccentColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            const Color(0xFF7C3AED),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? accent.withValues(alpha: 0.38)
                : Colors.black.withValues(alpha: 0.14),
            blurRadius: isDark ? 16 : 12,
            offset: Offset(0, isDark ? 9 : 5),
            spreadRadius: isDark ? 0 : -1,
          ),
        ],
      ),
      child: const Icon(
        Icons.account_tree_rounded,
        color: Colors.white,
        size: 25,
      ),
    );
  }

  /// Micro-chip (pill compacta) — versão refinada do antigo
  /// `_kanbanActiveContextChip`, agora pra contexto leve do hero
  /// (time, atualização, filtro). Usa cor tom-on-tom com leve borda.
  Widget _kanbanMicroChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tone.withValues(alpha: isDark ? 0.14 : 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 5),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.05,
                  fontSize: 11.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _kanbanActiveContextChip(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onClear,
  }) {
    final accent = _kanbanAccentColor(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 14, color: accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Header da seção "Refinar quadro" — pequeno banner com gradient stripe e descrição.
  Widget _kanbanToolsHeader(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _kanbanAccentColor(context);
    const cool = Color(0xFF0891B2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.95),
                    cool.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Refinar pipeline',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.35,
                      height: 1.1,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Trocar de funil, buscar leads e cortar por prioridade.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            return Container(
              width: c.maxWidth,
              height: 2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    accent.withValues(alpha: 0.42),
                    cool.withValues(alpha: 0.38),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.28, 0.62, 1.0],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _kanbanToolsContinuation(
    BuildContext context,
    KanbanController controller,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;

        final projectSelector = ProjectSelector(
          key: ValueKey(controller.team?.id ?? 't'),
          embedded: true,
        );

        final filters = KanbanFilters(
          key: ValueKey(controller.filterClearGeneration),
          embedded: true,
        );

        Widget mainBlock;
        if (wide) {
          mainBlock = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: projectSelector),
              const SizedBox(width: 14),
              Expanded(flex: 7, child: filters),
            ],
          );
        } else {
          mainBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              projectSelector,
              const SizedBox(height: 12),
              filters,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kanbanToolsHeader(context),
            const SizedBox(height: 14),
            mainBlock,
            // Linha de ações utilitárias do CRM — sempre exibe "Tarefas"
            // (lista global de subtarefas), e o "Modo seleção" só aparece
            // quando o controller habilita (regra antiga preservada).
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kanbanTasksButton(context),
                if (controller.showBulkSelectionEntry &&
                    (controller.board?.columns.isNotEmpty ?? false))
                  _kanbanBulkToggleButton(context, controller),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Cor do botão de Tarefas — usa o accent de oportunidades (vermelho da
  /// marca) com leve tom roxo via gradiente para sinalizar "produtividade".
  Color _kanbanTasksButtonColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  Widget _kanbanTasksButton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _kanbanTasksButtonColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.kanbanSubtasks),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: isDark ? 0.22 : 0.13),
                color.withValues(alpha: isDark ? 0.10 : 0.06),
              ],
            ),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.5 : 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isDark ? 0.18 : 0.10),
                blurRadius: 10,
                offset: const Offset(0, 4),
                spreadRadius: -3,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 8, 13, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.checklist_rounded,
                  size: 17,
                  color: color,
                ),
                const SizedBox(width: 7),
                Text(
                  'Tarefas',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cor "gerencial" do modo de seleção em lote — indigo. Diferente do accent
  /// rosa do app, pra criar um contexto visual distinto ("modo edição/admin")
  /// e quebrar a sensação de tela 100% preto-e-vermelho.
  static const Color _kBulkManageColor = Color(0xFF6366F1);

  Widget _kanbanBulkToggleButton(
    BuildContext context,
    KanbanController controller,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final active = controller.bulkSelectionActive;
    final disabled = controller.bulkDeleteEligibilityLoading;

    // Quando ativo: cor "âmbar de aviso" (você está em um modo especial,
    // saiba que clicar = sair). Quando inativo: indigo gerencial.
    final color = active ? const Color(0xFFD97706) : _kBulkManageColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled
            ? null
            : () {
                if (active) {
                  controller.exitBulkSelectionMode();
                } else {
                  controller.setBulkSelectionActive(true);
                }
              },
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Color.alphaBlend(
              color.withValues(alpha: isDark ? 0.14 : 0.08),
              ThemeHelpers.cardBackgroundColor(context),
            ),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.5 : 0.35),
              width: active ? 1.4 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: isDark ? 0.22 : 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 8, 13, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active
                      ? Icons.close_rounded
                      : Icons.library_add_check_outlined,
                  size: 17,
                  color: color,
                ),
                const SizedBox(width: 7),
                Text(
                  active ? 'Sair do modo seleção' : 'Modo seleção',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKanbanHero(
    BuildContext context,
    KanbanController controller,
    double padH,
    bool compact,
    double width, {
    Widget? toolsContinuation,
  }) {
    final theme = Theme.of(context);

    final hasSearch = controller.searchQuery != null &&
        controller.searchQuery!.trim().isNotEmpty;
    final hasFilters = controller.filterPriority != null ||
        (controller.filterAssigneeId != null &&
            controller.filterAssigneeId!.trim().isNotEmpty);

    final q = controller.searchQuery?.trim() ?? '';
    final headline = hasSearch ? 'Radar de leads' : 'Pipeline de leads';

    final mainTitles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _kanbanHeroEyebrow(context, compact),
        const SizedBox(height: 4),
        Text(
          headline,
          style: (compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)
              ?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.02,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ],
    );

    // Linha de contexto reescrita: time + última atualização (em chip leve,
    // sem repetir contagem de etapas/cards — isso vai aparecer na navegação
    // por etapas logo abaixo, evitando a redundância antiga).
    final updatedAtLabel = DateFormat("HH:mm · d MMM", 'pt_BR')
        .format(DateTime.now());

    final contextStrip = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _kanbanMicroChip(
          context,
          icon: Icons.update_rounded,
          label: 'Atualização $updatedAtLabel',
          tone: ThemeHelpers.textSecondaryColor(context),
        ),
        if (hasSearch)
          _kanbanMicroChip(
            context,
            icon: Icons.search_rounded,
            label: q.length > 28 ? '${q.substring(0, 28)}…' : 'busca: $q',
            tone: _kanbanAccentColor(context),
          )
        else if (hasFilters)
          _kanbanMicroChip(
            context,
            icon: Icons.tune_rounded,
            label: 'Filtros aplicados',
            tone: _kanbanAccentColor(context),
          ),
      ],
    );

    final Widget heroTop = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kanbanHeroLeadingIcon(context),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              mainTitles,
              const SizedBox(height: 10),
              contextStrip,
            ],
          ),
        ),
      ],
    );


    return Padding(
      padding: EdgeInsets.fromLTRB(
        padH,
        8,
        padH,
        toolsContinuation != null ? 22 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: _kHeaderPadVTop),
            child: heroTop,
          ),
          if (toolsContinuation != null) ...[
            SizedBox(height: compact ? 18 : 22),
            toolsContinuation,
          ],
        ],
      ),
    );
  }

  /// Nova negociação (card) — primeira etapa real do funil, mesmo fluxo do botão por coluna / CRM web.
  void _openHeroCreateNegotiationModal(
    BuildContext context,
    KanbanController controller,
  ) {
    final teamId = controller.teamId;
    if (teamId == null || teamId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um funil antes de criar um card.'),
        ),
      );
      return;
    }

    final cols = controller.displayColumns;
    KanbanColumn? target;
    for (final c in cols) {
      if (!KanbanSyntheticColumns.isSyntheticId(c.id)) {
        target = c;
        break;
      }
    }
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aguarde o quadro sincronizar para poder criar um card.',
          ),
        ),
      );
      return;
    }
    final createInColumn = target;

    Navigator.of(context).push(
      adaptivePageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChangeNotifierProvider<KanbanController>.value(
          value: controller,
          child: CreateTaskModal(
            columnId: createInColumn.id,
            teamId: teamId,
          ),
        ),
      ),
    );
  }

  Color _columnAccentColor(KanbanColumn column, BuildContext context) {
    final raw = column.color;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        return Color(int.parse(raw.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return Theme.of(context).colorScheme.primary;
  }

  Widget _columnStageGlyph(KanbanColumn column, Color accent) {
    IconData icon;
    if (column.position <= 0) {
      icon = Icons.flag_outlined;
    } else if (column.position == 1) {
      icon = Icons.timelapse_rounded;
    } else {
      icon = Icons.workspace_premium_outlined;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(icon, size: 22, color: accent),
    );
  }

  Widget _buildColumn(
    BuildContext context,
    KanbanController controller,
    KanbanColumn column,
    List<KanbanTask> tasks,
  ) {
    final theme = Theme.of(context);
    final synth = column.isSyntheticKanbanPlaceholder;
    final columnColor = _columnAccentColor(column, context);
    final canEditCols = (controller.permissions?.canEditColumns ?? false) ||
        (controller.permissions?.canDeleteColumns ?? false);

    final emptyCaption = synth
        ? 'Etapas oficiais aparecem quando o quadro sincroniza.'
        : 'Nenhuma tarefa';

    final borderLine = ThemeHelpers.borderColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = ThemeHelpers.cardBackgroundColor(context);
    final tintTop = columnColor.withValues(alpha: synth ? 0.045 : (isDark ? 0.13 : 0.085));
    final tintMid = columnColor.withValues(alpha: synth ? 0.02 : (isDark ? 0.055 : 0.035));
    final borderTint = Color.alphaBlend(
      columnColor.withValues(alpha: synth ? 0.12 : (isDark ? 0.38 : 0.18)),
      borderLine,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kKanbanColumnRadius),
        border: Border.all(color: borderTint),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
            blurRadius: isDark ? 14 : 10,
            offset: const Offset(0, 3),
          ),
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kKanbanColumnRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.22, 0.52, 1.0],
                    colors: [
                      tintTop,
                      tintMid,
                      Color.alphaBlend(columnColor.withValues(alpha: synth ? 0.03 : (isDark ? 0.06 : 0.045)), surface),
                      Color.alphaBlend(
                        theme.colorScheme.surface.withValues(alpha: isDark ? 0.12 : 0.06),
                        surface,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      columnColor,
                      Color.alphaBlend(
                        columnColor.withValues(alpha: 0.72),
                        surface,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: ThemeHelpers.cardBackgroundColor(context),
                      border: Border(
                        bottom: BorderSide(
                          color: Color.alphaBlend(
                            columnColor.withValues(alpha: 0.2),
                            borderLine,
                          ),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 11, 8, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _columnStageGlyph(column, columnColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (synth)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          'Funil padrão',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: columnColor,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      column.title,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.35,
                                        height: 1.08,
                                      ),
                                    ),
                                    if (column.description != null &&
                                        column.description!
                                            .trim()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        column.description!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color:
                                              ThemeHelpers.textSecondaryColor(
                                            context,
                                          ),
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '${tasks.length}',
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        color: columnColor,
                                        fontWeight: FontWeight.w900,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                  if (canEditCols && !synth)
                                    PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert_rounded,
                                        size: 22,
                                        color: ThemeHelpers.textSecondaryColor(
                                          context,
                                        ),
                                      ),
                                      itemBuilder: (context) => [
                                        if (controller.permissions
                                                ?.canEditColumns ??
                                            true)
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit, size: 18),
                                                SizedBox(width: 8),
                                                Text('Editar'),
                                              ],
                                            ),
                                          ),
                                        if (controller.permissions
                                                ?.canDeleteColumns ??
                                            true)
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.delete,
                                                  size: 18,
                                                  color: Colors.red,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Deletar',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            backgroundColor: Colors.transparent,
                                            builder: (context) =>
                                                EditColumnModal(column: column),
                                          );
                                        } else if (value == 'delete') {
                                          _confirmDeleteColumn(
                                            context,
                                            controller,
                                            column,
                                          );
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: DragTarget<KanbanTask>(
                      onWillAcceptWithDetails: synth ||
                              controller.bulkSelectionActive
                          ? (_) => false
                          : (details) => details.data.columnId != column.id,
                      onAcceptWithDetails: (details) {
                        _handleTaskDrop(
                          context,
                          controller,
                          details.data,
                          column.id,
                        );
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isTargeting = candidateData.isNotEmpty;
                        final highlight = isTargeting
                            ? columnColor.withValues(alpha: 0.09)
                            : Colors.transparent;
                        final dashedBorderColor = isTargeting
                            ? columnColor.withValues(alpha: 0.55)
                            : Colors.transparent;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: highlight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: dashedBorderColor,
                              width: isTargeting ? 1.4 : 0,
                            ),
                          ),
                          child: tasks.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 16,
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isTargeting
                                              ? Icons
                                                  .download_for_offline_outlined
                                              : Icons.inbox_outlined,
                                          size: 42,
                                          color: isTargeting
                                              ? columnColor
                                              : ThemeHelpers
                                                      .textSecondaryColor(
                                                  context,
                                                ).withValues(alpha: 0.45),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          isTargeting
                                              ? 'Solte para mover aqui'
                                              : emptyCaption,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: isTargeting
                                                ? columnColor
                                                : ThemeHelpers
                                                    .textSecondaryColor(
                                                    context,
                                                  ),
                                            fontWeight: isTargeting
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            height: 1.4,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ScrollConfiguration(
                                  behavior: NoScrollbarScrollBehavior(),
                                  child: Builder(
                                    builder: (context) {
                                      // Paginação por coluna — auto load ao
                                      // chegar no fim da lista; mantém item
                                      // extra apenas para mostrar spinner.
                                      final pagination = controller
                                          .columnPaginationFor(column.id);
                                      final showFooter = pagination.loadingMore;
                                      final itemCount = tasks.length +
                                          (showFooter ? 1 : 0);
                                      return NotificationListener<
                                        ScrollNotification
                                      >(
                                        onNotification: (notification) {
                                          if (notification.metrics.axis !=
                                              Axis.vertical) {
                                            return false;
                                          }
                                          final nearBottom =
                                              notification
                                                  .metrics
                                                  .pixels >=
                                              notification
                                                      .metrics
                                                      .maxScrollExtent -
                                                  120;
                                          if (nearBottom &&
                                              pagination.hasMore &&
                                              !pagination.loadingMore) {
                                            controller.loadMoreTasksForColumn(
                                              column.id,
                                            );
                                          }
                                          return false;
                                        },
                                        child: ListView.builder(
                                          shrinkWrap: false,
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.fromLTRB(
                                            6,
                                            8,
                                            6,
                                            8,
                                          ),
                                          itemCount: itemCount,
                                          itemBuilder: (context, index) {
                                            if (index >= tasks.length) {
                                              return _buildLoadMoreFooter(
                                                context,
                                                columnColor,
                                                pagination,
                                              );
                                            }
                                            final task = tasks[index];
                                            return _buildDraggableTaskForReorder(
                                              context,
                                              controller,
                                              task,
                                              column.id,
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                  if ((controller.permissions?.canCreateTasks ?? true) &&
                      !synth)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              adaptivePageRoute<void>(
                                fullscreenDialog: true,
                                builder: (_) =>
                                    ChangeNotifierProvider<KanbanController>
                                        .value(
                                  value: controller,
                                  child: CreateTaskModal(
                                    columnId: column.id,
                                    teamId: controller.teamId ?? '',
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Nova tarefa'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Footer da lista de cards — somente spinner do carregamento automático.
  Widget _buildLoadMoreFooter(
    BuildContext context,
    Color columnColor,
    ColumnPagination pagination,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final loading = pagination.loadingMore;
    final loaded = pagination.loadedCount;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: columnColor.withValues(alpha: isDark ? 0.10 : 0.06),
            border: Border.all(
              color: columnColor.withValues(alpha: isDark ? 0.35 : 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: columnColor,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Carregando mais tarefas...',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: columnColor,
                    letterSpacing: -0.1,
                  ),
                ),
              ] else
                Text(
                  '$loaded carregados',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: columnColor,
                    fontSize: 10,
                    letterSpacing: 0.2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableTaskForReorder(
    BuildContext context,
    KanbanController controller,
    KanbanTask task,
    String currentColumnId,
  ) {
    if (controller.bulkSelectionActive) {
      final selected = controller.isBulkTaskSelected(task.id);
      final accent = Theme.of(context).colorScheme.primary;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: controller.bulkDeleting
                ? null
                : () => controller.toggleBulkTaskSelection(task.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      selected ? accent : Colors.transparent,
                  width: selected ? 2 : 1,
                ),
              ),
              child: _buildTaskCard(
                task,
                bulkMode: true,
                bulkSelected: selected,
              ),
            ),
          ),
        ),
      );
    }

    if (!(controller.permissions?.canMoveTasks ?? false)) {
      return GestureDetector(
        onDoubleTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            builder: (context) => TaskDetailsModal(task: task),
          );
        },
        onLongPress: () {
          _showTaskActions(context, task);
        },
        child: _buildTaskCard(task),
      );
    }

    return LongPressDraggable<KanbanTask>(
      data: task,
      delay: const Duration(milliseconds: 100),
      onDragStarted: () {
        setState(() {
          _isDragging = true;
        });
        _startAutoScroll();
      },
      onDragEnd: (_) {
        setState(() {
          _isDragging = false;
        });
        _stopAutoScroll();
      },
      onDragUpdate: (details) {
        _updateAutoScroll(details.globalPosition.dx);
      },
      feedback: Material(
        color: Colors.transparent,
        elevation: 0,
        child: Opacity(
          opacity: 0.92,
          child: SizedBox(width: 280, child: _buildTaskCard(task)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: _buildTaskCard(task)),
      child: GestureDetector(
        onDoubleTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: Colors.black54,
            builder: (context) => TaskDetailsModal(task: task),
          );
        },
        onLongPress: () {
          _showTaskActions(context, task);
        },
        child: _buildTaskCard(task),
      ),
    );
  }

  void _handleTaskDrop(
    BuildContext context,
    KanbanController controller,
    KanbanTask task,
    String targetColumnId,
  ) {
    if (task.columnId == targetColumnId) return;
    if (KanbanSyntheticColumns.isSyntheticId(targetColumnId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Etapas ainda não carregadas do servidor nesta vista.',
          ),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    // Em paridade com o web: ordenação cliente é sempre por createdAt desc,
    // então a posição enviada ao backend é apenas o "tail" (final) da nova
    // coluna — o backend mantém position p/ outros consumidores, mas o
    // mobile já reflete o movimento imediatamente via update otimista.
    final targetTasks = controller.getTasksForColumn(targetColumnId);
    final newPosition = targetTasks.length;

    // Fire-and-forget: o controller já faz update otimista (notifyListeners
    // antes da chamada à API), então a UI move o card em real time. Enviamos
    // explicitamente `fromColumnId` (coluna atual antes do drop) porque o
    // backend valida `@IsUUID` e rejeita 400 se ausente.
    unawaited(
      controller.moveTask(
        taskId: task.id,
        fromColumnId: task.columnId,
        targetColumnId: targetColumnId,
        targetPosition: newPosition,
      ),
    );
  }

  Widget _taskResultChip(KanbanTask task) {
    final r = task.normalizedResult;
    if (r == 'open') return const SizedBox.shrink();
    late final String label;
    late final Color color;
    switch (r) {
      case 'won':
        label = 'Vendido';
        color = const Color(0xFF16A34A);
        break;
      case 'lost':
        label = 'Perdido';
        color = const Color(0xFFDC2626);
        break;
      default:
        label = 'Cancelado';
        color = ThemeHelpers.textSecondaryColor(context);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _buildTaskCard(
    KanbanTask task, {
    bool bulkMode = false,
    bool bulkSelected = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final priorityColor = task.priority != null
        ? Color(int.parse(task.priority!.color.replaceFirst('#', '0xFF')))
        : null;

    final deadline = _KanbanTaskDeadline.fromDueDate(task.dueDate);
    final cardSurface = ThemeHelpers.cardBackgroundColor(context);
    final secondaryText = ThemeHelpers.textSecondaryColor(context);

    final accent = deadline.accentColor(context);
    final tintedSurface = accent == null
        ? cardSurface
        : Color.alphaBlend(accent.withValues(alpha: isDark ? 0.07 : 0.05), cardSurface);
    final borderColor = accent != null
        ? accent.withValues(alpha: isDark ? 0.45 : 0.32)
        : (priorityColor?.withValues(alpha: 0.28) ??
            ThemeHelpers.borderColor(context));
    final borderWidth = accent != null || priorityColor != null ? 1.2 : 1.0;
    final leftStripe = accent ?? priorityColor;

    final tags = task.displayTags;
    final hasTags = tags != null && tags.isNotEmpty;

    // Cor primária do card: usa o accent do prazo > prioridade > primary
    final cardAccent = accent ?? priorityColor ?? theme.colorScheme.primary;
    final assigned = task.assignedTo;
    final descriptionText = task.description?.trim() ?? '';
    final hasDescription = descriptionText.isNotEmpty;

    return GestureDetector(
      onDoubleTap: bulkMode
          ? null
          : () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                barrierColor: Colors.black54,
                builder: (context) => TaskDetailsModal(task: task),
              );
            },
      child: Container(
        width: double.infinity,
        margin: bulkMode ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: tintedSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: cardAccent.withValues(alpha: isDark ? 0.10 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
              spreadRadius: -2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              // Glow sutil diagonal (canto superior direito) com a cor do
              // card. Dá vida ao card sem virar uma cara colorida cheia.
              Positioned(
                top: -22,
                right: -22,
                child: IgnorePointer(
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          cardAccent.withValues(alpha: isDark ? 0.20 : 0.13),
                          cardAccent.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Tira lateral em gradiente (mantida — é a identidade)
              if (leftStripe != null)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          leftStripe.withValues(alpha: 1.0),
                          leftStripe.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                ),
              if (deadline.isOverdue || deadline.isDueToday)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent!.withValues(alpha: 0.0),
                          accent.withValues(alpha: 0.95),
                          accent.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  leftStripe != null ? 16 : 14,
                  14,
                  12,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ─── HEADER: avatar grande à esquerda + título à direita
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bulkMode)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: 10, top: 2),
                            child: Icon(
                              bulkSelected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 22,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        else
                          _taskCardLeadAvatar(
                            assigned: assigned,
                            accent: cardAccent,
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                task.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  height: 1.25,
                                  letterSpacing: -0.2,
                                  color: ThemeHelpers.textColor(context),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (assigned != null && !bulkMode) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline_rounded,
                                      size: 11,
                                      color: secondaryText,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        _firstName(assigned.name),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: secondaryText,
                                          fontSize: 11,
                                          letterSpacing: -0.05,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (task.isCompleted)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 1),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        if (!bulkMode) _buildTaskCardMenu(task),
                      ],
                    ),

                    // ─── DESCRIÇÃO opcional (mais discreta agora)
                    if (hasDescription) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.black.withValues(alpha: 0.025),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.04),
                          ),
                        ),
                        child: Text(
                          descriptionText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondaryText,
                            fontSize: 12.25,
                            height: 1.45,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],

                    // ─── PILLS de contexto (prioridade, prazo, resultado, tags)
                    if (task.priority != null ||
                        deadline.isVisible ||
                        hasTags ||
                        task.hasClosedResult) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (task.priority != null)
                            _priorityChip(task.priority!, priorityColor!),
                          if (deadline.isVisible) _deadlineChip(deadline),
                          if (task.hasClosedResult) _taskResultChip(task),
                          if (hasTags)
                            ..._buildTaskTagChips(tags, theme),
                        ],
                      ),
                    ],

                    // ─── FOOTER: data + comentários (à esquerda), separados
                    // por divisor sutil
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          _taskCardMetric(
                            icon: Icons.schedule_rounded,
                            label: _relativeCardTime(task.createdAt),
                            color: secondaryText,
                          ),
                          if (task.commentsCount != null &&
                              task.commentsCount! > 0) ...[
                            const SizedBox(width: 12),
                            _taskCardMetric(
                              icon: Icons.mode_comment_outlined,
                              label: '${task.commentsCount}',
                              color: secondaryText,
                            ),
                          ],
                          const Spacer(),
                          // Tag "Nova" para tarefas criadas há menos de 24h
                          if (DateTime.now()
                                  .difference(task.createdAt)
                                  .inHours <
                              24)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cardAccent.withValues(
                                  alpha: isDark ? 0.20 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: cardAccent.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                'NOVA',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 9,
                                  letterSpacing: 1.2,
                                  color: cardAccent,
                                  height: 1,
                                ),
                              ),
                            ),
                        ],
                      ),
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

  /// Avatar do responsável no canto superior esquerdo do card — quando
  /// não há responsável, mostra um "ghost" tintado pra manter o ritmo
  /// visual sem brigar com o título.
  Widget _taskCardLeadAvatar({
    required dynamic assigned,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (assigned == null) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
          border: Border.all(
            color: accent.withValues(alpha: 0.30),
            style: BorderStyle.solid,
          ),
        ),
        child: Icon(
          Icons.person_outline_rounded,
          size: 18,
          color: accent.withValues(alpha: 0.65),
        ),
      );
    }
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        children: [
          Positioned.fill(child: _assigneeAvatar(assigned)),
          // anel da cor do card em volta do avatar
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCardMetric({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.05,
          ),
        ),
      ],
    );
  }

  /// Constrói até 3 chips de tag para o card. Tags adicionais aparecem como
  /// um chip "+N" no final, mantendo a densidade horizontal mesmo com várias
  /// tags configuradas.
  List<Widget> _buildTaskTagChips(List<String> tags, ThemeData theme) {
    const maxVisible = 3;
    final visible = tags.length <= maxVisible ? tags : tags.take(maxVisible).toList();
    final extra = tags.length - visible.length;
    return [
      for (final t in visible) _firstTagChip(t, theme),
      if (extra > 0) _moreTagsChip(extra, theme),
    ];
  }

  /// Hora relativa curta para o rodapé do card (ex.: "agora", "5 min", "3 h",
  /// "2 d", "12/04"). Mantém o card legível em qualquer largura de coluna.
  String _relativeCardTime(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays < 7) return '${diff.inDays} d';
    String twoDigits(int v) => v.toString().padLeft(2, '0');
    return '${twoDigits(createdAt.day)}/${twoDigits(createdAt.month)}';
  }

  /// Primeiro nome do usuário (com fallback para uma string vazia quando o
  /// nome estiver em branco).
  String _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final firstSpace = trimmed.indexOf(' ');
    return firstSpace == -1 ? trimmed : trimmed.substring(0, firstSpace);
  }

  Widget _buildTaskCardMenu(KanbanTask task) {
    return SizedBox(
      width: 26,
      height: 26,
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16),
        padding: EdgeInsets.zero,
        iconSize: 16,
        constraints: const BoxConstraints(),
        splashRadius: 18,
        onSelected: (value) {
          switch (value) {
            case 'details':
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => TaskDetailsModal(task: task),
              );
              break;
            case 'edit':
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: EditTaskModal(task: task),
                ),
              );
              break;
            case 'delete':
              final controller = context.read<KanbanController>();
              _confirmDeleteTask(context, controller, task);
              break;
          }
        },
        itemBuilder: (context) {
          final ctrl = context.read<KanbanController>();
          final perms = ctrl.permissions;
          return [
            const PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 8),
                  Text('Ver detalhes'),
                ],
              ),
            ),
            if (perms?.canEditTasks ?? true)
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 8),
                    Text('Editar'),
                  ],
                ),
              ),
            if (perms?.canDeleteTasks ?? true)
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Excluir', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ];
        },
      ),
    );
  }

  Widget _priorityChip(KanbanPriority p, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.7),
      ),
      child: Text(
        p.label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _deadlineChip(_KanbanTaskDeadline deadline) {
    final c =
        deadline.accentColor(context) ?? ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.28), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(deadline.icon, size: 11, color: c),
          const SizedBox(width: 3),
          Text(
            deadline.shortLabel,
            style: TextStyle(
              color: c,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _firstTagChip(String tag, ThemeData theme) {
    final c = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10,
          color: c,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _moreTagsChip(int extra, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '+$extra',
        style: TextStyle(
          fontSize: 10,
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _assigneeAvatar(KanbanUser user) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 11,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      backgroundImage: user.avatar != null && user.avatar!.isNotEmpty
          ? NetworkImage(user.avatar!)
          : null,
      child: user.avatar == null || user.avatar!.isEmpty
          ? Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }


  void _showTaskActions(BuildContext context, KanbanTask task) {
    final pageContext = context;
    final controller = context.read<KanbanController>();
    final perms = controller.permissions;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Ver detalhes'),
              onTap: () {
                Navigator.pop(sheetContext);
                showModalBottomSheet<void>(
                  context: pageContext,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  barrierColor: Colors.black54,
                  builder: (ctx) => TaskDetailsModal(task: task),
                );
              },
            ),
            if (perms?.canEditTasks ?? true)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Editar'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showModalBottomSheet<void>(
                    context: pageContext,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(ctx).viewInsets.bottom,
                      ),
                      child: EditTaskModal(task: task),
                    ),
                  );
                },
              ),
            if (perms?.canDeleteTasks ?? true)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Deletar',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteTask(pageContext, controller, task);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Dock do modo de seleção — sticky no rodapé. Visual de modal premium:
  /// header colorido com gradient indigo + contador + ações com paleta
  /// distinta por intent (azul = seleção total, neutro = limpar, vermelho =
  /// excluir). Quebra a tela "preto-e-vermelho" introduzindo indigo/cyan.
  Widget _buildBulkSelectionDock(
    BuildContext context,
    KanbanController controller,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const manage = _kBulkManageColor; // indigo
    const cyan = Color(0xFF0891B2);
    final muted = ThemeHelpers.textSecondaryColor(context);

    final selected = controller.bulkSelectedCount;
    final hasSelection = selected > 0;
    final disabled = controller.bulkDeleting;

    return Material(
      elevation: 18,
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: manage.withValues(alpha: isDark ? 0.32 : 0.22),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: manage.withValues(alpha: isDark ? 0.22 : 0.12),
                blurRadius: 22,
                spreadRadius: -4,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header gradient (modo ativo) ──────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              manage.withValues(alpha: 0.22),
                              cyan.withValues(alpha: 0.12),
                            ]
                          : [
                              manage.withValues(alpha: 0.12),
                              cyan.withValues(alpha: 0.06),
                            ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: manage.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Glyph com badge de contador
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  manage,
                                  Color.lerp(manage, cyan, 0.5)!,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: manage.withValues(alpha: 0.45),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.library_add_check_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          if (hasSelection)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: const Color(0xFF10B981),
                                  border: Border.all(
                                    color: ThemeHelpers.cardBackgroundColor(
                                      context,
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  selected > 99 ? '99+' : '$selected',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'MODO SELEÇÃO',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.6,
                                color: manage,
                                fontSize: 9.5,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hasSelection
                                  ? '$selected ${selected == 1 ? "card selecionado" : "cards selecionados"}'
                                  : 'Toque nos cards para selecionar',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sair do modo seleção',
                        onPressed: disabled
                            ? null
                            : () => controller.exitBulkSelectionMode(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: muted,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                // ── Ações ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      // Selecionar todos — cyan info
                      Expanded(
                        child: _buildBulkActionButton(
                          context,
                          icon: Icons.done_all_rounded,
                          label: 'Todos',
                          color: cyan,
                          onPressed: disabled
                              ? null
                              : controller.bulkSelectAllCurrentTasks,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Limpar — neutro
                      Expanded(
                        child: _buildBulkActionButton(
                          context,
                          icon: Icons.clear_rounded,
                          label: 'Limpar',
                          color: muted,
                          neutral: true,
                          onPressed: (disabled || !hasSelection)
                              ? null
                              : controller.clearBulkTaskSelection,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Excluir — único filled vermelho (intent destrutivo)
                      Expanded(
                        flex: 2,
                        child: _buildBulkActionButton(
                          context,
                          icon: Icons.delete_outline_rounded,
                          label: 'Excluir',
                          color: theme.colorScheme.error,
                          filled: true,
                          onPressed: (disabled || !hasSelection)
                              ? null
                              : () => _confirmBulkDelete(context, controller),
                        ),
                      ),
                    ],
                  ),
                ),
                if (disabled) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: manage,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Excluindo cards selecionados…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Botão de ação do dock — pílula com ícone + label.
  /// `filled=true` → fundo na cor `color` com texto branco (intent forte).
  /// `neutral=true` → outline cinza (intent neutro/secundário).
  /// padrão → outline tinted na cor (intent informativo).
  Widget _buildBulkActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool filled = false,
    bool neutral = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disabled = onPressed == null;
    final borderCol = ThemeHelpers.borderColor(context);

    final bg = filled
        ? color.withValues(alpha: disabled ? 0.45 : 1)
        : Color.alphaBlend(
            (neutral ? borderCol : color)
                .withValues(alpha: isDark ? 0.14 : 0.08),
            ThemeHelpers.cardBackgroundColor(context),
          );
    final fg = filled
        ? Colors.white
        : (neutral
              ? ThemeHelpers.textColor(context).withValues(alpha: 0.85)
              : color);
    final borderColor = filled
        ? Colors.transparent
        : (neutral
              ? borderCol
              : color.withValues(alpha: isDark ? 0.45 : 0.32));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
            boxShadow: filled && !disabled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 11,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: fg,
                      fontSize: 13,
                      letterSpacing: 0.05,
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

  void _confirmBulkDelete(
    BuildContext context,
    KanbanController controller,
  ) {
    final n = controller.bulkSelectedCount;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir cards em massa'),
        content: Text(
          n <= 1
              ? 'Excluir o card selecionado definitivamente?'
              : 'Excluir $n cards definitivamente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ok = await controller.bulkDeleteSelectedTasks();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Exclusão concluída.'
                        : (controller.error ??
                            'Alguns ou todos os cards não puderam ser excluídos. O quadro foi atualizado.'),
                  ),
                  backgroundColor: ok ? Colors.green : Colors.orange.shade900,
                ),
              );
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTask(
    BuildContext context,
    KanbanController controller,
    KanbanTask task,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Tarefa'),
        content: Text(
          'Tem certeza que deseja deletar a tarefa "${task.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await controller.deleteTask(task.id);
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tarefa deletada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        controller.error ?? 'Erro ao deletar tarefa',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteColumn(
    BuildContext context,
    KanbanController controller,
    KanbanColumn column,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Coluna'),
        content: Text(
          'Tem certeza que deseja deletar a coluna "${column.title}"? '
          'Todas as tarefas desta coluna serão movidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await controller.deleteColumn(column.id);
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coluna deletada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        controller.error ?? 'Erro ao deletar coluna',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
  }
}

/// Status de prazo do card (espelho do `getDeadlineStatus` em
/// `imobx-front/.../TaskDeadlineIndicator.tsx` e do filtro `task.dueDate < today`
/// usado no backend `kanban.service.ts` / `dashboard.service.ts`):
///
/// - `overdue` — `dueDate < hoje` (vencido) → vermelho.
/// - `due_today` — `dueDate == hoje` (vence hoje) → âmbar.
/// - `ok` — futuro ou sem data → sem realce de cor.
enum _KanbanDeadlineStatus { none, ok, dueToday, overdue }

class _KanbanTaskDeadline {
  final _KanbanDeadlineStatus status;
  final int daysDelta;

  const _KanbanTaskDeadline._(this.status, this.daysDelta);

  static _KanbanTaskDeadline fromDueDate(DateTime? due) {
    if (due == null) {
      return const _KanbanTaskDeadline._(_KanbanDeadlineStatus.none, 0);
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final localDue = due.toLocal();
    final dueDay = DateTime(localDue.year, localDue.month, localDue.day);
    final diffDays = dueDay.difference(today).inDays;
    if (diffDays < 0) {
      return _KanbanTaskDeadline._(_KanbanDeadlineStatus.overdue, diffDays);
    }
    if (diffDays == 0) {
      return const _KanbanTaskDeadline._(_KanbanDeadlineStatus.dueToday, 0);
    }
    return _KanbanTaskDeadline._(_KanbanDeadlineStatus.ok, diffDays);
  }

  bool get isOverdue => status == _KanbanDeadlineStatus.overdue;
  bool get isDueToday => status == _KanbanDeadlineStatus.dueToday;
  bool get isVisible =>
      status == _KanbanDeadlineStatus.overdue ||
      status == _KanbanDeadlineStatus.dueToday ||
      status == _KanbanDeadlineStatus.ok;

  IconData get icon {
    switch (status) {
      case _KanbanDeadlineStatus.overdue:
        return Icons.error_rounded;
      case _KanbanDeadlineStatus.dueToday:
        return Icons.warning_amber_rounded;
      case _KanbanDeadlineStatus.ok:
        return Icons.event_outlined;
      case _KanbanDeadlineStatus.none:
        return Icons.event_outlined;
    }
  }

  String get shortLabel {
    switch (status) {
      case _KanbanDeadlineStatus.overdue:
        final n = daysDelta.abs();
        return n == 1 ? '1 dia atrasado' : '${n}d atrasado';
      case _KanbanDeadlineStatus.dueToday:
        return 'Hoje';
      case _KanbanDeadlineStatus.ok:
        return '${daysDelta}d';
      case _KanbanDeadlineStatus.none:
        return '';
    }
  }

  /// Cor de realce do prazo. `null` quando nada deve ser realçado (ok/none).
  Color? accentColor(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _KanbanDeadlineStatus.overdue:
        return theme.colorScheme.error;
      case _KanbanDeadlineStatus.dueToday:
        return const Color(0xFFD4A017);
      case _KanbanDeadlineStatus.ok:
      case _KanbanDeadlineStatus.none:
        return null;
    }
  }
}

