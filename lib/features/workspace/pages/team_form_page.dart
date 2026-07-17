import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../services/company_team_service.dart';
import '../widgets/team_member_picker_sheet.dart';

/// Paleta de cores da equipe (mesma régua do web/TeamsPage).
const _teamColors = [
  '#EF4444',
  '#F97316',
  '#F59E0B',
  '#84CC16',
  '#10B981',
  '#06B6D4',
  '#3B82F6',
  '#6366F1',
  '#8B5CF6',
  '#EC4899',
];

Color _parseHex(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF3B82F6);
}

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Iniciais da EQUIPE pro monograma — paridade com o card da lista
/// (uma palavra → 2 primeiras letras; várias → primeira + última).
String _teamInitialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final w = parts.first;
    return w.substring(0, w.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Membro em edição local (antes de salvar).
class _DraftMember {
  final String userId;
  final String name;
  final String email;
  final String? avatar;
  String role; // 'member' | 'leader'

  _DraftMember({
    required this.userId,
    required this.name,
    this.email = '',
    this.avatar,
    this.role = 'member',
  });

  bool get isLeader => role == 'leader';
}

/// Criar/editar equipe — identidade viva flush no topo (monograma + nome
/// digitado + meta), banda contínua de cor, membros como protagonistas
/// (pilha sobreposta, líderes primeiro) e configurações em linhas tonais.
class TeamFormPage extends StatefulWidget {
  const TeamFormPage({super.key, this.teamId});

  /// `null` = criação; senão edição.
  final String? teamId;

  @override
  State<TeamFormPage> createState() => _TeamFormPageState();
}

class _TeamFormPageState extends State<TeamFormPage> {
  static const double _padH = 20;

  final _name = TextEditingController();
  final _description = TextEditingController();
  String _color = _teamColors.first;
  bool _isActive = true;
  bool _useInSaleForms = false;
  final List<_DraftMember> _members = [];

  bool _loading = false;
  bool _saving = false;
  bool _nameError = false;
  String? _error;

  /// Snapshot para detectar alterações não salvas.
  String _savedFingerprint = '';

  bool get _isEditing => widget.teamId != null;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  /// Cor CRUA da equipe — pinta swatches, monograma e avatares.
  Color get _teamColor => _parseHex(_color);

  /// Cor da equipe ajustada pra legibilidade de texto/ícone pequeno no dark.
  Color get _accent => _isDark
      ? Color.lerp(_teamColor, Colors.white, 0.22)!
      : _teamColor;

  /// Tom profundo do gradiente do monograma — mesma mistura com índigo
  /// profundo dos cards da lista de equipes.
  Color get _deep =>
      Color.lerp(_teamColor, const Color(0xFF312E81), _isDark ? 0.38 : 0.45)!;

  /// Verde de confirmação do sistema (Salvar/Criar).
  Color get _confirm =>
      _isDark ? AppColors.status.successDarkMode : AppColors.status.success;

  Color get _violet =>
      _isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

  Color get _sky =>
      _isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

  Color get _amber => _isDark
      ? AppColors.message.warningTextDarkMode
      : AppColors.message.warningText;

  /// Líderes primeiro — são o rosto da equipe (mesma ordem da lista).
  List<_DraftMember> get _ordered => [
        ..._members.where((m) => m.isLeader),
        ..._members.where((m) => !m.isLeader),
      ];

  int get _leadersCount => _members.where((m) => m.isLeader).length;

  @override
  void initState() {
    super.initState();
    _savedFingerprint = _fingerprint();
    _name.addListener(_onNameChanged);
    _description.addListener(_rebuild);
    if (_isEditing) _load();
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _description.removeListener(_rebuild);
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _onNameChanged() {
    setState(() {
      if (_nameError && _name.text.trim().isNotEmpty) _nameError = false;
    });
  }

  String _fingerprint() => [
        _name.text.trim(),
        _description.text.trim(),
        _color,
        _isActive,
        _useInSaleForms,
        _members.map((m) => '${m.userId}:${m.role}').join(','),
      ].join('|');

  bool get _isDirty => !_saving && _fingerprint() != _savedFingerprint;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CompanyTeamService.instance.getTeam(widget.teamId!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        final t = res.data!;
        _name.text = t.name;
        _description.text = t.description ?? '';
        if ((t.color ?? '').isNotEmpty) _color = t.color!;
        _isActive = t.isActive;
        _useInSaleForms = t.useInSaleForms;
        _members
          ..clear()
          ..addAll(t.members.map(
            (m) => _DraftMember(
              userId: m.userId,
              name: m.name,
              email: m.email,
              avatar: m.avatar,
              role: m.role,
            ),
          ));
        _savedFingerprint = _fingerprint();
      } else {
        _error = res.message ?? 'Erro ao carregar equipe';
      }
    });
  }

  Future<void> _addMember() async {
    final picked = await showTeamMemberPickerSheet(
      context,
      accent: _teamColor,
      excludeIds: _members.map((m) => m.userId).toSet(),
    );
    if (picked == null || picked.id.isEmpty || !mounted) return;
    if (_members.any((m) => m.userId == picked.id)) return;
    setState(() {
      _members.add(_DraftMember(
        userId: picked.id,
        name: picked.name,
        email: picked.email,
      ));
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      HapticFeedback.mediumImpact();
      setState(() => _nameError = true);
      return;
    }
    setState(() => _saving = true);
    final members = _members
        .map((m) => {'userId': m.userId, 'role': m.role})
        .toList(growable: false);
    final res = _isEditing
        ? await CompanyTeamService.instance.updateTeam(
            teamId: widget.teamId!,
            name: name,
            description: _description.text.trim(),
            color: _color,
            isActive: _isActive,
            useInSaleForms: _useInSaleForms,
            members: members,
          )
        : await CompanyTeamService.instance.createTeam(
            name: name,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            color: _color,
            members: members,
          );
    if (!mounted) return;
    if (res.success) {
      _savedFingerprint = _fingerprint();
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.message ??
                (_isEditing
                    ? 'Não foi possível salvar a equipe.'
                    : 'Não foi possível criar a equipe.'),
          ),
        ),
      );
    }
  }

  /// Guarda de saída: com alterações não salvas, confirma o descarte.
  Future<void> _confirmDiscard() async {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger =
        _isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Descartar alterações?',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        content: Text(
          'Você mexeu na equipe e ainda não salvou. Ao sair, as alterações serão perdidas.',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: secondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Continuar editando',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: danger),
            child: const Text(
              'Descartar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmDiscard();
      },
      child: AppScaffold(
        title: _isEditing ? 'Editar equipe' : 'Nova equipe',
        showBottomNavigation: false,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _loading
              ? KeyedSubtree(
                  key: const ValueKey('loading'),
                  child: _buildSkeleton(),
                )
              : _error != null
                  ? KeyedSubtree(
                      key: const ValueKey('error'),
                      child: _buildError(),
                    )
                  : Column(
                      key: const ValueKey('form'),
                      children: [
                        Expanded(child: _buildForm()),
                        _buildSaveBar(),
                      ],
                    ),
        ),
      ),
    );
  }

  // ─── Skeleton fiel ao layout novo (masthead flush + banda + membros) ──────

  Widget _buildSkeleton() => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 18, bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonText(width: 120, height: 10),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const SkeletonBox(width: 56, height: 56, borderRadius: 16),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SkeletonText(width: 190, height: 24),
                          SizedBox(height: 8),
                          SkeletonText(width: 150, height: 11),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const SkeletonText(width: 90, height: 10),
                const SizedBox(height: 8),
                const SkeletonText(width: 140, height: 20),
                const SizedBox(height: 16),
                const SkeletonBox(height: 56, borderRadius: 14),
                const SizedBox(height: 12),
                const SkeletonBox(height: 88, borderRadius: 14),
                const SizedBox(height: 22),
                const SkeletonText(width: 110, height: 10),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Banda de cor — círculos grandes correndo pra fora da margem.
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: _padH),
              itemCount: 7,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) =>
                  const SkeletonBox(width: 48, height: 48, borderRadius: 24),
            ),
          ),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SkeletonText(width: 70, height: 10),
                          SizedBox(height: 8),
                          SkeletonText(width: 120, height: 20),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++)
                          const Padding(
                            padding: EdgeInsets.only(left: 2),
                            child: SkeletonBox(
                              width: 28,
                              height: 28,
                              borderRadius: 999,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < 3; i++) ...[
                  Row(
                    children: [
                      const SkeletonBox(
                          width: 40, height: 40, borderRadius: 999),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonText(width: 140, height: 13),
                            SizedBox(height: 6),
                            SkeletonText(width: 180, height: 10),
                          ],
                        ),
                      ),
                      const SkeletonBox(
                          width: 64, height: 26, borderRadius: 999),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                const SkeletonBox(height: 48, borderRadius: 14),
              ],
            ),
          ),
        ],
      );

  Widget _buildError() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: secondary.withValues(alpha: 0.1),
              ),
              child: Icon(LucideIcons.cloudOff, size: 28, color: secondary),
            ),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(LucideIcons.rotateCcw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Formulário ────────────────────────────────────────────────────────────

  InputDecoration _dec(String label, {String? hint, String? errorText}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
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
          borderSide: BorderSide(color: _teamColor, width: 1.6),
        ),
        // Label flutuante na cor da equipe só quando focado e sem erro —
        // erro continua vermelho, repouso continua neutro.
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          if (states.contains(WidgetState.error)) {
            return TextStyle(
              color: _isDark
                  ? AppColors.status.errorDarkMode
                  : AppColors.status.error,
              fontWeight: FontWeight.w700,
            );
          }
          if (states.contains(WidgetState.focused)) {
            return TextStyle(color: _accent, fontWeight: FontWeight.w700);
          }
          return TextStyle(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w600,
          );
        }),
      );

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        _Entrance(index: 0, child: _buildMasthead()),
        const SizedBox(height: 26),
        // ── Identidade ──────────────────────────────────────────────────────
        _Entrance(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  eyebrow: 'COMO SE APRESENTA',
                  title: 'Identidade',
                  subtitle:
                      'Nome e descrição — a manchete lá em cima acompanha.',
                  tone: _accent,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec(
                    'Nome da equipe *',
                    hint: 'Ex.: Equipe Centro',
                    errorText:
                        _nameError ? 'Informe o nome da equipe.' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _dec(
                    'Descrição',
                    hint: 'Opcional — foco, região, especialidade…',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        // ── Banda de cor — full-bleed, correndo além da margem ──────────────
        _Entrance(index: 2, child: _buildColorBand()),
        // ── Configurações (só edição) ───────────────────────────────────────
        if (_isEditing) ...[
          _sectionSeparator(),
          _Entrance(
            index: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _padH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    eyebrow: 'COMPORTAMENTO',
                    title: 'Configurações',
                    subtitle: 'Como a equipe aparece e é usada no dia a dia.',
                    tone: _violet,
                  ),
                  const SizedBox(height: 10),
                  _SettingRow(
                    icon: LucideIcons.circleCheck,
                    tone: _confirm,
                    title: 'Equipe ativa',
                    description: _isActive
                        ? 'Visível nas listagens e nos relatórios.'
                        : 'Oculta das listagens até ser reativada.',
                    value: _isActive,
                    enabled: !_saving,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _isActive = v);
                    },
                  ),
                  _rowDivider(indent: 48),
                  _SettingRow(
                    icon: LucideIcons.fileText,
                    tone: _sky,
                    title: 'Usar nas fichas de venda',
                    description: 'Equipe selecionável ao criar novas fichas.',
                    value: _useInSaleForms,
                    enabled: !_saving,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _useInSaleForms = v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        _sectionSeparator(),
        // ── Membros ─────────────────────────────────────────────────────────
        _Entrance(
          index: _isEditing ? 4 : 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  eyebrow: 'PESSOAS',
                  title: 'Membros',
                  subtitle: _members.isEmpty
                      ? 'Monte o time e defina quem lidera.'
                      : _membersSubtitle(),
                  tone: _accent,
                  trailing:
                      _members.isEmpty ? null : _buildHeaderAvatarStack(),
                ),
                const SizedBox(height: 14),
                if (_members.isEmpty)
                  _buildMembersEmpty()
                else
                  ..._buildMemberRows(),
                const SizedBox(height: 14),
                _buildAddMemberButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _membersSubtitle() {
    final total = _members.length;
    final leaders = _leadersCount;
    final t = total == 1 ? '1 pessoa' : '$total pessoas';
    final l = leaders == 0
        ? 'sem liderança definida'
        : leaders == 1
            ? '1 líder'
            : '$leaders líderes';
    return '$t · $l — toque no papel para alternar.';
  }

  // ─── Masthead flush — a identidade viva da equipe ─────────────────────────

  Widget _buildMasthead() {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final name = _name.text.trim();
    final hasName = name.isNotEmpty;
    // Inativa "apaga" a identidade — a cor volta quando reativar.
    final dimmed = _isEditing && !_isActive;
    final tone = dimmed ? secondary.withValues(alpha: 0.85) : _teamColor;
    final toneDeep = dimmed
        ? secondary.withValues(alpha: 0.6)
        : _deep;
    final eyebrowTone = dimmed ? secondary : _accent;
    final statusTone = _isActive ? _confirm : secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow com dot vivo — mesma gramática do hero da lista.
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: eyebrowTone,
                  boxShadow: [
                    BoxShadow(
                      color: eyebrowTone.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  _isEditing ? 'ORGANIZAÇÃO · EDITANDO EQUIPE'
                      : 'ORGANIZAÇÃO · NOVA EQUIPE',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: eyebrowTone,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Monograma na cor viva — flush na margem, sem moldura em volta.
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tone, toneDeep],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tone.withValues(alpha: _isDark ? 0.4 : 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                      spreadRadius: -3,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: hasName
                    ? Text(
                        _teamInitialsOf(name),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.3,
                          height: 1.0,
                        ),
                      )
                    : const Icon(
                        LucideIcons.users,
                        size: 24,
                        color: Colors.white,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Manchete que digita junto — nunca trunca com ellipsis.
                    Text(
                      hasName ? name : 'Nova equipe',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        height: 1.05,
                        fontSize: 26,
                        color: hasName
                            ? ThemeHelpers.textColor(context)
                            : secondary.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 7),
                    // Meta discreta: pessoas · cor · status.
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MetaBit(
                          icon: LucideIcons.users,
                          iconColor: secondary,
                          text: _members.isEmpty
                              ? 'sem membros'
                              : _members.length == 1
                                  ? '1 membro'
                                  : '${_members.length} membros',
                        ),
                        _metaDot(secondary),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _teamColor,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _color.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: secondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        _metaDot(secondary),
                        Text(
                          _isActive ? 'Ativa' : 'Inativa',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: statusTone,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaDot(Color secondary) => Container(
        width: 3.5,
        height: 3.5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: secondary.withValues(alpha: 0.45),
        ),
      );

  // ─── Banda de cor — swatches grandes, contínua, full-bleed ────────────────

  Widget _buildColorBand() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padH),
          child: Row(
            children: [
              Icon(LucideIcons.palette, size: 14, color: _accent),
              const SizedBox(width: 7),
              Text(
                'COR DA EQUIPE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'Assina monograma, foco e avatares',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: secondary.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // A banda corre além das margens — convite natural pro scroll.
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _padH),
            physics: const BouncingScrollPhysics(),
            itemCount: _teamColors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _buildSwatch(_teamColors[i]),
          ),
        ),
      ],
    );
  }

  /// Swatch grande com anel de seleção afastado na própria cor.
  Widget _buildSwatch(String hex) {
    final c = _parseHex(hex);
    final selected = _color == hex;
    return GestureDetector(
      onTap: _saving
          ? null
          : () {
              HapticFeedback.selectionClick();
              setState(() => _color = hex);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 52,
        height: 52,
        padding: EdgeInsets.all(selected ? 4 : 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            width: 2,
            color: selected ? c : Colors.transparent,
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                      spreadRadius: -1,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(LucideIcons.check, size: 17, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  // ─── Membros — protagonistas ──────────────────────────────────────────────

  /// Pilha de avatares sobrepostos no cabeçalho da seção (líderes primeiro,
  /// mesma gramática dos cards da lista) + bolha de excedente.
  Widget _buildHeaderAvatarStack() {
    const maxShown = 4;
    final ordered = _ordered;
    final shown = ordered.take(maxShown).toList();
    final extra = ordered.length - shown.length;
    final bg = ThemeHelpers.backgroundColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          Align(
            widthFactor: i == 0 ? 1 : 0.62,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: bg, width: 2),
              ),
              child: _memberAvatar(shown[i], size: 28, fontSize: 11),
            ),
          ),
        if (extra > 0)
          Align(
            widthFactor: 0.62,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _teamColor.withValues(alpha: 0.12),
                border: Border.all(color: bg, width: 2),
              ),
              child: Text(
                '+$extra',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: _isDark ? _accent : _teamColor,
                  height: 1.0,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        if (extra <= 0 && shown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '${_members.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: secondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }

  /// Estado vazio ilustrado — trio de "assentos" tonais esperando gente.
  Widget _buildMembersEmpty() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Align(
                    widthFactor: i == 0 ? 1 : 0.72,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _teamColor.withValues(
                          alpha: i == 1 ? 0.14 : 0.07,
                        ),
                        border: Border.all(
                          color: _teamColor.withValues(
                            alpha: i == 1 ? 0.4 : 0.2,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        i == 1 ? LucideIcons.userPlus : LucideIcons.users,
                        size: i == 1 ? 20 : 16,
                        color: _accent.withValues(alpha: i == 1 ? 1.0 : 0.45),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'A equipe ainda está vazia',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Adicione corretores e toque na coroa para\ndefinir quem lidera.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Linhas de membro — líderes agrupados primeiro com eyebrow próprio.
  List<Widget> _buildMemberRows() {
    final leaders = _members.where((m) => m.isLeader).toList();
    final others = _members.where((m) => !m.isLeader).toList();
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final showGroups = leaders.isNotEmpty && others.isNotEmpty;

    final rows = <Widget>[];

    void addGroup(List<_DraftMember> group) {
      for (var i = 0; i < group.length; i++) {
        // 44 do avatar + 12 de respiro = divisor alinhado ao texto.
        if (i > 0) rows.add(_rowDivider(indent: 56));
        rows.add(_buildMemberRow(group[i]));
      }
    }

    if (showGroups) {
      rows.add(_GroupEyebrow(
        icon: LucideIcons.crown,
        label: leaders.length == 1 ? 'LIDERANÇA' : 'LIDERANÇAS',
        tone: _amber,
      ));
      addGroup(leaders);
      rows.add(const SizedBox(height: 10));
      rows.add(_GroupEyebrow(
        icon: LucideIcons.users,
        label: 'TIME',
        tone: secondary,
      ));
      addGroup(others);
    } else {
      addGroup(leaders.isNotEmpty ? leaders : others);
    }
    return rows;
  }

  /// Avatar do membro — foto real quando existe, senão monograma na cor viva.
  /// Líder ganha anel âmbar + mini coroa (mesma gramática da lista).
  Widget _memberAvatar(
    _DraftMember m, {
    double size = 40,
    double fontSize = 14,
    bool leaderBadge = false,
  }) {
    Widget monogram() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_teamColor, _deep],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            _initialsOf(m.name),
            style: TextStyle(
              fontSize: fontSize * 0.78,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: Colors.white,
              height: 1.0,
            ),
          ),
        );

    final hasPhoto = m.avatar != null && m.avatar!.trim().isNotEmpty;
    final inner = hasPhoto
        ? ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: Image.network(
                m.avatar!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => monogram(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : monogram(),
              ),
            ),
          )
        : monogram();

    if (!leaderBadge || !m.isLeader) return inner;

    final bg = ThemeHelpers.backgroundColor(context);
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size + 4,
            height: size + 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _amber, width: 1.8),
            ),
            alignment: Alignment.center,
            child: inner,
          ),
          Positioned(
            top: -3,
            right: -2,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD97706),
                border: Border.all(color: bg, width: 1.4),
              ),
              alignment: Alignment.center,
              child: const Icon(
                LucideIcons.crown,
                size: 8,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberRow(_DraftMember m) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          // Caixa fixa de 44 — líder (com anel) e membro ficam no mesmo eixo.
          SizedBox(
            width: 44,
            height: 44,
            child: Center(child: _memberAvatar(m, leaderBadge: true)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (m.email.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    m.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: secondary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildRoleChip(m),
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remover da equipe',
            onPressed: _saving
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() => _members.remove(m));
                  },
            icon: Icon(
              LucideIcons.x,
              size: 16,
              color: secondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// Chip de papel tocável — alterna Líder (coroa âmbar) ↔ Membro.
  Widget _buildRoleChip(_DraftMember m) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isLeader = m.isLeader;
    final tone = isLeader ? _amber : secondary;
    return Material(
      color: tone.withValues(alpha: isLeader ? 0.14 : 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _saving
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(
                  () => m.role = isLeader ? 'member' : 'leader',
                );
              },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: tone.withValues(alpha: isLeader ? 0.45 : 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.crown,
                size: 12,
                color: isLeader ? _amber : secondary.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 5),
              Text(
                isLeader ? 'Líder' : 'Membro',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddMemberButton() {
    return Material(
      color: _teamColor.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _saving ? null : _addMember,
        borderRadius: BorderRadius.circular(14),
        splashColor: _teamColor.withValues(alpha: 0.14),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _teamColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.userPlus, size: 16, color: _accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Adicionar membro',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Separadores ───────────────────────────────────────────────────────────

  Widget _rowDivider({double indent = 0}) => Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.45),
      );

  Widget _sectionSeparator() => Container(
        height: 1,
        margin: const EdgeInsets.fromLTRB(_padH, 24, 0, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
              ThemeHelpers.borderColor(context).withValues(alpha: 0.0),
            ],
          ),
        ),
      );

  // ─── Barra de salvar — neutro cancela, verde confirma ─────────────────────
  //
  // Cancelar dimensiona pela largura do próprio rótulo (nunca espremido num
  // Expanded) e o rótulo não quebra linha; Salvar ocupa o resto com FittedBox
  // — aguenta fontes de acessibilidade maiores sem partir "Cancela\r".

  Widget _buildSaveBar() {
    final onConfirm = _isDark ? const Color(0xFF0B2314) : Colors.white;
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
          top: BorderSide(
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed:
                _saving ? null : () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              foregroundColor: ThemeHelpers.textSecondaryColor(context),
              side: BorderSide(
                color: ThemeHelpers.borderColor(context)
                    .withValues(alpha: 0.75),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Cancelar',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _confirm,
                foregroundColor: onConfirm,
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: onConfirm,
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.check, size: 17),
                          const SizedBox(width: 8),
                          Text(
                            _isEditing ? 'Salvar alterações' : 'Criar equipe',
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
    );
  }
}

// ─── Widgets auxiliares ──────────────────────────────────────────────────────

/// Entrada suave de seção — fade + leve subida, uma única vez ao montar.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + index * 50),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
    );
  }
}

/// Cabeçalho editorial de seção — barra tonal + eyebrow + título + subtítulo
/// (mesma gramática do ProfilePage), com trailing opcional.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.tone,
    this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Color tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
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
                      overflow: TextOverflow.fade,
                      softWrap: false,
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
                  fontSize: 21,
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
        if (trailing != null)
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 18),
            child: trailing!,
          ),
      ],
    );
  }
}

/// Eyebrow de grupo dentro da lista de membros (LIDERANÇA / TIME).
class _GroupEyebrow extends StatelessWidget {
  const _GroupEyebrow({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 11, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              color: tone,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: tone.withValues(alpha: 0.16),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fragmento de meta do masthead — ícone pequeno + texto discreto.
class _MetaBit extends StatelessWidget {
  const _MetaBit({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: iconColor.withValues(alpha: 0.8)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: secondary,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

/// Linha de configuração — placa de ícone tom-on-tom + título + descrição
/// curta + switch na cor do significado.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: value ? 0.14 : 0.08),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: tone.withValues(alpha: value ? 0.35 : 0.0),
                ),
              ),
              child: Icon(
                icon,
                size: 17,
                color: value ? tone : secondary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Switch.adaptive(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeTrackColor: tone.withValues(alpha: 0.45),
              activeThumbColor: tone,
            ),
          ],
        ),
      ),
    );
  }
}
