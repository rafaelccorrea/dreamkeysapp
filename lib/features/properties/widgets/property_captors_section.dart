import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/profile_service.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/utils/property_finalidade.dart';
import '../services/property_captor_users_service.dart';
import '../utils/property_captor_slots.dart';

/// Estado da captação por papel + responsáveis do wizard de imóvel.
///
/// Porte do que o web guarda em `formData.saleCaptorIds` /
/// `rentCaptorIds` / `responsibleUserIds` (`CreatePropertyPage.tsx`), com a
/// lista de usuários de `usersApi.getUsers({ allCompanyUsers: true })`.
/// Fica fora da página para o encaixe no wizard ser só "ler/gravar".
class PropertyCaptorsController extends ChangeNotifier {
  PropertyCaptorsController({PropertyCaptorUsersService? usersService})
      : _usersService = usersService ?? PropertyCaptorUsersService.instance;

  final PropertyCaptorUsersService _usersService;

  List<String> _sale = [];
  List<String> _rent = [];
  List<String> _responsibles = [];

  /// Como o imóvel veio do servidor (só na edição). `null` = não carregado:
  /// a edição não manda nada de captação (imoveis-04).
  List<String>? _loadedSale;
  List<String>? _loadedRent;
  List<String>? _loadedResponsibles;

  final Map<String, CaptorUserOption> _company = {};

  /// Vínculos já gravados que não estão na lista da empresa (desativados,
  /// lista negada por permissão) — `linkedUsersFallback` do web.
  final Map<String, CaptorUserOption> _fallback = {};
  CaptorUserOption? _me;

  bool _loadingUsers = true;
  String? _permissionMessage;
  bool _disposed = false;

  List<String> get saleIds => List.unmodifiable(_sale);
  List<String> get rentIds => List.unmodifiable(_rent);
  List<String> get responsibleIds => List.unmodifiable(_responsibles);
  bool get loadingUsers => _loadingUsers;
  String? get permissionMessage => _permissionMessage;

