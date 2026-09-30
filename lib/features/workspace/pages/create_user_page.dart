import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/tag_service.dart';
import '../../../shared/utils/input_formatters.dart';
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
/// (com gerador), papel, gestores (obrigatório para corretor), cargo e
/// superior (admin/master), tags e permissões com as regras do web (fixas,
/// dependências, alçada de quem cria, módulos do plano). Tudo vai no mesmo
/// `POST /admin/users` — o back recusa corretor sem gestor e usuário sem
/// permissão, então não existe "configurar depois".
class CreateUserPage extends StatefulWidget {
  const CreateUserPage({super.key});

  @override
  State<CreateUserPage> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUserPage> {
  static const double _padH = 16;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();

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
    final documentDigits = _document.text.replaceAll(RegExp(r'\D'), '');
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

  InputDecoration _dec(
    String label, {
    String? hint,
    String? errorText,
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        errorMaxLines: 2,
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

  Widget _sectionLabel(IconData icon, String label, {Widget? trailing}) => Row(
        children: [
          Icon(icon, size: 14, color: _accent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          ?trailing,
        ],
      );

  Widget _hint(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textSecondaryColor(context),
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

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Papéis criáveis: qualquer gestor cria corretor; admin/master também
    // criam gestores e proprietários (paridade com o web).
    final myRole = _myRole();
    final elevated = _elevated;
    final sel = _sel;

    return AppScaffold(
      title: 'Novo usuário',
      showBottomNavigation: false,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 20),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _sectionLabel(LucideIcons.userRound, 'Dados básicos'),
                const SizedBox(height: 10),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                  decoration: _dec('Nome completo *', errorText: _nameError),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  enabled: !_saving,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _dec('Email *', errorText: _emailError),
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _twoCols(
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
                  TextField(
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneInputFormatter()],
                    onChanged: (_) {
                      if (_phoneError != null) {
                        setState(() => _phoneError = null);
                      }
                    },
                    decoration: _dec('Telefone *', errorText: _phoneError),
                  ),
                ),
                const SizedBox(height: 18),
                _sectionLabel(LucideIcons.keyRound, 'Senha inicial'),
                const SizedBox(height: 10),
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
                  decoration: _dec(
                    'Senha *',
                    hint: 'Mínimo 6 caracteres',
                    errorText: _passwordError,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Gerar senha forte',
                          onPressed: _saving ? null : _generatePassword,
                          icon: Icon(
                            LucideIcons.sparkles,
                            size: 18,
                            color: _accent,
                          ),
                        ),
                        IconButton(
                          tooltip:
                              _showPassword ? 'Ocultar senha' : 'Mostrar senha',
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _hint(
                  'Compartilhe a senha com o colaborador; ele pode trocá-la no primeiro acesso.',
                ),
                const SizedBox(height: 18),
                _sectionLabel(LucideIcons.shieldCheck, 'Papel'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _roleChip('user', 'Corretor', LucideIcons.userRound),
                    if (elevated || myRole == 'manager')
                      _roleChip('manager', 'Gestor', LucideIcons.users),
                    if (elevated)
                      _roleChip('admin', 'Proprietário', LucideIcons.crown),
                  ],
                ),
                if (_role == 'user') ...[
                  const SizedBox(height: 18),
                  _sectionLabel(LucideIcons.users, 'Gestores responsáveis'),
                  const SizedBox(height: 10),
                  if (_loadingAccess)
                    const SkeletonBox(width: 150, height: 36, borderRadius: 999)
                  else
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
                          if (!_selectedManagers.remove(id)) {
                            _selectedManagers.add(id);
                          }
                        }),
                      ),
                      onRemove: (id) =>
                          setState(() => _selectedManagers.remove(id)),
                    ),
                ],
                // Cargo e superior: só administrador/master (regra do back).
                if (elevated) ...[
                  const SizedBox(height: 18),
                  _sectionLabel(LucideIcons.network, 'Hierarquia'),
                  const SizedBox(height: 10),
                  UaHierarchyFields(
                    jobLevelId: _jobLevelId,
                    reportsToUserId: _reportsToUserId,
                    accent: _accent,
                    enabled: !_saving,
                    onChanged: (level, superior) => setState(() {
                      _jobLevelId = level;
                      _reportsToUserId = superior;
                    }),
                  ),
                ],
                const SizedBox(height: 18),
                _sectionLabel(LucideIcons.tag, 'Tags'),
                const SizedBox(height: 10),
                UaTagSelector(
                  tags: _tags,
                  selected: _selectedTags,
                  maxTags: 5,
                  accent: _accent,
                  loading: _tagsLoading,
                  enabled: !_saving,
                  onToggle: (id) => setState(() {
                    if (!_selectedTags.remove(id)) _selectedTags.add(id);
                  }),
                ),
                const SizedBox(height: 18),
                _sectionLabel(
                  LucideIcons.shieldCheck,
                  'Permissões',
                  trailing: sel == null
                      ? null
                      : Text(
                          '${sel.selected.length}/${sel.visibleTotal}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: _accent,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                _hint(
                  'As permissões obrigatórias do sistema e do Funil de Vendas já vêm marcadas. Toque numa categoria para ajustar.',
                ),
                const SizedBox(height: 12),
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
                else ...[
                  if (sel.selected.isEmpty) ...[
                    const UaNoticeBanner(
                      notice: PermissionNotice(
                        'É obrigatório selecionar pelo menos 1 permissão',
                      ),
                    ),
                    const SizedBox(height: 11),
                  ],
                  UaPermissionGrid(
                    selection: sel,
                    accent: _accent,
                    horizontalPadding: _padH,
                    onOpenCategory: (category, perms) =>
                        showUaPermissionCategorySheet(
                      context: context,
                      selection: sel,
                      category: category,
                      perms: perms,
                      accent: _accent,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildSaveBar(),
        ],
      ),
    );
  }

  Widget _permissionSkeleton() {
    final w = (MediaQuery.sizeOf(context).width - (_padH * 2) - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(
        6,
        (_) => SkeletonBox(width: w, height: 84, borderRadius: 16),
      ),
    );
  }

  Widget _roleChip(String value, String label, IconData icon) {
    final active = _role == value;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: _saving ? null : () => _onRoleChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? _accent.withValues(alpha: 0.10)
              : ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? _accent
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            width: active ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? _accent : secondary),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: active ? _accent : ThemeHelpers.textColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveBar() {
    final confirm = AppColors.status.success;
    return Container(
      padding: EdgeInsets.fromLTRB(
        _padH,
        10,
        _padH,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color:
                ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: ThemeHelpers.textColor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _saving || _loadingAccess ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: confirm,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Criar usuário',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
