import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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

  Widget _kanbanBoardChromeHeader(
    BuildContext context,
    KanbanController controller,
  ) {
    final theme = Theme.of(context);
    final accent = _kanbanAccentColor(context);
    final n = controller.displayColumns.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.view_kanban_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Quadro · $n etapas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                    height: 1.1,
                    color: ThemeHelpers.textColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Arraste cards entre colunas.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            thickness: 1,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.38),
          ),
        ],
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

  Widget _kanbanHeroPill(BuildContext context, IconData icon, String label) {
    final accent = _kanbanAccentColor(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.045)
            : ThemeHelpers.backgroundColor(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? accent.withValues(alpha: 0.2)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: -0.12,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _kanbanHeroContextPills(
    BuildContext context,
    KanbanController controller, {
    required bool gatedGlobal,
    required bool compact,
  }) {
    final n = controller.displayColumns.length;
    final stepLabel =
        compact && n >= 100 ? '$n etapas' : '$n etapas · funil ativo';
    return [
      _kanbanHeroPill(
        context,
        gatedGlobal ? Icons.layers_outlined : Icons.filter_alt_outlined,
        gatedGlobal ? 'Quadro inteiro' : 'Filtro refinado',
      ),
      _kanbanHeroPill(
        context,
        Icons.linear_scale_rounded,
        stepLabel,
      ),
    ];
  }

  Widget _kanbanQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
    bool highlight = false,
  }) {
    final accent = _kanbanAccentColor(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final style = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: 12.75,
      height: 1.15,
      letterSpacing: -0.1,
      color: isPrimary
          ? Colors.white
          : highlight
              ? accent
              : ThemeHelpers.textColor(context),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isPrimary
                ? accent
                : Colors.transparent,
            border: Border.all(
              color: isPrimary
                  ? accent
                  : highlight
                      ? accent.withValues(alpha: 0.52)
                      : ThemeHelpers.borderColor(context)
                          .withValues(alpha: isDark ? 0.45 : 0.4),
            ),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: isPrimary ? Colors.white : accent),
                const SizedBox(width: 8),
                Text(label, style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  Widget _kanbanFluidToolsRail(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _kanbanAccentColor(context);
    final cool = const Color(0xFF0891B2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 32,
              width: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.95),
                    cool.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Funil',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.35,
                      height: 1.12,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fluxo contínuo — escolha o funil em seguida e refine sem “caixa” cortando o quadro.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final accent = _kanbanAccentColor(context);
            final cool = const Color(0xFF0891B2);
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kanbanAccentColor(context);
    final baseFill = ThemeHelpers.cardBackgroundColor(context);
    final fillBlend = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.055 : 0.048),
      baseFill.withValues(alpha: isDark ? 0.92 : 0.96),
    );
    OutlineInputBorder fluxBr(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );

    final inputDecorationTheme = InputDecorationTheme(
      filled: true,
      fillColor: fillBlend,
      isDense: false,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      prefixIconConstraints: const BoxConstraints(
        minHeight: 48,
        minWidth: 48,
      ),
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: ThemeHelpers.textSecondaryColor(context),
      ),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
      border: fluxBr(accent.withValues(alpha: isDark ? 0.26 : 0.2)),
      enabledBorder:
          fluxBr(accent.withValues(alpha: isDark ? 0.24 : 0.18)),
      focusedBorder:
          fluxBr(accent.withValues(alpha: isDark ? 0.65 : 0.48), 1.4),
    );

    final inputTheme =
        theme.copyWith(inputDecorationTheme: inputDecorationTheme);

    return Theme(
      data: inputTheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProjectSelector(
            key: ValueKey(controller.team?.id ?? 't'),
            embedded: true,
          ),
          if (controller.showBulkSelectionEntry &&
              (controller.board?.columns.isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.bulkDeleteEligibilityLoading
                    ? null
                    : () {
                        if (controller.bulkSelectionActive) {
                          controller.exitBulkSelectionMode();
                        } else {
                          controller.setBulkSelectionActive(true);
                        }
                      },
                icon: Icon(
                  controller.bulkSelectionActive
                      ? Icons.close_rounded
                      : Icons.checklist_rounded,
                  size: 20,
                ),
                label: Text(
                  controller.bulkSelectionActive
                      ? 'Sair da seleção em massa'
                      : 'Seleção em massa',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          KanbanFilters(
            key: ValueKey(controller.filterClearGeneration),
            embedded: true,
          ),
        ],
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
    final accent = _kanbanAccentColor(context);

    final hasSearch = controller.searchQuery != null &&
        controller.searchQuery!.trim().isNotEmpty;
    final hasFilters = controller.filterPriority != null ||
        (controller.filterAssigneeId != null &&
            controller.filterAssigneeId!.trim().isNotEmpty);
    final gatedGlobal = !hasSearch && !hasFilters;

    final teamName = controller.team?.name;
    final q = controller.searchQuery?.trim() ?? '';
    final subtitleParts = [
      DateFormat("'Atualização' HH:mm · d MMMM", 'pt_BR')
          .format(DateTime.now()),
      if (teamName != null && teamName.isNotEmpty) teamName,
      '${controller.displayColumns.length} etapas · ${_compactIntFormatter.format(controller.tasks.length)} cards',
      if (hasSearch)
        'busca: “${q.length > 28 ? '${q.substring(0, 28)}…' : q}”'
      else if (hasFilters)
        'recorte por prioridade / responsável',
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    final headline = hasSearch ? 'Radar de leads' : 'Pipeline de leads';

    final spread = width >= 480;
    final actionsTop = width >= 640;
    final pillsBesideFunil = width >= 520;

    final canCreateTask =
        controller.permissions?.canCreateTasks ?? true;

    final quickActions = <Widget>[
      if (canCreateTask)
        _kanbanQuickAction(
          context,
          icon: Icons.add_rounded,
          label: 'Cria',
          isPrimary: true,
          onPressed: () =>
              _openHeroCreateNegotiationModal(context, controller),
        ),
      _kanbanQuickAction(
        context,
        icon: Icons.refresh_rounded,
        label: 'Atualizar',
        onPressed: () => controller.loadBoard(),
      ),
    ];

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

    final dateLineWidget = Text(
      subtitleParts,
      style: theme.textTheme.bodySmall?.copyWith(
        color: ThemeHelpers.textSecondaryColor(context),
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: spread ? TextAlign.right : TextAlign.start,
    );

    Widget pillRow() => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kanbanHeroContextPills(
            context,
            controller,
            gatedGlobal: gatedGlobal,
            compact: compact,
          ),
        );

    Widget funilSection() => _kanbanFluidToolsRail(context);

    Widget actionsBar() => Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: quickActions,
        );

    late final Widget heroTop;
    if (!spread) {
      heroTop = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kanbanHeroLeadingIcon(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    mainTitles,
                    const SizedBox(height: 6),
                    dateLineWidget,
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          pillRow(),
          const SizedBox(height: 18),
          funilSection(),
          const SizedBox(height: 18),
          Align(alignment: Alignment.centerRight, child: actionsBar()),
        ],
      );
    } else {
      heroTop = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kanbanHeroLeadingIcon(context),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 52, child: mainTitles),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 48,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: dateLineWidget,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionsTop) ...[
                const SizedBox(width: 12),
                actionsBar(),
              ],
            ],
          ),
          const SizedBox(height: 18),
          if (pillsBesideFunil)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 42, child: pillRow()),
                const SizedBox(width: 12),
                Expanded(flex: 58, child: funilSection()),
              ],
            )
          else ...[
            pillRow(),
            const SizedBox(height: 18),
            funilSection(),
          ],
          if (!actionsTop) ...[
            const SizedBox(height: 18),
            Align(alignment: Alignment.centerRight, child: actionsBar()),
          ],
        ],
      );
    }

    final bridgeTeal = const Color(0xFF0891B2);

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heroTop,
                if (hasSearch || hasFilters) ...[
                  SizedBox(height: compact ? 14 : 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (hasSearch)
                        _kanbanActiveContextChip(
                          context,
                          Icons.search_rounded,
                          q.isEmpty ? 'Busca' : q,
                          onClear: () => context
                              .read<KanbanController>()
                              .clearFilters(),
                        ),
                      if (hasFilters)
                        _kanbanActiveContextChip(
                          context,
                          Icons.tune_rounded,
                          'Filtros aplicados',
                          onClear: () => context
                              .read<KanbanController>()
                              .clearFilters(),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (toolsContinuation != null) ...[
            SizedBox(height: compact ? 16 : 18),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0),
                    accent.withValues(alpha: 0.32),
                    bridgeTeal.withValues(alpha: 0.32),
                    bridgeTeal.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.22, 0.72, 1.0],
                ),
              ),
              child: const SizedBox(height: 1),
            ),
            const SizedBox(height: 16),
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

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: CreateTaskModal(
          columnId: createInColumn.id,
          teamId: teamId,
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
                                    Icons.inbox_outlined,
                                    size: 42,
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ).withValues(alpha: 0.45),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    emptyCaption,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : DragTarget<KanbanTask>(
                            onWillAcceptWithDetails: synth ||
                                    controller.bulkSelectionActive
                                ? (_) => false
                                : (details) =>
                                    details.data.columnId != column.id,
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
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOut,
                                decoration: BoxDecoration(
                                  color: isTargeting
                                      ? columnColor.withValues(alpha: 0.07)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ScrollConfiguration(
                                  behavior: NoScrollbarScrollBehavior(),
                                  child: ListView.builder(
                                    shrinkWrap: false,
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      10,
                                      8,
                                      8,
                                    ),
                                    itemCount: tasks.length,
                                    itemBuilder: (context, index) {
                                      final task = tasks[index];
                                      return DragTarget<KanbanTask>(
                                        onWillAcceptWithDetails: synth ||
                                                controller.bulkSelectionActive
                                            ? (_) => false
                                            : (details) {
                                                return details.data.id !=
                                                    task.id;
                                              },
                                        onAcceptWithDetails: (details) {
                                          final draggedTask = details.data;
                                          debugPrint(
                                            '🎯 [KANBAN_PAGE] DragTarget onAccept:',
                                          );
                                          debugPrint(
                                            '   - Tarefa arrastada: ${draggedTask.title}',
                                          );
                                          debugPrint(
                                            '   - Coluna da tarefa: ${draggedTask.columnId}',
                                          );
                                          debugPrint(
                                            '   - Coluna alvo: ${column.id}',
                                          );
                                          debugPrint(
                                            '   - Índice alvo: $index',
                                          );

                                          if (draggedTask.columnId ==
                                              column.id) {
                                            final oldIndex =
                                                tasks.indexWhere(
                                              (t) => t.id == draggedTask.id,
                                            );
                                            debugPrint(
                                              '   - Índice antigo: $oldIndex',
                                            );
                                            if (oldIndex != -1 &&
                                                oldIndex != index) {
                                              _handleTaskReorder(
                                                context,
                                                controller,
                                                draggedTask,
                                                column.id,
                                                oldIndex,
                                                index,
                                              );
                                            } else {
                                              debugPrint(
                                                '   - ⚠️ Não foi possível reordenar (oldIndex: $oldIndex, newIndex: $index)',
                                              );
                                            }
                                          } else {
                                            debugPrint(
                                              '   - Movendo tarefa de outra coluna',
                                            );
                                            _handleTaskDrop(
                                              context,
                                              controller,
                                              draggedTask,
                                              column.id,
                                            );
                                          }
                                        },
                                        builder:
                                            (context, candidateData, rejectedData) {
                                          final isTargeting =
                                              candidateData.isNotEmpty;
                                          final isSameColumn =
                                              candidateData.isNotEmpty &&
                                              candidateData.first?.columnId ==
                                                  column.id;
                                          return Container(
                                            margin: EdgeInsets.only(
                                              bottom: 8,
                                              top: isTargeting ? 4 : 0,
                                            ),
                                            decoration: isTargeting
                                                ? BoxDecoration(
                                                    border: Border.all(
                                                      color: isSameColumn
                                                          ? Colors.blue
                                                          : Colors.green,
                                                      width: 2,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      8,
                                                    ),
                                                  )
                                                : null,
                                            child: _buildDraggableTaskForReorder(
                                              context,
                                              controller,
                                              task,
                                              column.id,
                                            ),
                                          );
                                        },
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
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => Padding(
                                padding: EdgeInsets.only(
                                  bottom: MediaQuery.of(context)
                                      .viewInsets
                                      .bottom,
                                ),
                                child: CreateTaskModal(
                                  columnId: column.id,
                                  teamId: controller.teamId ?? '',
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

  Widget _buildDraggableTaskForReorder(
    BuildContext context,
    KanbanController controller,
    KanbanTask task,
    String currentColumnId,
  ) {
    if (controller.bulkSelectionActive) {
      final selected = controller.isBulkTaskSelected(task.id);
      final accent = Theme.of(context).colorScheme.primary;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
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
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: LongPressDraggable<KanbanTask>(
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
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 280, child: _buildTaskCard(task)),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: _buildTaskCard(task)),
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

    final targetTasks = controller.getTasksForColumn(targetColumnId);
    final newPosition = targetTasks.length;

    controller.moveTask(
      taskId: task.id,
      targetColumnId: targetColumnId,
      targetPosition: newPosition,
    );
  }

  void _handleTaskReorder(
    BuildContext context,
    KanbanController controller,
    KanbanTask task,
    String columnId,
    int oldIndex,
    int newIndex,
  ) {
    // Se a posição não mudou, não fazer nada
    if (oldIndex == newIndex) return;

    debugPrint('🔄 [KANBAN_PAGE] Reordenando tarefa:');
    debugPrint('   - Tarefa: ${task.title}');
    debugPrint('   - Coluna: $columnId');
    debugPrint('   - Posição antiga: $oldIndex');
    debugPrint('   - Posição nova: $newIndex');

    // Atualizar a posição da tarefa
    controller.moveTask(
      taskId: task.id,
      targetColumnId: columnId,
      targetPosition: newIndex,
    );
  }

  Widget _buildTaskCard(
    KanbanTask task, {
    bool bulkMode = false,
    bool bulkSelected = false,
  }) {
    final theme = Theme.of(context);
    final priorityColor = task.priority != null
        ? Color(int.parse(task.priority!.color.replaceFirst('#', '0xFF')))
        : null;

    return GestureDetector(
      onDoubleTap: bulkMode
          ? null
          : () {
            // Abrir modal de detalhes ao dar duplo clique
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
        constraints: const BoxConstraints(minHeight: 140),
        margin: bulkMode ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                priorityColor?.withValues(alpha: 0.3) ??
                ThemeHelpers.borderColor(context),
            width: priorityColor != null ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bulkMode) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Icon(
                      bulkSelected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!bulkMode)
                  PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
                  itemBuilder: (context) => [
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
                    if (context
                            .read<KanbanController>()
                            .permissions
                            ?.canEditTasks ??
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
                    if (context
                            .read<KanbanController>()
                            .permissions
                            ?.canDeleteTasks ??
                        true)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Excluir',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (task.description != null && task.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                task.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (task.priority != null ||
                task.assignedTo != null ||
                task.dueDate != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (task.priority != null)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: priorityColor?.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          task.priority!.label,
                          style: TextStyle(
                            color: priorityColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (task.assignedTo != null) ...[
                    const Spacer(),
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.1,
                      ),
                      backgroundImage: task.assignedTo!.avatar != null
                          ? NetworkImage(task.assignedTo!.avatar!)
                          : null,
                      child: task.assignedTo!.avatar == null
                          ? Text(
                              task.assignedTo!.name[0].toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                  ],
                  if (task.dueDate != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: _isOverdue(task.dueDate!)
                          ? theme.colorScheme.error
                          : ThemeHelpers.textSecondaryColor(context),
                    ),
                  ],
                  if (task.commentsCount != null &&
                      task.commentsCount! > 0) ...[
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.comment,
                          size: 14,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${task.commentsCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (task.displayTags != null &&
                      task.displayTags!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: task.displayTags!.take(2).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isOverdue(DateTime dueDate) {
    return dueDate.isBefore(DateTime.now());
  }

  void _showTaskActions(BuildContext context, KanbanTask task) {
    final controller = context.read<KanbanController>();
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(context);
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
              },
            ),
            if (controller.permissions?.canDeleteTasks ?? true)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Deletar',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteTask(context, controller, task);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkSelectionDock(
    BuildContext context,
    KanbanController controller,
  ) {
    final theme = Theme.of(context);
    final border = ThemeHelpers.borderColor(context);

    return Material(
      elevation: 12,
      color: ThemeHelpers.cardBackgroundColor(context),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: border.withValues(alpha: 0.45)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.bulkSelectedCount == 0
                          ? 'Nenhum card selecionado'
                          : '${controller.bulkSelectedCount} card(s) selecionado(s)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar modo de seleção',
                    onPressed: controller.bulkDeleting
                        ? null
                        : () => controller.exitBulkSelectionMode(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                children: [
                  OutlinedButton(
                    onPressed: controller.bulkDeleting
                        ? null
                        : controller.bulkSelectAllCurrentTasks,
                    child: const Text('Selecionar todos'),
                  ),
                  OutlinedButton(
                    onPressed: controller.bulkDeleting ||
                            controller.bulkSelectedCount == 0
                        ? null
                        : controller.clearBulkTaskSelection,
                    child: const Text('Limpar'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: controller.bulkDeleting ||
                            controller.bulkSelectedCount == 0
                        ? null
                        : () => _confirmBulkDelete(context, controller),
                    child: const Text('Excluir'),
                  ),
                ],
              ),
              if (controller.bulkDeleting) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
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