  List<CaptorUserOption> get users {
    final out = <String, CaptorUserOption>{..._company};
    for (final u in _fallback.values) {
      out.putIfAbsent(u.id, () => u);
    }
    final list = out.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  String nameOf(String id) {
    final u = _company[id] ?? _fallback[id];
    if (u != null && u.name.trim().isNotEmpty) return u.name;
    return 'Usuário ${id.length > 8 ? id.substring(0, 8) : id}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Carrega o usuário logado e a lista da empresa. Na criação, o
  /// responsável começa como o usuário logado (web: só na criação).
  Future<void> loadUsers({required bool defaultResponsibleToMe}) async {
    _loadingUsers = true;
    _permissionMessage = null;
    _notify();
    try {
      final profile = await ProfileService.instance.getProfile();
      if (profile.success && profile.data != null && profile.data!.id.isNotEmpty) {
        final p = profile.data!;
        _me = CaptorUserOption(
          id: p.id,
          name: p.name.trim().isNotEmpty
              ? p.name.trim()
              : (p.email.trim().isNotEmpty ? p.email.trim() : 'Usuário'),
          email: p.email.trim().isEmpty ? null : p.email.trim(),
        );
        _company[_me!.id] = _me!;
        if (defaultResponsibleToMe && _responsibles.isEmpty) {
          _responsibles = [_me!.id];
        }
        _notify();
      }
    } catch (e) {
      debugPrint('Captadores: falha ao carregar o perfil: $e');
    }

    final res = await _usersService.listCompanyUsers();
    if (_disposed) return;
    if (res.success && res.data != null) {
      _company
        ..clear()
        ..addEntries(res.data!.map((u) => MapEntry(u.id, u)));
      if (_me != null) _company.putIfAbsent(_me!.id, () => _me!);
    } else if (res.statusCode == 403) {
      _permissionMessage = 'Você não tem permissão para visualizar a lista de '
          'usuários. Selecione você mesmo como captador ou solicite a um '
          'administrador.';
    }
    _loadingUsers = false;
    _notify();
  }

  /// Edição: preenche os slots a partir do `GET /properties/:id` e guarda o
  /// retrato para o PATCH mandar só o que mudar.
  void hydrateFromProperty(Property p) {
    final refs = <CaptorRef>[
      for (final c in p.captors ?? const <PropertyCaptor>[])
        (id: c.id, role: c.role),
    ];
    final allIds = loadedCaptorIds(
      captors: refs,
      capturedByIds: p.capturedByIds,
      capturedById: p.capturedById ?? p.capturedBy?.id,
    );
    final split = splitCaptorsByRole(
      captors: refs,
      allIds: allIds,
      finalidadeGravada: PropertyFinalidade.tryParse(p.finalidade),
    );
    _sale = List.of(split.sale);
    _rent = List.of(split.rent);
    _loadedSale = List.of(split.sale);
    _loadedRent = List.of(split.rent);

    final resp = loadedResponsibleIds(
      responsibleUserIds: p.responsibleUserIds,
      responsiblesFromList: [
        for (final r in p.responsibles ?? const <PropertyResponsible>[]) r.id,
      ],
      responsibleUserId: p.responsibleUserId,
    );
    _responsibles = List.of(resp);
    _loadedResponsibles = List.of(resp);

    // Nomes dos vínculos atuais para o seletor (mesmo fora da lista).
    for (final c in p.captors ?? const <PropertyCaptor>[]) {
      if (c.id.isEmpty) continue;
      _fallback[c.id] = CaptorUserOption(
        id: c.id,
        name: (c.name ?? '').trim().isNotEmpty ? c.name!.trim() : nameOf(c.id),
        email: c.email,
      );
    }
    final cb = p.capturedBy;
    if (cb != null && cb.id.isNotEmpty && cb.name.trim().isNotEmpty) {
      _fallback.putIfAbsent(
        cb.id,
        () => CaptorUserOption(id: cb.id, name: cb.name.trim(), email: cb.email),
      );
    }
    for (final r in p.responsibles ?? const <PropertyResponsible>[]) {
      if (r.id.isEmpty || (r.name ?? '').trim().isEmpty) continue;
      _fallback.putIfAbsent(
        r.id,
        () => CaptorUserOption(id: r.id, name: r.name!.trim(), email: r.email),
      );
    }
    _notify();
  }

  void setSale(List<String> ids) {
    _sale = List.of(ids);
    _notify();
  }

  void setRent(List<String> ids) {
    _rent = List.of(ids);
    _notify();
  }

  void setResponsibles(List<String> ids) {
    _responsibles = List.of(ids);
    _notify();
  }

  CaptorSlotsEvaluation evaluate(PropertyFinalidade? finalidade) =>
      evaluateCaptorSlots(
        finalidade: finalidade,
        saleIds: _sale,
        rentIds: _rent,
      );

  /// Campos do `POST /properties`.
  Map<String, dynamic> createPayload(String currentUserId) =>
      captorCreatePayload(
        saleIds: _sale,
        rentIds: _rent,
        responsibleIds: _responsibles,
        currentUserId: currentUserId,
      );

  /// Campos do `PATCH /properties/:id` — só o que mudou.
  Map<String, dynamic> editPatch({required bool finalidadeChanged}) {
    final ls = _loadedSale;
    final lr = _loadedRent;
    final lresp = _loadedResponsibles;
    if (ls == null || lr == null || lresp == null) return const {};
    return captorEditPatch(
      loadedSale: ls,
      loadedRent: lr,
      sale: _sale,
      rent: _rent,
      loadedResponsibles: lresp,
      responsibles: _responsibles,
      finalidadeChanged: finalidadeChanged,
    );
  }

  /// Captador principal como fica depois do save (para a checagem local de
  /// campos obrigatórios configuráveis).
  String? get primaryCaptorId {
    final u = captorUnion(_sale, _rent);
    return u.isEmpty ? null : u.first;
  }

  Map<String, dynamic> toDraftJson() => {
        'saleCaptorIds': List<String>.from(_sale),
        'rentCaptorIds': List<String>.from(_rent),
        'responsibleUserIds': List<String>.from(_responsibles),
      };

  void restoreDraft(Map<String, dynamic>? raw) {
    if (raw == null) return;
    List<String>? read(String k) {
      final v = raw[k];
      if (v is! List) return null;
      return v.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
    }

    final s = read('saleCaptorIds');
    final r = read('rentCaptorIds');
    final resp = read('responsibleUserIds');
    if (s != null) _sale = s;
    if (r != null) _rent = r;
    if (resp != null && resp.isNotEmpty) _responsibles = resp;
    _notify();
  }
}

/// Seção "Captação e responsáveis" — porte de `CaptorRoleSlots` +
/// `CaptorMultiSelect` (responsáveis) do web. A finalidade é escolhida no
/// próprio wizard (modal de pré-criação ou cartão da etapa 1); aqui ela só
/// acende os slots como obrigatórios/opcionais.
class PropertyCaptorsSection extends StatelessWidget {
  final PropertyCaptorsController controller;
  final PropertyFinalidade? finalidade;

  const PropertyCaptorsSection({
    super.key,
    required this.controller,
    required this.finalidade,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final evaluation = controller.evaluate(finalidade);
        final required = captorRolesRequiredBy(finalidade);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final role in CaptorRole.values) ...[
              if (role == CaptorRole.locacao) const SizedBox(height: 12),
              _SlotCard(
                role: role,
                controller: controller,
                state: finalidade == null
                    ? _SlotState.idle
                    : required.contains(role)
                        ? _SlotState.required
                        : _SlotState.optional,
                missing: evaluation.missingRoles.contains(role),
              ),
            ],
            const SizedBox(height: 12),
            _RuleStrip(
              evaluation: evaluation,
              finalidade: finalidade,
              permissionMessage: controller.permissionMessage,
            ),
            const SizedBox(height: 18),
            _ResponsiblesBlock(controller: controller),
          ],
        );
      },
    );
  }
}

