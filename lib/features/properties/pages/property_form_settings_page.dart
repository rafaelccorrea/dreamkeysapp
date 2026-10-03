import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../services/property_settings_service.dart';
import '../widgets/property_settings_kit.dart';

/// Imóveis › Regras do formulário — paridade com
/// `PropertyFormSettingsPage.tsx` (`/properties/form-settings`).
///
/// Lê `GET /properties/form-settings` + `GET /properties/approval-settings`
/// + `GET /users/company-members/simple` juntos. Campos, equipes e sucessão
/// salvam juntos (`PATCH /properties/approval-settings`); o catálogo de
/// cômodos/infraestrutura salva na hora (`/property-catalog`).
class PropertyFormSettingsPage extends StatefulWidget {
  const PropertyFormSettingsPage({super.key});

  @override
  State<PropertyFormSettingsPage> createState() =>
      _PropertyFormSettingsPageState();
}

class _PropertyFormSettingsPageState extends State<PropertyFormSettingsPage> {
  final _svc = PropertySettingsService.instance;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _errorStatus = 0;
  Object? _errorDetail;

  PropertyFormRulesState? _saved;
  PropertyFormRulesState _state = const PropertyFormRulesState();
  List<PropertySettingsTeam> _teams = const [];
  List<PropertySettingsMember> _users = const [];

