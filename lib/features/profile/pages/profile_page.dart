import 'dart:io';
import 'dart:math' as math;

import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/services/theme_service.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../../shared/utils/masks.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/brand_wordmark_logo.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../finance/pin/widgets/finance_biometric_tile.dart';
import '../../organization/pages/edit_company_page.dart';
import '../../organization/services/company_admin_service.dart';
import '../widgets/avatar_edit_modal.dart';
import '../widgets/change_password_modal.dart';

// ─── Cores do Perfil (só tokens) ────────────────────────────────────────────
// Vermelho da marca = você (o crachá e o que você muda); violeta = gestão
// (as empresas que o administrador controla); neutro com cadeado = o que
// não muda por aqui. Nada de arco-íris.
Color _pBrand(bool d) =>
    d ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
Color _pAdmin(bool d) =>
    d ? AppColors.status.purpleDarkMode : AppColors.status.purple;

/// Meu perfil — um crachá, não um formulário. Responde de cara: quem sou,
/// o que posso mudar e o que não muda por aqui.
///   • Crachá: foto (toque para trocar), nome, e-mail, cargo e empresa.
///   • "O que você pode mudar": foto, nome e telefone, tags, senha e tema —
///     cada linha com o valor de hoje e o caminho para mudar.
///   • "Não muda por aqui": e-mail de acesso, cargo e empresa, com cadeado
///     e quem altera (travado e explicado, nunca escondido).
///   • Empresas (admin/master): logo, dados e as duas regras de acesso.
/// Flush: linhas com filete, sem cards encapsulando seções.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Profile? _profile;
  bool _isLoading = true;
  String? _errorMessage;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;
  ErrorCause? _errorCause;

  // Toast do avatar fica pendente e só é exibido DEPOIS que o sheet fecha —
  // antes o SnackBar aparecia atrás do modal.
  String? _pendingToastMsg;
  bool _pendingToastOk = false;

  // Empresas (admin/master) — paridade com a seção "Empresas" do Perfil web:
  // switches por empresa de "App liberado para todos" e "2FA obrigatório".
  List<CompanyAdminRecord> _companies = const [];
  bool _companiesLoading = false;
  String? _companiesError;
  final Map<String, bool> _company2FA = {};
  final Map<String, bool> _companyAppAccess = {};
  final Map<String, bool> _saving2FA = {};
  final Map<String, bool> _savingAppAccess = {};

  // ─── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorStatus = 0;
      _errorCause = null;
    });
    try {
      final response = await ProfileService.instance.getProfile();
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _profile = response.data;
          _isLoading = false;
        });
        if (_canManageCompanies) await _loadCompanies();
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar perfil';
          _errorStatus = response.statusCode;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorCause = ErrorCause.fromException(e);
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  // ─── Empresas (admin/master) ────────────────────────────────────────────

  /// Mesmo recorte do web: a seção e os switches só existem para
  /// `role === 'admin' || role === 'master'`.
  bool get _canManageCompanies {
    final role = (_profile?.role ?? '').toLowerCase();
    return role == 'admin' || role == 'master';
  }

  Future<void> _loadCompanies() async {
    if (!mounted) return;
    setState(() {
      _companiesLoading = true;
      _companiesError = null;
    });
    final res = await CompanyAdminService.instance.listCompanies();
    if (!mounted) return;
    if (res.success && res.data != null) {
      final list = res.data!;
      setState(() {
        _companies = list;
        _company2FA
          ..clear()
          ..addEntries(list.map((c) => MapEntry(c.id, c.requireTwoFactor)));
        _companyAppAccess
          ..clear()
          ..addEntries(
            list.map((c) => MapEntry(c.id, c.mobileAppAccessForAll)),
          );
        _companiesLoading = false;
      });
    } else {
      setState(() {
        _companiesError = 'Não deu para carregar as empresas.';
        _companiesLoading = false;
      });
    }
  }

  /// Confirmação de "2FA obrigatório": diz quem fica trancado e o que fazer.
  Future<bool> _confirmRequire2FA(String companyId) async {
    final name = _companies
        .where((c) => c.id == companyId)
        .map((c) => c.name.trim())
        .firstWhere((n) => n.isNotEmpty, orElse: () => 'esta empresa');
    final muted = ThemeHelpers.textSecondaryColor(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        icon: Icon(
          Icons.shield_outlined,
          color: Theme.of(ctx).brightness == Brightness.dark
              ? AppColors.status.warningDarkMode
              : AppColors.status.warning,
        ),
        title: const Text('Exigir verificação em duas etapas?'),
        content: SingleChildScrollView(
          child: Text(
            'Em $name, todo usuário vai precisar configurar o código de '
            'verificação (2FA) para entrar.\n\n'
            'Quem ainda não configurou fica trancado no próximo login até '
            'concluir a configuração — avise a equipe antes de ligar.',
            style: TextStyle(color: muted, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: muted),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exigir 2FA'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _toggleCompany2FA(String companyId, bool next) async {
    // Ligar tranca fora quem ainda não configurou o código: pede confirmação
    // antes de gravar (o web grava direto; aqui o aviso vem primeiro).
    if (next && !await _confirmRequire2FA(companyId)) return;
    if (!mounted) return;
    setState(() {
      _company2FA[companyId] = next;
      _saving2FA[companyId] = true;
    });
    final res = await CompanyAdminService.instance.setRequireTwoFactor(
      companyId,
      next,
    );
    if (!mounted) return;
    setState(() {
      _saving2FA[companyId] = false;
      if (!res.success) _company2FA[companyId] = !next;
    });
    if (res.success) {
      _toast(
        next
            ? 'Verificação em duas etapas agora é obrigatória na empresa.'
            : 'Verificação em duas etapas deixou de ser obrigatória na empresa.',
        success: true,
      );
    } else {
      _toast(
        res.message ?? 'Não deu para salvar a verificação em duas etapas.',
        success: false,
      );
    }
  }

  Future<void> _toggleCompanyAppAccess(String companyId, bool next) async {
    setState(() {
      _companyAppAccess[companyId] = next;
      _savingAppAccess[companyId] = true;
    });
    final res = await CompanyAdminService.instance.setMobileAppAccessForAll(
      companyId,
      next,
    );
    if (!mounted) return;
    setState(() {
      _savingAppAccess[companyId] = false;
      if (!res.success) _companyAppAccess[companyId] = !next;
    });
    if (res.success) {
      _toast(
        next
            ? 'App mobile liberado para todos os colaboradores da empresa.'
            : 'Liberação geral do app mobile desativada. Vale o acesso '
                  'individual de cada usuário.',
        success: true,
      );
    } else {
      _toast(
        res.message ?? 'Erro ao salvar o acesso ao app da empresa.',
        success: false,
      );
    }
  }

  Future<void> _openEditCompany(CompanyAdminRecord company) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditCompanyPage(companyId: company.id),
      ),
    );
    if (saved == true && mounted) await _loadCompanies();
  }

  /// Abre a edição e, na volta, relê o perfil sem piscar o skeleton — o
  /// crachá mostra o nome e o telefone novos na hora.
  Future<void> _openEditProfile() async {
    await Navigator.pushNamed(context, AppRoutes.profileEdit);
    if (!mounted) return;
    final res = await ProfileService.instance.getProfile();
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _profile = res.data);
  }

  // ─── Avatar ─────────────────────────────────────────────────────────────

  /// Aplica a troca/remoção da foto. Retorna `true` em sucesso para o modal
  /// fechar; em erro retorna `false` (o modal permanece aberto para retry) e a
  /// página mostra um toast. Não pisca o skeleton da página: o próprio modal
  /// exibe o progresso, evitando flash atrás do sheet.
  Future<bool> _handleAvatarChange(String? avatarUrlOrPath) async {
    if (avatarUrlOrPath == null) {
      final response = await ProfileService.instance.removeAvatar();
      if (!mounted) return false;
      if (response.success && response.data != null) {
        setState(() => _profile = response.data);
        _queueToast('Foto removida com sucesso', ok: true);
        return true;
      }
      _queueToast(response.message ?? 'Erro ao remover foto', ok: false);
      return false;
    }

    final imageFile = File(avatarUrlOrPath);
    if (!await imageFile.exists()) {
      _queueToast('Arquivo não encontrado', ok: false);
      return false;
    }
    try {
      final response = await ProfileService.instance.uploadAvatar(imageFile);
      if (!mounted) return false;
      if (response.success) {
        await _loadProfile();
        if (!mounted) return false;
        _queueToast('Foto de perfil atualizada!', ok: true);
        return true;
      }
      _queueToast(response.message ?? 'Erro ao enviar a foto', ok: false);
      return false;
    } catch (e) {
      _queueToast('Erro: $e', ok: false);
      return false;
    }
  }

  /// Enfileira um toast para ser exibido só quando o sheet do avatar fechar.
  void _queueToast(String msg, {required bool ok}) {
    _pendingToastMsg = msg;
    _pendingToastOk = ok;
  }

  void _flushPendingToast() {
    final msg = _pendingToastMsg;
    if (msg == null || !mounted) return;
    _pendingToastMsg = null;
    _toast(msg, success: _pendingToastOk);
  }

  Future<void> _openAvatarEditor() async {
    final p = _profile;
    if (p == null) return;
    await AvatarEditModal.show(
      context: context,
      onSave: _handleAvatarChange,
      currentAvatar: p.avatar,
    );
    _flushPendingToast();
  }

  void _toast(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success
            ? AppColors.status.success
            : AppColors.status.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── Formatação ─────────────────────────────────────────────────────────

  String _getRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Administrador';
      case 'master':
        return 'Master';
      case 'manager':
        return 'Gerente';
      default:
        return 'Corretor';
    }
  }

  String? _joinedSince(String iso) {
    if (iso.isEmpty) return null;
    try {
      return DateFormat('MMM yyyy', 'pt_BR').format(DateTime.parse(iso));
    } catch (_) {
      return null;
    }
  }

  Color _brand(BuildContext context) =>
      _pBrand(Theme.of(context).brightness == Brightness.dark);

  // ─── Build ──────────────────────────────────────────────────────────────

  /// Tablet/landscape largo: a coluna para em [_kMaxContentWidth] e
  /// centraliza, sem esticar as linhas.
  EdgeInsets _pagePadding({double top = 0, double bottom = 0}) {
    final w = MediaQuery.sizeOf(context).width;
    final side = w > _kMaxContentWidth ? (w - _kMaxContentWidth) / 2 : 0.0;
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  @override
  Widget build(BuildContext context) {
    final brand = _brand(context);

    return AppScaffold(
      title: 'Meu Perfil',
      currentBottomNavIndex: 4,
      showBottomNavigation: true,
      userName: _profile?.name,
      userEmail: _profile?.email,
      userAvatar: _profile?.avatar,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _isLoading
            ? KeyedSubtree(
                key: const ValueKey('loading'),
                child: _buildSkeleton(context),
              )
            : _errorMessage != null
            ? Padding(
                key: ValueKey<String>('e-${_errorMessage.hashCode}'),
                padding: const EdgeInsets.all(24),
                child: _buildErrorState(),
              )
            : CustomRefreshIndicator(
                key: const ValueKey('ok'),
                offsetToArmed: 96,
                onRefresh: _loadProfile,
                builder: _pullRefreshBuilder,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: _pagePadding(top: 14, bottom: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBadge(context, brand),
                      _sectionBreak(context),
                      _buildCanChangeSection(context, brand),
                      // Biometria do Financeiro (opt-in, 03/10/2026) — some
                      // sozinha sem o módulo ou sem biometria no aparelho.
                      const Padding(
                        padding: EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 0),
                        child: FinanceBiometricTile(),
                      ),
                      _sectionBreak(context),
                      _buildLockedSection(context),
                      if (_canManageCompanies) ...[
                        _sectionBreak(context),
                        _buildCompaniesSection(context),
                      ],
                      const SizedBox(height: 30),
                      _buildFooterSignature(context),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ─── Pull-to-refresh com pílula (mesmo idioma do Kanban CRM) ─────────────

  Widget _pullRefreshBuilder(
    BuildContext context,
    Widget child,
    IndicatorController controller,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _pBrand(isDark);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final dragPct = controller.value.clamp(0.0, 1.0);
        final shift = (controller.value * 64).clamp(0.0, 80.0);
        final visible =
            controller.value > 0.02 ||
            controller.isLoading ||
            controller.isFinalizing;
        return Stack(
          children: [
            Transform.translate(offset: Offset(0, shift), child: child),
            if (visible)
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: dragPct == 0 ? 1 : dragPct,
                    child: _refreshPill(context, accent, controller, dragPct),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _refreshPill(
    BuildContext context,
    Color accent,
    IndicatorController controller,
    double dragPct,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loading = controller.isLoading || controller.isFinalizing;
    final armed = controller.isArmed;
    final label = loading
        ? 'Atualizando…'
        : (armed ? 'Solte para atualizar' : 'Puxe para atualizar');
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 14, 8),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.45 : 0.30),
        ),
        // Claro: só o crisp de 1px do tema (nada de sombra difusa tingida).
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: loading
                ? _SpinningGlyph(color: accent)
                : Transform.rotate(
                    angle: dragPct * math.pi,
                    child: Icon(Icons.refresh_rounded, size: 18, color: accent),
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Crachá — quem é você ─────────────────────────────────────────────────

  Widget _buildBadge(BuildContext context, Color brand) {
    final p = _profile!;
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final company = (p.companyName ?? '').trim();
    final since = _joinedSince(p.createdAt);
    final name = p.name.trim();
    // Em tela estreita a foto desce um degrau para o nome caber em 2 linhas.
    final avatarSize = MediaQuery.sizeOf(context).width < 360 ? 72.0 : 84.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kPadH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AvatarPlate(
                profile: p,
                size: avatarSize,
                onTap: _openAvatarEditor,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isEmpty ? 'Seu nome' : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        height: 1.1,
                        letterSpacing: -0.4,
                        fontSize: 21,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _IdChip(
                          icon: Icons.workspace_premium_outlined,
                          label: _getRoleLabel(p.role),
                          tone: brand,
                        ),
                        if (company.isNotEmpty)
                          _IdChip(
                            icon: Icons.apartment_rounded,
                            label: company,
                            tone: secondary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (since != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.event_available_outlined, size: 15, color: secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Na plataforma desde $since',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── O que você pode mudar — cada linha com o valor de hoje ─────────────

  Widget _buildCanChangeSection(BuildContext context, Color brand) {
    final p = _profile!;
    final themeService = ThemeService.instance;
    final hasPhoto = (p.avatar ?? '').trim().isNotEmpty;
    final phone = (p.phone ?? '').trim();
    final cell = (p.cellphone ?? '').trim();

    final String phoneValue;
    if (phone.isNotEmpty && cell.isNotEmpty) {
      phoneValue = '${Masks.phone(phone)}  ·  ${Masks.phone(cell)}';
    } else if (phone.isNotEmpty || cell.isNotEmpty) {
      phoneValue = Masks.phone(phone.isNotEmpty ? phone : cell);
    } else {
      phoneValue = 'Sem telefone cadastrado';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileSectionHeader(
          icon: Icons.edit_rounded,
          title: 'O que você pode mudar',
          subtitle: 'Toque na linha para mudar. Cada uma mostra como está hoje.',
          tone: brand,
        ),
        const SizedBox(height: 8),
        _ChangeRow(
          tone: brand,
          icon: Icons.photo_camera_outlined,
          title: 'Foto',
          value: hasPhoto ? 'Com foto' : 'Sem foto — toque para pôr uma',
          onTap: _openAvatarEditor,
        ),
        _rowDivider(context),
        _ChangeRow(
          tone: brand,
          icon: Icons.badge_outlined,
          title: 'Nome e telefone',
          value: phoneValue,
          onTap: _openEditProfile,
        ),
        _rowDivider(context),
        _ChangeRow(
          tone: brand,
          icon: Icons.sell_outlined,
          title: 'Tags',
          value: 'Como você é classificado nas listas e filtros',
          onTap: _openEditProfile,
        ),
        _rowDivider(context),
        _ChangeRow(
          tone: brand,
          icon: Icons.password_rounded,
          title: 'Senha',
          value: 'Pede a senha atual; sessões antigas podem ser encerradas',
          onTap: () => ChangePasswordModal.show(context: context),
        ),
        _rowDivider(context),
        _ChangeRow(
          tone: brand,
          icon: themeService.getThemeIcon(),
          title: 'Tema do app',
          value: themeService.getThemeName(),
          onTap: () => _showThemeSheet(context, brand),
        ),
      ],
    );
  }

  // ─── Não muda por aqui — travado e explicado, nunca escondido ────────────

  Widget _buildLockedSection(BuildContext context) {
    final p = _profile!;
    final company = (p.companyName ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileSectionHeader(
          icon: Icons.lock_outline_rounded,
          title: 'Não muda por aqui',
          subtitle: _canManageCompanies
              ? 'Cargo e e-mail mudam na gestão de usuários; os dados da empresa, em Empresas.'
              : 'Para corrigir algum destes, fale com o administrador da sua empresa.',
          tone: ThemeHelpers.textSecondaryColor(context),
        ),
        const SizedBox(height: 8),
        _LockedRow(
          icon: Icons.mail_outline_rounded,
          label: 'E-mail de acesso',
          value: p.email,
        ),
        _rowDivider(context),
        _LockedRow(
          icon: Icons.workspace_premium_outlined,
          label: 'Cargo',
          value: _getRoleLabel(p.role),
        ),
        if (company.isNotEmpty) ...[
          _rowDivider(context),
          _LockedRow(
            icon: Icons.apartment_rounded,
            label: 'Empresa',
            value: company,
          ),
        ],
      ],
    );
  }

  // ─── Empresas (violeta = gestão) — só admin/master ─────────────────────────

  Widget _buildCompaniesSection(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _pAdmin(theme.brightness == Brightness.dark);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final n = _companies.length;
    final appForAll = _companies
        .where((c) => _companyAppAccess[c.id] ?? false)
        .length;
    final twoFactor = _companies.where((c) => _company2FA[c.id] ?? false).length;

    final List<Widget> body;
    if (_companiesLoading && _companies.isEmpty) {
      body = [
        for (var i = 0; i < 2; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
            child: Row(
              children: [
                SkeletonBox(width: 44, height: 44, borderRadius: 12),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 38, borderRadius: 10)),
              ],
            ),
          ),
      ];
    } else if (_companiesError != null && _companies.isEmpty) {
      body = [
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPadH, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _companiesError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _loadCompanies,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Tentar de novo'),
                style: TextButton.styleFrom(foregroundColor: tone),
              ),
            ],
          ),
        ),
      ];
    } else if (_companies.isEmpty) {
      body = [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 6),
          child: Text(
            'Nenhuma empresa para administrar ainda. Quando houver, os dados e as regras de acesso de cada uma aparecem aqui.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.35,
            ),
          ),
        ),
      ];
    } else {
      body = [];
      for (var i = 0; i < _companies.length; i++) {
        if (i > 0) body.add(_rowDivider(context, indent: _kPadH));
        body.add(_buildCompanyBlock(context, _companies[i], tone));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileSectionHeader(
          icon: Icons.apartment_rounded,
          title: 'Empresas',
          subtitle: n == 0
              ? 'Dados, logo e regras de acesso de cada empresa que você administra.'
              : 'App liberado para todos em $appForAll de $n · verificação em duas etapas obrigatória em $twoFactor de $n.',
          tone: tone,
          trailing: n == 0 ? null : '$n empresa${n == 1 ? '' : 's'}',
        ),
        const SizedBox(height: 6),
        ...body,
      ],
    );
  }

  Widget _buildCompanyBlock(
    BuildContext context,
    CompanyAdminRecord c,
    Color tone,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final place = [
      c.city.trim(),
      c.state.trim().toUpperCase(),
    ].where((s) => s.isNotEmpty).join('/');
    final meta = [
      if (c.isMatrix) 'Matriz',
      if (c.cnpj.trim().isNotEmpty) 'CNPJ ${c.cnpj.trim()}',
    ].join('  ·  ');
    final initials = c.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 12, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _CompanyLogo(url: c.logoUrl, initials: initials, tone: tone),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.name.trim().isEmpty ? 'Empresa sem nome' : c.name.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar empresa',
                onPressed: () => _openEditCompany(c),
                icon: Icon(Icons.edit_outlined, size: 20, color: tone),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _CompanySwitchRow(
            tone: tone,
            icon: Icons.smartphone_rounded,
            title: 'App liberado para todos',
            subtitle: 'Todo colaborador entra no app, sem liberação individual.',
            value: _companyAppAccess[c.id] ?? false,
            saving: _savingAppAccess[c.id] ?? false,
            onChanged: (v) => _toggleCompanyAppAccess(c.id, v),
          ),
          _CompanySwitchRow(
            tone: tone,
            icon: Icons.verified_user_outlined,
            title: 'Verificação em duas etapas',
            subtitle:
                'Obrigatória: cada um configura o código (2FA) antes de entrar.',
            value: _company2FA[c.id] ?? false,
            saving: _saving2FA[c.id] ?? false,
            onChanged: (v) => _toggleCompany2FA(c.id, v),
          ),
        ],
      ),
    );
  }

  // ─── Rodapé — assinatura da marca ──────────────────────────────────────────

  Widget _buildFooterSignature(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 0, _kPadH, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hairline(context),
          const SizedBox(height: 16),
          const BrandWordmarkLogo(height: 26, alignment: Alignment.centerLeft),
          const SizedBox(height: 6),
          Text(
            'Plataforma · CRM Imobiliário',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Folha do tema — escolha única; em tela baixa rola por dentro ─────────

  Future<void> _showThemeSheet(BuildContext context, Color tone) async {
    final themeService = ThemeService.instance;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final mq = MediaQuery.of(sheetContext);
        final theme = Theme.of(sheetContext);
        final secondary = ThemeHelpers.textSecondaryColor(sheetContext);
        return Padding(
          padding: EdgeInsets.only(bottom: mq.padding.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
            child: Container(
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(sheetContext),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border(
                  top: BorderSide(color: ThemeHelpers.borderColor(sheetContext)),
                ),
              ),
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
                        color: secondary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(_kPadH, 10, 6, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Tema do app',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: ThemeHelpers.textColor(sheetContext),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: Icon(Icons.close_rounded, color: secondary),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              _kPadH,
                              0,
                              _kPadH,
                              6,
                            ),
                            child: Text(
                              'Escolha como quer ver o app. Dá para mudar quando quiser.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondary,
                                height: 1.35,
                              ),
                            ),
                          ),
                          _themeOptionTile(
                            sheetContext,
                            tone,
                            ThemeMode.light,
                            'Claro',
                            'Fundo branco. Melhor de dia e em lugar claro.',
                            Icons.light_mode_rounded,
                            themeService,
                          ),
                          _themeOptionTile(
                            sheetContext,
                            tone,
                            ThemeMode.dark,
                            'Escuro',
                            'Fundo grafite. Cansa menos a vista à noite.',
                            Icons.dark_mode_rounded,
                            themeService,
                          ),
                          _themeOptionTile(
                            sheetContext,
                            tone,
                            ThemeMode.system,
                            'Sistema',
                            'Acompanha o tema do celular.',
                            Icons.brightness_auto_rounded,
                            themeService,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Atualiza a linha do tema caso a seleção não dispare rebuild global.
    if (mounted) setState(() {});
  }

  Widget _themeOptionTile(
    BuildContext sheetContext,
    Color tone,
    ThemeMode mode,
    String title,
    String subtitle,
    IconData icon,
    ThemeService themeService,
  ) {
    final selected = themeService.themeMode == mode;
    final theme = Theme.of(sheetContext);
    final secondary = ThemeHelpers.textSecondaryColor(sheetContext);

    return InkWell(
      onTap: () async {
        await themeService.setThemeMode(mode);
        if (sheetContext.mounted) Navigator.pop(sheetContext);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
        child: Row(
          children: [
            _ToneIconPlate(tone: tone, icon: icon, active: selected),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(sheetContext),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? tone : secondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers de layout ─────────────────────────────────────────────────────

  /// Filete entre linhas — começa onde começa o texto (placa sem corte).
  Widget _rowDivider(BuildContext context, {double indent = _kRowTextInset}) {
    return Padding(
      padding: EdgeInsets.only(left: indent, right: _kPadH),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
      ),
    );
  }

  Widget _hairline(BuildContext context) {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
    );
  }

  Widget _sectionBreak(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: _hairline(context),
    );
  }

  // ─── Skeleton / Error ───────────────────────────────────────────────────

  /// Espelha a tela real: crachá, e duas seções de linhas com placa.
  Widget _buildSkeleton(BuildContext context) {
    final hair = ThemeHelpers.borderColor(context).withValues(alpha: 0.3);

    Widget header() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: _kPadH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 30, height: 30, borderRadius: 15),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 170, height: 17),
                SizedBox(height: 6),
                SkeletonText(width: 230, height: 11),
              ],
            ),
          ),
        ],
      ),
    );

    Widget row() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
      child: Row(
        children: [
          SkeletonBox(width: 40, height: 40, borderRadius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 110, height: 13),
                SizedBox(height: 6),
                SkeletonText(width: 170, height: 11),
              ],
            ),
          ),
          SizedBox(width: 10),
          SkeletonBox(width: 14, height: 14, borderRadius: 4),
        ],
      ),
    );

    Widget divider() => Padding(
      padding: const EdgeInsets.only(left: _kRowTextInset, right: _kPadH),
      child: Container(height: 1, color: hair),
    );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: _pagePadding(top: 14, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _kPadH),
            child: Row(
              children: [
                SkeletonBox(width: 84, height: 84, borderRadius: 42),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 170, height: 20),
                      SizedBox(height: 8),
                      SkeletonText(width: 190, height: 11),
                      SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          SkeletonBox(width: 76, height: 24, borderRadius: 999),
                          SkeletonBox(width: 92, height: 24, borderRadius: 999),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _kPadH),
            child: SkeletonText(width: 180, height: 11),
          ),
          const SizedBox(height: 22),
          Container(height: 1, color: hair),
          const SizedBox(height: 22),
          header(),
          const SizedBox(height: 8),
          for (var i = 0; i < 5; i++) ...[if (i > 0) divider(), row()],
          const SizedBox(height: 22),
          Container(height: 1, color: hair),
          const SizedBox(height: 22),
          header(),
          const SizedBox(height: 8),
          for (var i = 0; i < 3; i++) ...[if (i > 0) divider(), row()],
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    // Exceção solta traz seu próprio diagnóstico; falha de API vem da resposta.
    final cause = _errorCause;
    if (cause != null) {
      return AppErrorState(cause: cause, onRetry: _loadProfile, dense: true);
    }
    return AppErrorState.fromApi(
      message: _errorMessage,
      statusCode: _errorStatus,
      onRetry: _loadProfile,
      dense: true,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// COMPONENTES INTERNOS — crachá e linhas flush
// ════════════════════════════════════════════════════════════════════════

/// Margem lateral da tela (gramática flush do app).
const double _kPadH = 16;

/// Onde começa o texto das linhas com placa (16 + placa 40 + 14).
const double _kRowTextInset = 70;

/// Largura máxima da coluna em tela larga.
const double _kMaxContentWidth = 720;

/// Cabeçalho de seção do Perfil — disco com o ícone do assunto (lápis = você
/// muda, cadeado = não muda por aqui), título, explicação curta e contagem.
class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader({
    required this.icon,
    required this.title,
    required this.tone,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kPadH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.12),
              border: Border.all(color: tone.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      height: 1.2,
                      fontSize: 18,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  trailing!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Linha "você pode mudar" — o que é, como está hoje e a seta de ir mudar.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.tone,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.10),
        highlightColor: tone.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kPadH, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ToneIconPlate(tone: tone, icon: icon, active: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 22, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha "não muda por aqui" — rótulo pequeno em cima, valor em destaque,
/// cadeado à direita. Placa apagada: é dado, não ação.
class _LockedRow extends StatelessWidget {
  const _LockedRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 12, _kPadH, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ToneIconPlate(tone: secondary, icon: icon, active: false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Não muda por aqui',
            child: Icon(Icons.lock_outline_rounded, size: 17, color: secondary),
          ),
        ],
      ),
    );
  }
}

