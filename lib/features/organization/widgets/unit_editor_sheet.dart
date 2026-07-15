import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/unit_model.dart';
import '../services/unit_service.dart';
import 'org_ui.dart';

/// Bottom-sheet de criação/edição de unidade — espelha o modal do
/// `UnitsPage.tsx`: nome, descrição, cor de identificação e gestores
/// (multi-seleção com busca sobre os membros da empresa).
class UnitEditorSheet extends StatefulWidget {
  /// Nulo para criar; preenchido para editar.
  final OrgUnit? unit;

  /// Chamado após salvar com sucesso (a página recarrega a lista).
  final VoidCallback onSaved;

  const UnitEditorSheet({super.key, this.unit, required this.onSaved});

  @override
  State<UnitEditorSheet> createState() => _UnitEditorSheetState();
}

class _UnitEditorSheetState extends State<UnitEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final TextEditingController _searchController = TextEditingController();

  late String _colorHex;
  late final Set<String> _managerIds;

  List<CompanyMember> _members = const [];
  bool _membersLoading = true;
  String? _membersError;
  String _memberSearch = '';
  bool _saving = false;

  bool get _isEdit => widget.unit != null;

  @override
  void initState() {
    super.initState();
    final u = widget.unit;
    _nameController = TextEditingController(text: u?.name ?? '');
    _descriptionController = TextEditingController(text: u?.description ?? '');
    _colorHex = u?.color ?? _hexOf(kUnitColorValues.first);
    _managerIds = {...?u?.managers.map((m) => m.userId)};
    _loadMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  static String _hexOf(int value) =>
      '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _loadMembers() async {
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    final res = await UnitService.instance.getAllMembers();
    if (!mounted) return;
    setState(() {
      _membersLoading = false;
      if (res.success && res.data != null) {
        final sorted = [...res.data!]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _members = sorted;
      } else {
        _membersError = res.message ?? 'Erro ao carregar membros';
      }
    });
  }

  List<CompanyMember> get _filteredMembers {
    final q = _memberSearch.trim().toLowerCase();
    if (q.isEmpty) return _members;
    return _members
        .where((m) =>
            m.name.toLowerCase().contains(q) ||
            m.email.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome da unidade.')),
      );
      return;
    }
    setState(() => _saving = true);

    String? errorMessage;
    final description = _descriptionController.text.trim();
    if (_isEdit) {
      final unit = widget.unit!;
      final res = await UnitService.instance.update(
        unit.id,
        name: name,
        description: description,
        color: _colorHex,
      );
      if (res.success) {
        final res2 = await UnitService.instance
            .setManagers(unit.id, _managerIds.toList());
        if (!res2.success) errorMessage = res2.message;
      } else {
        errorMessage = res.message;
      }
    } else {
      final res = await UnitService.instance.create(
        name: name,
        description: description.isEmpty ? null : description,
        color: _colorHex,
        managerUserIds: _managerIds.toList(),
      );
      if (!res.success) errorMessage = res.message;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      return;
    }
    Navigator.of(context).pop();
    widget.onSaved();
  }

  Color get _accent {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
  }

  Color _fieldFill(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final selectedColor = Color(
      int.tryParse('FF${_colorHex.replaceAll('#', '')}', radix: 16) ??
          kUnitColorValues.first,
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
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
              // Cabeçalho
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(colors: [
                          selectedColor,
                          selectedColor.withValues(alpha: 0.75),
                        ]),
                      ),
                      child: const Icon(LucideIcons.building,
                          color: Colors.white, size: 19),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        _isEdit ? 'Editar unidade' : 'Nova unidade',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(LucideIcons.x, size: 20, color: secondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    _sectionLabel(context, 'Identificação', accent),
                    const SizedBox(height: 10),
                    _textField(
                      context,
                      controller: _nameController,
                      label: 'Nome *',
                      hint: 'Ex.: Unidade Rio Branco',
                      icon: LucideIcons.building2,
                    ),
                    const SizedBox(height: 10),
                    _textField(
                      context,
                      controller: _descriptionController,
                      label: 'Descrição',
                      hint: 'Opcional',
                      icon: LucideIcons.text,
                    ),
                    const SizedBox(height: 18),
                    _sectionLabel(context, 'Cor de identificação', accent),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final value in kUnitColorValues)
                          _colorSwatch(context, value),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _sectionLabel(
                      context,
                      'Gestores da unidade (${_managerIds.length})',
                      accent,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gestores de unidade veem as fichas de venda da sua '
                      'unidade.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _memberSearch = v),
                      style: TextStyle(
                        color: ThemeHelpers.textColor(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Buscar pessoa por nome ou e-mail…',
                        hintStyle: TextStyle(
                          color: secondary.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(LucideIcons.search,
                            size: 17, color: secondary),
                        filled: true,
                        fillColor: _fieldFill(context),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_membersLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: accent),
                          ),
                        ),
                      )
                    else if (_membersError != null)
                      OrgErrorState(
                        message: _membersError!,
                        onRetry: _loadMembers,
                      )
                    else if (_filteredMembers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text(
                            'Nenhuma pessoa encontrada.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: secondary),
                          ),
                        ),
                      )
                    else
                      ..._filteredMembers.map((m) => _memberRow(context, m)),
                  ],
                ),
              ),
              // Rodapé
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _saving ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: secondary,
                            side: BorderSide(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(LucideIcons.check, size: 17),
                          label: Text(_saving ? 'Salvando…' : 'Salvar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String label, Color accent) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 10.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _textField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return TextField(
      controller: controller,
      style: TextStyle(
        color: ThemeHelpers.textColor(context),
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          color: secondary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        hintStyle: TextStyle(
          color: secondary.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
          fontSize: 13.5,
        ),
        prefixIcon: Icon(icon, size: 17, color: secondary),
        filled: true,
        fillColor: _fieldFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _colorSwatch(BuildContext context, int value) {
    final hex = _hexOf(value);
    final selected = _colorHex.toUpperCase() == hex;
    final color = Color(value);
    return InkWell(
      onTap: () => setState(() => _colorHex = hex),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? ThemeHelpers.textColor(context)
                : Colors.transparent,
            width: 2.4,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: selected
            ? const Icon(LucideIcons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }

  Widget _memberRow(BuildContext context, CompanyMember member) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final selected = _managerIds.contains(member.id);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() {
            if (!_managerIds.remove(member.id)) _managerIds.add(member.id);
          }),
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: isDark ? 0.12 : 0.07)
                  : ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.45)
                    : ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.55),
                width: selected ? 1.3 : 1,
              ),
            ),
            child: Row(
              children: [
                OrgAvatar(
                  name: member.name,
                  imageUrl: member.avatar,
                  tone: selected ? accent : secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      Text(
                        member.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? green : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? green
                          : ThemeHelpers.borderColor(context),
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(LucideIcons.check,
                          size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
