import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../inspections/widgets/cpf_cnpj_text_field.dart';
import '../models/admin_user_model.dart';
import '../services/admin_users_service.dart';
import '../utils/permission_rules.dart';
import '../widgets/user_access_widgets.dart';

/// Criar usuário — paridade com o `CreateUserPage` do web num passo só:
/// dados básicos (email e CPF/CNPJ checados antes do POST), senha inicial
/// (com gerador), papel, gestores (obrigatório para Colaborador), cargo e
/// superior (admin/master), tags e permissões com as regras do web (fixas,
/// dependências, alçada de quem cria, módulos do plano). Tudo vai no mesmo
/// `POST /admin/users` — o back recusa Colaborador sem gestor e usuário sem
/// permissão, então não existe "configurar depois".
///
/// Layout: seções com cabeçalho flush; o que é obrigatório aparece como
/// linha de requisito na própria seção e como pendência tocável na barra
/// de salvar — a pessoa vê o que falta ANTES de tocar em "Criar usuário".
class CreateUserPage extends StatefulWidget {
  const CreateUserPage({super.key});

  @override
  State<CreateUserPage> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUserPage> {
  static const double _padH = 16;
  static const double _gap = 28; // respiro entre seções

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();

  // Âncoras para as pendências da barra de salvar levarem até a seção.
  final _managersKey = GlobalKey();
  final _permissionsKey = GlobalKey();

  String _role = 'user';
  bool _showPassword = false;
  bool _saving = false;

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _documentError;
  String? _phoneError;

  // Acesso.
  bool _loadingAccess = true;
  PermissionSelection? _sel;
  String? _accessError;
  int _accessErrorStatus = 0;
  Object? _accessErrorRaw;
  List<AdminUser> _managers = [];
  final Set<String> _selectedManagers = {};

  // Tags.
  List<Tag> _tags = [];
  bool _tagsLoading = true;
  final Set<String> _selectedTags = {};

  // Cargo / superior.
  String? _jobLevelId;
  String? _reportsToUserId;

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  String _myRole() =>
      ModuleAccessService.instance.userRole?.toLowerCase().trim() ?? '';

  bool get _elevated {
    final r = _myRole();
    return r == 'admin' || r == 'master';
  }

  bool get _managerMissing => _role == 'user' && _selectedManagers.isEmpty;

  @override
  void initState() {
    super.initState();
    _loadAccess();
    _loadTags();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _document.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadAccess() async {
    setState(() {
      _loadingAccess = true;
      _accessError = null;
      _accessErrorStatus = 0;
      _accessErrorRaw = null;
    });
    final svc = AdminUsersService.instance;
    final results = await Future.wait([
      svc.getPermissionCatalog(),
      svc.listManagers(),
    ]);
    if (!mounted) return;
    final catalogRes = results[0];
    final managersRes = results[1];
    setState(() {
      _loadingAccess = false;
      if (managersRes.success && managersRes.data != null) {
        _managers = managersRes.data! as List<AdminUser>;
      }
      if (catalogRes.success && catalogRes.data != null) {
        final ma = ModuleAccessService.instance;
        final sel = PermissionSelection(
          isEdit: false,
          catalog: catalogRes.data! as Map<String, List<UserPermission>>,
          actorRole: _myRole(),
          actorPermissionNames: ma.userPermissionNames,
          companyModules: ma.companyModules,
          role: _role,
        )..initialize();
        _sel = sel;
      } else {
        _accessError =
            catalogRes.message ?? 'Não foi possível carregar as permissões.';
        _accessErrorStatus = catalogRes.statusCode;
        _accessErrorRaw = catalogRes.error;
      }
    });
  }

  Future<void> _loadTags() async {
    final res = await TagService.instance.getTags();
    if (!mounted) return;
    setState(() {
      _tagsLoading = false;
      if (res.success && res.data != null) _tags = res.data!;
    });
  }

  /// Gera senha forte de 10 caracteres (letras, números e símbolo).
  void _generatePassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789@#%&*';
    final rnd = Random.secure();
    final pwd = List.generate(10, (_) => chars[rnd.nextInt(chars.length)]);
    setState(() {
      _password.text = pwd.join();
      _showPassword = true;
      _passwordError = null;
    });
  }

  bool _validEmail(String v) => RegExp(r'\S+@\S+\.\S+').hasMatch(v);

  void _onRoleChanged(String role) {
    setState(() {
      _role = role;
      _sel?.setRole(role);
    });
  }

  /// `validateForm` do web — devolve a primeira mensagem (ou null).
  String? _validate() {
    final errors = <String>[];
    _nameError = null;
    _emailError = null;
    _passwordError = null;
    _documentError = null;
    _phoneError = null;

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
    if (_password.text.trim().isEmpty) {
      _passwordError = 'Senha é obrigatória';
      errors.add(_passwordError!);
    } else if (_password.text.length < 6) {
      _passwordError = 'Senha deve ter pelo menos 6 caracteres';
      errors.add(_passwordError!);
    }
    if (_document.text.trim().isEmpty) {
      _documentError = 'CPF/CNPJ é obrigatório';
      errors.add(_documentError!);
    }
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length < 10 || phoneDigits.length > 13) {
      _phoneError = 'Telefone é obrigatório (DDD + número, 10 a 13 dígitos)';
      errors.add(_phoneError!);
    }
    if (_managerMissing) {
      errors.add('Selecione ao menos um gestor para o Colaborador');
    }
    if (_role == 'admin' && !_elevated) {
      errors.add(
        'Apenas Administrador ou Master podem criar usuários com função Proprietário.',
      );
    }
    final sel = _sel;
    if (sel == null) {
      errors.add('Não foi possível carregar as permissões.');
    } else {
      if (sel.selected.isEmpty) {
        errors.add('É obrigatório selecionar pelo menos 1 permissão');
      }
      sel.mergeFixed();
    }
    return errors.isEmpty ? null : errors.first;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final problem = _validate();
    if (problem != null) {
      HapticFeedback.mediumImpact();
      setState(() {});
      _snack(problem, error: true);
      return;
    }

    final name = _name.text.trim();
    final email = _email.text.trim();
    // Letras + números: o CNPJ alfanumérico perde as letras com `\D`.
    final documentDigits = Masks.unmaskCnpj(_document.text);
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');

    setState(() => _saving = true);

    // Disponibilidade de email e CPF/CNPJ antes do POST (paridade web).
    final results = await Future.wait([
      AdminUsersService.instance.validateEmailAvailable(email),
      AdminUsersService.instance.validateDocumentAvailable(documentDigits),
    ]);
    if (!mounted) return;
    final emailOk = results[0];
    final docOk = results[1];
    if (emailOk == false || docOk == false) {
      setState(() {
        _saving = false;
        if (emailOk == false) _emailError = 'Email já está em uso';
        if (docOk == false) _documentError = 'CPF/CNPJ já está em uso';
      });
      return;
    }

    final res = await AdminUsersService.instance.createUser({
      'name': name,
      'email': email,
      'password': _password.text,
      'document': documentDigits,
      'phone': phoneDigits,
      'role': _role,
      'permissionIds': _sel!.idsForSave(),
      'tagIds': _selectedTags.toList(),
      if (_selectedManagers.isNotEmpty)
        'managerIds': _selectedManagers.toList(),
      if (_elevated && _jobLevelId != null) 'jobLevelId': _jobLevelId,
      if (_elevated && _reportsToUserId != null)
        'reportsToUserId': _reportsToUserId,
    });
    if (!mounted) return;
    setState(() => _saving = false);

    if (!res.success || res.data == null) {
      _snack(res.message ?? 'Erro ao criar usuário', error: true);
      return;
    }
    _snack('Usuário criado com sucesso!');
    Navigator.of(context).pop(true);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            error ? AppColors.status.error : AppColors.status.success,
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

  /// O que ainda impede o POST — mesmas condições do `_validate`, mostradas
  /// antes do toque em salvar.
  List<UaPending> _pending() {
    final sel = _sel;
    return [
      if (_managerMissing)
        UaPending('Gestor responsável', () => _scrollTo(_managersKey)),
      if (sel != null && sel.selected.isEmpty)
        UaPending('Pelo menos 1 permissão', () => _scrollTo(_permissionsKey)),
    ];
  }

  /// Papéis criáveis: qualquer gestor cria Colaborador; admin/master também
  /// criam Gestor e Proprietário (paridade com o web). O que a pessoa não
  /// pode criar aparece travado, com o motivo. Nomes: [uaRoleLabel] — aqui o
  /// admin é "Proprietário", como o cartão do `CreateUserPage` do web.
  List<UaRoleChoice> _roleChoices() {
    final myRole = _myRole();
    final elevated = _elevated;
    return [
      const UaRoleChoice('user'),
      UaRoleChoice(
        'manager',
        lockedReason: elevated || myRole == 'manager'
            ? null
            : 'Seu papel não permite cadastrar usuário '
                '${uaRoleLabel('manager')}.',
      ),
      UaRoleChoice(
        'admin',
        isOwner: true,
        lockedReason: elevated
            ? null
            : 'Seu papel não permite cadastrar usuário '
                '${uaRoleLabel('admin', isOwner: true)}.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final elevated = _elevated;
    final sel = _sel;
    final accent = _accent;

    return AppScaffold(
      title: 'Novo usuário',
      showBottomNavigation: false,
      body: Column(
        children: [
          Expanded(
            child: Theme(
              data: uaFormTheme(context, accent),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(_padH, 18, _padH, 28),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kUaMaxContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Dados básicos ────────────────────────────────
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
                          textInputAction: TextInputAction.next,
                          onChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Nome completo *',
                            hintText: 'Ex.: Maria Silva',
                            errorText: _nameError,
                          ),
                        ),
                        const SizedBox(height: 12),
                        UaTwoCols(
                          left: TextField(
                            controller: _email,
                            enabled: !_saving,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Email *',
                              hintText: 'nome@empresa.com',
                              errorText: _emailError,
                            ),
                            onChanged: (_) {
                              if (_emailError != null) {
                                setState(() => _emailError = null);
                              }
                            },
                          ),
                          right: TextField(
                            controller: _phone,
                            enabled: !_saving,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [PhoneInputFormatter()],
                            onChanged: (_) {
                              if (_phoneError != null) {
                                setState(() => _phoneError = null);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Telefone *',
                              hintText: '(00) 00000-0000',
                              errorText: _phoneError,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // CPF/CNPJ em linha própria: o campo traz o rótulo
                        // em cima e desalinharia a dupla de colunas.
                        CpfCnpjTextField(
                          controller: _document,
                          enabled: !_saving,
                          label: 'CPF/CNPJ *',
                          errorText: _documentError,
                          onChanged: (_) {
                            if (_documentError != null) {
                              setState(() => _documentError = null);
                            }
                          },
                        ),

                        // ── Senha inicial ────────────────────────────────
                        const SizedBox(height: _gap),
                        UaSectionHeader(
                          icon: LucideIcons.keyRound,
                          label: 'Senha inicial',
                          accent: accent,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _password,
                          enabled: !_saving,
                          obscureText: !_showPassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          onChanged: (_) {
                            if (_passwordError != null) {
                              setState(() => _passwordError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Senha *',
                            hintText: 'Mínimo 6 caracteres',
                            errorText: _passwordError,
                            suffixIcon: IconButton(
                              tooltip: _showPassword
                                  ? 'Ocultar senha'
                                  : 'Mostrar senha',
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                              icon: Icon(
                                _showPassword
                                    ? LucideIcons.eyeOff
                                    : LucideIcons.eye,
                                size: 18,
                                color: secondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              child: UaHint(
                                'Compartilhe a senha com a pessoa; ela pode '
                                'trocá-la no primeiro acesso.',
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: _saving ? null : _generatePassword,
                              style: TextButton.styleFrom(
                                foregroundColor: uaInk(context, accent),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 40),
                              ),
                              icon: const Icon(LucideIcons.sparkles, size: 16),
                              label: const Text(
                                'Gerar senha',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),

                        // ── Papel ────────────────────────────────────────
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

                        // ── Gestor responsável (só Colaborador) ─────────
                        if (_role == 'user') ...[
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
                                ? 'Gestor é obrigatório para usuários com '
                                    'perfil Colaborador. Selecione ao menos '
                                    'um gestor.'
                                : 'Gestor definido. Dá para vincular mais de '
                                    'um.',
                          ),
                          const SizedBox(height: 12),
                          if (_loadingAccess)
                            const SkeletonBox(height: 62, borderRadius: 14)
                          else
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

                        // ── Hierarquia (admin/master — regra do back) ───
                        if (elevated) ...[
                          const SizedBox(height: _gap),
                          UaSectionHeader(
                            icon: LucideIcons.network,
                            label: 'Hierarquia',
                            accent: accent,
                          ),
                          const SizedBox(height: 10),
                          const UaHint(
                            'Opcional: o cargo na escada da imobiliária e a '
                            'quem esta pessoa responde.',
                          ),
                          const SizedBox(height: 12),
                          UaHierarchyFields(
                            jobLevelId: _jobLevelId,
                            reportsToUserId: _reportsToUserId,
                            accent: accent,
                            enabled: !_saving,
                            onChanged: (level, superior) => setState(() {
                              _jobLevelId = level;
                              _reportsToUserId = superior;
                            }),
                          ),
                        ],

                        // ── Tags ─────────────────────────────────────────
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
                          maxTags: 5,
                          accent: accent,
                          loading: _tagsLoading,
                          enabled: !_saving,
                          onToggle: (id) => setState(() {
                            if (!_selectedTags.remove(id)) _selectedTags.add(id);
                          }),
                        ),

                        // ── Permissões ───────────────────────────────────
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
                        if (sel != null) ...[
                          UaRequirementLine(
                            met: sel.selected.isNotEmpty,
                            text: sel.selected.isNotEmpty
                                ? 'As obrigatórias (com cadeado) já vêm '
                                    'marcadas. Toque numa categoria para ver '
                                    'e ajustar cada permissão.'
                                : 'É obrigatório selecionar pelo menos 1 '
                                    'permissão.',
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_role == 'admin') ...[
                          UaNoticeBanner(
                            notice: PermissionNotice(
                              'O papel '
                              '${uaRoleLabel('admin', isOwner: true)} tem acesso '
                              'total — as permissões abaixo não limitam o '
                              'que ele pode fazer.',
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_loadingAccess)
                          _permissionSkeleton()
                        else if (sel == null)
                          AppErrorState.fromApi(
                            message: _accessError ??
                                'Não foi possível carregar as permissões.',
                            statusCode: _accessErrorStatus,
                            error: _accessErrorRaw,
                            onRetry: _loadAccess,
                            dense: true,
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
            ),
          ),
          UaSaveBar(
            saveLabel: _saving ? 'Criando…' : 'Criar usuário',
            saving: _saving,
            onSave: _saving || _loadingAccess ? null : _submit,
            cancelLabel: 'Cancelar',
            onCancel: () => Navigator.of(context).pop(),
            pendingTitle: 'Falta para criar:',
            pending: _pending(),
          ),
        ],
      ),
    );
  }

  /// Skeleton fiel às linhas de categoria (ícone, nome, barra).
  Widget _permissionSkeleton() {
    return Column(
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const SkeletonBox(width: 36, height: 36, borderRadius: 11),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                      width: 120.0 + (i % 3) * 24,
                      height: 13,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 10),
                    const SkeletonBox(height: 4, borderRadius: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
