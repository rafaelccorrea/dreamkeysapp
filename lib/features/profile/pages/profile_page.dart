import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/utils/masks.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../widgets/avatar_edit_modal.dart';
import '../widgets/change_password_modal.dart';
import '../widgets/sessions_modal.dart';

/// Página de Perfil — identidade visual unificada com o resto do app.
///
/// Convenções:
///   • Conteúdo flat (sem cards encapsulando), tudo flui no fundo da tela.
///   • Eyebrows accent uppercase pequenos (10.5px w900 letterSpacing 1.65).
///   • Paleta única: primary accent + neutros (text + secondary). Verde
///     reservado para estado "ativo"; âmbar para avisos. Sem rainbow.
///   • Mesmo layout para light e dark mode — sem wrapper "glass" exclusivo.
///   • Ícones outline 18–22px, sem chips coloridos de 44×44.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Profile? _profile;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isUpdatingVisibility = false;
  int? _sessionCount;

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
        _loadSessionCount();
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

  Future<void> _loadSessionCount() async {
    try {
      final r = await SessionService.instance.getSessions();
      if (!mounted) return;
      if (r.success && r.data != null) {
        setState(() => _sessionCount = r.data!.length);
      }
    } catch (_) {
      if (mounted) setState(() => _sessionCount = null);
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
        _toast('Foto removida com sucesso', success: true);
        return true;
      }
      _toast(response.message ?? 'Erro ao remover foto', success: false);
      return false;
    }

    final imageFile = File(avatarUrlOrPath);
    if (!await imageFile.exists()) {
      if (mounted) _toast('Arquivo não encontrado', success: false);
      return false;
    }
    try {
      final response = await ProfileService.instance.uploadAvatar(imageFile);
      if (!mounted) return false;
      if (response.success) {
        await _loadProfile();
        if (!mounted) return false;
        _toast('Foto de perfil atualizada!', success: true);
        return true;
      }
      _toast(
        response.message ?? 'Erro ao enviar a foto',
        success: false,
      );
      return false;
    } catch (e) {
      if (mounted) _toast('Erro: $e', success: false);
      return false;
    }
  }

  Future<void> _togglePublicVisibility() async {
    if (_profile == null) return;
    setState(() => _isUpdatingVisibility = true);
    try {
      final response = await ProfileService.instance.updatePublicVisibility(
        !_profile!.isAvailableForPublicSite,
      );
      if (!mounted) return;
      if (response.success) {
        final newVisibility = response.data ?? _profile!.isAvailableForPublicSite;
        setState(() {
          _profile = Profile(
            id: _profile!.id,
            name: _profile!.name,
            email: _profile!.email,
            phone: _profile!.phone,
            cellphone: _profile!.cellphone,
            avatar: _profile!.avatar,
            role: _profile!.role,
            companyId: _profile!.companyId,
            companyName: _profile!.companyName,
            isAvailableForPublicSite: newVisibility,
            preferences: _profile!.preferences,
            tagIds: _profile!.tagIds,
            createdAt: _profile!.createdAt,
            updatedAt: _profile!.updatedAt,
          );
        });
      } else {
        _toast(
          response.message ?? 'Erro ao atualizar visibilidade',
          success: false,
        );
      }
    } catch (e) {
      if (mounted) _toast('Erro: $e', success: false);
    } finally {
      if (mounted) setState(() => _isUpdatingVisibility = false);
    }
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

  String _formatDate(String dateString) {
    try {
      return DateFormat('dd/MM/yyyy', 'pt_BR').format(DateTime.parse(dateString));
    } catch (_) {
      return dateString;
    }
  }

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

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Meu Perfil',
      currentBottomNavIndex: 4,
      showBottomNavigation: true,
      userName: _profile?.name,
      userEmail: _profile?.email,
      userAvatar: _profile?.avatar,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            _loadProfile();
            _loadSessionCount();
          },
          tooltip: 'Atualizar',
        ),
      ],
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _isLoading
            ? Padding(
                key: const ValueKey('loading'),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: _buildSkeleton(),
              )
            : _errorMessage != null
                ? Padding(
                    key: ValueKey<String>('e-${_errorMessage.hashCode}'),
                    padding: const EdgeInsets.all(24),
                    child: _buildErrorState(context, theme),
                  )
                : RefreshIndicator(
                    key: const ValueKey('ok'),
                    color: AppColors.primary.primary,
                    onRefresh: () async {
                      await _loadProfile();
                      await _loadSessionCount();
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 56),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHero(context, theme),
                          const SizedBox(height: 4),
                          _buildActionsSection(context, theme),
                          const SizedBox(height: 26),
                          _buildDetailsSection(context, theme),
                          const SizedBox(height: 26),
                          _buildPrivacySection(context, theme),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  // ─── Hero ───────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final p = _profile!;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow accent (mesmo padrão dos atalhos do corretor).
          Row(
            children: [
              Icon(Icons.account_circle_outlined, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                'PERFIL DA CONTA',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.65,
                  fontSize: 10.5,
                ),
              ),
              const Spacer(),
              _AvatarStatusDot(active: true),
            ],
          ),
          const SizedBox(height: 14),
          // Bloco principal: avatar + nome + email.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AvatarPlate(
                profile: p,
                onTap: () => AvatarEditModal.show(
                  context: context,
                  onSave: _handleAvatarChange,
                  currentAvatar: p.avatar,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.name.isEmpty ? 'Usuário' : p.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.5,
                        height: 1.05,
                        fontSize: 22,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondaryColor,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Pills de meta — cargo, empresa, sessões.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaPill(
                icon: Icons.workspace_premium_outlined,
                label: _getRoleLabel(p.role),
                tone: accent,
              ),
              if ((p.companyName ?? '').trim().isNotEmpty)
                _MetaPill(
                  icon: Icons.apartment_rounded,
                  label: p.companyName!.trim(),
                  tone: secondaryColor,
                ),
              _MetaPill(
                icon: Icons.devices_rounded,
                label: _sessionCount != null
                    ? '$_sessionCount sessã${_sessionCount == 1 ? "o" : "ões"}'
                    : 'Sessões…',
                tone: secondaryColor,
              ),
              _MetaPill(
                icon: Icons.event_outlined,
                label: 'Desde ${_formatDate(p.createdAt)}',
                tone: secondaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Ações ──────────────────────────────────────────────────────────────

  Widget _buildActionsSection(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    // Azul (info) para dispositivos/sessões — cor com significado, não rainbow.
    final info =
        isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label: 'AÇÕES'),
        const SizedBox(height: 6),
        _FlatActionRow(
          icon: Icons.tune_rounded,
          tone: accent,
          title: 'Editar dados do perfil',
          subtitle: 'Nome, telefone, foto e informações pessoais.',
          onTap: () => Navigator.pushNamed(context, AppRoutes.profileEdit),
        ),
        _FlatActionRow(
          icon: Icons.devices_outlined,
          tone: info,
          title: 'Sessões e dispositivos',
          subtitle: _sessionCount != null
              ? '$_sessionCount sessã${_sessionCount == 1 ? "o" : "ões"} ativa${_sessionCount == 1 ? "" : "s"}.'
              : 'Gerencie onde sua conta está conectada.',
          trailing: _sessionCount != null
              ? _OutlineCounterBadge(value: '$_sessionCount', tone: info)
              : null,
          onTap: () => SessionsModal.show(context: context)
              .then((_) => _loadSessionCount()),
        ),
      ],
    );
  }

  // ─── Detalhes ───────────────────────────────────────────────────────────

  Widget _buildDetailsSection(BuildContext context, ThemeData theme) {
    final p = _profile!;
    final hasPhone = (p.phone ?? '').trim().isNotEmpty;
    final hasCell = (p.cellphone ?? '').trim().isNotEmpty;
    final hasCompany = (p.companyName ?? '').trim().isNotEmpty;

    String? phoneLabel;
    String? phoneValue;
    if (hasPhone && hasCell) {
      phoneLabel = 'TELEFONE / CELULAR';
      phoneValue =
          '${Masks.phone(p.phone!.trim())}  ·  ${Masks.phone(p.cellphone!.trim())}';
    } else if (hasPhone) {
      phoneLabel = 'TELEFONE';
      phoneValue = Masks.phone(p.phone!.trim());
    } else if (hasCell) {
      phoneLabel = 'CELULAR';
      phoneValue = Masks.phone(p.cellphone!.trim());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label: 'DETALHES DO CADASTRO'),
        const SizedBox(height: 6),
        _FlatInfoRow(
          icon: Icons.person_outline_rounded,
          label: 'Nome completo',
          value: p.name,
        ),
        _FlatInfoRow(
          icon: Icons.mail_outline_rounded,
          label: 'E-mail',
          value: p.email,
        ),
        if (phoneValue != null)
          _FlatInfoRow(
            icon: Icons.phone_iphone_rounded,
            label: phoneLabel!.toLowerCase(),
            value: phoneValue,
          ),
        _FlatInfoRow(
          icon: Icons.workspace_premium_outlined,
          label: 'Cargo / função',
          value: _getRoleLabel(p.role),
        ),
        if (hasCompany)
          _FlatInfoRow(
            icon: Icons.apartment_rounded,
            label: 'Empresa',
            value: p.companyName!.trim(),
          ),
      ],
    );
  }

  // ─── Segurança e privacidade ────────────────────────────────────────────

  Widget _buildPrivacySection(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label: 'SEGURANÇA E PRIVACIDADE'),
        const SizedBox(height: 6),
        _FlatActionRow(
          icon: Icons.lock_outline_rounded,
          tone: accent,
          title: 'Alterar senha',
          subtitle: 'Fluxo seguro · sessões antigas podem ser invalidadas.',
          onTap: () => ChangePasswordModal.show(context: context),
        ),
        _FlatToggleRow(
          icon: Icons.public_rounded,
          tone: green,
          title: 'Presença no site público',
          hint: 'Aparecer na lista de corretores do site.',
          value: _profile?.isAvailableForPublicSite ?? false,
          isLoading: _isUpdatingVisibility,
          onTap: _togglePublicVisibility,
        ),
      ],
    );
  }

  // ─── Skeleton / Error ───────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        Row(
          children: [
            SkeletonBox(width: 88, height: 88, borderRadius: 44),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180, height: 18, borderRadius: 5),
                  SizedBox(height: 8),
                  SkeletonBox(width: 220, height: 13, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 22),
        SkeletonBox(width: 140, height: 11, borderRadius: 4),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
        SizedBox(height: 8),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
        SizedBox(height: 24),
        SkeletonBox(width: 160, height: 11, borderRadius: 4),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
        SizedBox(height: 8),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
      ],
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
            foregroundColor: AppColors.primary.primary,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Widgets de UI (todos flat, sem cards encapsulando)
