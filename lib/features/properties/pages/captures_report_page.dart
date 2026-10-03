import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/file_delivery_sheet.dart';
import '../../clients/utils/client_spreadsheet.dart';
import '../services/captures_report_service.dart';
import '../utils/public_property_link.dart';

/// Relatório de captações — paridade com `CapturesReportPage.tsx` (web).
///
/// Conta os imóveis cadastrados no período pela EQUIPE DO IMÓVEL (não a do
/// corretor). Filtros: período (ou todo o cadastro), inativos, equipe do
/// imóvel, corretor/captador e responsável; mudar um filtro não recarrega
/// sozinho — "Aplicar filtros", como no web. Exporta a mesma planilha (4
/// abas). Gestor/admin/master veem também as auditorias de troca de
/// responsável e de downloads de imagens.
class CapturesReportPage extends StatefulWidget {
  const CapturesReportPage({super.key});

  /// Mesmo gate do web: papel de gestão OU criar/editar/excluir imóveis
  /// (`hasPropertyManagePermission`), com o módulo de imóveis ativo.
  static bool canOpen() {
    final access = ModuleAccessService.instance;
    if (!access.isModuleAvailableForCompany('property_management')) {
      return false;
    }
    return isManagementRole(access.userRole) ||
        access.hasAnyPermission(const [
          AppPermissions.propertyCreate,
          AppPermissions.propertyUpdate,
          AppPermissions.propertyDelete,
        ]);
  }

  static bool isManagementRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    return r == 'master' || r == 'admin' || r == 'manager';
  }

  @override
  State<CapturesReportPage> createState() => _CapturesReportPageState();
}

const int _pageSize = 20;

class _CapturesReportPageState extends State<CapturesReportPage> {
  final _service = CapturesReportService.instance;
  final _searchCtrl = TextEditingController();

  // Filtros na tela
  late DateTime _from;
  late DateTime _to;
  bool _allDates = false;
  bool _includeInactive = false;
  List<String> _teamIds = [];
  List<String> _capturerIds = [];
  List<String> _responsibleIds = [];

  // Opções
  List<CapturesTeamOption> _teamOptions = const [];
  List<CapturesReportPerson> _members = const [];
  CapturesTeamContext _teamContext = CapturesTeamContext.empty;
  String? _siteBase;

  // Resultado
  bool _loading = true;
  String? _error;
  int _errorStatus = 0;
  Object? _errorDetail;
  CapturesReportResult? _result;
  CapturesReportQuery? _loadedQuery;
  int _visible = _pageSize;
  int _ticket = 0;

  // Auditorias (gestão)
  bool _auditLoading = false;
  ResponsibleChangesResult? _changes;
  bool _changesForbidden = false;
  ImageDownloadsResult? _downloads;
  bool _downloadsForbidden = false;

