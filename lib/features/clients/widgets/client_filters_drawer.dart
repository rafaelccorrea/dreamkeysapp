import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../models/client_model.dart';

/// Bottom-sheet de filtros avançados para a carteira de clientes.
class ClientFiltersDrawer extends StatefulWidget {
  final ClientSearchFilters? initialFilters;
  final Function(ClientSearchFilters?) onFiltersChanged;

  const ClientFiltersDrawer({
    super.key,
    this.initialFilters,
    required this.onFiltersChanged,
  });

  @override
  State<ClientFiltersDrawer> createState() => _ClientFiltersDrawerState();
}

class _ClientFiltersDrawerState extends State<ClientFiltersDrawer> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _documentController = TextEditingController();
  final _cityController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _stateController = TextEditingController();
  final _createdFromController = TextEditingController();
  final _createdToController = TextEditingController();

  ClientType? _selectedType;
  ClientStatus? _selectedStatus;
  bool? _isActive;
  bool? _onlyMyData;
  String? _sortBy;
  String? _sortOrder;

  @override
  void initState() {
    super.initState();
    _loadInitialFilters();
  }

  void _loadInitialFilters() {
    final filters = widget.initialFilters;
    if (filters == null) return;

    _nameController.text = filters.name ?? '';
    _emailController.text = filters.email ?? '';
    _phoneController.text = filters.phone ?? '';
    _documentController.text = filters.document ?? '';
    _cityController.text = filters.city ?? '';
    _neighborhoodController.text = filters.neighborhood ?? '';
    _stateController.text = filters.state ?? '';
    _createdFromController.text = filters.createdFrom ?? '';
    _createdToController.text = filters.createdTo ?? '';
    _selectedType = filters.type;
    _selectedStatus = filters.status;
    _isActive = filters.isActive;
    _onlyMyData = filters.onlyMyData;
    _sortBy = filters.sortBy;
    _sortOrder = filters.sortOrder;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _documentController.dispose();
    _cityController.dispose();
    _neighborhoodController.dispose();
    _stateController.dispose();
    _createdFromController.dispose();
    _createdToController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  void _applyFilters() {
    final filters = ClientSearchFilters(
      name: _nullIfEmpty(_nameController.text),
      email: _nullIfEmpty(_emailController.text),
      phone: _nullIfEmpty(_phoneController.text),
      document: _nullIfEmpty(_documentController.text),
      city: _nullIfEmpty(_cityController.text),
      neighborhood: _nullIfEmpty(_neighborhoodController.text),
      state: _nullIfEmpty(_stateController.text)?.toUpperCase(),
      type: _selectedType,
      status: _selectedStatus,
      isActive: _isActive,
      onlyMyData: _onlyMyData,
      createdFrom: _nullIfEmpty(_createdFromController.text),
      createdTo: _nullIfEmpty(_createdToController.text),
      sortBy: _sortBy,
      sortOrder: _sortOrder,
    );

    widget.onFiltersChanged(filters);
    Navigator.of(context).pop();
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _clearFilters() {
    setState(() {
      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _documentController.clear();
      _cityController.clear();
      _neighborhoodController.clear();
      _stateController.clear();
      _createdFromController.clear();
      _createdToController.clear();
      _selectedType = null;
      _selectedStatus = null;
      _isActive = null;
      _onlyMyData = null;
      _sortBy = null;
      _sortOrder = null;
    });
    widget.onFiltersChanged(null);
    Navigator.of(context).pop();
  }

  int _activeFilterCount() {
    int count = 0;
    if (_nameController.text.isNotEmpty) count++;
    if (_emailController.text.isNotEmpty) count++;
    if (_phoneController.text.isNotEmpty) count++;
    if (_documentController.text.isNotEmpty) count++;
    if (_cityController.text.isNotEmpty) count++;
    if (_neighborhoodController.text.isNotEmpty) count++;
    if (_stateController.text.isNotEmpty) count++;
    if (_selectedType != null) count++;
    if (_selectedStatus != null) count++;
    if (_isActive != null) count++;
    if (_onlyMyData != null) count++;
    if (_createdFromController.text.isNotEmpty) count++;
    if (_createdToController.text.isNotEmpty) count++;
    if (_sortBy != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFFF4D67) : AppColors.primary.primary;
    final mq = MediaQuery.of(context);
    final activeCount = _activeFilterCount();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Center(
                  child: Container(
                    width: 44,
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    _buildSection(
                      context,
                      icon: Icons.search_rounded,
                      accent: accent,
                      title: 'Busca direta',
                      description:
                          'Filtre por nome, email, telefone ou documento.',
                      child: Column(
                        children: [
                          CustomTextField(
                            controller: _nameController,
                            label: 'Nome',
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _emailController,
                            label: 'Email',
                            prefixIcon: const Icon(Icons.email_outlined),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _phoneController,
                            label: 'Telefone',
                            prefixIcon: const Icon(Icons.phone_outlined),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _documentController,
                            label: 'CPF',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.location_on_outlined,
                      accent: accent,
                      title: 'Localização',
                      description: 'Cidade, bairro e UF do cliente.',
                      child: Column(
                        children: [
                          CustomTextField(
                            controller: _cityController,
                            label: 'Cidade',
                            prefixIcon:
                                const Icon(Icons.location_city_outlined),
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _neighborhoodController,
                            label: 'Bairro',
                            prefixIcon: const Icon(Icons.place_outlined),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _stateController,
                            decoration: InputDecoration(
                              labelText: 'UF',
                              prefixIcon: const Icon(Icons.map_outlined),
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            maxLength: 2,
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.category_outlined,
                      accent: accent,
                      title: 'Classificação',
                      description: 'Tipo de cliente e estágio do funil.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _chipFieldLabel(context, 'Tipo de cliente'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipChoice(
                                label: 'Todos',
                                selected: _selectedType == null,
                                onTap: () => setState(() => _selectedType = null),
                                accent: accent,
                              ),
                              ...ClientType.values.map(
                                (t) => _ChipChoice(
                                  label: t.label,
                                  selected: _selectedType == t,
                                  onTap: () =>
                                      setState(() => _selectedType = t),
                                  accent: accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _chipFieldLabel(context, 'Status do cliente'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipChoice(
                                label: 'Todos',
                                selected: _selectedStatus == null,
                                onTap: () =>
                                    setState(() => _selectedStatus = null),
                                accent: accent,
                              ),
                              ...ClientStatus.values.map(
                                (s) => _ChipChoice(
                                  label: s.label,
                                  selected: _selectedStatus == s,
                                  onTap: () =>
                                      setState(() => _selectedStatus = s),
                                  accent: accent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.toggle_on_outlined,
                      accent: accent,
                      title: 'Escopo',
                      description: 'Restrinja o resultado da listagem.',
                      child: Column(
                        children: [
                          _switchTile(
                            context,
                            icon: Icons.power_settings_new_rounded,
                            title: 'Apenas ativos',
                            subtitle: 'Oculta clientes desativados',
                            value: _isActive ?? false,
                            onChanged: (value) =>
                                setState(() => _isActive = value ? true : null),
                            accent: accent,
                          ),
                          const SizedBox(height: 8),
                          _switchTile(
                            context,
                            icon: Icons.person_pin_circle_outlined,
                            title: 'Apenas meus clientes',
                            subtitle:
                                'Mostrar somente o que está sob sua responsabilidade',
                            value: _onlyMyData ?? false,
                            onChanged: (value) => setState(
                              () => _onlyMyData = value ? true : null,
                            ),
                            accent: accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.event_outlined,
                      accent: accent,
                      title: 'Período de cadastro',
                      description: 'Limite por data de criação.',
                      child: Row(
                        children: [
                          Expanded(
                            child: _dateField(
                              context,
                              controller: _createdFromController,
                              label: 'De',
                              accent: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dateField(
                              context,
                              controller: _createdToController,
                              label: 'Até',
                              accent: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      context,
                      icon: Icons.sort_rounded,
                      accent: accent,
                      title: 'Ordenação',
                      description: 'Critério principal e direção.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _chipFieldLabel(context, 'Ordenar por'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipChoice(
                                label: 'Padrão',
                                selected: _sortBy == null,
                                onTap: () => setState(() => _sortBy = null),
                                accent: accent,
                              ),
                              _ChipChoice(
                                label: 'Nome',
                                selected: _sortBy == 'name',
                                onTap: () => setState(() => _sortBy = 'name'),
                                accent: accent,
                              ),
                              _ChipChoice(
                                label: 'Data',
                                selected: _sortBy == 'createdAt',
                                onTap: () =>
                                    setState(() => _sortBy = 'createdAt'),
                                accent: accent,
                              ),
                              _ChipChoice(
                                label: 'Status',
                                selected: _sortBy == 'status',
                                onTap: () => setState(() => _sortBy = 'status'),
                                accent: accent,
                              ),
                              _ChipChoice(
                                label: 'Tipo',
                                selected: _sortBy == 'type',
                                onTap: () => setState(() => _sortBy = 'type'),
                                accent: accent,
                              ),
                              _ChipChoice(
                                label: 'Cidade',
                                selected: _sortBy == 'city',
                                onTap: () => setState(() => _sortBy = 'city'),
                                accent: accent,
                              ),
                            ],
                          ),
                          if (_sortBy != null) ...[
                            const SizedBox(height: 16),
                            _chipFieldLabel(context, 'Direção'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _ChipChoice(
                                  label: 'Crescente',
                                  selected: (_sortOrder ?? 'ASC') == 'ASC',
                                  onTap: () =>
                                      setState(() => _sortOrder = 'ASC'),
                                  accent: accent,
                                  icon: Icons.arrow_upward_rounded,
                                ),
                                _ChipChoice(
                                  label: 'Decrescente',
                                  selected: _sortOrder == 'DESC',
                                  onTap: () =>
                                      setState(() => _sortOrder = 'DESC'),
                                  accent: accent,
                                  icon: Icons.arrow_downward_rounded,
                                ),
                              ],
                            ),
                          ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF7C3AED)],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtros avançados',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activeCount == 0
                      ? 'Nenhum filtro aplicado'
                      : '$activeCount filtro${activeCount == 1 ? '' : 's'} ativo${activeCount == 1 ? '' : 's'}',
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

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required String description,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(icon, color: accent, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _chipFieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.1,
          ),
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value
              ? accent.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(
            color: value
                ? accent.withValues(alpha: 0.45)
                : ThemeHelpers.borderLightColor(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: accent.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required Color accent,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: () => _selectDate(context, controller),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(Icons.calendar_today_outlined, color: accent),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () => setState(() => controller.clear()),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + mq.padding.bottom,
      ),
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
            child: OutlinedButton.icon(
              onPressed: activeCount == 0 ? null : _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Limpar tudo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                activeCount == 0
                    ? 'Aplicar'
                    : 'Aplicar ($activeCount)',
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

class _ChipChoice extends StatelessWidget {
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : ThemeHelpers.textColor(context);
    final bg = selected ? accent : ThemeHelpers.cardBackgroundColor(context);
    final border = selected
        ? accent
        : ThemeHelpers.borderLightColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
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
                color: fg,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
