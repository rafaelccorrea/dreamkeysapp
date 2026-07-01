import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/services/settings_service.dart';
import '../../../../shared/services/theme_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/brand_wordmark_logo.dart';
import '../../../../shared/services/app_update_service.dart';
import '../../../../shared/widgets/app_update_dialog.dart';
import '../../../../shared/widgets/skeleton_box.dart';

/// Tela de Configurações — layout editorial aberto.
///
/// Sem cards encapsulando seções: cada bloco respira na página, separado por
/// hierarquia tipográfica (eyebrow uppercase em accent + headline w900) e
/// divisores finos. Paleta coerente atribuída por seção: azul para canais,
/// âmbar para eventos, violeta para aparência, vermelho da marca para conta.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  Settings? _settings;
  Profile? _profile;
  String? _errorMessage;

  String _appVersionLabel = '…';

  // ── Paleta editorial por seção ────────────────────────────────────────
  // Coerente, sem arco-íris. Cada seção tem 1 cor de identidade que tinge
  // o eyebrow, o ícone do tile e o thumb do Switch.
  static const Color _toneChannels = Color(0xFF0EA5E9); // azul céu
  static const Color _toneEvents = Color(0xFFF59E0B); // âmbar
  static const Color _toneAppearance = Color(0xFF8B5CF6); // violeta
  static const Color _toneAccount = Color(0xFFDC2626); // vermelho marca
  static const Color _toneApp = Color(0xFF059669); // verde — atualização

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadData();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionLabel = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _appVersionLabel = '—');
    }
  }

  Future<void> _checkForAppUpdate() async {
    final info = await AppUpdateService.instance.checkForUpdate(force: true);
    if (!mounted) return;
    if (info != null) {
      await showAppUpdateDialog(context, info);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Você já está na versão mais recente disponível.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Color _brand(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Future<void> _loadData() async {
    debugPrint('⚙️ [SETTINGS PAGE] Iniciando carregamento de dados');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settingsResponse = await SettingsService.instance.getSettings();
      final profileResponse = await ProfileService.instance.getProfile();

      if (mounted) {
        setState(() {
          if (settingsResponse.success && settingsResponse.data != null) {
            _settings = settingsResponse.data;
          }
          if (profileResponse.success && profileResponse.data != null) {
            _profile = profileResponse.data;
          }
          _isLoading = false;
          if (_settings == null && _profile == null) {
            _errorMessage = 'Erro ao carregar dados';
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [SETTINGS PAGE] Erro: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateNotificationSetting({
    required bool Function(NotificationSettings) getValue,
    required NotificationSettings Function(NotificationSettings, bool) setValue,
  }) async {
    if (_settings == null) return;

    final currentNotifications = _settings!.notifications;
    final oldValue = getValue(currentNotifications);
    final newValue = !oldValue;

    final updatedNotifications = setValue(currentNotifications, newValue);
    final updatedSettings = Settings(
      notifications: updatedNotifications,
      language: _settings!.language,
      timezone: _settings!.timezone,
    );

    setState(() {
      _settings = updatedSettings;
    });

    final response = await SettingsService.instance.updateSettings(
      updatedSettings,
    );

    if (response.success) {
      if (response.data != null) {
        setState(() => _settings = response.data);
      }
    } else if (mounted) {
      setState(() {
        _settings = Settings(
          notifications: currentNotifications,
          language: _settings!.language,
          timezone: _settings!.timezone,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  response.message ?? 'Erro ao atualizar configuração',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = _brand(context);

    return AppScaffold(
      title: 'Configurações',
      currentBottomNavIndex: 4,
      showBottomNavigation: true,
      body: _isLoading
          ? _buildSkeleton(context, theme, brand)
          : _errorMessage != null && _settings == null && _profile == null
          ? _buildErrorState(context, theme, brand)
          : RefreshIndicator(
              color: brand,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 4, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPageMasthead(context, theme, brand),
                    const SizedBox(height: 18),
                    if (_profile != null)
                      _buildProfileManchete(context, theme, brand, _profile!),
                    if (_profile != null) const SizedBox(height: 14),
                    _buildQuickStrip(context, theme, brand),
                    const SizedBox(height: 14),
                    _sectionSeparator(context),
                    const SizedBox(height: 22),
                    _buildChannelsSection(context, theme),
                    const SizedBox(height: 28),
                    _sectionSeparator(context),
                    const SizedBox(height: 22),
                    _buildEventsSection(context, theme),
                    const SizedBox(height: 28),
                    _sectionSeparator(context),
                    const SizedBox(height: 22),
                    _buildAppearanceSection(context, theme),
                    const SizedBox(height: 28),
                    _sectionSeparator(context),
                    const SizedBox(height: 22),
                    _buildAccountSection(context, theme, brand),
                    const SizedBox(height: 28),
                    _sectionSeparator(context),
                    const SizedBox(height: 22),
                    _buildAppUpdateSection(context, theme),
                    const SizedBox(height: 32),
                    _buildFooterSignature(context, theme, brand),
                  ],
                ),
              ),
            ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SKELETON & ERROR
  // ──────────────────────────────────────────────────────────────────────

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
              children: [
                SkeletonText(width: 90, height: 11),
                const SizedBox(height: 12),
                SkeletonText(width: 220, height: 28),
                const SizedBox(height: 10),
                SkeletonText(width: 280, height: 14),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SkeletonBox(width: 64, height: 64, borderRadius: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 160, height: 17),
                      const SizedBox(height: 6),
                      SkeletonText(width: 200, height: 12),
                      const SizedBox(height: 10),
                      SkeletonText(width: 100, height: 12),
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
                    children: [
                      SkeletonText(width: 40, height: 22),
                      const SizedBox(height: 6),
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
                children: [
                  SkeletonText(width: 70, height: 10),
                  const SizedBox(height: 8),
                  SkeletonText(width: 180, height: 22),
                  const SizedBox(height: 6),
                  SkeletonText(width: 240, height: 12),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < 3; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    SkeletonBox(width: 40, height: 40, borderRadius: 12),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(width: 120, height: 13),
                          const SizedBox(height: 6),
                          SkeletonText(width: 200, height: 11),
                        ],
                      ),
                    ),
                    SkeletonBox(width: 44, height: 26, borderRadius: 13),
                  ],
                ),
              ),
              if (i < 2)
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

  Widget _buildErrorState(BuildContext context, ThemeData theme, Color brand) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Text(
          'ERRO',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.status.error,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Não foi possível carregar',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: ThemeHelpers.textColor(context),
            height: 1.05,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ??
              'Verifique a ligação e tente novamente. Se o problema persistir, contacte o suporte.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 22),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
            style: FilledButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // MASTHEAD — eyebrow + headline + subtítulo (sem hero card)
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildPageMasthead(
    BuildContext context,
    ThemeData theme,
    Color brand,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'PREFERÊNCIAS',
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
                'SINCRONIZADO',
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
            'Configurações',
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
            'Canais de alerta, eventos relevantes e aparência do app. Cada interruptor grava no servidor assim que a API confirma.',
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

  // ──────────────────────────────────────────────────────────────────────
  // MANCHETE DE PERFIL — sem card, layout horizontal explorando a margem
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildProfileManchete(
    BuildContext context,
    ThemeData theme,
    Color brand,
    Profile p,
  ) {
    final since = _formatJoinedSince(p.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _AvatarRing(profile: p, accent: brand, size: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.name.isEmpty ? 'Usuário' : p.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    height: 1.1,
                    letterSpacing: -0.3,
                    fontSize: 17,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  p.email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MetaPill(
                      label: _formatRole(p.role),
                      tone: brand,
                      filled: true,
                    ),
                    if (p.companyName != null &&
                        p.companyName!.trim().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: _MetaPill(
                          label: p.companyName!.trim(),
                          tone: AppColors.secondary.secondary,
                          filled: false,
                        ),
                      ),
                    ],
                  ],
                ),
                if (since != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'NA PLATAFORMA DESDE · ${since.toUpperCase()}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(
                        context,
                      ).withValues(alpha: 0.7),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 9,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _GhostIconButton(
            icon: Icons.edit_rounded,
            tone: brand,
            onTap: () => Navigator.pushNamed(context, AppRoutes.profileEdit),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // QUICK KPI STRIP — 4 colunas separadas por linhas verticais finas
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildQuickStrip(BuildContext context, ThemeData theme, Color brand) {
    final n = _settings?.notifications;
    final channelsActive = [
      n?.email ?? false,
      n?.push ?? false,
      n?.sms ?? false,
    ].where((e) => e).length;
    final eventsActive = [
      n?.newMatches ?? false,
      n?.newMessages ?? false,
      n?.appointmentReminders ?? false,
    ].where((e) => e).length;

    final themeService = ThemeService.instance;
    final themeShort = switch (themeService.themeMode) {
      ThemeMode.light => 'Claro',
      ThemeMode.dark => 'Escuro',
      ThemeMode.system => 'Auto',
    };
    final langShort = _shortLanguage(_settings?.language ?? 'pt-BR');

    final items = <_QuickKpi>[
      _QuickKpi(
        accent: _toneChannels,
        label: 'CANAIS',
        value: '$channelsActive/3',
        sub: 'ativos',
      ),
      _QuickKpi(
        accent: _toneEvents,
        label: 'ALERTAS',
        value: '$eventsActive/3',
        sub: 'eventos',
      ),
      _QuickKpi(
        accent: _toneAppearance,
        label: 'TEMA',
        value: themeShort,
        sub: themeService.themeMode == ThemeMode.system ? 'sistema' : 'manual',
      ),
      _QuickKpi(
        accent: brand,
        label: 'IDIOMA',
        value: langShort,
        sub: 'região',
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

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: CANAIS DE NOTIFICAÇÃO (azul)
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildChannelsSection(BuildContext context, ThemeData theme) {
    final n = _settings?.notifications;
    final activeCount = [
      n?.email ?? false,
      n?.push ?? false,
      n?.sms ?? false,
    ].where((e) => e).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'COMO RECEBER',
          title: 'Canais de notificação',
          subtitle: 'Por onde o app pode te alcançar.',
          rightHint: '$activeCount de 3 ativos',
          tone: _toneChannels,
        ),
        const SizedBox(height: 16),
        _SwitchRow(
          tone: _toneChannels,
          icon: Icons.email_outlined,
          title: 'Email',
          subtitle: 'Resumos diários e ações que precisam de leitura calma.',
          value: n?.email ?? true,
          onChanged: (_) => _updateNotificationSetting(
            getValue: (x) => x.email,
            setValue: (x, v) => x.copyWith(email: v),
          ),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _toneChannels,
          icon: Icons.notifications_active_outlined,
          title: 'Push',
          subtitle:
              'Alertas em tempo real diretamente no aparelho — mesmo com o app fechado.',
          value: n?.push ?? true,
          onChanged: (_) => _updateNotificationSetting(
            getValue: (x) => x.push,
            setValue: (x, v) => x.copyWith(push: v),
          ),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _toneChannels,
          icon: Icons.sms_outlined,
          title: 'SMS',
          subtitle:
              'Reservado para alertas críticos. Pode ter custo da operadora.',
          value: n?.sms ?? false,
          onChanged: (_) => _updateNotificationSetting(
            getValue: (x) => x.sms,
            setValue: (x, v) => x.copyWith(sms: v),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: EVENTOS (âmbar)
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildEventsSection(BuildContext context, ThemeData theme) {
    final n = _settings?.notifications;
    final activeCount = [
      n?.newMatches ?? false,
      n?.newMessages ?? false,
      n?.appointmentReminders ?? false,
    ].where((e) => e).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'O QUE NOTIFICAR',
          title: 'Eventos relevantes',
          subtitle: 'Que momentos merecem chegar até você.',
          rightHint: '$activeCount de 3 ativos',
          tone: _toneEvents,
        ),
        const SizedBox(height: 16),
        _SwitchRow(
          tone: _toneEvents,
          icon: Icons.favorite_rounded,
          title: 'Novos matches',
          subtitle:
              'Cliente combinou com imóvel. Avisa assim que o casamento é detectado.',
          value: n?.newMatches ?? true,
          onChanged: (_) => _updateNotificationSetting(
            getValue: (x) => x.newMatches,
            setValue: (x, v) => x.copyWith(newMatches: v),
          ),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _toneEvents,
          icon: Icons.chat_bubble_outline,
          title: 'Novas mensagens',
          subtitle:
              'Conversas com clientes, equipa e parceiros. Resposta rápida vence venda.',
          value: n?.newMessages ?? true,
          onChanged: (_) => _updateNotificationSetting(
            getValue: (x) => x.newMessages,
            setValue: (x, v) => x.copyWith(newMessages: v),
          ),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _toneEvents,
          icon: Icons.event_available_outlined,
          title: 'Compromissos',
          subtitle:
              'Lembretes de visita, reunião e vistoria com antecedência configurável.',
          value: n?.appointmentReminders ?? true,
          onChanged: (_) => _updateNotificationSetting(
            getValue: (x) => x.appointmentReminders,
            setValue: (x, v) => x.copyWith(appointmentReminders: v),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: APARÊNCIA (violeta)
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildAppearanceSection(BuildContext context, ThemeData theme) {
    final themeService = ThemeService.instance;
    final lang = _settings?.language ?? 'pt-BR';
    final tz = _settings?.timezone ?? 'America/Sao_Paulo';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'COMO VOCÊ VÊ',
          title: 'Aparência & região',
          subtitle: 'Tema visual, idioma da interface e fuso horário.',
          tone: _toneAppearance,
        ),
        const SizedBox(height: 16),
        _NavigationRow(
          tone: _toneAppearance,
          icon: themeService.getThemeIcon(),
          title: 'Tema do app',
          subtitle: 'Atualmente: ${themeService.getThemeName().toLowerCase()}',
          trailing: _ValueChip(
            label: themeService.getThemeName(),
            tone: _toneAppearance,
          ),
          onTap: () => _showThemeSheet(context, _toneAppearance),
        ),
        _rowDivider(context),
        _NavigationRow(
          tone: _toneAppearance,
          icon: Icons.translate_rounded,
          title: 'Idioma',
          subtitle: 'Textos, datas e formatos numéricos da interface.',
          trailing: _ValueChip(
            label: _languageLabel(lang),
            tone: _toneAppearance,
          ),
          onTap: null, // read-only por enquanto
        ),
        _rowDivider(context),
        _NavigationRow(
          tone: _toneAppearance,
          icon: Icons.schedule_rounded,
          title: 'Fuso horário',
          subtitle: 'Horários de agenda exibidos com base neste fuso.',
          trailing: _ValueChip(
            label: _timezoneLabel(tz),
            tone: _toneAppearance,
          ),
          onTap: null,
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: CONTA (vermelho marca)
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildAccountSection(
    BuildContext context,
    ThemeData theme,
    Color brand,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'IDENTIDADE',
          title: 'Conta & perfil',
          subtitle:
              'Seus dados pessoais e como apareces para clientes e equipa.',
          tone: _toneAccount,
        ),
        const SizedBox(height: 16),
        _NavigationRow(
          tone: _toneAccount,
          icon: Icons.person_rounded,
          title: 'Perfil',
          subtitle: 'Nome, telefone, foto e dados de contacto.',
          trailing: Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
        ),
        _rowDivider(context),
        _NavigationRow(
          tone: _toneAccount,
          icon: Icons.edit_note_rounded,
          title: 'Editar perfil',
          subtitle:
              'Altera nome, telefone e foto. Salva ao confirmar no formulário.',
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

  Widget _buildAppUpdateSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'APLICATIVO',
          title: 'Atualização (TestFlight)',
          subtitle:
              'Versão instalada e atalho para instalar o build mais recente no TestFlight.',
          tone: _toneApp,
        ),
        const SizedBox(height: 16),
        _NavigationRow(
          tone: _toneApp,
          icon: Icons.info_outline_rounded,
          title: 'Versão instalada',
          subtitle: 'Build atual neste dispositivo.',
          trailing: _ValueChip(label: _appVersionLabel, tone: _toneApp),
          onTap: null,
        ),
        _rowDivider(context),
        _NavigationRow(
          tone: _toneApp,
          icon: Icons.system_update_alt_rounded,
          title: 'Verificar atualização',
          subtitle: 'Compara com a versão publicada no servidor.',
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          onTap: _checkForAppUpdate,
        ),
        _rowDivider(context),
        _NavigationRow(
          tone: _toneApp,
          icon: Icons.flight_takeoff_rounded,
          title: 'Abrir TestFlight',
          subtitle: 'Instala ou atualiza o app beta direto na loja de testes.',
          trailing: Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          onTap: () => openTestFlightUpdateUrl(),
        ),
        _rowDivider(context),
        _NavigationRow(
          tone: _toneApp,
          icon: Icons.policy_rounded,
          title: 'Política de privacidade',
          subtitle: 'Como coletamos, usamos e compartilhamos seus dados.',
          trailing: Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          onTap: () => openPrivacyPolicyUrl(),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // FOOTER — assinatura editorial
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildFooterSignature(
    BuildContext context,
    ThemeData theme,
    Color brand,
  ) {
    final lang = _shortLanguage(_settings?.language ?? 'pt-BR');
    final themeShort = ThemeService.instance.getThemeName();
    final year = DateTime.now().year;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandWordmarkLogo(
                      height: 26,
                      alignment: Alignment.centerLeft,
                    ),
                    const SizedBox(height: 4),
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
              ),
              const SizedBox(width: 12),
              Text(
                'v$_appVersionLabel',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: brand,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _FooterMeta(label: 'IDIOMA', value: lang),
              _FooterMeta(label: 'TEMA', value: themeShort),
              _FooterMeta(
                label: 'FUSO',
                value: _timezoneLabel(
                  _settings?.timezone ?? 'America/Sao_Paulo',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '© $year Intellisys. Todos os direitos reservados.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(
                context,
              ).withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // HELPERS de layout
  // ──────────────────────────────────────────────────────────────────────

  /// Divisor entre rows da mesma seção — fininho, indentado para alinhar
  /// com o conteúdo (margem H 20).
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

  /// Separador entre seções — linha que sangra de borda a borda para
  /// criar uma "quebra editorial" forte.
  Widget _sectionSeparator(BuildContext context) {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.3),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // THEME SHEET — substitui o `vivid_chrome`. Sheet limpa, sem moldura
  // exagerada, alinhada ao tom violeta da seção Aparência.
  // ──────────────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────────────
  // FORMATTERS
  // ──────────────────────────────────────────────────────────────────────

  String? _formatJoinedSince(String iso) {
    if (iso.isEmpty) return null;
    try {
      final d = DateTime.parse(iso);
      return DateFormat('MMM yyyy', 'pt_BR').format(d);
    } catch (_) {
      return null;
    }
  }

  String _formatRole(String role) {
    final r = role.trim().toLowerCase();
    return switch (r) {
      'master' => 'Master',
      'admin' => 'Admin',
      'broker' => 'Corretor',
      'agent' => 'Corretor',
      'manager' => 'Gestor',
      'user' => 'Usuário',
      _ =>
        role.isEmpty
            ? 'Usuário'
            : '${role[0].toUpperCase()}${role.substring(1).toLowerCase()}',
    };
  }

  String _shortLanguage(String code) {
    final c = code.trim().toLowerCase().replaceAll('_', '-');
    if (c.startsWith('pt')) return 'PT-BR';
    if (c.startsWith('en')) return 'EN';
    if (c.startsWith('es')) return 'ES';
    return c.toUpperCase();
  }

  String _languageLabel(String code) {
    final c = code.trim().toLowerCase().replaceAll('_', '-');
    if (c == 'pt-br' || c == 'pt') return 'Português (BR)';
    if (c == 'pt-pt') return 'Português (PT)';
    if (c.startsWith('en')) return 'English';
    if (c.startsWith('es')) return 'Español';
    return code;
  }

  String _timezoneLabel(String tz) {
    final t = tz.trim();
    if (t.isEmpty) return '—';
    final parts = t.split('/');
    if (parts.length < 2) return t;
    final city = parts.last.replaceAll('_', ' ');
    return city;
  }
}

// ════════════════════════════════════════════════════════════════════════
// COMPONENTES INTERNOS — sem cards encapsulando seções
// ════════════════════════════════════════════════════════════════════════

/// Cabeçalho editorial de seção. Eyebrow uppercase coloridA + título
/// w900 grande + subtítulo opcional + hint à direita (ex. "2 de 3 ativos").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.tone,
    this.subtitle,
    this.rightHint,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final String? rightHint;
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
          if (rightHint != null) ...[
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                rightHint!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Row de switch — full-bleed (sem moldura), padding H 20.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ToneIconPlate(tone: tone, icon: icon, active: value),
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
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: tone,
                activeTrackColor: tone.withValues(alpha: 0.42),
                inactiveTrackColor: ThemeHelpers.borderColor(
                  context,
                ).withValues(alpha: 0.5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
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
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                        color: ThemeHelpers.textColor(
                          context,
                        ).withValues(alpha: disabled ? 0.85 : 1.0),
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

/// Placa de ícone tom-on-tom — usada nos rows de cada seção. Mantém
/// identidade visual da seção (azul/âmbar/violeta/vermelho).
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

/// Chip de valor à direita de uma navigation row (ex. "Escuro", "PT-BR").
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

/// Pill de meta — usada no perfil (role + empresa). Pode ser filled
/// (com fundo tingido) ou outlined (apenas contorno).
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.tone,
    required this.filled,
  });

  final String label;
  final Color tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: filled ? tone.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(
          color: tone.withValues(alpha: filled ? 0.35 : 0.5),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: filled ? ThemeHelpers.textColor(context) : tone,
          letterSpacing: 0.3,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Avatar circular com aro accent fino — sem moldura sombreada
/// pesada. Tem fallback de monograma quando não há foto.
class _AvatarRing extends StatelessWidget {
  const _AvatarRing({
    required this.profile,
    required this.accent,
    required this.size,
  });

  final Profile profile;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        profile.avatar != null && profile.avatar!.trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                profile.avatar!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _Monogram(name: profile.name, accent: accent),
              )
            : _Monogram(name: profile.name, accent: accent),
      ),
    );
  }
}

/// Fallback do avatar — círculo com gradient accent + primeira letra.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, required this.accent});

  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.85),
            AppColors.secondary.secondary.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

/// Botão fantasma redondo — sem fundo. Usado no canto direito da
/// manchete de perfil (atalho para editar).
class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tone.withValues(alpha: 0.32)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: tone, size: 17),
      ),
    );
  }
}

/// Coluna de KPI rápida — valor grande em accent + label uppercase +
/// sub-rótulo sutil + traço accent fino. Igual ao estilo do dashboard.
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
