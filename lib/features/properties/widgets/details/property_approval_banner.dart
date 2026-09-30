import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/constants/app_permissions.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../services/property_approval_service.dart';
import 'property_details_kit.dart';

/// Avisos de aprovação no topo da ficha — paridade com o
/// `PropertyRejectionNotice` e o `PropertyInReviewNotice` do web (W:2181-2223;
/// ações em W:1547-1595). Mesma condição do web, lida do [Property]:
///
/// - `availabilityRejectedAt` → recusa da disponibilidade (vermelho): motivo,
///   "recusado em …", "Reenviar para aprovação" e "Ver fila";
/// - `publicationRejectedAt` → recusa da publicação no site (âmbar), idem;
/// - sem recusa e status `pending_approval`/`pending_publication` → "Em
///   análise" (âmbar, espera): desde quando e "Ver a fila".
///
/// Nada disso → `SizedBox.shrink()` (use [hasContent] para não reservar
/// espaço).
///
/// Reenviar chama o endpoint do web: quem aprova (disponibilidade:
/// master/admin ou `property:approve_availability` explícita; publicação:
/// master/admin/gestor ou `property:approve_publication` explícita) usa
/// `request-(availability|site-publication)-review`; os demais, o do
/// responsável (`responsible/reopen-…-review`). Calcule as duas flags com
/// [approverRights] — ele segue a regra do web (o `hasPermission` do app
/// libera gestor em tudo, e o back NÃO libera gestor nesses endpoints).
///
/// Depois do reenvio o aviso de sucesso sai daqui e [onResent] avisa a página
/// para recarregar a ficha; falha aparece dentro do próprio aviso, com a
/// causa. [onOpenQueue] abre a fila de aprovações (sem ele, o botão não
/// aparece). [resendLockedReason] trava o reenvio com o motivo (ex.: imóvel
/// excluído — somente consulta).
class PropertyApprovalBanner extends StatefulWidget {
  const PropertyApprovalBanner({
    super.key,
    required this.property,
    required this.canApproveAvailability,
    required this.canApprovePublication,
    this.onResent,
    this.onOpenQueue,
    this.resendLockedReason,
  });

  final Property property;

  /// Usa o endpoint de aprovador para reabrir a disponibilidade.
  final bool canApproveAvailability;

  /// Usa o endpoint de aprovador para reabrir a publicação.
  final bool canApprovePublication;

  /// Reenvio aceito — a página recarrega a ficha.
  final VoidCallback? onResent;

  /// Abre a fila de aprovações.
  final VoidCallback? onOpenQueue;

  /// Quando preenchido, "Reenviar" fica travado com este motivo.
  final String? resendLockedReason;

  /// Há algum aviso para este imóvel.
  static bool hasContent(Property property) =>
      _noticesOf(property).isNotEmpty;

  /// As duas flags de aprovador exatamente como o web as calcula
  /// (`canApproveAvailability` / `canApprovePublication` da ficha):
  /// passe o papel do usuário e as permissões EXPLÍCITAS
  /// (`ModuleAccessService.instance.userPermissionNames`).
  static ({bool availability, bool publication}) approverRights({
    required String? role,
    required List<String> explicitPermissions,
  }) {
    final r = role?.trim().toLowerCase() ?? '';
    final masterOrAdmin = r == 'master' || r == 'admin';
    return (
      availability: masterOrAdmin ||
          explicitPermissions.contains(
            AppPermissions.propertyApproveAvailability,
          ),
      publication: masterOrAdmin ||
          r == 'manager' ||
          explicitPermissions.contains(
            AppPermissions.propertyApprovePublication,
          ),
    );
  }

  @override
  State<PropertyApprovalBanner> createState() => _PropertyApprovalBannerState();
}

enum _NoticeKind {
  availabilityInReview,
  publicationInReview,
  availabilityRejected,
  publicationRejected,
}

extension on _NoticeKind {
  bool get isPublication =>
      this == _NoticeKind.publicationInReview ||
      this == _NoticeKind.publicationRejected;

  bool get isRejection =>
      this == _NoticeKind.availabilityRejected ||
      this == _NoticeKind.publicationRejected;
}

/// Mesma ordem e condição do web: "em análise" só sem recusa; depois a recusa
/// da disponibilidade e a da publicação (as duas podem aparecer juntas).
List<_NoticeKind> _noticesOf(Property p) {
  final availabilityRejected = (p.availabilityRejectedAt ?? '').trim().isNotEmpty;
  final publicationRejected = (p.publicationRejectedAt ?? '').trim().isNotEmpty;
  final status = p.statusRaw.trim().toLowerCase().replaceAll('-', '_');
  final out = <_NoticeKind>[];
  if (!availabilityRejected && !publicationRejected) {
    if (status == PropertyStatus.pendingPublication.value) {
      out.add(_NoticeKind.publicationInReview);
    } else if (status == PropertyStatus.pendingApproval.value) {
      out.add(_NoticeKind.availabilityInReview);
    }
  }
  if (availabilityRejected) out.add(_NoticeKind.availabilityRejected);
  if (publicationRejected) out.add(_NoticeKind.publicationRejected);
  return out;
}

String? _nonEmpty(String? value) {
  final v = value?.trim() ?? '';
  return v.isEmpty ? null : v;
}

class _PropertyApprovalBannerState extends State<PropertyApprovalBanner> {
  /// Aviso cujo reenvio está em andamento.
  _NoticeKind? _busy;

  final Map<_NoticeKind, ErrorCause> _errors = <_NoticeKind, ErrorCause>{};

  @override
  void didUpdateWidget(covariant PropertyApprovalBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ficha recarregada: a falha antiga não vale mais.
    if (!identical(oldWidget.property, widget.property)) _errors.clear();
  }

