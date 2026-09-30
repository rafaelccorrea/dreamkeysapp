import '../models/admin_user_model.dart';
import 'permission_meta.dart';

/// Regras de atribuição de permissões — porte fiel das utilidades do web
/// usadas nas telas de criar/editar usuário:
///   • `utils/requiredPermissions.ts` (obrigatórias do sistema + alçada)
///   • `utils/permissionDependencies.ts` (dependências e ocultas)
///   • `utils/permissionModuleMapping.ts` (módulo do plano por permissão)
///   • `hooks/useKanbanPermissions.ts` (fixas do funil para corretor)
///
/// O back valida tudo de novo (alçada, plano, proprietário); espelhar aqui
/// evita o 403 na hora de salvar e o usuário "zerado" sem acesso.
class PermissionRules {
  PermissionRules._();

  /// `KANBAN_OPERATIONAL_PERMISSIONS` — fixas do Funil de Vendas.
  static const List<String> brokerFixed = [
    'kanban:view',
    'kanban:create',
    'kanban:update',
    'kanban:view_history',
  ];

  /// `SYSTEM_REQUIRED_PERMISSION_NAMES` — pacote obrigatório de todo usuário
  /// interno (sincronizado com MANDATORY_PERMISSIONS_FOR_ALL do back).
  static const List<String> systemRequired = [
    'user:view',
    'team:view',
    'property:view',
    'property:create',
    'property:update',
    'property:delete',
    'client:view',
    'client:create',
    'client:update',
    'client:assign_property',
    'calendar:view',
    'calendar:create',
    'calendar:update',
    'calendar:delete',
    'note:view',
    'note:create',
    'note:update',
    'note:delete',
    'kanban:view',
    'kanban:create',
    'kanban:update',
    'kanban:view_history',
    'proposal:view',
    'proposal:create',
    'proposal:update',
    'proposal:delete',
    'proposal:export',
    'sale_form:view',
    'sale_form:create',
    'sale_form:update',
    'sale_form:delete',
    'sale_form:export',
    'rental_form:view',
    'rental_form:create',
    'rental_form:update',
    'rental_form:delete',
    'rental_form:export',
    'condominium:view',
    'empreendimento:view',
    'document:read',
    'document:create',
    'document:update',
    'document:download',
    'visit:view',
    'visit:create',
    'visit:update',
    'visit:delete',
    'key:view',
    'key:checkout',
    'key:return',
    'check_in:do',
    'check_in:view',
    'gallery:view',
    'ticket:view',
    'ticket:create',
  ];

  /// Permissões do funil que só admin/master concede (edição).
  static const List<String> adminOnly = ['kanban:export', 'kanban:import'];

  static const List<String> _hiddenPrefixes = [
    'gallery:',
    'audit:',
    'instagram:',
  ];
  static const List<String> _hiddenCategories = [
    'gallery',
    'audit',
    'instagram',
  ];

  /// Módulos ocultos do produto (`HIDDEN_MODULES` do web): a permissão que
  /// depende deles nunca aparece.
  static const List<String> _hiddenModules = [
    'commission_management',
    'gamification',
    'mcmv',
    'mcmv_management',
  ];

  /// Aliases de módulo (`MODULE_ALIASES` do web) — os que as permissões usam.
  static const Map<String, List<String>> _moduleAliases = {
    'vistoria': ['vistoria', 'inspection', 'inspections'],
    'key_control': ['key_control', 'keys', 'key_management'],
    'rental_management': ['rental_management', 'rentals', 'rental'],
    'credit_and_collection': [
      'credit_and_collection',
      'credit_and_collection_management',
    ],
    'calendar_management': ['calendar_management', 'calendar', 'calendars'],
    'commission_management': [
      'commission_management',
      'commissions',
      'commission',
    ],
    'document_management': ['document_management', 'documents', 'document'],
    'visit_report': ['visit_report', 'visit-reports', 'visit'],
    'match_system': ['match_system', 'matches', 'match'],
    'sale_forms': ['sale_forms', 'sale_form', 'fichas_venda', 'fichas-venda'],
    'notes': ['notes', 'note'],
    'appointments': ['appointments', 'appointment'],
    'dashboard': ['dashboard', 'dashboards'],
    'system_management': ['system_management', 'system', 'systems'],
  };

  static bool isSystemRequired(String name) => systemRequired.contains(name);

  static bool isHidden(UserPermission p) {
    final name = p.name.toLowerCase();
    final cat = p.category.toLowerCase();
    return _hiddenCategories.contains(cat) ||
        _hiddenPrefixes.any((pre) => name.startsWith(pre));
  }

