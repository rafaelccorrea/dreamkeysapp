import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/shimmer_image.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../condominium_routes.dart';
import '../models/development_models.dart';
import '../services/development_service.dart';
import '../widgets/estate_shared.dart';

/// Detalhe do **empreendimento** — herda a gramática de seções do Perfil:
/// masthead editorial (eyebrow + headline w900 + subtítulo), manchete com
/// placa de imagem + meta pills, quick KPI strip de 3 colunas e seções
/// full-bleed com header editorial (barra tonal + eyebrow + título grande),
/// divisores finos e placas de ícone tom-on-tom. Uma cor por seção.
class DevelopmentDetailPage extends StatefulWidget {
  final String developmentId;

  const DevelopmentDetailPage({super.key, required this.developmentId});

  @override
  State<DevelopmentDetailPage> createState() => _DevelopmentDetailPageState();
}

class _DevelopmentDetailPageState extends State<DevelopmentDetailPage> {
  Development? _development;
  bool _loading = true;
  String? _error;
  bool _changed = false;

  bool get _canView =>
      ModuleAccessService.instance.hasCompanyModule('property_management') &&
      ModuleAccessService.instance.hasPermission('condominium:view');
  bool get _canEdit =>
      ModuleAccessService.instance.hasPermission('condominium:update');

