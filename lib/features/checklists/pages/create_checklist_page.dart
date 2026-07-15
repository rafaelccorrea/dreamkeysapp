import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../documents/widgets/entity_selector.dart';
import '../models/checklist_models.dart';
import '../services/checklist_service.dart';

/// Criação/edição de checklist — paridade com `CreateChecklistPage.tsx`:
/// vínculos (imóvel + cliente, travados na edição), tipo, observações e
/// itens personalizados. Sem itens personalizados, o backend cria o
/// template padrão do tipo (a prévia é exibida).
class CreateChecklistPage extends StatefulWidget {
  final String? checklistId;

  const CreateChecklistPage({super.key, this.checklistId});

  bool get isEdit => checklistId != null;

  @override
  State<CreateChecklistPage> createState() => _CreateChecklistPageState();
}

class _CreateChecklistPageState extends State<CreateChecklistPage> {
  final _notesController = TextEditingController();

  String? _propertyId;
  String? _propertyName;
  String? _clientId;
  String? _clientName;
  ChecklistType _type = ChecklistType.sale;

  final List<_ItemControllers> _items = [];

  bool _loading = false;
  bool _saving = false;
  bool _triedSubmit = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) _loadChecklist();
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Future<void> _loadChecklist() async {
    setState(() => _loading = true);
    final res =
        await ChecklistService.instance.getById(widget.checklistId!);
    if (!mounted) return;
    if (res.success && res.data != null) {
      final c = res.data!;
      setState(() {
        _loading = false;
        _propertyId = c.propertyId;
        _propertyName = c.propertyTitle;
        _clientId = c.clientId;
        _clientName = c.clientName;
        _type = c.type == ChecklistType.unknown ? ChecklistType.sale : c.type;
        _notesController.text = c.notes ?? '';
        for (final item in c.items) {
          _items.add(_ItemControllers.fromDraft(
              ChecklistItemDraft.fromItem(item)));
        }
      });
    } else {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao carregar checklist'),
          backgroundColor: AppColors.status.error,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _addItem() {
    setState(() => _items.add(_ItemControllers()));
  }

  void _removeItem(int index) {
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  List<ChecklistItemDraft> _buildDrafts() {
    final drafts = <ChecklistItemDraft>[];
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      drafts.add(ChecklistItemDraft(
        title: it.title.text,
        description: it.description.text,
        status: it.status,
        estimatedDays: int.tryParse(it.days.text.trim()),
        order: i + 1,
        notes: it.notes.text,
      ));
    }
    return drafts;
  }

  bool get _formValid {
    if ((_propertyId ?? '').isEmpty || (_clientId ?? '').isEmpty) return false;
    for (final it in _items) {
      if (it.title.text.trim().isEmpty) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    if (!_formValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (_propertyId ?? '').isEmpty || (_clientId ?? '').isEmpty
                ? 'Selecione o imóvel e o cliente do checklist'
                : 'Todo item personalizado precisa de um título',
          ),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final drafts = _buildDrafts();
    final notes = _notesController.text.trim();

    final res = widget.isEdit
        ? await ChecklistService.instance.update(
            widget.checklistId!,
            type: _type,
            notes: notes,
            items: drafts.isEmpty ? null : drafts,
          )
        : await ChecklistService.instance.create(
            propertyId: _propertyId!,
            clientId: _clientId!,
            type: _type,
            notes: notes.isEmpty ? null : notes,
            items: drafts.isEmpty ? null : drafts,
          );

    if (!mounted) return;
    setState(() => _saving = false);

    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEdit
              ? 'Checklist atualizado com sucesso'
              : 'Checklist criado com sucesso'),
          backgroundColor: AppColors.status.success,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ??
              (widget.isEdit
                  ? 'Erro ao atualizar checklist'
                  : 'Erro ao criar checklist')),
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
    final cVinculos =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cTipo =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    final cItens =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    return AppScaffold(
      title: widget.isEdit ? 'Editar checklist' : 'Novo checklist',
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
                    icon: LucideIcons.link,
                    eyebrow: 'VÍNCULOS',
                    title: 'Imóvel e cliente',
                    hint: widget.isEdit
                        ? 'Os vínculos não podem ser alterados na edição.'
                        : 'Selecione o imóvel e o cliente deste processo.',
                    tone: cVinculos,
                  ),
                  const SizedBox(height: 14),
                  IgnorePointer(
                    ignoring: widget.isEdit,
                    child: Opacity(
                      opacity: widget.isEdit ? 0.6 : 1,
                      child: Column(
                        children: [
                          EntitySelector(
                            type: 'property',
                            selectedId: _propertyId,
                            selectedName: _propertyName,
                            onSelected: (id, name) => setState(() {
                              _propertyId = id;
                              _propertyName = name;
                            }),
                          ),
                          if (_triedSubmit && (_propertyId ?? '').isEmpty)
                            _fieldError(context, 'Selecione um imóvel'),
                          const SizedBox(height: 14),
                          EntitySelector(
                            type: 'client',
                            selectedId: _clientId,
                            selectedName: _clientName,
                            onSelected: (id, name) => setState(() {
                              _clientId = id;
                              _clientName = name;
                            }),
                          ),
                          if (_triedSubmit && (_clientId ?? '').isEmpty)
                            _fieldError(context, 'Selecione um cliente'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _sectionHeader(
                    context,
                    icon: LucideIcons.tag,
                    eyebrow: 'TIPO',
                    title: 'Tipo do processo',
                    hint: 'Define o template padrão dos itens.',
                    tone: cTipo,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _typeChip(context, ChecklistType.sale, cTipo),
                      const SizedBox(width: 10),
                      _typeChip(context, ChecklistType.rental, cTipo),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CustomTextField(
                    controller: _notesController,
                    label: 'Observações gerais',
                    hint: 'Anotações sobre este checklist…',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 26),
                  _sectionHeader(
                    context,
                    icon: LucideIcons.listChecks,
                    eyebrow: 'ITENS',
                    title: 'Itens personalizados',
                    hint: _items.isEmpty
                        ? 'Sem itens personalizados, o template padrão do tipo é criado automaticamente.'
                        : 'Cada item pode ter descrição, prazo estimado e observações.',
                    tone: cItens,
                  ),
                  const SizedBox(height: 14),
                  if (_items.isEmpty && !widget.isEdit)
                    _buildTemplatePreview(context),
                  for (var i = 0; i < _items.length; i++)
                    _buildItemEditor(context, i),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Adicionar item'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  CustomButton(
                    text: _saving
                        ? (widget.isEdit ? 'Salvando…' : 'Criando…')
                        : (widget.isEdit
                            ? 'Salvar alterações'
                            : 'Criar checklist'),
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

  Widget _fieldError(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 13, color: danger),
          const SizedBox(width: 5),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(BuildContext context, ChecklistType type, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selected = _type == type;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _type = type),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
                : fieldFill,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? accent
                  : ThemeHelpers.borderLightColor(context),
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                type == ChecklistType.sale ? LucideIcons.home : LucideIcons.key,
                size: 15,
                color: fg,
              ),
              const SizedBox(width: 7),
              Text(
                type.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Prévia do template padrão ───────────────────────────────────────────

  Widget _buildTemplatePreview(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final template = ChecklistDefaultTemplates.forType(_type);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: blue.withValues(alpha: isDark ? 0.08 : 0.05),
        border: Border.all(color: blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.eye, size: 15, color: blue),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'PRÉVIA DO TEMPLATE PADRÃO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: blue,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 10.5,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${template.length} itens',
                  style: TextStyle(
                    color: blue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sem itens personalizados, este checklist padrão de '
            '${_type.label.toLowerCase()} será criado automaticamente:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < template.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: blue.withValues(alpha: isDark ? 0.18 : 0.1),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: blue,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template[i].title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${template[i].description} · ${template[i].days} '
                        'dia${template[i].days == 1 ? '' : 's'}',
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
          ],
        ],
      ),
    );
  }

  // ─── Editor de item personalizado ────────────────────────────────────────

  Widget _buildItemEditor(BuildContext context, int index) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final item = _items[index];
    final titleEmpty = _triedSubmit && item.title.text.trim().isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent(context).withValues(alpha: 0.12),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: _accent(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ITEM ${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 10,
                  ),
                ),
              ),
              InkResponse(
                radius: 18,
                onTap: () => _removeItem(index),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child:
                      Icon(LucideIcons.trash2, size: 16, color: secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CustomTextField(
            controller: item.title,
            label: 'Título do item *',
            hint: 'Ex: Vistoria técnica',
            errorText: titleEmpty ? 'Título é obrigatório' : null,
            onChanged: (_) {
              if (_triedSubmit) setState(() {});
            },
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: item.description,
            label: 'Descrição',
            hint: 'Descrição do item (opcional)',
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          // Duas colunas: prazo + observações.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CustomTextField(
                  controller: item.days,
                  label: 'Prazo (dias)',
                  hint: 'Ex: 5',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: item.notes,
                  label: 'Observações',
                  hint: 'Opcional',
                ),
              ),
            ],
          ),
        ],
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

/// Controllers de um item personalizado em edição.
class _ItemControllers {
  final TextEditingController title = TextEditingController();
  final TextEditingController description = TextEditingController();
  final TextEditingController days = TextEditingController();
  final TextEditingController notes = TextEditingController();
  ChecklistStatus status = ChecklistStatus.pending;

  _ItemControllers();

  factory _ItemControllers.fromDraft(ChecklistItemDraft draft) {
    final c = _ItemControllers();
    c.title.text = draft.title;
    c.description.text = draft.description;
    c.days.text = draft.estimatedDays?.toString() ?? '';
    c.notes.text = draft.notes;
    c.status = draft.status;
    return c;
  }

  void dispose() {
    title.dispose();
    description.dispose();
    days.dispose();
    notes.dispose();
  }
}