  /// `getRequiredModuleForPermission` do web (mapa por prefixo).
  static String? requiredModuleFor(String name) {
    bool s(String p) => name.startsWith(p);
    if (s('user:')) return 'user_management';
    if (s('company:')) return 'company_management';
    if (s('property:')) return 'property_management';
    if (s('client:')) return 'client_management';
    if (s('checklist:')) return 'checklist_management';
    if (s('kanban:')) return 'kanban_management';
    if (s('inspection:')) return 'vistoria';
    if (s('key:')) return 'key_control';
    if (s('rental:')) return 'rental_management';
    if (s('rental_form:')) return 'rental_management';
    if (s('sale_form:') || s('proposal:')) return 'sale_forms';
    if (s('chaves_na_mao:') || s('properties_api:')) {
      return 'third_party_integrations';
    }
    if (s('calendar:')) return 'calendar_management';
    if (s('commission:')) return 'commission_management';
    if (s('document:')) return 'document_management';
    if (s('match:')) return 'match_system';
    if (s('team:')) return 'team_management';
    if (s('backup:')) return 'basic_reports';
    if (s('visit:')) return 'visit_report';
    if (s('condominium:')) return 'property_management';
    if (s('empreendimento:')) return 'property_management';
    if (s('financial:')) return 'financial_management';
    if (s('marketing:')) return 'marketing_tools';
    if (s('api:')) return 'api_integrations';
    if (s('custom-field:')) return 'custom_fields';
    if (s('workflow:')) return 'workflow_automation';
    if (s('bi:') || s('business-intelligence:')) {
      return 'business_intelligence';
    }
    if (s('integration:') ||
        s('meta_campaign:') ||
        s('grupo_zap:') ||
        s('instagram:')) {
      return 'third_party_integrations';
    }
    if (s('lead_distribution:')) return 'lead_distribution';
    if (s('gamification:') ||
        s('competition:') ||
        s('reward:') ||
        s('prize:')) {
      return 'gamification';
    }
    if (s('note:')) return 'notes';
    if (s('appointment:')) return 'appointments';
    if (s('audit:')) return 'advanced_reports';
    if (s('insurance:') || s('collection:') || s('credit_analysis:')) {
      return 'credit_and_collection';
    }
    if (s('performance:')) return 'dashboard';
    if (s('report:')) {
      if (name.contains('advanced') || name.contains('export')) {
        return 'advanced_reports';
      }
      return 'basic_reports';
    }
    if (s('system:')) return 'system_management';
    if (s('gallery:')) return 'image_gallery';
    if (s('mcmv:')) return 'mcmv_management';
    if (s('asset:')) return 'asset_management';
    if (s('public_analytics:')) return 'public_site_analytics';
    if (s('public_site:')) return 'public_site_hosting';
    if (name == 'whatsapp:manage_config') return 'third_party_integrations';
    if (s('whatsapp:')) return 'api_integrations';
    return null;
  }

  /// `isModuleAvailable` do web (com aliases e módulos ocultos). Lista vazia
  /// = módulos da empresa ainda não conhecidos → não filtra (o back decide).
  static bool moduleAvailable(String module, List<String> companyModules) {
    if (companyModules.isEmpty) return true;
    final id = module.toLowerCase().trim();
    if (_hiddenModules.contains(id)) return false;
    final mods = companyModules.map((m) => m.toLowerCase().trim()).toSet();
    if (mods.contains(id)) return true;
    for (final entry in _moduleAliases.entries) {
      if (entry.key == id || entry.value.contains(id)) {
        if (mods.contains(entry.key)) return true;
        if (entry.value.any(mods.contains)) return true;
      }
    }
    return false;
  }

  static bool allowedForCompany(String name, List<String> companyModules) {
    final m = requiredModuleFor(name);
    if (m == null) return true;
    return moduleAvailable(m, companyModules);
  }

  /// `actorCanGrantPermissionByName`: master/admin concedem tudo; os demais,
  /// o pacote obrigatório ou o que eles mesmos possuem.
  static bool actorCanGrant(
    String actorRole,
    List<String> actorPermissionNames,
    String name,
  ) {
    if (actorRole == 'master' || actorRole == 'admin') return true;
    if (isSystemRequired(name)) return true;
    return actorPermissionNames.contains(name);
  }

  static String _category(String name) => name.split(':').first;
  static String _action(String name) {
    final parts = name.split(':');
    return parts.length > 1 ? parts[1] : '';
  }

  static String _viewFor(String name) {
    final c = _category(name);
    if (c == 'document' || c == 'client') return '$c:read';
    return '$c:view';
  }

