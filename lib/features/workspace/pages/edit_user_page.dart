import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/tag_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/admin_user_model.dart';
import '../services/admin_users_service.dart';
import '../utils/permission_rules.dart';
import '../widgets/user_access_widgets.dart';

/// Tela de **Editar Usuário** (mobile, identidade própria — sem banner, flush).
/// Paridade com o `EditUserPage` do web: dados básicos (nome, email com
/// checagem de disponibilidade, telefone, nova senha opcional), papel,
/// gestores (obrigatório p/ Colaborador), cargo/superior (admin/master), tags
/// e permissões com as regras do web (fixas, dependências, alçada do editor,
/// módulos do plano, trava do proprietário). Nomes de papel: [uaRoleLabel].
///
/// O acento da tela é a cor do papel de quem se edita (verde Colaborador,
/// azul Gestor, roxo Administrativo/Proprietário, ardósia Gerenciador);
/// salvar é verde de confirmação.
class EditUserPage extends StatefulWidget {
  const EditUserPage({super.key, required this.user});

  final AdminUser user;

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  static const double _padH = 16;
  static const double _gap = 28; // respiro entre seções

  bool _loading = true;
  bool _saving = false;
  String? _error;
  // Sem o código HTTP o erro não sabe dizer se foi permissão ou servidor.
  int _errorStatus = 0;
  Object? _errorRaw;

  PermissionSelection? _sel;
  List<AdminUser> _managers = [];

  /// Usuário exibido no hero — começa com o item da lista e é substituído pelo
  /// detalhe (`GET /admin/users/:id`), que traz `lastLogin`, documento, etc.
  late AdminUser _user;

  late String _role;
  Set<String> _selectedManagers = {};

  // Dados básicos.
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  bool _showPassword = false;
  bool _validatingEmail = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;

  // Tags.
  List<Tag> _tags = [];
  bool _tagsLoading = true;
  Set<String> _selectedTags = {};

  // Cargo / superior (só admin/master alteram — regra do back).
  String? _jobLevelId;
  String? _reportsToUserId;

  // Snapshot inicial p/ detectar alterações.
  late String _role0;
  Set<String> _perms0 = {};
  Set<String> _managers0 = {};
  Set<String> _tags0 = {};
  String _name0 = '';
  String _email0 = '';
  String _phone0 = '';
  String? _jobLevelId0;
  String? _reportsToUserId0;

  // Âncoras para as pendências da barra de salvar levarem até a seção.
  final _managersKey = GlobalKey();
  final _permissionsKey = GlobalKey();

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _accent => uaRoleTone(_role, isDark: _isDark);
  bool get _isUser => _role == 'user';
  bool get _isPrivileged => _role == 'admin' || _role == 'master';

