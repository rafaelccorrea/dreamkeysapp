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

/// Detalhe do **empreendimento** — porta a `EmpreendimentoDetalhePage` do
/// web: hero editorial (nome + status + meta de contato), Sobre, localização
/// detalhada, material da equipe (notas/links/arquivos), galeria e auditoria.
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
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(context, d),
          const SizedBox(height: 22),
          if ((d.description ?? '').trim().isNotEmpty) ...[
            _panel(
              context,
              tone: _accent(context),
              icon: LucideIcons.blocks,
              label: 'Sobre o empreendimento',
              child: Text(
                d.description!.trim(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      height: 1.5,
                    ),
              ),
            ),
            const SizedBox(height: 22),
          ],
          _panel(
            context,
            tone: EstateTones.blue(context),
            icon: LucideIcons.mapPin,
            label: 'Localização detalhada',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.fullAddressLine,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    d.cityState,
                    if (d.zipCode.trim().isNotEmpty) 'CEP ${d.zipCode.trim()}',
                  ].where((s) => s.trim().isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _buildMaterialPanel(context, d),
          const SizedBox(height: 22),
          _buildGalleryPanel(context, d),
          const SizedBox(height: 22),
          _panel(
            context,
            tone: ThemeHelpers.textSecondaryColor(context),
            icon: LucideIcons.calendarClock,
            label: 'Auditoria do cadastro',
            child: Column(
              children: [
                if (d.createdAt != null)
                  EstateInfoRow(
                    label: 'Criado em',
                    value: DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                        .format(d.createdAt!.toLocal()),
                    icon: LucideIcons.calendarPlus,
                  ),
                if (d.updatedAt != null)
                  EstateInfoRow(
                    label: 'Atualizado em',
                    value: DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                        .format(d.updatedAt!.toLocal()),
                    icon: LucideIcons.history,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, Development d) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final statusTone =
        d.isActive ? EstateTones.green(context) : EstateTones.amber(context);

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
                color: statusTone,
                boxShadow: [
                  BoxShadow(
                    color: statusTone.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'DETALHES DO EMPREENDIMENTO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  fontSize: 11,
                ),
              ),
            ),
            EstateMiniPill(
              label: d.isActive ? 'Ativo' : 'Inativo',
              icon: d.isActive
                  ? LucideIcons.circleCheckBig
                  : LucideIcons.circleOff,
              tone: statusTone,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          d.name,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [d.address, d.cityState]
              .where((s) => s.trim().isNotEmpty)
              .join(' · '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _buildMetaGrid(context, d),
        if (_canEdit) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _goToEdit,
              icon: const Icon(LucideIcons.pencil, size: 15),
              label: const Text('Editar empreendimento'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetaGrid(BuildContext context, Development d) {
    final cells = <({IconData icon, String label, String value})>[
      (
        icon: LucideIcons.landmark,
        label: 'CNPJ',
        value: formatCnpjPretty(d.cnpj).isEmpty
            ? 'Não informado'
            : formatCnpjPretty(d.cnpj),
      ),
      (
        icon: LucideIcons.phone,
        label: 'TELEFONE',
        value: (d.phone ?? '').trim().isEmpty ? 'Não informado' : d.phone!.trim(),
      ),
      (
        icon: LucideIcons.mail,
        label: 'E-MAIL',
        value: (d.email ?? '').trim().isEmpty ? 'Não informado' : d.email!.trim(),
      ),
      (
        icon: LucideIcons.globe,
        label: 'SITE',
        value: websiteHost(d.website).isEmpty
            ? 'Não informado'
            : websiteHost(d.website),
      ),
    ];
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final divider = ThemeHelpers.borderLightColor(context);

    Widget cell(({IconData icon, String label, String value}) c) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: secondary,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(c.icon, size: 13, color: secondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  c.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cell(cells[0])),
            const SizedBox(width: 14),
            Expanded(child: cell(cells[1])),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Container(height: 1, color: divider),
        ),
        Row(
          children: [
            Expanded(child: cell(cells[2])),
            const SizedBox(width: 14),
            Expanded(child: cell(cells[3])),
          ],
        ),
      ],
    );
  }

  // ─── Material da equipe ──────────────────────────────────────────────────

  Widget _buildMaterialPanel(BuildContext context, Development d) {
    final theme = Theme.of(context);
    final purple = EstateTones.purple(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final notes = d.materialNotes;
    final links = d.playbookKit.links;
    final files = d.playbookKit.files;

    return _panel(
      context,
      tone: purple,
      icon: LucideIcons.folderOpen,
      label: 'Material da equipe',
      child: !d.hasMaterial
          ? Text(
              'Nenhum material cadastrado ainda.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontStyle: FontStyle.italic,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notes.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: purple.withValues(
                          alpha: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? 0.10
                              : 0.06),
                      border: Border.all(
                        color: purple.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      notes,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        height: 1.5,
                      ),
                    ),
                  ),
                if (links.isNotEmpty) ...[
                  if (notes.isNotEmpty) const SizedBox(height: 12),
                  for (final link in links)
                    _materialTile(
                      context,
                      icon: LucideIcons.link,
                      title: link.label.trim().isEmpty
                          ? link.url
                          : link.label.trim(),
                      subtitle: link.label.trim().isEmpty ? null : link.url,
                      tone: purple,
                      onTap: () => _openUrl(link.url),
                    ),
                ],
                if (files.isNotEmpty) ...[
                  if (notes.isNotEmpty || links.isNotEmpty)
                    const SizedBox(height: 4),
                  for (final f in files)
                    _materialTile(
                      context,
                      icon: LucideIcons.paperclip,
                      title: f.originalName,
                      subtitle: _fileSizeLabel(f.fileSize),
                      tone: EstateTones.blue(context),
                      onTap: () => _openUrl(f.fileUrl),
                    ),
                ],
              ],
            ),
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

  Widget _materialTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required Color tone,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: ThemeHelpers.borderLightColor(context),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 15, color: tone),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ((subtitle ?? '').trim().isNotEmpty)
                        Text(
                          subtitle!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontSize: 10.5,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.externalLink,
                  size: 14,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Galeria ─────────────────────────────────────────────────────────────

  Widget _buildGalleryPanel(BuildContext context, Development d) {
    final photos = d.activeImages;
    return _panel(
      context,
      tone: EstateTones.amber(context),
      icon: LucideIcons.images,
      label: 'Galeria',
      trailing: photos.isEmpty ? null : '${photos.length}',
      child: photos.isEmpty
          ? Text(
              'Nenhuma imagem cadastrada.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontStyle: FontStyle.italic,
                  ),
            )
          : GridView.builder(
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
    );
  }

  // ─── Painel flush ────────────────────────────────────────────────────────

  Widget _panel(
    BuildContext context, {
    required Color tone,
    required IconData icon,
    required String label,
    String? trailing,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: tone,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: tone.withValues(alpha: 0.45), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Icon(icon, size: 14, color: tone),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
            if (trailing != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  trailing,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 190, height: 11, borderRadius: 5),
          const SizedBox(height: 12),
          const SkeletonText(width: 230, height: 24, borderRadius: 8),
          const SizedBox(height: 10),
          const SkeletonText(width: double.infinity, height: 13, borderRadius: 5),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 44, borderRadius: 12)),
              SizedBox(width: 14),
              Expanded(child: SkeletonBox(height: 44, borderRadius: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 44, borderRadius: 12)),
              SizedBox(width: 14),
              Expanded(child: SkeletonBox(height: 44, borderRadius: 12)),
            ],
          ),
          const SizedBox(height: 26),
          const SkeletonText(width: 150, height: 11, borderRadius: 5),
          const SizedBox(height: 12),
          const SkeletonBox(
              width: double.infinity, height: 110, borderRadius: 16),
          const SizedBox(height: 26),
          const SkeletonText(width: 120, height: 11, borderRadius: 5),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 96, borderRadius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 96, borderRadius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 96, borderRadius: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
