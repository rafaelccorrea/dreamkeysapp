import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helpers.dart';

/// Editor premium de foto **travado em 1:1**.
///
/// Substitui o cropper nativo (`image_cropper`) no fluxo de criação de
/// imóvel: corretores precisam de fotos quadradas para a fila de
/// aprovação aceitar e a vitrine renderizar bem. Antes, o picker
/// oferecia múltiplas proporções (3:2, 4:3, 16:9) — corretores
/// frequentemente escolhiam a errada e a foto era reprovada na fila.
///
/// **Comportamento desta tela**:
/// - Lock 1:1: a janela de crop é um quadrado fixo no centro.
/// - Pan + pinch zoom da imagem (até 8x).
/// - Botão "Reposicionar" pra voltar ao enquadramento inicial.
/// - Captura via `RepaintBoundary.toImage(pixelRatio)` — gera um PNG
///   em ~1024px de lado mantendo qualidade (suficiente pra publicação
///   no portal e marca-d'água).
///
/// **Abordagem técnica de crop**:
/// O quadrado de crop é um `SizedBox(maxSide × maxSide)` com
/// `RepaintBoundary` + `ClipRect` em volta de um `InteractiveViewer`
/// não-restrito. A imagem entra com `BoxFit.cover` no quadrado: já
/// começa preenchendo. O user pode dar pinch/zoom/drag pra ajustar o
/// que vai ficar visível. Ao confirmar, capturamos exatamente o que
/// está dentro do `RepaintBoundary` — que é exatamente o quadrado
/// visível pelo usuário (o `ClipRect` corta tudo o que sobra fora).
class SquarePhotoEditorPage extends StatefulWidget {
  const SquarePhotoEditorPage({
    super.key,
    required this.sourceFile,
    this.title = 'Recortar em quadrado',
    this.eyebrow = 'PUBLICAÇÃO · 1:1',
    this.subtitle =
        'Arraste a foto e use 2 dedos pra ajustar o zoom. Imóveis ficam melhores em quadrado.',
    this.outputSize = 1024,
  });

  final File sourceFile;
  final String title;
  final String eyebrow;
  final String subtitle;

  /// Tamanho do lado da imagem final (em pixels).
  final int outputSize;

  @override
  State<SquarePhotoEditorPage> createState() => _SquarePhotoEditorPageState();
}

