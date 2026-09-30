import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/bio_page_model.dart';
import 'public_site_shared.dart';

/// Bottom sheet de criar/editar um link da página Link in Bio.
///
/// Devolve o [BioPageLink] resultante via `Navigator.pop(result)` — a página
/// decide onde encaixar (novo no fim, edição no lugar). Validação local:
/// rótulo obrigatório (máx. 80) e URL obrigatória (https:// completado
/// automaticamente quando falta o esquema).
///
/// 29/09/2026 (integ-01): o botão de captação (`kind: lead_form`, criado no
/// web) agora sobrevive ao "Salvar links" do app e aparece na lista. Ele não
/// tem URL — o web esconde o campo e manda `url: ''` —, então aqui a edição
/// dele muda só o rótulo: o campo de URL some e não é validado. O resto
/// (tipo, cor, ícone, subtítulo) segue do original pelo `copyWith`. Criar um
/// botão de captação novo pelo app fica para o integ-30.
///
/// Revisão 30/09/2026: teto de 88% da altura que sobra acima do teclado,
/// cabeçalho da casa (título à esquerda, fechar à direita), corpo numa
/// rolagem só e rodapé Cancelar (neutro) / confirmar (verde) — que desce
/// para o fim da rolagem quando falta altura (paisagem, teclado num
/// aparelho baixo). Prévia ao vivo do botão como o visitante vê (cores do
/// cliente = dado, texto legível por [siteOnColor]); erro no próprio campo.
class BioLinkEditSheet extends StatefulWidget {
  final BioPageLink? initial;

  const BioLinkEditSheet({super.key, this.initial});

  static Future<BioPageLink?> show(
    BuildContext context, {
    BioPageLink? initial,
  }) {
    return showModalBottomSheet<BioPageLink>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => BioLinkEditSheet(initial: initial),
    );
  }

  @override
  State<BioLinkEditSheet> createState() => _BioLinkEditSheetState();
}

class _BioLinkEditSheetState extends State<BioLinkEditSheet> {
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;
  String? _labelError;
  String? _urlError;

  bool get _isEditing => widget.initial != null;

