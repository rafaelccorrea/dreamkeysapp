import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../assets/widgets/user_picker_sheet.dart';
import '../services/company_team_service.dart';

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

/// Membro em edição local (antes de salvar).
class _DraftMember {
  final String userId;
  final String name;
  String role; // 'member' | 'leader'
  _DraftMember({required this.userId, required this.name, this.role = 'member'});
}

/// Criar/editar equipe — porta o CreateTeamPage/EditTeamPage do web:
/// nome, descrição, cor, membros (com papel líder/membro) e, na edição,
/// ativa/inativa + uso nas fichas de venda.
class TeamFormPage extends StatefulWidget {
  const TeamFormPage({super.key, this.teamId});

  /// `null` = criação; senão edição.
  final String? teamId;

  @override
  State<TeamFormPage> createState() => _TeamFormPageState();
}

class _TeamFormPageState extends State<TeamFormPage> {
  static const double _padH = 16;

  final _name = TextEditingController();
  final _description = TextEditingController();
  String _color = _teamColors.first;
  bool _isActive = true;
  bool _useInSaleForms = false;
  final List<_DraftMember> _members = [];

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.teamId != null;

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

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
            (m) => _DraftMember(userId: m.userId, name: m.name, role: m.role),
          ));
      } else {
        _error = res.message ?? 'Erro ao carregar equipe';
      }
    });
  }

  Future<void> _addMember() async {
    final picked = await showUserPickerSheet(context);
    if (picked == null || picked.id.isEmpty || !mounted) return;
    if (_members.any((m) => m.userId == picked.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este usuário já está na equipe.')),
      );
      return;
    }
    setState(() {
      _members.add(_DraftMember(userId: picked.id, name: picked.name));
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome da equipe.')),
      );
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
    setState(() => _saving = false);
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
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
    );
  }

  Widget _buildSkeleton() => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 16),
        children: const [
          SkeletonBox(height: 56, borderRadius: 14),
          SizedBox(height: 12),
          SkeletonBox(height: 96, borderRadius: 14),
          SizedBox(height: 12),
          SkeletonBox(height: 48, borderRadius: 14),
          SizedBox(height: 12),
          SkeletonBox(height: 180, borderRadius: 14),
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
            Icon(LucideIcons.cloudOff, size: 40, color: secondary),
            const SizedBox(height: 12),
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

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
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
          borderSide: BorderSide(color: _accent, width: 1.6),
        ),
      );

  Widget _sectionLabel(IconData icon, String label, {Widget? trailing}) => Row(
        children: [
          Icon(icon, size: 14, color: _accent),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      );

  Widget _buildForm() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 20),
      children: [
        TextField(
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          decoration: _dec('Nome da equipe *', hint: 'Ex.: Equipe Centro'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          enabled: !_saving,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: _dec('Descrição', hint: 'Opcional'),
        ),
        const SizedBox(height: 18),
        _sectionLabel(LucideIcons.palette, 'Cor da equipe'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final hex in _teamColors)
              GestureDetector(
                onTap: _saving ? null : () => setState(() => _color = hex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _parseHex(hex),
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: 3,
                      color: _color == hex
                          ? ThemeHelpers.textColor(context)
                          : Colors.transparent,
                    ),
                  ),
                  child: _color == hex
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
        if (_isEditing) ...[
          const SizedBox(height: 18),
          _sectionLabel(LucideIcons.settings2, 'Configurações'),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _isActive,
            onChanged: _saving ? null : (v) => setState(() => _isActive = v),
            title: const Text(
              'Equipe ativa',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          SwitchListTile(
            value: _useInSaleForms,
            onChanged:
                _saving ? null : (v) => setState(() => _useInSaleForms = v),
            title: const Text(
              'Usar nas fichas de venda',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Equipe selecionável ao criar fichas.',
              style: TextStyle(fontSize: 11.5, color: secondary),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
        const SizedBox(height: 18),
        _sectionLabel(
          LucideIcons.users,
          'Membros',
          trailing: Text(
            '${_members.length}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: secondary,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(14),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Column(
            children: [
              if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nenhum membro ainda. Adicione colaboradores à equipe.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ),
              for (var i = 0; i < _members.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 14,
                    endIndent: 14,
                    color: ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.4),
                  ),
                _memberRow(_members[i]),
              ],
              Divider(
                height: 1,
                thickness: 1,
                color: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.4),
              ),
              InkWell(
                onTap: _saving ? null : _addMember,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.userPlus, size: 16, color: _accent),
                      const SizedBox(width: 8),
                      Text(
                        'Adicionar membro',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _accent,
                        ),
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

  Widget _memberRow(_DraftMember m) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isLeader = m.role == 'leader';
    final leaderTone = const Color(0xFFD97706);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _parseHex(_color).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              m.name.isEmpty ? '?' : m.name.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _parseHex(_color),
              ),
            ),
          ),
          const SizedBox(width: 10),
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
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                Text(
                  isLeader ? 'Líder' : 'Membro',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isLeader ? leaderTone : secondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: isLeader ? 'Tornar membro' : 'Tornar líder',
            onPressed: _saving
                ? null
                : () => setState(
                      () => m.role = isLeader ? 'member' : 'leader',
                    ),
            icon: Icon(
              LucideIcons.crown,
              size: 17,
              color: isLeader ? leaderTone : secondary.withValues(alpha: 0.55),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remover da equipe',
            onPressed: _saving
                ? null
                : () => setState(() => _members.remove(m)),
            icon: Icon(
              LucideIcons.x,
              size: 17,
              color: secondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
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
            color: ThemeHelpers.borderLightColor(context)
                .withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isEditing ? 'Salvar equipe' : 'Criar equipe'),
            ),
          ),
        ],
      ),
    );
  }
}
