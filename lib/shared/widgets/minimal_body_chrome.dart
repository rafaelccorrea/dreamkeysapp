import 'package:flutter/material.dart';
import '../../core/layout/handheld_layout.dart';
import '../../core/theme/shell_visual_tokens.dart';
import '../../core/theme/theme_helpers.dart';
import 'brand_wordmark_logo.dart';

/// Altura útil da faixa (abaixo da safe area).
const double kMinimalChromeBarHeight = 52;

/// Cabeçalho no corpo: menu minimalista, título e ações agrupadas (sem AppBar).
class MinimalBodyChrome extends StatelessWidget {
  const MinimalBodyChrome({
    super.key,
    required this.title,
    required this.showDrawer,
    this.onBack,
    this.actions,
  });

  final String title;
  final bool showDrawer;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  static const String _brandKeyword = 'intellisys';

  bool get _showScreenTitle {
    final t = title.trim();
    if (t.isEmpty) return false;
    return t.toLowerCase() != _brandKeyword;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kMinimalChromeBarHeight,
          child: Padding(
            padding: EdgeInsets.only(
              left: HandheldLayout.isIosPhone ? 10 : 12,
              right: HandheldLayout.isIosPhone ? 14 : 16,
            ),
            child: Row(
              children: [
                if (showDrawer)
                  Builder(
                    builder: (ctx) => _MinimalMenuButton(
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      tooltip: HandheldLayout.isIosPhone
                          ? 'Abrir menu'
                          : 'Menu',
                    ),
                  )
                else
                  _MinimalBackButton(
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Semantics(
                    header: true,
                    label: title.trim().isEmpty ? 'Intellisys' : title,
                    child: Row(
                      children: [
                        Flexible(
                          flex: 0,
                          fit: FlexFit.loose,
                          child: BrandWordmarkLogo(
                            height: 30,
                            maxWidth: 30 * (200 / 64),
                            variant: BrandWordmarkVariant.appBar,
                          ),
                        ),
                        if (_showScreenTitle) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.35,
                                    height: 1.15,
                                    color: textColor,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _ToolbarActionCluster(children: actions!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Três traços finos — alvo de toque circular discreto.
class _MinimalMenuButton extends StatelessWidget {
  const _MinimalMenuButton({
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = ThemeHelpers.textColor(context).withValues(alpha: 0.82);

    Widget bar(double width) {
      return Container(
        width: width,
        height: 2,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  bar(18),
                  const SizedBox(height: 5),
                  bar(18),
                  const SizedBox(height: 5),
                  bar(14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimalBackButton extends StatelessWidget {
  const _MinimalBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = ThemeHelpers.textColor(context);

    return Tooltip(
      message: 'Voltar',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: c.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cápsula única para ícones à direita (notificações, filtros, etc.).
class _ToolbarActionCluster extends StatelessWidget {
  const _ToolbarActionCluster({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final edge = ThemeHelpers.borderColor(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 42, maxHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ShellVisualTokens.toolbarClusterBorder(context)),
        color: ShellVisualTokens.toolbarClusterFill(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 1,
                  height: 22,
                  color: edge.withValues(alpha: 0.28),
                ),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Ícone de ação para usar dentro de [_ToolbarActionCluster] (ex.: filtros).
class ChromeToolbarIconButton extends StatelessWidget {
  const ChromeToolbarIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = ThemeHelpers.textColor(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 21, color: c.withValues(alpha: 0.9)),
          ),
        ),
      ),
    );
  }
}
