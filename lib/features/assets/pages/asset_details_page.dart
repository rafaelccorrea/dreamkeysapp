import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../documents/widgets/entity_selector.dart';
import '../models/asset_models.dart';
import '../services/asset_service.dart';
import '../widgets/asset_card.dart';
import '../widgets/user_picker_sheet.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Detalhe do patrimônio — hero com valor e status, ações no próprio item
/// (editar / transferir / dar baixa, gated por permissão), especificações
/// flush e linha do tempo de movimentações.
class AssetDetailsPage extends StatefulWidget {
  final String assetId;

  const AssetDetailsPage({super.key, required this.assetId});

  @override
  State<AssetDetailsPage> createState() => _AssetDetailsPageState();
}

class _AssetDetailsPageState extends State<AssetDetailsPage> {
  Asset? _asset;
  List<AssetMovement> _movements = const [];
  bool _loading = true;
  bool _movementsLoading = true;
  String? _error;
  int _errorStatus = 0;

  bool get _canUpdate =>
      ModuleAccessService.instance.hasPermission('asset:update');
  bool get _canTransfer =>
      ModuleAccessService.instance.hasPermission('asset:transfer');
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission('asset:delete');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await AssetService.instance.getById(widget.assetId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _asset = res.data!;
        _error = null;
        _errorStatus = 0;
      } else {
        _error = res.message ?? 'Erro ao carregar patrimônio';
        _errorStatus = res.statusCode;
      }
    });
    _loadMovements();
  }

  Future<void> _loadMovements() async {
    setState(() => _movementsLoading = true);
    final res = await AssetService.instance.getMovements(widget.assetId);
    if (!mounted) return;
    setState(() {
      _movementsLoading = false;
      if (res.success && res.data != null) {
        _movements = res.data!;
      }
    });
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.of(context)
        .pushNamed('/assets/${widget.assetId}/edit');
    if (changed == true) _load(silent: true);
  }

  Future<void> _confirmDelete() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dar baixa no item'),
        content: Text(
          'Tem certeza que deseja dar baixa em '
          '"${_asset?.name ?? 'este item'}"? O item sai do acervo ativo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dar baixa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await AssetService.instance.delete(widget.assetId);
    if (!mounted) return;
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao dar baixa no patrimônio'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  Future<void> _openTransfer() async {
    final transferred = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _TransferSheet(assetId: widget.assetId),
    );
    if (transferred == true && mounted) _load(silent: true);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Patrimônio',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: () => _load(silent: true),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _asset == null) return _buildSkeleton(context);
    if (_error != null && _asset == null) return _buildError(context);
    final a = _asset!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Cor de cada capítulo vive só no glifo da plaqueta (a casa não pinta
    // área): especificações em azul (dado), histórico em violeta (tempo).
    final cSpecs =
        isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final cHistory =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

    final movimentacoesResumo = _movementsLoading
        ? 'carregando'
        : _movements.isEmpty
            ? 'sem registros'
            : _movements.length == 1
                ? '1 registro'
                : '${_movements.length} registros';

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Soma a barra de navegação do Android (gestos/3 botões), senão ela
      // engole o fim da linha do tempo.
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(context, a),
          const SizedBox(height: 16),
          _buildLeitura(context, a),
          const SizedBox(height: 14),
          _buildActions(context),
          const SizedBox(height: 26),
          _sectionHeader(
            context,
            icon: LucideIcons.scanBarcode,
            numero: '01',
            eyebrow: 'ESPECIFICAÇÕES',
            title: 'Ficha do item',
            aside: a.category.label,
            tone: cSpecs,
          ),
          const SizedBox(height: 4),
          _buildFicha(context, a),
          if ((a.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _labelText(context, 'DESCRIÇÃO'),
            const SizedBox(height: 6),
            Text(
              a.description!.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.45,
                  ),
            ),
          ],
          if ((a.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _labelText(context, 'OBSERVAÇÕES'),
            const SizedBox(height: 6),
            Text(
              a.notes!.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.45,
                  ),
            ),
          ],
          const SizedBox(height: 26),
          _sectionHeader(
            context,
            icon: LucideIcons.history,
            numero: '02',
            eyebrow: 'HISTÓRICO',
            title: 'Movimentações',
            aside: movimentacoesResumo,
            tone: cHistory,
          ),
          const SizedBox(height: 14),
          _buildMovements(context, cHistory),
        ],
      ).animate().fadeIn(duration: 240.ms),
    );
  }

  /// Iniciais de um nome ("Edson Silva" → "ES") para os avatares da página.
  static String _iniciais(String nome) {
    final partes =
        nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '';
    final a = partes.first[0];
    final b = partes.length > 1 ? partes.last[0] : '';
    return (a + b).toUpperCase();
  }

  /// "há 2 a 3 m" / "há 8 m" / "este mês" — idade desde uma data.
  static String _idade(DateTime desde) {
    final agora = DateTime.now();
    var meses =
        (agora.year - desde.year) * 12 + (agora.month - desde.month);
    if (agora.day < desde.day) meses -= 1;
    if (meses <= 0) {
      final dias = agora.difference(desde).inDays;
      if (dias <= 0) return 'hoje';
      if (dias == 1) return 'há 1 dia';
      return 'há $dias dias';
    }
    final anos = meses ~/ 12;
    final resto = meses % 12;
    if (anos == 0) return 'há $meses m';
    if (resto == 0) return 'há $anos a';
    return 'há $anos a $resto m';
  }

  /// Plaqueta sólida: gradiente da cor de significado com glifo branco — a
  /// mesma da lista e dos painéis do sino. É onde a cor mora nesta página.
  Widget _plaqueta(Color tone, IconData icon,
      {double size = 46, double radius = 14, double iconSize = 22}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(tone, Colors.white, 0.12)!,
            Color.lerp(tone, Colors.black, 0.18)!,
          ],
        ),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }

  /// Carimbo de situação: ponto + palavra em caixa alta na cor do significado
  /// (sem pílula — a cor fica na tinta, não na área).
  Widget _carimbo(String label, Color color, {double size = 10}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: size,
              letterSpacing: 0.9,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  /// Avatar da pessoa: a FOTO quando existe; senão (ou se a imagem falhar),
  /// iniciais na cor de significado (tinta cheia, letra branca).
  Widget _avatar(String nome, Color tone, {double size = 26, String? foto}) {
    final iniciais = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
      child: Text(
        _iniciais(nome),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.38,
          letterSpacing: 0.3,
          height: 1.0,
        ),
      ),
    );
    if ((foto ?? '').trim().isEmpty) return iniciais;
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.network(
          foto!.trim(),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Enquanto carrega e se falhar, as iniciais seguram o lugar.
          frameBuilder: (context, child, frame, wasSync) =>
              frame == null && !wasSync ? iniciais : child,
          errorBuilder: (_, _, _) => iniciais,
        ),
      ),
    );
  }

  Widget _labelText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 10,
          ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, Asset a) {
    final theme = Theme.of(context);
    // Situação real (com alguém = em uso), não o status cru do banco.
    final tone = assetStatusColor(context, a.situacao);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);

    final subBits = <Widget>[
      _carimbo(a.situacao.label, tone),
      if (a.brandModelLabel != null)
        Text(
          a.brandModelLabel!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      if ((a.serialNumber ?? '').trim().isNotEmpty)
        Text(
          'Nº ${a.serialNumber!.trim()}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow neutro: a cor desta página é do significado (situação),
        // não da marca — a marca fica só no botão primário.
        Text(
          'PATRIMÔNIO · ${a.category.label.toUpperCase()}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _plaqueta(tone, assetCategoryIcon(a.category)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.4,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: subBits,
                  ),
                  if ((a.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      a.description!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Faixa de leitura, flush entre dois fios: o que a pessoa quer saber de
  /// bate-pronto — valor, situação, com quem está e desde quando no acervo.
  Widget _buildLeitura(BuildContext context, Asset a) {
    final theme = Theme.of(context);
    final tone = assetStatusColor(context, a.situacao);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final fio = ThemeHelpers.borderColor(context).withValues(alpha: 0.6);

    Widget rotulo(String t) => Text(
          t,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: secondary,
          ),
        );

    final holder = (a.assignedToUserName ?? '').trim();
    final imovel = (a.propertyTitle ?? '').trim();
    final criado = a.createdAt?.toLocal();
    final por = (a.createdByName ?? '').trim();

    Widget responsavel;
    if (holder.isNotEmpty) {
      responsavel = Row(
        children: [
          _avatar(holder, tone, foto: a.assignedToUserAvatar),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'responsável atual',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontSize: 10.5,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else if (imovel.isNotEmpty) {
      responsavel = Row(
        children: [
          _plaqueta(tone, LucideIcons.building2,
              size: 26, radius: 8, iconSize: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  imovel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (a.propertyCode ?? '').trim().isNotEmpty
                      ? 'no imóvel · cód ${a.propertyCode!.trim()}'
                      : 'no imóvel',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontSize: 10.5,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      responsavel = Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: secondary.withValues(alpha: 0.6)),
            ),
            child: Icon(LucideIcons.userX, size: 13, color: secondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sem responsável',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'livre para atribuição',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontSize: 10.5,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: fio),
          bottom: BorderSide(color: fio),
        ),
      ),
      child: Column(
        children: [
          // Linha 1: valor grande à esquerda, situação carimbada à direita.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      rotulo('VALOR DO BEM'),
                      const SizedBox(height: 4),
                      Text(
                        _money.format(a.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: textColor,
                          letterSpacing: -0.7,
                          height: 1.05,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (a.acquisitionDate != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'adquirido ${_idade(a.acquisitionDate!.toLocal())} · '
                          '${DateFormat('dd/MM/yy', 'pt_BR').format(a.acquisitionDate!.toLocal())}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    rotulo('SITUAÇÃO'),
                    const SizedBox(height: 7),
                    _carimbo(a.situacao.label, tone, size: 11),
                    if (a.situacao != a.status) ...[
                      const SizedBox(height: 4),
                      Text(
                        'vinculado a alguém',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: fio),
          // Linha 2: com quem está | no acervo desde quando (e por quem).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 11, 10, 11),
                    child: responsavel,
                  ),
                ),
                Container(width: 1, color: fio),
                Expanded(
                  flex: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 0, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        rotulo('NO ACERVO'),
                        const SizedBox(height: 4),
                        Text(
                          criado != null ? _idade(criado) : '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (criado != null)
                              'desde ${DateFormat('dd/MM/yy', 'pt_BR').format(criado)}',
                            if (por.isNotEmpty) 'por $por',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontSize: 10.5,
                            height: 1.1,
                          ),
                        ),
                      ],
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

  // ─── Ações no próprio item ───────────────────────────────────────────────

  Widget _buildActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent(context);
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    // Controle tem corpo: Editar sólido na marca (o primário da página);
    // Transferir e Dar baixa com corpo neutro e SELO sólido na cor do
    // significado (azul = movimento, vermelho = saída). Sem contorno-só,
    // sem sombra.
    // Hierarquia, não fileira: Editar é a ação da tela (sólido, largura
    // cheia); Transferir e Dar baixa são ferramentas menores logo abaixo.
    final primario = _canUpdate
        ? _actionButton(context, LucideIcons.pencil, 'Editar', accent, _openEdit,
            primary: true)
        : null;
    final ferramentas = <Widget>[
      if (_canTransfer)
        _actionButton(context, LucideIcons.arrowLeftRight, 'Transferir', blue,
            _openTransfer),
      if (_canDelete)
        _actionButton(
            context, LucideIcons.archive, 'Dar baixa', danger, _confirmDelete),
    ];
    if (primario == null && ferramentas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?primario,
        if (primario != null && ferramentas.isNotEmpty)
          const SizedBox(height: 8),
        if (ferramentas.isNotEmpty)
          Row(
            children: [
              for (var i = 0; i < ferramentas.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: ferramentas[i]),
              ],
            ],
          ),
      ],
    );
  }

  Widget _actionButton(BuildContext context, IconData icon, String label,
      Color tone, VoidCallback onTap,
      {bool primary = false}) {
    final fio = ThemeHelpers.borderColor(context).withValues(alpha: 0.8);
    final fg = primary ? Colors.white : ThemeHelpers.textColor(context);

    // Primário: bloco sólido de 46px na cor da marca, glifo branco.
    // Ferramenta: 38px, só contorno, selo pequeno na cor do significado —
    // visivelmente uma ordem abaixo do primário.
    return Material(
      color: primary ? tone : Colors.transparent,
      borderRadius: BorderRadius.circular(primary ? 12 : 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(primary ? 12 : 10),
        child: Container(
          height: primary ? 46 : 38,
          padding: EdgeInsets.symmetric(horizontal: primary ? 14 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(primary ? 12 : 10),
            border: primary ? null : Border.all(color: fio),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (primary)
                Icon(icon, size: 17, color: Colors.white)
              else
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(icon, size: 12, color: Colors.white),
                ),
              SizedBox(width: primary ? 8 : 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: fg,
                      fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
                      fontSize: primary ? 13.5 : 12,
                      letterSpacing: primary ? 0.1 : -0.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Ficha em grade ──────────────────────────────────────────────────────

  /// Ficha do item em duas colunas separadas por fio (valor forte, rótulo
  /// miúdo) — o que era uma lista de "ícone · rótulo · valor à direita".
  Widget _buildFicha(BuildContext context, Asset a) {
    final fmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final celulas = <_Celula>[
      _Celula('CATEGORIA', a.category.label),
      if (a.brandModelLabel != null) _Celula('MARCA / MODELO', a.brandModelLabel!),
      if ((a.serialNumber ?? '').trim().isNotEmpty)
        _Celula('Nº DE SÉRIE', a.serialNumber!.trim(), mono: true),
      if (a.acquisitionDate != null)
        _Celula(
          'AQUISIÇÃO',
          fmt.format(a.acquisitionDate!.toLocal()),
          sub: _idade(a.acquisitionDate!.toLocal()),
        ),
      if ((a.location ?? '').trim().isNotEmpty)
        _Celula('LOCALIZAÇÃO', a.location!.trim()),
      if ((a.assignedToUserName ?? '').trim().isNotEmpty)
        _Celula('RESPONSÁVEL', a.assignedToUserName!.trim()),
      if ((a.propertyTitle ?? '').trim().isNotEmpty)
        _Celula(
          'IMÓVEL',
          a.propertyTitle!.trim(),
          sub: (a.propertyCode ?? '').trim().isNotEmpty
              ? 'cód ${a.propertyCode!.trim()}'
              : null,
          larga: true,
        ),
      if ((a.createdByName ?? '').trim().isNotEmpty)
        _Celula('CADASTRADO POR', a.createdByName!.trim()),
      if (a.createdAt != null)
        _Celula('CADASTRADO EM', fmt.format(a.createdAt!.toLocal())),
    ];

    // Empacota: célula larga ocupa a linha; as outras vão de duas em duas.
    final linhas = <List<_Celula>>[];
    var i = 0;
    while (i < celulas.length) {
      final c = celulas[i];
      if (c.larga) {
        linhas.add([c]);
        i += 1;
        continue;
      }
      final prox = i + 1 < celulas.length ? celulas[i + 1] : null;
      if (prox != null && !prox.larga) {
        linhas.add([c, prox]);
        i += 2;
      } else {
        linhas.add([c]);
        i += 1;
      }
    }

    final fio = ThemeHelpers.borderColor(context).withValues(alpha: 0.5);
    return Column(
      children: [
        for (var l = 0; l < linhas.length; l++)
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: l == linhas.length - 1 ? Colors.transparent : fio,
                ),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var k = 0; k < linhas[l].length; k++) ...[
                    if (k > 0) Container(width: 1, color: fio),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                            k == 0 ? 0 : 12, 10, k == 0 && linhas[l].length > 1 ? 12 : 0, 10),
                        child: _celula(context, linhas[l][k]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _celula(BuildContext context, _Celula c) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          c.rotulo,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            color: secondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          c.valor,
          maxLines: c.larga ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w800,
            height: 1.2,
            fontFeatures: c.mono ? const [FontFeature.tabularFigures()] : null,
          ),
        ),
        if (c.sub != null) ...[
          const SizedBox(height: 2),
          Text(
            c.sub!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontSize: 10.5,
              height: 1.1,
            ),
          ),
        ],
      ],
    );
  }

  // ─── Movimentações ───────────────────────────────────────────────────────

  Widget _buildMovements(BuildContext context, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    if (_movementsLoading) {
      return Column(
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 32, height: 32, borderRadius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: 140, height: 14),
                      SizedBox(height: 6),
                      SkeletonText(width: double.infinity, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_movements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(LucideIcons.history, size: 15, color: secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nenhuma movimentação registrada para este item.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fmt = DateFormat('dd/MM/yy', 'pt_BR');
    return Column(
      children: [
        for (var i = 0; i < _movements.length; i++)
          _movementRow(context, _movements[i], tone, fmt,
              isLast: i == _movements.length - 1),
      ],
    );
  }

  /// Cor de cada tipo de movimentação — por significado: entrada verde,
  /// saída vermelha, transferência azul, status/manutenção âmbar.
  Color _movementTone(BuildContext context, AssetMovementType type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (type) {
      case AssetMovementType.entry:
        return isDark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case AssetMovementType.exit:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case AssetMovementType.transfer:
        return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case AssetMovementType.statusChange:
      case AssetMovementType.maintenance:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case AssetMovementType.unknown:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  /// "de X para Y" com o destino forte — a rota da movimentação.
  Widget _rota(BuildContext context, IconData icon, String? de, String? para) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final fraco = theme.textTheme.labelSmall?.copyWith(
      color: secondary,
      fontWeight: FontWeight.w600,
      fontSize: 11.5,
      height: 1.2,
    );
    final forte = theme.textTheme.labelSmall?.copyWith(
      color: textColor,
      fontWeight: FontWeight.w800,
      fontSize: 11.5,
      height: 1.2,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 12, color: secondary),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if ((de ?? '').trim().isNotEmpty) ...[
                  TextSpan(text: 'de ', style: fraco),
                  TextSpan(text: de!.trim(), style: forte),
                  TextSpan(text: '  ', style: fraco),
                ],
                TextSpan(text: 'para ', style: fraco),
                TextSpan(
                  text: (para ?? '').trim().isNotEmpty ? para!.trim() : '—',
                  style: forte,
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _movementRow(BuildContext context, AssetMovement m, Color tone,
      DateFormat fmt,
      {required bool isLast}) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final date = m.movementDate ?? m.createdAt;
    // A cor da linha vem do TIPO de movimentação (verde entrou, vermelho
    // saiu, azul mudou de mão, âmbar mudou de estado); o violeta do capítulo
    // fica no trilho, discreto.
    final tipoTone = _movementTone(context, m.type);
    final trilho = ThemeHelpers.borderColor(context).withValues(alpha: 0.8);
    final registrou = (m.recordedByName ?? '').trim();

    final temPessoas = (m.fromUserName ?? '').trim().isNotEmpty ||
        (m.toUserName ?? '').trim().isNotEmpty;
    final temImoveis = (m.fromPropertyTitle ?? '').trim().isNotEmpty ||
        (m.toPropertyTitle ?? '').trim().isNotEmpty;
    final temStatus = m.previousStatus != null || m.newStatus != null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trilho: plaqueta sólida do tipo + fio neutro descendo.
          Column(
            children: [
              _plaqueta(tipoTone, assetMovementIcon(m.type),
                  size: 32, radius: 10, iconSize: 15),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: trilho,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          m.type.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (date != null) ...[
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              fmt.format(date.toLocal()),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                height: 1.2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            Text(
                              DateFormat('HH:mm', 'pt_BR')
                                  .format(date.toLocal()),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                                height: 1.2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  // O motivo é o conteúdo da linha: cor de texto, não cinza.
                  if (m.reason.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      m.reason.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (temPessoas) ...[
                    const SizedBox(height: 6),
                    _rota(context, LucideIcons.userRound, m.fromUserName,
                        m.toUserName),
                  ],
                  if (temImoveis) ...[
                    const SizedBox(height: 5),
                    _rota(context, LucideIcons.building2, m.fromPropertyTitle,
                        m.toPropertyTitle),
                  ],
                  if (temStatus) ...[
                    const SizedBox(height: 6),
                    // Estado antes → depois, cada um no seu carimbo.
                    Row(
                      children: [
                        if (m.previousStatus != null) ...[
                          _carimbo(
                            m.previousStatus!.label,
                            assetStatusColor(context, m.previousStatus!),
                            size: 9.5,
                          ),
                          const SizedBox(width: 6),
                          Icon(LucideIcons.arrowRight, size: 11,
                              color: secondary),
                          const SizedBox(width: 6),
                        ],
                        if (m.newStatus != null)
                          Flexible(
                            child: _carimbo(
                              m.newStatus!.label,
                              assetStatusColor(context, m.newStatus!),
                              size: 9.5,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if ((m.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      m.notes!.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (registrou.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _avatar(registrou, secondary,
                            size: 18, foto: m.recordedByAvatar),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'registrado por $registrou',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers visuais ─────────────────────────────────────────────────────

  /// Cabeçalho de capítulo: plaqueta sólida, "01 · EYEBROW" neutro, título e
  /// um dado útil à direita (categoria, contagem) no lugar do texto
  /// explicativo. Fio abaixo fecha o cabeçalho.
  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String numero,
    required String eyebrow,
    required String title,
    required Color tone,
    String? aside,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        children: [
          _plaqueta(tone, icon, size: 36, radius: 11, iconSize: 18),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$numero · $eyebrow',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          if ((aside ?? '').isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              aside!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Soma a barra de navegação do Android (gestos/3 botões), senão ela
      // engole o fim da linha do tempo.
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 40 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Row(
          children: [
            SkeletonBox(width: 46, height: 46, borderRadius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonText(width: double.infinity, height: 20),
                  SizedBox(height: 8),
                  SkeletonText(width: 140, height: 14, borderRadius: 999),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // Faixa de leitura: duas linhas entre fios.
        Row(
          children: const [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 80, height: 9),
                  SizedBox(height: 8),
                  SkeletonText(width: 150, height: 24),
                ],
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SkeletonText(width: 56, height: 9),
                SizedBox(height: 10),
                SkeletonText(width: 64, height: 11),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: const [
            SkeletonBox(width: 26, height: 26, borderRadius: 999),
            SizedBox(width: 8),
            Expanded(child: SkeletonText(width: double.infinity, height: 13)),
            SizedBox(width: 24),
            Expanded(child: SkeletonText(width: double.infinity, height: 13)),
          ],
        ),
        const SizedBox(height: 16),
        SkeletonBox(width: double.infinity, height: 46, borderRadius: 12),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: SkeletonBox(
                    width: double.infinity, height: 38, borderRadius: 10)),
            const SizedBox(width: 8),
            Expanded(
                child: SkeletonBox(
                    width: double.infinity, height: 38, borderRadius: 10)),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: const [
            SkeletonBox(width: 36, height: 36, borderRadius: 11),
            SizedBox(width: 11),
            Expanded(child: SkeletonText(width: 140, height: 14)),
          ],
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: const [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 70, height: 9),
                      SizedBox(height: 6),
                      SkeletonText(width: 120, height: 13),
                    ],
                  ),
                ),
                SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 70, height: 9),
                      SizedBox(height: 6),
                      SkeletonText(width: 100, height: 13),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return AppErrorState.fromApi(
      message: _error,
      statusCode: _errorStatus,
      onRetry: _load,
    );
  }
}

// ─── Sheet de transferência ──────────────────────────────────────────────────

enum _TransferTarget { user, property }

class _TransferSheet extends StatefulWidget {
  final String assetId;

  const _TransferSheet({required this.assetId});

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();

  _TransferTarget _target = _TransferTarget.user;
  String? _toUserId;
  String? _toUserName;
  String? _toPropertyId;
  String? _toPropertyName;

  bool _saving = false;
  bool _triedSubmit = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_reasonController.text.trim().isEmpty) return false;
    if (_target == _TransferTarget.user) return (_toUserId ?? '').isNotEmpty;
    return (_toPropertyId ?? '').isNotEmpty;
  }

  Future<void> _pickUser() async {
    final picked = await showUserPickerSheet(context, selectedId: _toUserId);
    if (picked == null || picked.id.isEmpty || !mounted) return;
    setState(() {
      _toUserId = picked.id;
      _toUserName = picked.name;
    });
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    if (!_valid) return;
    setState(() => _saving = true);
    final res = await AssetService.instance.transfer(
      widget.assetId,
      toUserId: _target == _TransferTarget.user ? _toUserId : null,
      toPropertyId:
          _target == _TransferTarget.property ? _toPropertyId : null,
      reason: _reasonController.text,
      notes: _notesController.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      Navigator.of(context).pop(true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message ?? 'Erro ao transferir patrimônio'),
        backgroundColor: AppColors.status.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(blue, Colors.white, 0.12)!,
                            Color.lerp(blue, Colors.black, 0.18)!,
                          ],
                        ),
                      ),
                      child: const Icon(LucideIcons.arrowLeftRight,
                          color: Colors.white, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transferir patrimônio',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mova o item para um colaborador ou imóvel.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _targetChip(context, _TransferTarget.user, 'Colaborador',
                        LucideIcons.userRound, blue),
                    const SizedBox(width: 10),
                    _targetChip(context, _TransferTarget.property, 'Imóvel',
                        LucideIcons.building2, blue),
                  ],
                ),
                const SizedBox(height: 14),
                if (_target == _TransferTarget.user) ...[
                  InkWell(
                    onTap: _pickUser,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Destinatário *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.person_outline),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        (_toUserName ?? '').isNotEmpty
                            ? _toUserName!
                            : 'Selecionar colaborador',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: (_toUserName ?? '').isNotEmpty
                              ? ThemeHelpers.textColor(context)
                              : secondary,
                        ),
                      ),
                    ),
                  ),
                  if (_triedSubmit && (_toUserId ?? '').isEmpty)
                    _errorHint(context, 'Selecione o colaborador de destino'),
                ] else ...[
                  EntitySelector(
                    type: 'property',
                    selectedId: _toPropertyId,
                    selectedName: _toPropertyName,
                    onSelected: (id, name) => setState(() {
                      _toPropertyId = id;
                      _toPropertyName = name;
                    }),
                  ),
                  if (_triedSubmit && (_toPropertyId ?? '').isEmpty)
                    _errorHint(context, 'Selecione o imóvel de destino'),
                ],
                const SizedBox(height: 14),
                CustomTextField(
                  controller: _reasonController,
                  label: 'Motivo *',
                  hint: 'Ex: Mudança de setor',
                  errorText:
                      _triedSubmit && _reasonController.text.trim().isEmpty
                          ? 'Motivo é obrigatório'
                          : null,
                  onChanged: (_) {
                    if (_triedSubmit) setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _notesController,
                  label: 'Observações',
                  hint: 'Opcional',
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
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
                      : const Icon(LucideIcons.arrowLeftRight, size: 16),
                  label: Text(
                    _saving ? 'Transferindo…' : 'Confirmar transferência',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorHint(BuildContext context, String message) {
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

  Widget _targetChip(BuildContext context, _TransferTarget target,
      String label, IconData icon, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selected = _target == target;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _target = target),
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
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 7),
              Text(
                label,
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
}

/// Célula da ficha em grade: rótulo miúdo + valor forte (+ subtexto).
/// larga = ocupa a linha inteira; mono = alinha dígitos (nº de série).
class _Celula {
  final String rotulo;
  final String valor;
  final String? sub;
  final bool larga;
  final bool mono;

  const _Celula(
    this.rotulo,
    this.valor, {
    this.sub,
    this.larga = false,
    this.mono = false,
  });
}