  Future<void> _resend(_NoticeKind kind) async {
    if (_busy != null) return;
    setState(() {
      _busy = kind;
      _errors.remove(kind);
    });
    final service = PropertyApprovalService.instance;
    final id = widget.property.id;
    final ApiResponse<Property> res;
    if (kind.isPublication) {
      res = widget.canApprovePublication
          ? await service.requestSitePublicationReview(id)
          : await service.requestSitePublicationReviewAsResponsible(id);
    } else {
      res = widget.canApproveAvailability
          ? await service.requestAvailabilityReview(id)
          : await service.requestAvailabilityReviewAsResponsible(id);
    }
    if (!mounted) return;
    final ok = pdkApplied(res);
    setState(() {
      _busy = null;
      if (!ok) _errors[kind] = pdkFailureCause(res);
    });
    if (!ok) return;
    pdkShowSnack(
      context,
      kind.isPublication
          ? 'Publicação reenviada para nova aprovação.'
          : 'Disponibilidade reenviada para nova aprovação.',
      tone: PdkSnackTone.success,
    );
    widget.onResent?.call();
  }

  @override
  Widget build(BuildContext context) {
    final notices = _noticesOf(widget.property);
    if (notices.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < notices.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _notice(context, notices[i]),
        ],
      ],
    );
  }

  Widget _notice(BuildContext context, _NoticeKind kind) {
    final p = widget.property;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final text = ThemeHelpers.textColor(context);
    final publication = kind.isPublication;
    final rejected = kind.isRejection;
    final tone = kind == _NoticeKind.availabilityRejected
        ? PdkTone.red(context)
        : PdkTone.amber(context);
    final ink = pdkInk(context, tone);
    final IconData icon;
    if (kind == _NoticeKind.availabilityRejected) {
      icon = LucideIcons.ban;
    } else if (rejected) {
      icon = LucideIcons.triangleAlert;
    } else {
      icon = LucideIcons.hourglass;
    }

    final area = publication ? 'Publicação no site' : 'Disponibilidade';
    final eyebrow = rejected ? 'Recusa · $area' : 'Em análise · $area';
    final String? stampIso;
    if (rejected) {
      stampIso =
          publication ? p.publicationRejectedAt : p.availabilityRejectedAt;
    } else {
      stampIso = publication
          ? (_nonEmpty(p.publicationRequestedAt) ?? p.updatedAt)
          : p.updatedAt;
    }
    final stamp = pdkStamp(stampIso);
    final stampText =
        stamp == null ? null : (rejected ? 'recusado em $stamp' : 'desde $stamp');
    final String title;
    if (rejected) {
      title = publication
          ? 'O aprovador recusou a publicação deste imóvel no site'
          : 'O aprovador recusou a disponibilidade deste imóvel';
    } else {
      title = publication
          ? 'O imóvel está na fila de aprovação de publicação no site'
          : 'O imóvel está na fila de aprovação de disponibilidade';
    }
    final reason = rejected
        ? (_nonEmpty(
                publication
                    ? p.publicationRejectionReason
                    : p.availabilityRejectionReason,
              ) ??
              '')
        : '';
    final error = _errors[kind];
    final busy = _busy == kind;
    final lockReason = _nonEmpty(widget.resendLockedReason);

    Widget? queueButton;
    if (widget.onOpenQueue != null) {
      queueButton = PdkNeutralButton(
        label: rejected ? 'Ver fila de aprovações' : 'Ver a fila de aprovações',
        trailingIcon: LucideIcons.chevronRight,
        onPressed: widget.onOpenQueue,
      );
    }
    Widget? resendButton;
    if (rejected) {
      resendButton = PdkSolidButton(
        label: busy ? 'Reenviando…' : 'Reenviar para aprovação',
        tone: PdkTone.green(context),
        icon: lockReason != null ? LucideIcons.lock : LucideIcons.refreshCw,
        busy: busy,
        onPressed: lockReason != null || _busy != null
            ? null
            : () => _resend(kind),
      );
    }

    final Widget? actions;
    if (resendButton != null && queueButton != null) {
      actions = PdkActionPair(
        primary: resendButton,
        secondary: queueButton,
        minPrimary: 170,
        minSecondary: 120,
      );
    } else {
      actions = resendButton ?? queueButton;
    }

    return Semantics(
      container: true,
      label: rejected
          ? (publication
              ? 'Publicação no site recusada pelo aprovador'
              : 'Disponibilidade recusada pelo aprovador')
          : 'Imóvel em análise de aprovação',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            eyebrow,
                            style: TextStyle(
                              color: ink,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (stampText != null)
                            Text(
                              stampText,
                              style: TextStyle(
                                color: secondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          color: text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motivo',
                      style: TextStyle(
                        color: secondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason,
                      style: TextStyle(
                        color: text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (rejected)
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Corrija o cadastro e '),
                    TextSpan(
                      text: 'reenvie',
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const TextSpan(
                      text: ': o imóvel volta para a fila e o aprovador '
                          'analisa de novo.',
                    ),
                  ],
                ),
                style: TextStyle(color: secondary, fontSize: 12.5, height: 1.4),
              )
            else
              Text(
                'Nada a fazer aqui: assim que o aprovador responder, o estado '
                'muda sozinho.',
                style: TextStyle(color: secondary, fontSize: 12.5, height: 1.4),
              ),
            if (error != null) ...[
              const SizedBox(height: 12),
              PdkErrorNote(
                title: 'Não foi possível reenviar para nova aprovação',
                cause: error,
              ),
            ],
            if (actions != null) ...[
              const SizedBox(height: 14),
              actions,
            ],
            if (rejected && lockReason != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      LucideIcons.lock,
                      size: 14,
                      color: pdkInk(context, PdkTone.violet(context)),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      lockReason,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