  /// `getRequiredPermissions` do web.
  static List<String> requiredNames(String name) {
    final req = <String>[name];
    if (name == 'performance:compare') {
      req.addAll([
        'performance:view',
        'performance:view_team',
        'performance:view_company',
      ]);
      return req;
    }
    if (name.startsWith('team:') && !req.contains('user:view')) {
      req.insert(0, 'user:view');
    }
    if (name == 'kanban:manage_users' && !req.contains('team:view')) {
      req.insert(0, 'team:view');
    }
    final action = _action(name);
    if (action != 'view' && action != 'read') {
      req.insert(0, _viewFor(name));
    }
    if (_category(name) == 'property') {
      req.add('gallery:$action');
    }
    return req;
  }

  static String labelOf(UserPermission p) =>
      PermissionMeta.permissionDescription(p.name, fallback: p.description);
}

/// Aviso gerado por uma ação na grade (dependência adicionada, remoção
/// bloqueada, permissão travada). `warning` = âmbar; senão informativo.
class PermissionNotice {
  final String message;
  final bool warning;
  const PermissionNotice(this.message, {this.warning = true});
}

/// Estado da seleção de permissões compartilhado por criar e editar usuário.
/// Reproduz `availablePermissions`, `getFixedPermissionIds`,
/// `finalizePermissionSelectionForCreate/Edit`, `handlePermissionChange` e
/// `toggleCategory` do web.
class PermissionSelection {
  PermissionSelection({
    required this.isEdit,
    required Map<String, List<UserPermission>> catalog,
    required String actorRole,
    required List<String> actorPermissionNames,
    required List<String> companyModules,
    List<String> baselineNames = const [],
    this.editingOwner = false,
    required String role,
  })  : _actorRole = actorRole.toLowerCase().trim(),
        _actorPerms = List.unmodifiable(actorPermissionNames),
        _companyModules = List.unmodifiable(companyModules),
        _baselineNames = Set.unmodifiable(baselineNames),
        _role = role {
    final seen = <String>{};
    for (final entry in catalog.entries) {
      for (final p in entry.value) {
        if (p.id.isEmpty || !seen.add(p.id)) continue;
        _all.add(p);
        _categoryOf[p.id] = entry.key;
      }
    }
    _available = _all.where((p) {
      if (!PermissionRules.allowedForCompany(p.name, _companyModules)) {
        return false;
      }
      if (elevatedActor) return true;
      return PermissionRules.actorCanGrant(_actorRole, _actorPerms, p.name) ||
          (isEdit && _baselineNames.contains(p.name));
    }).toList();
    _availableIds = _available.map((p) => p.id).toSet();

    // Grade: por categoria, sem as ocultas, ordenada pelo rótulo.
    final grouped = <String, List<UserPermission>>{};
    for (final p in _available) {
      if (PermissionRules.isHidden(p)) continue;
      grouped.putIfAbsent(_categoryOf[p.id]!, () => []).add(p);
    }
    categories = grouped.entries.toList()
      ..sort((a, b) => PermissionMeta.categoryLabel(a.key)
          .toLowerCase()
          .compareTo(PermissionMeta.categoryLabel(b.key).toLowerCase()));
  }

  final bool isEdit;

  /// Usuário editado é o proprietário (owner).
  final bool editingOwner;

  final String _actorRole;
  final List<String> _actorPerms;
  final List<String> _companyModules;
  final Set<String> _baselineNames;
  String _role;

  final List<UserPermission> _all = [];
  final Map<String, String> _categoryOf = {};
  late final List<UserPermission> _available;
  late final Set<String> _availableIds;

  /// Categorias exibidas na grade.
  late final List<MapEntry<String, List<UserPermission>>> categories;

  /// Seleção corrente (IDs).
  Set<String> selected = {};

  bool get elevatedActor => _actorRole == 'master' || _actorRole == 'admin';
  bool get actorIsMaster => _actorRole == 'master';

  /// Proprietário só tem as permissões alteradas pelo master.
  bool get ownerLocked => isEdit && editingOwner && !actorIsMaster;

  String get role => _role;

  int get visibleTotal => categories.fold(0, (s, e) => s + e.value.length);

  UserPermission? byId(String id) {
    for (final p in _all) {
      if (p.id == id) return p;
    }
    return null;
  }

  UserPermission? _availableById(String id) {
    if (!_availableIds.contains(id)) return null;
    return byId(id);
  }

  String? _availableIdByName(String name) {
    for (final p in _available) {
      if (p.name == name) return p.id;
    }
    return null;
  }

