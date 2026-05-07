import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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

  Widget _kanbanBoardChromeHeader(
    BuildContext context,
    KanbanController controller,
  ) {
    final theme = Theme.of(context);
    final accent = _kanbanAccentColor(context);
    final n = controller.displayColumns.length;
    final canCreateTask = controller.permissions?.canCreateTasks ?? true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.view_kanban_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
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
                    const SizedBox(height: 4),
                    Text(
                      'Arraste cards entre colunas.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.35,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (canCreateTask) ...[
                _kanbanQuickAction(
                  context,
                  icon: Icons.add_rounded,
                  label: 'Cria',
                  isPrimary: true,
                  onPressed: () =>
                      _openHeroCreateNegotiationModal(context, controller),
                ),
                const SizedBox(width: 8),
              ],
              _kanbanIconAction(
                context,
                icon: Icons.refresh_rounded,
                tooltip: 'Atualizar',
                onPressed: () => controller.loadBoard(),
              ),
            ],
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

  /// Botão de ação só com ícone (usado pro "Atualizar" no header do quadro).
  /// Mantém alinhamento visual com `_kanbanQuickAction` (mesmo border-radius e
  /// borda) sem ocupar largura com texto.
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
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(
                alpha: isDark ? 0.55 : 0.5,
              ),
            ),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
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
              const SizedBox(height: 6),
              dateLineWidget,
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
      MaterialPageRoute<void>(
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
                                    itemCount: tasks.length,
                                    itemBuilder: (context, index) {
                                      final task = tasks[index];
                                      return _buildDraggableTaskForReorder(
                                        context,
                                        controller,
                                        task,
                                        column.id,
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
                              MaterialPageRoute<void>(
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
        margin: bulkMode ? EdgeInsets.zero : const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: tintedSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              if (leftStripe != null)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          leftStripe.withValues(alpha: 0.95),
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
                  height: 1.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent!.withValues(alpha: 0.0),
                          accent.withValues(alpha: 0.85),
                          accent.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  leftStripe != null ? 14 : 12,
                  16,
                  10,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bulkMode)
                          Padding(
                            padding: const EdgeInsets.only(right: 8, top: 1),
                            child: Icon(
                              bulkSelected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            task.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              height: 1.32,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (task.isCompleted)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 1),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        if (!bulkMode) _buildTaskCardMenu(task),
                      ],
                    ),
                    if (task.description != null &&
                        task.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        task.description!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondaryText,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (task.priority != null ||
                        deadline.isVisible ||
                        hasTags) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (task.priority != null)
                            _priorityChip(task.priority!, priorityColor!),
                          if (deadline.isVisible) _deadlineChip(deadline),
                          if (hasTags)
                            ..._buildTaskTagChips(tags, theme),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _relativeCardTime(task.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (task.commentsCount != null &&
                            task.commentsCount! > 0) ...[
                          const SizedBox(width: 10),
                          Icon(
                            Icons.mode_comment_outlined,
                            size: 12,
                            color: secondaryText,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${task.commentsCount}',
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (task.assignedTo != null) ...[
                          Flexible(
                            child: Text(
                              _firstName(task.assignedTo!.name),
                              style: TextStyle(
                                fontSize: 11,
                                color: secondaryText,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _assigneeAvatar(task.assignedTo!),
                        ],
                      ],
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
          if (context.read<KanbanController>().permissions?.canEditTasks ?? true)
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
          if (context.read<KanbanController>().permissions?.canDeleteTasks ??
              true)
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
        ],
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
    final c = deadline.accentColor(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.32), width: 0.7),
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
