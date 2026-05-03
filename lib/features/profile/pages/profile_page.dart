import 'package:flutter/material.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../widgets/avatar_edit_modal.dart';
import '../widgets/change_password_modal.dart';
import '../widgets/sessions_modal.dart';

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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Color _accent(BuildContext context) => AppColors.primary.primary;

  static const Color _colorEmail    = Color(0xFF4A90E2);
  static const Color _colorPhone    = Color(0xFF3FA66B);
  static const Color _colorRole     = Color(0xFFE6B84C);
  static const Color _colorName     = Color(0xFFD32F2F);
  static const Color _colorSessions = Color(0xFF8B5CF6);
  static const Color _colorCompany  = Color(0xFF3FA66B);
  static const Color _colorLock     = Color(0xFF4A90E2);
  static const Color _colorPublic   = Color(0xFF3FA66B);

  // ─── Lógica ──────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await ProfileService.instance.getProfile();
      if (mounted) {
        if (response.success && response.data != null) {
          setState(() { _profile = response.data; _isLoading = false; });
          _loadSessionCount();
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar perfil';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() { _errorMessage = 'Erro ao conectar com o servidor'; _isLoading = false; });
      }
    }
  }

  Future<void> _loadSessionCount() async {
    try {
      final r = await SessionService.instance.getSessions();
      if (!mounted) return;
      if (r.success && r.data != null) setState(() => _sessionCount = r.data!.length);
    } catch (_) {
      if (mounted) setState(() => _sessionCount = null);
    }
  }

  Future<void> _handleAvatarChange(String? avatarUrlOrPath) async {
    if (avatarUrlOrPath == null) {
      final response = await ProfileService.instance.removeAvatar();
      if (mounted) {
        if (response.success && response.data != null) {
          setState(() { _profile = response.data; });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Avatar removido com sucesso'),
            backgroundColor: AppColors.status.success,
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(response.message ?? 'Erro ao remover avatar'),
            backgroundColor: AppColors.status.error,
          ));
        }
      }
    } else {
      final imageFile = File(avatarUrlOrPath);
      if (!await imageFile.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Arquivo não encontrado'),
          backgroundColor: AppColors.status.error,
        ));
        return;
      }
      setState(() { _isLoading = true; });
      try {
        final response = await ProfileService.instance.uploadAvatar(imageFile);
        if (mounted) {
          if (response.success && response.data != null) {
            await _loadProfile();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Avatar atualizado com sucesso!'),
              backgroundColor: AppColors.status.success,
            ));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(response.message ?? 'Erro ao fazer upload do avatar'),
              backgroundColor: AppColors.status.error,
            ));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ));
        }
      } finally {
        if (mounted) setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _togglePublicVisibility() async {
    if (_profile == null) return;
    setState(() { _isUpdatingVisibility = true; });
    try {
      final response = await ProfileService.instance.updatePublicVisibility(
        !_profile!.isAvailableForPublicSite,
      );
      if (mounted) {
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(response.message ?? 'Erro ao atualizar visibilidade'),
            backgroundColor: AppColors.status.error,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: ${e.toString()}'),
          backgroundColor: AppColors.status.error,
        ));
      }
    } finally {
      if (mounted) setState(() { _isUpdatingVisibility = false; });
    }
  }

  // ─── Formatação ──────────────────────────────────────────────────────────

  String _formatDate(String dateString) {
    try {
      return DateFormat('dd/MM/yyyy', 'pt_BR').format(DateTime.parse(dateString));
    } catch (e) { return dateString; }
  }

  String _formatTodayLine() =>
      DateFormat("EEEE · d 'de' MMMM", 'pt_BR').format(DateTime.now());

  String _getRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':   return 'Administrador';
      case 'master':  return 'Master';
      case 'manager': return 'Gerente';
      default:        return 'Usuário';
    }
  }

  // ─── Componentes de layout flat ──────────────────────────────────────────

  /// Cabeçalho de seção: rótulo pequeno + linha full-width.
  Widget _sectionHeader(BuildContext context, ThemeData theme, String label, {Color? color}) {
    final c = color ?? _accent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 13,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: c,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: c,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            thickness: 1,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
          ),
        ],
      ),
    );
  }

  /// Linha de informação flat: ícone colorido + label + valor.
  Widget _infoRow(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool last = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: iconColor.withValues(alpha: isDark ? 0.18 : 0.10),
                  border: Border.all(
                    color: iconColor.withValues(alpha: isDark ? 0.26 : 0.18),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 21, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: iconColor.withValues(alpha: isDark ? 0.80 : 0.70),
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!last)
          Padding(
            padding: const EdgeInsets.only(left: 80),
            child: Divider(
              height: 1,
              thickness: 0.8,
              color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }

  /// Linha de ação flat: ícone + título + subtítulo + chevron.
  Widget _actionRow(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
    bool last = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: iconColor.withValues(alpha: isDark ? 0.18 : 0.10),
                    border: Border.all(
                      color: iconColor.withValues(alpha: isDark ? 0.26 : 0.18),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 21, color: iconColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.55),
                    ),
              ],
            ),
          ),
        ),
        if (!last)
          Padding(
            padding: const EdgeInsets.only(left: 80),
            child: Divider(
              height: 1,
              thickness: 0.8,
              color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }

  // ─── Avatar ──────────────────────────────────────────────────────────────

  Widget _avatarRing(BuildContext context, ThemeData theme, Profile p) {
    final isDark = theme.brightness == Brightness.dark;
    const size = 108.0;
    const ringSize = 116.0;

    return Material(
      color: Colors.transparent,
      child: Semantics(
        label: 'Alterar foto de perfil',
        button: true,
        child: InkWell(
          onTap: () => AvatarEditModal.show(
            context: context,
            onSave: _handleAvatarChange,
            currentAvatar: p.avatar,
          ),
          borderRadius: BorderRadius.circular(ringSize / 2),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Anel na paleta da marca: vermelho → vinho → vermelho escuro
              Container(
                width: ringSize,
                height: ringSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Color(0xFFD32F2F),
                      Color(0xFFE53935),
                      Color(0xFF592722),
                      Color(0xFFB71C1C),
                      Color(0xFF8B1515),
                      Color(0xFFD32F2F),
                    ],
                  ),
                ),
              ),
              // Separador
              Container(
                width: size + 5,
                height: size + 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.background.backgroundDarkMode : Colors.white,
                ),
              ),
              // Foto
              Container(
                width: size,
                height: size,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: p.avatar != null && p.avatar!.isNotEmpty
                    ? Image.network(
                        p.avatar!,
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                        errorBuilder: (_, _, _) => _avatarFallback(context, isDark),
                      )
                    : _avatarFallback(context, isDark),
              ),
              // Botão câmera
              Positioned(
                bottom: 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.background.backgroundDarkMode : Colors.white,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.primary.withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback(BuildContext context, bool isDark) {
    return Container(
      color: isDark ? AppColors.background.backgroundSecondaryDarkMode : const Color(0xFFF0F4F8),
      child: Icon(Icons.person_rounded, size: 50, color: AppColors.primary.primary.withValues(alpha: 0.45)),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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
          onPressed: () { _loadProfile(); _loadSessionCount(); },
          tooltip: 'Atualizar',
        ),
      ],
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _isLoading
            ? Padding(
                key: const ValueKey('loading'),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: _buildSkeleton(context, theme),
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
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHero(context, theme),
                          _buildActionsSection(context, theme),
                          _buildDetailsSection(context, theme),
                          _buildPrivacySection(context, theme),
                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  // ─── Skeleton ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: SkeletonBox(width: 116, height: 116, borderRadius: 58)),
        const SizedBox(height: 16),
        Center(child: SkeletonBox(width: 160, height: 22, borderRadius: 6)),
        const SizedBox(height: 10),
        Center(child: SkeletonBox(width: 220, height: 14, borderRadius: 4)),
        const SizedBox(height: 28),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
        const SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
        const SizedBox(height: 24),
        SkeletonBox(width: 120, height: 12, borderRadius: 4),
        const SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
        const SizedBox(height: 8),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
        const SizedBox(height: 8),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
      ],
    );
  }

  // ─── Error ────────────────────────────────────────────────────────────────

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_off_outlined, size: 52, color: AppColors.status.error.withValues(alpha: 0.9)),
        const SizedBox(height: 20),
        Text(
          'Não foi possível carregar',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          _errorMessage ?? '',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.45,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        TextButton.icon(
          onPressed: _loadProfile,
          icon: const Icon(Icons.refresh),
          label: const Text('Tentar de novo'),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary.primary),
        ),
      ],
    );
  }

  // ─── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final amber  = AppColors.status.warning;
    final wine   = AppColors.secondary.secondary;
    final p = _profile!;
    final nameParts  = p.name.trim().split(' ');
    final firstName  = nameParts.isNotEmpty ? nameParts.first : 'Usuário';
    final lastName   = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + info lado a lado
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _avatarRing(context, theme, p),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge de perfil
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(colors: [accent, AppColors.secondary.secondary]),
                      ),
                      child: Text(
                        'PERFIL DA CONTA',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Nome em duas linhas se necessário
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$firstName ',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              height: 1.1,
                            ),
                          ),
                          if (lastName.isNotEmpty)
                            TextSpan(
                              text: lastName,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: ThemeHelpers.textColor(context),
                                height: 1.1,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // E-mail
                    Row(
                      children: [
                        Icon(Icons.mail_rounded, size: 13, color: _colorEmail),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            p.email,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Status ativo
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.status.success,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.status.success.withValues(alpha: 0.5),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Ativo · membro desde ${_formatDate(p.createdAt)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Linha separadora
          Divider(
            height: 1,
            thickness: 0.8,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
          ),
          const SizedBox(height: 18),
          // Pills de contexto
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill(context, theme, Icons.badge_outlined, _getRoleLabel(p.role), _colorName),
              _heroPill(context, theme, Icons.calendar_month_outlined,
                  'Desde ${_formatDate(p.createdAt)}', _colorEmail),
              if (p.companyName != null && p.companyName!.trim().isNotEmpty)
                _heroPill(context, theme, Icons.apartment_rounded, p.companyName!.trim(), _colorCompany),
              _heroPill(
                context, theme,
                Icons.devices_outlined,
                _sessionCount != null ? '$_sessionCount sessões ativas' : 'Sessões…',
                _colorSessions,
              ),
              _heroPill(context, theme, Icons.today_outlined, _formatTodayLine(), accent),
            ],
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // Base quente neutra — bege/creme no light, charcoal quente no dark
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF14100F), Color(0xFF0E0A0A)]
              : const [Color(0xFFFCF9F7), Color(0xFFF5EFEB)],
        ),
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Glow vermelho radial atrás do avatar (canto superior esquerdo)
          Positioned(
            left: -80,
            top: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: isDark ? 0.32 : 0.18),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Glow âmbar/dourado no canto superior direito (calor + premium)
          Positioned(
            right: -100,
            top: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    amber.withValues(alpha: isDark ? 0.18 : 0.16),
                    amber.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Glow vinho profundo no canto inferior direito (ancoragem da paleta)
          Positioned(
            right: -120,
            bottom: -90,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    wine.withValues(alpha: isDark ? 0.26 : 0.10),
                    wine.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Conteúdo
          content,
        ],
      ),
    );
  }

  Widget _heroPill(BuildContext context, ThemeData theme, IconData icon, String label, Color color) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: isDark ? 0.15 : 0.09),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.30 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
                fontSize: 11.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Seção de ações ───────────────────────────────────────────────────────

  Widget _buildActionsSection(BuildContext context, ThemeData theme) {
    final accent = _accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, theme, 'AÇÕES', color: accent),
        _actionRow(
          context, theme,
          icon: Icons.tune_rounded,
          iconColor: accent,
          title: 'Editar dados do perfil',
          subtitle: 'Nome, telefone, foto e informações pessoais.',
          onTap: () => Navigator.pushNamed(context, AppRoutes.profileEdit),
        ),
        _actionRow(
          context, theme,
          icon: Icons.devices_rounded,
          iconColor: _colorSessions,
          title: 'Sessões e dispositivos',
          subtitle: _sessionCount != null
              ? '$_sessionCount sessão${_sessionCount == 1 ? '' : 'ões'} ativa${_sessionCount == 1 ? '' : 's'} neste momento.'
              : 'Gerencie onde sua conta está conectada.',
          onTap: () => SessionsModal.show(context: context).then((_) => _loadSessionCount()),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_sessionCount != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: _colorSessions.withValues(alpha: 0.15),
                  ),
                  child: Text(
                    '$_sessionCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _colorSessions,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.55),
              ),
            ],
          ),
          last: true,
        ),
      ],
    );
  }

  // ─── Seção de detalhes ────────────────────────────────────────────────────

  Widget _buildDetailsSection(BuildContext context, ThemeData theme) {
    final p = _profile!;
    final hasPhone = p.phone != null && p.phone!.trim().isNotEmpty;
    final hasCell  = p.cellphone != null && p.cellphone!.trim().isNotEmpty;

    String? phoneLabel;
    String? phoneValue;
    if (hasPhone && hasCell) {
      phoneLabel = 'TELEFONE / CELULAR';
      phoneValue = '${p.phone!.trim()}  ·  ${p.cellphone!.trim()}';
    } else if (hasPhone) {
      phoneLabel = 'TELEFONE';
      phoneValue = p.phone!.trim();
    } else if (hasCell) {
      phoneLabel = 'CELULAR';
      phoneValue = p.cellphone!.trim();
    }

    final hasCompany = p.companyName != null && p.companyName!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, theme, 'DETALHES DO CADASTRO', color: _colorEmail),
        _infoRow(context, theme,
          icon: Icons.person_rounded,
          iconColor: _colorName,
          label: 'NOME COMPLETO',
          value: p.name,
        ),
        _infoRow(context, theme,
          icon: Icons.mail_rounded,
          iconColor: _colorEmail,
          label: 'E-MAIL',
          value: p.email,
        ),
        if (phoneValue != null)
          _infoRow(context, theme,
            icon: Icons.phone_iphone_rounded,
            iconColor: _colorPhone,
            label: phoneLabel!,
            value: phoneValue,
          ),
        _infoRow(context, theme,
          icon: Icons.workspace_premium_rounded,
          iconColor: _colorRole,
          label: 'CARGO / FUNÇÃO',
          value: _getRoleLabel(p.role),
          last: !hasCompany,
        ),
        if (hasCompany)
          _infoRow(context, theme,
            icon: Icons.apartment_rounded,
            iconColor: _colorCompany,
            label: 'EMPRESA',
            value: p.companyName!.trim(),
            last: true,
          ),
      ],
    );
  }

  // ─── Seção de segurança e privacidade ────────────────────────────────────

  Widget _buildPrivacySection(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, theme, 'SEGURANÇA E PRIVACIDADE', color: _colorLock),
        // Alterar senha
        _actionRow(
          context, theme,
          icon: Icons.lock_rounded,
          iconColor: _colorLock,
          title: 'Alterar senha',
          subtitle: 'Fluxo seguro · sessões antigas podem ser invalidadas.',
          onTap: () => ChangePasswordModal.show(context: context),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: _colorLock.withValues(alpha: isDark ? 0.18 : 0.10),
              border: Border.all(color: _colorLock.withValues(alpha: 0.22)),
            ),
            child: Text(
              'Alterar',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _colorLock,
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
              ),
            ),
          ),
        ),
        // Visibilidade pública
        _actionRow(
          context, theme,
          icon: Icons.public_rounded,
          iconColor: _colorPublic,
          title: 'Presença no site público',
          subtitle: 'Lista de corretores · visível para novos contatos.',
          onTap: _togglePublicVisibility,
          trailing: _isUpdatingVisibility
              ? SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: _colorPublic),
                )
              : SwitchTheme(
                  data: SwitchThemeData(
                    thumbColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected) ? Colors.white : ThemeHelpers.textSecondaryColor(context)),
                    trackColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? _colorPublic.withValues(alpha: 0.70)
                            : ThemeHelpers.borderLightColor(context).withValues(alpha: 0.88)),
                    trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                  ),
                  child: Switch.adaptive(
                    value: _profile?.isAvailableForPublicSite ?? false,
                    onChanged: (_) => _togglePublicVisibility(),
                  ),
                ),
          last: true,
        ),
      ],
    );
  }
}
