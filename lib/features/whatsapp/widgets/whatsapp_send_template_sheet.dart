import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/whatsapp_models.dart';
import '../services/whatsapp_service.dart';

/// Bottom-sheet **Enviar template** — reabre a janela de 24h da API oficial.
///
/// Paridade com `SendWhatsAppTemplate.tsx` do painel: tenta listar os
/// templates aprovados (`GET /whatsapp/templates`, exige
/// `whatsapp:manage_config`); sem a permissão ou sem templates, cai na
/// digitação manual do nome + variáveis ({{1}}, {{2}}, …) — exatamente o
/// payload de `POST /whatsapp/send-template`.
///
/// Fecha com `true` quando o envio deu certo.
class WhatsAppSendTemplateSheet extends StatefulWidget {
  final String phoneNumber;
  final String? clientId;

  const WhatsAppSendTemplateSheet({
    super.key,
    required this.phoneNumber,
    this.clientId,
  });

  /// Abre o sheet e devolve `true` se um template foi enviado.
  static Future<bool> show(
    BuildContext context, {
    required String phoneNumber,
    String? clientId,
  }) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => WhatsAppSendTemplateSheet(
        phoneNumber: phoneNumber,
        clientId: clientId,
      ),
    );
    return sent == true;
  }

  @override
  State<WhatsAppSendTemplateSheet> createState() =>
      _WhatsAppSendTemplateSheetState();
}

class _WhatsAppSendTemplateSheetState extends State<WhatsAppSendTemplateSheet> {
  final _nameController = TextEditingController();
  final List<TextEditingController> _paramControllers = [];

  bool _loadingTemplates = true;
  List<WhatsAppTemplate> _templates = const [];
  WhatsAppTemplate? _selected;
  bool _manualMode = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _paramControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final res = await WhatsAppService.instance.getTemplates();
    if (!mounted) return;
    setState(() {
      _loadingTemplates = false;
      if (res.success && res.data != null && res.data!.isNotEmpty) {
        _templates = res.data!.where((t) => t.isApproved).toList();
        if (_templates.isEmpty) _manualMode = true;
      } else {
        // 403 (sem whatsapp:manage_config) ou sem templates → modo manual.
        _manualMode = true;
      }
    });
  }

  void _selectTemplate(WhatsAppTemplate t) {
    setState(() {
      _selected = t;
      _nameController.text = t.name;
      final needed = t.bodyVariableCount;
      while (_paramControllers.length < needed) {
        _paramControllers.add(TextEditingController());
      }
    });
  }

  void _addParam() {
    setState(() => _paramControllers.add(TextEditingController()));
  }

  void _removeParam(int index) {
    setState(() {
      _paramControllers.removeAt(index).dispose();
    });
  }

  bool get _canSend =>
      !_sending && _nameController.text.trim().isNotEmpty;

  Future<void> _send() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _sending) return;
    setState(() => _sending = true);
    final parameters = _paramControllers
        .map((c) => c.text.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    final res = await WhatsAppService.instance.sendTemplate(
      to: widget.phoneNumber,
      templateName: name,
      parameters: parameters,
      clientId: widget.clientId,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao enviar template'),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? AppColors.status.errorDarkMode
              : AppColors.status.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final mq = MediaQuery.of(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
        ),
      ),
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            _buildHeader(context, accent),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loadingTemplates)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 26),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: accent),
                          ),
                        ),
                      )
                    else ...[
                      if (_templates.isNotEmpty) ...[
                        _sectionLabel(context, 'TEMPLATE APROVADO'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in _templates)
                              _templateChip(context, t, accent),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: ThemeHelpers.borderLightColor(context),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'ou digite o nome',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: ThemeHelpers.borderLightColor(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ] else if (_manualMode) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (isDark
                                    ? AppColors.status.infoDarkMode
                                    : AppColors.status.info)
                                .withValues(alpha: isDark ? 0.14 : 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (isDark
                                      ? AppColors.status.infoDarkMode
                                      : AppColors.status.info)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(LucideIcons.info,
                                  size: 16,
                                  color: isDark
                                      ? AppColors.status.infoDarkMode
                                      : AppColors.status.info),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Digite o nome exato de um template aprovado '
                                  'na Meta (ex.: boas_vindas). A lista completa '
                                  'fica no painel web.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ThemeHelpers.textColor(context),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _sectionLabel(context, 'NOME DO TEMPLATE'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        onChanged: (_) => setState(() => _selected = null),
                        style: TextStyle(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        decoration: _fieldDecoration(
                          context,
                          hint: 'ex.: boas_vindas',
                          icon: LucideIcons.fileText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                              child: _sectionLabel(
                                  context, 'VARIÁVEIS DO TEMPLATE')),
                          TextButton.icon(
                            onPressed: _addParam,
                            icon: const Icon(LucideIcons.plus, size: 15),
                            label: const Text('Adicionar'),
                            style: TextButton.styleFrom(
                              foregroundColor: accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_paramControllers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Preencha na ordem em que aparecem no corpo '
                            '({{1}}, {{2}}, …). Opcional.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secondary.withValues(alpha: 0.9),
                              height: 1.3,
                            ),
                          ),
                        ),
                      for (var i = 0; i < _paramControllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _paramControllers[i],
                                  style: TextStyle(
                                    color: ThemeHelpers.textColor(context),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                  decoration: _fieldDecoration(
                                    context,
                                    hint: 'Valor de {{${i + 1}}}',
                                    icon: LucideIcons.braces,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkResponse(
                                radius: 18,
                                onTap: () => _removeParam(i),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(LucideIcons.trash2,
                                      size: 16, color: secondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.45),
                  ),
                ),
              ),
              child: FilledButton.icon(
                onPressed: _canSend ? _send : null,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.sendHorizontal, size: 17),
                label: Text(
                  _sending ? 'Enviando…' : 'Enviar template',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 10, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.badgeCheck, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enviar template',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Para ${formatWhatsAppPhone(widget.phoneNumber)} · reabre a '
                  'janela de 24h',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(false),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 10.5,
          ),
    );
  }

  Widget _templateChip(
      BuildContext context, WhatsAppTemplate t, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selected = _selected?.name == t.name;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    return InkWell(
      onTap: () => _selectTemplate(t),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
              : fieldFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected ? accent : ThemeHelpers.borderLightColor(context),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.fileText, size: 13, color: fg),
            const SizedBox(width: 6),
            Text(
              t.name,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 12.5,
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (t.language.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                t.language,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String hint,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: secondary.withValues(alpha: 0.75),
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      prefixIcon: Icon(icon, size: 17, color: secondary),
      filled: true,
      fillColor: fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }
}