  bool get _isManager => CapturesReportPage.isManagementRole(
        ModuleAccessService.instance.userRole,
      );

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = capturesStartOfMonth(now);
    _to = DateTime(now.year, now.month, now.day);
    _service.getCompanyMembers().then((m) {
      if (mounted) setState(() => _members = m);
    });
    PublicPropertyLink.resolveBaseUrl().then((b) {
      if (mounted) setState(() => _siteBase = b);
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  CapturesReportQuery get _query => CapturesReportQuery(
        allDates: _allDates,
        createdFrom: _from,
        createdTo: _to,
        propertyTeamIds: expandCapturesTeamIds(_teamIds, _teamOptions),
        capturerIds: _capturerIds,
        responsibleIds: _responsibleIds,
        includeInactive: _includeInactive,
      );

  bool get _dirty =>
      _loadedQuery != null && _loadedQuery!.cacheKey != _query.cacheKey;

  Future<void> _load() async {
    if (!_allDates && !isValidCapturesRange(_from, _to)) {
      _toast('Informe um período válido (data inicial ≤ data final).');
      return;
    }
    final ticket = ++_ticket;
    final query = _query;
    setState(() {
      _loading = true;
      _error = null;
      _visible = _pageSize;
      _searchCtrl.clear();
    });
    final results = await Future.wait([
      PropertyService.instance.getPropertyFormSettings(),
      _service.getReport(query),
    ]);
    if (!mounted || ticket != _ticket) return;
    final settings = results[0] as ApiResponse<PropertyFormSettingsBundle>;
    final report = results[1] as ApiResponse<CapturesReportResult>;
    setState(() {
      _loading = false;
      if (settings.success && settings.data != null) {
        _teamOptions = buildCapturesTeamOptions(settings.data!.teams);
        _teamContext = CapturesTeamContext.fromTeams(settings.data!.teams);
      }
      if (report.success && report.data != null) {
        _result = report.data;
        _loadedQuery = query;
      } else {
        _error = report.message ?? 'Erro ao carregar o relatório.';
        _errorStatus = report.statusCode;
        _errorDetail = report.error;
      }
    });
    if (report.success && _isManager) _loadAudits(query);
  }

  Future<void> _loadAudits(CapturesReportQuery q) async {
    final start = q.allDates ? '2000-01-01' : capturesYmd(q.createdFrom);
    final end = q.allDates ? null : capturesYmd(q.createdTo);
    setState(() => _auditLoading = true);
    final res = await Future.wait([
      _service.getResponsibleChanges(startDate: start, endDate: end),
      _service.getImageDownloads(startDate: start, endDate: end),
    ]);
    if (!mounted) return;
    final changes = res[0] as ApiResponse<ResponsibleChangesResult>;
    final downloads = res[1] as ApiResponse<ImageDownloadsResult>;
    setState(() {
      _auditLoading = false;
      _changes = changes.data;
      _changesForbidden = changes.statusCode == 403;
      _downloads = downloads.data;
      _downloadsForbidden = downloads.statusCode == 403;
    });
  }

  void _clearOptional() {
    setState(() {
      _allDates = false;
      _includeInactive = false;
      _teamIds = [];
      _capturerIds = [];
      _responsibleIds = [];
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
  }

  // ── Rótulos ──────────────────────────────────────────────────────────

  String get _periodLabel =>
      capturesPeriodLabel(allDates: _allDates, from: _from, to: _to);

  Map<String, String> get _memberNames => {
        for (final m in _members) m.id: m.displayName,
      };

  /// Corretores = membros + quem aparece nas estatísticas (ex.: inativo).
  List<CapturesReportPerson> get _capturerOptions {
    final byId = {for (final m in _members) m.id: m};
    for (final c in _result?.statistics.byCapturer ?? const <CapturerStat>[]) {
      byId.putIfAbsent(
        c.capturerId,
        () => CapturesReportPerson(
          id: c.capturerId,
          name: c.capturerName,
          email: c.capturerEmail,
        ),
      );
    }
    return byId.values.toList()
      ..sort((a, b) => a.displayName
          .toLowerCase()
          .compareTo(b.displayName.toLowerCase()));
  }

  String _labels(List<String> ids, Map<String, String> names, String all) =>
      ids.isEmpty ? all : ids.map((id) => names[id] ?? id).join(', ');

  Map<String, String> get _teamNames => {
        for (final t in _teamOptions) t.id: t.name,
      };

  // ── Ações ────────────────────────────────────────────────────────────

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      locale: const Locale('pt', 'BR'),
      helpText: 'Período de cadastro',
      saveText: 'Usar período',
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
      _allDates = false;
    });
  }

  void _preset(String id) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _allDates = false;
      switch (id) {
        case 'month':
          _from = capturesStartOfMonth(now);
          _to = today;
        case 'last_month':
          _from = DateTime(now.year, now.month - 1);
          _to = DateTime(now.year, now.month, 0);
        case '30':
          _from = today.subtract(const Duration(days: 29));
          _to = today;
        case '90':
          _from = today.subtract(const Duration(days: 89));
          _to = today;
        case 'year':
          _from = DateTime(now.year);
          _to = today;
      }
    });
  }

  Future<void> _pickMany({
    required String title,
    required IconData icon,
    required List<(String, String, String?)> options,
    required List<String> selected,
    required ValueChanged<List<String>> onDone,
  }) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MultiSelectSheet(
        title: title,
        icon: icon,
        options: options,
        initial: selected,
      ),
    );
    if (result != null && mounted) setState(() => onDone(result));
  }

  Future<void> _export() async {
    if (_dirty) {
      _toast('Filtros alterados. Toque em "Aplicar filtros" antes de exportar.');
      return;
    }
    final result = _result;
    final query = _loadedQuery;
    if (result == null || query == null) return;
    final sheets = buildCapturesWorkbookSheets(
      properties: result.properties,
      statistics: result.statistics,
      teamContext: _teamContext,
      query: query,
      teamLabels: _labels(_teamIds, _teamNames, ''),
      capturerLabels: _labels(_capturerIds, _memberNames, ''),
      responsibleLabels: _labels(_responsibleIds, _memberNames, ''),
      publicSiteBase: _siteBase,
    );
    await showFileDeliverySheet(
      context,
      title: 'Relatório de captações',
      subtitle: '$_periodLabel · ${result.properties.length} imóveis',
      paper: FileDeliveryPaper.spreadsheet,
      expectedType: 'XLSX',
      generatingTitle: 'Montando a planilha…',
      readyTitle: 'Planilha pronta',
      shareSubject: 'Relatório de captações',
      load: () async => ApiResponse.success(
        statusCode: 200,
        data: DeliverableFile(
          bytes: ClientSpreadsheet.buildXlsxSheets([
            for (final s in sheets)
              (name: s.name, rows: s.rows, widths: s.widths),
          ]),
          fileName: capturesReportFileName(DateTime.now()),
        ),
      ),
    );
  }

  Future<void> _exportAudit({
    required String title,
    required String fileName,
    required List<({String name, List<List<Object?>> rows, List<double>? widths})>
        sheets,
  }) {
    return showFileDeliverySheet(
      context,
      title: title,
      subtitle: _periodLabel,
      paper: FileDeliveryPaper.spreadsheet,
      expectedType: 'XLSX',
      readyTitle: 'Planilha pronta',
      shareSubject: title,
      load: () async => ApiResponse.success(
        statusCode: 200,
        data: DeliverableFile(
          bytes: ClientSpreadsheet.buildXlsxSheets(sheets),
          fileName: fileName,
        ),
      ),
    );
  }

  String get _periodSlug => _loadedQuery == null || _loadedQuery!.allDates
      ? 'todo-cadastro'
      : '${capturesYmd(_loadedQuery!.createdFrom)}_a_'
          '${capturesYmd(_loadedQuery!.createdTo)}';

  Future<void> _openSite(CapturesReportProperty p) async {
    final base = _siteBase;
    if (base == null) return;
    final ident = (p.code ?? '').isNotEmpty ? p.code! : p.id;
    try {
      await launchUrl(
        Uri.parse('$base/imovel/${Uri.encodeComponent(ident)}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (mounted) _toast('Não foi possível abrir o site.');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Relatório de captações',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Exportar Excel',
          onPressed: _loading || _result == null ? null : _export,
          icon: const Icon(LucideIcons.download, size: 20),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _intro(context)),
            SliverToBoxAdapter(child: _filtersCard(context)),
            if (_dirty && !_loading)
              SliverToBoxAdapter(child: _staleBanner(context)),
            if (_error != null && _result == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppErrorState.fromApi(
                  message: _error,
                  statusCode: _errorStatus,
                  error: _errorDetail,
                  onRetry: _load,
                ),
              )
            else ...[
              SliverToBoxAdapter(child: _statsGrid(context)),
              SliverToBoxAdapter(child: _rankings(context)),
              ..._propertiesSection(context),
              if (_isManager) ...[
                if (!_changesForbidden)
                  SliverToBoxAdapter(child: _changesSection(context)),
                if (!_downloadsForbidden)
                  SliverToBoxAdapter(child: _downloadsSection(context)),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 36)),
          ],
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final total = _result?.properties.length ?? 0;
    final caps = _result == null
        ? 0
        : buildCapturerRanking(_result!.properties).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.chartColumn, size: 12, color: accent),
              const SizedBox(width: 6),
              Text(
                'RELATÓRIOS · CAPTAÇÕES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Relatório de captações',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Total de imóveis pela equipe cadastrada no imóvel (não pela '
            'equipe do corretor). Filtre por período, equipe e exporte.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
          ),
          if (!_loading && total > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _ToneChip(
                  tone: const Color(0xFF0EA5E9),
                  icon: LucideIcons.house,
                  text: '$total ${total == 1 ? 'imóvel' : 'imóveis'}',
                ),
                _ToneChip(
                  tone: const Color(0xFF10B981),
                  icon: LucideIcons.user,
                  text: '$caps ${caps == 1 ? 'captador' : 'captadores'}',
                ),
                _ToneChip(
                  tone: const Color(0xFF6366F1),
                  icon: LucideIcons.calendar,
                  text: _loadedQuery == null
                      ? _periodLabel
                      : capturesPeriodLabel(
                          allDates: _loadedQuery!.allDates,
                          from: _loadedQuery!.createdFrom,
                          to: _loadedQuery!.createdTo,
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filtersCard(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final isDark = theme.brightness == Brightness.dark;
    final presets = const [
      ('month', 'Este mês'),
      ('last_month', 'Mês passado'),
      ('30', '30 dias'),
      ('90', '90 dias'),
      ('year', 'Este ano'),
    ];
    final teamNames = _teamNames;
    final memberNames = _memberNames;

    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Roundel(icon: LucideIcons.slidersHorizontal, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtros do relatório',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Conta pela equipe cadastrada no imóvel',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Período
          InkWell(
            onTap: _allDates ? null : _pickRange,
            borderRadius: BorderRadius.circular(14),
            child: Opacity(
              opacity: _allDates ? 0.45 : 1,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1)
                          .withValues(alpha: isDark ? 0.22 : 0.10),
                      const Color(0xFF0EA5E9)
                          .withValues(alpha: isDark ? 0.16 : 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.calendarRange,
                        size: 20, color: Color(0xFF6366F1)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PERÍODO DE CADASTRO',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: muted,
                            ),
                          ),
                          Text(
                            '${DateFormat('dd/MM/yyyy').format(_from)} – '
                            '${DateFormat('dd/MM/yyyy').format(_to)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.pencil, size: 16, color: muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: presets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => ActionChip(
                label: Text(presets[i].$2),
                onPressed: () => _preset(presets[i].$1),
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _SwitchRow(
            icon: LucideIcons.infinity,
            title: 'Todo o cadastro',
            subtitle: 'Ignora as datas (até 50 mil imóveis)',
            value: _allDates,
            onChanged: (v) => setState(() => _allDates = v),
          ),
          _SwitchRow(
            icon: LucideIcons.eyeOff,
            title: 'Incluir imóveis inativos',
            subtitle: 'Mesmo critério da listagem de imóveis',
            value: _includeInactive,
            onChanged: (v) => setState(() => _includeInactive = v),
          ),
          const SizedBox(height: 6),
          _SelectTile(
            icon: LucideIcons.users,
            color: const Color(0xFFF59E0B),
            label: 'Equipe do imóvel',
            value: _labels(_teamIds, teamNames, 'Todas as equipes'),
            count: _teamIds.length,
            onTap: () => _pickMany(
              title: 'Equipe do imóvel',
              icon: LucideIcons.users,
              options: [for (final t in _teamOptions) (t.id, t.name, null)],
              selected: _teamIds,
              onDone: (ids) => _teamIds = ids,
            ),
          ),
          _SelectTile(
            icon: LucideIcons.userSearch,
            color: const Color(0xFF10B981),
            label: 'Corretor / captador',
            value: _labels(_capturerIds, memberNames, 'Todos os corretores'),
            count: _capturerIds.length,
            onTap: () => _pickMany(
              title: 'Corretor / captador',
              icon: LucideIcons.userSearch,
              options: [
                for (final m in _capturerOptions)
                  (m.id, m.displayName, m.email),
              ],
              selected: _capturerIds,
              onDone: (ids) => _capturerIds = ids,
            ),
          ),
          _SelectTile(
            icon: LucideIcons.badgeCheck,
            color: const Color(0xFF6366F1),
            label: 'Responsável',
            value: _labels(_responsibleIds, memberNames, 'Todos os responsáveis'),
            count: _responsibleIds.length,
            onTap: () => _pickMany(
              title: 'Responsável',
              icon: LucideIcons.badgeCheck,
              options: [
                for (final m in _members) (m.id, m.displayName, m.email),
              ],
              selected: _responsibleIds,
              onDone: (ids) => _responsibleIds = ids,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 16),
                  label: Text(_dirty ? 'Aplicar filtros' : 'Atualizar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (_query.hasOptionalFilters) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loading ? null : _clearOptional,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Limpar'),
                ),
              ],
              const SizedBox(width: 8),
              Tooltip(
                message: 'Exportar Excel',
                child: OutlinedButton(
                  onPressed:
                      _loading || _result == null || _dirty ? null : _export,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(13),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Icon(LucideIcons.fileSpreadsheet, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _staleBanner(BuildContext context) {
    const tone = Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.refreshCw, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Filtros alterados — os números abaixo ainda são da última '
              'consulta. Toque em "Aplicar filtros".',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(BuildContext context) {
    final r = _result;
    final total = r?.properties.length ?? 0;
    final caps = r == null
        ? 0
        : (r.properties.isNotEmpty
            ? buildCapturerRanking(r.properties).length
            : r.statistics.byCapturer.length);
    final q = _loadedQuery;
    final subtitle = q == null
        ? ''
        : q.allDates
            ? (q.includeInactive
                ? 'Todo o cadastro (ativos e inativos)'
                : 'Todo o cadastro (somente ativos)')
            : 'Cadastrados no período · equipe do imóvel';
    final fmt = NumberFormat.decimalPattern('pt_BR');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('RESUMO DO PERÍODO'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  tone: const Color(0xFF0EA5E9),
                  icon: LucideIcons.house,
                  label: 'Total de imóveis',
                  value: _loading ? '…' : fmt.format(total),
                  sub: subtitle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  tone: const Color(0xFF10B981),
                  icon: LucideIcons.user,
                  label: 'Captadores',
                  value: _loading ? '…' : fmt.format(caps),
                  sub: 'Com captação no período',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StatTile(
            tone: const Color(0xFF6366F1),
            icon: LucideIcons.calendar,
            label: 'Período',
            value: q == null
                ? _periodLabel
                : capturesPeriodLabel(
                    allDates: q.allDates,
                    from: q.createdFrom,
                    to: q.createdTo,
                  ),
            valueSize: 16,
            sub: _dirty
                ? 'Toque em Aplicar filtros'
                : (q == null || !q.hasOptionalFilters
                    ? 'Período por data de cadastro'
                    : [
                        if (_teamIds.isNotEmpty)
                          'Equipes: ${_labels(_teamIds, _teamNames, '')}',
                        if (_capturerIds.isNotEmpty)
                          'Corretores: ${_labels(_capturerIds, _memberNames, '')}',
                        if (_responsibleIds.isNotEmpty)
                          'Responsáveis: '
                              '${_labels(_responsibleIds, _memberNames, '')}',
                        if (q.includeInactive) 'Inclui inativos',
                        if (q.allDates) 'Todo o cadastro',
                      ].join(' · ')),
          ),
          if (r?.statistics.propertiesSold != null) ...[
            const SizedBox(height: 10),
            _StatTile(
              tone: const Color(0xFFDB2777),
              icon: LucideIcons.handshake,
              label: 'Vendidos/alugados no período',
              value: fmt.format(r!.statistics.propertiesSold),
              sub: r.statistics.propertiesSoldRate == null
                  ? ''
                  : 'Conversão de '
                      '${r.statistics.propertiesSoldRate!.toStringAsFixed(1).replaceAll('.', ',')}%',
            ),
          ],
        ],
      ),
    );
  }

  Widget _rankings(BuildContext context) {
    final r = _result;
    final caps = r == null
        ? const <CapturesRankingItem>[]
        : (r.properties.isNotEmpty || _loadedQuery != null
            ? buildCapturerRanking(r.properties)
            : [
                for (final c in r.statistics.byCapturer)
                  CapturesRankingItem(
                    id: c.capturerId,
                    name: c.capturerName,
                    count: c.propertiesCount,
                  ),
              ]);
    final teams = r == null
        ? const <CapturesRankingItem>[]
        : onlyConfiguredTeams(
            buildTeamRanking(r.properties, _teamContext),
            _teamContext,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('RANKINGS'),
          const SizedBox(height: 8),
          _RankingCard(
            icon: LucideIcons.trophy,
            title: 'Top 5 captadores',
            items: caps.take(5).toList(),
            loading: _loading,
            empty: 'Nenhum captador no período.',
          ),
          const SizedBox(height: 10),
          _RankingCard(
            icon: LucideIcons.users,
            title: 'Top 5 equipes (imóvel)',
            items: teams.take(5).toList(),
            loading: _loading,
            empty: 'Nenhuma equipe no período.',
          ),
        ],
      ),
    );
  }

  List<Widget> _propertiesSection(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final all = _result?.properties ?? const <CapturesReportProperty>[];
    final filtered =
        filterCapturesProperties(all, _searchCtrl.text, _teamContext);
    final shown = filtered.take(_visible).toList();
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: _Eyebrow('IMÓVEIS CAPTADOS')),
                  if (!_loading)
                    Text(
                      NumberFormat.decimalPattern('pt_BR')
                          .format(filtered.length),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary.primary,
                      ),
                    ),
                ],
              ),
              if (!_loading && all.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() => _visible = _pageSize),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar por código, título, captador…',
                    prefixIcon:
                        Icon(LucideIcons.search, size: 18, color: muted),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(LucideIcons.x, size: 16, color: muted),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _visible = _pageSize;
                            }),
                          ),
                    filled: true,
                    fillColor: ThemeHelpers.cardBackgroundColor(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: ThemeHelpers.borderColor(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: ThemeHelpers.borderColor(context)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      if (_loading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (filtered.isEmpty)
        SliverToBoxAdapter(
          child: _Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(LucideIcons.searchX, size: 30, color: muted),
                  const SizedBox(height: 8),
                  Text(
                    all.isEmpty
                        ? 'Nenhum imóvel encontrado no período'
                            '${_loadedQuery?.hasOptionalFilters == true ? ' com os filtros selecionados' : ''}.'
                        : 'Nenhum imóvel corresponde à busca.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _CapturedCard(
              property: shown[i],
              teamLabel: capturesTableTeamLabel(shown[i], _teamContext),
              hasSite: _siteBase != null,
              onOpen: () => Navigator.of(context)
                  .pushNamed(AppRoutes.propertyDetails(shown[i].id)),
              onSite: () => _openSite(shown[i]),
            ),
          ),
        ),
        if (filtered.length > shown.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visible += _pageSize),
                icon: const Icon(LucideIcons.chevronsDown, size: 16),
                label: Text(
                  'Ver mais (${filtered.length - shown.length} restantes)',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
      ],
    ];
  }

  Widget _changesSection(BuildContext context) {
    final items = _changes?.items ?? const <ResponsibleChangeItem>[];
    final df = DateFormat('dd/MM/yyyy HH:mm');
    return _AuditSection(
      icon: LucideIcons.arrowLeftRight,
      color: const Color(0xFF0891B2),
      title: 'Trocas de responsável',
      subtitle: 'Alterações de responsável (principal e adicionais) no '
          'período, com quem alterou.',
      countLabel: _changes == null
          ? null
          : '${items.length} ${items.length == 1 ? 'troca' : 'trocas'}',
      loading: _auditLoading,
      empty: _changes == null
          ? 'Aplique os filtros para carregar as trocas de responsável.'
          : 'Nenhuma troca de responsável no período.',
      onExport: items.isEmpty
          ? null
          : () => _exportAudit(
                title: 'Trocas de responsável',
                fileName: 'trocas-responsavel-$_periodSlug.xlsx',
                sheets: [
                  (
                    name: 'Trocas de responsável',
                    rows: [
                      [
                        'Data/Hora', 'Código', 'Imóvel', 'Tipo',
                        'Antes', 'Depois', 'Alterado por',
                      ],
                      for (final it in items)
                        [
                          it.changedAt == null ? '' : df.format(it.changedAt!),
                          it.propertyCode ?? '—',
                          it.propertyTitle,
                          it.isPrincipal ? 'Principal' : 'Adicionais',
                          it.previousLabel,
                          it.currentLabel,
                          it.changedByName ?? '—',
                        ],
                    ],
                    widths: const [18, 10, 45, 12, 30, 30, 24],
                  ),
                ],
              ),
      children: [
        for (final it in items.take(30))
          _AuditRow(
            leading: it.isPrincipal ? 'Principal' : 'Adicionais',
            title: '${it.propertyCode ?? '—'} · ${it.propertyTitle}',
            line: '${it.previousLabel.isEmpty ? '—' : it.previousLabel}  →  '
                '${it.currentLabel.isEmpty ? '—' : it.currentLabel}',
            meta: [
              if (it.changedAt != null) df.format(it.changedAt!),
              if (it.changedByName != null) 'por ${it.changedByName}',
            ].join(' · '),
            onTap: it.propertyId.isEmpty
                ? null
                : () => Navigator.of(context)
                    .pushNamed(AppRoutes.propertyDetails(it.propertyId)),
          ),
        if (items.length > 30)
          _MoreHint('+${items.length - 30} na planilha exportada'),
      ],
    );
  }

  Widget _downloadsSection(BuildContext context) {
    final data = _downloads;
    final items = data?.items ?? const <ImageDownloadItem>[];
    final perUser = summarizeImageDownloads(items);
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final total = data?.totalImages ?? 0;
    return _AuditSection(
      icon: LucideIcons.images,
      color: const Color(0xFFDB2777),
      title: 'Downloads de imagens',
      subtitle: 'Quem baixou imagens dos imóveis no período — quando, qual '
          'imóvel, ZIP ou individual e quantas.',
      countLabel: data == null
          ? null
          : '${items.length} download${items.length == 1 ? '' : 's'} · '
              '$total imagem${total == 1 ? '' : 's'}',
      loading: _auditLoading,
      empty: data == null
          ? 'Aplique os filtros para carregar os downloads de imagens.'
          : 'Nenhum download de imagem registrado no período.',
      onExport: items.isEmpty
          ? null
          : () => _exportAudit(
                title: 'Downloads de imagens',
                fileName: 'downloads-imagens-$_periodSlug.xlsx',
                sheets: [
                  (
                    name: 'Downloads',
                    rows: [
                      [
                        'Data/Hora', 'Usuário', 'Tipo', 'Qtd. imagens',
                        'Código', 'Imóvel', 'Status',
                      ],
                      for (final it in items)
                        [
                          it.downloadedAt == null
                              ? ''
                              : df.format(it.downloadedAt!),
                          it.userName ?? '(usuário removido)',
                          it.isZip ? 'ZIP' : 'Individual',
                          it.count,
                          it.propertyCode ?? '—',
                          it.propertyTitle,
                          it.propertyStatus ?? '—',
                        ],
                    ],
                    widths: const [18, 28, 12, 12, 10, 55, 22],
                  ),
                  (
                    name: 'Resumo por usuário',
                    rows: [
                      [
                        'Usuário', 'Nº de downloads', 'Total de imagens',
                        'Último download',
                      ],
                      for (final u in perUser)
                        [
                          u.user,
                          u.downloads,
                          u.images,
                          u.lastAt == null ? '' : df.format(u.lastAt!),
                        ],
                    ],
                    widths: const [28, 16, 16, 18],
                  ),
                ],
              ),
      children: [
        if (perUser.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final u in perUser.take(6))
                  _ToneChip(
                    tone: const Color(0xFFDB2777),
                    icon: LucideIcons.user,
                    text: '${u.user} · ${u.images} img',
                  ),
              ],
            ),
          ),
        for (final it in items.take(30))
          _AuditRow(
            leading: it.isZip ? 'ZIP · ${it.count}' : 'Individual',
            title: '${it.propertyCode ?? '—'} · ${it.propertyTitle}',
            line: it.userName ?? '(usuário removido)',
            meta: it.downloadedAt == null ? '' : df.format(it.downloadedAt!),
            onTap: it.propertyId.isEmpty
                ? null
                : () => Navigator.of(context)
                    .pushNamed(AppRoutes.propertyDetails(it.propertyId)),
          ),
        if (items.length > 30)
          _MoreHint('+${items.length - 30} na planilha exportada'),
      ],
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: ThemeHelpers.textSecondaryColor(context),
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        fontSize: 10.5,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.margin});
  final Widget child;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Roundel extends StatelessWidget {
  const _Roundel({required this.icon, required this.color, this.size = 38});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.36 : 0.24)),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