enum _SlotState { required, optional, idle }

Color _roleColor(CaptorRole role, bool isDark) => role == CaptorRole.venda
    ? FinalidadeTint.venda(isDark)
    : FinalidadeTint.locacao(isDark);

String _countLabel(int n) =>
    n == 0 ? 'Ninguém escolhido' : (n == 1 ? '1 pessoa' : '$n pessoas');

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length && a.every(b.contains);

class _SlotCard extends StatelessWidget {
  final CaptorRole role;
  final PropertyCaptorsController controller;
  final _SlotState state;
  final bool missing;

  const _SlotCard({
    required this.role,
    required this.controller,
    required this.state,
    required this.missing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _roleColor(role, isDark);
    final isSale = role == CaptorRole.venda;
    final ids = isSale ? controller.saleIds : controller.rentIds;
    final other = isSale ? controller.rentIds : controller.saleIds;
    final error = AppColors.status.error;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final canMirror = other.isNotEmpty && !_sameList(ids, other);

    final borderColor = missing
        ? error
        : state == _SlotState.required
            ? accent.withValues(alpha: 0.55)
            : (isDark
                ? Colors.white.withValues(alpha: 0.10)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.45));

    void setIds(List<String> next) =>
        isSale ? controller.setSale(next) : controller.setRent(next);

    Widget badge;
    switch (state) {
      case _SlotState.required:
        badge = _Badge(
          text: 'OBRIGATÓRIO',
          icon: missing ? Icons.error_outline_rounded : Icons.check_rounded,
          color: missing ? error : accent,
          filled: !missing,
        );
      case _SlotState.optional:
        badge = _Badge(text: 'OPCIONAL', color: secondary, filled: false);
      case _SlotState.idle:
        badge = _Badge(
          text: 'DEFINA A FINALIDADE',
          icon: Icons.lock_outline_rounded,
          color: secondary,
          filled: false,
        );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: state == _SlotState.required && !missing
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Faixa de cor no topo: cheia quando obrigatório, fraca quando
          // opcional, neutra sem finalidade (mesma leitura do web).
          Container(
            height: 4,
            color: state == _SlotState.required
                ? accent
                : state == _SlotState.optional
                    ? accent.withValues(alpha: 0.30)
                    : secondary.withValues(alpha: 0.18),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                      ),
                      child: Icon(
                        isSale ? Icons.sell_rounded : Icons.vpn_key_rounded,
                        size: 18,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isSale ? 'Captador de venda' : 'Captador de locação',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          Text(
                            _countLabel(ids.length),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: secondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: badge),
                  ],
                ),
                const SizedBox(height: 10),
                _PeopleChips(
                  ids: ids,
                  controller: controller,
                  accent: accent,
                  onRemove: (id) => setIds([...ids]..remove(id)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final next = await showCaptorUserPicker(
                          context: context,
                          controller: controller,
                          title: isSale
                              ? 'Quem captou para venda'
                              : 'Quem captou para locação',
                          selected: ids,
                          accent: accent,
                        );
                        if (next != null) setIds(next);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withValues(alpha: 0.5)),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: Icon(
                        ids.isEmpty
                            ? Icons.person_add_alt_1_rounded
                            : Icons.edit_rounded,
                        size: 16,
                      ),
                      label: Text(ids.isEmpty ? 'Escolher' : 'Alterar'),
                    ),
                    TextButton.icon(
                      onPressed: canMirror ? () => setIds(List.of(other)) : null,
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: Text(
                        isSale ? 'Mesmos da locação' : 'Mesmos da venda',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      missing
                          ? Icons.error_outline_rounded
                          : ids.isNotEmpty
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                      size: 15,
                      color: missing
                          ? error
                          : ids.isNotEmpty
                              ? AppColors.status.success
                              : secondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        missing
                            ? 'Falta o captador de ${role.label}'
                            : ids.isNotEmpty
                                ? 'Preenchido'
                                : state == _SlotState.optional
                                    ? 'Não exigido por esta finalidade'
                                    : 'Escolha quem captou',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: missing
                              ? error
                              : ids.isNotEmpty
                                  ? AppColors.status.success
                                  : secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  final bool filled;

  const _Badge({
    required this.text,
    required this.color,
    required this.filled,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: filled ? color : color.withValues(alpha: 0.08),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleChips extends StatelessWidget {
  final List<String> ids;
  final PropertyCaptorsController controller;
  final Color accent;
  final ValueChanged<String> onRemove;

  const _PeopleChips({
    required this.ids,
    required this.controller,
    required this.accent,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (ids.isEmpty) {
      return Text(
        controller.loadingUsers ? 'Carregando usuários…' : 'Ninguém selecionado',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontStyle: FontStyle.italic,
            ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < ids.length; i++)
          InputChip(
            avatar: CircleAvatar(
              backgroundColor: accent.withValues(alpha: isDark ? 0.30 : 0.16),
              child: Text(
                _initials(controller.nameOf(ids[i])),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
            label: Text(
              controller.nameOf(ids[i]),
              overflow: TextOverflow.ellipsis,
            ),
            labelStyle: TextStyle(
              fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
            side: BorderSide(color: accent.withValues(alpha: 0.35)),
            backgroundColor: accent.withValues(alpha: isDark ? 0.10 : 0.05),
            visualDensity: VisualDensity.compact,
            onDeleted: () => onRemove(ids[i]),
            deleteIconColor: ThemeHelpers.textSecondaryColor(context),
          ),
      ],
    );
  }
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

class _RuleStrip extends StatelessWidget {
  final CaptorSlotsEvaluation evaluation;
  final PropertyFinalidade? finalidade;
  final String? permissionMessage;

  const _RuleStrip({
    required this.evaluation,
    required this.finalidade,
    required this.permissionMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = evaluation.valid;
    final warn = !ok && !evaluation.finalidadeMissing;
    final color = ok
        ? AppColors.status.success
        : warn
            ? AppColors.status.error
            : ThemeHelpers.textSecondaryColor(context);
    final msg = [
      if ((permissionMessage ?? '').isNotEmpty) permissionMessage!,
      captorRuleMessage(evaluation, finalidade),
    ].join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.07),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok
                ? Icons.check_circle_rounded
                : warn
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: warn ? color : ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiblesBlock extends StatelessWidget {
  final PropertyCaptorsController controller;

  const _ResponsiblesBlock({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = Color(0xFF6366F1);
    final ids = controller.responsibleIds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.badge_rounded, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Responsável(eis)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                final next = await showCaptorUserPicker(
                  context: context,
                  controller: controller,
                  title: 'Responsáveis pelo imóvel',
                  selected: ids,
                  accent: accent,
                );
                if (next != null) controller.setResponsibles(next);
              },
              style: TextButton.styleFrom(
                foregroundColor: accent,
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(
                ids.isEmpty ? Icons.person_add_alt_1_rounded : Icons.edit_rounded,
                size: 16,
              ),
              label: Text(ids.isEmpty ? 'Escolher' : 'Alterar'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _PeopleChips(
          ids: ids,
          controller: controller,
          accent: accent,
          onRemove: (id) => controller.setResponsibles([...ids]..remove(id)),
        ),
        const SizedBox(height: 6),
        Text(
          'Se vazio, o usuário atual será o responsável. O primeiro da lista '
          'é o principal.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }
}

/// Folha de seleção múltipla com busca (o `CaptorMultiSelect` do web).
/// Devolve a nova lista, na ordem em que foi marcada, ou `null` se fechar.
Future<List<String>?> showCaptorUserPicker({
  required BuildContext context,
  required PropertyCaptorsController controller,
  required String title,
  required List<String> selected,
  required Color accent,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _CaptorUserPickerSheet(
      controller: controller,
      title: title,
      initial: selected,
      accent: accent,
    ),
  );
}

class _CaptorUserPickerSheet extends StatefulWidget {
  final PropertyCaptorsController controller;
  final String title;
  final List<String> initial;
  final Color accent;

  const _CaptorUserPickerSheet({
    required this.controller,
    required this.title,
    required this.initial,
    required this.accent,
  });

  @override
  State<_CaptorUserPickerSheet> createState() => _CaptorUserPickerSheetState();
}

class _CaptorUserPickerSheetState extends State<_CaptorUserPickerSheet> {
  late final List<String> _picked = List.of(widget.initial);
  String _query = '';

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final q = _norm(_query.trim());
        final users = widget.controller.users.where((u) {
          if (q.isEmpty) return true;
          return _norm(u.name).contains(q) || _norm(u.email ?? '').contains(q);
        }).toList();
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: ThemeHelpers.borderColor(context),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome ou e-mail',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (widget.controller.loadingUsers)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Flexible(
                child: users.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.controller.loadingUsers
                              ? 'Carregando usuários…'
                              : 'Nenhum usuário encontrado.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: users.length,
                        itemBuilder: (context, i) {
                          final u = users[i];
                          final on = _picked.contains(u.id);
                          return CheckboxListTile(
                            value: on,
                            activeColor: widget.accent,
                            controlAffinity: ListTileControlAffinity.trailing,
                            dense: true,
                            title: Text(
                              u.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: (u.email ?? '').isEmpty
                                ? null
                                : Text(
                                    u.email!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                if (!_picked.contains(u.id)) _picked.add(u.id);
                              } else {
                                _picked.remove(u.id);
                              }
                            }),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.accent,
                          ),
                          onPressed: () =>
                              Navigator.of(context).pop(List.of(_picked)),
                          child: Text(
                            _picked.isEmpty
                                ? 'Confirmar'
                                : 'Confirmar (${_picked.length})',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
