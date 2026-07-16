import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/subscription_models.dart';

/// Bottom-sheet de filtros da gestão de assinaturas — espelha o modal de
/// filtros do CRM (`kanban_filters_drawer.dart`): seções *flush* separadas por
/// filete tracejado + eyebrow com dot de cor; campos em pill com chip de
/// ícone; cor apenas como sinal.
///
/// O `status` NÃO entra aqui — é controlado pelas abas da página.
class SubscriptionFiltersSheet extends StatefulWidget {
  const SubscriptionFiltersSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    required this.onClear,
  });

  final AdminSubscriptionFilters initialFilters;
  final ValueChanged<AdminSubscriptionFilters> onApply;
  final VoidCallback onClear;

  @override
  State<SubscriptionFiltersSheet> createState() =>
      _SubscriptionFiltersSheetState();
}

class _SubscriptionFiltersSheetState extends State<SubscriptionFiltersSheet> {
  late final TextEditingController _companyController;
  late final TextEditingController _cnpjController;
  late final TextEditingController _userController;
  late final TextEditingController _emailController;
  String? _planType;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    _companyController = TextEditingController(text: f.companyName ?? '');
    _cnpjController = TextEditingController(text: f.companyCnpj ?? '');
    _userController = TextEditingController(text: f.userName ?? '');
    _emailController = TextEditingController(text: f.userEmail ?? '');
    _planType = f.planType;
  }

  @override
  void dispose() {
    _companyController.dispose();
    _cnpjController.dispose();
    _userController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Color _fieldFill(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  AdminSubscriptionFilters _build() {
    String? clean(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    return AdminSubscriptionFilters(
      companyName: clean(_companyController),
      companyCnpj: clean(_cnpjController),
      userName: clean(_userController),
      userEmail: clean(_emailController),
      status: widget.initialFilters.status,
      planType: _planType,
      page: 1,
      limit: widget.initialFilters.limit,
    );
  }

  int get _activeCount => _build().activeCount;

  void _apply() {
    widget.onApply(_build());
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onClear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final cEmpresa =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cUsuario =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final cPlano =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final mq = MediaQuery.of(context);
    final activeCount = _activeCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
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
              _buildHeader(context, accent, activeCount),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: [
                    _section(
                      context,
                      accent: cEmpresa,
                      label: 'Empresa',
                      hint: 'Nome fantasia ou razão social.',
                      first: true,
                      child: _textControl(
                        context,
                        accent: cEmpresa,
                        icon: LucideIcons.building2,
                        controller: _companyController,
                        hint: 'Nome da empresa…',
                      ),
                    ),
                    _section(
                      context,
                      accent: cEmpresa,
                      label: 'CNPJ',
                      hint: 'Somente números também funciona.',
                      child: _textControl(
                        context,
                        accent: cEmpresa,
                        icon: LucideIcons.fileText,
                        controller: _cnpjController,
                        hint: '00.000.000/0000-00',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    _section(
                      context,
                      accent: cUsuario,
                      label: 'Titular',
                      hint: 'Nome ou e-mail do dono da assinatura.',
                      child: Column(
                        children: [
                          _textControl(
                            context,
                            accent: cUsuario,
                            icon: LucideIcons.userRound,
                            controller: _userController,
                            hint: 'Nome do titular…',
                          ),
                          const SizedBox(height: 10),
                          _textControl(
                            context,
                            accent: cUsuario,
                            icon: LucideIcons.mail,
                            controller: _emailController,
                            hint: 'email@exemplo.com',
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cPlano,
                      label: 'Tipo de plano',
                      hint: 'Filtre pela categoria do plano contratado.',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(context, 'Todos', null, cPlano),
                          _chip(context, 'Básico', 'basic', cPlano),
                          _chip(
                              context, 'Profissional', 'professional', cPlano),
                          _chip(context, 'Personalizado', 'custom', cPlano),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildFooter(context, accent, activeCount, mq),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, int activeCount) {
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
              color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.slidersHorizontal, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar assinaturas',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activeCount == 0
                      ? 'Nenhum filtro aplicado'
                      : '$activeCount filtro${activeCount == 1 ? '' : 's'} '
                          'ativo${activeCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: activeCount == 0
                        ? ThemeHelpers.textSecondaryColor(context)
                        : accent,
                    fontWeight: FontWeight.w700,
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
          if (!first) ...[
            _DashedLine(color: ThemeHelpers.borderLightColor(context)),
            const SizedBox(height: 18),
          ],
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
    final hasText = controller.text.isNotEmpty;
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
              color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
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
          if (hasText)
            GestureDetector(
              onTap: () => setState(controller.clear),
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

  Widget _chip(
      BuildContext context, String label, String? value, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selected = _planType == value;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    return InkWell(
      onTap: () => setState(() => _planType = value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.18 : 0.1)
              : fieldFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : ThemeHelpers.borderLightColor(context),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontSize: 12.5,
            color: fg,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    Color accent,
    int activeCount,
    MediaQueryData mq,
  ) {
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
      child: Row(
        children: [
          if (activeCount > 0) ...[
            Expanded(
              flex: 3,
              child: OutlinedButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text(
                  'Limpar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: activeCount > 0 ? 4 : 1,
            child: FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                activeCount == 0 ? 'Aplicar' : 'Aplicar ($activeCount)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedPainter(color)),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) =>
      oldDelegate.color != color;
}