class _ToneChip extends StatelessWidget {
  const _ToneChip({required this.tone, required this.icon, required this.text});
  final Color tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: value ? AppColors.primary.primary : muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ],
              ),
            ),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: count > 0
                    ? color.withValues(alpha: 0.5)
                    : ThemeHelpers.borderColor(context),
              ),
            ),
            child: Row(
              children: [
                _Roundel(icon: icon, color: color, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          color: muted,
                        ),
                      ),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                Icon(LucideIcons.chevronRight, size: 18, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    this.valueSize = 24,
  });

  final Color tone;
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tone.withValues(alpha: isDark ? 0.24 : 0.13),
            tone.withValues(alpha: isDark ? 0.08 : 0.03),
          ],
        ),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: tone.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: muted, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.icon,
    required this.title,
    required this.items,
    required this.loading,
    required this.empty,
  });

  final IconData icon;
  final String title;
  final List<CapturesRankingItem> items;
  final bool loading;
  final String empty;

  static const _medals = [
    Color(0xFFF59E0B),
    Color(0xFF94A3B8),
    Color(0xFFB45309),
  ];

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final max = items.isEmpty ? 1 : items.first.count.clamp(1, 1 << 30);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Roundel(icon: icon, color: accent, size: 34),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(empty, style: TextStyle(color: muted)),
            )
          else
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < 3
                                ? _medals[i]
                                : accent.withValues(alpha: 0.14),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              color: i < 3 ? Colors.white : accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            items[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Text(
                          '${items[i].count} '
                          '${items[i].count == 1 ? 'imóvel' : 'imóveis'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: items[i].count / max,
                        minHeight: 7,
                        backgroundColor:
                            ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
                        valueColor: AlwaysStoppedAnimation(
                          i < 3 ? _medals[i] : accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _CapturedCard extends StatelessWidget {
  const _CapturedCard({
    required this.property,
    required this.teamLabel,
    required this.hasSite,
    required this.onOpen,
    required this.onSite,
  });

  final CapturesReportProperty property;
  final String teamLabel;
  final bool hasSite;
  final VoidCallback onOpen;
  final VoidCallback onSite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.primary.primary;
    final Color teamTone = switch (teamLabel) {
      kNoTeamLabel => const Color(0xFFF59E0B),
      kOutsideTeamLabel => const Color(0xFF64748B),
      _ => const Color(0xFF6366F1),
    };
    final created = property.createdAt == null
        ? '—'
        : DateFormat('dd/MM/yyyy HH:mm').format(property.createdAt!);

    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      property.code ?? '—',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: teamTone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          teamLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: teamTone,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (hasSite)
                    IconButton(
                      tooltip: 'Abrir no site',
                      visualDensity: VisualDensity.compact,
                      onPressed: onSite,
                      icon: Icon(LucideIcons.globe, size: 17, color: accent),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                property.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _Meta(icon: LucideIcons.userSearch, label: 'Captador',
                      value: property.captorName),
                  _Meta(icon: LucideIcons.badgeCheck, label: 'Responsável',
                      value: property.responsibleName),
                  _Meta(icon: LucideIcons.calendarPlus, label: 'Cadastro',
                      value: created),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: muted),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(fontSize: 11.5, color: muted)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _AuditSection extends StatelessWidget {
  const _AuditSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.countLabel,
    required this.loading,
    required this.empty,
    required this.onExport,
    required this.children,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? countLabel;
  final bool loading;
  final String empty;
  final VoidCallback? onExport;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return _Card(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Roundel(icon: icon, color: color, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    if (countLabel != null && !loading)
                      Text(
                        countLabel!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Exportar Excel',
                onPressed: loading ? null : onExport,
                icon: const Icon(LucideIcons.fileSpreadsheet, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 10),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(empty, style: TextStyle(color: muted)),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({
    required this.leading,
    required this.title,
    required this.line,
    required this.meta,
    this.onTap,
  });

  final String leading;
  final String title;
  final String line;
  final String meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  leading.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: AppColors.primary.primary,
                  ),
                ),
                const Spacer(),
                Text(meta, style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreHint extends StatelessWidget {
  const _MoreHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
    );
  }
}

/// Seleção múltipla com busca (equipes, corretores, responsáveis).
class _MultiSelectSheet extends StatefulWidget {
  const _MultiSelectSheet({
    required this.title,
    required this.icon,
    required this.options,
    required this.initial,
  });

  final String title;
  final IconData icon;
  final List<(String, String, String?)> options;
  final List<String> initial;

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<String> _sel = {...widget.initial};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.options
        : widget.options
            .where((o) =>
                o.$2.toLowerCase().contains(q) ||
                (o.$3 ?? '').toLowerCase().contains(q))
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  _Roundel(icon: widget.icon, color: accent, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (_sel.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_sel.clear),
                      child: const Text('Limpar'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar…',
                  prefixIcon: Icon(LucideIcons.search, size: 18, color: muted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        widget.options.isEmpty
                            ? 'Nenhuma opção disponível'
                            : 'Nada encontrado',
                        style: TextStyle(color: muted),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final (id, label, sub) = list[i];
                        return CheckboxListTile(
                          value: _sel.contains(id),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _sel.add(id);
                            } else {
                              _sel.remove(id);
                            }
                          }),
                          title: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: sub == null || sub == label
                              ? null
                              : Text(sub, style: TextStyle(color: muted)),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: accent,
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop([
                      for (final o in widget.options)
                        if (_sel.contains(o.$1)) o.$1,
                    ]),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _sel.isEmpty
                          ? 'Usar todos'
                          : 'Aplicar ${_sel.length} '
                              '${_sel.length == 1 ? 'seleção' : 'seleções'}',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
