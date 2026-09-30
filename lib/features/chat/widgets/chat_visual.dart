import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

/// Peças visuais do chat interno (30/09/2026).
///
/// Eixo AZUL, como o chat interno do web (comunicação é azul; o vermelho da
/// marca fica para o botão flutuante e para o que é destrutivo). A gramática
/// é a do WhatsApp do app — linha flush, avatar, hora curta, não lidas em
/// destaque —, mas no azul, para que ninguém confunda a conversa com um
/// colega com a conversa com um cliente.
///
/// Contraste medido: `message.infoText` (#2563EB) dá 5,2:1 no branco e
/// 4,5:1 no cinza de campo (#EEF0F3); `message.infoTextDarkMode` (#4A90E2)
/// dá 5,6:1 no cartão escuro. O selo de não lidas usa #2563EB nos dois temas
/// porque o número é branco (5,2:1) — o #4A90E2 com branco ficaria em 3,3:1.

/// Tinta azul do chat para TEXTO e ícone pequeno (≥ 4,5:1 nos dois temas).
Color chatInk(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.message.infoTextDarkMode
      : AppColors.message.infoText;
}

/// Preenchimento do selo de não lidas e do botão de enviar (texto branco).
Color chatSolid(BuildContext context) => AppColors.message.infoText;

/// Fundo do campo de busca e do campo de mensagem — o mesmo cinza sólido
/// dos campos do app (fill terciário), nunca branco sobre branco.
Color chatFieldFill(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;
}

/// Tom de linha selecionada (tablet, conversa aberta ao lado da lista).
Color chatSelectedFill(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return chatInk(context).withValues(alpha: isDark ? 0.14 : 0.07);
}

/// Hora curta da lista, como no WhatsApp: "14:32" hoje, "Ontem", o dia da
/// semana até 6 dias atrás ("Segunda") e a data ("28/08/26") depois disso.
String chatShortTime(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return DateFormat('HH:mm').format(local);
  if (diff == 1) return 'Ontem';
  if (diff < 7) {
    // "segunda-feira" → "Segunda".
    final wd = DateFormat('EEEE', 'pt_BR').format(local).split('-').first;
    return wd.isEmpty ? '' : wd[0].toUpperCase() + wd.substring(1);
  }
  return DateFormat('dd/MM/yy').format(local);
}

/// Hora da bolha ("14:32").
String chatBubbleTime(DateTime date) =>
    DateFormat('HH:mm').format(date.toLocal());

final RegExp _loneUrl = RegExp(r'^https?://\S+$', caseSensitive: false);

/// Figurinha ou GIF enviados pelo web chegam como uma URL solta no texto
/// (GIPHY). Devolve a URL quando o conteúdo é só isso — a bolha mostra a
/// imagem, e a lista escreve "Figurinha"/"GIF" em vez do endereço.
String? chatInlineGifUrl(String content) {
  final s = content.trim();
  if (!_loneUrl.hasMatch(s)) return null;
  final lower = s.toLowerCase();
  if (lower.contains('giphy.com') || lower.split('#').first.endsWith('.gif')) {
    return s;
  }
  return null;
}

/// Figurinha × GIF (mesma regra do web): marca `#figurinha` no envio e, nas
/// antigas, o tamanho `200w.gif` que só o seletor de figurinhas usa.
bool chatIsSticker(String url) {
  final lower = url.toLowerCase();
  return lower.contains('#figurinha') || lower.contains('/200w.gif');
}

/// Texto da prévia na lista: tira o marcador antigo de mensagem apagada que
/// vem gravado no banco (um emoji — a interface não usa emoji) e troca a URL
/// de figurinha/GIF por uma palavra.
String chatPreviewText(String? raw) {
  var s = (raw ?? '').trim();
  if (s.startsWith('\u{1F6AB}')) {
    s = s.substring('\u{1F6AB}'.length).trim();
  }
  if (s.isEmpty) return '';
  final gif = chatInlineGifUrl(s);
  if (gif != null) return chatIsSticker(gif) ? 'Figurinha' : 'GIF';
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

/// Selo de não lidas (número branco sobre o azul sólido). Altura pela fonte:
/// com texto a 130% o número não é cortado.
class ChatUnreadBadge extends StatelessWidget {
  final int count;

  const ChatUnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 3),
      decoration: BoxDecoration(
        color: chatSolid(context),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Filete de linha flush (hairline do app).
BorderSide chatHairline(BuildContext context) =>
    BorderSide(color: ThemeHelpers.borderLightColor(context), width: 0.8);
