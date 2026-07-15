import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/visit_report_access.dart';
import '../models/visit_report_model.dart';
import '../services/visit_report_service.dart';
import '../widgets/visit_report_pickers.dart';

/// Linha editável de imóvel visitado no formulário.
class _PropertyEntry {
  String? propertyId;
  final TextEditingController address = TextEditingController();
  final TextEditingController reference = TextEditingController();

  void dispose() {
    address.dispose();
    reference.dispose();
  }
}

/// Criar / editar **relatório de visita** — campos fiéis ao web
/// (`VisitReportFormPage`): cliente, data da visita, imóveis visitados
/// (busca no cadastro OU endereço livre + referência) e observações.
class VisitReportFormPage extends StatefulWidget {
  /// `null` = criação; preenchido = edição.
  final String? reportId;

  const VisitReportFormPage({super.key, this.reportId});

  @override
  State<VisitReportFormPage> createState() => _VisitReportFormPageState();
}

class _VisitReportFormPageState extends State<VisitReportFormPage> {
  bool get _isEdit => widget.reportId != null;

  VisitReport? _initialReport;
  bool _loadingExisting = false;
  String? _loadError;

  String _clientId = '';
  String _clientName = '';
  DateTime _visitDate = DateTime.now();
  final List<_PropertyEntry> _properties = [_PropertyEntry()];
  final TextEditingController _notes = TextEditingController();

  bool _saving = false;
  String? _formError;