  /// Editando um botão de captação existente (sem URL).
  bool get _isLeadForm => widget.initial?.isLeadForm == true;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initial?.label ?? '');
    _urlController = TextEditingController(text: widget.initial?.url ?? '');
  }

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String _normalizeUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return v;
    final hasScheme =
        v.startsWith('http://') || v.startsWith('https://');
    return hasScheme ? v : 'https://$v';
  }

  void _submit() {
    final label = _labelController.text.trim();
    final isLeadForm = _isLeadForm;
    final url = isLeadForm ? '' : _normalizeUrl(_urlController.text);

    String? labelError;
    String? urlError;
    if (label.isEmpty) labelError = 'Informe o texto do botão';
    if (label.length > 80) labelError = 'Máximo de 80 caracteres';
    // Botão de captação não tem URL: nada a validar (o back aceita url
    // vazia só nesse tipo, e o toJson do modelo já força `url: ''`).
    if (!isLeadForm) {
      if (url.isEmpty) {
        urlError = 'Informe o endereço do link';
      } else if (Uri.tryParse(url)?.host.isNotEmpty != true) {
        urlError = 'Endereço inválido — ex.: https://wa.me/5511999999999';
      }
    }

    if (labelError != null || urlError != null) {
      setState(() {
        _labelError = labelError;
        _urlError = urlError;
      });
      return;
    }

    final base = widget.initial ??
        BioPageLink(
          id: 'lk-${DateTime.now().microsecondsSinceEpoch}',
          label: '',
          url: '',
          order: 0,
          isActive: true,
        );
    Navigator.of(context).pop(
      isLeadForm
          ? base.copyWith(label: label)
          : base.copyWith(label: label, url: url),
    );
  }

  /// O link como vai ficar — só para a prévia ao vivo. O que volta para a
  /// página continua sendo o de [_submit] (`base.copyWith` do original).
  BioPageLink get _previewLink {
    final base =
        widget.initial ??
        const BioPageLink(id: '', label: '', url: '', order: 0, isActive: true);
    final label = _labelController.text.trim();
    return _isLeadForm
        ? base.copyWith(label: label)
        : base.copyWith(label: label, url: _normalizeUrl(_urlController.text));
  }

  /// Violeta — o acento do Link in Bio (identidade de "bio/criador"). O
  /// vermelho da marca não entra nesta feature; aqui ele fica só na tinta
  /// dos erros de validação (dentro do próprio campo).
  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.purpleDarkMode
      : AppColors.status.purple;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final room = mq.size.height - keyboard;
    final maxHeight = math.max(0.0, room * 0.88);
    // Pouca altura (paisagem, teclado num aparelho baixo): o rodapé desce
    // para o fim da rolagem e a frase do cabeçalho some — fixos, eles
    // espremeriam os campos. Só o ÚLTIMO filho de cada coluna muda: o campo
    // em edição não é recriado e não perde o foco.
    final footerInScroll = room < 420;
    final compactHeader = room < 520;
    final footer = _footer(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: siteHairline(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, compact: compactHeader),
              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [_body(context), if (footerInScroll) footer],
                  ),
                ),
              ),
              if (!footerInScroll) footer,
            ],
          ),
        ),
      ),
    );
  }

  /// Pegador + cabeçalho da casa: selo do tipo, título à esquerda, fechar à
  /// direita e um filete embaixo.
  Widget _header(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final title = _isLeadForm
        ? 'Editar botão de captação'
        : (_isEditing ? 'Editar link' : 'Novo link');
    final sub = _isEditing
        ? 'A mudança entra na lista agora e vai ao ar quando você salvar os '
              'links.'
        : 'O link entra no fim da lista — depois é só arrastar para mudar a '
              'ordem.';
    final IconData icon;
    if (_isLeadForm) {
      icon = LucideIcons.userRoundPlus;
    } else if (_isEditing) {
      icon = LucideIcons.pencilLine;
    } else {
      icon = LucideIcons.plus;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderColor(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: siteInk(context, accent), size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 3),
                        Text(
                          sub,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SheetCloseButton(onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Container(height: 1, color: ThemeHelpers.borderLightColor(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLeadForm) ...[
            _leadFormNote(context),
            const SizedBox(height: 14),
          ],
          SiteFilledField(
            controller: _labelController,
            label: 'Texto do botão',
            // Mesmo placeholder do web para cada tipo de botão.
            hint: _isLeadForm ? 'Quero ser atendido' : 'Fale no WhatsApp',
            icon: LucideIcons.type,
            maxLength: 80,
            accent: accent,
            errorText: _labelError,
            textCapitalization: TextCapitalization.sentences,
            // Cada tecla redesenha a prévia; o erro some ao corrigir.
            onChanged: (_) => setState(() => _labelError = null),
          ),
          if (!_isLeadForm) ...[
            const SizedBox(height: 12),
            SiteFilledField(
              controller: _urlController,
              label: 'Endereço (link)',
              hint: 'https://wa.me/5511999999999',
              icon: LucideIcons.link,
              keyboardType: TextInputType.url,
              accent: accent,
              errorText: _urlError,
              onChanged: (_) => setState(() => _urlError = null),
            ),
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(LucideIcons.info, size: 13, color: secondary),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Pode colar sem o https:// — ele entra sozinho. WhatsApp: '
                    'wa.me/55 + DDD + número.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _preview(context),
        ],
      ),
    );
  }

  /// No lugar do endereço, o que o botão de captação faz — mesma explicação
  /// do "Ação do botão" do web, sem mandar ninguém para o painel.
  Widget _leadFormNote(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(context);
    final ink = siteInk(context, accent);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.userRoundPlus, size: 16, color: ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Botão de captação',
                  style: TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Abre um formulário de nome e telefone no lugar de um link '
                  '— cada envio vira um card no funil de leads da página. Não '
                  'usa endereço: aqui você muda só o texto do botão.',
                  style: TextStyle(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Prévia ao vivo do botão como o visitante vê. Cor escolhida pelo cliente
  /// = DADO: o botão sai como na página (degradê quando há segunda cor) e o
  /// texto vem de [siteOnColor]; sem cor, o violeta da tela. O ícone segue a
  /// regra da página pública (captação, escolhido no web, ou pelo endereço).
  Widget _preview(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = _accent(context);
    final link = _previewLink;
    final c1 = siteParseHexColor(link.color);
    final c2 = siteParseHexColor(link.color2);
    final List<Color>? paint = c1 == null ? null : [c1, c2 ?? c1];
    final fg = paint != null
        ? siteOnColor(Color.lerp(paint.first, paint.last, 0.5)!)
        : siteInk(context, accent);
    final typed = link.label.trim();
    final subtitle = (link.subtitle ?? '').trim();
    final String iconNote;
    if (link.isLeadForm) {
      iconNote = 'Ícone de captação — o mesmo da página.';
    } else if ((link.icon ?? '').trim().isNotEmpty) {
      iconNote = 'Ícone escolhido no painel web.';
    } else {
      iconNote = 'O ícone muda sozinho conforme o endereço.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SiteSubsectionHeader(
          label: 'Como aparece na página',
          icon: LucideIcons.smartphone,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: siteFieldFill(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: paint == null
                      ? null
                      : LinearGradient(colors: paint),
                  color: paint == null
                      ? accent.withValues(alpha: isDark ? 0.2 : 0.12)
                      : null,
                  border: paint == null
                      ? Border.all(color: accent.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(bioLinkIcon(link), size: 16, color: fg),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            typed.isEmpty ? 'Texto do botão' : typed,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: typed.isEmpty
                                  ? fg.withValues(alpha: 0.55)
                                  : fg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.85),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          iconNote,
          style: TextStyle(color: secondary, fontSize: 11.5, height: 1.35),
        ),
      ],
    );
  }

  /// Rodapé: Cancelar neutro (o tema pintaria de vermelho) e confirmar
  /// verde. Lado a lado quando cabem; em 320dp com fonte grande, o
  /// confirmar vai em cima, na largura inteira.
  Widget _footer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Confirmar = verde escurecido até o rótulo branco passar de 4,5:1 (o
    // verde de status cru dava 3:1 no claro e 2:1 no escuro).
    final green = siteSolid(
      isDark ? AppColors.status.greenDarkMode : AppColors.status.green,
    );
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 14 + safeBottom),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SiteActionPair(
        primaryFlex: 2,
        minSecondary: 84,
        primary: FilledButton.icon(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
          icon: const Icon(LucideIcons.check, size: 17),
          label: SiteButtonLabel(_isEditing ? 'Aplicar' : 'Adicionar link'),
        ),
        secondary: OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: ThemeHelpers.textSecondaryColor(context),
            side: BorderSide(color: ThemeHelpers.borderColor(context)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          ),
          child: const SiteButtonLabel('Cancelar'),
        ),
      ),
    );
  }
}

/// Fechar do cabeçalho — quadrado neutro com filete, sem vermelho.
class _SheetCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SheetCloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
    );
    return Tooltip(
      message: 'Fechar',
      child: Material(
        color: Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              LucideIcons.x,
              size: 17,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
      ),
    );
  }
}
