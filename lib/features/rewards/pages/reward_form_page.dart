import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/reward_model.dart';
import '../services/rewards_service.dart';
import '../widgets/reward_card.dart';
import '../widgets/rewards_ui.dart';

/// Formulário de prêmio — criação (`/rewards/create`, gated `reward:create`)
/// e edição (`/rewards/:id/edit`, gated `reward:update`). Paridade com
/// `CreateRewardPage.tsx` / `EditRewardPage.tsx`: nome, descrição, categoria,
/// ícone (emoji), custo em pontos, valor monetário, estoque, ordem de
/// exibição e (na edição) disponibilidade — com **pré-visualização ao vivo**
/// do card exatamente como aparece no catálogo. Campos *filled* em 2 colunas
/// quando couber e máscara monetária via [CurrencyInputFormatter].
class RewardFormPage extends StatefulWidget {
  final String? rewardId;

  const RewardFormPage({super.key, this.rewardId});

  @override
  State<RewardFormPage> createState() => _RewardFormPageState();
}

class _RewardFormPageState extends State<RewardFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _icon = TextEditingController();
  final _pointsCost = TextEditingController();
  final _monetaryValue = TextEditingController();
  final _stockQuantity = TextEditingController();
  final _displayOrder = TextEditingController();

  RewardCategory _category = RewardCategory.monetary;
  bool _isActive = true;

  Reward? _existing;
  bool _loadingExisting = false;
  String? _loadError;
  bool _saving = false;

  bool get _isEdit => widget.rewardId != null;

  bool get _allowed => _isEdit
      ? ModuleAccessService.instance.hasPermission('reward:update')
      : ModuleAccessService.instance.hasPermission('reward:create');

  Color get _accent => rewardsAccent(context);

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExisting();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _icon.dispose();
    _pointsCost.dispose();
    _monetaryValue.dispose();
    _stockQuantity.dispose();
    _displayOrder.dispose();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _loadError = null;
    });
    final res = await RewardsService.instance.getRewardById(widget.rewardId!);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (res.success && res.data != null) {
        _prefill(res.data!);
      } else {
        _loadError = res.message ?? 'Erro ao carregar o prêmio';
      }
    });
  }

  void _prefill(Reward r) {
    _existing = r;
    _name.text = r.name;
    _description.text = r.description ?? '';
    _category = r.category;
    _icon.text = (r.icon ?? '').trim();
    _pointsCost.text = r.pointsCost > 0 ? '${r.pointsCost}' : '';
    _monetaryValue.text = r.monetaryValue != null && r.monetaryValue! > 0
        ? CurrencyInputFormatter.format(r.monetaryValue)
        : '';
    _stockQuantity.text =
        r.stockQuantity != null && r.stockQuantity! > 0
            ? '${r.stockQuantity}'
            : '';
    _displayOrder.text = '${r.displayOrder}';
    _isActive = r.isActive;
  }

  // ─── Parse dos campos ────────────────────────────────────────────────────

  int _parseInt(String text) =>
      int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  double _parseCurrency(String text) {
    final clean = text.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
  }

  /// Prêmio "ao vivo" para a pré-visualização do card do catálogo.
  Reward get _preview {
    final name = _name.text.trim();
    final stock = _parseInt(_stockQuantity.text);
    final monetary = _parseCurrency(_monetaryValue.text);
    return Reward(
      id: _existing?.id ?? 'preview',
      name: name.isEmpty ? 'Nome do prêmio' : name,
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      category: _category,
      pointsCost: _parseInt(_pointsCost.text),
      monetaryValue: monetary > 0 ? monetary : null,
      icon: _icon.text.trim().isEmpty ? null : _icon.text.trim(),
      stockQuantity: stock > 0 ? stock : null,
      redeemedCount: _existing?.redeemedCount ?? 0,
      isActive: _isActive,
      displayOrder: _parseInt(_displayOrder.text),
    );
  }

  // ─── Salvar ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final monetary = _parseCurrency(_monetaryValue.text);
    final stock = _parseInt(_stockQuantity.text);
    final payload = RewardPayload(
      name: _name.text.trim(),
      description: _description.text,
      category: _category,
      pointsCost: _parseInt(_pointsCost.text),
      monetaryValue: monetary > 0 ? monetary : null,
      // Vazio → emoji padrão da categoria (paridade com o web).
      icon: _icon.text.trim().isEmpty
          ? _category.defaultIcon
          : _icon.text.trim(),
      stockQuantity: stock > 0 ? stock : null,
      displayOrder: _parseInt(_displayOrder.text),
      isActive: _isEdit ? _isActive : null,
    );

    setState(() => _saving = true);
    final res = _isEdit
        ? await RewardsService.instance
            .updateReward(widget.rewardId!, payload.toJson())
        : await RewardsService.instance.createReward(payload);
    if (!mounted) return;
    setState(() => _saving = false);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit
              ? 'Prêmio atualizado com sucesso!'
              : 'Prêmio criado e disponível no catálogo!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isDark
              ? AppColors.status.greenDarkMode
              : AppColors.status.green,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ??
              (_isEdit
                  ? 'Erro ao atualizar o prêmio'
                  : 'Erro ao criar o prêmio')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isDark
              ? AppColors.status.errorDarkMode
              : AppColors.status.error,
        ),
      );
    }
  }

  // ─── Tema do formulário (campos filled, foco no acento) ──────────────────

  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
        );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: _accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _accent,
        selectionColor: _accent.withValues(alpha: 0.18),
        selectionHandleColor: _accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle: TextStyle(
            color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
        floatingLabelStyle: TextStyle(
            color: _accent, fontWeight: FontWeight.w700, fontSize: 13.5),
        hintStyle: TextStyle(
            color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
        prefixStyle: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700),
        counterStyle: TextStyle(color: muted, fontSize: 11),
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
        errorBorder: b(danger, 1.2),
        focusedErrorBorder: b(danger, 1.6),
      ),
    );
  }

  TextStyle _fieldStyle(BuildContext context) => TextStyle(
        color: ThemeHelpers.textColor(context),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Editar prêmio' : 'Novo prêmio';

    if (!_allowed) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        showDrawer: false,
        body: RewardsDeniedView(
          message: _isEdit
              ? 'Você não tem acesso à edição de prêmios.'
              : 'Você não tem acesso à criação de prêmios.',
          permission: _isEdit ? 'reward:update' : 'reward:create',
        ),
      );
    }

    Widget body;
    if (_loadingExisting) {
      body = _buildSkeleton(context);
    } else if (_loadError != null) {
      body = RewardsErrorState(message: _loadError!, onRetry: _loadExisting);
    } else {
      body = _buildForm(context);
    }

    return AppScaffold(
      title: title,
      showBottomNavigation: false,
      showDrawer: false,
      body: body,
    );
  }

  Widget _buildForm(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    return Theme(
      data: _formTheme(context),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildIntro(context),
                    const SizedBox(height: 18),
                    _section(
                      context,
                      accent: _accent,
                      label: 'Identificação',
                      hint: 'Nome e descrição exibidos no catálogo de '
                          'resgates.',
                      first: true,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.sentences,
                            style: _fieldStyle(context),
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: 'Nome do prêmio *',
                              hintText: 'Ex: Vale-compras R\$ 100',
                              counterText: '',
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Informe o nome do prêmio'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _description,
                            textCapitalization: TextCapitalization.sentences,
                            style: _fieldStyle(context),
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Descrição',
                              hintText:
                                  'Condições de uso, validade, observações…',
                              alignLabelWithHint: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: blue,
                      label: 'Categoria e ícone',
                      hint: 'A categoria agrupa o prêmio no catálogo; sem '
                          'emoji, usamos o padrão da categoria.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in RewardCategory.values)
                                _categoryChip(context, c, blue),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _icon,
                                  style: _fieldStyle(context),
                                  maxLength: 2,
                                  decoration: InputDecoration(
                                    labelText: 'Ícone (emoji)',
                                    hintText: _category.defaultIcon,
                                    counterText: '',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Amostra do emoji em uso.
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: blue.withValues(
                                      alpha: isDark ? 0.16 : 0.08),
                                  border: Border.all(
                                    color: blue.withValues(alpha: 0.28),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _preview.displayIcon,
                                  style: const TextStyle(
                                      fontSize: 22, height: 1),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: emerald,
                      label: 'Valores',
                      hint: 'Custo em pontos para o resgate e, se for o caso, '
                          'o valor monetário equivalente.',
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _pointsCost,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(7),
                              ],
                              style: _fieldStyle(context),
                              decoration: const InputDecoration(
                                labelText: 'Custo em pontos *',
                                hintText: '500',
                                suffixText: 'pts',
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (v) => _parseInt(v ?? '') <= 0
                                  ? 'Informe o custo'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _monetaryValue,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [CurrencyInputFormatter()],
                              style: _fieldStyle(context),
                              decoration: const InputDecoration(
                                labelText: 'Valor (R\$)',
                                prefixText: 'R\$ ',
                                hintText: '100,00',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: amber,
                      label: 'Estoque e exibição',
                      hint: 'Estoque vazio = ilimitado. A menor ordem aparece '
                          'primeiro no catálogo.',
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _stockQuantity,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              style: _fieldStyle(context),
                              decoration: const InputDecoration(
                                labelText: 'Estoque',
                                hintText: 'Ilimitado',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _displayOrder,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              style: _fieldStyle(context),
                              decoration: const InputDecoration(
                                labelText: 'Ordem de exibição',
                                hintText: '0',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isEdit)
                      _section(
                        context,
                        accent: _isActive
                            ? emerald
                            : ThemeHelpers.textSecondaryColor(context),
                        label: 'Disponibilidade',
                        hint: 'Prêmios inativos ficam ocultos do catálogo, '
                            'sem afetar resgates já realizados.',
                        child: _activeSwitch(context, emerald),
                      ),
                    _section(
                      context,
                      accent: _accent,
                      label: 'Pré-visualização',
                      hint: 'É assim que o prêmio aparece no catálogo da '
                          'equipe.',
                      child: IgnorePointer(
                        child: RewardCard(
                          reward: _preview,
                          myPoints: _preview.pointsCost,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  // ─── Intro editorial ─────────────────────────────────────────────────────

  Widget _buildIntro(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              _isEdit ? 'EDITAR PRÊMIO' : 'NOVO PRÊMIO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _isEdit
              ? (_existing?.name ?? 'Prêmio')
              : 'Adicione um prêmio ao catálogo',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _isEdit
              ? 'Ajuste os dados do prêmio — as alterações valem para os '
                  'próximos resgates.'
              : 'A equipe troca os pontos da gamificação pelos prêmios do '
                  'catálogo.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ─── Peças do formulário ─────────────────────────────────────────────────

  Widget _categoryChip(
      BuildContext context, RewardCategory category, Color accent) {
    final selected = _category == category;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? accent.withValues(alpha: isDark ? 0.2 : 0.1)
          : (isDark
              ? Colors.white.withValues(alpha: 0.045)
              : Colors.black.withValues(alpha: 0.025)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _category = category),
        borderRadius: BorderRadius.circular(12),
        splashColor: accent.withValues(alpha: 0.12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : ThemeHelpers.borderLightColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.defaultIcon,
                style: const TextStyle(fontSize: 14, height: 1),
              ),
              const SizedBox(width: 6),
              Text(
                category.label,
                style: TextStyle(
                  color: selected ? accent : secondary,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 12.5,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeSwitch(BuildContext context, Color emerald) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = _isActive ? emerald : secondary;
    return Material(
      color: tone.withValues(alpha: isDark ? 0.1 : 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => setState(() => _isActive = !_isActive),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tone.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                _isActive ? LucideIcons.circleCheck : LucideIcons.circleOff,
                size: 18,
                color: tone,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isActive
                          ? 'Prêmio ativo no catálogo'
                          : 'Prêmio inativo (oculto)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isActive
                          ? 'A equipe pode ver e resgatar este prêmio.'
                          : 'Ninguém consegue resgatar enquanto estiver '
                              'inativo.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isActive,
                activeColor: emerald,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ],
          ),
        ),
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
      padding: EdgeInsets.only(top: first ? 0 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(context)
                  .withValues(alpha: 0.7),
            ),
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

  // ─── Footer com ações ────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final mq = MediaQuery.of(context);
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
          Expanded(
            flex: 3,
            child: OutlinedButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.check, size: 18),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : _isEdit
                        ? 'Salvar alterações'
                        : 'Criar prêmio',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
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

  // ─── Skeleton fiel ao formulário ─────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    Widget field({double height = 48}) => SkeletonBox(
          width: double.infinity,
          height: height,
          borderRadius: 14,
        );
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkeletonText(width: 130, height: 11),
          const SizedBox(height: 10),
          const SkeletonText(width: 220, height: 22),
          const SizedBox(height: 8),
          const SkeletonText(width: double.infinity, height: 12),
          const SizedBox(height: 24),
          field(),
          const SizedBox(height: 12),
          field(height: 84),
          const SizedBox(height: 24),
          Row(
            children: List.generate(
              3,
              (i) => Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                child: const SkeletonBox(
                    width: 92, height: 36, borderRadius: 12),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: field()),
              const SizedBox(width: 12),
              Expanded(child: field()),
            ],
          ),
          const SizedBox(height: 24),
          field(height: 160),
        ],
      ),
    );
  }
}
