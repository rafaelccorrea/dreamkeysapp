import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../services/property_settings_service.dart';
import '../widgets/property_settings_kit.dart';

/// Imóveis › Campos protegidos — paridade com
/// `PropertyProtectedFieldsConfigPage.tsx` + `ProtectedFieldsSettingsSection`
/// (`/properties/protected-fields-config`).
///
/// O interruptor do fluxo salva com "Salvar configuração"
/// (`PATCH /properties/approval-settings` com `protectedFieldsEnabled` +
/// `protectedFields` preservado). Os aprovadores de edição (`edit_request`,
/// sem quórum) entram e saem na hora.
class PropertyProtectedFieldsPage extends StatefulWidget {
  const PropertyProtectedFieldsPage({super.key});

  @override
  State<PropertyProtectedFieldsPage> createState() =>
      _PropertyProtectedFieldsPageState();
}

class _PropertyProtectedFieldsPageState
    extends State<PropertyProtectedFieldsPage> {
  final _svc = PropertySettingsService.instance;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _errorStatus = 0;
  Object? _errorDetail;

  PropertyApprovalSettingsFull? _settings;
  bool _savedEnabled = false;
  bool _enabled = false;

  List<PropertyApproverConfig> _approvers = const [];
  bool _loadingApprovers = true;
  List<PropertySettingsMember> _members = const [];
  bool _adding = false;
  String? _removingId;

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
    _loadApprovers();
    final res = await settingsF;
    final members = await membersF;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (members.success) _members = members.data ?? const [];
      if (res.success && res.data != null) {
        _settings = res.data;
        _savedEnabled = res.data!.protectedFieldsEnabled;
        _enabled = _savedEnabled;
      } else {
        _error = psFailMessage(
          res.message,
          'Não foi possível carregar a configuração.',
        );
        _errorStatus = res.statusCode;
        _errorDetail = res.error;
      }
    });
  }

  Future<void> _loadApprovers() async {
    setState(() => _loadingApprovers = true);
    final res = await _svc.listApprovers(ApproverType.editRequest);
    if (!mounted) return;
    setState(() {
      _loadingApprovers = false;
      _approvers = res.success ? (res.data ?? const []) : const [];
    });
  }

  Future<void> _save() async {
    final s = _settings;
    if (s == null) return;
    setState(() => _saving = true);
    final res = await _svc.updateApprovalSettings(
      PropertyApprovalRules.protectedFieldsPayload(
        enabled: _enabled,
        fields: s.protectedFields,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      setState(() {
        _savedEnabled = _enabled;
        _settings = s.copyWith(protectedFieldsEnabled: _enabled);
      });
      psSnack(context, 'Configuração de aprovação de edição salva.', ok: true);
      if (_enabled && _approvers.isEmpty) {
        psSnack(
          context,
          'Cadastre ao menos um aprovador para revisar as solicitações.',
          warn: true,
        );
      }
    } else {
      psSnack(
        context,
        psFailMessage(
          res.message,
          'Erro ao salvar configuração de campos protegidos.',
        ),
      );
    }
  }

  Future<void> _addApprover() async {
    final pick = await showPsUserPicker(
      context,
      title: 'Adicionar aprovador de edição',
      subtitle: 'Ele passa a editar campos protegidos sem aprovação e a '
          'decidir as solicitações (sem quórum).',
      users: _members,
      excludeIds: _approvers.map((a) => a.userId).toSet(),
      color: PsPalette.amber(context),
    );
    final member = pick?.member;
    if (member == null || !mounted) return;
    setState(() => _adding = true);
    final res = await _svc.upsertApprover(
      userId: member.id,
      type: ApproverType.editRequest,
    );
    if (!mounted) return;
    setState(() => _adding = false);
    if (res.success) {
      psSnack(
        context,
        'Aprovador adicionado. Ele pode editar campos protegidos direto e '
        'aprovar solicitações.',
        ok: true,
      );
      await _loadApprovers();
    } else {
      psSnack(context, psFailMessage(res.message, 'Erro ao adicionar aprovador.'));
    }
  }

  Future<void> _removeApprover(PropertyApproverConfig a) async {
    final ok = await psConfirm(
      context,
      title: 'Remover aprovador',
      message: 'Remover ${a.userName}? A permissão de editar campos '
          'protegidos sem aprovação é revogada.',
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _removingId = a.id);
    final res = await _svc.revokeUserApprovalPermission(
      userId: a.userId,
      type: ApproverType.editRequest,
    );
    if (!mounted) return;
    setState(() => _removingId = null);
    if (res.success) {
      psSnack(context, 'Aprovador removido.', ok: true);
      await _loadApprovers();
    } else {
      psSnack(context, psFailMessage(res.message, 'Erro ao remover aprovador.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _settings != null && _enabled != _savedEnabled;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final ok = await psConfirm(
          context,
          title: 'Descartar alteração?',
          message: 'O fluxo foi ${_enabled ? 'ativado' : 'desativado'} mas '
              'não foi salvo. Sair sem salvar?',
          confirmLabel: 'Sair sem salvar',
          destructive: true,
        );
        if (ok && mounted) {
          setState(() => _enabled = _savedEnabled);
          nav.pop();
        }
      },
      child: AppScaffold(
        title: 'Campos protegidos',
        showBottomNavigation: false,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
        ],
        body: RefreshIndicator(onRefresh: _load, child: _content(context)),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final s = _settings;
    if (_loading && s == null) {
      return ListView(children: const [PsSkeleton(blocks: [170, 120, 260])]);
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
    final amber = PsPalette.amber(context);
    final green = PsPalette.green(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    const total = PropertyApprovalRules.protectedFieldOptionsCount;
    final count = s.protectedFields.length;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PsHero(
          eyebrow: 'Controle de alterações',
          title: 'Campos protegidos do imóvel',
          icon: LucideIcons.lock,
          color: amber,
          subtitle: 'Quando um usuário sem permissão altera a ficha, a mudança '
              'vira uma solicitação de alteração para os aprovadores '
              'configurados — o resto do fluxo segue normal.',
          chips: [
            PsChip(
              label: _savedEnabled ? 'Fluxo ativo' : 'Fluxo desativado',
              color: green,
              on: _savedEnabled,
              icon: LucideIcons.shieldCheck,
            ),
            PsChip(
              value: '$count',
              label: 'de $total campos na lista',
              color: amber,
              icon: LucideIcons.listChecks,
            ),
            PsChip(
              value: _loadingApprovers ? '…' : '${_approvers.length}',
              label: 'aprovador(es)',
              color: PsPalette.indigo(context),
              icon: LucideIcons.users,
            ),
          ],
          footer: const PsNote(
            icon: LucideIcons.info,
            text: 'Gestores, administradores e os aprovadores continuam '
                'editando todos os campos direto, sem gerar solicitação.',
          ),
        ),
        PsSection(
          title: 'Exigir aprovação para editar o imóvel',
          subtitle: 'Com o fluxo ativo, QUALQUER alteração de dados da ficha '
              'por quem não é aprovador vira uma solicitação — só é aplicada '
              'após aprovação. Não importa o campo.',
          icon: LucideIcons.lock,
          color: amber,
          trailing: _enabled != _savedEnabled
              ? PsBadge(label: 'não salvo', color: amber)
              : null,
          child: PsSwitchTile(
            title: _enabled ? 'Fluxo ativado' : 'Fluxo desativado',
            subtitle: _enabled
                ? 'Toda alteração de dados da ficha por quem não é aprovador '
                    'vira solicitação e aguarda aprovação.'
                : 'Todos os usuários com acesso ao imóvel salvam qualquer '
                    'campo direto.',
            value: _enabled,
            color: amber,
            icon: _enabled ? LucideIcons.lock : LucideIcons.lockOpen,
            onChanged: _saving ? null : (v) => setState(() => _enabled = v),
          ),
        ),
        if (_enabled) ...[
          PsSection(
            title: 'O que passa por aprovação',
            subtitle: 'Com o fluxo ativo, todos os dados da ficha exigem '
                'aprovação — não há seleção campo a campo.',
            icon: LucideIcons.listChecks,
            color: amber,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _scope(
                  context,
                  color: amber,
                  title: 'Passa por aprovação (todos os dados da ficha)',
                  text: 'Responsável, captador, valores (venda, aluguel, '
                      'mínimos, condomínio, IPTU), proprietário, endereço, '
                      'características (quartos, banheiros, áreas, vagas…), '
                      'título, descrição, tipo, finalidade, equipe, '
                      'condomínio/empreendimento e demais campos da ficha.',
                ),
                const SizedBox(height: 12),
                _scope(
                  context,
                  color: muted,
                  title: 'Segue no fluxo próprio (não vira solicitação de '
                      'edição)',
                  text: 'Status/disponibilidade e publicação no site (filas '
                      'de aprovação já existentes), marcar como '
                      'vendido/alugado, ativar/desativar e imagens/vídeo.',
                ),
              ],
            ),
          ),
          PsSection(
            title: 'Aprovadores',
            subtitle: 'Quem revisa as solicitações e pode editar campos '
                'protegidos sem aprovação.',
            icon: LucideIcons.users,
            color: PsPalette.indigo(context),
            trailing: !_loadingApprovers && _approvers.isNotEmpty
                ? PsBadge(
                    label: '${_approvers.length}',
                    color: PsPalette.indigo(context),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadingApprovers)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_approvers.isEmpty)
                  const PsEmpty(
                    icon: LucideIcons.users,
                    text: 'Nenhum aprovador cadastrado. Sem aprovadores, as '
                        'solicitações só podem ser revisadas por gestores e '
                        'administradores.',
                  )
                else
                  for (final a in _approvers) _approverRow(context, a),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _adding ? null : _addApprover,
                  icon: _adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.userPlus, size: 16),
                  label: Text(_adding ? 'Adicionando…' : 'Adicionar aprovador'),
                ),
                const SizedBox(height: 10),
                const PsNote(
                  text: 'Qualquer aprovador decide sozinho (sem quórum). Ao '
                      'adicionar, o usuário passa a editar campos protegidos '
                      'sem aprovação; ao remover, essa permissão é revogada.',
                ),
              ],
            ),
          ),
        ],
        // ── Ação ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _enabled
                    ? 'Toda edição de dados passa por aprovação · '
                        '${_approvers.length} aprovador(es)'
                    : 'Fluxo desativado — nenhum campo exige aprovação.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: PsPalette.primary(context),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.save, size: 18),
                label: Text(_saving ? 'Salvando…' : 'Salvar configuração'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scope(
    BuildContext context, {
    required Color color,
    required String title,
    required String text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }

  Widget _approverRow(BuildContext context, PropertyApproverConfig a) {
    final color = PsPalette.indigo(context);
    final removing = _removingId == a.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
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
                  Text(
                    a.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (a.userEmail.isNotEmpty)
                    Text(
                      a.userEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remover aprovador (revoga o bypass de campos protegidos)',
              onPressed: removing ? null : () => _removeApprover(a),
              icon: removing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      LucideIcons.trash2,
                      size: 18,
                      color: PsPalette.red(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
