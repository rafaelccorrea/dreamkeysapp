import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../services/property_settings_service.dart';
import '../widgets/property_settings_kit.dart';
import 'property_protected_fields_page.dart';

/// Imóveis › Configuração de aprovações — paridade com
/// `PropertyApprovalSettingsPage.tsx` (`/properties/approval-settings`).
///
/// - Regras do fluxo: 5 interruptores salvos juntos
///   (`PATCH /properties/approval-settings`).
/// - Votação por aprovadores: liga/desliga na hora
///   (`PUT /properties/approvers/quorum-settings`) e, ligada, os painéis de
///   aprovadores de disponibilidade e publicação (adicionar, obrigatório ★,
///   remover, mínimo de aprovações).
/// - Atalho para Campos protegidos.
/// - Usuários autorizados a aprovar, com revogação.
class PropertyApprovalSettingsPage extends StatefulWidget {
  const PropertyApprovalSettingsPage({super.key});

  @override
  State<PropertyApprovalSettingsPage> createState() =>
      _PropertyApprovalSettingsPageState();
}

class _PropertyApprovalSettingsPageState
    extends State<PropertyApprovalSettingsPage> {
  final _svc = PropertySettingsService.instance;

  bool _loading = true;
  bool _savingRules = false;
  String? _error;
  int _errorStatus = 0;
  Object? _errorDetail;

  PropertyApprovalSettingsFull? _saved;
  PropertyApprovalSettingsFull? _settings;
  PropertyAuthorizedApprovers _authorized = const PropertyAuthorizedApprovers();
  List<PropertySettingsMember> _members = const [];

  /// Sobe quando algo fora dos painéis muda a lista de aprovadores.
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final settingsF = _svc.getApprovalSettings();
    final membersF = _svc.listCompanyMembers();
    _loadAuthorized();
    final res = await settingsF;
    final members = await membersF;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (members.success) _members = members.data ?? const [];
      if (res.success && res.data != null) {
        _saved = res.data;
        _settings = res.data;
        _reloadToken++;
      } else {
        _error = psFailMessage(
          res.message,
          'Não foi possível carregar a configuração de aprovações.',
        );
        _errorStatus = res.statusCode;
        _errorDetail = res.error;
      }
    });
  }

  Future<void> _loadAuthorized() async {
    final res = await _svc.listAuthorizedApprovers();
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _authorized = res.data!);
  }

  /// Ao voltar de Campos protegidos: só o resumo do fluxo muda — não
  /// descarta interruptores ainda não salvos.
  Future<void> _refreshProtected() async {
    final res = await _svc.getApprovalSettings();
    final fresh = res.data;
    if (!mounted || !res.success || fresh == null) return;
    setState(() {
      _settings = _settings?.copyWith(
        protectedFieldsEnabled: fresh.protectedFieldsEnabled,
        protectedFields: fresh.protectedFields,
      );
      _saved = _saved?.copyWith(
        protectedFieldsEnabled: fresh.protectedFieldsEnabled,
        protectedFields: fresh.protectedFields,
      );
    });
  }

  void _patch(PropertyApprovalSettingsFull next) =>
      setState(() => _settings = next);

  Future<void> _saveRules() async {
    final s = _settings;
    if (s == null) return;
    setState(() => _savingRules = true);
    final res =
        await _svc.updateApprovalSettings(PropertyApprovalRules.rulesPayload(s));
    if (!mounted) return;
    setState(() => _savingRules = false);
    if (res.success) {
      setState(() {
        _saved = (_saved ?? s).copyWith(
          requireApprovalToBeAvailable: s.requireApprovalToBeAvailable,
          requireApprovalToPublishOnSite: s.requireApprovalToPublishOnSite,
          requireOwnerAuthorizationToBeAvailable:
              s.requireOwnerAuthorizationToBeAvailable,
          applyWatermarkToImages: s.applyWatermarkToImages,
          preservePublicationOnEdit: s.preservePublicationOnEdit,
        );
      });
      psSnack(context, 'Regras de aprovação salvas.', ok: true);
    } else {
      psSnack(
        context,
        psFailMessage(res.message, 'Erro ao salvar as regras de aprovação.'),
      );
    }
  }

  Future<void> _toggleApprovers(bool next) async {
    final s = _settings;
    if (s == null) return;
    _patch(s.copyWith(approversEnabled: next));
    final res = await _svc.updateQuorumSettings({'approversEnabled': next});
    if (!mounted) return;
    if (res.success) {
      final updated = res.data;
      setState(() {
        _settings = updated != null
            ? _settings!.copyWith(
                approversEnabled: updated.approversEnabled,
                minApprovalsAvailability: updated.minApprovalsAvailability,
                minApprovalsPublication: updated.minApprovalsPublication,
              )
            : _settings;
        _saved = (_saved ?? s).copyWith(approversEnabled: next);
      });
      psSnack(
        context,
        next
            ? 'Sistema de votação por aprovadores ativado.'
            : 'Sistema de votação por aprovadores desativado.',
        ok: true,
      );
    } else {
      _patch(_settings!.copyWith(approversEnabled: !next));
      psSnack(
        context,
        psFailMessage(res.message, 'Erro ao atualizar o sistema de aprovadores.'),
      );
    }
  }

  Future<void> _revoke(PropertySettingsMember u, ApproverType type) async {
    final ok = await psConfirm(
      context,
      title: 'Revogar permissão',
      message: 'Remover ${u.name} da lista de aprovadores de '
          '${type == ApproverType.availability ? 'disponibilidade' : 'publicação'}'
          '? As permissões diretas deste tipo também serão revogadas.',
      confirmLabel: 'Revogar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final res =
        await _svc.revokeUserApprovalPermission(userId: u.id, type: type);
    if (!mounted) return;
    if (res.success) {
      psSnack(context, 'Permissão de aprovação removida.', ok: true);
      setState(() => _reloadToken++);
      _loadAuthorized();
    } else {
      psSnack(context, psFailMessage(res.message, 'Erro ao revogar permissão.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Aprovações',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loading ? null : _load,
          icon: const Icon(LucideIcons.refreshCw, size: 20),
        ),
      ],
      body: RefreshIndicator(onRefresh: _load, child: _content(context)),
    );
  }

  Widget _content(BuildContext context) {
    final s = _settings;
    if (_loading && s == null) {
      return ListView(children: const [PsSkeleton(blocks: [150, 320, 180])]);
    }
    if (s == null) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: AppErrorState.fromApi(
              message: _error,
              statusCode: _errorStatus,
              error: _errorDetail,
              onRetry: _load,
            ),
          ),
        ],
      );
    }
    final primary = PsPalette.primary(context);
    final green = PsPalette.green(context);
    final dirty = PropertyApprovalRules.rulesDirty(_saved, s);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PsHero(
          eyebrow: 'Fluxo de aprovações',
          title: 'Configuração de aprovações',
          icon: LucideIcons.badgeCheck,
          color: primary,
          subtitle: 'Defina as regras do fluxo de aprovação dos imóveis, o '
              'sistema de votação por aprovadores e quem está autorizado a '
              'aprovar. As regras valem para toda a empresa.',
          chips: [
            PsChip(
              label: s.anyActive ? 'Aprovações ativas' : 'Aprovações inativas',
              color: green,
              on: s.anyActive,
              icon: LucideIcons.shieldCheck,
            ),
            PsChip(
              label: 'Disponibilidade',
              color: green,
              on: s.requireApprovalToBeAvailable,
              icon: s.requireApprovalToBeAvailable
                  ? LucideIcons.circleCheck
                  : LucideIcons.circle,
            ),
            PsChip(
              label: 'Publicação',
              color: green,
              on: s.requireApprovalToPublishOnSite,
              icon: s.requireApprovalToPublishOnSite
                  ? LucideIcons.circleCheck
                  : LucideIcons.circle,
            ),
            PsChip(
              label: 'Votação',
              color: green,
              on: s.approversEnabled,
              icon: s.approversEnabled
                  ? LucideIcons.circleCheck
                  : LucideIcons.circle,
            ),
            PsChip(
              label: 'Campos protegidos',
              color: green,
              on: s.protectedFieldsEnabled,
              icon: s.protectedFieldsEnabled
                  ? LucideIcons.circleCheck
                  : LucideIcons.circle,
            ),
          ],
        ),
        // ── Regras ──
        PsSection(
          title: 'Regras de aprovação',
          subtitle: 'Ative ou desative cada regra do fluxo. As mudanças só '
              'valem após salvar.',
          icon: LucideIcons.settings2,
          color: primary,
          trailing: dirty
              ? PsBadge(label: 'não salvo', color: PsPalette.amber(context))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rule(
                'Exigir autorização do proprietário',
                'O imóvel só fica disponível após a autorização do '
                    'proprietário.',
                LucideIcons.fileSignature,
                s.requireOwnerAuthorizationToBeAvailable,
                (v) => _patch(
                    s.copyWith(requireOwnerAuthorizationToBeAvailable: v)),
              ),
              _rule(
                'Exigir aprovação para disponibilizar',
                'Novos imóveis entram em fila de aprovação antes de ficar '
                    'disponíveis.',
                LucideIcons.house,
                s.requireApprovalToBeAvailable,
                (v) => _patch(s.copyWith(requireApprovalToBeAvailable: v)),
              ),
              _rule(
                'Exigir aprovação para publicar no site',
                'A publicação no site passa por aprovação antes de ir ao ar.',
                LucideIcons.globe,
                s.requireApprovalToPublishOnSite,
                (v) => _patch(s.copyWith(requireApprovalToPublishOnSite: v)),
              ),
              _rule(
                'Aplicar marca d’água ao publicar',
                'Ao aprovar a publicação, aplica a marca d’água nas imagens.',
                LucideIcons.image,
                s.applyWatermarkToImages,
                (v) => _patch(s.copyWith(applyWatermarkToImages: v)),
              ),
              _rule(
                'Manter publicação ao editar',
                'Editar um imóvel já publicado não o envia para nova '
                    'aprovação.',
                LucideIcons.pencil,
                s.preservePublicationOnEdit,
                (v) => _patch(s.copyWith(preservePublicationOnEdit: v)),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (dirty)
                    TextButton(
                      onPressed: _savingRules
                          ? null
                          : () => setState(() => _settings = _saved?.copyWith(
                                approversEnabled: s.approversEnabled,
                                minApprovalsAvailability:
                                    s.minApprovalsAvailability,
                                minApprovalsPublication:
                                    s.minApprovalsPublication,
                                protectedFieldsEnabled:
                                    s.protectedFieldsEnabled,
                                protectedFields: s.protectedFields,
                              )),
                      child: const Text('Descartar'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _savingRules ? null : _saveRules,
                    icon: _savingRules
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.save, size: 16),
                    label: Text(_savingRules ? 'Salvando…' : 'Salvar regras'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ── Votação ──
        PsSection(
          title: 'Votação por aprovadores',
          subtitle: 'Quando ativado, os imóveis só são aprovados após um '
              'número mínimo de aprovadores votar. Configure aprovadores para '
              'disponibilidade e publicação.',
          icon: LucideIcons.vote,
          color: PsPalette.indigo(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PsSwitchTile(
                title: 'Ativar votação por aprovadores',
                subtitle:
                    'Exige quórum mínimo de votos para liberar cada imóvel.',
                value: s.approversEnabled,
                icon: LucideIcons.vote,
                color: PsPalette.indigo(context),
                onChanged: _toggleApprovers,
              ),
              if (s.approversEnabled) ...[
                const SizedBox(height: 12),
                _ApproversPanel(
                  key: const ValueKey('panel-availability'),
                  type: ApproverType.availability,
                  minApprovals: s.minApprovalsAvailability,
                  members: _members,
                  reloadToken: _reloadToken,
                  onChanged: _loadAuthorized,
                  onQuorumSaved: (updated) => setState(() {
                    _settings = _settings!.copyWith(
                      minApprovalsAvailability:
                          updated.minApprovalsAvailability,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                _ApproversPanel(
                  key: const ValueKey('panel-publication'),
                  type: ApproverType.publication,
                  minApprovals: s.minApprovalsPublication,
                  members: _members,
                  reloadToken: _reloadToken,
                  onChanged: _loadAuthorized,
                  onQuorumSaved: (updated) => setState(() {
                    _settings = _settings!.copyWith(
                      minApprovalsPublication: updated.minApprovalsPublication,
                    );
                  }),
                ),
              ],
            ],
          ),
        ),
        // ── Campos protegidos ──
        PsSection(
          title: 'Campos protegidos do imóvel',
          subtitle: 'Defina se alterar a ficha exige aprovação e quem aprova '
              'as solicitações.',
          icon: LucideIcons.lock,
          color: PsPalette.amber(context),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PropertyProtectedFieldsPage(),
                  ),
                );
                if (mounted) _refreshProtected();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    PsRoundel(
                      icon: LucideIcons.lock,
                      color: PsPalette.amber(context),
                      size: 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Abrir configuração de campos protegidos',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          Text(
                            s.protectedFieldsEnabled
                                ? 'Ativado · ${s.protectedFields.length} '
                                    'campo(s) protegido(s)'
                                : 'Desativado',
                            style: TextStyle(
                              fontSize: 12,
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 20,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // ── Autorizados ──
        if (!_authorized.isEmpty)
          PsSection(
            title: 'Usuários autorizados a aprovar',
            subtitle: 'Inclui quem tem permissão direta ou está na lista de '
                'aprovadores. Remova para revogar a permissão deste tipo '
                '(usuários master mantêm acesso implícito).',
            icon: LucideIcons.userCheck,
            color: green,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_authorized.availability.isNotEmpty)
                  _authorizedGroup(
                    context,
                    'Disponibilidade',
                    _authorized.availability,
                    ApproverType.availability,
                  ),
                if (_authorized.publication.isNotEmpty)
                  _authorizedGroup(
                    context,
                    'Publicação',
                    _authorized.publication,
                    ApproverType.publication,
                  ),
                const SizedBox(height: 4),
                const PsNote(
                  text: 'Revogar remove o usuário da lista de aprovadores e '
                      'retira as permissões diretas deste tipo.',
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _rule(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PsSwitchTile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        value: value,
        onChanged: _savingRules ? null : onChanged,
      ),
    );
  }

  Widget _authorizedGroup(
    BuildContext context,
    String label,
    List<PropertySettingsMember> users,
    ApproverType type,
  ) {
    final green = PsPalette.green(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in users)
                InputChip(
                  avatar: PsAvatar(
                    name: u.name,
                    url: u.avatar,
                    color: green,
                    size: 24,
                  ),
                  label: Text(
                    u.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  deleteIcon: const Icon(LucideIcons.x, size: 16),
                  deleteButtonTooltipMessage: 'Revogar',
                  onDeleted: () => _revoke(u, type),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aprovadores de um tipo (`ApproversPanel` do web): lista, ★ obrigatório,
/// remover, adicionar e mínimo de aprovações.
class _ApproversPanel extends StatefulWidget {
  const _ApproversPanel({
    super.key,
    required this.type,
    required this.minApprovals,
    required this.members,
    required this.reloadToken,
    required this.onChanged,
    required this.onQuorumSaved,
  });

  final ApproverType type;
  final int minApprovals;
  final List<PropertySettingsMember> members;
  final int reloadToken;
  final VoidCallback onChanged;
  final ValueChanged<PropertyApprovalSettingsFull> onQuorumSaved;

  @override
  State<_ApproversPanel> createState() => _ApproversPanelState();
}

class _ApproversPanelState extends State<_ApproversPanel> {
  final _svc = PropertySettingsService.instance;
  List<PropertyApproverConfig> _approvers = const [];
  bool _loading = true;
  bool _busy = false;
  bool _savingQuorum = false;
  late int _min = PropertyApprovalRules.clampMinApprovals(widget.minApprovals);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ApproversPanel old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken) _load();
    if (old.minApprovals != widget.minApprovals) {
      _min = PropertyApprovalRules.clampMinApprovals(widget.minApprovals);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _svc.listApprovers(widget.type);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _approvers = res.success ? (res.data ?? const []) : const [];
    });
  }

  Future<void> _afterMutation() async {
    await _load();
    widget.onChanged();
  }

  Future<void> _add() async {
    final pick = await showPsUserPicker(
      context,
      title: 'Adicionar aprovador — ${widget.type.label}',
      subtitle: 'Ao adicionar aqui, o sistema concede automaticamente as '
          'permissões de aprovar e recusar '
          '${widget.type == ApproverType.availability ? 'disponibilidade' : 'publicação'}.',
      users: widget.members,
      excludeIds: _approvers.map((a) => a.userId).toSet(),
      flagLabel: 'Aprovador obrigatório',
      flagHint: 'Mesmo com o mínimo atingido, o imóvel só é liberado se '
          'todos os obrigatórios aprovarem.',
      color: PsPalette.indigo(context),
    );
    final member = pick?.member;
    if (member == null || !mounted) return;
    setState(() => _busy = true);
    final res = await _svc.upsertApprover(
      userId: member.id,
      type: widget.type,
      isRequired: pick!.flag,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.success) {
      psSnack(
        context,
        'Aprovador adicionado. Permissões de aprovação foram concedidas ao '
        'usuário.',
        ok: true,
      );
      await _afterMutation();
    } else {
      psSnack(context, psFailMessage(res.message, 'Erro ao adicionar aprovador.'));
    }
  }

  Future<void> _toggleRequired(PropertyApproverConfig a) async {
    setState(() => _busy = true);
    final res = await _svc.upsertApprover(
      userId: a.userId,
      type: a.type,
      isRequired: !a.isRequired,
      displayOrder: a.displayOrder,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.success) {
      await _afterMutation();
    } else {
      psSnack(context, psFailMessage(res.message, 'Erro ao atualizar aprovador.'));
    }
  }

  Future<void> _remove(PropertyApproverConfig a) async {
    final ok = await psConfirm(
      context,
      title: 'Remover aprovador',
      message: 'Tem certeza que deseja remover ${a.userName} da lista de '
          'aprovadores de ${widget.type.label.toLowerCase()}?',
      confirmLabel: 'Sim, remover',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await _svc.removeApprover(a.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.success) {
      psSnack(
        context,
        'Aprovador removido e permissões de aprovação revogadas para este '
        'tipo.',
        ok: true,
      );
      await _afterMutation();
    } else {
      psSnack(context, psFailMessage(res.message, 'Erro ao remover aprovador.'));
    }
  }

  Future<void> _saveQuorum() async {
    final v = PropertyApprovalRules.clampMinApprovals(_min);
    setState(() {
      _min = v;
      _savingQuorum = true;
    });
    final res = await _svc.updateQuorumSettings(
      PropertyApprovalRules.quorumPayload(widget.type, v),
    );
    if (!mounted) return;
    setState(() => _savingQuorum = false);
    if (res.success) {
      if (res.data != null) widget.onQuorumSaved(res.data!);
      psSnack(context, 'Mínimo de aprovações salvo.', ok: true);
    } else {
      psSnack(
        context,
        psFailMessage(res.message, 'Erro ao salvar mínimo de aprovações.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = PsPalette.indigo(context);
    final amber = PsPalette.amber(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final max = _approvers.isEmpty ? 1 : _approvers.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        color: color.withValues(alpha: psDark(context) ? 0.06 : 0.025),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                widget.type == ApproverType.availability
                    ? LucideIcons.house
                    : LucideIcons.globe,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Aprovadores — ${widget.type.label}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              if (!_loading) PsBadge(label: '${_approvers.length}', color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ao adicionar, as permissões de aprovar/recusar são concedidas '
            'automaticamente; ao remover, são revogadas (master mantém acesso '
            'total). Aprovadores com ★ são obrigatórios.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: muted),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_approvers.isEmpty)
            const PsEmpty(
              text: 'Nenhum aprovador cadastrado.',
              icon: LucideIcons.users,
            )
          else
            for (final a in _approvers)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: ThemeHelpers.cardBackgroundColor(context),
                    border: Border.all(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      PsAvatar(name: a.userName, url: a.userAvatar, color: color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    a.userName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: ThemeHelpers.textColor(context),
                                    ),
                                  ),
                                ),
                                if (a.isRequired) ...[
                                  const SizedBox(width: 6),
                                  PsBadge(label: 'Obrigatório', color: amber),
                                ],
                              ],
                            ),
                            if (a.userEmail.isNotEmpty)
                              Text(
                                a.userEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: muted),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: a.isRequired
                            ? 'Remover obrigatoriedade'
                            : 'Tornar obrigatório',
                        onPressed: _busy ? null : () => _toggleRequired(a),
                        icon: Icon(
                          LucideIcons.star,
                          size: 18,
                          color: a.isRequired ? amber : muted,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover aprovador',
                        onPressed: _busy ? null : () => _remove(a),
                        icon: Icon(
                          LucideIcons.trash2,
                          size: 18,
                          color: PsPalette.red(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(LucideIcons.userPlus, size: 16),
            label: const Text('Adicionar aprovador'),
          ),
          const SizedBox(height: 12),
          Text(
            'Mínimo de aprovações para liberar',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Menos',
                onPressed: _min <= 1 ? null : () => setState(() => _min--),
                icon: const Icon(LucideIcons.minus, size: 16),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '$_min',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Mais',
                onPressed: () => setState(() => _min++),
                icon: const Icon(LucideIcons.plus, size: 16),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: _savingQuorum ? null : _saveQuorum,
                child: Text(_savingQuorum ? 'Salvando…' : 'Salvar'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Mínimo: 1. Máximo: $max (todos os aprovadores). Se definir $max, '
            'todos precisam votar para liberar o imóvel.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: muted),
          ),
          if (_approvers.isNotEmpty && _min > _approvers.length) ...[
            const SizedBox(height: 6),
            PsNote(
              icon: LucideIcons.triangleAlert,
              color: amber,
              text: 'O mínimo está acima do número de aprovadores '
                  '(${_approvers.length}).',
            ),
          ],
        ],
      ),
    );
  }
}
