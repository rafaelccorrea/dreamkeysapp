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

/// Acento por papel — torna a subtela coerente com QUEM se edita (Corretor,
/// Gerente, Admin, Master). O vermelho da marca fica reservado para a ação
/// principal (Salvar). Ver memória `color-strategy-subscreens`.
/// Cores por papel — alinhadas ao hero da tela de Usuários (fonte de verdade):
/// Corretor = verde, Gestor = azul/indigo, Admin = roxo. O conforto vem do
/// uso TONAL (sem preenchimento neon) no segmented. Ver
/// memória color-strategy-subscreens.
Color _roleAccent(String role, bool isDark) {
  switch (role) {
    case 'master':
      // Distinto do Admin (roxo mais profundo).
      return isDark ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9);
    case 'admin':
      return isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED); // roxo
    case 'manager':
      return isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1); // azul
    case 'user':
    default:
      return isDark ? const Color(0xFF34D399) : const Color(0xFF059669); // verde
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'master':
      return 'Master';
    case 'admin':
      return 'Administrador';
    case 'manager':
      return 'Gestor';
    default:
      return 'Corretor';
  }
}

/// Tela de **Editar Usuário** (mobile, identidade própria — sem banner, flush).
/// Paridade com o `EditUserPage` do web: dados básicos (nome, email com
/// checagem de disponibilidade, telefone, nova senha opcional), papel,
/// gestores (obrigatório p/ corretor), cargo/superior (admin/master), tags e
/// permissões com as regras do web (fixas, dependências, alçada do editor,
/// módulos do plano, trava do proprietário).
class EditUserPage extends StatefulWidget {
  const EditUserPage({super.key, required this.user});

  final AdminUser user;

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  static const double _padH = 20;
  static const double _gap = 20; // espaçamento entre seções (enxuto)

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

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _accent => _roleAccent(_role, _isDark);
  Color get _brandRed =>
      _isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
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