  String get _actorRole =>
      ModuleAccessService.instance.userRole?.toLowerCase().trim() ?? '';
  bool get _elevatedActor => _actorRole == 'admin' || _actorRole == 'master';

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _role = widget.user.role.toLowerCase();
    _role0 = _role;
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus && mounted && !_loading) {
        _validateEmailRemote();
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  String _maskPhone(String? raw) {
    final v = (raw ?? '').trim();
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return digits.length <= 11 ? Masks.phone(digits) : v;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
      _errorRaw = null;
    });
    final svc = AdminUsersService.instance;
    final results = await Future.wait([
      svc.getUserById(widget.user.id),
      svc.getPermissionCatalog(),
      svc.listManagers(),
    ]);
    if (!mounted) return;
    final detailRes = results[0];
    final catalogRes = results[1];
    final managersRes = results[2];

    if (managersRes.success && managersRes.data != null) {
      _managers = (managersRes.data! as List<AdminUser>)
          .where((m) => m.id != widget.user.id)
          .toList();
    }
    if (detailRes.success && detailRes.data != null) {
      _user = detailRes.data! as AdminUser;
    }
    final u = _user;
    _role = u.role.toLowerCase();
    _selectedManagers = {...u.managerIds};
    _name.text = u.name;
    _email.text = u.email;
    _phone.text = _maskPhone(u.phone);
    _password.clear();
    _jobLevelId = u.jobLevelId;
    _reportsToUserId = u.reportsToUserId;

    PermissionSelection? sel;
    if (catalogRes.success && catalogRes.data != null) {
      final ma = ModuleAccessService.instance;
      sel = PermissionSelection(
        isEdit: true,
        catalog: catalogRes.data! as Map<String, List<UserPermission>>,
        actorRole: _actorRole,
        actorPermissionNames: ma.userPermissionNames,
        companyModules: ma.companyModules,
        baselineNames: u.permissionNames,
        editingOwner: u.owner,
        role: _role,
      );
      if (sel.ownerLocked) {
        // Proprietário travado: a grade só mostra o que ele tem.
        sel.selected = {...u.permissionIds};
      } else if (u.permissionNames.isNotEmpty) {
        sel.initialize(currentNames: u.permissionNames);
      } else {
        sel.initialize(
          currentNames: [
            for (final id in u.permissionIds) ?sel.byId(id)?.name,
          ],
        );
      }
    }
    _sel = sel;

    _role0 = _role;
    _perms0 = {...?sel?.selected};
    _managers0 = {..._selectedManagers};
    _name0 = _name.text;
    _email0 = _email.text;
    _phone0 = _phone.text;
    _jobLevelId0 = _jobLevelId;
    _reportsToUserId0 = _reportsToUserId;

    setState(() {
      _loading = false;
      if (sel == null) {
        _error =
            catalogRes.message ?? 'Não foi possível carregar as permissões.';
        _errorStatus = catalogRes.statusCode;
        _errorRaw = catalogRes.error;
      }
    });
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() => _tagsLoading = true);
    final results = await Future.wait([
      TagService.instance.getTags(),
      TagService.instance.getUserTags(widget.user.id),
    ]);
    if (!mounted) return;
    final all = results[0];
    final mine = results[1];
    setState(() {
      _tagsLoading = false;
      if (all.success && all.data != null) _tags = all.data!;
      final ids = mine.success && mine.data != null
          ? mine.data!.map((t) => t.id).toSet()
          : {..._user.tagIds};
      _selectedTags = ids;
      _tags0 = {...ids};
    });
  }

  Future<void> _validateEmailRemote() async {
    final email = _email.text.trim();
    if (email.isEmpty || !_validEmail(email) || email == _email0.trim()) {
      return;
    }
    setState(() => _validatingEmail = true);
    final ok = await AdminUsersService.instance.validateEmailAvailable(
      email,
      excludeUserId: widget.user.id,
    );
    if (!mounted) return;
    setState(() {
      _validatingEmail = false;
      if (ok == false) {
        _emailError = 'Email já está em uso';
      } else if (ok == null) {
        _emailError = 'Erro ao verificar disponibilidade';
      }
    });
  }

  bool _validEmail(String v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v);

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  bool get _dirty =>
      _role != _role0 ||
      (_isUser && !_setEquals(_selectedManagers, _managers0)) ||
      !_setEquals(_sel?.selected ?? {}, _perms0) ||
      !_setEquals(_selectedTags, _tags0) ||
      _name.text != _name0 ||
      _email.text != _email0 ||
      _phone.text != _phone0 ||
      _password.text.isNotEmpty ||
      _jobLevelId != _jobLevelId0 ||
      _reportsToUserId != _reportsToUserId0;

  bool get _managerMissing => _isUser && _selectedManagers.isEmpty;

  /// Permissões efetivas (proprietário travado mantém as que já tem).
  bool get _permissionsMissing {
    final sel = _sel;
    if (sel == null) return false;
    if (sel.ownerLocked) return _perms0.isEmpty;
    return sel.selected.isEmpty;
  }

  void _onRoleChanged(String r) {
    setState(() {
      _role = r;
      _sel?.setRole(r);
    });
  }

  /// `validateForm` do web — devolve a primeira mensagem de erro.
  String? _validate() {
    final errors = <String>[];
    _nameError = null;
    _emailError = _emailError == 'Email já está em uso' ? _emailError : null;
    _passwordError = null;

    if (_name.text.trim().isEmpty) {
      _nameError = 'Nome é obrigatório';
      errors.add(_nameError!);
    }
    final email = _email.text.trim();
    if (email.isEmpty) {
      _emailError = 'Email é obrigatório';
      errors.add(_emailError!);
    } else if (!_validEmail(email)) {
      _emailError = 'Email inválido';
      errors.add(_emailError!);
    }
    if (_password.text.isNotEmpty && _password.text.length < 6) {
      _passwordError = 'Senha deve ter pelo menos 6 caracteres';
      errors.add(_passwordError!);
    }
    if (_managerMissing) {
      errors.add(
        'Gestor é obrigatório para usuários com perfil Colaborador. Selecione ao menos um gestor.',
      );
    }
    if (_role == 'admin' && _role0 != 'admin' && !_elevatedActor) {
      errors.add(
        'Apenas Administrador ou Master podem definir a função Proprietário.',
      );
    }
    if (_permissionsMissing) {
      errors.add('É obrigatório selecionar pelo menos 1 permissão');
    }
    _sel?.mergeFixed();
    if (errors.isEmpty) return null;
    return errors.length == 1
        ? errors.first
        : '${errors.first} (${errors.length} campos precisam ser corrigidos)';
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    final problem = _validate();
    if (problem != null) {
      setState(() {});
      _snack(problem, error: true);
      return;
    }
    setState(() => _saving = true);

    // Disponibilidade do email antes de salvar (exclui o próprio usuário).
    final email = _email.text.trim();
    final available = await AdminUsersService.instance.validateEmailAvailable(
      email,
      excludeUserId: widget.user.id,
    );
    if (!mounted) return;
    if (available == false) {
      setState(() {
        _saving = false;
        _emailError = 'Email já está em uso';
      });
      _snack('Email já está em uso por outro usuário.', error: true);
      return;
    }

    final sel = _sel;
    final res = await AdminUsersService.instance.updateUser(
      widget.user.id,
      name: _name.text.trim(),
      email: email,
      phone: _phone.text != _phone0 ? _phone.text.trim() : null,
      password: _password.text.isNotEmpty ? _password.text : null,
      role: _role != _role0 ? _role : null,
      managerIds: _isUser ? _selectedManagers.toList() : null,
      // Proprietário: só o master altera as permissões — não envia.
      permissionIds:
          sel == null || sel.ownerLocked ? null : sel.idsForSave(),
      tagIds: _selectedTags.toList(),
      isAvailableForPublicSite: _user.isAvailableForPublicSite,
      includeHierarchy: _elevatedActor,
      jobLevelId: _jobLevelId,
      reportsToUserId: _reportsToUserId,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      // Permissões do próprio usuário mudaram → recarrega.
      if (ModuleAccessService.instance.userId == widget.user.id) {
        await ModuleAccessService.instance.refreshPermissions();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      _snack(res.message ?? 'Erro ao atualizar usuário', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? AppColors.status.error : AppColors.status.success,
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  // ─── Apresentação ────────────────────────────────────────────────────────

  /// Leva a rolagem até a seção (usado pelas pendências da barra).
  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.06,
    );
  }

  /// Papéis da edição (nomes via [uaRoleLabel]; o admin dono da empresa
  /// aparece como "Proprietário"). Sem alçada, o admin fica travado com o
  /// motivo — a mesma condição que o `_validate` recusaria ao salvar.
  List<UaRoleChoice> _roleChoices() {
    return [
      const UaRoleChoice('user'),
      const UaRoleChoice('manager'),
      UaRoleChoice(
        'admin',
        isOwner: _user.owner,
        lockedReason: !_elevatedActor && _role0 != 'admin'
            ? 'Seu papel não permite definir a função '
                '${uaRoleLabel('admin', isOwner: _user.owner)}.'
            : null,
      ),
      if (_role0 == 'master') const UaRoleChoice('master'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Editar usuário',
      showBottomNavigation: false,
      body: _loading
          ? _buildSkeleton()
          : Column(
              children: [
                Expanded(child: _buildContent()),
                _buildSaveBar(),
              ],
            ),
    );
  }

  // ─── Conteúdo ──────────────────────────────────────────────────────────

  Widget _buildContent() {
    final sel = _sel;
    final accent = _accent;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Theme(
      data: uaFormTheme(context, accent),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 28),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kUaMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FlushHero(user: _user, role: _role, accent: accent),

                // ── Dados básicos ────────────────────────────────────────
                const SizedBox(height: _gap),
                UaSectionHeader(
                  icon: LucideIcons.userRound,
                  label: 'Dados básicos',
                  accent: accent,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() => _nameError = null),
                  decoration: InputDecoration(
                    labelText: 'Nome completo',
                    hintText: 'Ex.: Maria Silva',
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: 12),
                UaTwoCols(
                  left: TextField(
                    controller: _email,
                    focusNode: _emailFocus,
                    enabled: !_saving,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onChanged: (_) => setState(() => _emailError = null),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: 'usuario@empresa.com',
                      errorText: _emailError,
                      suffixIcon: _validatingEmail
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SkeletonBox(
                                width: 16,
                                height: 16,
                                borderRadius: 4,
                              ),
                            )
                          : null,
                    ),
                  ),
                  right: TextField(
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneInputFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      hintText: '(00) 00000-0000',
                    ),
                  ),
                ),

                // ── Papel ────────────────────────────────────────────────
                const SizedBox(height: _gap),
                UaSectionHeader(
                  icon: LucideIcons.shieldCheck,
                  label: 'Papel',
                  accent: accent,
                ),
                const SizedBox(height: 14),
                UaRolePicker(
                  current: _role,
                  choices: _roleChoices(),
                  enabled: !_saving,
                  onChanged: _onRoleChanged,
                ),

                // ── Gestor responsável: exclusivo de Colaborador ─────────
                if (_isUser) ...[
                  const SizedBox(height: _gap),
                  UaSectionHeader(
                    key: _managersKey,
                    icon: LucideIcons.users,
                    label: 'Gestor responsável',
                    accent: accent,
                  ),
                  const SizedBox(height: 10),
                  UaRequirementLine(
                    met: !_managerMissing,
                    text: _managerMissing
                        ? 'Gestor é obrigatório para usuários com perfil '
                            'Colaborador. Selecione ao menos um gestor.'
                        : 'Gestor definido. Dá para vincular mais de um.',
                  ),
                  const SizedBox(height: 12),
                  UaManagerSelector(
                    managers: _managers,
                    selected: _selectedManagers,
                    missing: _managerMissing,
                    accent: accent,
                    enabled: !_saving,
                    onAdd: () => showUaManagerSheet(
                      context: context,
                      managers: _managers,
                      selected: _selectedManagers,
                      accent: accent,
                      onToggle: (id) => setState(() {
                        if (!_selectedManagers.remove(id)) {
                          _selectedManagers.add(id);
                        }
                      }),
                    ),
                    onRemove: (id) =>
                        setState(() => _selectedManagers.remove(id)),
                  ),
                ],

                // ── Hierarquia: só administrador/master alteram ──────────
                if (_elevatedActor) ...[
                  const SizedBox(height: _gap),
                  UaSectionHeader(
                    icon: LucideIcons.network,
                    label: 'Hierarquia',
                    accent: accent,
                  ),
                  const SizedBox(height: 10),
                  const UaHint(
                    'O cargo na escada da imobiliária e a quem esta pessoa '
                    'responde.',
                  ),
                  const SizedBox(height: 12),
                  UaHierarchyFields(
                    jobLevelId: _jobLevelId,
                    reportsToUserId: _reportsToUserId,
                    userId: widget.user.id,
                    accent: accent,
                    enabled: !_saving,
                    onChanged: (level, superior) => setState(() {
                      _jobLevelId = level;
                      _reportsToUserId = superior;
                    }),
                  ),
                ],

                // ── Segurança ────────────────────────────────────────────
                const SizedBox(height: _gap),
                UaSectionHeader(
                  icon: LucideIcons.keyRound,
                  label: 'Segurança',
                  accent: accent,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  enabled: !_saving,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() => _passwordError = null),
                  decoration: InputDecoration(
                    labelText: 'Nova senha',
                    hintText: 'Mínimo 6 caracteres',
                    errorText: _passwordError,
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                        size: 18,
                        color: secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const UaHint(
                  'Deixe em branco para manter a senha atual.',
                ),

                // ── Tags ─────────────────────────────────────────────────
                const SizedBox(height: _gap),
                UaSectionHeader(
                  icon: LucideIcons.tag,
                  label: 'Tags',
                  accent: accent,
                ),
                const SizedBox(height: 14),
                UaTagSelector(
                  tags: _tags,
                  selected: _selectedTags,
                  maxTags: 10,
                  accent: accent,
                  loading: _tagsLoading,
                  enabled: !_saving,
                  onToggle: (id) => setState(() {
                    if (!_selectedTags.remove(id)) _selectedTags.add(id);
                  }),
                ),

                // ── Permissões ───────────────────────────────────────────
                const SizedBox(height: _gap),
                UaSectionHeader(
                  key: _permissionsKey,
                  icon: LucideIcons.listChecks,
                  label: 'Permissões',
                  accent: accent,
                  trailing: sel == null
                      ? null
                      : UaCountPill(
                          text: '${uaVisibleSelectedCount(sel)} de '
                              '${sel.visibleTotal}',
                          accent: accent,
                        ),
                ),
                const SizedBox(height: 10),
                if (sel != null && sel.ownerLocked) ...[
                  const UaNoticeBanner(
                    notice: PermissionNotice(
                      'Apenas o usuário master pode alterar as permissões do '
                      'proprietário.',
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else if (_isPrivileged) ...[
                  UaNoticeBanner(
                    notice: PermissionNotice(
                      'O papel '
                      '${uaRoleLabel(_role, isOwner: _user.owner)} tem '
                      'acesso total — as permissões abaixo são ignoradas '
                      'pelo sistema.',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (sel != null) ...[
                  UaRequirementLine(
                    met: !_permissionsMissing,
                    text: _permissionsMissing
                        ? 'É obrigatório selecionar pelo menos 1 permissão.'
                        : 'As obrigatórias (com cadeado) não saem. Toque numa '
                            'categoria para ver e ajustar cada permissão.',
                  ),
                  const SizedBox(height: 8),
                ],
                if (sel == null)
                  _ErrorInline(
                    message:
                        _error ?? 'Não foi possível carregar as permissões.',
                    statusCode: _errorStatus,
                    error: _errorRaw,
                    onRetry: _bootstrap,
                  )
                else
                  UaPermissionGrid(
                    selection: sel,
                    accent: accent,
                    onOpenCategory: (category, perms) =>
                        showUaPermissionCategorySheet(
                      context: context,
                      selection: sel,
                      category: category,
                      perms: perms,
                      accent: accent,
                      onChanged: () => setState(() {}),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Save bar ─────────────────────────────────────────────────────────────

  Widget _buildSaveBar() {
    final blocked = _managerMissing;
    final canSave = _dirty && !_saving && !blocked;
    return UaSaveBar(
      saveLabel: _saving
          ? 'Salvando…'
          : (_dirty ? 'Salvar alterações' : 'Tudo salvo'),
      saving: _saving,
      onSave: canSave ? _save : null,
      cancelLabel: _dirty ? 'Descartar' : null,
      onCancel: () => Navigator.of(context).pop(),
      pendingTitle: 'Falta para salvar:',
      pending: [
        if (_managerMissing)
          UaPending('Gestor responsável', () => _scrollTo(_managersKey)),
        if (_permissionsMissing)
          UaPending('Pelo menos 1 permissão', () => _scrollTo(_permissionsKey)),
      ],
    );
  }

  // ─── Skeleton (fiel ao hero + campos + papéis) ───────────────────────────

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kUaMaxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 60, height: 60, borderRadius: 18),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 170, height: 18, borderRadius: 6),
                        SizedBox(height: 8),
                        SkeletonBox(width: 190, height: 12, borderRadius: 4),
                        SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            SkeletonBox(
                              width: 90,
                              height: 22,
                              borderRadius: 999,
                            ),
                            SkeletonBox(
                              width: 70,
                              height: 22,
                              borderRadius: 999,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const SkeletonBox(height: 46, borderRadius: 10),
              const SizedBox(height: _gap),
              const SkeletonBox(width: 140, height: 12, borderRadius: 4),
              const SizedBox(height: 14),
              const SkeletonBox(height: 50, borderRadius: 14),
              const SizedBox(height: 12),
              const SkeletonBox(height: 50, borderRadius: 14),
              const SizedBox(height: _gap),
              const SkeletonBox(width: 90, height: 12, borderRadius: 4),
              const SizedBox(height: 14),
              for (var i = 0; i < 3; i++) ...[
                const SkeletonBox(height: 60, borderRadius: 14),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Hero flush (sem card) — identidade + metadados
// ───────────────────────────────────────────────────────────────────────────

class _FlushHero extends StatelessWidget {
  const _FlushHero({
    required this.user,
    required this.role,
    required this.accent,
  });

  final AdminUser user;
  final String role;
  final Color accent;

  ({Color color, String label, IconData icon}) _presence(bool isDark) {
    if (!user.isActiveInCompany || !user.active) {
      return (
        color: isDark ? AppColors.text.textLightDarkMode : AppColors.text.textLight,
        label: 'Desativado',
        icon: LucideIcons.ban,
      );
    }
    if (user.neverLoggedIn) {
      return (
        color: isDark
            ? AppColors.status.warningDarkMode
            : AppColors.message.warningText,
        label: 'Nunca acessou',
        icon: LucideIcons.clock,
      );
    }
    return (
      color: isDark ? AppColors.status.successDarkMode : AppColors.status.success,
      label: 'Ativo',
      icon: LucideIcons.check,
    );
  }

  String? _maskedDoc() {
    final raw = user.document;
    if (raw == null || raw.trim().isEmpty) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length < 2) return '***.***.***-**';
    return '***.***.***-${d.substring(d.length - 2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final presence = _presence(isDark);

    final lastLogin = user.lastLoginAt != null
        ? DateFormat("d 'de' MMM · HH:mm", 'pt_BR')
            .format(user.lastLoginAt!.toLocal())
        : 'Nunca';
    final created = user.createdAt != null
        ? DateFormat("d 'de' MMM yyyy", 'pt_BR').format(user.createdAt!.toLocal())
        : '—';
    final phone = (user.phone?.trim().isNotEmpty == true)
        ? user.phone!.trim()
        : 'Não informado';

    final meta = <Widget>[
      _MetaDatum(icon: LucideIcons.phone, label: 'TELEFONE', value: phone),
      _MetaDatum(
        icon: LucideIcons.fingerprint,
        label: 'CPF',
        value: _maskedDoc() ?? 'Não informado',
        monospace: _maskedDoc() != null,
      ),
      // "Nunca" já vem sinalizado na pílula âmbar do estado — aqui fica na
      // tinta de texto (âmbar como texto não passa em contraste no claro).
      _MetaDatum(
        icon: LucideIcons.clock,
        label: 'ÚLTIMO ACESSO',
        value: lastLogin,
      ),
      _MetaDatum(
        icon: LucideIcons.calendar,
        label: 'MEMBRO DESDE',
        value: created,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UaAvatar(
              name: user.name,
              url: user.avatar,
              tone: accent,
              size: 60,
              radius: 18,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name.isEmpty ? 'Sem nome' : user.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.5,
                      height: 1.1,
                      fontSize: 20,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(LucideIcons.mail, size: 12, color: secondary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Pill(
                        label: uaRoleLabel(role, isOwner: user.owner),
                        color: accent,
                        icon: uaRoleIcon(role),
                      ),
                      _Pill(
                        label: presence.label,
                        color: presence.color,
                        icon: presence.icon,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Metadados em faixa com filetes: 4 em linha na tela larga, 2×2 no
        // celular (altura intrínseca — sem caixa de tamanho fixo).
        LayoutBuilder(
          builder: (context, c) {
            final perRow = c.maxWidth >= 560 ? 4 : 2;
            final hairline = ThemeHelpers.borderLightColor(context);
            final rows = <Widget>[];
            for (var i = 0; i < meta.length; i += perRow) {
              final slice = meta.sublist(
                i,
                i + perRow > meta.length ? meta.length : i + perRow,
              );
              rows.add(
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: hairline)),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = 0; j < slice.length; j++) ...[
                          if (j > 0)
                            Container(
                              width: 1,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              color: hairline,
                            ),
                          Expanded(child: slice[j]),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rows,
                Container(height: 1, color: hairline),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Reuso: pílula / meta / erro
// ───────────────────────────────────────────────────────────────────────────

/// Pílula de papel/estado: tom no fundo, na borda e no ícone; texto na tinta
/// de texto (contraste garantido nos dois temas).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaDatum extends StatelessWidget {
  const _MetaDatum({
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final valueText = Text(
      value,
      maxLines: 1,
      softWrap: false,
      overflow: monospace ? TextOverflow.visible : TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: textColor,
        letterSpacing: monospace ? 0.4 : -0.1,
        fontFamily: monospace ? 'monospace' : null,
        height: 1.15,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: secondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: secondary,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // CPF mascarado: encolhe para caber — os 2 dígitos finais são a
        // única informação e não podem sumir no "…".
        monospace
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: valueText,
              )
            : valueText,
      ],
    );
  }
}

class _ErrorInline extends StatelessWidget {
  const _ErrorInline({
    required this.message,
    required this.onRetry,
    this.statusCode = 0,
    this.error,
  });
  final String message;
  final int statusCode;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return AppErrorState.fromApi(
      message: message,
      statusCode: statusCode,
      error: error,
      onRetry: onRetry,
      dense: true,
    );
  }
}
