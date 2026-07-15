import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../documents/widgets/entity_selector.dart';
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
          : SingleChildScrollView(
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
                  const SizedBox(height: 12),
                  _chipsLabel(context, 'Categoria'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in AssetCategory.values)
                        _choiceChip(
                          context,
                          label: c.label,
                          icon: assetCategoryIcon(c),
                          selected: _category == c,
                          accent: cClass,
                          onTap: () => setState(() => _category = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _chipsLabel(context, 'Situação'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in const [
                        AssetStatus.available,
                        AssetStatus.inUse,
                        AssetStatus.maintenance,
                        AssetStatus.disposed,
                        AssetStatus.lost,
                      ])
                        _choiceChip(
                          context,
                          label: s.label,
                          selected: _status == s,
                          accent: assetStatusColor(context, s),
                          onTap: () => setState(() => _status = s),
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
                    icon: LucideIcons.link,
                    eyebrow: 'VÍNCULOS',
                    title: 'Responsável e imóvel',
                    hint: 'Vincule o item a um colaborador ou imóvel (opcional).',
                    tone: cVinculos,
                  ),
                  const SizedBox(height: 14),
                  _responsibleField(context),
                  const SizedBox(height: 14),
                  EntitySelector(
                    type: 'property',
                    selectedId: _propertyId,
                    selectedName: _propertyName,
                    onSelected: (id, name) => setState(() {
                      _propertyId = id;
                      _propertyName = name;
                    }),
                  ),
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _chipsLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
    );
  }

  Widget _choiceChip(
    BuildContext context, {
    required String label,
    IconData? icon,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    return InkWell(
      onTap: onTap,
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
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 12.5,
                color: fg,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
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
        Text(
          'Aquisição',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickAcquisitionDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: ThemeHelpers.borderColor(context)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.calendarDays, size: 16, color: secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filled
                        ? DateFormat('dd/MM/yyyy', 'pt_BR')
                            .format(_acquisitionDate!)
                        : 'Selecionar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: filled
                          ? ThemeHelpers.textColor(context)
                          : secondary.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                if (filled)
                  InkResponse(
                    radius: 16,
                    onTap: () => setState(() => _acquisitionDate = null),
                    child: Icon(LucideIcons.x, size: 14, color: secondary),
                  ),
              ],
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
    return InkWell(
      onTap: _pickResponsible,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Responsável',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          prefixIcon: const Icon(Icons.person_outline),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          hasUser ? _assignedUserName!.trim() : 'Selecionar colaborador',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: hasUser ? ThemeHelpers.textColor(context) : secondary,
          ),
        ),
      ),
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
