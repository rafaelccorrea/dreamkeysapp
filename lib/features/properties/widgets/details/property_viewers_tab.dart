import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../services/property_detail_extras_service.dart';
import 'property_details_kit.dart';

/// Motivo do cadeado da aba — a frase do back (`GET /properties/:id/views`).
const String kPropertyViewersLockedReason =
    'Apenas gestores e administradores podem visualizar este histórico. Para '
    'liberar o acesso, fale com o seu gestor ou com o suporte.';

/// Corpo da aba "Visualizações" da ficha — paridade com o
/// `PropertyDetailsViewersSection` do web (276-397): quem da equipe abriu a
/// ficha, quantas visitas, o total de aberturas e, por pessoa, papel, última
/// vez e contagem.
///
/// A aba só existe para gestão (master/admin/gestor — [canViewFor], a regra
/// do web `restrictedToManagers`); se chegar aqui sem [canView], mostra o
/// cadeado com o motivo em vez de buscar. A página embrulha no molde flush
/// com o título "Visualizações da equipe".
///
/// Carrega sozinho `GET /properties/:id/views` ao montar (sob demanda, como o
/// web) e guarda o resultado por imóvel na sessão: ao voltar para a aba, os
/// dados aparecem na hora e se atualizam em silêncio. Carregando = skeleton;
/// falha = causa + "Tentar de novo"; vazio ensina. Para forçar recarga
/// (puxar para atualizar), chame [invalidate] e reconstrua com outra `key`.
class PropertyViewersTab extends StatefulWidget {
  const PropertyViewersTab({
    super.key,
    required this.propertyId,
    required this.canView,
  });

  final String propertyId;
  final bool canView;

  /// Gestor, admin ou master (a mesma regra do back).
  static bool canViewFor(String? userRole) =>
      PropertyDetailExtrasService.isManagementRole(userRole);

  static final Map<String, PropertyViewsSummary> _cache =
      <String, PropertyViewsSummary>{};

  /// Esquece o que foi guardado deste imóvel (a próxima montagem busca).
  static void invalidate(String propertyId) => _cache.remove(propertyId);

  @override
  State<PropertyViewersTab> createState() => _PropertyViewersTabState();
}

