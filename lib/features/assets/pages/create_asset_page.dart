import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../models/asset_models.dart';
import '../services/asset_service.dart';
import '../widgets/asset_card.dart';
import '../widgets/user_picker_sheet.dart';

/// Criação/edição de patrimônio — paridade com `CreateAssetPage.tsx`:
/// identificação, categoria/situação em chips, valor com máscara monetária,
/// especificações em duas colunas e vínculos opcionais (responsável/imóvel).
class CreateAssetPage extends StatefulWidget {
  final String? assetId;

  const CreateAssetPage({super.key, this.assetId});

  bool get isEdit => assetId != null;

  @override
  State<CreateAssetPage> createState() => _CreateAssetPageState();
}

class _CreateAssetPageState extends State<CreateAssetPage> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _serialController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  AssetCategory _category = AssetCategory.electronics;
  AssetStatus _status = AssetStatus.available;
  DateTime? _acquisitionDate;

  String? _assignedUserId;
  String? _assignedUserName;
  String? _propertyId;
  String? _propertyName;

  bool _loading = false;
  bool _saving = false;
  bool _triedSubmit = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) _loadAsset();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Future<void> _loadAsset() async {
    setState(() => _loading = true);
    final res = await AssetService.instance.getById(widget.assetId!);
    if (!mounted) return;
    if (res.success && res.data != null) {
      final a = res.data!;
      setState(() {
        _loading = false;
        _nameController.text = a.name;
        _descriptionController.text = a.description ?? '';
        _valueController.text = CurrencyInputFormatter.format(a.value);
        _brandController.text = a.brand ?? '';
        _modelController.text = a.model ?? '';
        _serialController.text = a.serialNumber ?? '';
        _locationController.text = a.location ?? '';
        _notesController.text = a.notes ?? '';
        _category = a.category;
        _status =
            a.status == AssetStatus.unknown ? AssetStatus.available : a.status;
        _acquisitionDate = a.acquisitionDate?.toLocal();
        _assignedUserId = a.assignedToUserId;
        _assignedUserName = a.assignedToUserName;
        _propertyId = a.propertyId;
        _propertyName = a.propertyTitle;
      });
    } else {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao carregar patrimônio'),
          backgroundColor: AppColors.status.error,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  double _parseValue() {
    final digits = _valueController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return (int.tryParse(digits) ?? 0) / 100.0;
  }

  bool get _formValid => _nameController.text.trim().isNotEmpty;

  Future<void> _pickAcquisitionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _acquisitionDate ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() => _acquisitionDate = picked);
  }

  Future<void> _pickResponsible() async {
    final picked = await showUserPickerSheet(
      context,
      selectedId: _assignedUserId,
      allowClear: (_assignedUserId ?? '').isNotEmpty,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _assignedUserId = picked.id.isEmpty ? null : picked.id;
      _assignedUserName = picked.id.isEmpty ? null : picked.name;
    });
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    if (!_formValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Informe o nome do item'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final draft = AssetDraft(
      name: _nameController.text,
      description: _descriptionController.text,
      category: _category,
      status: _status,
      value: _parseValue(),
      serialNumber: _serialController.text,
      brand: _brandController.text,
      model: _modelController.text,
      acquisitionDate: _acquisitionDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(_acquisitionDate!),
      location: _locationController.text,
      notes: _notesController.text,
      assignedToUserId: _assignedUserId,
      propertyId: _propertyId,
    );

    final res = widget.isEdit
        ? await AssetService.instance.update(widget.assetId!, draft)
        : await AssetService.instance.create(draft);

    if (!mounted) return;
    setState(() => _saving = false);

    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEdit
              ? 'Patrimônio atualizado com sucesso'
              : 'Patrimônio cadastrado com sucesso'),
          backgroundColor: AppColors.status.success,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ??
              (widget.isEdit
                  ? 'Erro ao atualizar patrimônio'
                  : 'Erro ao cadastrar patrimônio')),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cIdent =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cClass =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cSpecs =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final cVinculos =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

    return AppScaffold(
      title: widget.isEdit ? 'Editar item' : 'Novo item',
      showBottomNavigation: false,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : Theme(
              // Inputs mais enxutos nesta tela: reduz a altura/gordura dos
              // campos (o tema global usa 16px verticais — aqui 11).
              data: Theme.of(context).copyWith(
                inputDecorationTheme:
                    Theme.of(context).inputDecorationTheme.copyWith(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                        ),
              ),
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader(
                    context,
                    icon: LucideIcons.package,
                    eyebrow: 'IDENTIFICAÇÃO',
                    title: 'Dados do item',
                    hint: 'Nome, descrição e valor do bem.',
                    tone: cIdent,
                  ),
                  const SizedBox(height: 14),
                  CustomTextField(
                    controller: _nameController,
                    label: 'Nome do item *',
                    hint: 'Ex: Notebook Dell Latitude',
                    errorText:
                        _triedSubmit && _nameController.text.trim().isEmpty
                            ? 'Nome é obrigatório'
                            : null,
                    onChanged: (_) {
                      if (_triedSubmit) setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: _descriptionController,
                    label: 'Descrição',
                    hint: 'Detalhes do item (opcional)',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: _valueController,
                    label: 'Valor (R\$)',
                    hint: '0,00',
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 8),
                      child: Icon(
                        LucideIcons.banknote,
                        size: 18,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _sectionHeader(
                    context,
                    icon: LucideIcons.tag,
                    eyebrow: 'CLASSIFICAÇÃO',
                    title: 'Categoria e situação',
                    hint: 'Como o item entra no inventário.',
                    tone: cClass,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _selectField(
                          context,
                          label: 'Categoria',
                          leading: Icon(assetCategoryIcon(_category),
                              size: 18, color: cClass),
                          value: _category.label,
                          onTap: _pickCategory,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _selectField(
                          context,
                          label: 'Situação',
                          leading: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: assetStatusColor(context, _status),
                            ),
                          ),
                          value: _status.label,
                          onTap: _pickStatus,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  _sectionHeader(
                    context,
                    icon: LucideIcons.scanBarcode,
                    eyebrow: 'ESPECIFICAÇÕES',
                    title: 'Detalhes técnicos',
                    hint: 'Marca, modelo, série e aquisição.',
                    tone: cSpecs,
                  ),
                  const SizedBox(height: 14),
                  // Duas colunas: marca + modelo.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: CustomTextField(
                          controller: _brandController,
                          label: 'Marca',
                          hint: 'Ex: Dell',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomTextField(
                          controller: _modelController,
                          label: 'Modelo',
                          hint: 'Ex: Latitude 5440',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Duas colunas: nº de série + data de aquisição.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: CustomTextField(
                          controller: _serialController,
                          label: 'Nº de série',
                          hint: 'Opcional',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _dateField(context)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: _locationController,
                    label: 'Localização',
                    hint: 'Ex: Sede - Sala 2',
                  ),
                  const SizedBox(height: 26),
                  _sectionHeader(
                    context,
                    icon: LucideIcons.userCheck,
                    eyebrow: 'RESPONSÁVEL',
                    title: 'Quem responde pelo item',
                    hint: 'Vincule o bem a um colaborador (opcional).',
                    tone: cVinculos,
                  ),
                  const SizedBox(height: 14),
                  _responsibleField(context),
                  const SizedBox(height: 20),
                  CustomTextField(
                    controller: _notesController,
                    label: 'Observações',
                    hint: 'Observações gerais (opcional)',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 28),
                  CustomButton(
                    text: _saving
                        ? (widget.isEdit ? 'Salvando…' : 'Cadastrando…')
                        : (widget.isEdit
                            ? 'Salvar alterações'
                            : 'Cadastrar item'),
                    onPressed: _saving ? null : _submit,
                    isLoading: _saving,
                    isFullWidth: true,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 16),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      // "Cancelar" NUNCA em vermelho: o tema global pinta o
                      // OutlinedButton com a cor da marca (vermelha). Cancelar
                      // não é destrutivo — força ferragem neutra.
                      foregroundColor: ThemeHelpers.textSecondaryColor(context),
                      side: BorderSide(
                        color: ThemeHelpers.borderColor(context),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
    );
  }

  /// Campo-seletor de uma linha (categoria/situação) — mesma anatomia do tema
  /// (fill + borda), abre uma folha de opções. Substitui as paredes de pills.
  Widget _selectField(
    BuildContext context, {
    required String label,
    required Widget leading,
    required String value,
    required VoidCallback onTap,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, label),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                        ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded, color: secondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCategory() async {
    final chosen = await _showOptionSheet<AssetCategory>(
      title: 'Categoria do item',
      values: AssetCategory.values,
      current: _category,
      labelOf: (c) => c.label,
      iconOf: (c) => assetCategoryIcon(c),
      accentOf: (_) => _accent(context),
    );
    if (chosen != null) setState(() => _category = chosen);
  }

  Future<void> _pickStatus() async {
    final chosen = await _showOptionSheet<AssetStatus>(
      title: 'Situação do item',
      values: const [
        AssetStatus.available,
        AssetStatus.inUse,
        AssetStatus.maintenance,
        AssetStatus.disposed,
        AssetStatus.lost,
      ],
      current: _status,
      labelOf: (s) => s.label,
      accentOf: (s) => assetStatusColor(context, s),
    );
    if (chosen != null) setState(() => _status = chosen);
  }

  /// Folha de opções na anatomia da casa (grabber + título + lista com glifo
  /// tonal, rótulo e check no ativo). Sem vermelho chapado.
  Future<T?> _showOptionSheet<T>({
    required String title,
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required Color Function(T) accentOf,
    IconData Function(T)? iconOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final secondary = ThemeHelpers.textSecondaryColor(ctx);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.backgroundColor(ctx),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ThemeHelpers.borderColor(ctx)
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: ThemeHelpers.textColor(ctx),
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close_rounded,
                            size: 19, color: secondary),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: ThemeHelpers.borderLightColor(ctx)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.fromLTRB(
                        12, 8, 12, 16 + media.padding.bottom),
                    children: [
                      for (final v in values)
                        _optionRow<T>(
                          ctx,
                          selected: v == current,
                          label: labelOf(v),
                          accent: accentOf(v),
                          icon: iconOf?.call(v),
                          isDark: isDark,
                          onTap: () => Navigator.of(ctx).pop(v),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _optionRow<T>(
    BuildContext ctx, {
    required bool selected,
    required String label,
    required Color accent,
    required IconData? icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 11, 12, 11),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: accent.withValues(
                        alpha: selected ? (isDark ? 0.26 : 0.16) : 0.10),
                  ),
                  child: icon != null
                      ? Icon(icon,
                          size: 16,
                          color: selected
                              ? accent
                              : ThemeHelpers.textSecondaryColor(ctx))
                      : Container(
                          width: 9,
                          height: 9,
                          decoration:
                              BoxDecoration(shape: BoxShape.circle, color: accent),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? accent
                              : ThemeHelpers.textColor(ctx),
                          letterSpacing: -0.1,
                        ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 19, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rótulo de campo — idêntico ao do [CustomTextField] (labelLarge w600 acima),
  /// para que todos os campos da tela fiquem alinhados.
  Widget _fieldLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textColor(context),
          ),
    );
  }

  Widget _dateField(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final filled = _acquisitionDate != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Aquisição'),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickAcquisitionDate,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            // Sem `border` explícito: herda o InputDecorationTheme (fill
            // terciário + borda 1.5 + radius 12), casando com os CustomTextField.
            decoration: InputDecoration(
              prefixIcon: Icon(LucideIcons.calendarDays, size: 18, color: secondary),
              suffixIcon: filled
                  ? IconButton(
                      icon: Icon(LucideIcons.x, size: 16, color: secondary),
                      onPressed: () => setState(() => _acquisitionDate = null),
                      tooltip: 'Limpar data',
                    )
                  : null,
            ),
            child: Text(
              filled
                  ? DateFormat('dd/MM/yyyy', 'pt_BR').format(_acquisitionDate!)
                  : 'Selecionar',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: filled
                    ? ThemeHelpers.textColor(context)
                    : secondary.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _responsibleField(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasUser = (_assignedUserName ?? '').trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Responsável'),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickResponsible,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.person_outline),
              suffixIcon: hasUser
                  ? IconButton(
                      icon: Icon(LucideIcons.x, size: 16, color: secondary),
                      onPressed: () => setState(() {
                        _assignedUserId = null;
                        _assignedUserName = null;
                      }),
                      tooltip: 'Remover responsável',
                    )
                  : const Icon(Icons.arrow_drop_down),
            ),
            child: Text(
              hasUser ? _assignedUserName!.trim() : 'Selecionar colaborador',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: hasUser ? ThemeHelpers.textColor(context) : secondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String eyebrow,
    required String title,
    required String hint,
    required Color tone,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(icon, color: tone, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
