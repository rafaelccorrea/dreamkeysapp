import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../services/property_detail_extras_service.dart';
import 'property_details_kit.dart';

/// Motivo do cadeado de "Restaurar versão" — a frase do back
/// (`restorePropertyToRevision`).
const String kPropertyRestoreLockedReason =
    'Apenas administradores e gestores podem restaurar uma versão anterior do '
    'imóvel. Para liberar o acesso, fale com o seu gestor ou com o suporte.';

/// "Versões anteriores (restauração)" — paridade com o bloco do histórico
/// completo do web (W:1349-1460 e 3123-3174). A página monta dentro da aba
/// Atividades, junto do histórico completo, sob o título "Versões anteriores
/// (restauração)"; o corpo carrega sozinho `GET
/// /properties/:id/revisions?limit=50` (da mais recente para a mais antiga).
///
/// - [canRestore] = master/admin/gestor e imóvel NÃO excluído (a regra do
///   web; calcule com [canRestoreFor]). Sem ela, a seção mostra o cadeado com
///   o motivo ([lockedReason] troca o texto — ex.: imóvel excluído) e não
///   busca nada.
/// - Cada versão: quando · quem fez a alteração e "Restaurar", com
///   confirmação (texto do web). Restaurar chama `POST
///   /properties/:id/revisions/:revId/restore`; deu certo → aviso "Versão
///   restaurada." e [onRestored] (a página recarrega a ficha e o
///   histórico).
/// - Carregando = skeleton; falha = causa + "Tentar de novo"; vazio ensina.
class PropertyRevisionsSection extends StatefulWidget {
  const PropertyRevisionsSection({
    super.key,
    required this.propertyId,
    required this.canRestore,
    this.lockedReason,
    this.onRestored,
  });

  final String propertyId;
  final bool canRestore;
  final String? lockedReason;
  final VoidCallback? onRestored;

  /// Regra do web (`canRestorePropertyVersion`): gestão e imóvel não
  /// excluído.
  static bool canRestoreFor({
    required Property property,
    required String? userRole,
  }) =>
      !property.isDeleted &&
      PropertyDetailExtrasService.isManagementRole(userRole);

  @override
  State<PropertyRevisionsSection> createState() =>
      _PropertyRevisionsSectionState();
}

class _PropertyRevisionsSectionState extends State<PropertyRevisionsSection> {
  static const int _preview = 8;

  bool _loading = false;
  _LoadFailure? _failure;
  List<PropertyRevision> _revisions = const <PropertyRevision>[];
  bool _showAll = false;
  String? _restoringId;

  @override
  void initState() {
    super.initState();
    if (widget.canRestore) _load();
  }

  @override
  void didUpdateWidget(covariant PropertyRevisionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameAllowed = widget.canRestore && !oldWidget.canRestore;
    if (oldWidget.propertyId != widget.propertyId || becameAllowed) {
      _revisions = const <PropertyRevision>[];
      _showAll = false;
      if (widget.canRestore) _load();
    }
  }

  Future<void> _load() async {
    final propertyId = widget.propertyId;
    setState(() {
      _loading = true;
      _failure = null;
    });
    final res =
        await PropertyDetailExtrasService.instance.getRevisions(propertyId);
    if (!mounted || widget.propertyId != propertyId) return;
    setState(() {
      _loading = false;
      if (res.success) {
        _revisions = res.data ?? const <PropertyRevision>[];
      } else {
        _failure = _LoadFailure(
          message: res.message,
          statusCode: res.statusCode,
          error: res.error,
        );
      }
    });
  }

  Future<void> _restore(PropertyRevision revision) async {
    if (_restoringId != null) return;
    final confirmed = await _confirmRestore(context, revision);
    if (confirmed != true || !mounted) return;
    setState(() => _restoringId = revision.id);
    final res = await PropertyDetailExtrasService.instance.restoreRevision(
      widget.propertyId,
      revision.id,
    );
    if (!mounted) return;
    setState(() => _restoringId = null);
    if (pdkApplied(res)) {
      pdkShowSnack(context, 'Versão restaurada.', tone: PdkSnackTone.success);
      widget.onRestored?.call();
      _load();
      return;
    }
    final String message;
    if (res.statusCode == 408) {
      message = 'A restauração demorou mais que o esperado e pode ter sido '
          'aplicada. Recarregue a ficha para conferir.';
    } else {
      final server = (res.message ?? '').trim();
      message = server.isNotEmpty
          ? server
          : 'Não foi possível restaurar a versão. '
              '${pdkFailureCause(res).cause}';
    }
    pdkShowSnack(context, message, tone: PdkSnackTone.error);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canRestore) {
      final custom = widget.lockedReason?.trim() ?? '';
      return PdkLockNote(
        title: 'Restaurar versões está travado',
        reason: custom.isNotEmpty ? custom : kPropertyRestoreLockedReason,
      );
    }
    if (_loading && _revisions.isEmpty) return const _RevisionsSkeleton();
    final failure = _failure;
    if (failure != null && _revisions.isEmpty) {
      return AppErrorState.fromApi(
        message: failure.message,
        statusCode: failure.statusCode,
        error: failure.error,
        onRetry: _load,
        dense: true,
      );
    }
    if (_revisions.isEmpty) return const _RevisionsEmpty();