  /// `getFixedPermissionIds`: funil (corretor) + obrigatórias do sistema.
  Set<String> get fixedIds => _available
      .where((p) =>
          PermissionRules.brokerFixed.contains(p.name) ||
          PermissionRules.isSystemRequired(p.name))
      .map((p) => p.id)
      .toSet();

  bool _isUserPerm(UserPermission p) =>
      p.category == 'user' ||
      p.name.startsWith('user:') ||
      p.category == 'Gestão de Usuários';

  bool get _roleLocksUserPerms => _role == 'manager' || _role == 'admin';

  /// Motivo da trava de uma permissão na grade (null = editável). Aparece
  /// na própria linha, ao lado do cadeado — frase curta que diz o porquê.
  String? lockReason(UserPermission p) {
    if (ownerLocked) {
      return 'Apenas o usuário master pode alterar as permissões do proprietário.';
    }
    if (isEdit && PermissionRules.adminOnly.contains(p.name) && !elevatedActor) {
      return 'Somente administradores ou o usuário master podem conceder esta permissão.';
    }
    if (_roleLocksUserPerms && _isUserPerm(p)) {
      return 'Obrigatória para este papel';
    }
    if (selected.contains(p.id) &&
        (PermissionRules.brokerFixed.contains(p.name) ||
            PermissionRules.isSystemRequired(p.name))) {
      return 'Obrigatória para todo usuário';
    }
    return null;
  }

  /// `finalizePermissionSelectionForCreate/Edit`.
  Set<String> finalize(Iterable<String> ids) {
    final keep = fixedIds;
    final out = <String>{};
    for (final id in ids) {
      if (out.contains(id)) continue;
      final p = byId(id);
      if (p == null) continue;
      final grantable = keep.contains(id) ||
          (isEdit && _baselineNames.contains(p.name)) ||
          PermissionRules.actorCanGrant(_actorRole, _actorPerms, p.name);
      if (!grantable) continue;
      if (!PermissionRules.allowedForCompany(p.name, _companyModules)) continue;
      out.add(id);
    }
    return out;
  }

  /// Seleção inicial: na edição, resolve pelos NOMES que o usuário já tem
  /// (evita divergência de ID) e mescla as fixas; na criação, só as fixas.
  void initialize({List<String> currentNames = const []}) {
    final ids = <String>{};
    for (final n in currentNames) {
      final id = _availableIdByName(n);
      if (id != null) ids.add(id);
    }
    selected = {...ids, ...fixedIds};
    _addUserPermsForRole();
  }

  /// Troca de papel do usuário-alvo: manager/admin recebem todas as
  /// permissões de usuário (travadas), como o web.
  void setRole(String role) {
    _role = role;
    _addUserPermsForRole();
  }

  void _addUserPermsForRole() {
    if (!_roleLocksUserPerms) return;
    selected.addAll(_available.where(_isUserPerm).map((p) => p.id));
  }

  /// Garante as fixas (usado antes de validar/salvar).
  void mergeFixed() => selected = {...selected, ...fixedIds};

  /// IDs a enviar no POST/PUT.
  List<String> idsForSave() => finalize({...selected, ...fixedIds}).toList();

  PermissionNotice get _ownerNotice => PermissionNotice(
        editingOwner
            ? 'Apenas o usuário master pode alterar as permissões do proprietário.'
            : 'Por segurança, proprietários não podem alterar suas próprias permissões.',
      );

  /// `handlePermissionChange`: liga/desliga uma permissão aplicando as
  /// travas, as dependências e a alçada. Devolve o aviso a exibir.
  PermissionNotice? toggle(String id) {
    if (ownerLocked) return _ownerNotice;
    final p = _availableById(id);
    if (p == null) return null;
    final checked = !selected.contains(id);

    if (isEdit && PermissionRules.adminOnly.contains(p.name) && !elevatedActor) {
      return const PermissionNotice(
        'Somente administradores ou o usuário master podem conceder Exportar/Importar do Funil de Vendas.',
      );
    }
    if (_roleLocksUserPerms && _isUserPerm(p)) {
      return const PermissionNotice(
        'Permissões de usuário são obrigatórias para este perfil e não podem ser editadas',
      );
    }
    if (!checked && PermissionRules.brokerFixed.contains(p.name)) {
      return const PermissionNotice(
        'Permissões de Funil de Vendas são obrigatórias para corretores e não podem ser removidas',
      );
    }
    if (!checked && PermissionRules.isSystemRequired(p.name)) {
      return const PermissionNotice(
        'Visualização de usuários e equipes é obrigatória para o funcionamento do sistema e não pode ser removida',
      );
    }

    PermissionNotice? notice;
    Set<String> next;
    if (checked) {
      final required = PermissionRules.requiredNames(p.name);
      final added = <String>[];
      next = {...selected};
      for (final name in required) {
        final rid = _availableIdByName(name);
        if (rid == null || next.contains(rid)) continue;
        next.add(rid);
        if (rid != id && !name.startsWith('gallery:')) added.add(rid);
      }
      next.add(id);
      if (added.isNotEmpty) {
        final names = added
            .map((x) => byId(x))
            .whereType<UserPermission>()
            .map(PermissionRules.labelOf)
            .join(', ');
        notice = PermissionNotice(
          added.length == 1
              ? 'A permissão "$names" foi adicionada automaticamente pois é necessária.'
              : 'As permissões "$names" foram adicionadas automaticamente pois são necessárias.',
          warning: false,
        );
      }
    } else {
      final result = _removeCheckingDependencies(p);
      if (result == null) {
        return _dependentNotice(p);
      }
      next = result;
    }

    selected = finalize({...next, ...fixedIds});
    return notice;
  }