// ──────────────────────────────────────────────────────────────────────────

/// Eyebrow accent uppercase pequeno — mesmo padrão dos atalhos do corretor,
/// agora com uma pequena barra tonal à esquerda para dar estrutura/refino.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent, accent.withValues(alpha: 0.45)],
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.65,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha de informação flat — ícone outline + label + valor selecionável.
/// Sem chip 44x44 colorido, sem divisor pesado. Apenas hierarquia tipográfica.
class _FlatInfoRow extends StatelessWidget {
  const _FlatInfoRow({
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
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: secondaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
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

/// Linha de ação flat — ícone outline + título + subtítulo + chevron/trailing.
/// Splash sutil no tap. Sem moldura, sem card.
class _FlatActionRow extends StatelessWidget {
  const _FlatActionRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.10),
        highlightColor: tone.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: tone),
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
                        color: textColor,
                        letterSpacing: -0.15,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryColor,
                        height: 1.3,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: secondaryColor.withValues(alpha: 0.55),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha de toggle flat — ícone outline + título + hint + pill switch
/// (mesmo padrão usado no painel de atalhos do corretor).
class _FlatToggleRow extends StatelessWidget {
  const _FlatToggleRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.hint,
    required this.value,
    required this.isLoading,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String hint;
  final bool value;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        splashColor: tone.withValues(alpha: 0.10),
        highlightColor: tone.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: value ? tone : secondaryColor),
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
                        color: value ? tone : textColor,
                        letterSpacing: -0.15,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryColor,
                        height: 1.3,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isLoading)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: tone,
                  ),
                )
              else
                _PillSwitch(active: value, tone: tone),
            ],
          ),
        ),
      ),
    );
  }
}

