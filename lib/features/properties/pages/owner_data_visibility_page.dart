import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../services/property_settings_service.dart';
import '../widgets/property_settings_kit.dart';

/// Imóveis › Visibilidade de dados do proprietário — paridade com
/// `OwnerDataVisibilityConfigPage.tsx` (`/properties/owner-data-visibility`).
///
/// Ver a lista: admin/master OU `property:view_protected_owner_data`.
/// Habilitar/remover: só admin/master (o back recusa os demais com 403).
/// Lê `GET /protected-owner-data/users`, `GET /protected-owner-data/scope`
/// (aditivo — sem ele a tela vive igual) e, para quem gerencia,
/// `GET /users/company-members/simple`.
class OwnerDataVisibilityPage extends StatefulWidget {
  const OwnerDataVisibilityPage({super.key});

  @override
  State<OwnerDataVisibilityPage> createState() =>
      _OwnerDataVisibilityPageState();
}

class _OwnerDataVisibilityPageState extends State<OwnerDataVisibilityPage> {
  final _svc = PropertySettingsService.instance;

  late final bool _canManage =
      PropertySettingsGates.canManageOwnerData(ModuleAccessService.instance.userRole);

  bool _loading = true;
  String? _error;
  int _errorStatus = 0;
  Object? _errorDetail;

  List<PropertySettingsMember> _enabled = const [];
  List<PropertySettingsMember> _members = const [];
  OwnerDataScope? _scope;

