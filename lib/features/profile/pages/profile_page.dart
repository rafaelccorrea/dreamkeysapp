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
import '../../../../shared/utils/masks.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/brand_wordmark_logo.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../widgets/avatar_edit_modal.dart';
import '../widgets/change_password_modal.dart';

// ─── Paleta editorial do Perfil ─────────────────────────────────────────────
// Mesmo DNA da tela de Configurações (referência): 1 cor de identidade por
// seção, sem arco-íris. Vermelho da marca = conta/identidade; violeta =
// aparência; índigo = segurança. Tons de apoio com significado no strip.
Color _pBrand(bool d) =>
    d ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
Color _pIndigo(bool d) => d ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
Color _pViolet(bool d) => d ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);

/// Página de Perfil — reconstruída sobre o sistema editorial da tela de
/// Configurações (a referência do app):
///   • Masthead (eyebrow + headline w900 + subtítulo) sem hero-card.
///   • Manchete de perfil (avatar editável + nome + email + meta pills).
///   • Quick KPI strip de 4 colunas separadas por linhas finas.
///   • Seções full-bleed com header editorial (barra tonal + eyebrow + título
///     grande + subtítulo + hint), divisores finos e placas de ícone tom-on-tom.
///   • **Aparência**: troca de tema do app (claro/escuro/sistema) via sheet.
///   • Rodapé com assinatura da marca.
/// Uma cor de identidade por seção — coerente, sem virar rainbow.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Profile? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  // Toast do avatar fica pendente e só é exibido DEPOIS que o sheet fecha —
  // antes o SnackBar aparecia atrás do modal.
  String? _pendingToastMsg;
  bool _pendingToastOk = false;

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
    });
    try {
      final response = await ProfileService.instance.getProfile();
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _profile = response.data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar perfil';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
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

  String _joinedYear(String iso) {
    if (iso.isEmpty) return '—';
    try {
      return DateFormat('yyyy', 'pt_BR').format(DateTime.parse(iso));
    } catch (_) {
      return '—';
    }
  }

  String _themeShort(ThemeMode m) => switch (m) {
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Escuro',
    ThemeMode.system => 'Auto',
  };

  Color _brand(BuildContext context) =>
      _pBrand(Theme.of(context).brightness == Brightness.dark);

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            ? Padding(
                key: const ValueKey('loading'),
                padding: const EdgeInsets.only(top: 4),
                child: _buildSkeleton(context, theme, brand),
              )
            : _errorMessage != null
            ? Padding(
                key: ValueKey<String>('e-${_errorMessage.hashCode}'),
                padding: const EdgeInsets.all(24),
                child: _buildErrorState(context, theme),
              )
            : CustomRefreshIndicator(
                key: const ValueKey('ok'),
                offsetToArmed: 96,
                onRefresh: _loadProfile,
                builder: _pullRefreshBuilder,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 4, bottom: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMasthead(context, theme, brand),
                      const SizedBox(height: 18),
                      _buildProfileManchete(context, theme, brand),
                      const SizedBox(height: 14),
                      _buildQuickStrip(context, theme, brand),
                      const SizedBox(height: 14),
                      _sectionSeparator(context),
                      const SizedBox(height: 22),
                      _buildAccountSection(context, theme, brand),
                      const SizedBox(height: 28),
                      _sectionSeparator(context),
                      const SizedBox(height: 22),
                      _buildAppearanceSection(context, theme),
                      const SizedBox(height: 28),
                      _sectionSeparator(context),
                      const SizedBox(height: 22),
                      _buildSecuritySection(context, theme),
                      const SizedBox(height: 32),
                      _buildFooterSignature(context, theme),
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
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -6,
          ),
        ],
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

  // ─── Masthead ────────────────────────────────────────────────────────────

  Widget _buildMasthead(BuildContext context, ThemeData theme, Color brand) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MINHA CONTA',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: brand,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brand.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'CONECTADO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(
                    context,
                  ).withValues(alpha: 0.85),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Meu perfil',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: ThemeHelpers.textColor(context),
              height: 1.0,
              fontSize: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Seus dados, aparência do app e segurança da conta. Tudo o que te identifica na plataforma, em um lugar só.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Manchete de perfil ───────────────────────────────────────────────────

  Widget _buildProfileManchete(
    BuildContext context,
    ThemeData theme,
    Color brand,
  ) {
    final p = _profile!;
    final isDark = theme.brightness == Brightness.dark;
    final violet = _pViolet(isDark);
    final indigo = _pIndigo(isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AvatarPlate(profile: p, onTap: _openAvatarEditor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.name.isEmpty ? 'Usuário' : p.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        height: 1.08,
                        letterSpacing: -0.4,
                        fontSize: 20,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.mail_outline_rounded,
                          size: 13,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            p.email,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _GhostIconButton(
                icon: Icons.edit_rounded,
                tone: brand,
                label: 'Editar',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.profileEdit),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaPill(
                icon: Icons.workspace_premium_outlined,
                label: _getRoleLabel(p.role),
                tone: violet,
              ),
              if ((p.companyName ?? '').trim().isNotEmpty)
                _MetaPill(
                  icon: Icons.apartment_rounded,
                  label: p.companyName!.trim(),
                  tone: indigo,
                ),
              _AvatarStatusDot(active: true),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Quick KPI strip ───────────────────────────────────────────────────────

  Widget _buildQuickStrip(BuildContext context, ThemeData theme, Color brand) {
    final p = _profile!;
    final isDark = theme.brightness == Brightness.dark;
    final mode = ThemeService.instance.themeMode;

    final items = <_QuickKpi>[
      _QuickKpi(
        accent: _pViolet(isDark),
        label: 'TEMA',
        value: _themeShort(mode),
        sub: mode == ThemeMode.system ? 'sistema' : 'manual',
      ),
      _QuickKpi(
        accent: _pIndigo(isDark),
        label: 'CARGO',
        value: _getRoleLabel(p.role),
        sub: 'função',
      ),
      _QuickKpi(
        accent: brand,
        label: 'DESDE',
        value: _joinedYear(p.createdAt),
        sub: 'membro',
      ),
    ];

    final divColor = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 1, height: 44, color: divColor),
            Expanded(child: items[i].render(context)),
          ],
        ],
      ),
    );
  }

  // ─── Seção: CONTA & DADOS (vermelho marca) ─────────────────────────────────

  Widget _buildAccountSection(
    BuildContext context,
    ThemeData theme,
    Color brand,
  ) {
    final p = _profile!;
    final hasPhone = (p.phone ?? '').trim().isNotEmpty;
    final hasCell = (p.cellphone ?? '').trim().isNotEmpty;
    final hasCompany = (p.companyName ?? '').trim().isNotEmpty;

    String? phoneLabel;
    String? phoneValue;
    if (hasPhone && hasCell) {
      phoneLabel = 'Telefone / celular';
      phoneValue =
          '${Masks.phone(p.phone!.trim())}  ·  ${Masks.phone(p.cellphone!.trim())}';
    } else if (hasPhone) {
      phoneLabel = 'Telefone';
      phoneValue = Masks.phone(p.phone!.trim());
    } else if (hasCell) {
      phoneLabel = 'Celular';
      phoneValue = Masks.phone(p.cellphone!.trim());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'IDENTIDADE',
          title: 'Conta & dados',
          subtitle: 'Seus dados pessoais e de contato no sistema.',
          tone: brand,
        ),
        const SizedBox(height: 16),
        _InfoRow(
          tone: brand,
          icon: Icons.badge_outlined,
          label: 'Nome completo',
          value: p.name.isEmpty ? '—' : p.name,
        ),
        _rowDivider(context),
        _InfoRow(
          tone: brand,
          icon: Icons.mail_outline_rounded,
          label: 'E-mail',
          value: p.email,
        ),
        if (phoneValue != null) ...[
          _rowDivider(context),
          _InfoRow(
            tone: brand,
            icon: Icons.phone_iphone_rounded,
            label: phoneLabel!,
            value: phoneValue,
          ),
        ],
        _rowDivider(context),
        _InfoRow(
          tone: brand,
          icon: Icons.workspace_premium_outlined,
          label: 'Cargo / função',
          value: _getRoleLabel(p.role),
        ),
        if (hasCompany) ...[
          _rowDivider(context),
          _InfoRow(
            tone: brand,
            icon: Icons.apartment_rounded,
            label: 'Empresa',
            value: p.companyName!.trim(),
          ),
        ],
        _rowDivider(context),
        _NavigationRow(
          tone: brand,
          icon: Icons.edit_note_rounded,
          title: 'Editar perfil',
          subtitle: 'Altera nome, telefone e foto. Salva ao confirmar.',
          trailing: Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          onTap: () => Navigator.pushNamed(context, AppRoutes.profileEdit),
        ),
      ],
    );
  }

  // ─── Seção: APARÊNCIA (violeta) — troca de tema ────────────────────────────

  Widget _buildAppearanceSection(BuildContext context, ThemeData theme) {
    final tone = _pViolet(theme.brightness == Brightness.dark);
    final themeService = ThemeService.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'COMO VOCÊ VÊ',
          title: 'Aparência',
          subtitle: 'Tema visual do app — claro, escuro ou seguindo o sistema.',
          tone: tone,
        ),
        const SizedBox(height: 16),
        _NavigationRow(
          tone: tone,
          icon: themeService.getThemeIcon(),
          title: 'Tema do app',
          subtitle: 'Atualmente: ${themeService.getThemeName().toLowerCase()}',
          trailing: _ValueChip(label: themeService.getThemeName(), tone: tone),
          onTap: () => _showThemeSheet(context, tone),
        ),
      ],
    );
  }

  // ─── Seção: SEGURANÇA & PRIVACIDADE (índigo) ───────────────────────────────

  Widget _buildSecuritySection(BuildContext context, ThemeData theme) {
    final tone = _pIndigo(theme.brightness == Brightness.dark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'ACESSO & PRIVACIDADE',
          title: 'Segurança',
          subtitle: 'Gerencie a senha da sua conta.',
          tone: tone,
        ),
        const SizedBox(height: 16),
        _NavigationRow(
          tone: tone,
          icon: Icons.lock_outline_rounded,
          title: 'Alterar senha',
          subtitle: 'Fluxo seguro · sessões antigas podem ser invalidadas.',
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          onTap: () => ChangePasswordModal.show(context: context),
        ),
      ],
    );
  }

  // ─── Rodapé — assinatura da marca ──────────────────────────────────────────

  Widget _buildFooterSignature(BuildContext context, ThemeData theme) {
    final p = _profile!;
    final since = _joinedSince(p.createdAt);
    final themeName = ThemeService.instance.getThemeName();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
          ),
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _FooterMeta(label: 'CARGO', value: _getRoleLabel(p.role)),
              _FooterMeta(label: 'TEMA', value: themeName),
              if (since != null) _FooterMeta(label: 'DESDE', value: since),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Theme sheet — troca de tema (mesma sheet da tela de Configurações) ────

  Future<void> _showThemeSheet(BuildContext context, Color tone) async {
    final themeService = ThemeService.instance;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(sheetContext).bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(sheetContext),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: Border(
                top: BorderSide(
                  color: tone.withValues(alpha: 0.35),
                  width: 1.2,
                ),
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
                      color: ThemeHelpers.textSecondaryColor(
                        sheetContext,
                      ).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'APARÊNCIA',
                              style: Theme.of(sheetContext).textTheme.labelSmall
                                  ?.copyWith(
                                    color: tone,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.0,
                                    fontSize: 10,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tema do app',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                    color: ThemeHelpers.textColor(sheetContext),
                                    height: 1.05,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                  child: Text(
                    'Escolhe como queres ver o app. Pode mudar a qualquer momento.',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(sheetContext),
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _themeOptionTile(
                  sheetContext,
                  tone,
                  ThemeMode.light,
                  'Claro',
                  'Melhor em ambientes luminosos e durante o dia.',
                  Icons.light_mode_rounded,
                  themeService,
                ),
                _themeOptionTile(
                  sheetContext,
                  tone,
                  ThemeMode.dark,
                  'Escuro',
                  'Menos cansaço visual à noite, contraste reduzido.',
                  Icons.dark_mode_rounded,
                  themeService,
                ),
                _themeOptionTile(
                  sheetContext,
                  tone,
                  ThemeMode.system,
                  'Sistema',
                  'Segue automaticamente o tema do telemóvel.',
                  Icons.brightness_auto_rounded,
                  themeService,
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        );
      },
    );

    // Atualiza chip/KPI de tema caso a seleção não dispare rebuild global.
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

    return InkWell(
      onTap: () async {
        await themeService.setThemeMode(mode);
        if (sheetContext.mounted) Navigator.pop(sheetContext);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: tone.withValues(alpha: selected ? 0.18 : 0.1),
                border: Border.all(
                  color: tone.withValues(alpha: selected ? 0.5 : 0.25),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: tone, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(sheetContext),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(sheetContext),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected
                  ? tone
                  : ThemeHelpers.textSecondaryColor(sheetContext),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers de layout ─────────────────────────────────────────────────────

  Widget _rowDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
      ),
    );
  }

  Widget _sectionSeparator(BuildContext context) {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.3),
    );
  }

  // ─── Skeleton / Error ───────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context, ThemeData theme, Color brand) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonText(width: 90, height: 11),
                SizedBox(height: 12),
                SkeletonText(width: 200, height: 28),
                SizedBox(height: 10),
                SkeletonText(width: 280, height: 14),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SkeletonBox(width: 88, height: 88, borderRadius: 44),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonText(width: 170, height: 18),
                      SizedBox(height: 8),
                      SkeletonText(width: 210, height: 12),
                      SizedBox(height: 12),
                      SkeletonText(width: 120, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: List.generate(
                4,
                (i) => Expanded(
                  child: Column(
                    children: const [
                      SkeletonText(width: 40, height: 22),
                      SizedBox(height: 6),
                      SkeletonText(width: 50, height: 9),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          for (var s = 0; s < 3; s++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonText(width: 70, height: 10),
                  SizedBox(height: 8),
                  SkeletonText(width: 160, height: 22),
                  SizedBox(height: 6),
                  SkeletonText(width: 240, height: 12),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < 2; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    SkeletonBox(width: 42, height: 42, borderRadius: 12),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SkeletonText(width: 120, height: 13),
                          SizedBox(height: 6),
                          SkeletonText(width: 200, height: 11),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (i < 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    height: 1,
                    color: ThemeHelpers.borderColor(
                      context,
                    ).withValues(alpha: 0.3),
                  ),
                ),
            ],
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.cloud_off_outlined,
          size: 48,
          color: AppColors.status.error.withValues(alpha: 0.9),
        ),
        const SizedBox(height: 18),
        Text(
          'Não foi possível carregar',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? '',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        TextButton.icon(
          onPressed: _loadProfile,
          icon: const Icon(Icons.refresh),
          label: const Text('Tentar de novo'),
          style: TextButton.styleFrom(
            foregroundColor: _pBrand(theme.brightness == Brightness.dark),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// COMPONENTES INTERNOS — sistema editorial (mesmo DNA da tela de Configurações)
// ════════════════════════════════════════════════════════════════════════

/// Cabeçalho editorial de seção. Barra tonal + eyebrow uppercase colorido +
/// título w900 grande + subtítulo opcional + hint à direita.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.tone,
    this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 2,
                      decoration: BoxDecoration(
                        color: tone,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        eyebrow,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    color: ThemeHelpers.textColor(context),
                    height: 1.05,
                    fontSize: 22,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha de informação (read-only) — placa de ícone tom-on-tom + label
/// uppercase pequeno + valor selecionável.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
  });

  final Color tone;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    fontSize: 14,
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

/// Row de navegação — tap leva para outra tela / abre sheet. Sem moldura.
class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.10),
        highlightColor: tone.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Placa de ícone tom-on-tom — mantém a identidade da seção.
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
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            tone.withValues(alpha: active ? 0.22 : 0.12),
            tone.withValues(alpha: active ? 0.08 : 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: tone.withValues(alpha: active ? 0.42 : 0.22)),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: tone.withValues(alpha: active ? 1.0 : 0.6),
        size: 20,
      ),
    );
  }
}

