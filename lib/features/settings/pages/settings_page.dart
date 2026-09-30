import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart'
    hide UserPreferences;
import '../../../../shared/services/settings_service.dart';
import '../../../../shared/services/theme_service.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/brand_wordmark_logo.dart';
import '../../../../shared/widgets/app_update_dialog.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import 'notification_preferences_page.dart';

/// Tela de Configurações — layout editorial aberto.
///
/// Grava em `/user-preferences` (paridade com o SettingsPage do imobx-front):
/// canais, avisos na tela, os dois avisos de lead, a regra de sobreposição da
/// agenda e o tema. Cada interruptor manda só o bloco que mudou (o back funde)
/// e só conta como salvo quando a API confirma; erro volta o valor anterior.
///
/// Abre respondendo "o que está ligado para mim": um sumário com a resposta
/// de cada grupo (3 de 4 canais, 12 de 14 assuntos…) que leva direto à
/// seção. As seções são linhas flush com filete, interruptores alinhados à
/// direita e a contagem no cabeçalho. Um tom só (azul de informação, por
/// token); âmbar só quando algo desligado faz você deixar de receber.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  UserPreferences? _prefs;
  List<NotificationCategoryMeta>? _catalog;
  Profile? _profile;
  int _savingCount = 0;
  String? _errorMessage;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;
  ErrorCause? _errorCause;

  String _appVersionLabel = '…';

  // ── Cor da tela ───────────────────────────────────────────────────────
  // Um tom só, por token: o azul de informação — quase tudo aqui é "por
  // onde o sistema fala com você". Por cima dele, só significado: âmbar
  // quando algo está desligado a ponto de você deixar de receber; verde
  // quando a API confirmou a gravação.
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _tone =>
      _isDark ? AppColors.message.infoTextDarkMode : AppColors.message.infoText;

  Color get _attention => _isDark
      ? AppColors.message.warningTextDarkMode
      : AppColors.message.warningText;

  Color get _saved => _isDark
      ? AppColors.message.successTextDarkMode
      : AppColors.message.successText;

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

  Color _brand(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorStatus = 0;
      _errorCause = null;
    });

    try {
      // As três partem juntas (preferências, perfil e catálogo de assuntos).
      final prefsFuture = SettingsService.instance.getPreferences();
      final profileFuture = ProfileService.instance.getProfile();
      final catalogFuture = SettingsService.instance
          .getNotificationCategories();
      final prefsResponse = await prefsFuture;
      final profileResponse = await profileFuture;
      final catalogResponse = await catalogFuture;

      if (mounted) {
        setState(() {
          _prefs = prefsResponse.success ? prefsResponse.data : null;
          if (profileResponse.success && profileResponse.data != null) {
            _profile = profileResponse.data;
          }
          _catalog = catalogResponse.success ? catalogResponse.data : null;
          _isLoading = false;
          // Sem as preferências a tela não tem o que mostrar nem onde gravar:
          // erro real, nada de padrões fingindo que carregou.
          if (_prefs == null) {
            _errorMessage =
                prefsResponse.message ??
                'Não deu para carregar as preferências.';
            _errorStatus = prefsResponse.statusCode;
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[SETTINGS PAGE] Erro: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _errorCause = ErrorCause.fromException(e);
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  /// Funde recursivamente [patch] em [base] — o mesmo merge que o back faz,
  /// para o interruptor refletir a escolha enquanto a API confirma.
  static Map<String, dynamic> _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic>? patch,
  ) {
    if (patch == null) return base;
    final out = Map<String, dynamic>.of(base);
    patch.forEach((key, value) {
      final current = out[key];
      if (value is Map && current is Map) {
        out[key] = _deepMerge(
          Map<String, dynamic>.from(current),
          Map<String, dynamic>.from(value),
        );
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  UserPreferences _applyLocal(UserPreferences p, Map<String, dynamic> body) {
    Map<String, dynamic>? section(String k) =>
        body[k] is Map ? Map<String, dynamic>.from(body[k] as Map) : null;
    return UserPreferences(
      themeSettings: _deepMerge(p.themeSettings, section('themeSettings')),
      notificationSettings: _deepMerge(
        p.notificationSettings,
        section('notificationSettings'),
      ),
      layoutSettings: _deepMerge(p.layoutSettings, section('layoutSettings')),
      generalSettings: _deepMerge(
        p.generalSettings,
        section('generalSettings'),
      ),
      updatedAt: p.updatedAt,
    );
  }

  /// Grava um bloco em PUT /user-preferences. Otimista na tela; se a API
  /// recusar, volta ao valor anterior e mostra a causa.
  Future<void> _savePatch(Map<String, dynamic> body) async {
    final before = _prefs;
    if (before == null) return;

    setState(() {
      _prefs = _applyLocal(before, body);
      _savingCount++;
    });

    final response = await SettingsService.instance.updatePreferences(body);
    if (!mounted) return;

    setState(() {
      _savingCount = _savingCount > 0 ? _savingCount - 1 : 0;
      if (response.success && response.data != null) {
        _prefs = response.data;
      } else {
        _prefs = before;
      }
    });

    if (!response.success) {
      _showError(response.message ?? 'Não deu para salvar as preferências.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.status.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleChannel(String channel) {
    final p = _prefs;
    if (p == null) return;
    var email = p.emailChannel;
    var push = p.pushChannel;
    var inApp = p.inAppChannel;
    var whatsapp = p.whatsappChannel;
    switch (channel) {
      case 'email':
        email = !email;
      case 'push':
        push = !push;
      case 'inApp':
        inApp = !inApp;
      case 'whatsapp':
        whatsapp = !whatsapp;
    }
    _savePatch({
      'notificationSettings': SettingsService.channelsPayload(
        email: email,
        push: push,
        inApp: inApp,
        whatsapp: whatsapp,
      ),
    });
  }

  void _setLeadEvent(String key, LeadEventPreference next) {
    _savePatch({
      'notificationSettings': {
        'events': {key: next.toJson()},
      },
    });
  }

  /// Tema: o app aplica na hora (como o web) e grava claro/escuro no back.
  /// "Sistema" é só do aparelho — o back não tem esse valor.
  Future<void> _applyTheme(ThemeMode mode) async {
    await ThemeService.instance.setThemeMode(mode);
    if (mounted) setState(() {});
    final p = _prefs;
    if (p == null || mode == ThemeMode.system) return;
    final theme = mode == ThemeMode.dark ? 'dark' : 'light';
    if (p.themeSettings['theme'] == theme) return;
    await _savePatch({
      'themeSettings': {'theme': theme, 'language': p.language},
    });
  }

  Future<void> _openNotificationPreferences() async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => const NotificationPreferencesPage(),
      ),
    );
    if (!mounted) return;
    // As escolhas por assunto podem ter mudado lá dentro.
    final res = await SettingsService.instance.getPreferences();
    if (mounted && res.success && res.data != null && _savingCount == 0) {
      setState(() => _prefs = res.data);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // LAYOUT
  // ──────────────────────────────────────────────────────────────────────

  // Âncoras das seções: cada linha do resumo leva direto à sua.
  final GlobalKey _channelsKey = GlobalKey();
  final GlobalKey _screenKey = GlobalKey();
  final GlobalKey _leadsKey = GlobalKey();
  final GlobalKey _subjectsKey = GlobalKey();
  final GlobalKey _agendaKey = GlobalKey();
  final GlobalKey _appearanceKey = GlobalKey();

  /// Abre Meu perfil ou a edição e, na volta, relê só o perfil (sem piscar
  /// o skeleton) para a linha de quem é mostrar nome e foto novos.
  Future<void> _openProfileRoute(String route) async {
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    final res = await ProfileService.instance.getProfile();
    if (mounted && res.success && res.data != null) {
      setState(() => _profile = res.data);
    }
  }

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  /// Em tela larga (tablet, landscape grande) a coluna para em
  /// [_kMaxContentWidth] e centraliza: interruptor longe do rótulo não lê.
  EdgeInsets _pagePadding({double top = 0, double bottom = 0}) {
    final w = MediaQuery.sizeOf(context).width;
    final side = w > _kMaxContentWidth ? (w - _kMaxContentWidth) / 2 : 0.0;
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  @override
  Widget build(BuildContext context) {
    final brand = _brand(context);

    return AppScaffold(
      title: 'Configurações',
      currentBottomNavIndex: 4,
      showBottomNavigation: true,
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null && _prefs == null
          ? _buildErrorState()
          : RefreshIndicator(
              color: brand,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: _pagePadding(top: 6, bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_profile != null) ...[
                      _buildWhoRow(context, brand, _profile!),
                      const SizedBox(height: 6),
                      _hairline(context),
                    ],
                    const SizedBox(height: 20),
                    _buildSummary(context),
                    _sectionBreak(context),
                    KeyedSubtree(
                      key: _channelsKey,
                      child: _buildChannelsSection(context),
                    ),
                    _sectionBreak(context),
                    KeyedSubtree(
                      key: _screenKey,
                      child: _buildScreenAlertsSection(context),
                    ),
                    _sectionBreak(context),
                    KeyedSubtree(
                      key: _leadsKey,
                      child: _buildEventsSection(context),
                    ),
                    _sectionBreak(context),
                    KeyedSubtree(
                      key: _subjectsKey,
                      child: _buildSubjectsSection(context),
                    ),
                    _sectionBreak(context),
                    KeyedSubtree(
                      key: _agendaKey,
                      child: _buildAgendaSection(context),
                    ),
                    _sectionBreak(context),
                    KeyedSubtree(
                      key: _appearanceKey,
                      child: _buildAppearanceSection(context),
                    ),
                    _sectionBreak(context),
                    _buildAboutSection(context),
                    const SizedBox(height: 30),
                    _buildFooterSignature(context, brand),
                  ],
                ),
              ),
            ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SKELETON & ERROR
  // ──────────────────────────────────────────────────────────────────────

  /// Espelha a tela real: linha de quem é, resumo com respostas e uma seção
  /// de interruptores.
  Widget _buildSkeleton(BuildContext context) {
    final hair = ThemeHelpers.borderColor(context).withValues(alpha: 0.3);

    Widget summaryRow() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
      child: Row(
        children: [
          SkeletonBox(width: 18, height: 18, borderRadius: 5),
          SizedBox(width: 12),
          Expanded(child: SkeletonText(width: 110, height: 13)),
          SizedBox(width: 10),
          SkeletonText(width: 54, height: 13),
        ],
      ),
    );

    Widget switchRow() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
      child: Row(
        children: [
          SkeletonBox(width: 40, height: 40, borderRadius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 120, height: 13),
                SizedBox(height: 6),
                SkeletonText(width: 190, height: 11),
              ],
            ),
          ),
          SizedBox(width: 10),
          SkeletonBox(width: 44, height: 26, borderRadius: 13),
        ],
      ),
    );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: _pagePadding(top: 6, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _kPadH, vertical: 10),
            child: Row(
              children: [
                SkeletonBox(width: 48, height: 48, borderRadius: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 150, height: 15),
                      SizedBox(height: 6),
                      SkeletonText(width: 190, height: 11),
                      SizedBox(height: 6),
                      SkeletonText(width: 120, height: 10),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                SkeletonBox(width: 76, height: 32, borderRadius: 999),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: hair),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _kPadH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 230, height: 20),
                SizedBox(height: 8),
                SkeletonText(width: 90, height: 12),
                SizedBox(height: 8),
                SkeletonText(width: 270, height: 11),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < 6; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 46, right: _kPadH),
                child: Container(height: 1, color: hair),
              ),
            summaryRow(),
          ],
          const SizedBox(height: 22),
          Container(height: 1, color: hair),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _kPadH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 110, height: 18),
                SizedBox(height: 8),
                SkeletonText(width: 250, height: 11),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < 4; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(
                  left: _kRowTextInset,
                  right: _kPadH,
                ),
                child: Container(height: 1, color: hair),
              ),
            switchRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    // Exceção solta traz seu próprio diagnóstico; falha de API vem da resposta.
    final cause = _errorCause;
    if (cause != null) {
      return AppErrorState(cause: cause, onRetry: _loadData);
    }
    return AppErrorState.fromApi(
      message: _errorMessage,
      statusCode: _errorStatus,
      onRetry: _loadData,
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // DE QUEM SÃO ESTAS PREFERÊNCIAS — uma linha; o perfil mora em Meu perfil
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildWhoRow(BuildContext context, Color brand, Profile p) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final company = (p.companyName ?? '').trim();
    final role = _formatRole(p.role);
    final name = p.name.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProfileRoute(AppRoutes.profile),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 10),
          child: Row(
            children: [
              _AvatarRing(profile: p, accent: brand, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isEmpty ? 'Seu perfil' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        height: 1.15,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      company.isEmpty ? role : '$role · $company',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _SmallActionPill(
                icon: Icons.edit_rounded,
                label: 'Editar',
                tone: brand,
                onTap: () => _openProfileRoute(AppRoutes.profileEdit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // RESUMO — sumário com resposta: cada linha diz o estado e leva à seção
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    final p = _prefs;
    final text = ThemeHelpers.textColor(context);

    int countOn(List<bool> v) => v.where((e) => e).length;

    // A cor da resposta é significado: tudo ligado no tom da tela, parte
    // ligada em texto comum, nada ligado em âmbar (você deixa de receber).
    Color answerColor(int on, int of) {
      if (of > 0 && on == 0) return _attention;
      return on == of ? _tone : text;
    }

    final channels = p == null
        ? 0
        : countOn([
            p.inAppChannel,
            p.emailChannel,
            p.pushChannel,
            p.whatsappChannel,
          ]);
    final screen = p == null
        ? 0
        : countOn([p.sound, p.leadEventToasts, p.celebrations]);
    final leads = p == null
        ? 0
        : countOn([
            p.leadEvent(SettingsService.leadTransferEvent).enabled,
            p.leadEvent(SettingsService.leadWhatsappEvent).enabled,
          ]);
    final catalog = _catalog;
    final silenceable =
        catalog?.where((c) => c.silenciavel).toList() ??
        const <NotificationCategoryMeta>[];
    final subjectsOn = p == null
        ? 0
        : silenceable.where((c) => p.category(c.key).enabled).length;
    final allowOverlap = p?.calendarAllowOverlappingSlots ?? false;
    final themeService = ThemeService.instance;

    final items = <_SummaryItem>[
      _SummaryItem(
        icon: Icons.forum_outlined,
        label: 'Canais',
        answer: '$channels de 4',
        color: answerColor(channels, 4),
        anchor: _channelsKey,
      ),
      _SummaryItem(
        icon: Icons.notifications_active_outlined,
        label: 'Avisos na tela',
        answer: '$screen de 3',
        color: answerColor(screen, 3),
        anchor: _screenKey,
      ),
      _SummaryItem(
        icon: Icons.contact_phone_outlined,
        label: 'Avisos de lead',
        answer: '$leads de 2',
        color: answerColor(leads, 2),
        anchor: _leadsKey,
      ),
      _SummaryItem(
        icon: Icons.tune_rounded,
        label: 'Assuntos',
        answer: catalog == null
            ? 'Não carregou'
            : '$subjectsOn de ${silenceable.length}',
        color: catalog == null
            ? _attention
            : answerColor(subjectsOn, silenceable.length),
        anchor: _subjectsKey,
      ),
      _SummaryItem(
        icon: Icons.event_outlined,
        label: 'Horário repetido',
        answer: allowOverlap ? 'Permite' : 'Bloqueia',
        color: text,
        anchor: _agendaKey,
      ),
      _SummaryItem(
        icon: themeService.getThemeIcon(),
        label: 'Tema do app',
        answer: themeService.getThemeName(),
        color: text,
        anchor: _appearanceKey,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPadH),
          child: Text(
            'O que está ligado para você',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.15,
              color: text,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Estado da gravação logo abaixo do título (ao lado dele, em 320dp
        // com fonte grande, o título quebrava em três linhas).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPadH),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _SaveState(saving: _savingCount > 0, savedColor: _saved),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPadH),
          child: Text(
            'Toque numa linha para ir ao ajuste. Cada interruptor grava na hora e volta sozinho se a gravação falhar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) _rowDivider(context, indent: 46),
          _SummaryRow(
            item: items[i],
            tone: _tone,
            onTap: () => _jumpTo(items[i].anchor),
          ),
        ],
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: CANAIS
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildChannelsSection(BuildContext context) {
    final p = _prefs;
    final activeCount = p == null
        ? 0
        : [
            p.inAppChannel,
            p.emailChannel,
            p.pushChannel,
            p.whatsappChannel,
          ].where((e) => e).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Canais',
          subtitle:
              'Por onde o sistema fala com você. O que chega por cada um se ajusta em Assuntos.',
          trailing: '$activeCount de 4 ligados',
          trailingColor: activeCount == 0 ? _attention : _tone,
          tone: _tone,
        ),
        const SizedBox(height: 8),
        _SwitchRow(
          tone: _tone,
          icon: Icons.notifications_none_rounded,
          title: 'Sino do sistema',
          subtitle: 'O painel de avisos dentro do app.',
          value: p?.inAppChannel ?? true,
          onChanged: (_) => _toggleChannel('inApp'),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _tone,
          icon: Icons.email_outlined,
          title: 'E-mail',
          subtitle: 'No e-mail da sua conta.',
          value: p?.emailChannel ?? true,
          onChanged: (_) => _toggleChannel('email'),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _tone,
          icon: Icons.phone_android_rounded,
          title: 'Push no celular',
          subtitle: 'Chega mesmo com o app fechado.',
          value: p?.pushChannel ?? true,
          onChanged: (_) => _toggleChannel('push'),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _tone,
          icon: Icons.chat_outlined,
          title: 'WhatsApp',
          subtitle: 'No seu número de WhatsApp.',
          value: p?.whatsappChannel ?? true,
          onChanged: (_) => _toggleChannel('whatsapp'),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: AVISOS NA TELA
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildScreenAlertsSection(BuildContext context) {
    final p = _prefs;
    final on = p == null
        ? 0
        : [p.sound, p.leadEventToasts, p.celebrations].where((e) => e).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Avisos na tela',
          subtitle: 'O que aparece por cima do que você está fazendo.',
          trailing: '$on de 3 ligados',
          trailingColor: on == 0 ? _attention : _tone,
          tone: _tone,
        ),
        const SizedBox(height: 8),
        _SwitchRow(
          tone: _tone,
          icon: Icons.volume_up_outlined,
          title: 'Som ao receber',
          subtitle: 'Um toque curto quando chega mensagem ou aviso.',
          value: p?.sound ?? true,
          onChanged: (v) => _savePatch({
            'notificationSettings': {'sound': v},
          }),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _tone,
          icon: Icons.campaign_outlined,
          title: 'Popups de lead',
          subtitle:
              'Lead novo, atribuído ou perdido aparece num popup. O sino não muda.',
          value: p?.leadEventToasts ?? false,
          onChanged: (v) => _savePatch({
            'notificationSettings': {'leadEventToasts': v},
          }),
        ),
        _rowDivider(context),
        _SwitchRow(
          tone: _tone,
          icon: Icons.celebration_outlined,
          title: 'Comemorações',
          subtitle:
              'Confete quando alguém da empresa fecha venda ou locação.',
          value: p?.celebrations ?? true,
          onChanged: (v) => _savePatch({
            'notificationSettings': {'celebrations': v},
          }),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: AVISOS DE LEAD
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildEventsSection(BuildContext context) {
    final p = _prefs;
    if (p == null) return const SizedBox.shrink();
    final transfer = p.leadEvent(SettingsService.leadTransferEvent);
    final whatsapp = p.leadEvent(SettingsService.leadWhatsappEvent);
    final activeCount = [
      transfer.enabled,
      whatsapp.enabled,
    ].where((e) => e).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Avisos de lead',
          subtitle: 'Ligue o aviso e marque por onde ele chega.',
          trailing: '$activeCount de 2 ligados',
          trailingColor: activeCount == 0 ? _attention : _tone,
          tone: _tone,
        ),
        const SizedBox(height: 8),
        _leadEventBlock(
          context,
          SettingsService.leadTransferEvent,
          Icons.swap_horiz_rounded,
          'Lead transferido para você',
          transfer,
        ),
        _rowDivider(context),
        _leadEventBlock(
          context,
          SettingsService.leadWhatsappEvent,
          Icons.chat_outlined,
          'Lead novo pelo WhatsApp',
          whatsapp,
        ),
      ],
    );
  }

  Widget _leadEventBlock(
    BuildContext context,
    String key,
    IconData icon,
    String title,
    LeadEventPreference ev,
  ) {
    const channels = [
      ('inApp', 'Sino'),
      ('email', 'E-mail'),
      ('whatsapp', 'WhatsApp'),
    ];
    bool valueOf(String c) => switch (c) {
      'inApp' => ev.inApp,
      'email' => ev.email,
      _ => ev.whatsapp,
    };
    LeadEventPreference toggled(String c) => switch (c) {
      'inApp' => ev.copyWith(inApp: !ev.inApp),
      'email' => ev.copyWith(email: !ev.email),
      _ => ev.copyWith(whatsapp: !ev.whatsapp),
    };

    // A linha diz por onde o aviso chega hoje, sem precisar ler os chips.
    final marked = [
      for (final (c, label) in channels)
        if (valueOf(c)) label,
    ];
    final String subtitle;
    if (!ev.enabled) {
      subtitle = 'Desligado: não avisa.';
    } else if (marked.isEmpty) {
      subtitle = 'Ligado, mas sem canal marcado.';
    } else {
      subtitle = 'Chega por ${marked.join(', ')}.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwitchRow(
          tone: _tone,
          icon: icon,
          title: title,
          subtitle: subtitle,
          value: ev.enabled,
          onChanged: (v) => _setLeadEvent(key, ev.copyWith(enabled: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_kRowTextInset, 0, _kPadH, 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (c, label) in channels)
                _ChannelToggleChip(
                  label: label,
                  on: ev.enabled && valueOf(c),
                  tone: _tone,
                  onTap: ev.enabled
                      ? () => _setLeadEvent(key, toggled(c))
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: ASSUNTOS — resumo + página dedicada
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildSubjectsSection(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final p = _prefs;
    final catalog = _catalog;
    final silenceable =
        catalog?.where((c) => c.silenciavel).toList() ??
        const <NotificationCategoryMeta>[];
    final on = p == null
        ? 0
        : silenceable.where((c) => p.category(c.key).enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Assuntos',
          subtitle:
              'Financeiro, imóveis, leads… o que chega e por onde, assunto a assunto.',
          trailing: catalog == null
              ? null
              : '$on de ${silenceable.length} ligados',
          trailingColor: silenceable.isNotEmpty && on == 0
              ? _attention
              : _tone,
          tone: _tone,
        ),
        const SizedBox(height: 12),
        if (catalog == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kPadH),
            child: Text(
              'Não deu para ler a lista de assuntos. Puxe a tela para baixo para tentar de novo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _attention,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kPadH),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in catalog)
                  _SubjectPill(
                    label: c.label,
                    on: !c.silenciavel || (p?.category(c.key).enabled ?? true),
                    locked: !c.silenciavel,
                    tone: _tone,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kPadH),
            child: Text(
              'Riscado = silenciado. Cadeado = aviso do sistema, sempre ligado.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        _NavigationRow(
          tone: _tone,
          icon: Icons.tune_rounded,
          title: 'Ajustar por assunto',
          subtitle:
              'Liga, silencia e escolhe os canais de cada assunto, inclusive os avisos do Financeiro.',
          trailing: Icon(Icons.chevron_right_rounded, size: 22, color: secondary),
          onTap: _openNotificationPreferences,
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: AGENDA — regra de sobreposição (escolha única)
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildAgendaSection(BuildContext context) {
    final theme = Theme.of(context);
    final allow = _prefs?.calendarAllowOverlappingSlots ?? false;

    Widget option(bool value, String title, String subtitle, IconData icon) {
      final selected = allow == value;
      return InkWell(
        onTap: selected || _prefs == null
            ? null
            : () => _savePatch({
                'generalSettings': {'calendarAllowOverlappingSlots': value},
              }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
          child: Row(
            children: [
              _ToneIconPlate(tone: _tone, icon: icon, active: selected),
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
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? _tone
                    : ThemeHelpers.textSecondaryColor(context),
                size: 22,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Agenda',
          subtitle:
              'Dois compromissos seus no mesmo horário. Vale só para a sua agenda.',
          trailing: allow ? 'Permite' : 'Bloqueia',
          tone: _tone,
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              option(
                false,
                'Bloqueia',
                'Avisa e não deixa marcar por cima de outro compromisso seu.',
                Icons.event_busy_outlined,
              ),
              _rowDivider(context),
              option(
                true,
                'Permite',
                'Deixa marcar dois compromissos no mesmo horário, lado a lado.',
                Icons.event_available_outlined,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPadH, 6, _kPadH, 0),
          child: Text(
            'Vale ao criar agendamento, editar horário e adiar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: APARÊNCIA
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildAppearanceSection(BuildContext context) {
    final themeService = ThemeService.instance;
    final lang = _prefs?.language ?? 'pt-BR';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Aparência',
          subtitle: 'Claro ou escuro também vale no sistema web.',
          trailing: themeService.getThemeName(),
          tone: _tone,
        ),
        const SizedBox(height: 8),
        _NavigationRow(
          tone: _tone,
          icon: themeService.getThemeIcon(),
          title: 'Tema do app',
          subtitle: 'Claro, escuro ou igual ao do celular.',
          trailing: _ValueChip(
            label: themeService.getThemeName(),
            tone: _tone,
          ),
          onTap: () => _showThemeSheet(context),
        ),
        _rowDivider(context),
        // O web também só lê o idioma (themeSettings.language): informação,
        // não ajuste — por isso não tem seta nem toque.
        _InfoRow(
          tone: _tone,
          icon: Icons.translate_rounded,
          title: 'Idioma',
          subtitle: 'Textos, datas e números. Não muda pelo app.',
          value: _languageLabel(lang),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SEÇÃO: SOBRE O APP
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Sobre o app',
          subtitle: 'Políticas do app. A versão instalada fica no rodapé.',
          tone: _tone,
        ),
        const SizedBox(height: 8),
        _NavigationRow(
          tone: _tone,
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
  // RODAPÉ — assinatura da marca + versão instalada
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildFooterSignature(BuildContext context, Color brand) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final year = DateTime.now().year;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 0, _kPadH, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hairline(context),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
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
          const SizedBox(height: 12),
          Text(
            '© $year Intellisys. Todos os direitos reservados.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary.withValues(alpha: 0.8),
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

  /// Filete entre linhas da mesma seção — começa onde começa o texto, como
  /// numa lista de ajustes; a placa de ícone fica sem corte.
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

  /// Quebra entre seções — filete de ponta a ponta com respiro igual dos
  /// dois lados.
  Widget _sectionBreak(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: _hairline(context),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // FOLHA DO TEMA — escolha única; em tela baixa o conteúdo rola por dentro
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _showThemeSheet(BuildContext context) async {
    final themeService = ThemeService.instance;
    final tone = _tone;

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
      onTap: () {
        Navigator.pop(sheetContext);
        _applyTheme(mode);
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

  // ──────────────────────────────────────────────────────────────────────
  // FORMATTERS
  // ──────────────────────────────────────────────────────────────────────

  String _formatRole(String role) {
    final r = role.trim().toLowerCase();
    return switch (r) {
      'master' => 'Master',
      'admin' => 'Administrador',
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

  String _languageLabel(String code) {
    final c = code.trim().toLowerCase().replaceAll('_', '-');
    if (c == 'pt-br' || c == 'pt') return 'Português (BR)';
    if (c == 'pt-pt') return 'Português (PT)';
    if (c.startsWith('en')) return 'English';
    if (c.startsWith('es')) return 'Español';
    return code;
  }
}

// ════════════════════════════════════════════════════════════════════════
// COMPONENTES INTERNOS — linhas flush, sem cards encapsulando seções
// ════════════════════════════════════════════════════════════════════════

/// Margem lateral da tela (gramática flush do app).
const double _kPadH = 16;

/// Onde começa o texto das linhas com placa (16 + placa 40 + 14): alinha
/// filetes e os chips de canal dos avisos de lead.
const double _kRowTextInset = 70;

/// Largura máxima da coluna em tela larga.
const double _kMaxContentWidth = 720;

/// Uma linha do resumo: rótulo, resposta e para onde leva.
class _SummaryItem {
  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.answer,
    required this.color,
    required this.anchor,
  });

  final IconData icon;
  final String label;
  final String answer;
  final Color color;
  final GlobalKey anchor;
}

/// Linha do sumário com resposta — rótulo à esquerda, estado à direita na
/// cor do significado, seta para baixo (leva à seção nesta mesma tela).
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.item,
    required this.tone,
    required this.onTap,
  });

  final _SummaryItem item;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kPadH, 11, 10, 11),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: tone),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 124),
                child: Text(
                  item.answer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: item.color,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado da gravação — "Tudo salvo" (verde, confirmado pela API) ou
/// "Salvando…" enquanto algum interruptor espera resposta. Estático.
class _SaveState extends StatelessWidget {
  const _SaveState({required this.saving, required this.savedColor});

  final bool saving;
  final Color savedColor;

  @override
  Widget build(BuildContext context) {
    final color = saving
        ? ThemeHelpers.textSecondaryColor(context)
        : savedColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          saving ? Icons.sync_rounded : Icons.check_circle_rounded,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 5),
        Text(
          saving ? 'Salvando…' : 'Tudo salvo',
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Cabeçalho de seção — barra tonal, título, explicação curta e a contagem
/// do que está ligado à direita (quebra em duas linhas se faltar espaço).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.tone,
    this.subtitle,
    this.trailing,
    this.trailingColor,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final Color? trailingColor;
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
            width: 3,
            height: 18,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    height: 1.2,
                    fontSize: 18,
                    color: ThemeHelpers.textColor(context),
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
              constraints: const BoxConstraints(maxWidth: 124),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  trailing!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: trailingColor ?? tone,
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

/// Linha de interruptor — flush, placa à esquerda, interruptor alinhado à
/// direita em todas as seções.
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
          padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
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
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
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

/// Linha de navegação — leva para outra tela ou abre a folha. Sem moldura.
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
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

/// Linha só de leitura — mesmo desenho das outras, com o valor à direita e
/// sem seta (não há o que ajustar por aqui).
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
      child: Row(
        children: [
          _ToneIconPlate(tone: tone, icon: icon, active: false),
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
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 124),
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placa de ícone tom-sobre-tom, chapada (sem degradê): acesa quando o
/// ajuste está ligado, apagada quando desligado.
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
        color: tone.withValues(alpha: active ? 0.13 : 0.05),
        border: Border.all(color: tone.withValues(alpha: active ? 0.32 : 0.14)),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: tone.withValues(alpha: active ? 1.0 : 0.5),
        size: 20,
      ),
    );
  }
}

/// Valor à direita de uma linha de navegação (ex.: "Escuro").
class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: tone.withValues(alpha: 0.1),
          border: Border.all(color: tone.withValues(alpha: 0.32)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            color: tone,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Botão pequeno em pílula — ícone no tom, texto neutro. Usado no "Editar"
/// da linha de quem é.
class _SmallActionPill extends StatelessWidget {
  const _SmallActionPill({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tone),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar circular com aro fino na cor da marca e monograma de reserva.
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
                errorBuilder: (_, _, _) =>
                    _Monogram(name: profile.name, accent: accent),
              )
            : _Monogram(name: profile.name, accent: accent),
      ),
    );
  }
}

/// Reserva do avatar — primeira letra na cor da marca sobre o mesmo tom
/// bem claro (chapado, sem degradê inventado).
class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, required this.accent});

  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      color: accent.withValues(alpha: 0.14),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w900,
          fontSize: 18,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

/// Canal de um aviso de lead (Sino / E-mail / WhatsApp) — contorno; acende
/// no tom quando ligado. Desabilitado quando o aviso está desligado.
class _ChannelToggleChip extends StatelessWidget {
  const _ChannelToggleChip({
    required this.label,
    required this.on,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final bool on;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fg = on ? tone : secondary.withValues(alpha: onTap == null ? 0.5 : 1);
    return Material(
      color: on ? tone.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on
                  ? tone.withValues(alpha: 0.5)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.check_rounded : Icons.close_rounded,
                size: 13,
                color: fg,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Assunto no resumo "Assuntos" — marcado quando ligado, riscado quando
/// silenciado, cadeado quando é do sistema (não pode ser desligado).
class _SubjectPill extends StatelessWidget {
  const _SubjectPill({
    required this.label,
    required this.on,
    required this.locked,
    required this.tone,
  });

  final String label;
  final bool on;
  final bool locked;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fg = on ? ThemeHelpers.textColor(context) : secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: on && !locked ? tone.withValues(alpha: 0.1) : Colors.transparent,
        border: Border.all(
          color: on && !locked
              ? tone.withValues(alpha: 0.45)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked
                ? Icons.lock_outline_rounded
                : on
                ? Icons.check_rounded
                : Icons.notifications_off_outlined,
            size: 13,
            color: locked ? secondary : (on ? tone : secondary),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: fg,
                decoration: on ? null : TextDecoration.lineThrough,
                decorationColor: secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