  OwnerDataRole? _role;
  String _listQuery = '';
  String _panelQuery = '';
  String? _addingId;
  String? _removingId;
  bool _loadedOnce = false;

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
    final enabledF = _svc.listOwnerDataUsers();
    final scopeF = _svc.getOwnerDataScope();
    final membersF = _canManage ? _svc.listCompanyMembers() : null;
    final enabled = await enabledF;
    final scope = await scopeF;
    final members = membersF == null ? null : await membersF;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (enabled.success) {
        _enabled = enabled.data ?? const [];
        _loadedOnce = true;
      } else {
        _error = psFailMessage(
          enabled.message,
          'Não foi possível carregar a configuração.',
        );
        _errorStatus = enabled.statusCode;
        _errorDetail = enabled.error;
      }
      _scope = scope.success ? scope.data : null;
      if (members != null && members.success) {
        _members = members.data ?? const [];
      }
    });
  }

  Future<void> _reloadEnabled() async {
    final res = await _svc.listOwnerDataUsers();
    if (!mounted || !res.success) return;
    setState(() => _enabled = res.data ?? const []);
  }

  Future<void> _enable(PropertySettingsMember u) async {
    setState(() => _addingId = u.id);
    final res = await _svc.enableOwnerDataUser(u.id);
    if (!mounted) return;
    setState(() => _addingId = null);
    if (res.success) {
      psSnack(context, '${u.name} agora vê os dados do proprietário.', ok: true);
      await _reloadEnabled();
    } else {
      psSnack(context, psFailMessage(res.message, 'Não deu para habilitar.'));
    }
  }

  Future<void> _disable(PropertySettingsMember u) async {
    final ok = await psConfirm(
      context,
      title: 'Remover ${u.name}?',
      message: OwnerDataRules.seesByRole(u.role)
          ? '${u.name} sai da lista, mas continua vendo pelo papel '
              '(${OwnerDataRules.roleLabel(OwnerDataRules.roleOf(u.role))}).'
          : '${u.name} deixa de ver os dados do proprietário nos imóveis '
              'restritos.',
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _removingId = u.id);
    final res = await _svc.disableOwnerDataUser(u.id);
    if (!mounted) return;
    setState(() => _removingId = null);
    if (res.success) {
      psSnack(
        context,
        '${u.name} deixou de ver os dados do proprietário.',
        ok: true,
      );
      await _reloadEnabled();
    } else {
      psSnack(context, psFailMessage(res.message, 'Não deu para remover.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Dados do proprietário',
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
    if (_loading && !_loadedOnce) {
      return ListView(children: const [PsSkeleton(blocks: [170, 90, 280])]);
    }
    if (_error != null && !_loadedOnce) {
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
    final teal = PsPalette.teal(context);
    final red = PsPalette.red(context);
    final scope = _scope;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PsHero(
          eyebrow: 'Imóveis · Privacidade do proprietário',
          title: 'Visibilidade de dados do proprietário',
          icon: LucideIcons.eyeOff,
          color: teal,
          subtitle: 'Nos imóveis com proprietário restrito'
              '${(scope?.responsibleName ?? '').isNotEmpty ? ' — os cujo responsável é ${scope!.responsibleName} —' : ''}'
              ' os dados do proprietário ficam ocultos para todos. Só quem '
              'está nesta lista, além de admin e master, consegue vê-los.',
          chips: [
            PsChip(
              value: '${_enabled.length}',
              label: _enabled.length == 1 ? 'pessoa vê' : 'pessoas veem',
              color: teal,
              icon: LucideIcons.eye,
            ),
            if (scope != null)
              PsChip(
                value: NumberFormat.decimalPattern('pt_BR')
                    .format(scope.restrictedProperties),
                label: scope.restrictedProperties == 1
                    ? 'imóvel restrito'
                    : 'imóveis restritos',
                color: red,
                on: scope.restrictedProperties > 0,
                icon: LucideIcons.lock,
              ),
            if (!_canManage)
              PsChip(
                label: 'Só leitura — habilitar é com admin/master',
                color: PsPalette.amber(context),
                icon: LucideIcons.info,
              ),
          ],
        ),
        _secrecyRuler(context),
        _roleTrail(context),
        _enabledSection(context),
        if (_canManage) _enablePanel(context),
      ],
    );
  }

  // ─── Régua do sigilo ────────────────────────────────────────────────────

  Widget _secrecyRuler(BuildContext context) {
    final teal = PsPalette.teal(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return PsSection(
      title: 'O que fica oculto',
      subtitle: 'E onde a regra vale.',
      icon: LucideIcons.shieldCheck,
      color: teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in OwnerDataRules.hiddenFields)
                PsChip(label: f, color: teal, icon: LucideIcons.lock),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'VALE EM',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: muted,
            ),
          ),
          const SizedBox(height: 6),
          for (final (where, phrase) in OwnerDataRules.whereItApplies)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.circleCheck, size: 15, color: teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$where — ',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          TextSpan(text: phrase),
                        ],
                      ),
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── Trilha dos papéis (filtro) ─────────────────────────────────────────

  Widget _roleTrail(BuildContext context) {
    final counts = OwnerDataRules.countByRole(_enabled);
    final dark = psDark(context);
    Widget chip(OwnerDataRole? r, String label, int n, Color color) {
      final selected = _role == r;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          showCheckmark: false,
          selected: selected,
          onSelected: (_) => setState(() => _role = r),
          avatar: r == null
              ? null
              : Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
          label: Text('$label  $n'),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 0),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            chip(null, 'Todos', _enabled.length, PsPalette.teal(context)),
            for (final r in OwnerDataRole.values)
              chip(
                r,
                OwnerDataRules.roleLabel(r, plural: true),
                counts[r] ?? 0,
                PsPalette.role(context, r),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ─── Quem vê ────────────────────────────────────────────────────────────

  Widget _enabledSection(BuildContext context) {
    final teal = PsPalette.teal(context);
    final filtered = OwnerDataRules.filter(_enabled, _listQuery, role: _role);
    final groups = <OwnerDataRole, List<PropertySettingsMember>>{};
    for (final u in filtered) {
      groups.putIfAbsent(OwnerDataRules.roleOf(u.role), () => []).add(u);
    }
    return PsSection(
      title: 'Quem vê',
      subtitle: 'Habilitados a ver os dados do proprietário nos imóveis '
          'restritos.',
      icon: LucideIcons.userCheck,
      color: teal,
      trailing: PsBadge(label: '${filtered.length}', color: teal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_enabled.isNotEmpty) ...[
            _searchField(
              hint: 'Buscar por nome ou e-mail',
              onChanged: (v) => setState(() => _listQuery = v),
            ),
            const SizedBox(height: 10),
          ],
          if (_enabled.isEmpty)
            PsEmpty(
              icon: LucideIcons.eyeOff,
              text: _canManage
                  ? 'Ninguém habilitado ainda: só admin e master veem os '
                      'dados do proprietário. Habilite alguém logo abaixo — '
                      'vale na hora.'
                  : 'Ninguém habilitado ainda: só admin e master veem os '
                      'dados do proprietário.',
            )
          else if (filtered.isEmpty)
            const PsEmpty(
              icon: LucideIcons.search,
              text: 'Ninguém com esse nome neste recorte.',
            )
          else
            for (final r in OwnerDataRole.values)
              if ((groups[r] ?? const []).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Text(
                    '${OwnerDataRules.roleLabel(r, plural: true)} · '
                            '${groups[r]!.length}'
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: PsPalette.role(context, r),
                    ),
                  ),
                ),
                for (final u in (groups[r]!
                  ..sort((a, b) => OwnerDataRules.fold(a.name)
                      .compareTo(OwnerDataRules.fold(b.name)))))
                  _enabledRow(context, u),
              ],
        ],
      ),
    );
  }

  Widget _enabledRow(BuildContext context, PropertySettingsMember u) {
    final role = OwnerDataRules.roleOf(u.role);
    final color = PsPalette.role(context, role);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final removing = _removingId == u.id;
    final when = u.enabledAt == null
        ? null
        : DateFormat('dd/MM/yyyy', 'pt_BR').format(u.enabledAt!.toLocal());
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          children: [
            PsAvatar(name: u.name, url: u.avatar, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          u.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PsBadge(
                        label: OwnerDataRules.roleLabel(role),
                        color: color,
                      ),
                    ],
                  ),
                  if (u.email.isNotEmpty)
                    Text(
                      u.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  if (when != null || OwnerDataRules.seesByRole(u.role))
                    Text(
                      [
                        if (when != null) 'habilitado em $when',
                        if (OwnerDataRules.seesByRole(u.role))
                          'vê também pelo papel',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                ],
              ),
            ),
            if (_canManage)
              removing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: () => _disable(u),
                      style: TextButton.styleFrom(
                        foregroundColor: PsPalette.red(context),
                      ),
                      child: const Text('Remover'),
                    ),
          ],
        ),
      ),
    );
  }

  // ─── Habilitar ──────────────────────────────────────────────────────────

  Widget _enablePanel(BuildContext context) {
    final teal = PsPalette.teal(context);
    final enabledIds = _enabled.map((u) => u.id).toSet();
    final available =
        _members.where((u) => !enabledIds.contains(u.id)).toList();
    final filtered = OwnerDataRules.filter(available, _panelQuery);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return PsSection(
      title: 'Habilitar usuário',
      subtitle: 'Quem ainda não vê. Toque em + para habilitar — vale na hora.',
      icon: LucideIcons.userPlus,
      color: teal,
      trailing: PsBadge(label: '${available.length}', color: teal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchField(
            hint: 'Buscar por nome ou e-mail',
            onChanged: (v) => setState(() => _panelQuery = v),
          ),
          const SizedBox(height: 10),
          if (available.isEmpty)
            const PsEmpty(icon: LucideIcons.users, text: 'Todos já veem.')
          else if (filtered.isEmpty)
            const PsEmpty(
              icon: LucideIcons.search,
              text: 'Ninguém com esse nome.',
            )
          else
            for (final u in filtered.take(60))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    PsAvatar(
                      name: u.name,
                      url: u.avatar,
                      color: PsPalette.role(
                        context,
                        OwnerDataRules.roleOf(u.role),
                      ),
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          if (u.email.isNotEmpty)
                            Text(
                              u.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: muted),
                            ),
                        ],
                      ),
                    ),
                    _addingId == u.id
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton.filledTonal(
                            tooltip: 'Habilitar ${u.name}',
                            onPressed:
                                _addingId != null ? null : () => _enable(u),
                            icon: Icon(LucideIcons.plus, size: 18, color: teal),
                          ),
                  ],
                ),
              ),
          if (filtered.length > 60)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Mostrando 60 de ${filtered.length} — refine a busca.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchField({
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: const Icon(LucideIcons.search, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