class _SquarePhotoEditorPageState extends State<SquarePhotoEditorPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey _captureKey = GlobalKey();
  final TransformationController _transformController =
      TransformationController();

  bool _exporting = false;
  ui.Image? _decoded;
  Object? _decodeError;

  late final AnimationController _hintAnim;

  @override
  void initState() {
    super.initState();
    _hintAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _decodeImage();
  }

  /// Decodifica a imagem original em background pra termos width/height
  /// reais (úteis pra mostrar resolução na pill informativa).
  Future<void> _decodeImage() async {
    try {
      final bytes = await widget.sourceFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _decoded = frame.image);
    } catch (e) {
      if (!mounted) return;
      setState(() => _decodeError = e);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    _hintAnim.dispose();
    _decoded?.dispose();
    super.dispose();
  }

  void _resetTransform() {
    _transformController.value = Matrix4.identity();
    setState(() {});
  }

  /// Captura o `RepaintBoundary` (que envolve só o quadrado visível
  /// pelo user) em um PNG no diretório temporário.
  Future<File?> _captureSquare() async {
    final boundary = _captureKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;

    // Aumenta o pixelRatio pra entregar ~outputSize logical pixels —
    // independente do tamanho do quadrado renderizado em tela.
    final logicalSide = boundary.size.shortestSide;
    final ratio = (widget.outputSize / logicalSide).clamp(1.0, 5.0);

    final image = await boundary.toImage(pixelRatio: ratio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return null;
    final pngBytes = byteData.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final fileName =
        'crop_${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(widget.sourceFile.path)}.png';
    final out = File(p.join(dir.path, fileName));
    await out.writeAsBytes(pngBytes, flush: true);
    return out;
  }

  Future<void> _confirm() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final out = await _captureSquare();
      if (!mounted) return;
      Navigator.of(context).pop<File?>(out);
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Não foi possível processar a foto: $e',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.primary.primary;

    return PopScope(
      canPop: !_exporting,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF050505) : const Color(0xFFEFEFF1),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(theme, isDark, accent),
              Expanded(child: _buildEditorArea(theme, isDark, accent)),
              _buildBottomBar(theme, isDark, accent),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  Widget _buildTopBar(ThemeData theme, bool isDark, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconChipButton(
            icon: Icons.close_rounded,
            onTap:
                _exporting ? null : () => Navigator.of(context).pop<File?>(null),
            tooltip: 'Cancelar',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.eyebrow,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black,
                    height: 1.05,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _IconChipButton(
            icon: Icons.refresh_rounded,
            onTap: _exporting ? null : _resetTransform,
            tooltip: 'Reposicionar',
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  Widget _buildEditorArea(ThemeData theme, bool isDark, Color accent) {
    if (_decodeError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível abrir esta imagem.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Quadrado fixo, ocupando o lado menor menos um pequeno padding.
        final maxSide =
            (constraints.biggest.shortestSide - 24).clamp(0.0, 600.0);

        return Center(
          child: SizedBox(
            width: maxSide,
            height: maxSide,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Frame de captura (RepaintBoundary + ClipRect em volta
                // do InteractiveViewer). É EXATAMENTE o que vai sair na
                // foto final — o que o user vê dentro desse quadrado é
                // o que será salvo.
                Positioned.fill(
                  child: RepaintBoundary(
                    key: _captureKey,
                    child: ClipRect(
                      child: ColoredBox(
                        color: Colors.black,
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 0.5,
                          maxScale: 8,
                          panEnabled: true,
                          // `constrained: false` + boundary infinita
                          // permitem que o user mova/escale livremente.
                          // O ClipRect/RepaintBoundary é quem decide o
                          // que sai na foto final.
                          constrained: false,
                          boundaryMargin:
                              const EdgeInsets.all(double.infinity),
                          child: SizedBox(
                            width: maxSide,
                            height: maxSide,
                            child: Image.file(
                              widget.sourceFile,
                              // `cover`: a imagem JÁ entra preenchendo o
                              // quadrado. Sem letterbox preto. O user só
                              // ajusta zoom/posição se quiser.
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Borda accent + cantos reforçados + grade rule-of-thirds
                // (overlay puramente visual, IgnorePointer pra não roubar
                // gestos do InteractiveViewer abaixo).
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CropFramePainter(accent: accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────
  Widget _buildBottomBar(ThemeData theme, bool isDark, Color accent) {
    final w = _decoded?.width;
    final h = _decoded?.height;
    final dimsLabel = (w != null && h != null) ? '$w × $h px' : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pill "dica + dimensões"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _hintAnim,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(_hintAnim.value * 4 - 2, 0),
                    child: Icon(
                      Icons.swipe_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.subtitle,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.85)
                          : Colors.black.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
                if (dimsLabel != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      dimsLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Botões de ação
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _exporting
                        ? null
                        : () => Navigator.of(context).pop<File?>(null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : Colors.black,
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.18)
                            : Colors.black.withValues(alpha: 0.18),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _exporting ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 22),
                    label: Text(
                      _exporting ? 'Salvando…' : 'Concluir',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Borda accent do quadrado + cantos reforçados + grade rule-of-thirds.
class _CropFramePainter extends CustomPainter {
  _CropFramePainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Borda fina branca semitransparente
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(rect, border);

    // Cantos reforçados em accent
    final corner = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    const cornerLen = 22.0;
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(cornerLen, 0),
      corner,
    );
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(0, cornerLen),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - cornerLen, 0),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerLen),
      corner,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerLen, size.height),
      corner,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerLen),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cornerLen, size.height),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - cornerLen),
      corner,
    );

    // Rule-of-thirds — linhas suaves
    final thirds = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final third = size.width / 3;
    canvas.drawLine(
      Offset(third, 0),
      Offset(third, size.height),
      thirds,
    );
    canvas.drawLine(
      Offset(third * 2, 0),
      Offset(third * 2, size.height),
      thirds,
    );
    canvas.drawLine(
      Offset(0, third),
      Offset(size.width, third),
      thirds,
    );
    canvas.drawLine(
      Offset(0, third * 2),
      Offset(size.width, third * 2),
      thirds,
    );
  }

  @override
  bool shouldRepaint(_CropFramePainter old) => old.accent != accent;
}

/// Botão circular discreto usado na top bar (fechar / reset).
class _IconChipButton extends StatelessWidget {
  const _IconChipButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = onTap == null;
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.white.withValues(alpha: disabled ? 0.04 : 0.08)
                : Colors.black.withValues(alpha: disabled ? 0.04 : 0.06),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: disabled
                ? (isDark ? Colors.white38 : Colors.black38)
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