  /// Capítulo do filtro de campos (`null` = todos).
  int? _chapter;

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
    // As três idas partem juntas (regras do formulário, de aprovação e
    // usuários), como no web.
    final bundleF = _svc.getFormSettings();
    final approvalF = _svc.getApprovalSettings();
    final usersF = _svc.listCompanyMembers();
    final bundleRes = await bundleF;
    final approvalRes = await approvalF;
    final usersRes = await usersF;
    if (!mounted) return;
    setState(() {
      _loading = false;
      final bundle = bundleRes.data;
      if (!bundleRes.success || bundle == null) {
        _error = psFailMessage(
          bundleRes.message,
          'Não foi possível carregar as configurações.',
        );
        _errorStatus = bundleRes.statusCode;
        _errorDetail = bundleRes.error;
        return;
      }
      final approval = approvalRes.success ? approvalRes.data : null;
      _teams = bundle.editableTeams;
      _users = usersRes.success
          ? (usersRes.data ?? const <PropertySettingsMember>[])
          : const <PropertySettingsMember>[];
      final s = PropertyFormRulesState.fromServer(
        bundle: bundle,
        approval: approval,
      );
      _saved = s;
      _state = s;
    });
  }

  int get _changes => PropertyFormRules.countChanges(_saved, _state);

  String? get _blockReason =>
      PropertyFormRules.blockReason(_saved, _state, _teams.length);

  Future<void> _save() async {
    final reason = _blockReason;
    if (reason != null) {
      if (_changes > 0) psSnack(context, '$reason.');
      return;
    }
    setState(() => _saving = true);
    final res = await _svc.updateApprovalSettings(
      PropertyFormRules.buildPayload(_state),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      psSnack(context, 'Regras do formulário salvas.', ok: true);
      await _load();
    } else {
      psSnack(context, psFailMessage(res.message, 'Erro ao salvar.'));
    }
  }

  void _discard() {
    final s = _saved;
    if (s != null) setState(() => _state = s);
  }

  void _toggleField(String key) {
    final list = List<String>.from(_state.extras);
    list.contains(key) ? list.remove(key) : list.add(key);
    setState(() => _state = _state.copyWith(extras: list));
  }

  void _setRestrict(bool on) {
    setState(() {
      _state = _state.copyWith(
        restrictTeams: on,
        allowedTeamIds: on
            ? (_state.allowedTeamIds.isNotEmpty
                ? _state.allowedTeamIds
                : _teams.map((t) => t.id).toList())
            : const <String>[],
      );
    });
  }

  void _toggleTeam(String id) {
    final list = List<String>.from(_state.allowedTeamIds);
    list.contains(id) ? list.remove(id) : list.add(id);
    setState(() => _state = _state.copyWith(allowedTeamIds: list));
  }

  Future<bool> _confirmLeave() async {
    if (_changes == 0) return true;
    return psConfirm(
      context,
      title: 'Descartar alterações?',
      message: 'Há $_changes alteração(ões) não salva(s) nas regras do '
          'formulário. Sair sem salvar?',
      confirmLabel: 'Sair sem salvar',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = PsPalette.indigo(context);
    final changes = _loading ? 0 : _changes;
    return PopScope(
      canPop: changes == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave() && mounted) {
          setState(() => _state = _saved ?? _state);
          nav.pop();
        }
      },
      child: AppScaffold(
        title: 'Regras do formulário',
        showBottomNavigation: false,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
        ],
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _content(context),
              ),
            ),
            if (changes > 0)
              PsSaveBar(
                changes: changes,
                saving: _saving,
                blockReason:
                    _blockReason == 'Nada a salvar' ? null : _blockReason,
                onSave: _save,
                onDiscard: _discard,
                color: color,
                saveLabel: 'Salvar regras',
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_loading && _saved == null) {
      return ListView(
        children: const [PsSkeleton(blocks: [150, 260, 180, 220])],
      );
    }
    if (_error != null && _saved == null) {
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _hero(context),
        _fieldsSection(context),
        _teamsSection(context),
        _successionSection(context),
        const _CatalogSection(),
      ],
    );
  }

  // ─── Cabeçalho ──────────────────────────────────────────────────────────

  Widget _hero(BuildContext context) {
    final reading = PropertyFormRules.reading(null, _state.extras);
    final inPicker = PropertyFormRules.teamsInPicker(_state, _teams.length);
    final successor = _userById(_state.successorId);
    final color = PsPalette.indigo(context);
    return PsHero(
      eyebrow: 'Imóveis · Cadastro',
      title: 'Regras do formulário',
      icon: LucideIcons.listChecks,
      color: color,
      subtitle: 'O que o cadastro de imóvel exige além do mínimo do sistema, '
          'quais equipes aparecem no vínculo e o que acontece com os imóveis '
          'quando um colaborador é desativado. Campos, equipes e sucessão '
          'salvam juntos; o catálogo de cômodos salva na hora.',
      chips: [
        PsChip(
          value: '${reading.required}',
          label: 'obrigatórios · ${reading.system} do sistema + '
              '${reading.extras} ${reading.extras == 1 ? 'extra' : 'extras'}',
          color: color,
          icon: LucideIcons.asterisk,
        ),
        PsChip(
          value: '$inPicker/${_teams.length}',
          label: 'equipes no seletor',
          color: PsPalette.green(context),
          icon: LucideIcons.users,
        ),
        PsChip(
          label: 'Quem sai → ${PropertyFormRules.successionLabel(
            _state,
            successorName: successor?.name,
          )}',
          color: PropertyFormRules.successionInvalid(_state)
              ? PsPalette.amber(context)
              : PsPalette.teal(context),
          icon: LucideIcons.arrowLeftRight,
        ),
      ],
    );
  }

  PropertySettingsMember? _userById(String? id) {
    if ((id ?? '').isEmpty) return null;
    for (final u in _users) {
      if (u.id == id) return u;
    }
    return null;
  }

  // ─── Campos obrigatórios ────────────────────────────────────────────────

  Widget _fieldsSection(BuildContext context) {
    final color = PsPalette.indigo(context);
    final green = PsPalette.green(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final all = PropertyFormRules.reading(null, _state.extras);
    final fields = PropertyFormRules.fieldsOf(_chapter);
    return PsSection(
      title: 'Campos obrigatórios',
      subtitle: 'O sistema já exige os travados; marque os extras por '
          'política da imobiliária.',
      icon: LucideIcons.asterisk,
      color: color,
      trailing: _state.extras.isEmpty
          ? null
          : TextButton.icon(
              onPressed: () => setState(
                () => _state = _state.copyWith(extras: const <String>[]),
              ),
              icon: const Icon(LucideIcons.listX, size: 16),
              label: const Text('Limpar'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProportionBar(reading: all, system: muted, extra: green),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chapterChip(context, null, 'Todos', all),
                for (final c in PropertyFormRules.chapters)
                  _chapterChip(
                    context,
                    c.index,
                    c.short,
                    PropertyFormRules.reading(c.index, _state.extras),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in fields) _fieldTile(context, f),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chapterChip(
    BuildContext context,
    int? index,
    String label,
    PropertyFormReading r,
  ) {
    final selected = _chapter == index;
    final color = PsPalette.indigo(context);
    final dark = psDark(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        showCheckmark: false,
        selected: selected,
        onSelected: (_) => setState(() => _chapter = index),
        label: Text('$label  ${r.required}/${r.total}'),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
          color: selected ? color : ThemeHelpers.textColor(context),
        ),
        selectedColor: color.withValues(alpha: dark ? 0.22 : 0.12),
        side: BorderSide(
          color: selected
              ? color.withValues(alpha: 0.5)
              : ThemeHelpers.borderColor(context),
        ),
      ),
    );
  }

  Widget _fieldTile(BuildContext context, PropertyFormFieldOption f) {
    final dark = psDark(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final green = PsPalette.green(context);
    final isExtra = !f.isSystem && _state.extras.contains(f.key);
    final tone = f.isSystem ? muted : (isExtra ? green : muted);
    final width = (MediaQuery.of(context).size.width - 32 - 28 - 8) / 2;
    return SizedBox(
      width: width.clamp(130.0, 400.0),
      child: Material(
        color: isExtra
            ? green.withValues(alpha: dark ? 0.14 : 0.07)
            : (f.isSystem
                ? ThemeHelpers.borderColor(context).withValues(alpha: 0.18)
                : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: f.isSystem ? null : () => _toggleField(f.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isExtra
                    ? green.withValues(alpha: 0.5)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  f.isSystem
                      ? LucideIcons.lock
                      : (isExtra ? LucideIcons.squareCheck : LucideIcons.square),
                  size: 16,
                  color: tone,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      Text(
                        f.isSystem
                            ? 'sistema'
                            : (isExtra ? 'obrigatório' : 'opcional'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: tone,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Equipes ────────────────────────────────────────────────────────────

  Widget _teamsSection(BuildContext context) {
    final color = PsPalette.green(context);
    final amber = PsPalette.amber(context);
    final noTeam = PropertyFormRules.noTeamSelected(_state, _teams.length);
    final inPicker = PropertyFormRules.teamsInPicker(_state, _teams.length);
    return PsSection(
      title: 'Equipes no seletor',
      subtitle: 'Quem cadastra pode vincular a qualquer equipe permitida, '
          'mesmo sem fazer parte dela.',
      icon: LucideIcons.users,
      color: color,
      trailing: _teams.isEmpty
          ? null
          : PsBadge(
              label: '$inPicker/${_teams.length}',
              color: noTeam ? amber : color,
            ),
      child: _teams.isEmpty
          ? const PsEmpty(
              icon: LucideIcons.users,
              text: 'Nenhuma equipe ativa na empresa. Cadastre equipes em '
                  'Colaboradores para escolher aqui quais aparecem.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text('Todas (${_teams.length})'),
                      icon: const Icon(LucideIcons.layers, size: 16),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(
                        'Só as marcadas'
                        '${_state.restrictTeams ? ' (${_state.allowedTeamIds.length})' : ''}',
                      ),
                      icon: const Icon(LucideIcons.listFilter, size: 16),
                    ),
                  ],
                  selected: {_state.restrictTeams},
                  onSelectionChanged: (s) => _setRestrict(s.first),
                ),
                const SizedBox(height: 12),
                if (_state.restrictTeams) ...[
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _state.allowedTeamIds.length == _teams.length
                            ? null
                            : () => setState(
                                  () => _state = _state.copyWith(
                                    allowedTeamIds:
                                        _teams.map((t) => t.id).toList(),
                                  ),
                                ),
                        icon: const Icon(LucideIcons.checkCheck, size: 16),
                        label: const Text('Marcar todas'),
                      ),
                      TextButton.icon(
                        onPressed: _state.allowedTeamIds.isEmpty
                            ? null
                            : () => setState(
                                  () => _state = _state.copyWith(
                                    allowedTeamIds: const <String>[],
                                  ),
                                ),
                        icon: const Icon(LucideIcons.listX, size: 16),
                        label: const Text('Limpar'),
                      ),
                    ],
                  ),
                  for (final t in _teams) _teamTile(context, t),
                ] else
                  _allTeamsStrip(context),
                if (noTeam) ...[
                  const SizedBox(height: 10),
                  PsNote(
                    icon: LucideIcons.triangleAlert,
                    color: amber,
                    text: 'Com "só as marcadas" ligado, ao menos uma equipe '
                        'precisa aparecer — ou volte para todas.',
                  ),
                ],
              ],
            ),
    );
  }

  Widget _teamTile(BuildContext context, PropertySettingsTeam t) {
    final on = _state.allowedTeamIds.contains(t.id);
    final green = PsPalette.green(context);
    final dark = psDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? green.withValues(alpha: dark ? 0.12 : 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _toggleTeam(t.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on
                    ? green.withValues(alpha: 0.45)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  on ? LucideIcons.squareCheck : LucideIcons.square,
                  size: 18,
                  color: on ? green : ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: PsPalette.hex(t.color),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
                Text(
                  on ? 'APARECE' : 'OCULTA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: on ? green : ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _allTeamsStrip(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Modo completo: ',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              TextSpan(
                text: 'as ${_teams.length} equipes ativas aparecem para quem '
                    'cadastra ou edita imóveis.',
              ),
            ],
          ),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _teams)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: PsPalette.hex(t.color).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: PsPalette.hex(t.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      t.name,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─── Sucessão ───────────────────────────────────────────────────────────

  Widget _successionSection(BuildContext context) {
    final color = PsPalette.teal(context);
    final amber = PsPalette.amber(context);
    final missing = PropertyFormRules.successionInvalid(_state);
    final isUser = _state.successionTarget == SuccessionTarget.user;
    final successor = _userById(_state.successorId);
    return PsSection(
      title: 'Desativação de colaborador',
      subtitle: 'A desativação em Colaboradores aplica estas regras '
          'automaticamente.',
      icon: LucideIcons.userX,
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _station(
            context,
            icon: LucideIcons.userX,
            name: 'Colaborador desativado',
            reading: 'em Colaboradores',
            tone: color,
          ),
          _arrow(context),
          _station(
            context,
            icon: LucideIcons.arrowLeftRight,
            name: 'Imóveis dele vão para',
            reading: missing
                ? 'falta escolher o sucessor'
                : PropertyFormRules.successionLabel(
                    _state,
                    successorName: successor?.name,
                  ),
            tone: missing ? amber : color,
          ),
          _arrow(context),
          _station(
            context,
            icon: LucideIcons.handshake,
            name: 'Se era captador',
            reading: PropertyFormRules.captorLabel(_state.captorAction),
            tone: color,
          ),
          const SizedBox(height: 14),
          _label(context, 'Destino dos imóveis'),
          const SizedBox(height: 6),
          _optionGroup<SuccessionTarget>(
            context,
            value: _state.successionTarget,
            color: color,
            options: const [
              (
                SuccessionTarget.companyOwner,
                'Dono da empresa',
                'com contingência opcional',
              ),
              (SuccessionTarget.user, 'Sempre um usuário específico', null),
            ],
            onChanged: (v) => setState(
              () => _state = _state.copyWith(successionTarget: v),
            ),
          ),
          const SizedBox(height: 14),
          _label(
            context,
            isUser ? 'Sucessor' : 'Contingência',
            hint: isUser ? 'obrigatório' : 'opcional',
          ),
          const SizedBox(height: 6),
          _successorButton(context, successor, missing),
          const SizedBox(height: 4),
          Text(
            isUser
                ? 'Quem recebe os imóveis de quem for desativado.'
                : 'Assume se o dono estiver inativo ou for o próprio '
                    'desativado.',
            style: TextStyle(
              fontSize: 11.5,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 14),
          _label(context, 'Captação'),
          const SizedBox(height: 6),
          _optionGroup<CaptorAction>(
            context,
            value: _state.captorAction,
            color: color,
            options: const [
              (
                CaptorAction.remove,
                'Sai da captação',
                'e o captador principal é atualizado, se for ele',
              ),
              (
                CaptorAction.keep,
                'Segue como captador',
                'os vínculos ficam como estão',
              ),
            ],
            onChanged: (v) =>
                setState(() => _state = _state.copyWith(captorAction: v)),
          ),
        ],
      ),
    );
  }

  Widget _station(
    BuildContext context, {
    required IconData icon,
    required String name,
    required String reading,
    required Color tone,
  }) {
    return Row(
      children: [
        PsRoundel(icon: icon, color: tone, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              Text(
                reading,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: tone == PsPalette.amber(context)
                      ? tone
                      : ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _arrow(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 9, top: 2, bottom: 2),
        child: Icon(
          LucideIcons.arrowDown,
          size: 16,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      );

  Widget _label(BuildContext context, String text, {String? hint}) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Text(
            hint.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _optionGroup<T>(
    BuildContext context, {
    required T value,
    required Color color,
    required List<(T, String, String?)> options,
    required ValueChanged<T> onChanged,
  }) {
    final dark = psDark(context);
    return Column(
      children: [
        for (final (v, label, hint) in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: v == value
                  ? color.withValues(alpha: dark ? 0.14 : 0.07)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(v),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: v == value
                          ? color.withValues(alpha: 0.5)
                          : ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        v == value
                            ? LucideIcons.circleDot
                            : LucideIcons.circle,
                        size: 18,
                        color: v == value
                            ? color
                            : ThemeHelpers.textSecondaryColor(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                            if (hint != null)
                              Text(
                                hint,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color:
                                      ThemeHelpers.textSecondaryColor(context),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _successorButton(
    BuildContext context,
    PropertySettingsMember? successor,
    bool missing,
  ) {
    final color = PsPalette.teal(context);
    final amber = PsPalette.amber(context);
    final isUser = _state.successionTarget == SuccessionTarget.user;
    final hasId = (_state.successorId ?? '').isNotEmpty;
    final label = successor?.name ??
        (hasId
            ? 'Usuário não está mais ativo'
            : (isUser ? 'Escolha o usuário' : 'Ninguém — só o dono'));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final pick = await showPsUserPicker(
            context,
            title: isUser ? 'Sucessor dos imóveis' : 'Contingência',
            subtitle: isUser
                ? 'Quem recebe os imóveis de quem for desativado.'
                : 'Assume se o dono estiver inativo ou for o próprio '
                    'desativado.',
            users: _users,
            selectedId: _state.successorId,
            noneLabel: isUser ? null : 'Ninguém — só o dono da empresa',
            emptyText: 'Nenhum usuário ativo',
            color: color,
          );
          if (pick == null || !mounted) return;
          setState(() {
            _state = pick.member == null
                ? _state.copyWith(clearSuccessor: true)
                : _state.copyWith(successorId: pick.member!.id);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: missing
                  ? amber
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.9),
              width: missing ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              successor == null
                  ? PsRoundel(
                      icon: LucideIcons.user,
                      color: missing ? amber : color,
                      size: 32,
                    )
                  : PsAvatar(
                      name: successor.name,
                      url: successor.avatar,
                      color: color,
                      size: 32,
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: missing ? amber : ThemeHelpers.textColor(context),
                      ),
                    ),
                    if ((successor?.email ?? '').isNotEmpty)
                      Text(
                        successor!.email,
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
              Icon(
                LucideIcons.chevronsUpDown,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Régua da exigência: sistema · extras · livres.
class _ProportionBar extends StatelessWidget {
  const _ProportionBar({
    required this.reading,
    required this.system,
    required this.extra,
  });

  final PropertyFormReading reading;
  final Color system;
  final Color extra;

  @override
  Widget build(BuildContext context) {
    final free = ThemeHelpers.borderColor(context).withValues(alpha: 0.6);
    final total = reading.total == 0 ? 1 : reading.total;
    Widget seg(int n, Color c) => n <= 0
        ? const SizedBox.shrink()
        : Expanded(flex: n, child: Container(color: c));
    Widget legend(Color c, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                seg(reading.system, system.withValues(alpha: 0.75)),
                seg(reading.extras, extra),
                seg(total - reading.system - reading.extras, free),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            legend(system.withValues(alpha: 0.75),
                '${reading.system} do sistema'),
            legend(extra, '${reading.extras} extras'),
            legend(free, '${reading.free} livres'),
          ],
        ),
      ],
    );
  }
}

/// Catálogo extra (cômodos e infraestrutura) — salva item a item, na hora
/// (`PropertyCatalogSettingsSection` do web).
class _CatalogSection extends StatefulWidget {
  const _CatalogSection();

  @override
  State<_CatalogSection> createState() => _CatalogSectionState();
}

class _CatalogSectionState extends State<_CatalogSection> {
  final _svc = PropertySettingsService.instance;
  final _drafts = {
    CatalogKind.room: TextEditingController(),
    CatalogKind.infrastructure: TextEditingController(),
  };
  List<PropertyCatalogEntry> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in _drafts.values) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _drafts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _svc.listCatalog();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success) {
        _items = res.data ?? const [];
        _error = null;
      } else {
        _error = 'Não foi possível carregar os cômodos e a infraestrutura.';
      }
    });
  }

  Future<void> _add(CatalogKind kind) async {
    final name = _drafts[kind]!.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    final res = await _svc.createCatalogItem(kind, name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.success) {
      _drafts[kind]!.clear();
      if (res.data != null) {
        setState(() => _items = [..._items, res.data!]);
      } else {
        await _load();
      }
    } else {
      psSnack(context, psFailMessage(res.message, 'Não foi possível adicionar.'));
    }
  }

  Future<void> _rename(PropertyCatalogEntry item) async {
    final ctrl = TextEditingController(text: item.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Renomear'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(hintText: 'Novo nome'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final t = name?.trim() ?? '';
    if (t.isEmpty || t == item.name || !mounted) return;
    setState(() => _busy = true);
    final res = await _svc.renameCatalogItem(item.id, t);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.success) {
      final updated = res.data ??
          PropertyCatalogEntry(
            id: item.id,
            kind: item.kind,
            name: t,
            sortOrder: item.sortOrder,
          );
      setState(() {
        _items = [for (final i in _items) i.id == item.id ? updated : i];
      });
    } else {
      psSnack(context, psFailMessage(res.message, 'Não foi possível renomear.'));
    }
  }

  Future<void> _remove(PropertyCatalogEntry item) async {
    if (_busy) return;
    final ok = await psConfirm(
      context,
      title: 'Remover "${item.name}"?',
      message: 'O item some do cadastro de imóvel para toda a empresa.',
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await _svc.deleteCatalogItem(item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.success) {
      setState(() => _items = _items.where((i) => i.id != item.id).toList());
    } else {
      psSnack(context, psFailMessage(res.message, 'Não foi possível remover.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _column(
          context,
          kind: CatalogKind.room,
          title: 'Cômodos extras',
          subtitle: 'Ganham campo de quantidade, junto de quartos e banheiros.',
          becomes: 'Um cômodo extra vira um campo numérico no cadastro — '
              '"Escritório: 1".',
          hint: 'Ex.: Escritório, Lavabo, Closet',
          icon: LucideIcons.doorOpen,
          color: PsPalette.purple(context),
        ),
        _column(
          context,
          kind: CatalogKind.infrastructure,
          title: 'Infraestrutura extra',
          subtitle: 'Viram opções para marcar, junto das características.',
          becomes: 'Um item de infraestrutura vira uma opção de marcar — '
              '"Gerador ✓".',
          hint: 'Ex.: Gerador, Poço artesiano, Energia solar',
          icon: LucideIcons.zap,
          color: PsPalette.amber(context),
        ),
      ],
    );
  }

  Widget _column(
    BuildContext context, {
    required CatalogKind kind,
    required String title,
    required String subtitle,
    required String becomes,
    required String hint,
    required IconData icon,
    required Color color,
  }) {
    final list = _items.where((i) => i.kind == kind).toList();
    final ctrl = _drafts[kind]!;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return PsSection(
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      trailing: PsBadge(
        label: _loading
            ? '…'
            : '${list.length} ${list.length == 1 ? 'item' : 'itens'}',
        color: color,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  maxLength: 80,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(kind),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: hint,
                    prefixIcon: Icon(icon, size: 18, color: color),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: color),
                tooltip: 'Adicionar',
                onPressed:
                    _busy || ctrl.text.trim().isEmpty ? null : () => _add(kind),
                icon: const Icon(LucideIcons.plus, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Salvo na hora — não passa pelo "Salvar regras".',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            PsNote(
              text: _error!,
              icon: LucideIcons.triangleAlert,
              color: PsPalette.red(context),
            )
          else if (list.isEmpty)
            PsEmpty(text: 'Nenhum item extra ainda. $becomes', icon: icon)
          else
            for (var i = 0; i < list.length; i++)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        list[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Renomear',
                      onPressed: _busy ? null : () => _rename(list[i]),
                      icon: Icon(LucideIcons.pencil, size: 17, color: muted),
                    ),
                    IconButton(
                      tooltip: 'Remover',
                      onPressed: _busy ? null : () => _remove(list[i]),
                      icon: Icon(
                        LucideIcons.x,
                        size: 18,
                        color: PsPalette.red(context),
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