class _PropertyViewersTabState extends State<PropertyViewersTab> {
  PropertyViewsSummary? _data;
  bool _loading = false;
  String? _errorMessage;
  int _errorStatus = 0;
  Object? _errorDetail;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _data = PropertyViewersTab._cache[widget.propertyId];
    if (widget.canView) _load();
  }

  @override
  void didUpdateWidget(covariant PropertyViewersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId ||
        (widget.canView && !oldWidget.canView)) {
      _data = PropertyViewersTab._cache[widget.propertyId];
      _failed = false;
      if (widget.canView) _load();
    }
  }

  Future<void> _load() async {
    final propertyId = widget.propertyId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final res =
        await PropertyDetailExtrasService.instance.getViews(propertyId);
    if (!mounted || widget.propertyId != propertyId) return;
    final data = res.data;
    setState(() {
      _loading = false;
      if (res.success && data != null) {
        _data = data;
        PropertyViewersTab._cache[propertyId] = data;
      } else {
        _failed = true;
        _errorMessage = res.message;
        _errorStatus = res.statusCode;
        _errorDetail = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final lead = Text(
      'Acompanhe quais colaboradores acessaram a ficha deste imóvel e quando. '
      'Visível apenas para gestores e administradores.',
      style: TextStyle(color: secondary, fontSize: 12.5, height: 1.45),
    );
    if (!widget.canView) {
      return const PdkLockNote(
        title: 'Visualizações da equipe',
        reason: kPropertyViewersLockedReason,
      );
    }

    final data = _data;
    final Widget body;
    if (data == null && _loading) {
      body = const _ViewersSkeleton();
    } else if (data == null && _failed) {
      body = AppErrorState.fromApi(
        message: _errorMessage,
        statusCode: _errorStatus,
        error: _errorDetail,
        onRetry: _load,
        dense: true,
      );
    } else if (data == null || !data.hasData) {
      body = const _ViewersEmpty();
    } else {
      body = _ViewersContent(data: data);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        lead,
        const SizedBox(height: 14),
        body,
        // Atualização em silêncio falhou com dados na tela: diz, sem apagar.
        if (data != null && _failed) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                LucideIcons.circleAlert,
                size: 14,
                color: pdkInk(context, PdkTone.amber(context)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Não foi possível atualizar agora — mostrando a última '
                  'leitura.',
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _load,
                style: TextButton.styleFrom(
                  foregroundColor: secondary,
                  minimumSize: const Size(0, 36),
                ),
                child: const PdkButtonLabel('Tentar de novo'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Papel → rótulo (`translateUserRole` do web; admin sem o "dono" vira
/// "Administrativo").
String _roleLabel(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'user':
      return 'Colaborador';
    case 'manager':
      return 'Gestor';
    case 'admin':
      return 'Administrativo';
    case 'master':
      return 'Gerenciador';
    case 'leader':
      return 'Gestor da equipe';
    case 'member':
      return 'Membro';
    default:
      return (role ?? '').trim();
  }
}

class _ViewersContent extends StatelessWidget {
  const _ViewersContent({required this.data});

  final PropertyViewsSummary data;

  @override
  Widget build(BuildContext context) {
    final divider = ThemeHelpers.borderLightColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Figures(
          people: data.uniqueViewers,
          visits: data.totalVisits,
          views: data.totalViews,
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: divider),
        for (var i = 0; i < data.viewers.length; i++) ...[
          if (i > 0) Container(height: 1, color: divider),
          _ViewerRow(viewer: data.viewers[i]),
        ],
      ],
    );
  }
}

/// Os três números do web (pessoas, visitas, aberturas) numa régua com
/// filetes — número na tinta do texto, rótulo curto embaixo.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.people,
    required this.visits,
    required this.views,
  });

  final int people;
  final int visits;
  final int views;

  @override
  Widget build(BuildContext context) {
    final divider = ThemeHelpers.borderLightColor(context);
    final blue = PdkTone.blue(context);
    Widget figure(int value, String label, {bool lead = false}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$value',
                  maxLines: 1,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontSize: lead ? 30 : 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.05,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: lead ? blue : ThemeHelpers.borderColor(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          figure(
            people,
            people == 1 ? 'pessoa viu' : 'pessoas viram',
            lead: true,
          ),
          Container(width: 1, color: divider),
          const SizedBox(width: 8),
          figure(visits, visits == 1 ? 'visita' : 'visitas'),
          Container(width: 1, color: divider),
          const SizedBox(width: 8),
          figure(
            views,
            views == 1 ? 'abertura no total' : 'aberturas no total',
          ),
        ],
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({required this.viewer});

  final PropertyViewer viewer;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final blue = PdkTone.blue(context);
    final name = viewer.userName?.trim() ?? '';
    final role = _roleLabel(viewer.userRole);
    final last = viewer.lastViewedAt;
    final lastText = last == null
        ? null
        : DateFormat('dd/MM/yyyy · HH:mm').format(last.toLocal());
    final extraOpenings = viewer.totalViews > viewer.visitCount;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PdkInitialsAvatar(
            name: name.isEmpty ? 'Usuário' : name,
            tone: blue,
            imageUrl: viewer.avatar,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Usuário removido' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (role.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: blue.withValues(alpha: isDark ? 0.18 : 0.1),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          role.toUpperCase(),
                          style: TextStyle(
                            color: pdkInk(context, blue),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    if (lastText != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.clock, size: 12, color: secondary),
                          const SizedBox(width: 4),
                          Text(
                            lastText,
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    if (extraOpenings)
                      Text(
                        '· ${viewer.totalViews} aberturas',
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, maxWidth: 72),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${viewer.visitCount}',
                    maxLines: 1,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  viewer.visitCount == 1 ? 'visita' : 'visitas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _ViewersEmpty extends StatelessWidget {
  const _ViewersEmpty();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = PdkTone.blue(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: isDark ? 0.2 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.users,
              size: 24,
              color: pdkInk(context, blue),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Nenhuma visualização registrada ainda',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Assim que algum membro da equipe abrir a ficha deste imóvel, o '
            'acesso aparecerá aqui com data, hora e quantidade de '
            'visualizações.',
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Skeleton fiel: régua dos três números e quatro linhas de pessoa.
class _ViewersSkeleton extends StatelessWidget {
  const _ViewersSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(child: _FigureSkeleton()),
            SizedBox(width: 12),
            Expanded(child: _FigureSkeleton()),
            SizedBox(width: 12),
            Expanded(child: _FigureSkeleton()),
          ],
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                const SkeletonBox(width: 42, height: 42, borderRadius: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: i.isEven ? 0.55 : 0.45,
                        child: const SkeletonBox(height: 13, borderRadius: 6),
                      ),
                      const SizedBox(height: 7),
                      const FractionallySizedBox(
                        widthFactor: 0.7,
                        child: SkeletonBox(height: 10, borderRadius: 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const SkeletonBox(width: 34, height: 30, borderRadius: 6),
              ],
            ),
          ),
      ],
    );
  }
}

class _FigureSkeleton extends StatelessWidget {
  const _FigureSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 44, height: 26, borderRadius: 6),
        SizedBox(height: 6),
        SkeletonBox(width: 70, height: 10, borderRadius: 4),
      ],
    );
  }
}
