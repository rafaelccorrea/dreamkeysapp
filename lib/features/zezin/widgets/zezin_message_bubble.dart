import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/zezin_models.dart';

/// Bolha de mensagem do chat com o Zezin — mesma gramática do chat do app
/// (`ChatMessageBubble`): usuário à direita com a cor da marca; assistente à
/// esquerda em card com header (avatar + nome). O tom violeta identifica a IA
/// (cor por significado — paridade com o web, que usa #8B5CF6 para o Zezin).
class ZezinMessageBubble extends StatelessWidget {
  const ZezinMessageBubble({super.key, required this.message});

  final ZezinChatMessage message;

  Color _aiTone(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
  }

  Color _brand(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = message.isUser;
    final tone = _aiTone(context);
    final brand = _brand(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isUser ? brand : ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 5),
          bottomRight: Radius.circular(isUser ? 5 : 18),
        ),
        border: isUser
            ? null
            : Border.all(
                color: message.isError
                    ? danger.withValues(alpha: 0.4)
                    : ThemeHelpers.borderLightColor(context),
              ),
        boxShadow: ThemeHelpers.cardShadow(context, strength: 0.6),
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isUser) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(
                      colors: [
                        tone.withValues(alpha: isDark ? 0.32 : 0.2),
                        tone.withValues(alpha: isDark ? 0.14 : 0.08),
                      ],
                    ),
                  ),
                  child: Icon(LucideIcons.bot, size: 13, color: tone),
                ),
                const SizedBox(width: 7),
                Text(
                  'Zezin',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                if (message.isStreaming) ...[
                  const SizedBox(width: 8),
                  ZezinTypingDots(color: tone, size: 4),
                ],
              ],
            ),
            const SizedBox(height: 7),
          ],
          if (!isUser && message.content.isEmpty && message.isStreaming)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ZezinTypingDots(color: tone),
            )
          else
            SelectableText.rich(
              TextSpan(
                text: message.content,
                children: [
                  if (message.isStreaming && message.content.isNotEmpty)
                    TextSpan(
                      text: ' ▍',
                      style: TextStyle(color: tone),
                    ),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isUser
                    ? Colors.white
                    : message.isError
                        ? danger
                        : ThemeHelpers.textColor(context),
                height: 1.45,
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isUser) const SizedBox(width: 44),
          Flexible(child: bubble),
          if (!isUser) const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// Três pontinhos animados ("digitando…") — usados na bolha do assistente
/// enquanto a resposta ainda não começou a chegar.
class ZezinTypingDots extends StatefulWidget {
  const ZezinTypingDots({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  State<ZezinTypingDots> createState() => _ZezinTypingDotsState();
}

class _ZezinTypingDotsState extends State<ZezinTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_controller.value - i * 0.18) % 1.0;
            final wave = t < 0 ? 0.0 : (t < 0.5 ? t * 2 : (1 - t) * 2);
            final alpha = 0.3 + 0.7 * wave.clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : widget.size * 0.7),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: alpha),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