/// Chip de valor à direita de uma navigation row (ex. "Escuro").
class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tone.withValues(alpha: 0.14),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: tone,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Coluna de KPI rápida — valor grande em accent + label uppercase +
/// sub-rótulo sutil + traço accent fino.
class _QuickKpi {
  const _QuickKpi({
    required this.accent,
    required this.label,
    required this.value,
    required this.sub,
  });

  final Color accent;
  final String label;
  final String value;
  final String sub;

  Widget render(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: -0.6,
                height: 1,
                fontSize: 22,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textSecondaryColor(context),
              letterSpacing: 1.4,
              fontSize: 9.5,
              height: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textSecondaryColor(
                context,
              ).withValues(alpha: 0.65),
              letterSpacing: 0.3,
              fontSize: 9,
              height: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            width: 16,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloco de meta no rodapé — label uppercase fino + valor compacto.
class _FooterMeta extends StatelessWidget {
  const _FooterMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(
              context,
            ).withValues(alpha: 0.65),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontSize: 9,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            color: ThemeHelpers.textColor(context).withValues(alpha: 0.85),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Pill outline simples — ícone + label numa única cor.
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.30 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.15,
                height: 1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Atalho de edição da manchete — pill tonal com rótulo. O círculo oco
/// anterior ("só um lápis") lia como decoração; com plate tom-sobre-tom,
/// rótulo e splash, vira ação inequívoca sem pesar a manchete.
class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({
    required this.icon,
    required this.tone,
    required this.onTap,
    this.label,
  });

  final IconData icon;
  final Color tone;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: label ?? 'Editar',
      child: Material(
        color: tone.withValues(alpha: isDark ? 0.14 : 0.09),
        shape: StadiumBorder(
          side: BorderSide(color: tone.withValues(alpha: 0.32)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: tone.withValues(alpha: 0.14),
          highlightColor: tone.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: label != null ? 12 : 10,
              vertical: 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: tone, size: 15),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    label!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Avatar (com chip da câmera para editar)
// ──────────────────────────────────────────────────────────────────────────

class _AvatarPlate extends StatelessWidget {
  const _AvatarPlate({required this.profile, required this.onTap});

  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _pBrand(isDark);
    const size = 84.0;

    return Semantics(
      label: 'Alterar foto de perfil',
      button: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size + 12,
            height: size + 12,
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
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: isDark ? 0.26 : 0.16),
                          blurRadius: 18,
                          spreadRadius: -4,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: (profile.avatar ?? '').isNotEmpty
                        ? Image.network(
                            profile.avatar!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _fallback(context, isDark),
                          )
                        : _fallback(context, isDark),
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

  Widget _fallback(BuildContext context, bool isDark) {
    final parts = profile.name.trim().split(RegExp(r'\s+'));
    final initials = parts.isEmpty || parts.first.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first[0].toUpperCase()
        : (parts.first[0] + parts.last[0]).toUpperCase();
    final accent = _pBrand(isDark);
    final toneDeep = HSLColor.fromColor(accent)
        .withLightness(
          (HSLColor.fromColor(accent).lightness * 0.78).clamp(0.0, 1.0),
        )
        .toColor();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, toneDeep],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 26,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Chip de status "Ativo/Inativo" — usado na manchete do perfil.
class _AvatarStatusDot extends StatelessWidget {
  const _AvatarStatusDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.status.success
        : ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.55),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Ativo' : 'Inativo',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
        ],
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