  InputDecoration _dec(
    String label, {
    String? hint,
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        errorMaxLines: 2,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: ThemeHelpers.cardBackgroundColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accent, width: 1.6),
        ),
      );

  /// Duas colunas quando cabe (largura e escala de fonte); senão empilha.
  Widget _twoCols(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, c) {
        final fits = c.maxWidth >= 360 &&
            MediaQuery.textScalerOf(context).scale(14) <= 16;
        if (!fits) {
          return Column(children: [a, const SizedBox(height: 12), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  Widget _buildContent() {
    final sel = _sel;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 20),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _FlushHero(user: _user, role: _role, accent: _accent),
        const SizedBox(height: _gap),
        _SectionLabel(
          icon: LucideIcons.userRound,
          label: 'DADOS BÁSICOS',
          accent: _accent,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() => _nameError = null),
          decoration: _dec(
            'Nome completo',
            hint: 'Ex: Maria Silva',
            errorText: _nameError,
          ),
        ),
        const SizedBox(height: 12),
        _twoCols(
          TextField(
            controller: _email,
            focusNode: _emailFocus,
            enabled: !_saving,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) => setState(() => _emailError = null),
            decoration: _dec(
              'Email',
              hint: 'usuario@empresa.com',
              errorText: _emailError,
              suffixIcon: _validatingEmail
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SkeletonBox(width: 16, height: 16, borderRadius: 4),
                    )
                  : null,
            ),
          ),
          TextField(
            controller: _phone,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
            onChanged: (_) => setState(() {}),
            decoration: _dec('Telefone', hint: '(00) 00000-0000'),
          ),
        ),
        const SizedBox(height: _gap),
        // Sem título (só "Permissões" tem): o segmented já é autoexplicativo.
        _RoleSegmented(
          current: _role,
          includeMaster: _role0 == 'master',
          onChanged: _onRoleChanged,
        ),
        // Gestor responsável: exclusivo de corretor.
        if (_isUser) ...[
          const SizedBox(height: 14),
          UaManagerSelector(
            managers: _managers,
            selected: _selectedManagers,
            missing: _managerMissing,
            accent: _accent,
            onAdd: () => showUaManagerSheet(
              context: context,
              managers: _managers,
              selected: _selectedManagers,
              accent: _accent,
              onToggle: (id) => setState(() {
                if (!_selectedManagers.remove(id)) _selectedManagers.add(id);
              }),
            ),
            onRemove: (id) => setState(() => _selectedManagers.remove(id)),
          ),
        ],
        // Cargo e superior: só administrador/master alteram (regra do back).
        if (_elevatedActor) ...[
          const SizedBox(height: _gap),
          _SectionLabel(
            icon: LucideIcons.network,
            label: 'HIERARQUIA',
            accent: _accent,
          ),
          const SizedBox(height: 12),
          UaHierarchyFields(
            jobLevelId: _jobLevelId,
            reportsToUserId: _reportsToUserId,
            userId: widget.user.id,
            accent: _accent,
            enabled: !_saving,
            onChanged: (level, superior) => setState(() {
              _jobLevelId = level;
              _reportsToUserId = superior;
            }),
          ),
        ],
        const SizedBox(height: _gap),
        _SectionLabel(
          icon: LucideIcons.keyRound,
          label: 'SEGURANÇA',
          accent: _accent,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !_saving,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() => _passwordError = null),
          decoration: _dec(
            'Nova senha',
            hint: 'Deixe em branco para manter a senha atual',
            errorText: _passwordError,
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 18,
                color: secondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: _gap),
        _SectionLabel(
          icon: LucideIcons.tag,
          label: 'TAGS',
          accent: _accent,
        ),
        const SizedBox(height: 12),
        UaTagSelector(
          tags: _tags,
          selected: _selectedTags,
          maxTags: 10,
          accent: _accent,
          loading: _tagsLoading,
          enabled: !_saving,
          onToggle: (id) => setState(() {
            if (!_selectedTags.remove(id)) _selectedTags.add(id);
          }),
        ),
        const SizedBox(height: _gap),
        _SectionLabel(
          icon: LucideIcons.shieldCheck,
          label: 'PERMISSÕES',
          accent: _accent,
          trailing: sel == null
              ? null
              : _CountPill(
                  text: '${sel.selected.length}/${sel.visibleTotal}',
                  color: _accent,
                ),
        ),
        const SizedBox(height: 11),
        if (sel != null && sel.ownerLocked) ...[
          const UaNoticeBanner(
            notice: PermissionNotice(
              'Apenas o usuário master pode alterar as permissões do proprietário.',
            ),
          ),
          const SizedBox(height: 11),
        ] else if (_isPrivileged) ...[
          _PrivilegedNote(role: _role),
          const SizedBox(height: 11),
        ],
        if (_permissionsMissing) ...[
          const UaNoticeBanner(
            notice: PermissionNotice(
              'É obrigatório selecionar pelo menos 1 permissão',
            ),
          ),
          const SizedBox(height: 11),
        ],
        if (sel == null)
          _ErrorInline(
            message: _error ?? 'Não foi possível carregar as permissões.',
            statusCode: _errorStatus,
            error: _errorRaw,
            onRetry: _bootstrap,
          )
        else
          UaPermissionGrid(
            selection: sel,
            accent: _accent,
            horizontalPadding: _padH,
            onOpenCategory: (category, perms) => showUaPermissionCategorySheet(
              context: context,
              selection: sel,
              category: category,
              perms: perms,
              accent: _accent,
              onChanged: () => setState(() {}),
            ),
          ),
      ],
    );
  }

  // ─── Save bar ─────────────────────────────────────────────────────────────

  Widget _buildSaveBar() {
    final blocked = _managerMissing;
    final canSave = _dirty && !_saving && !blocked;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          _padH, 12, _padH, 12 + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          if (_dirty) ...[
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Descartar'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: _brandRed,
                disabledBackgroundColor:
                    ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.check, size: 18),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : blocked
                        ? 'Selecione um gestor'
                        : (_dirty ? 'Salvar alterações' : 'Tudo salvo'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    letterSpacing: 0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Skeleton ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 20),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Row(
          children: [
            SkeletonBox(width: 60, height: 60, borderRadius: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 160, height: 16, borderRadius: 6),
                  SizedBox(height: 8),
                  SkeletonBox(width: 200, height: 12, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SkeletonBox(width: double.infinity, height: 52, borderRadius: 14),
        const SizedBox(height: 22),
        SkeletonBox(width: 120, height: 11, borderRadius: 999),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            6,
            (_) => SkeletonBox(
              width: (MediaQuery.sizeOf(context).width - (_padH * 2) - 12) / 2,
              height: 84,
              borderRadius: 16,
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Hero flush (sem card) — identidade + metadados
// ───────────────────────────────────────────────────────────────────────────

class _FlushHero extends StatelessWidget {
  const _FlushHero({required this.user, required this.role, required this.accent});

  final AdminUser user;
  final String role;
  final Color accent;

  ({Color color, String label, IconData icon}) _presence() {
    if (!user.isActiveInCompany || !user.active) {
      return (color: const Color(0xFFA1A1AA), label: 'Desativado', icon: LucideIcons.minus);
    }
    if (user.neverLoggedIn) {
      return (color: const Color(0xFFF59E0B), label: 'Nunca acessou', icon: LucideIcons.clock);
    }
    return (color: const Color(0xFF10B981), label: 'Ativo', icon: LucideIcons.check);
  }

  String? _maskedDoc() {
    final raw = user.document;
    if (raw == null || raw.trim().isEmpty) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length < 2) return '***.***.***-**';
    return '***.***.***-${d.substring(d.length - 2)}';
  }

  String _initials() {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final presence = _presence();
    final hasPhoto = (user.avatar ?? '').trim().isNotEmpty;
    final deep = HSLColor.fromColor(accent)
        .withLightness(
            (HSLColor.fromColor(accent).lightness * 0.78).clamp(0.0, 1.0))
        .toColor();

    final lastLogin = user.lastLoginAt != null
        ? DateFormat("d 'de' MMM · HH:mm", 'pt_BR')
            .format(user.lastLoginAt!.toLocal())
        : 'Nunca';
    final created = user.createdAt != null
        ? DateFormat("d 'de' MMM yyyy", 'pt_BR').format(user.createdAt!.toLocal())
        : '—';

    final initialsFallback = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, deep],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 21,
        ),
      ),
    );
    final avatarInner = hasPhoto
        ? Image.network(
            user.avatar!,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => initialsFallback,
            loadingBuilder: (_, child, prog) =>
                prog == null ? child : initialsFallback,
          )
        : initialsFallback;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.32)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarInner,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: presence.color,
                        border: Border.all(color: cardColor, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: presence.color.withValues(alpha: 0.55),
                            blurRadius: 6,
                            spreadRadius: 0.4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name.isEmpty ? '—' : user.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.5,
                      height: 1.05,
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
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MiniBadge(
                        label: _roleLabel(role),
                        color: accent,
                        icon: LucideIcons.shieldCheck,
                        isDark: isDark,
                      ),
                      _MiniBadge(
                        label: presence.label,
                        color: presence.color,
                        icon: presence.icon,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Divider(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.9)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetaDatum(
                icon: LucideIcons.phone,
                label: 'TELEFONE',
                value: (user.phone?.trim().isNotEmpty == true)
                    ? user.phone!.trim()
                    : '—',
              ),
            ),
            _metaDivider(context),
            Expanded(
              child: _MetaDatum(
                icon: LucideIcons.fingerprint,
                label: 'CPF',
                value: _maskedDoc() ?? '—',
                monospace: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetaDatum(
                icon: LucideIcons.clock,
                label: 'ÚLTIMO ACESSO',
                value: lastLogin,
                valueColor: user.neverLoggedIn ? const Color(0xFFF59E0B) : null,
              ),
            ),
            _metaDivider(context),
            Expanded(
              child: _MetaDatum(
                icon: LucideIcons.calendar,
                label: 'MEMBRO DESDE',
                value: created,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metaDivider(BuildContext context) => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
      );
}

// ───────────────────────────────────────────────────────────────────────────
// Section label (flush, com filete + trailing)
// ───────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.accent,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 12, color: accent),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.8),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Papel — segmented (cada papel na sua cor)
// ───────────────────────────────────────────────────────────────────────────

class _RoleSegmented extends StatelessWidget {
  const _RoleSegmented({
    required this.current,
    required this.includeMaster,
    required this.onChanged,
  });

  final String current;
  final bool includeMaster;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = <({String value, String label, IconData icon})>[
      (value: 'user', label: 'Corretor', icon: LucideIcons.user),
      (value: 'manager', label: 'Gestor', icon: LucideIcons.briefcase),
      (value: 'admin', label: 'Admin', icon: LucideIcons.shieldCheck),
      if (includeMaster)
        (value: 'master', label: 'Master', icon: LucideIcons.crown),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: _RoleChip(
                label: it.label,
                icon: it.icon,
                selected: current == it.value,
                color: _roleAccent(it.value, isDark),
                onTap: () => onChanged(it.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? color : ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          // Tonal suave (sem preenchimento saturado nem brilho) — conforto.
          color: selected
              ? color.withValues(alpha: isDark ? 0.20 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: isDark ? 0.5 : 0.38)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Reuso: badges / meta / notas
// ───────────────────────────────────────────────────────────────────────────

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.label,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.36 : 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.2,
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
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool monospace;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
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
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
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
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: valueColor ?? textColor,
            letterSpacing: monospace ? 0.4 : -0.1,
            fontFamily: monospace ? 'monospace' : null,
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PrivilegedNote extends StatelessWidget {
  const _PrivilegedNote({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${role == 'master' ? 'Master' : 'Administradores'} têm acesso '
              'total — as permissões abaixo são ignoradas pelo sistema.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tone,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
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