/// Switch tipo pill — gradient + glow quando on, neutro quando off.
/// Mesma identidade do `_PillSwitch` da `PropertiesPage`.
class _PillSwitch extends StatelessWidget {
  const _PillSwitch({required this.active, required this.tone});
  final bool active;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = ThemeHelpers.borderColor(context);
    final toneDeep = HSLColor.fromColor(tone)
        .withLightness(
          (HSLColor.fromColor(tone).lightness * 0.78).clamp(0.0, 1.0),
        )
        .toColor();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: 48,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: active
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tone, toneDeep],
              )
            : null,
        color: active
            ? null
            : (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : borderColor.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? toneDeep.withValues(alpha: 0.45)
              : borderColor.withValues(alpha: isDark ? 0.30 : 0.30),
          width: 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: tone.withValues(alpha: isDark ? 0.45 : 0.30),
                  blurRadius: 10,
                  spreadRadius: 0.2,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: active ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: active
                ? Icon(
                    Icons.check_rounded,
                    key: const ValueKey('on'),
                    size: 13,
                    color: toneDeep,
                  )
                : const SizedBox.shrink(key: ValueKey('off')),
          ),
        ),
      ),
    );
  }
}

/// Pill outline simples — ícone + label numa única cor (sem fill colorido
/// agressivo). Cor neutra por padrão.
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
        border: Border.all(
          color: tone.withValues(alpha: isDark ? 0.30 : 0.22),
        ),
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

/// Badge outline pra contagem ao lado de um item (ex.: nº de sessões).
class _OutlineCounterBadge extends StatelessWidget {
  const _OutlineCounterBadge({required this.value, required this.tone});
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tone.withValues(alpha: 0.32)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          size: 22,
          color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.55),
        ),
      ],
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
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    const size = 88.0;

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
                            errorBuilder: (_, _, _) => _fallback(context, isDark),
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
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
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
          fontSize: 28,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _AvatarStatusDot extends StatelessWidget {
  const _AvatarStatusDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.status.success
        : ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              fontSize: 10.5,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