/// Regra da empresa com interruptor — flush, sem moldura. Enquanto grava,
/// o interruptor fica travado e a linha diz "Salvando…" (sem trocar layout).
class _CompanySwitchRow extends StatelessWidget {
  const _CompanySwitchRow({
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.saving,
    required this.onChanged,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: saving ? null : () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Icon(
                icon,
                size: 18,
                color: value ? tone : secondary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    saving ? 'Salvando…' : subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: saving ? tone : secondary,
                      fontWeight: saving ? FontWeight.w700 : null,
                      height: 1.3,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: value,
              activeTrackColor: tone,
              onChanged: saving ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Placa de ícone tom-sobre-tom, chapada (sem degradê).
class _ToneIconPlate extends StatelessWidget {
  const _ToneIconPlate({
    required this.tone,
    required this.icon,
    required this.active,
  });

  final Color tone;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: tone.withValues(alpha: active ? 0.12 : 0.07),
        border: Border.all(color: tone.withValues(alpha: active ? 0.3 : 0.2)),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: tone.withValues(alpha: active ? 1.0 : 0.85),
        size: 20,
      ),
    );
  }
}

/// Carimbo de informação do crachá (cargo, empresa) — em contorno, nunca
/// chapa cinza; nome longo de empresa corta com reticências.
class _IdChip extends StatelessWidget {
  const _IdChip({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.1,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo da empresa numa caixa de tamanho fixo (44) — a logo fica sobre o
/// fundo do card (não tinge marca de terceiro); sem logo, as iniciais.
class _CompanyLogo extends StatelessWidget {
  const _CompanyLogo({
    required this.url,
    required this.initials,
    required this.tone,
  });

  final String? url;
  final String initials;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final hasLogo = (url ?? '').isNotEmpty;
    final fallback = Text(
      initials.isEmpty ? '·' : initials,
      style: TextStyle(color: tone, fontWeight: FontWeight.w900, fontSize: 14),
    );
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      padding: hasLogo ? const EdgeInsets.all(4) : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: hasLogo
            ? ThemeHelpers.cardBackgroundColor(context)
            : tone.withValues(alpha: 0.12),
        border: Border.all(
          color: hasLogo
              ? ThemeHelpers.borderColor(context)
              : tone.withValues(alpha: 0.32),
        ),
      ),
      alignment: Alignment.center,
      child: hasLogo
          ? Image.network(
              url!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Avatar (com selo da câmera para trocar a foto)
// ──────────────────────────────────────────────────────────────────────────

class _AvatarPlate extends StatelessWidget {
  const _AvatarPlate({
    required this.profile,
    required this.size,
    required this.onTap,
  });

  final Profile profile;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _pBrand(isDark);

    return Semantics(
      label: 'Trocar foto de perfil',
      button: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size + 8,
            height: size + 8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Container(
                    width: size,
                    height: size,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ThemeHelpers.cardBackgroundColor(context),
                      border: Border.all(
                        color: accent.withValues(alpha: isDark ? 0.5 : 0.34),
                        width: 1.5,
                      ),
                    ),
                    child: (profile.avatar ?? '').isNotEmpty
                        ? Image.network(
                            profile.avatar!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _fallback(accent),
                          )
                        : _fallback(accent),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                      border: Border.all(
                        color: ThemeHelpers.cardBackgroundColor(context),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Sem foto: iniciais na cor da marca sobre o mesmo tom bem claro
  /// (chapado — sem degradê inventado).
  Widget _fallback(Color accent) {
    final parts = profile.name.trim().split(RegExp(r'\s+'));
    final initials = parts.isEmpty || parts.first.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first[0].toUpperCase()
        : (parts.first[0] + parts.last[0]).toUpperCase();

    return Container(
      color: accent.withValues(alpha: 0.14),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.3,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Glyph que gira continuamente enquanto recarrega — mesmo idioma do
/// pull-to-refresh do Kanban.
class _SpinningGlyph extends StatefulWidget {
  const _SpinningGlyph({required this.color});
  final Color color;

  @override
  State<_SpinningGlyph> createState() => _SpinningGlyphState();
}

class _SpinningGlyphState extends State<_SpinningGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: Icon(Icons.sync_rounded, size: 18, color: widget.color),
    );
  }
}