    final shown = _showAll || _revisions.length <= _preview
        ? _revisions
        : _revisions.sublist(0, _preview);
    final divider = ThemeHelpers.borderLightColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _revisions.length == 1
              ? '1 versão guardada · a mais recente primeiro'
              : '${_revisions.length} versões guardadas · a mais recente '
                  'primeiro',
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Container(height: 1, color: divider),
          _RevisionRow(
            revision: shown[i],
            busy: _restoringId == shown[i].id,
            enabled: _restoringId == null,
            onRestore: () => _restore(shown[i]),
          ),
        ],
        if (_revisions.length > _preview) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                minimumSize: const Size(0, 40),
              ),
              icon: Icon(
                _showAll ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16,
              ),
              label: Text(
                _showAll
                    ? 'Mostrar menos'
                    : 'Ver todas as ${_revisions.length} versões',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Falha guardada para desenhar o erro.
class _LoadFailure {
  const _LoadFailure({this.message, this.statusCode = 0, this.error});

  final String? message;
  final int statusCode;
  final Object? error;
}

String _revisionStamp(PropertyRevision r) {
  final at = r.createdAt;
  final when = at == null
      ? 'Data não registrada'
      : DateFormat('dd/MM/yyyy · HH:mm').format(at.toLocal());
  final who = r.createdByName?.trim() ?? '';
  return who.isEmpty ? when : '$when · $who';
}

/// Confirmação da restauração (o `window.confirm` do web, na folha da casa).
Future<bool?> _confirmRestore(
  BuildContext context,
  PropertyRevision revision,
) {
  return showPdkSheet<bool>(
    context: context,
    builder: (sheetContext) => PdkSheetFrame(
      icon: LucideIcons.rotateCcw,
      tone: PdkTone.amber(sheetContext),
      title: 'Restaurar esta versão?',
      subtitle: 'Versão de ${_revisionStamp(revision)}',
      onClose: () => Navigator.of(sheetContext).pop(false),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Text(
          'A ficha voltará ao estado salvo nesse instante (incluindo '
          'responsáveis/captadores quando constarem nessa versão).',
          style: TextStyle(
            color: ThemeHelpers.textColor(sheetContext),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ),
      footer: PdkActionPair(
        primary: PdkSolidButton(
          label: 'Restaurar',
          tone: PdkTone.green(sheetContext),
          icon: LucideIcons.rotateCcw,
          onPressed: () => Navigator.of(sheetContext).pop(true),
        ),
        secondary: PdkNeutralButton(
          label: 'Cancelar',
          onPressed: () => Navigator.of(sheetContext).pop(false),
        ),
      ),
    ),
  );
}

/// Linha flush de uma versão: selo, quando · quem, o que ela é e
/// "Restaurar" (desce para baixo do texto em tela estreita/fonte grande).
class _RevisionRow extends StatelessWidget {
  const _RevisionRow({
    required this.revision,
    required this.busy,
    required this.enabled,
    required this.onRestore,
  });

  final PropertyRevision revision;
  final bool busy;
  final bool enabled;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _revisionStamp(revision),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            height: 1.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Estado da ficha antes desta alteração',
          style: TextStyle(color: secondary, fontSize: 12, height: 1.35),
        ),
      ],
    );
    final button = PdkNeutralButton(
      label: busy ? 'Restaurando…' : 'Restaurar',
      icon: LucideIcons.rotateCcw,
      onPressed: enabled ? onRestore : null,
    );
    final plate = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(LucideIcons.history, size: 17, color: secondary),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = pdkTextScale(context);
          final inline = constraints.maxWidth >= 360 * scale;
          if (inline) {
            return Row(
              children: [
                plate,
                const SizedBox(width: 12),
                Expanded(child: info),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: button,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              plate,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [info, const SizedBox(height: 8), button],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RevisionsEmpty extends StatelessWidget {
  const _RevisionsEmpty();

  @override
  Widget build(BuildContext context) {
    return PdkNote(
      icon: LucideIcons.history,
      tone: PdkTone.blue(context),
      text: 'Nenhuma versão anterior guardada ainda. Cada alteração salva na '
          'ficha guarda aqui como ela estava antes — e daqui dá para voltar.',
    );
  }
}

/// Skeleton fiel à linha (selo, duas linhas de texto e o botão).
class _RevisionsSkeleton extends StatelessWidget {
  const _RevisionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const SkeletonBox(width: 36, height: 36, borderRadius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: i.isEven ? 0.7 : 0.55,
                        child: const SkeletonBox(height: 13, borderRadius: 6),
                      ),
                      const SizedBox(height: 6),
                      const FractionallySizedBox(
                        widthFactor: 0.5,
                        child: SkeletonBox(height: 10, borderRadius: 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const SkeletonBox(width: 96, height: 40, borderRadius: 12),
              ],
            ),
          ),
      ],
    );
  }
}
