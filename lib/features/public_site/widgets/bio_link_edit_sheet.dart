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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Violeta — o acento do Link in Bio (identidade de "bio/criador").
    // O vermelho da marca não entra nesta feature; aqui ele fica só nos
    // textos de erro de validação.
    final accent = isDark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.3)),
                      ),
                      child: Icon(
                        _isEditing ? LucideIcons.pencilLine : LucideIcons.plus,
                        color: accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isLeadForm
                                ? 'Editar botão de captação'
                                : (_isEditing ? 'Editar link' : 'Novo link'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isEditing
                                ? 'As alterações entram na página quando '
                                      'você salvar a lista.'
                                : 'O botão entra no fim da lista — arraste '
                                      'depois para reordenar.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SiteFilledField(
                  controller: _labelController,
                  label: 'Texto do botão',
                  // Mesmo placeholder do web para cada tipo de botão.
                  hint: _isLeadForm ? 'Quero ser atendido' : 'Fale no WhatsApp',
                  icon: LucideIcons.type,
                  maxLength: 80,
                  accent: accent,
                  onChanged: (_) {
                    if (_labelError != null) {
                      setState(() => _labelError = null);
                    }
                  },
                ),
                if (_labelError != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    _labelError!,
                    style: TextStyle(
                      color: danger,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_isLeadForm)
                  // No lugar da URL, o que o botão faz — mesma explicação do
                  // "Ação do botão" do web, sem mandar ninguém para o painel.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          LucideIcons.userRoundPlus,
                          size: 16,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Abre um formulário de captação (nome e telefone) '
                          'no lugar de um link — o lead vira card no funil de '
                          'leads da página. Este botão não usa URL.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  SiteFilledField(
                    controller: _urlController,
                    label: 'Endereço (URL)',
                    hint: 'https://wa.me/5511999999999',
                    icon: LucideIcons.link,
                    keyboardType: TextInputType.url,
                    accent: accent,
                    onChanged: (_) {
                      if (_urlError != null) {
                        setState(() => _urlError = null);
                      }
                    },
                  ),
                  if (_urlError != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      _urlError!,
                      style: TextStyle(
                        color: danger,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: secondary,
                          side: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('Cancelar', softWrap: false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _submit,
                        // Confirmar = verde (o vermelho da marca fica na
                        // identidade do cabeçalho, nunca na ação).
                        style: FilledButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        icon: const Icon(LucideIcons.check, size: 17),
                        label: Text(
                          _isEditing ? 'Aplicar' : 'Adicionar link',
                          softWrap: false,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
