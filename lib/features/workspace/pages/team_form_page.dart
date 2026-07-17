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

/// Criar/editar equipe — nome, descrição, cor, membros (com papel
/// líder/membro) e, na edição, ativa/inativa + uso nas fichas de venda.
/// Estrutura flush com seções editoriais e prévia viva do cartão da equipe.
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

  /// Cor viva da equipe — pinta prévia, foco dos campos e detalhes.
  Color get _teamColor => _parseHex(_color);

  /// Verde de confirmação do sistema (Salvar/Criar).
  Color get _confirm =>
      _isDark ? AppColors.status.successDarkMode : AppColors.status.success;

  Color get _violet =>
      _isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

  Color get _sky => _isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

  Color get _amber => _isDark
      ? AppColors.message.warningTextDarkMode
      : AppColors.message.warningText;

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
        body: _loading
            ? _buildSkeleton()
            : _error != null
                ? _buildError()
                : Column(
                    children: [
                      Expanded(child: _buildForm()),
                      _buildSaveBar(),
                    ],
                  ),
      ),
    );
  }

  // ─── Skeleton fiel ao layout (prévia + seções + membros) ───────────────────

  Widget _buildSkeleton() => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 16),
        children: [
          const SkeletonBox(height: 118, borderRadius: 18),
          const SizedBox(height: 26),
          const SkeletonText(width: 90, height: 10),
          const SizedBox(height: 8),
          const SkeletonText(width: 150, height: 20),
          const SizedBox(height: 16),
          const SkeletonBox(height: 56, borderRadius: 14),
          const SizedBox(height: 12),
          const SkeletonBox(height: 88, borderRadius: 14),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < 6; i++) ...[
                const SkeletonBox(width: 40, height: 40, borderRadius: 20),
                const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 28),
          const SkeletonText(width: 70, height: 10),
          const SizedBox(height: 8),
          const SkeletonText(width: 120, height: 20),
          const SizedBox(height: 14),
          for (var i = 0; i < 3; i++) ...[
            Row(
              children: [
                const SkeletonBox(width: 40, height: 40, borderRadius: 20),
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
                const SkeletonBox(width: 64, height: 26, borderRadius: 999),
              ],
            ),
            const SizedBox(height: 14),
          ],
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
      );

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 24),
      children: [
        _buildPreviewCard(),
        const SizedBox(height: 26),
        // ── Identidade ──────────────────────────────────────────────────────
        _SectionHeader(
          eyebrow: 'QUEM É A EQUIPE',
          title: 'Identidade',
          subtitle: 'Nome, descrição e a cor que assina a equipe no sistema.',
          tone: _teamColor,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          decoration: _dec(
            'Nome da equipe *',
            hint: 'Ex.: Equipe Centro',
            errorText: _nameError ? 'Informe o nome da equipe.' : null,
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
        const SizedBox(height: 18),
        _buildColorPicker(),
        // ── Configurações (só edição) ───────────────────────────────────────
        if (_isEditing) ...[
          const SizedBox(height: 8),
          _sectionSeparator(),
          _SectionHeader(
            eyebrow: 'COMPORTAMENTO',
            title: 'Configurações',
            subtitle: 'Como a equipe aparece e é usada no dia a dia.',
            tone: _violet,
          ),
          const SizedBox(height: 14),
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
        // ── Membros ─────────────────────────────────────────────────────────
        const SizedBox(height: 8),
        _sectionSeparator(),
        _SectionHeader(
          eyebrow: 'PESSOAS',
          title: 'Membros',
          subtitle: 'Quem faz parte — toque no papel para alternar líder.',
          tone: _sky,
          trailing: _buildMembersCounter(),
        ),
        const SizedBox(height: 14),
        if (_members.isEmpty)
          _buildMembersEmpty()
        else
          for (var i = 0; i < _members.length; i++) ...[
            if (i > 0) _rowDivider(indent: 52),
            _buildMemberRow(_members[i]),
          ],
        const SizedBox(height: 14),
        _buildAddMemberButton(),
      ],
    );
  }

  // ─── Prévia viva do cartão da equipe ───────────────────────────────────────

  Widget _buildPreviewCard() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardBg = ThemeHelpers.cardBackgroundColor(context);
    final name = _name.text.trim();
    final description = _description.text.trim();
    final hasName = name.isNotEmpty;
    final leaders = _members.where((m) => m.isLeader).length;
    // Inativa desliga a cor da prévia — o cartão "apaga" junto com a equipe.
    final tone = _isActive ? _teamColor : secondary.withValues(alpha: 0.85);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Barra tonal viva à esquerda.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tone, tone.withValues(alpha: 0.35)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Monograma na cor viva.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            tone,
                            Color.lerp(tone, Colors.black, 0.22) ?? tone,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: tone.withValues(alpha: 0.32),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: hasName
                          ? Text(
                              _initialsOf(name),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            )
                          : const Icon(
                              LucideIcons.users,
                              size: 20,
                              color: Colors.white,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.eye, size: 11, color: tone),
                              const SizedBox(width: 5),
                              Text(
                                'PRÉVIA DA EQUIPE',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.6,
                                  color: tone,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            hasName ? name : 'Nome da equipe',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              color: hasName
                                  ? ThemeHelpers.textColor(context)
                                  : secondary.withValues(alpha: 0.55),
                            ),
                          ),
                          Text(
                            description.isNotEmpty
                                ? description
                                : 'Sem descrição',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: description.isNotEmpty
                                  ? secondary
                                  : secondary.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildPreviewBubbles(tone),
                    const Spacer(),
                    if (_isEditing)
                      _StatusChip(
                        label: _isActive ? 'Ativa' : 'Inativa',
                        tone: _isActive ? _confirm : secondary,
                        icon: _isActive
                            ? LucideIcons.circleCheck
                            : LucideIcons.circlePause,
                      ),
                    if (_isEditing && _useInSaleForms) ...[
                      const SizedBox(width: 6),
                      _StatusChip(
                        label: 'Fichas',
                        tone: _sky,
                        icon: LucideIcons.fileText,
                      ),
                    ],
                    if (leaders > 0) ...[
                      const SizedBox(width: 6),
                      _StatusChip(
                        label: leaders == 1 ? '1 líder' : '$leaders líderes',
                        tone: _amber,
                        icon: LucideIcons.crown,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pilha de avatares sobrepostos da prévia (até 5 + excedente).
  Widget _buildPreviewBubbles(Color tone) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardBg = ThemeHelpers.cardBackgroundColor(context);
    if (_members.isEmpty) {
      return Text(
        'Sem membros ainda',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: secondary.withValues(alpha: 0.7),
        ),
      );
    }
    const maxShown = 5;
    final shown = _members.take(maxShown).toList();
    final extra = _members.length - shown.length;
    final slots = shown.length + (extra > 0 ? 1 : 0);

    return SizedBox(
      width: 28.0 + (slots - 1) * 20.0,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 20.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cardBg, width: 2),
                ),
                child: _memberAvatar(shown[i], size: 24, fontSize: 10),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 20.0,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: 0.12),
                  border: Border.all(color: cardBg, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Seletor de cor ────────────────────────────────────────────────────────

  Widget _buildColorPicker() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.palette, size: 14, color: _teamColor),
            const SizedBox(width: 7),
            Text(
              'COR DA EQUIPE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const Spacer(),
            Text(
              'Assina o cartão e os avatares',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: secondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final hex in _teamColors) _buildSwatch(hex),
          ],
        ),
      ],
    );
  }

  /// Swatch com anel de seleção suave (aro afastado na própria cor).
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
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            width: 2,
            color: selected ? c : Colors.transparent,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(LucideIcons.check, size: 15, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  // ─── Membros ───────────────────────────────────────────────────────────────

  Widget _buildMembersCounter() {
    final total = _members.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _sky.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        total == 1 ? '1 membro' : '$total membros',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _sky,
        ),
      ),
    );
  }

  Widget _buildMembersEmpty() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _teamColor.withValues(alpha: 0.1),
              border: Border.all(
                color: _teamColor.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(LucideIcons.users, size: 24, color: _teamColor),
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum membro ainda',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Adicione corretores e defina quem lidera a equipe.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Avatar do membro — foto real quando existe, senão monograma na cor viva.
  Widget _memberAvatar(_DraftMember m, {double size = 40, double fontSize = 14}) {
    Widget monogram() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _teamColor.withValues(alpha: 0.14),
            border: Border.all(color: _teamColor.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: Text(
            _initialsOf(m.name),
            style: TextStyle(
              fontSize: fontSize * 0.78,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: _teamColor,
            ),
          ),
        );

    final hasPhoto = m.avatar != null && m.avatar!.trim().isNotEmpty;
    if (!hasPhoto) return monogram();
    return ClipOval(
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
    );
  }

  Widget _buildMemberRow(_DraftMember m) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          _memberAvatar(m),
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
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _teamColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.userPlus, size: 16, color: _teamColor),
              const SizedBox(width: 8),
              Text(
                'Adicionar membro',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _teamColor,
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
        margin: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
              ThemeHelpers.borderColor(context).withValues(alpha: 0.0),
            ],
          ),
        ),
      );

  // ─── Barra de salvar — semântica: neutro cancela, verde confirma ──────────

  Widget _buildSaveBar() {
    final onConfirm = _isDark ? const Color(0xFF0B2314) : Colors.white;
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
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 50),
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
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _confirm,
                foregroundColor: onConfirm,
                minimumSize: const Size(0, 50),
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
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.check, size: 17),
                        const SizedBox(width: 8),
                        Text(
                          _isEditing ? 'Salvar alterações' : 'Criar equipe',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets auxiliares ──────────────────────────────────────────────────────

/// Cabeçalho editorial de seção — barra tonal + eyebrow + título + subtítulo
/// (mesma gramática do ProfilePage).
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
            padding: const EdgeInsets.only(left: 10, top: 16),
            child: trailing!,
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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: value ? 0.14 : 0.08),
                borderRadius: BorderRadius.circular(11),
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

/// Chip de estado da prévia (Ativa/Inativa, Fichas, líderes).
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.tone,
    required this.icon,
  });

  final String label;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.5, color: tone),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}