  bool get _canSubmit => _isEdit
      ? ModuleAccessService.instance.hasPermission(VisitReportAccess.update)
      : ModuleAccessService.instance.hasPermission(VisitReportAccess.create);

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExisting();
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final p in _properties) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _loadError = null;
    });
    final res = await VisitReportService.instance.getById(widget.reportId!);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (res.success && res.data != null) {
        _prefill(res.data!);
      } else {
        _loadError = res.message ?? 'Relatório não encontrado.';
      }
    });
  }

  void _prefill(VisitReport report) {
    _initialReport = report;
    _clientId = report.clientId;
    _clientName = report.clientLabel;
    if (report.visitDate != null) _visitDate = report.visitDate!;
    _notes.text = report.notes ?? '';
    if (report.properties.isNotEmpty) {
      for (final p in _properties) {
        p.dispose();
      }
      _properties
        ..clear()
        ..addAll(report.properties.map((p) {
          final entry = _PropertyEntry()..propertyId = p.propertyId;
          entry.address.text = p.address;
          entry.reference.text = p.reference ?? '';
          return entry;
        }));
    }
  }

  /// Tema local dos campos — visual *filled* leve (mesma gramática dos steps
  /// da ficha de venda), foco/cursor na cor da marca.
  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    final muted = ThemeHelpers.textSecondaryColor(context);
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
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
      ),
    );
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _pickClient() async {
    if (_isEdit) return; // cliente não muda em edição (paridade com o web)
    final selected = await showClientPicker(context);
    if (selected == null || !mounted) return;
    setState(() {
      _clientId = selected.id;
      _clientName = selected.name;
    });
  }

  Future<void> _pickVisitDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null || !mounted) return;
    setState(() => _visitDate = picked);
  }

  Future<void> _pickProperty(_PropertyEntry entry) async {
    final selected = await showPropertyPicker(context);
    if (selected == null || !mounted) return;
    setState(() {
      entry.propertyId = selected.id;
      entry.address.text =
          selected.address.isNotEmpty ? selected.address : selected.title;
      entry.reference.text =
          (selected.code ?? '').isNotEmpty ? 'Ref. ${selected.code}' : '';
    });
  }

  void _addProperty() {
    setState(() => _properties.add(_PropertyEntry()));
  }

  void _removeProperty(int index) {
    if (_properties.length <= 1) return;
    setState(() => _properties.removeAt(index).dispose());
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    setState(() => _formError = null);
    if (_clientId.isEmpty) {
      setState(() => _formError = 'Selecione o cliente.');
      return;
    }
    final validProperties = <Map<String, dynamic>>[];
    for (final p in _properties) {
      final address = p.address.text.trim();
      if (address.isEmpty) continue;
      final reference = p.reference.text.trim();
      validProperties.add({
        if ((p.propertyId ?? '').isNotEmpty) 'propertyId': p.propertyId,
        'address': address,
        if (reference.isNotEmpty) 'reference': reference,
        'displayOrder': validProperties.length,
      });
    }
    if (validProperties.isEmpty) {
      setState(() => _formError = 'Informe ao menos um imóvel (endereço).');
      return;
    }

    setState(() => _saving = true);
    final notes = _notes.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    final res = _isEdit
        ? await VisitReportService.instance.update(widget.reportId!, {
            'visitDate': _ymd(_visitDate),
            'properties': validProperties,
            if (notes.isNotEmpty) 'notes': notes,
            if (_initialReport?.kanbanTaskId != null)
              'kanbanTaskId': _initialReport!.kanbanTaskId,
          })
        : await VisitReportService.instance.create({
            'clientId': _clientId,
            'visitDate': _ymd(_visitDate),
            'properties': validProperties,
            if (notes.isNotEmpty) 'notes': notes,
          });

    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(_isEdit ? 'Relatório atualizado.' : 'Relatório criado.'),
      ));
      Navigator.of(context).pop(true);
    } else {
      setState(() => _formError = res.message ?? 'Erro ao salvar.');
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Editar visita' : 'Nova visita';

    if (!_canSubmit) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        body: _buildDenied(context),
      );
    }
    if (_loadingExisting) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        body: _buildLoadingSkeleton(),
      );
    }
    if (_loadError != null) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        body: _buildLoadError(context),
      );
    }

    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return AppScaffold(
      title: title,
      showBottomNavigation: false,
      body: Theme(
        data: _formTheme(context),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho editorial.
              Text(
                _isEdit
                    ? 'EDITAR RELATÓRIO'
                    : 'NOVO RELATÓRIO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isEdit
                    ? 'Altere os dados da visita e dos imóveis.'
                    : 'Registre a visita, selecione o cliente e os imóveis visitados.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              _sectionHeader(context, LucideIcons.userRound, 'Cliente',
                  'Quem realizou a visita.'),
              const SizedBox(height: 12),
              _clientField(context),

              const SizedBox(height: 22),
              _sectionHeader(context, LucideIcons.calendarDays,
                  'Data da visita', 'Quando a visita aconteceu.'),
              const SizedBox(height: 12),
              _dateField(context),

              const SizedBox(height: 22),
              _sectionHeader(
                  context,
                  LucideIcons.building2,
                  'Imóveis visitados',
                  'Busque no cadastro ou digite o endereço.'),
              const SizedBox(height: 12),
              for (var i = 0; i < _properties.length; i++) ...[
                _propertyBlock(context, i),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addProperty,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Adicionar imóvel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),
              _sectionHeader(context, LucideIcons.penLine, 'Observações',
                  'Opcional — impressões do cliente, próximos passos.'),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'Escreva aqui…',
                ),
              ),

              if (_formError != null) ...[
                const SizedBox(height: 14),
                _errorBanner(context, _formError!),
              ],

              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: secondary,
                        side: BorderSide(
                            color: ThemeHelpers.borderColor(context)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _saving
                            ? 'Salvando…'
                            : _isEdit
                                ? 'Salvar alterações'
                                : 'Criar relatório',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Blocos ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(
      BuildContext context, IconData icon, String title, String hint) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: _accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: secondary.withValues(alpha: 0.85),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Campo do cliente — abre o seletor; travado na edição.
  Widget _clientField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final filled = _clientId.isNotEmpty;
    final disabled = _isEdit;
    return InkWell(
      onTap: disabled ? null : _pickClient,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: disabled ? 0.025 : 0.045)
              : Colors.black.withValues(alpha: disabled ? 0.015 : 0.025),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.userRound,
              size: 17,
              color: filled ? _accent : secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                filled ? _clientName : 'Buscar por nome ou CPF…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: filled ? FontWeight.w800 : FontWeight.w500,
                  color: filled
                      ? ThemeHelpers.textColor(context)
                          .withValues(alpha: disabled ? 0.6 : 1)
                      : secondary.withValues(alpha: 0.75),
                ),
              ),
            ),
            if (!disabled)
              Icon(LucideIcons.chevronRight, size: 16, color: secondary),
            if (disabled) Icon(LucideIcons.lock, size: 14, color: secondary),
          ],
        ),
      ),
    );
  }

  Widget _dateField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat("EEEE, dd/MM/yyyy", 'pt_BR');
    final label = fmt.format(_visitDate);
    return InkWell(
      onTap: _pickVisitDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.045)
              : Colors.black.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, size: 17, color: _accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label[0].toUpperCase() + label.substring(1),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Bloco de um imóvel visitado — botão de busca no cadastro + endereço +
  /// referência (2 colunas) + remover na própria linha.
  Widget _propertyBlock(BuildContext context, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final entry = _properties[index];
    final linked = (entry.propertyId ?? '').isNotEmpty;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.cardBackgroundColor(context),
        boxShadow: ThemeHelpers.cardShadow(context, strength: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  linked ? 'Imóvel do cadastro' : 'Imóvel ${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: secondary,
                  ),
                ),
              ),
              InkResponse(
                radius: 18,
                onTap: () => _pickProperty(entry),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.search, size: 13, color: _accent),
                    const SizedBox(width: 4),
                    Text(
                      'Buscar no cadastro',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (_properties.length > 1) ...[
                const SizedBox(width: 12),
                InkResponse(
                  radius: 16,
                  onTap: () => _removeProperty(index),
                  child: Icon(LucideIcons.trash2, size: 15, color: danger),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: entry.address,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            decoration: const InputDecoration(labelText: 'Endereço *'),
            onChanged: (_) {
              // Endereço digitado manualmente desvincula o imóvel do cadastro.
              if (linked) setState(() => entry.propertyId = null);
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: entry.reference,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  decoration:
                      const InputDecoration(labelText: 'Referência'),
                ),
              ),
              if (linked) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: isDark ? 0.16 : 0.09),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: _accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.link, size: 11, color: _accent),
                      const SizedBox(width: 4),
                      Text(
                        'Vinculado',
                        style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 16, color: danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: danger,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          SkeletonText(width: 140, height: 12),
          SizedBox(height: 10),
          SkeletonText(width: double.infinity, height: 14),
          SizedBox(height: 24),
          SkeletonBox(width: double.infinity, height: 52, borderRadius: 14),
          SizedBox(height: 18),
          SkeletonBox(width: double.infinity, height: 52, borderRadius: 14),
          SizedBox(height: 18),
          SkeletonBox(width: double.infinity, height: 150, borderRadius: 16),
          SizedBox(height: 18),
          SkeletonBox(width: double.infinity, height: 96, borderRadius: 14),
        ],
      ),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 34, color: danger),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Relatório não encontrado.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadExisting,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDenied(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              _isEdit
                  ? 'Você não tem permissão para editar relatórios de visita.'
                  : 'Você não tem permissão para criar relatórios de visita.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
