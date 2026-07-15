import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/mcmv_models.dart';

/// Bottom-sheet **Adicionar à blacklist** — mesmo DNA do modal de filtros do
/// Kanban (seções flush + pills de campo). Exige ao menos um identificador
/// (CPF, email ou telefone) e um motivo, espelhando a validação do backend.
class McmvBlacklistAddSheet extends StatefulWidget {
  const McmvBlacklistAddSheet({super.key});

  @override
  State<McmvBlacklistAddSheet> createState() => _McmvBlacklistAddSheetState();
}

class _McmvBlacklistAddSheetState extends State<McmvBlacklistAddSheet> {
  final _cpfController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _reasonController = TextEditingController();

  bool _isPermanent = false;
  DateTime? _expiresAt;

  @override
  void dispose() {
    _cpfController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  bool get _hasIdentifier =>
      _cpfController.text.trim().isNotEmpty ||
      _emailController.text.trim().isNotEmpty ||
      _phoneController.text.trim().isNotEmpty;

  bool get _canSubmit => _hasIdentifier && _reasonController.text.trim().isNotEmpty;

  Color _fieldFill(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() => _expiresAt = picked);
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(McmvBlacklistCreateRequest(
      cpf: _cpfController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      reason: _reasonController.text.trim(),
      isPermanent: _isPermanent,
      expiresAt: _isPermanent ? null : _expiresAt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final cIdent =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cMotivo =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final cVigencia =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final mq = MediaQuery.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              _buildHeader(context, danger),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                      20, 4, 20, 24 + mq.viewInsets.bottom),
                  children: [
                    _section(
                      context,
                      accent: cIdent,
                      label: 'Identificadores',
                      hint: 'Preencha ao menos um: CPF, email ou telefone.',
                      first: true,
                      child: Column(
                        children: [
                          _textControl(
                            context,
                            accent: cIdent,
                            icon: Icons.badge_outlined,
                            controller: _cpfController,
                            hint: 'CPF (000.000.000-00)',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          _textControl(
                            context,
                            accent: cIdent,
                            icon: Icons.alternate_email_rounded,
                            controller: _emailController,
                            hint: 'Email',
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 10),
                          _textControl(
                            context,
                            accent: cIdent,
                            icon: Icons.phone_outlined,
                            controller: _phoneController,
                            hint: 'Telefone ((00) 00000-0000)',
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cMotivo,
                      label: 'Motivo',
                      hint: 'Obrigatório — por que esse contato será bloqueado?',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: _fieldFill(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: ThemeHelpers.borderLightColor(context)),
                        ),
                        child: TextField(
                          controller: _reasonController,
                          maxLines: 3,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textColor(context),
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Descreva o motivo do bloqueio…',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: ThemeHelpers.textSecondaryColor(context)
                                  .withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _section(
                      context,
                      accent: cVigencia,
                      label: 'Vigência',
                      hint: 'Permanente ou com data de expiração.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () =>
                                setState(() => _isPermanent = !_isPermanent),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                              decoration: BoxDecoration(
                                color: _fieldFill(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isPermanent
                                      ? cVigencia
                                      : ThemeHelpers.borderLightColor(context),
                                  width: _isPermanent ? 1.2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.lock,
                                    size: 16,
                                    color: _isPermanent
                                        ? cVigencia
                                        : ThemeHelpers.textSecondaryColor(
                                            context),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Bloqueio permanente',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            ThemeHelpers.textColor(context),
                                      ),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: _isPermanent,
                                    activeThumbColor: cVigencia,
                                    onChanged: (v) =>
                                        setState(() => _isPermanent = v),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!_isPermanent) ...[
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: _pickExpiry,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                constraints:
                                    const BoxConstraints(minHeight: 48),
                                padding:
                                    const EdgeInsets.fromLTRB(8, 6, 10, 6),
                                decoration: BoxDecoration(
                                  color: _fieldFill(context),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: ThemeHelpers.borderLightColor(
                                          context)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: cVigencia.withValues(
                                            alpha: isDark ? 0.20 : 0.12),
                                        borderRadius:
                                            BorderRadius.circular(9),
                                      ),
                                      child: Icon(
                                          Icons.calendar_today_outlined,
                                          size: 17,
                                          color: cVigencia),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _expiresAt == null
                                            ? 'Expira em (opcional)'
                                            : DateFormat('dd/MM/yyyy', 'pt_BR')
                                                .format(_expiresAt!),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _expiresAt == null
                                              ? ThemeHelpers
                                                  .textSecondaryColor(context)
                                                  .withValues(alpha: 0.9)
                                              : ThemeHelpers.textColor(
                                                  context),
                                        ),
                                      ),
                                    ),
                                    if (_expiresAt != null)
                                      GestureDetector(
                                        onTap: () =>
                                            setState(() => _expiresAt = null),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color:
                                              ThemeHelpers.textSecondaryColor(
                                                  context),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildFooter(context, danger, mq),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Color danger) {
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
              color: danger.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.userMinus, color: danger, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adicionar à blacklist',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'O contato deixa de receber leads do MCMV.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required Color accent,
    required String label,
    String? hint,
    required Widget child,
    bool first = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _textControl(
    BuildContext context, {
    required Color accent,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: _fieldFill(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              onChanged: (_) => setState(() {}),
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => controller.clear()),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, Color danger, MediaQueryData mq) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: FilledButton.icon(
        onPressed: _canSubmit ? _submit : null,
        icon: const Icon(LucideIcons.userMinus, size: 18),
        label: Text(
          _canSubmit
              ? 'Adicionar à blacklist'
              : !_hasIdentifier
                  ? 'Informe CPF, email ou telefone'
                  : 'Informe o motivo',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: danger,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
