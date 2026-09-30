import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/settings_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Preferências de notificação por assunto — paridade com
/// `imobx-front/src/pages/NotificationPreferencesPage.tsx` (/settings/notifications).
///
///   - catálogo: `GET /user-preferences/notification-categories` (o back é a
///     fonte; categoria nova aparece sem deploy do app);
///   - escolhas: `notificationSettings.categories` em `PUT /user-preferences`,
///     no formato do web (só `false`; categoria toda ligada vai como `null`);
///   - Financeiro (quando a empresa tem o módulo): catálogo e opt-out do
///     microserviço, um `PUT /notifications/preferences` por evento mudado.
///
/// Como no web, tudo fica pendente até "Salvar" — a chave mestra silencia os
/// dois sistemas num toque sem disparar dezenas de gravações no ato.
class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _Channel {
  const _Channel(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const List<_Channel> _kChannels = [
  _Channel('inApp', 'No sistema', LucideIcons.monitor),
  _Channel('email', 'E-mail', LucideIcons.mail),
  _Channel('push', 'Push', LucideIcons.smartphone),
];

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  static const double _padH = 16;

  /// Em tela larga a coluna para aqui e centraliza.
  static const double _maxContentWidth = 720;

  bool _loading = true;
  String? _error;
  int _errorStatus = 0;

  List<NotificationCategoryMeta> _catalog = const [];
  Map<String, NotificationCategoryChoice> _choices = {};
  Map<String, NotificationCategoryChoice> _saved = {};

  bool _financeAvailable = false;
  List<FinanceNotificationEvent>? _finCatalog;
  bool _finError = false;
  Set<String> _finOff = {};
  Set<String> _finSaved = {};

  bool _saving = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // Tom da tela por token: o mesmo azul de informação das Configurações —
  // esta página é o detalhe da seção de canais e assuntos de lá. Âmbar só
  // para o que ficou silenciado.
  Color get _blue =>
      _isDark ? AppColors.message.infoTextDarkMode : AppColors.message.infoText;

  Color get _amber => _isDark
      ? AppColors.message.warningTextDarkMode
      : AppColors.message.warningText;

  Color get _brand => _isDark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Color get _confirm =>
      _isDark ? AppColors.status.successDarkMode : AppColors.status.success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
    });

    // Mesmo critério do web: o bloco do Financeiro só existe com o módulo.
    final financeAvailable = ModuleAccessService.instance.hasCompanyModule(
      'financial_management',
    );

    // As duas partem juntas; cada uma é esperada no seu tipo.
    final prefsFuture = SettingsService.instance.getPreferences();
    final catFuture = SettingsService.instance.getNotificationCategories();
    final prefsRes = await prefsFuture;
    final catRes = await catFuture;
    if (!mounted) return;

    if (!prefsRes.success || prefsRes.data == null) {
      setState(() {
        _loading = false;
        _error = prefsRes.message ?? 'Não deu para carregar as preferências.';
        _errorStatus = prefsRes.statusCode;
      });
      return;
    }
    if (!catRes.success || catRes.data == null) {
      setState(() {
        _loading = false;
        _error =
            'Não foi possível carregar a lista de assuntos. Tente novamente.';
        _errorStatus = catRes.statusCode;
      });
      return;
    }

    final prefs = prefsRes.data!;
    final catalog = catRes.data!;
    final loaded = <String, NotificationCategoryChoice>{
      for (final c in catalog) c.key: prefs.category(c.key),
    };

    setState(() {
      _catalog = catalog;
      _choices = Map.of(loaded);
      _saved = Map.of(loaded);
      _financeAvailable = financeAvailable;
      _finCatalog = null;
      _finError = false;
      _loading = false;
    });

    if (financeAvailable) _loadFinance();
  }

  Future<void> _loadFinance() async {
    final res = await SettingsService.instance
        .getFinanceNotificationPreferences();
    if (!mounted) return;
    setState(() {
      if (res.success && res.data != null) {
        _finCatalog = res.data!.catalogo;
        _finOff = Set.of(res.data!.desligados);
        _finSaved = Set.of(res.data!.desligados);
        _finError = false;
      } else {
        _finError = true;
      }
    });
  }

  // ── leituras ────────────────────────────────────────────────────────────

  List<NotificationCategoryMeta> get _silenceable =>
      _catalog.where((c) => c.silenciavel).toList();

  NotificationCategoryChoice _choiceOf(String key) =>
      _choices[key] ?? const NotificationCategoryChoice();

  int get _crmOn =>
      _silenceable.where((c) => _choiceOf(c.key).enabled).length;

  int get _finTotal => _finCatalog?.length ?? 0;

  int get _finOn {
    final cat = _finCatalog;
    if (cat == null) return 0;
    return cat.where((e) => !_finOff.contains(e.event)).length;
  }

  bool get _finAllOff => _finTotal > 0 && _finOn == 0;
  bool get _crmAllOff => _silenceable.isNotEmpty && _crmOn == 0;
  bool get _allOff => _crmAllOff && (_finTotal == 0 || _finAllOff);

  Set<String> get _activeChannels {
    final out = <String>{};
    for (final c in _silenceable) {
      final e = _choiceOf(c.key);
      if (!e.enabled) continue;
      for (final ch in _kChannels) {
        if (e.valueOf(ch.key)) out.add(ch.key);
      }
    }
    return out;
  }

  bool get _crmDirty {
    for (final c in _catalog) {
      if (_choiceOf(c.key) != (_saved[c.key] ??
          const NotificationCategoryChoice())) {
        return true;
      }
    }
    return false;
  }

  bool get _finDirty =>
      _finCatalog != null &&
      (_finOff.length != _finSaved.length || !_finOff.containsAll(_finSaved));

  bool get _dirty => _crmDirty || _finDirty;

  /// `contarAlteracoes` do web: campos-folha que mudaram.
  int get _changes {
    var n = 0;
    for (final c in _catalog) {
      final a = _saved[c.key] ?? const NotificationCategoryChoice();
      final b = _choiceOf(c.key);
      if (a.enabled != b.enabled) n++;
      if (a.inApp != b.inApp) n++;
      if (a.email != b.email) n++;
      if (a.push != b.push) n++;
    }
    if (_finCatalog != null) {
      final all = {..._finSaved, ..._finOff};
      for (final ev in all) {
        if (_finSaved.contains(ev) != _finOff.contains(ev)) n++;
      }
    }
    return n;
  }

  // ── mudanças locais ─────────────────────────────────────────────────────

  void _setField(String key, String field, bool value) {
    setState(() {
      _choices = {..._choices, key: _choiceOf(key).withChannel(field, value)};
    });
  }

  void _setAll(bool on) {
    setState(() {
      final next = Map.of(_choices);
      for (final c in _silenceable) {
        next[c.key] = _choiceOf(c.key).copyWith(enabled: on);
      }
      _choices = next;
    });
  }

  void _setFinAll(bool on) {
    setState(() {
      _finOff = on
          ? <String>{}
          : (_finCatalog ?? const []).map((e) => e.event).toSet();
    });
  }

  void _setFinEvent(String event, bool on) {
    setState(() {
      final next = Set.of(_finOff);
      if (on) {
        next.remove(event);
      } else {
        next.add(event);
      }
      _finOff = next;
    });
  }

  /// A chave mestra fala pelos dois sistemas.
  void _setEverything(bool on) {
    _setAll(on);
    if ((_finCatalog ?? const []).isNotEmpty) _setFinAll(on);
  }

  void _setChannelEverywhere(String channel, bool on) {
    setState(() {
      final next = Map.of(_choices);
      for (final c in _silenceable) {
        next[c.key] = _choiceOf(c.key).withChannel(channel, on);
      }
      _choices = next;
    });
  }

  void _discard() {
    setState(() {
      _choices = Map.of(_saved);
      _finOff = Set.of(_finSaved);
    });
  }

  // ── gravação ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    var failed = false;
    String? firstError;

    if (_crmDirty) {
      final res = await SettingsService.instance.updateCategoryChoices(
        _choices,
      );
      if (res.success && res.data != null) {
        final prefs = res.data!;
        final fresh = <String, NotificationCategoryChoice>{
          for (final c in _catalog) c.key: prefs.category(c.key),
        };
        _saved = Map.of(fresh);
        _choices = Map.of(fresh);
      } else {
        failed = true;
        firstError = res.message;
      }
    }

    if (_finDirty) {
      // Só o que mudou vira PUT — um por evento, contrato do microserviço.
      final changed = (_finCatalog ?? const [])
          .map((e) => e.event)
          .where((ev) => _finSaved.contains(ev) != _finOff.contains(ev))
          .toList();
      final results = await Future.wait(
        changed.map(
          (ev) => SettingsService.instance.setFinanceNotificationPreference(
            ev,
            !_finOff.contains(ev),
          ),
        ),
      );
      // O salvo avança só pelo que realmente gravou.
      final nextSaved = Set.of(_finSaved);
      for (var i = 0; i < changed.length; i++) {
        final ev = changed[i];
        if (results[i].success) {
          if (_finOff.contains(ev)) {
            nextSaved.add(ev);
          } else {
            nextSaved.remove(ev);
          }
        } else {
          failed = true;
          firstError ??= results[i].message;
        }
      }
      _finSaved = nextSaved;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    _snack(
      failed
          ? 'Parte das preferências não foi salva. Tente novamente.'
                '${firstError != null && firstError.trim().isNotEmpty ? '\n$firstError' : ''}'
          : 'Preferências de notificação salvas.',
      error: failed,
    );
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        backgroundColor: error ? AppColors.status.error : _confirm,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger = _isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Descartar alterações?',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        content: Text(
          'Você mexeu nas notificações e ainda não salvou. Ao sair, as alterações serão perdidas.',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: secondary),
        ),
        actions: [
          // Seguir editando é neutro (o tema pinta TextButton de vermelho);
          // descartar desfaz trabalho: chapa vermelha com texto branco.
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: secondary),
            child: const Text(
              'Continuar editando',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              'Descartar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop(true);
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmLeave();
      },
      child: AppScaffold(
        title: 'Notificações',
        showBottomNavigation: false,
        body: _loading
            ? _buildSkeleton()
            : _error != null
            ? AppErrorState.fromApi(
                message: _error,
                statusCode: _errorStatus,
                onRetry: _load,
              )
            : Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      color: _brand,
                      onRefresh: () async {
                        if (_dirty) return;
                        await _load();
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: _pagePadding(top: 14, bottom: 24),
                        children: [
                          _buildMasthead(),
                          const SizedBox(height: 20),
                          _buildMasterSwitch(),
                          const SizedBox(height: 22),
                          _separator(),
                          const SizedBox(height: 20),
                          _buildCategoriesSection(),
                          if (_financeAvailable) ...[
                            const SizedBox(height: 24),
                            _separator(),
                            const SizedBox(height: 20),
                            _buildFinanceSection(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _buildSaveBar(),
                ],
              ),
      ),
    );
  }

  /// Tablet/landscape largo: a coluna para em [_maxContentWidth] e
  /// centraliza (o ListView segue filho direto do RefreshIndicator).
  EdgeInsets _pagePadding({double top = 0, double bottom = 0}) {
    final w = MediaQuery.sizeOf(context).width;
    final side = w > _maxContentWidth ? (w - _maxContentWidth) / 2 : 0.0;
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  Widget _separator() => Container(
    height: 1,
    color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
  );

  Widget _rowDivider() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _padH),
    child: Divider(
      height: 1,
      thickness: 0.5,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
    ),
  );

  Widget _buildSkeleton() {
    // Mesmo desenho do topo real: título, frase de estado e um medidor por
    // canal (rótulo + contagem + barra), depois a chave mestra e as linhas.
    Widget meter() => const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SkeletonBox(width: 16, height: 16, borderRadius: 4),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SkeletonText(width: 90, height: 11),
                    Spacer(),
                    SkeletonText(width: 50, height: 11),
                  ],
                ),
                SizedBox(height: 6),
                SkeletonBox(height: 5, borderRadius: 99),
              ],
            ),
          ),
        ],
      ),
    );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: _pagePadding(top: 18, bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonText(width: 220, height: 24),
              const SizedBox(height: 10),
              const SkeletonText(width: 240, height: 12),
              const SizedBox(height: 18),
              meter(),
              meter(),
              meter(),
              const SizedBox(height: 14),
              const SkeletonBox(height: 44, borderRadius: 12),
              const SizedBox(height: 28),
              const SkeletonText(width: 110, height: 20),
              const SizedBox(height: 14),
            ],
          ),
        ),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: 10),
            child: Row(
              children: const [
                SkeletonBox(width: 22, height: 22, borderRadius: 6),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 140, height: 13),
                      SizedBox(height: 6),
                      SkeletonText(height: 10),
                      SizedBox(height: 10),
                      SkeletonText(width: 200, height: 26),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── topo: medidor por canal ─────────────────────────────────────────────
  // Quem abre quer saber "o que chega e por onde". Em vez de manchete com
  // números soltos, um medidor: quantos assuntos chegam por cada canal, com
  // a barra enchendo — e uma frase de estado logo abaixo do título.

  Widget _buildMasthead() {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final total = _silenceable.length;
    final crmOff = total - _crmOn;

    int litBy(String channel) => _silenceable.where((c) {
      final e = _choiceOf(c.key);
      return e.enabled && e.valueOf(channel);
    }).length;

    final String status;
    if (total == 0) {
      status = 'Nenhum assunto pode ser silenciado.';
    } else if (crmOff == 0) {
      status = 'Todos os $total assuntos estão ligados.';
    } else if (_crmOn == 0) {
      status = 'Todos os $total assuntos estão silenciados.';
    } else {
      status =
          '$_crmOn de $total assuntos ligados · $crmOff silenciado${crmOff == 1 ? '' : 's'}.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'O que chega '),
                TextSpan(
                  text: 'e por onde',
                  style: TextStyle(color: _blue),
                ),
              ],
            ),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: ThemeHelpers.textColor(context),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: theme.textTheme.bodyMedium?.copyWith(
              // Tudo ligado no tom da tela; algo silenciado em âmbar.
              color: total == 0
                  ? secondary
                  : crmOff > 0
                  ? _amber
                  : _blue,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          for (final ch in _kChannels) ...[
            _ChannelMeter(
              icon: ch.icon,
              label: ch.label,
              count: litBy(ch.key),
              total: total,
              tone: _blue,
            ),
            const SizedBox(height: 12),
          ],
          if (_financeAvailable && _finCatalog != null) ...[
            _ChannelMeter(
              icon: LucideIcons.wallet,
              label: 'Financeiro (no sino)',
              count: _finOn,
              total: _finTotal,
              tone: _blue,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Escolha por assunto o que chega para você e por onde. ',
                ),
                TextSpan(
                  text: 'Vale só para você',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const TextSpan(
                  text:
                      ' — quem mais recebe o aviso continua recebendo. Avisos do sistema e da assinatura não se desligam.',
                ),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── chave mestra ────────────────────────────────────────────────────────

  Widget _buildMasterSwitch() {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final disabled = _silenceable.isEmpty;
    final allOff = _allOff;

    Widget option(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: Material(
          color: selected
              ? _blue.withValues(alpha: _isDark ? 0.22 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: disabled ? null : onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? _blue.withValues(alpha: 0.55)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: selected ? _blue : secondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final String sentence;
    if (allOff) {
      sentence =
          'Só sistema e assinatura chegam. Ligue aqui para voltar a receber tudo, ou acenda assunto por assunto abaixo.';
    } else if (_finTotal > 0) {
      sentence =
          'Silenciar cala os assuntos do CRM e os avisos do Financeiro de uma vez; sistema e assinatura não são afetados.';
    } else {
      sentence =
          'Silenciar cala todos os assuntos de uma vez; sistema e assinatura não são afetados.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TUDO',
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                option('Ligadas', !allOff, () => _setEverything(true)),
                const SizedBox(width: 4),
                option('Silenciadas', allOff, () => _setEverything(false)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sentence,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── cabeçalho de seção ──────────────────────────────────────────────────

  Widget _sectionHeader(
    String title,
    String subtitle, {
    String? hint,
    Color? hintColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: ThemeHelpers.textColor(context),
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 10),
            // Contagem com teto de largura: em 320dp/fonte grande ela quebra
            // em duas linhas em vez de espremer o título.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: hintColor ?? _blue,
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

  Widget _actionChip({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final fg = enabled
        ? ThemeHelpers.textColor(context)
        : ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.55);
    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: ThemeHelpers.borderColor(
                context,
              ).withValues(alpha: enabled ? 0.8 : 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
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

  // ── por assunto ─────────────────────────────────────────────────────────

  Widget _buildCategoriesSection() {
    final active = _activeChannels;
    final silenceable = _silenceable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'Por assunto',
          'Toque no assunto para ligar ou silenciar; nos canais, por onde ele chega.',
          hint: '$_crmOn de ${silenceable.length} ligados',
          hintColor: _crmAllOff ? _amber : null,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padH),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionChip(
                label: 'Ligar todos',
                icon: LucideIcons.checkCheck,
                onTap: _crmOn == silenceable.length
                    ? null
                    : () => _setAll(true),
              ),
              _actionChip(
                label: 'Silenciar todos',
                icon: LucideIcons.bellOff,
                onTap: _crmAllOff ? null : () => _setAll(false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Canal em todos os assuntos de uma vez: aceso = em uso em algum
        // assunto (toque tira de todos); apagado = em nenhum (toque põe em
        // todos). Mesmo desenho dos canais de cada assunto, logo abaixo.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padH),
          child: Text(
            'Canal em todos os assuntos',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padH),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _kChannels)
                _ChannelChip(
                  label: c.label,
                  icon: c.icon,
                  lit: active.contains(c.key),
                  tone: _blue,
                  onTap: _crmAllOff
                      ? null
                      : () => _setChannelEverywhere(
                          c.key,
                          !active.contains(c.key),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_catalog.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(_padH, 8, _padH, 0),
            child: Text(
              'Não foi possível carregar a lista de assuntos. Puxe para recarregar.',
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontSize: 13,
              ),
            ),
          )
        else
          for (var i = 0; i < _catalog.length; i++) ...[
            if (i > 0) _rowDivider(),
            _categoryRow(_catalog[i]),
          ],
      ],
    );
  }

  Widget _categoryRow(NotificationCategoryMeta cat) {
    final theme = Theme.of(context);
    final e = _choiceOf(cat.key);
    final locked = !cat.silenciavel;
    final on = locked || e.enabled;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: locked ? null : () => _setField(cat.key, 'enabled', !e.enabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: _CheckBoxMark(
                  on: on,
                  locked: locked,
                  tone: _blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: ThemeHelpers.textColor(
                          context,
                        ).withValues(alpha: on ? 1 : 0.6),
                      ),
                    ),
                    if (cat.descricao.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        locked
                            ? '${cat.descricao} Sempre ligado, em todos os canais.'
                            : cat.descricao,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final ch in _kChannels)
                          _ChannelChip(
                            label: ch.label,
                            icon: ch.icon,
                            lit: locked || (e.enabled && e.valueOf(ch.key)),
                            tone: _blue,
                            onTap: locked || !e.enabled
                                ? null
                                : () => _setField(
                                    cat.key,
                                    ch.key,
                                    !e.valueOf(ch.key),
                                  ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── financeiro ──────────────────────────────────────────────────────────

  Widget _buildFinanceSection() {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cat = _finCatalog;

    Widget body;
    if (_finError) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: _padH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não foi possível carregar os avisos do Financeiro.',
              style: TextStyle(color: secondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _actionChip(
              label: 'Tentar de novo',
              icon: LucideIcons.refreshCw,
              onTap: () {
                setState(() => _finError = false);
                _loadFinance();
              },
            ),
          ],
        ),
      );
    } else if (cat == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: _padH),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++) ...[
              const SkeletonBox(height: 48, borderRadius: 8),
              if (i < 3) const SizedBox(height: 8),
            ],
          ],
        ),
      );
    } else if (cat.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: _padH),
        child: Text(
          'O Financeiro ainda não tem avisos configuráveis.',
          style: TextStyle(color: secondary, fontSize: 13),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cat.length; i++) ...[
            if (i > 0) _rowDivider(),
            _financeRow(cat[i]),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'Avisos do Financeiro',
          'Por evento; desligar aqui só afeta o seu sino — quem mais recebe continua recebendo.',
          hint: cat != null ? '$_finOn de $_finTotal ligados' : null,
          hintColor: _finAllOff ? _amber : null,
        ),
        const SizedBox(height: 12),
        if (cat != null && cat.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padH),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionChip(
                  label: 'Ligar todos',
                  icon: LucideIcons.checkCheck,
                  onTap: _finOn == _finTotal ? null : () => _setFinAll(true),
                ),
                _actionChip(
                  label: 'Silenciar todos',
                  icon: LucideIcons.bellOff,
                  onTap: _finAllOff ? null : () => _setFinAll(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        body,
        if (cat != null && cat.isNotEmpty && _finAllOff)
          Padding(
            padding: const EdgeInsets.fromLTRB(_padH, 10, _padH, 0),
            child: Text(
              'Todos os avisos do Financeiro estão silenciados.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _amber,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _financeRow(FinanceNotificationEvent ev) {
    final theme = Theme.of(context);
    final on = !_finOff.contains(ev.event);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _setFinEvent(ev.event, !on),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: _CheckBoxMark(on: on, locked: false, tone: _blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: ThemeHelpers.textColor(
                          context,
                        ).withValues(alpha: on ? 1 : 0.6),
                      ),
                    ),
                    if (ev.quando.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        ev.quando,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                on ? 'recebe' : 'silenciado',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: on ? _blue : secondary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── barra de salvar ─────────────────────────────────────────────────────

  Widget _buildSaveBar() {
    // Texto sobre o verde de confirmação: branco no claro, grafite no escuro
    // (o verde do tema escuro é claro demais para letra branca).
    final onConfirm = ThemeHelpers.onPrimaryColor(context);
    final dirty = _dirty;
    final n = _changes;
    final label = _saving
        ? 'Salvando…'
        : n == 0
        ? 'Sem alterações'
        : 'Salvar · $n ${n == 1 ? 'alteração' : 'alterações'}';

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : dirty
                    ? _discard
                    : () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  side: BorderSide(
                    color: ThemeHelpers.borderColor(
                      context,
                    ).withValues(alpha: 0.9),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  dirty ? 'Descartar' : 'Voltar',
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: dirty && !_saving ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _confirm,
                    foregroundColor: onConfirm,
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.check, size: 17),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
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

/// Caixa de marcação do assunto/evento — acesa em azul, cadeado quando
/// o assunto não pode ser desligado (Sistema e assinatura).
class _CheckBoxMark extends StatelessWidget {
  const _CheckBoxMark({
    required this.on,
    required this.locked,
    required this.tone,
  });

  final bool on;
  final bool locked;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: locked
            ? secondary.withValues(alpha: 0.12)
            : on
            ? tone
            : Colors.transparent,
        border: Border.all(
          color: locked
              ? secondary.withValues(alpha: 0.4)
              : on
              ? tone
              : ThemeHelpers.borderColor(context),
          width: 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: locked
          ? Icon(LucideIcons.lock, size: 12, color: secondary)
          : on
          ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// Canal dentro do assunto: contorno; acende no tom quando ativo.
class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.label,
    required this.icon,
    required this.lit,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool lit;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fg = lit ? tone : secondary.withValues(alpha: onTap == null ? 0.5 : 1);
    return Material(
      color: lit ? tone.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: lit
                  ? tone.withValues(alpha: 0.5)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fg),
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

/// Medidor de um canal no topo: rótulo, "N de M" e a barra enchendo na
/// proporção dos assuntos que chegam por ele. Só leitura — o ajuste fica
/// nas linhas de cada assunto.
class _ChannelMeter extends StatelessWidget {
  const _ChannelMeter({
    required this.icon,
    required this.label,
    required this.count,
    required this.total,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final int count;
  final int total;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final frac = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    final lit = count > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: lit ? tone : secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count de $total',
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: lit ? tone : secondary,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: ThemeHelpers.borderColor(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: frac,
                        heightFactor: 1,
                        child: ColoredBox(color: tone),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