  /// `removePermissionCheckDependencies` — null quando outra permissão
  /// selecionada depende desta.
  Set<String>? _removeCheckingDependencies(UserPermission p) {
    final action = PermissionRules._action(p.name);
    final category = PermissionRules._category(p.name);
    var next = {...selected}..remove(p.id);

    if (action == 'view') {
      if (_dependentsOf(p).isNotEmpty) return null;
    } else if (category == 'property') {
      final gid = _availableIdByName('gallery:$action');
      if (gid != null) next.remove(gid);
    }
    if (category == 'property' &&
        !next.any((x) => byId(x)?.name.startsWith('property:') ?? false)) {
      next = next
          .where((x) => !(byId(x)?.name.startsWith('gallery:') ?? false))
          .toSet();
    }
    return next;
  }

  List<UserPermission> _dependentsOf(UserPermission p) {
    final category = PermissionRules._category(p.name);
    final out = <UserPermission>[];
    for (final id in selected) {
      if (id == p.id) continue;
      final other = byId(id);
      if (other == null) continue;
      if (PermissionRules._category(other.name) == category &&
          PermissionRules._action(other.name) != 'view') {
        out.add(other);
      }
    }
    if (p.name == 'user:view') {
      for (final id in selected) {
        final other = byId(id);
        if (other != null &&
            other.name.startsWith('team:') &&
            !out.contains(other)) {
          out.add(other);
        }
      }
    }
    if (p.name == 'team:view') {
      for (final id in selected) {
        final other = byId(id);
        if (other != null &&
            other.name == 'kanban:manage_users' &&
            !out.contains(other)) {
          out.add(other);
        }
      }
    }
    return out;
  }

  PermissionNotice _dependentNotice(UserPermission p) {
    final deps = _dependentsOf(p);
    final names = deps.map(PermissionRules.labelOf).join(', ');
    return PermissionNotice(
      deps.length == 1
          ? 'Não é possível remover esta permissão pois "$names" depende dela. Remova "$names" primeiro.'
          : 'Não é possível remover esta permissão pois estas permissões dependem dela: "$names". Remova-as primeiro.',
    );
  }

  /// `toggleCategory`: marca/desmarca a categoria inteira.
  PermissionNotice? toggleCategory(String categoryKey) {
    if (ownerLocked) return _ownerNotice;
    final label = PermissionMeta.categoryLabel(categoryKey);
    if (_roleLocksUserPerms &&
        (categoryKey == 'user' || label == 'Gestão de Usuários')) {
      return const PermissionNotice(
        'Permissões de usuário são obrigatórias para este perfil e não podem ser editadas',
      );
    }
    if (categoryKey == 'kanban' ||
        categoryKey == 'CRM' ||
        label == 'Funil de Vendas') {
      return const PermissionNotice(
        'Permissões de Funil de Vendas são obrigatórias para corretores e não podem ser removidas',
      );
    }
    final perms = categories
        .firstWhere(
          (e) => e.key == categoryKey,
          orElse: () => MapEntry(categoryKey, const <UserPermission>[]),
        )
        .value;
    final ids = perms.map((p) => p.id).toList();
    if (ids.isEmpty) return null;
    final allOn = ids.every(selected.contains);
    if (allOn) {
      final fixed = fixedIds;
      final removable = ids.where((id) => !fixed.contains(id)).toSet();
      if (removable.isEmpty) {
        return const PermissionNotice(
          'Esta categoria contém permissões obrigatórias do sistema e não podem ser removidas',
        );
      }
      selected = selected.difference(removable);
      return null;
    }
    selected = finalize({...selected, ...ids, ...fixedIds});
    return null;
  }
}
