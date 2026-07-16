import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../inspections/widgets/cpf_cnpj_text_field.dart';
import '../services/admin_users_service.dart';
import 'edit_user_page.dart';

/// Criar usuário — porta o essencial do CreateUserPage do web: dados básicos
/// com validação remota de email/CPF, senha inicial (com gerador) e papel.
/// Permissões, gestores e tags são configurados na sequência pela tela de
/// edição (fluxo em 2 passos, adequado ao mobile).
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

  String? _emailError;
  String? _documentError;

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _document.dispose();
    _phone.dispose();
    super.dispose();
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
    });
  }

  bool _validEmail(String v) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(v);

  Future<void> _submit() async {
    if (_saving) return;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final documentDigits = _document.text.replaceAll(RegExp(r'\D'), '');
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');

    String? snack;
    if (name.isEmpty) {
      snack = 'Informe o nome.';
    } else if (!_validEmail(email)) {
      snack = 'Informe um email válido.';
    } else if (password.length < 6) {
      snack = 'A senha precisa de pelo menos 6 caracteres.';
    } else if (documentDigits.length != 11 && documentDigits.length != 14) {
      snack = 'Informe um CPF ou CNPJ válido.';
    } else if (phoneDigits.length < 10) {
      snack = 'Informe um telefone com DDD.';
    }
    if (snack != null) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(snack)));
      return;
    }

    setState(() {
      _saving = true;
      _emailError = null;
      _documentError = null;
    });

    // Validação remota de disponibilidade (paridade com o web, que valida
    // email e CPF/CNPJ antes do POST).
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
      'password': password,
      'document': documentDigits,
      'phone': phoneDigits,
      'role': _role,
    });
    if (!mounted) return;
    setState(() => _saving = false);

    if (!res.success || res.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao criar usuário.')),
      );
      return;
    }

    final created = res.data!;
    final goToPermissions = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuário criado!'),
        content: Text(
          '${created.name} já pode acessar o sistema.\n\n'
          'Deseja configurar permissões e gestores agora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Depois'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Configurar agora'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (goToPermissions == true) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EditUserPage(user: created)),
      );
    } else {
      Navigator.of(context).pop(true);
    }
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

  Widget _sectionLabel(IconData icon, String label) => Row(
        children: [
          Icon(icon, size: 14, color: _accent),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Papéis criáveis: qualquer gestor cria corretor; admin/master também
    // criam gestores e proprietários (paridade com o web).
    final myRole = _myRole();
    final elevated = myRole == 'admin' || myRole == 'master';

    return AppScaffold(
      title: 'Novo usuário',
      showBottomNavigation: false,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 20),
              children: [
                _sectionLabel(LucideIcons.userRound, 'Dados básicos'),
                const SizedBox(height: 10),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec('Nome completo *'),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CpfCnpjTextField(
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
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        enabled: !_saving,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [PhoneInputFormatter()],
                        decoration: _dec('Telefone *'),
                      ),
                    ),
                  ],
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
                  decoration: _dec(
                    'Senha *',
                    hint: 'Mínimo 6 caracteres',
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
                Text(
                  'Compartilhe a senha com o colaborador; ele pode trocá-la no primeiro acesso.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
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
                const SizedBox(height: 8),
                Text(
                  'Permissões, gestores responsáveis e tags são configurados no próximo passo.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ],
            ),
          ),
          _buildSaveBar(),
        ],
      ),
    );
  }

  String _myRole() =>
      ModuleAccessService.instance.userRole?.toLowerCase().trim() ?? '';

  Widget _roleChip(String value, String label, IconData icon) {
    final active = _role == value;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: _saving ? null : () => setState(() => _role = value),
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
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
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
                  : const Text('Criar usuário'),
            ),
          ),
        ],
      ),
    );
  }
}
