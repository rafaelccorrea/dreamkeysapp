import 'package:flutter/material.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/shell_visual_tokens.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../widgets/avatar_edit_modal.dart';
import '../widgets/change_password_modal.dart';
import '../widgets/sessions_modal.dart';

/// Perfil — hero inspirado no header do dashboard (foto + coluna textual + pills + faixa de insight).
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

  /// Superfície elevada alinhada ao painel do dashboard (gradiente leve + borda accent).
  BoxDecoration _profilePanelDecoration(BuildContext context) {
    return ShellVisualTokens.elevatedPanelDecoration(
      context,
      _accent(context),
      style: ShellElevatedPanelStyle.profile,
    );
  }

  Widget _profileSectionCard({
    required BuildContext context,
    required ThemeData theme,
    required IconData headerIcon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final accent = _accent(context);
    return Container(
      decoration: _profilePanelDecoration(context),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.14)),
                ),
                child: Icon(headerIcon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 3,
            width: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.12)],
              ),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _detailFieldRow(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final accent = _accent(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accent.withValues(alpha: 0.07),
              border: Border.all(color: accent.withValues(alpha: 0.11)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 21, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52, top: 4, bottom: 4),
      child: Divider(
        height: 1,
        thickness: 1,
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.45),
      ),
    );
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ProfileService.instance.getProfile();

      if (mounted) {
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
        setState(() {
          _sessionCount = r.data!.length;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sessionCount = null);
    }
  }

  Future<void> _handleAvatarChange(String? avatarUrlOrPath) async {
    if (avatarUrlOrPath == null) {
      final response = await ProfileService.instance.removeAvatar();
      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _profile = response.data;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Avatar removido com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao remover avatar'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } else {
      final imageFile = File(avatarUrlOrPath);
      if (!await imageFile.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Arquivo não encontrado'),
            backgroundColor: AppColors.status.error,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final response = await ProfileService.instance.uploadAvatar(imageFile);

        if (mounted) {
          if (response.success && response.data != null) {
            await _loadProfile();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Avatar atualizado com sucesso!'),
                backgroundColor: AppColors.status.success,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(response.message ?? 'Erro ao fazer upload do avatar'),
                backgroundColor: AppColors.status.error,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: ${e.toString()}'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _togglePublicVisibility() async {
    if (_profile == null) return;

    setState(() {
      _isUpdatingVisibility = true;
    });

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao atualizar visibilidade'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingVisibility = false;
        });
      }
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy', 'pt_BR').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatLongDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatTodayLine() {
    return DateFormat("EEEE · d 'de' MMMM", 'pt_BR').format(DateTime.now());
  }

  String _getRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Administrador';
      case 'master':
        return 'Master';
      case 'manager':
        return 'Gerente';
      case 'user':
      default:
        return 'Usuário';
    }
  }

  Widget _buildFilterPill(BuildContext context, IconData icon, String label) {
    final accent = _accent(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: ShellVisualTokens.profileGlassFill(context),
        border: Border.all(color: ShellVisualTokens.profileSectionBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final accent = _accent(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: primary ? accent : ShellVisualTokens.profileGlassFill(context),
          border: Border.all(color: primary ? accent : ShellVisualTokens.profileSectionBorder(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: primary ? Colors.white : accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: primary ? Colors.white : ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHero(context, theme, isDark),
                          const SizedBox(height: 26),
                          _buildPersonalBlock(context, theme),
                          const SizedBox(height: 22),
                          _buildSecurityPresenceSurface(context, theme),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 100, height: 100, borderRadius: 50),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 120, height: 12, borderRadius: 4),
                  const SizedBox(height: 12),
                  SkeletonBox(width: double.infinity, height: 20, borderRadius: 6),
                  const SizedBox(height: 10),
                  SkeletonBox(width: double.infinity, height: 14, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SkeletonBox(width: double.infinity, height: 44, borderRadius: 12),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    final primary = AppColors.primary.primary;

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
          style: TextButton.styleFrom(foregroundColor: primary),
        ),
      ],
    );
  }

  Widget _avatarStack(BuildContext context, ThemeData theme, bool isDark, Profile p) {
    final primary = _accent(context);
    const size = 104.0;

    return Material(
      color: Colors.transparent,
      child: Semantics(
        label: 'Alterar foto de perfil',
        button: true,
        child: InkWell(
          onTap: () {
            AvatarEditModal.show(
              context: context,
              onSave: _handleAvatarChange,
              currentAvatar: p.avatar,
            );
          },
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: [primary, AppColors.secondary.secondary.withValues(alpha: 0.92)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
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
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: ThemeHelpers.cardBackgroundColor(context), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback(BuildContext context, bool isDark) {
    return ColoredBox(
      color: isDark
          ? AppColors.background.backgroundSecondaryDarkMode
          : AppColors.background.backgroundSecondary,
      child: Icon(
        Icons.person_rounded,
        size: 52,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
    );
  }

  Widget _buildSessionsInsight(BuildContext context, ThemeData theme) {
    final primary = _accent(context);
    final count = _sessionCount;

    return InkWell(
      onTap: () {
        SessionsModal.show(context: context).then((_) => _loadSessionCount());
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: ShellVisualTokens.profileGlassFill(context),
          border: Border.all(color: ShellVisualTokens.profileSectionBorder(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withValues(alpha: 0.14),
              ),
              child: Icon(Icons.devices_rounded, color: primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sessões e dispositivos',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    count != null
                        ? '$count sessão${count == 1 ? '' : 'ões'} ativa${count == 1 ? '' : 's'} neste momento.'
                        : 'Carregando visão das sessões…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Gerenciar sessões →',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: ThemeHelpers.textSecondaryColor(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, ThemeData theme, bool isDark) {
    final accent = _accent(context);
    final p = _profile!;
    final firstName = p.name.trim().isEmpty ? 'Usuário' : p.name.trim().split(' ').first;

    final titlesColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PERFIL DA CONTA',
          style: theme.textTheme.labelSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          firstName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            height: 1.05,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          p.email,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.35,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          'Conta ativa · ${_formatLongDate(p.createdAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          _formatTodayLine(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.85),
            fontSize: 12,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final pills = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildFilterPill(context, Icons.badge_outlined, _getRoleLabel(p.role)),
        _buildFilterPill(context, Icons.calendar_month_outlined, 'Membro desde ${_formatDate(p.createdAt)}'),
        if (p.companyName != null && p.companyName!.trim().isNotEmpty)
          _buildFilterPill(context, Icons.apartment_rounded, p.companyName!.trim()),
        _buildFilterPill(
          context,
          Icons.devices_outlined,
          _sessionCount != null ? '$_sessionCount sessões' : 'Sessões…',
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;

        final headerRow = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatarStack(context, theme, isDark, p),
            const SizedBox(width: 14),
            Expanded(child: titlesColumn),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  headerRow,
                  const SizedBox(height: 16),
                  pills,
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatarStack(context, theme, isDark, p),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titlesColumn,
                        const SizedBox(height: 14),
                        pills,
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            _buildSessionsInsight(context, theme),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildQuickChip(
                  context: context,
                  icon: Icons.tune_rounded,
                  label: 'Editar dados',
                  primary: true,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.profileEdit),
                ),
                _buildQuickChip(
                  context: context,
                  icon: Icons.devices_rounded,
                  label: 'Sessões',
                  primary: false,
                  onTap: () {
                    SessionsModal.show(context: context).then((_) => _loadSessionCount());
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPersonalBlock(BuildContext context, ThemeData theme) {
    final p = _profile!;
    String? phoneLabel;
    String? phoneValue;
    final hasPhone = p.phone != null && p.phone!.trim().isNotEmpty;
    final hasCell = p.cellphone != null && p.cellphone!.trim().isNotEmpty;
    if (hasPhone && hasCell) {
      phoneLabel = 'Telefone / celular';
      phoneValue = '${p.phone!.trim()} · ${p.cellphone!.trim()}';
    } else if (hasPhone) {
      phoneLabel = 'Telefone';
      phoneValue = p.phone!.trim();
    } else if (hasCell) {
      phoneLabel = 'Celular';
      phoneValue = p.cellphone!.trim();
    }

    final tiles = <Widget>[
      _detailFieldRow(context, theme, icon: Icons.person_outline_rounded, label: 'Nome completo', value: p.name),
      _detailSeparator(context),
      _detailFieldRow(context, theme, icon: Icons.mail_outline_rounded, label: 'E-mail', value: p.email),
    ];

    if (phoneValue != null) {
      tiles.add(_detailSeparator(context));
      tiles.add(_detailFieldRow(
        context,
        theme,
        icon: Icons.phone_iphone_rounded,
        label: phoneLabel!,
        value: phoneValue,
      ));
    }

    tiles.add(_detailSeparator(context));
    tiles.add(_detailFieldRow(context, theme, icon: Icons.workspace_premium_outlined, label: 'Cargo', value: _getRoleLabel(p.role)));

    return _profileSectionCard(
      context: context,
      theme: theme,
      headerIcon: Icons.badge_outlined,
      title: 'Detalhes do cadastro',
      subtitle: 'Identificação e contato vinculados à sua conta.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: tiles),
    );
  }

  /// Faixa única neutra (sem glow accent): prioriza leitura horizontal; em telas largas senha | presença lado a lado.
  Widget _buildSecurityPresenceSurface(BuildContext context, ThemeData theme) {
    final primary = _accent(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderCol = ThemeHelpers.borderLightColor(context).withValues(alpha: 0.65);
    final stripeColor = isDark
        ? borderCol.withValues(alpha: 0.85)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.44);
    final subtleBg = isDark
        ? Color.alphaBlend(
            cs.surfaceTint.withValues(alpha: 0.06),
            cs.surfaceContainerHighest.withValues(alpha: 0.42),
          )
        : Color.alphaBlend(
            cs.surfaceTint.withValues(alpha: 0.024),
            const Color(0xFFEEF0F5),
          );

    EdgeInsets padWide() =>
        const EdgeInsets.symmetric(horizontal: 18, vertical: 18);

    Widget passwordLane({required EdgeInsets pad}) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => ChangePasswordModal.show(context: context),
          child: Padding(
            padding: pad,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 22,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Senha',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fluxo seguro · sessões antigas podem ser invalidadas.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          height: 1.38,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => ChangePasswordModal.show(context: context),
                  style: TextButton.styleFrom(
                    foregroundColor: ThemeHelpers.textColor(context),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Alterar',
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 18, color: ThemeHelpers.textSecondaryColor(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget visibilityLane({required EdgeInsets pad}) {
      return Padding(
        padding: pad,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.public_rounded,
              size: 22,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Presença no site público',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lista de corretores · visível para novos contatos.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (_isUpdatingVisibility)
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: primary),
              )
            else
              SwitchTheme(
                data: SwitchThemeData(
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return Colors.white;
                    return ThemeHelpers.textSecondaryColor(context);
                  }),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return primary.withValues(alpha: 0.62);
                    }
                    return ThemeHelpers.borderLightColor(context).withValues(alpha: 0.88);
                  }),
                  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                ),
                child: Switch.adaptive(
                  value: _profile?.isAvailableForPublicSite ?? false,
                  onChanged: (_) => _togglePublicVisibility(),
                ),
              ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: subtleBg,
        border: Border(
          top: BorderSide(color: stripeColor),
          bottom: BorderSide(color: stripeColor),
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.075),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;

          if (wide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 52,
                      child: passwordLane(pad: padWide()),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: 14,
                      endIndent: 14,
                      color: borderCol.withValues(alpha: 0.75),
                    ),
                    Expanded(
                      flex: 48,
                      child: visibilityLane(pad: padWide()),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                passwordLane(pad: padWide()),
                Divider(height: 1, thickness: 1, color: borderCol.withValues(alpha: 0.65)),
                visibilityLane(pad: padWide()),
              ],
            );
          },
        ),
    );
  }
}