  Color _accent(BuildContext context) => EstateTones.purple(context);
  Color _indigo(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF818CF8)
          : const Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    if (_canView) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await DevelopmentService.instance.getById(widget.developmentId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _development = res.data;
      } else {
        _error = res.message ?? 'Erro ao carregar empreendimento';
      }
    });
  }

  Future<void> _goToEdit() async {
    final result = await Navigator.of(context)
        .pushNamed(CondominiumRoutes.developmentEdit(widget.developmentId));
    if (result == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _openUrl(String rawUrl) async {
    final raw = rawUrl.trim();
    if (raw.isEmpty) return;
    final url = raw.startsWith('http') ? raw : 'https://$raw';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível abrir o link'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return AppScaffold(
        title: 'Empreendimento',
        showBottomNavigation: false,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.lock,
                    size: 38, color: ThemeHelpers.textSecondaryColor(context)),
                const SizedBox(height: 12),
                Text(
                  'Você não tem acesso a este empreendimento.',
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
        ),
      );
    }

    Widget body;
    if (_loading) {
      body = _buildSkeleton(context);
    } else if (_error != null) {
      body = EstateErrorState(message: _error!, onRetry: _load);
    } else if (_development == null) {
      body = EstateErrorState(
        message: 'Empreendimento não encontrado',
        onRetry: _load,
      );
    } else {
      body = RefreshIndicator(
        color: _accent(context),
        onRefresh: _load,
        child: _buildContent(context, _development!),
      );
    }

    // Devolve `true` para a lista recarregar se algo mudou na edição.
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(true);
      },
      child: AppScaffold(
        title: 'Empreendimento',
        showBottomNavigation: false,
        body: body,
      ),
    );
  }

  Widget _buildContent(BuildContext context, Development d) {
    final accent = _accent(context);
    final blue = EstateTones.blue(context);
    final amber = EstateTones.amber(context);
    final indigo = _indigo(context);
    final slate = ThemeHelpers.textSecondaryColor(context);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMasthead(context, d),
          const SizedBox(height: 18),
          _buildManchete(context, d),
          const SizedBox(height: 14),
          _buildQuickStrip(context, d),
          const SizedBox(height: 14),
          _sectionSeparator(context),
          const SizedBox(height: 22),
          // ── Sobre ────────────────────────────────────────────────────
          _EstateSectionHeader(
            eyebrow: 'APRESENTAÇÃO',
            title: 'Sobre o empreendimento',
            subtitle: 'O resumo que a equipe usa na abordagem de venda.',
            tone: accent,
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: (d.description ?? '').trim().isEmpty
                ? Text(
                    'Nenhuma descrição cadastrada ainda.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: slate,
                          fontStyle: FontStyle.italic,
                        ),
                  )
                : Text(
                    d.description!.trim(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          height: 1.5,
                        ),
                  ),
          ),
          const SizedBox(height: 28),
          _sectionSeparator(context),
          const SizedBox(height: 22),
          // ── Localização ──────────────────────────────────────────────
          _EstateSectionHeader(
            eyebrow: 'ONDE FICA',
            title: 'Localização',
            subtitle: 'Endereço completo do empreendimento.',
            tone: blue,
          ),
          const SizedBox(height: 10),
          _EstateInfoLine(
            tone: blue,
            icon: LucideIcons.mapPin,
            label: 'Endereço',
            value: d.fullAddressLine.trim().isEmpty
                ? '—'
                : d.fullAddressLine.trim(),
          ),
          _rowDivider(context),
          _EstateInfoLine(
            tone: blue,
            icon: LucideIcons.map,
            label: 'Cidade / UF',
            value: d.cityState.trim().isEmpty ? '—' : d.cityState.trim(),
          ),
          _rowDivider(context),
          _EstateInfoLine(
            tone: blue,
            icon: LucideIcons.mapPinned,
            label: 'CEP',
            value: d.zipCode.trim().isEmpty ? '—' : d.zipCode.trim(),
          ),
          const SizedBox(height: 28),
          _sectionSeparator(context),
          const SizedBox(height: 22),
          // ── Contato & registro ───────────────────────────────────────
          _EstateSectionHeader(
            eyebrow: 'CONTATO & REGISTRO',
            title: 'Dados institucionais',
            subtitle: 'CNPJ, contato e presença online da incorporadora.',
            tone: indigo,
          ),
          const SizedBox(height: 10),
          _EstateInfoLine(
            tone: indigo,
            icon: LucideIcons.landmark,
            label: 'CNPJ',
            value: formatCnpjPretty(d.cnpj).isEmpty
                ? '—'
                : formatCnpjPretty(d.cnpj),
          ),
          _rowDivider(context),
          _EstateInfoLine(
            tone: indigo,
            icon: LucideIcons.phone,
            label: 'Telefone',
            value: (d.phone ?? '').trim().isEmpty ? '—' : d.phone!.trim(),
          ),
          _rowDivider(context),
          _EstateInfoLine(
            tone: indigo,
            icon: LucideIcons.mail,
            label: 'E-mail',
            value: (d.email ?? '').trim().isEmpty ? '—' : d.email!.trim(),
          ),
          if (websiteHost(d.website).isNotEmpty) ...[
            _rowDivider(context),
            _EstateNavigationLine(
              tone: indigo,
              icon: LucideIcons.globe,
              title: 'Abrir site',
              subtitle: websiteHost(d.website),
              trailing: Icon(
                LucideIcons.externalLink,
                size: 16,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              onTap: () => _openUrl(d.website!),
            ),
          ],
          const SizedBox(height: 28),
          _sectionSeparator(context),
          const SizedBox(height: 22),
          // ── Material da equipe ───────────────────────────────────────
          _buildMaterialSection(context, d),
          const SizedBox(height: 28),
          _sectionSeparator(context),
          const SizedBox(height: 22),
          // ── Galeria ──────────────────────────────────────────────────
          _buildGallerySection(context, d, amber),
          const SizedBox(height: 28),
          _sectionSeparator(context),
          const SizedBox(height: 22),
          // ── Auditoria ────────────────────────────────────────────────
          _EstateSectionHeader(
            eyebrow: 'HISTÓRICO',
            title: 'Auditoria do cadastro',
            subtitle: 'Datas de criação e última atualização.',
            tone: slate,
          ),
          const SizedBox(height: 10),
          _EstateInfoLine(
            tone: slate,
            icon: LucideIcons.calendarPlus,
            label: 'Criado em',
            value: d.createdAt == null
                ? '—'
                : DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                    .format(d.createdAt!.toLocal()),
          ),
          _rowDivider(context),
          _EstateInfoLine(
            tone: slate,
            icon: LucideIcons.history,
            label: 'Atualizado em',
            value: d.updatedAt == null
                ? '—'
                : DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                    .format(d.updatedAt!.toLocal()),
          ),
          if (_canEdit) ...[
            _rowDivider(context),
            _EstateNavigationLine(
              tone: _accent(context),
              icon: LucideIcons.pencil,
              title: 'Editar empreendimento',
              subtitle: 'Dados, material da equipe e galeria.',
              trailing: Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              onTap: _goToEdit,
            ),
          ],
        ],
      ),
    );
  }

  // ─── Masthead (eyebrow + headline + subtítulo) ───────────────────────────

  Widget _buildMasthead(BuildContext context, Development d) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final statusTone =
        d.isActive ? EstateTones.green(context) : EstateTones.amber(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'EMPREENDIMENTO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusTone.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                d.isActive ? 'ATIVO' : 'INATIVO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusTone,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            d.name.isEmpty ? 'Empreendimento' : d.name,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: ThemeHelpers.textColor(context),
              height: 1.05,
              fontSize: 27,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            [d.fullAddressLine, d.cityState]
                    .where((s) => s.trim().isNotEmpty)
                    .join(' · ')
                    .trim()
                    .isEmpty
                ? 'Endereço não informado.'
                : [d.fullAddressLine, d.cityState]
                    .where((s) => s.trim().isNotEmpty)
                    .join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Manchete (placa de imagem + meta pills + editar) ────────────────────

  Widget _buildManchete(BuildContext context, Development d) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final statusTone =
        d.isActive ? EstateTones.green(context) : EstateTones.amber(context);
    final photos = d.activeImages;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _imagePlate(context, d),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.cityState.trim().isEmpty
                          ? 'Cidade não informada'
                          : d.cityState,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.35,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(LucideIcons.mapPinned, size: 12, color: secondary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            d.zipCode.trim().isEmpty
                                ? 'CEP não informado'
                                : 'CEP ${d.zipCode.trim()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_canEdit) ...[
                const SizedBox(width: 8),
                _ghostIconButton(
                  context,
                  icon: LucideIcons.pencil,
                  tone: accent,
                  tooltip: 'Editar empreendimento',
                  onTap: _goToEdit,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              EstateMiniPill(
                label: d.isActive ? 'Ativo' : 'Inativo',
                icon: d.isActive
                    ? LucideIcons.circleCheckBig
                    : LucideIcons.circleOff,
                tone: statusTone,
              ),
              EstateMiniPill(
                label: '${photos.length} foto${photos.length == 1 ? '' : 's'}',
                icon: LucideIcons.images,
                tone: EstateTones.amber(context),
              ),
              if (d.hasMaterial)
                EstateMiniPill(
                  label: 'Material da equipe',
                  icon: LucideIcons.folderOpen,
                  tone: accent,
                ),
              if ((d.cnpj ?? '').trim().isNotEmpty)
                EstateMiniPill(
                  label: 'CNPJ',
                  icon: LucideIcons.landmark,
                  tone: _indigo(context),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imagePlate(BuildContext context, Development d) {
    final accent = _accent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = (d.mainImageUrl ?? '').trim().isNotEmpty;

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.28 : 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18.5),
        child: hasImage
            ? ShimmerImage(
                imageUrl: d.mainImageUrl!,
                width: 76,
                height: 76,
                fit: BoxFit.cover,
                errorWidget: _imageFallback(context),
              )
            : _imageFallback(context),
      ),
    );
  }

  Widget _imageFallback(BuildContext context) {
    final accent = _accent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.28 : 0.16),
            accent.withValues(alpha: isDark ? 0.10 : 0.05),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          LucideIcons.blocks,
          size: 28,
          color: accent.withValues(alpha: isDark ? 0.85 : 0.7),
        ),
      ),
    );
  }

  Widget _ghostIconButton(
    BuildContext context, {
    required IconData icon,
    required Color tone,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.withValues(alpha: 0.30)),
            ),
            child: Icon(icon, size: 16, color: tone),
          ),
        ),
      ),
    );
  }

  // ─── Quick KPI strip (3 colunas separadas por filete) ────────────────────

  Widget _buildQuickStrip(BuildContext context, Development d) {
    final accent = _accent(context);
    final amber = EstateTones.amber(context);
    final materialCount = d.playbookKit.links.length +
        d.playbookKit.files.length +
        (d.materialNotes.isNotEmpty ? 1 : 0);
    final since = d.createdAt == null
        ? '—'
        : DateFormat('yyyy', 'pt_BR').format(d.createdAt!.toLocal());

    final items = <({Color tone, String label, String value, String sub})>[
      (
        tone: amber,
        label: 'FOTOS',
        value: '${d.activeImages.length}',
        sub: 'galeria',
      ),
      (
        tone: accent,
        label: 'MATERIAL',
        value: d.hasMaterial ? '$materialCount' : '—',
        sub: d.hasMaterial
            ? 'ite${materialCount == 1 ? 'm' : 'ns'}'
            : 'pendente',
      ),
      (
        tone: _indigo(context),
        label: 'DESDE',
        value: since,
        sub: 'cadastro',
      ),
    ];

    final divColor = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final theme = Theme.of(context);

    Widget kpi(({Color tone, String label, String value, String sub}) it) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              it.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                fontSize: 9.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              it.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: it.tone,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              it.sub,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 2,
              width: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    it.tone.withValues(alpha: 0.8),
                    it.tone.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 1, height: 48, color: divColor),
            Expanded(child: kpi(items[i])),
          ],
        ],
      ),
    );
  }

  // ─── Material da equipe ──────────────────────────────────────────────────

  Widget _buildMaterialSection(BuildContext context, Development d) {
    final theme = Theme.of(context);
    final purple = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = theme.brightness == Brightness.dark;
    final notes = d.materialNotes;
    final links = d.playbookKit.links;
    final files = d.playbookKit.files;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EstateSectionHeader(
          eyebrow: 'VENDAS',
          title: 'Material da equipe',
          subtitle: 'Notas, links e arquivos que apoiam a equipe comercial.',
          tone: purple,
        ),
        const SizedBox(height: 14),
        if (!d.hasMaterial)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Nenhum material cadastrado ainda.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else ...[
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: purple.withValues(alpha: isDark ? 0.10 : 0.06),
                  border: Border.all(color: purple.withValues(alpha: 0.22)),
                ),
                child: Text(
                  notes,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.5,
                  ),
                ),
              ),
            ),
          if (links.isNotEmpty) ...[
            if (notes.isNotEmpty) const SizedBox(height: 6),
            for (var i = 0; i < links.length; i++) ...[
              if (i > 0) _rowDivider(context),
              _EstateNavigationLine(
                tone: purple,
                icon: LucideIcons.link,
                title: links[i].label.trim().isEmpty
                    ? links[i].url
                    : links[i].label.trim(),
                subtitle:
                    links[i].label.trim().isEmpty ? 'Link' : links[i].url,
                trailing: Icon(
                  LucideIcons.externalLink,
                  size: 16,
                  color: secondary,
                ),
                onTap: () => _openUrl(links[i].url),
              ),
            ],
          ],
          if (files.isNotEmpty) ...[
            if (links.isNotEmpty || notes.isNotEmpty) _rowDivider(context),
            for (var i = 0; i < files.length; i++) ...[
              if (i > 0) _rowDivider(context),
              _EstateNavigationLine(
                tone: EstateTones.blue(context),
                icon: LucideIcons.paperclip,
                title: files[i].originalName,
                subtitle: _fileSizeLabel(files[i].fileSize) ?? 'Arquivo',
                trailing: Icon(
                  LucideIcons.download,
                  size: 16,
                  color: secondary,
                ),
                onTap: () => _openUrl(files[i].fileUrl),
              ),
            ],
          ],
        ],
      ],
    );
  }

  static String? _fileSizeLabel(int bytes) {
    if (bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    final mb = bytes / (1024 * 1024);
    return '${NumberFormat('#,##0.0', 'pt_BR').format(mb)} MB';
  }

  // ─── Galeria ─────────────────────────────────────────────────────────────

  Widget _buildGallerySection(
    BuildContext context,
    Development d,
    Color amber,
  ) {
    final photos = d.activeImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EstateSectionHeader(
          eyebrow: 'IMAGENS',
          title: 'Galeria',
          subtitle: photos.isEmpty
              ? 'Nenhuma imagem cadastrada.'
              : '${photos.length} imagem${photos.length == 1 ? '' : 's'} ativa${photos.length == 1 ? '' : 's'} do cadastro.',
          tone: amber,
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: photos.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _openUrl(photos[i].fileUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ShimmerImage(
                    imageUrl: photos[i].fileUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Helpers de layout (gramática do Perfil) ─────────────────────────────

  Widget _rowDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
      ),
    );
  }

  Widget _sectionSeparator(BuildContext context) {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.3),
    );
  }

  // ─── Skeleton (fiel ao layout novo) ──────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Masthead
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonText(width: 190, height: 10, borderRadius: 4),
                SizedBox(height: 12),
                SkeletonText(width: 250, height: 26, borderRadius: 8),
                SizedBox(height: 10),
                SkeletonText(
                    width: double.infinity, height: 12, borderRadius: 5),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Manchete: placa de imagem + linhas + pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    SkeletonBox(width: 76, height: 76, borderRadius: 20),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(width: 140, height: 16, borderRadius: 6),
                          SizedBox(height: 8),
                          SkeletonText(width: 110, height: 11, borderRadius: 4),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    SkeletonBox(width: 38, height: 38, borderRadius: 12),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: const [
                    SkeletonBox(width: 64, height: 22, borderRadius: 999),
                    SizedBox(width: 6),
                    SkeletonBox(width: 72, height: 22, borderRadius: 999),
                    SizedBox(width: 6),
                    SkeletonBox(width: 110, height: 22, borderRadius: 999),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Quick strip 3 colunas
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 44, height: 9, borderRadius: 4),
                        SizedBox(height: 7),
                        SkeletonText(width: 48, height: 20, borderRadius: 6),
                        SizedBox(height: 6),
                        SkeletonText(width: 54, height: 9, borderRadius: 4),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          // Seções
          for (var s = 0; s < 3; s++) ...[
            Container(
              height: 1,
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.3),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonText(width: 110, height: 10, borderRadius: 4),
                  SizedBox(height: 10),
                  SkeletonText(width: 190, height: 20, borderRadius: 7),
                  SizedBox(height: 14),
                  SkeletonBox(
                      width: double.infinity, height: 56, borderRadius: 14),
                  SizedBox(height: 10),
                  SkeletonBox(
                      width: double.infinity, height: 56, borderRadius: 14),
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

// ─── Widgets da gramática de seções do Perfil ────────────────────────────────

/// Header editorial de seção — barra tonal 18×2 + eyebrow em caps + título
/// grande w900 + subtítulo (mesma régua do Perfil).
class _EstateSectionHeader extends StatelessWidget {
  const _EstateSectionHeader({
    required this.eyebrow,
    required this.title,
    required this.tone,
    this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 18,
                height: 2,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  eyebrow,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: ThemeHelpers.textColor(context),
              height: 1.05,
              fontSize: 22,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Linha de informação (read-only) — placa de ícone tom-on-tom + label
/// uppercase pequeno + valor selecionável (gramática do Perfil).
class _EstateInfoLine extends StatelessWidget {
  const _EstateInfoLine({
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
  });

  final Color tone;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _EstateTonePlate(tone: tone, icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    fontSize: 14,
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

/// Linha de navegação — tap abre outra tela/link (gramática do Perfil).
class _EstateNavigationLine extends StatelessWidget {
  const _EstateNavigationLine({
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.10),
        highlightColor: tone.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _EstateTonePlate(tone: tone, icon: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Placa de ícone tom-on-tom — mantém a identidade da seção.
class _EstateTonePlate extends StatelessWidget {
  const _EstateTonePlate({required this.tone, required this.icon});

  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            tone.withValues(alpha: 0.22),
            tone.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: tone.withValues(alpha: 0.42)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: tone, size: 19),
    );
  }
}
