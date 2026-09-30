import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../organization/models/unit_model.dart';
import '../../organization/services/unit_service.dart';
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

/// Nome de cada cor da paleta — a tela fala "Azul", nunca "#3B82F6".
const _teamColorNames = {
  '#EF4444': 'Vermelho',
  '#F97316': 'Laranja',
  '#F59E0B': 'Âmbar',
  '#84CC16': 'Lima',
  '#10B981': 'Esmeralda',
  '#06B6D4': 'Ciano',
  '#3B82F6': 'Azul',
  '#6366F1': 'Índigo',
  '#8B5CF6': 'Violeta',
  '#EC4899': 'Rosa',
};

/// Compara hex sem ligar pra caixa (o web pode gravar `#ef4444`).
bool _sameHex(String a, String b) =>
    a.trim().toUpperCase() == b.trim().toUpperCase();

bool _isPaletteHex(String hex) => _teamColors.any((h) => _sameHex(h, hex));

String _colorNameOf(String hex) {
  for (final h in _teamColors) {
    if (_sameHex(h, hex)) return _teamColorNames[h] ?? 'Personalizada';
  }
  return 'Personalizada';
}

/// Razão de contraste (WCAG) entre duas cores opacas.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Aproxima [c] de [target] (preto no claro, branco no escuro) só até o
/// texto ler com folga (4,5:1) sobre [bg] — âmbar, lima e ciano puros somem
/// no branco.
Color _readableOn(Color c, Color bg, Color target) {
  var out = c;
  for (var i = 0; i < 12 && _contrastRatio(out, bg) < 4.5; i++) {
    out = Color.lerp(out, target, 0.12)!;
  }
  return out;
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
/// digitado) com o trilho do que a equipe precisa (nome, unidade, membros),
/// cores todas à vista, membros como protagonistas (pilha sobreposta,
/// líderes primeiro) e configurações em linhas tonais.
class TeamFormPage extends StatefulWidget {
  const TeamFormPage({super.key, this.teamId});

  /// `null` = criação; senão edição.
  final String? teamId;

  @override
  State<TeamFormPage> createState() => _TeamFormPageState();
}

class _TeamFormPageState extends State<TeamFormPage> {
  /// Margem flush da casa (~16) e teto de leitura em tablet/landscape.
  static const double _padH = 16;
  static const double _maxW = 720;

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _nameFocus = FocusNode();
  String _color = _teamColors.first;
  bool _isActive = true;
  bool _useInSaleForms = false;
  final List<_DraftMember> _members = [];

  // Âncoras pra levar a pessoa até o que falta (trilho e tentativa de salvar).
  final _nameKey = GlobalKey();
  final _unitKey = GlobalKey();
  final _membersKey = GlobalKey();

  /// Cor fora da paleta vinda da equipe (legado do web) — fica como opção
  /// "Personalizada" pra não sumir ao experimentar outra cor.
  String? _customColor;

  // Unidade (filial) dona da equipe — obrigatória no back
  // (`CreateTeamDto.unitId`), editável na edição (paridade EditTeamPage).
  List<OrgUnit> _units = const [];
  bool _unitsLoading = true;
  String? _unitsError;
  String? _unitId;

  /// Nome vindo da própria equipe — cobre a unidade que foi desativada e
  /// por isso não volta na lista de ativas.
  String? _unitNameFallback;
  bool _unitError = false;

  bool _loading = false;
  bool _saving = false;
  bool _nameError = false;
  bool _membersError = false;

  /// Já tentou salvar — o que falta no trilho passa a falar em vermelho.
  bool _triedSave = false;
  String? _error;
  // Sem o código HTTP o erro não sabe dizer se foi permissão ou servidor.
  int _errorStatus = 0;
  Object? _errorRaw;

  /// Snapshot para detectar alterações não salvas.
  String _savedFingerprint = '';

  bool get _isEditing => widget.teamId != null;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  /// Cor CRUA da equipe — pinta swatches, monograma e avatares.
  Color get _teamColor => _parseHex(_color);

  String? _accentKey;
  Color _accentMemo = Colors.transparent;

  /// Cor da equipe ajustada pra texto/ícone pequeno: clareia no escuro e
  /// escurece no claro só até ler (4,5:1). Swatches, monograma e avatares
  /// continuam na cor crua ([_teamColor]).
  Color get _accent {
    final key = '$_color|$_isDark';
    if (_accentKey == key) return _accentMemo;
    final start =
        _isDark ? Color.lerp(_teamColor, Colors.white, 0.22)! : _teamColor;
    _accentMemo = _readableOn(
      start,
      ThemeHelpers.backgroundColor(context),
      _isDark ? Colors.white : Colors.black,
    );
    _accentKey = key;
    return _accentMemo;
  }

  /// Tom profundo do gradiente do monograma — mesma mistura com índigo
  /// profundo dos cards da lista de equipes.
  Color get _deep =>
      Color.lerp(_teamColor, const Color(0xFF312E81), _isDark ? 0.38 : 0.45)!;

  /// Verde de confirmação do sistema (Salvar/Criar).
  Color get _confirm =>
      _isDark ? AppColors.status.successDarkMode : AppColors.status.success;

  /// Mesmo verde, legível como TEXTO pequeno no branco.
  Color get _confirmText => _isDark
      ? _confirm
      : _readableOn(
          _confirm, ThemeHelpers.backgroundColor(context), Colors.black);

  Color get _sky =>
      _isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

  Color get _amber => _isDark
      ? AppColors.message.warningTextDarkMode
      : AppColors.message.warningText;

  /// Âmbar do líder como TEXTO — o token cru fica abaixo de 4,5:1 no branco.
  Color get _amberText => _isDark
      ? _amber
      : _readableOn(
          _amber, ThemeHelpers.backgroundColor(context), Colors.black);

  Color get _danger =>
      _isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

  /// Líderes primeiro — são o rosto da equipe (mesma ordem da lista).
  List<_DraftMember> get _ordered => [
        ..._members.where((m) => m.isLeader),
        ..._members.where((m) => !m.isLeader),
      ];

  int get _leadersCount => _members.where((m) => m.isLeader).length;

  // As mesmas travas do `_save` (e do back) — alimentam o trilho do topo.
  bool get _hasName => _name.text.trim().isNotEmpty;
  bool get _hasUnit => (_unitId ?? '').isNotEmpty;
  int get _missingCount =>
      (_hasName ? 0 : 1) + (_hasUnit ? 0 : 1) + (_members.isEmpty ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _savedFingerprint = _fingerprint();
    _name.addListener(_onNameChanged);
    _description.addListener(_rebuild);
    _loadUnits();
    if (_isEditing) _load();
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _description.removeListener(_rebuild);
    _name.dispose();
    _description.dispose();
    _nameFocus.dispose();
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
        _unitId ?? '',
        _isActive,
        _useInSaleForms,
        _members.map((m) => '${m.userId}:${m.role}').join(','),
      ].join('|');

  bool get _isDirty => !_saving && _fingerprint() != _savedFingerprint;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
      _errorRaw = null;
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
        _customColor = _isPaletteHex(_color) ? null : _color;
        _unitId = t.unitId;
        _unitNameFallback = t.unitName;
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
        _errorStatus = res.statusCode;
        _errorRaw = res.error;
      }
    });
  }

  /// `GET /units?activeOnly=true` — mesma fonte do web (`unitsApi.list(true)`).
  Future<void> _loadUnits() async {
    if (!_unitsLoading || _unitsError != null) {
      setState(() {
        _unitsLoading = true;
        _unitsError = null;
      });
    }
    final res = await UnitService.instance.list(activeOnly: true);
    if (!mounted) return;
    setState(() {
      _unitsLoading = false;
      if (res.success) {
        _units = res.data ?? const [];
      } else {
        _units = const [];
        _unitsError = res.message ?? 'Erro ao carregar unidades';
      }
    });
  }

  /// Aviso na hora — não fica na fila atrás do "Desfazer" de uma remoção.
  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addMember() async {
    final picked = await showTeamMemberPickerSheet(
      context,
      accent: _accent,
      excludeIds: _members.map((m) => m.userId).toSet(),
    );
    if (picked == null || picked.id.isEmpty || !mounted) return;
    if (_members.any((m) => m.userId == picked.id)) return;
    setState(() {
      _membersError = false;
      _members.add(_DraftMember(
        userId: picked.id,
        name: picked.name,
        email: picked.email,
      ));
    });
  }

  /// Tira da lista local (nada vai pro servidor antes de salvar) com
  /// "Desfazer" — tirar um líder sem querer não obriga a refazer tudo.
  void _removeMember(_DraftMember m) {
    final index = _members.indexOf(m);
    if (index < 0) return;
    HapticFeedback.selectionClick();
    setState(() => _members.removeAt(index));
    final first = m.name.trim().split(RegExp(r'\s+')).first;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          first.isEmpty
              ? 'Pessoa removida da equipe.'
              : 'Pessoa removida: $first.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        persist: false,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () {
            if (!mounted || _saving) return;
            if (_members.any((x) => x.userId == m.userId)) return;
            setState(() {
              _members.insert(math.min(index, _members.length), m);
              _membersError = false;
            });
          },
        ),
      ),
    );
  }

  /// Leva a tela até [key] (e foca o campo, se houver) — usado pelo trilho
  /// do topo e quando falta algo ao salvar.
  void _reveal(GlobalKey key, {FocusNode? focus}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
      focus?.requestFocus();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    // Cada trava também leva a tela até o que falta (o campo pode estar
    // fora de vista quando a pessoa toca em salvar lá embaixo).
    if (name.isEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _nameError = true;
        _triedSave = true;
      });
      _reveal(_nameKey, focus: _nameFocus);
      return;
    }
    // Mesmas travas e mensagens do web (CreateTeamPage/EditTeamPage).
    if ((_unitId ?? '').isEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _unitError = true;
        _triedSave = true;
      });
      _snack('Selecione a unidade (filial) da equipe');
      _reveal(_unitKey);
      return;
    }
    if (_members.isEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _membersError = true;
        _triedSave = true;
      });
      _snack(
        _isEditing
            ? 'A equipe precisa ter pelo menos um membro'
            : 'Selecione pelo menos um usuário para a equipe',
      );
      _reveal(_membersKey);
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
            unitId: _unitId,
          )
        : await CompanyTeamService.instance.createTeam(
            name: name,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            color: _color,
            members: members,
            unitId: _unitId,
          );
    if (!mounted) return;
    if (res.success) {
      _savedFingerprint = _fingerprint();
      // Um "Desfazer" pendente não pode seguir pra tela anterior.
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
          // Ficar é a saída neutra (o tema pinta TextButton de vermelho);
          // descartar é destrutivo: vermelho cheio com texto branco.
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
    // Teclado aberto em tela baixa (landscape): a barra de salvar sai de
    // cena pro campo em edição ter onde aparecer; volta quando o teclado
    // fecha (arrastar a tela também fecha).
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final hideBar =
        keyboard > 0 && MediaQuery.sizeOf(context).height - keyboard < 300;
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
                        if (!hideBar) _buildSaveBar(),
                      ],
                    ),
        ),
      ),
    );
  }

  /// Respiro lateral: área segura (entalhe no landscape) + centralização
  /// quando a tela passa do teto de leitura ([_maxW]).
  EdgeInsets _gutters(double width) {
    final safe = MediaQuery.paddingOf(context);
    final extra = width > _maxW ? (width - _maxW) / 2 : 0.0;
    return EdgeInsets.only(
      left: math.max(safe.left, extra),
      right: math.max(safe.right, extra),
    );
  }

  // ─── Skeleton fiel ao layout (masthead + trilho + campos + cores + membros)
  //
  // Só aparece na edição (carregando a equipe) — por isso já traz a seção
  // de configurações.

  Widget _buildSkeleton() => LayoutBuilder(
        builder: (context, constraints) {
          final g = _gutters(constraints.maxWidth);
          final inner = constraints.maxWidth - g.horizontal - 2 * _padH;
          final twoCols = inner >= 560;
          final swatchCols = inner >= 570 ? 10 : 5;
          return ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              g.left + _padH,
              16,
              g.right + _padH,
              16,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 56, height: 56, borderRadius: 16),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: 180, height: 24),
                        SizedBox(height: 10),
                        SkeletonText(width: 90, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Trilho dos três requisitos (nome, unidade, membros).
              Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SkeletonBox(height: 3, borderRadius: 2),
                          SizedBox(height: 10),
                          SkeletonText(width: 64, height: 12),
                          SizedBox(height: 6),
                          SkeletonText(width: 52, height: 10),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              const _SkelLine(90, 10),
              const SizedBox(height: 8),
              const _SkelLine(140, 20),
              const SizedBox(height: 16),
              if (twoCols)
                const Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 56, borderRadius: 14)),
                    SizedBox(width: 12),
                    Expanded(child: SkeletonBox(height: 56, borderRadius: 14)),
                  ],
                )
              else ...const [
                SkeletonBox(height: 56, borderRadius: 14),
                SizedBox(height: 12),
                SkeletonBox(height: 56, borderRadius: 14),
              ],
              const SizedBox(height: 12),
              const SkeletonBox(height: 80, borderRadius: 14),
              const SizedBox(height: 26),
              const _SkelLine(110, 10),
              const SizedBox(height: 10),
              const _SkelLine(200, 11),
              const SizedBox(height: 14),
              // Grade de cores — fileiras alinhadas às margens.
              for (var r = 0; r < 10 ~/ swatchCols; r++) ...[
                if (r > 0) const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < swatchCols; i++)
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: SkeletonBox(
                            width: 34,
                            height: 34,
                            borderRadius: 17,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 56),
              // Configurações — cabeçalho + duas linhas com switch.
              const _SkelLine(100, 10),
              const SizedBox(height: 8),
              const _SkelLine(150, 20),
              const SizedBox(height: 16),
              for (var i = 0; i < 2; i++) ...[
                Row(
                  children: [
                    const SkeletonBox(width: 36, height: 36, borderRadius: 11),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SkeletonText(width: 130, height: 13),
                          SizedBox(height: 6),
                          SkeletonText(width: 180, height: 10),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const SkeletonBox(width: 44, height: 26, borderRadius: 999),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 40),
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
              const SizedBox(height: 18),
              // Linhas de membro: nome em cima, papel + e-mail embaixo.
              for (var i = 0; i < 3; i++) ...[
                const Row(
                  children: [
                    SkeletonBox(width: 40, height: 40, borderRadius: 999),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(width: 150, height: 13),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              SkeletonBox(
                                width: 72,
                                height: 24,
                                borderRadius: 999,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: SkeletonText(width: 120, height: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              const SkeletonBox(height: 48, borderRadius: 14),
            ],
          );
        },
      );

  Widget _buildError() {
    return AppErrorState.fromApi(
      message: _error,
      statusCode: _errorStatus,
      error: _errorRaw,
      onRetry: _load,
    );
  }

  // ─── Formulário ────────────────────────────────────────────────────────────

  /// Campo `filled` da casa: fill sólido (no branco o campo precisa de
  /// corpo), filete leve em repouso, cor da equipe no foco, vermelho no erro
  /// — o select de unidade usa a mesma decoração.
  InputDecoration _dec(String label, {String? hint, String? errorText}) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final rest = ThemeHelpers.borderLightColor(context);
    OutlineInputBorder edge(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      errorMaxLines: 2,
      filled: true,
      fillColor: _isDark
          ? AppColors.background.backgroundTertiaryDarkMode
          : AppColors.background.backgroundTertiary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: edge(rest, 1),
      enabledBorder: edge(rest, 1),
      disabledBorder: edge(rest.withValues(alpha: 0.5), 1),
      focusedBorder: edge(_accent, 1.6),
      errorBorder: edge(_danger.withValues(alpha: 0.8), 1.2),
      focusedErrorBorder: edge(_danger, 1.6),
      labelStyle: TextStyle(
        color: secondary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: secondary.withValues(alpha: 0.75),
        fontWeight: FontWeight.w500,
      ),
      helperStyle: TextStyle(color: secondary, fontSize: 11.5, height: 1.3),
      errorStyle: TextStyle(
        color: _danger,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      // Label flutuante na cor da equipe só quando focado e sem erro —
      // erro continua vermelho, repouso continua neutro.
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        if (states.contains(WidgetState.error)) {
          return TextStyle(color: _danger, fontWeight: FontWeight.w700);
        }
        if (states.contains(WidgetState.focused)) {
          return TextStyle(color: _accent, fontWeight: FontWeight.w700);
        }
        return TextStyle(color: secondary, fontWeight: FontWeight.w600);
      }),
    );
  }

  /// Valor digitado ou escolhido — o mesmo em input e select.
  TextStyle get _fieldStyle => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ThemeHelpers.textColor(context),
      );

  Widget _buildNameField() => TextField(
        key: _nameKey,
        controller: _name,
        focusNode: _nameFocus,
        enabled: !_saving,
        textCapitalization: TextCapitalization.words,
        cursorColor: _accent,
        style: _fieldStyle,
        decoration: _dec(
          'Nome da equipe *',
          hint: 'Ex.: Equipe Centro',
          errorText: _nameError ? 'Informe o nome da equipe.' : null,
        ),
      );

  Widget _buildForm() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final g = _gutters(constraints.maxWidth);
        // Nome e unidade lado a lado quando cabe (tablet/landscape).
        final twoCols =
            constraints.maxWidth - g.horizontal - 2 * _padH >= 560;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(g.left, 16, g.right, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Entrance(index: 0, child: _buildMasthead()),
              const SizedBox(height: 28),
              // ── Identidade — obrigatórios primeiro ──────────────────────
              _Entrance(
                index: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionHeader(
                        eyebrow: 'COMO SE APRESENTA',
                        title: 'Identidade',
                        subtitle: 'Nome e unidade são obrigatórios; '
                            'a descrição é opcional.',
                        tone: _accent,
                      ),
                      const SizedBox(height: 16),
                      if (twoCols)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildNameField()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildUnitField()),
                          ],
                        )
                      else ...[
                        _buildNameField(),
                        const SizedBox(height: 12),
                        _buildUnitField(),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _description,
                        enabled: !_saving,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: _accent,
                        style: _fieldStyle,
                        decoration: _dec(
                          'Descrição (opcional)',
                          hint: 'Foco, região, especialidade…',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // ── Cor — todas as opções à vista, com nome ─────────────────
              _Entrance(index: 2, child: _buildColorBand()),
              // ── Configurações (só edição) ───────────────────────────────
              if (_isEditing) ...[
                _sectionSeparator(),
                _Entrance(
                  index: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          eyebrow: 'COMPORTAMENTO',
                          title: 'Configurações',
                          subtitle:
                              'Como a equipe aparece e é usada no dia a dia.',
                          tone: _accent,
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
                          description:
                              'Equipe selecionável ao criar novas fichas.',
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
              // ── Membros ─────────────────────────────────────────────────
              _Entrance(
                index: _isEditing ? 4 : 3,
                child: KeyedSubtree(
                  key: _membersKey,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          eyebrow: 'PESSOAS',
                          title: 'Membros',
                          subtitle: _members.isEmpty
                              ? 'Obrigatório: pelo menos uma pessoa na equipe.'
                              : _membersSubtitle(),
                          tone: _accent,
                          trailing: _members.isEmpty
                              ? null
                              : _buildHeaderAvatarStack(),
                        ),
                        const SizedBox(height: 12),
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
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Unidade (filial) — select com corpo de input ──────────────────────────

  OrgUnit? get _selectedUnit {
    final id = _unitId;
    if (id == null || id.isEmpty) return null;
    for (final u in _units) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// Linha de apoio da unidade — paridade com `descreverUnidade` do web.
  String _describeUnit(OrgUnit u) {
    final parts = <String>[];
    final desc = u.description?.trim() ?? '';
    if (desc.isNotEmpty) parts.add(desc);
    final managers = u.managers
        .map((m) => m.name.trim().split(RegExp(r'\s+')).first)
        .where((n) => n.isNotEmpty)
        .toList();
    if (managers.length == 1) {
      parts.add('Gestor: ${managers.first}');
    } else if (managers.length > 1) {
      parts.add('Gestores: ${managers.take(2).join(', ')}');
    }
    parts.add(u.teamCount == 1 ? '1 equipe' : '${u.teamCount} equipes');
    return parts.join(' · ');
  }

  /// Toque no select (ou no item "Unidade" do trilho): recarrega se falhou,
  /// explica se não há unidade ativa, senão abre a lista.
  void _onUnitTap() {
    if (_saving || _unitsLoading) return;
    if (_unitsError != null) {
      _loadUnits();
      return;
    }
    if (_units.isEmpty) {
      _snack('Cadastre uma unidade antes de criar a equipe.');
      return;
    }
    _pickUnit();
  }

  Widget _buildUnitField() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final selected = _selectedUnit;
    final hasValue = (_unitId ?? '').isNotEmpty;
    final label = selected?.name ??
        (hasValue ? (_unitNameFallback ?? 'Unidade atual') : null);
    final dotColor = selected != null
        ? Color(selected.colorValue)
        : secondary.withValues(alpha: 0.6);

    String helper;
    if (_unitsLoading) {
      helper = 'Carregando as unidades…';
    } else if (_unitsError != null) {
      helper = 'Não foi possível carregar as unidades. Toque para tentar de novo.';
    } else if (_units.isEmpty) {
      helper =
          'Nenhuma unidade ativa. Cadastre uma unidade antes de criar a equipe.';
    } else if (hasValue && selected == null) {
      helper =
          'Esta unidade não está mais entre as ativas — mantenha ou troque.';
    } else {
      helper = 'A filial à qual a equipe pertence.';
    }

    // Mesmo corpo do input (filled, 14, label flutuante); carregando, o
    // próprio campo mostra o skeleton — sem pulo de layout quando chega.
    return KeyedSubtree(
      key: _unitKey,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _saving || _unitsLoading ? null : _onUnitTap,
            child: InputDecorator(
              isEmpty: label == null && !_unitsLoading,
              decoration: _dec(
                'Unidade (filial) *',
                hint: 'Toque para escolher',
                errorText: _unitError
                    ? 'Selecione a unidade (filial) da equipe.'
                    : null,
              ).copyWith(
                enabled: !_saving,
                helperText: _unitError ? null : helper,
                helperMaxLines: 3,
                suffixIcon: _unitsLoading
                    ? null
                    : Icon(
                        _unitsError != null
                            ? LucideIcons.refreshCw
                            : LucideIcons.chevronDown,
                        size: 18,
                        color: secondary,
                      ),
              ),
              child: _unitsLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 3),
                      child: SkeletonText(width: 140, height: 14),
                    )
                  : label == null
                      ? null
                      : Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _fieldStyle,
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickUnit() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        final secondary = ThemeHelpers.textSecondaryColor(ctx);
        // Teto da régua (88%) — em landscape/tela baixa a lista rola dentro.
        final maxH = MediaQuery.sizeOf(ctx).height * 0.88;
        final safeBottom = MediaQuery.paddingOf(ctx).bottom;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(ctx)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 6, 10, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ThemeHelpers.borderLightColor(ctx),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Unidade (filial)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Escolha a filial à qual a equipe pertence.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: secondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(LucideIcons.x, size: 20, color: secondary),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 16 + safeBottom),
                  itemCount: _units.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (_, i) {
                    final u = _units[i];
                    final isSel = u.id == _unitId;
                    final tone = Color(u.colorValue);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(ctx).pop(u.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isSel
                              ? _teamColor.withValues(alpha: _isDark ? 0.16 : 0.08)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tone,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: ThemeHelpers.textColor(ctx),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _describeUnit(u),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.3,
                                      color: secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSel) ...[
                              const SizedBox(width: 8),
                              Icon(LucideIcons.check, size: 18, color: _accent),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      _unitId = picked;
      _unitError = false;
    });
  }

  String _membersSubtitle() {
    final total = _members.length;
    final leaders = _leadersCount;
    final t = total == 1 ? '1 pessoa' : '$total pessoas';
    if (leaders == 0) {
      return '$t · ninguém lidera ainda — toque em "Membro" para tornar líder.';
    }
    final l = leaders == 1 ? '1 líder' : '$leaders líderes';
    return '$t · $l — toque no papel para trocar.';
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
    final toneDeep = dimmed ? secondary.withValues(alpha: 0.6) : _deep;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  // Claro: só o crisp de 1px da casa; o escuro mantém o halo.
                  boxShadow: _isDark
                      ? [
                          BoxShadow(
                            color: tone.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                            spreadRadius: -3,
                          ),
                        ]
                      : ThemeHelpers.cardShadow(context),
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
                    // Manchete que digita junto (até 3 linhas).
                    Text(
                      hasName ? name : 'Nova equipe',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        height: 1.05,
                        fontSize: 26,
                        color: hasName
                            ? ThemeHelpers.textColor(context)
                            : secondary.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 7),
                    _buildMastheadStatus(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildNeedsRail(),
        ],
      ),
    );
  }

  /// Estado sob a manchete: na criação, o que a equipe precisa (ou que já
  /// está pronta); na edição, se está ativa e se há alteração por salvar.
  Widget _buildMastheadStatus() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final IconData icon;
    final Color tone;
    final String text;
    if (_isEditing) {
      icon = _isActive ? LucideIcons.circleCheck : LucideIcons.eyeOff;
      tone = _isActive ? _confirmText : secondary;
      text = _isActive ? 'Ativa' : 'Inativa — fora das listagens';
    } else if (_missingCount == 0) {
      icon = LucideIcons.circleCheck;
      tone = _confirmText;
      text = 'Tudo pronto para criar a equipe.';
    } else {
      icon = LucideIcons.info;
      tone = secondary;
      text = 'Precisa de nome, unidade e ao menos 1 membro.';
    }
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(icon, size: 14, color: tone),
            ),
          ),
          TextSpan(text: text, style: TextStyle(color: tone)),
          if (_isEditing && _isDirty)
            TextSpan(
              text: '  ·  alterações não salvas',
              style: TextStyle(color: _amberText),
            ),
        ],
      ),
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }

  /// Trilho do que a equipe precisa pra ser salva — as mesmas travas do
  /// salvar (e do back): nome, unidade e ao menos 1 membro. Estado ao vivo;
  /// tocar num item leva direto ao que falta.
  Widget _buildNeedsRail() {
    final n = _members.length;
    final unitName = _selectedUnit?.name ?? _unitNameFallback ?? 'Escolhida';
    List<Widget> segments(bool stacked) => [
          _NeedSegment(
            stacked: stacked,
            label: 'Nome',
            value: _hasName ? 'Preenchido' : 'Falta preencher',
            done: _hasName,
            alert: _triedSave && !_hasName,
            doneTone: _confirm,
            alertTone: _danger,
            onTap: _saving
                ? null
                : () => _reveal(_nameKey, focus: _nameFocus),
          ),
          _NeedSegment(
            stacked: stacked,
            label: 'Unidade',
            value: _hasUnit ? unitName : 'Falta escolher',
            done: _hasUnit,
            alert: _triedSave && !_hasUnit,
            doneTone: _confirm,
            alertTone: _danger,
            onTap: _saving
                ? null
                : () {
                    if (_unitsLoading) {
                      _reveal(_unitKey);
                    } else {
                      _onUnitTap();
                    }
                  },
          ),
          _NeedSegment(
            stacked: stacked,
            label: 'Membros',
            value: n == 0
                ? 'Falta adicionar'
                : n == 1
                    ? '1 pessoa'
                    : '$n pessoas',
            done: n > 0,
            alert: _triedSave && n == 0,
            doneTone: _confirm,
            alertTone: _danger,
            onTap: _saving
                ? null
                : n == 0
                    ? _addMember
                    : () => _reveal(_membersKey),
          ),
        ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Três colunas quando cabem; tela estreita com fonte grande (320dp
        // a 130%) vira lista de três linhas — nada de "Membr…".
        final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
        final stacked = (constraints.maxWidth - 20) / 3 < 78 * scale;
        final items = segments(stacked);
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: items[i]),
            ],
          ],
        );
      },
    );
  }

  // ─── Cor da equipe — todas as opções à vista, com nome ────────────────────

  Widget _buildColorBand() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final options = [
      if (_customColor != null) _customColor!,
      ..._teamColors,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.palette, size: 14, color: _accent),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'COR DA EQUIPE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // A escolha dita em palavras — nada de código hex na tela.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _colorNameOf(_color),
                  style: TextStyle(fontWeight: FontWeight.w800, color: _accent),
                ),
                const TextSpan(
                  text: ' — identifica a equipe nas listas e nas fichas.',
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: secondary,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) =>
                _buildSwatchGrid(options, constraints.maxWidth),
          ),
        ],
      ),
    );
  }

  /// Grade uniforme: 5 por fileira no celular, as 10 numa fileira só quando
  /// cabe — primeira e última encostadas nas margens, alvo de toque de 48.
  Widget _buildSwatchGrid(List<String> options, double width) {
    final cols = width >= 570 ? 10 : 5;
    final size =
        math.min(48.0, math.max(0.0, (width - (cols - 1) * 8) / cols));
    final gap = (width - cols * size) / (cols - 1);
    final rows = <Widget>[];
    for (var start = 0; start < options.length; start += cols) {
      final end = math.min(start + cols, options.length);
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(
        Row(
          children: [
            for (var i = start; i < end; i++) ...[
              if (i > start) SizedBox(width: gap),
              _buildSwatch(options[i], size),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  /// Swatch com anel de seleção afastado na cor do texto (lê sobre qualquer
  /// cor, nos dois temas) + check no tom que contrasta com a própria cor.
  Widget _buildSwatch(String hex, double size) {
    final c = _parseHex(hex);
    final selected = _sameHex(_color, hex);
    final ring = ThemeHelpers.textColor(context);
    final dark = AppColors.text.text;
    final onSwatch = _contrastRatio(Colors.white, c) >= _contrastRatio(dark, c)
        ? Colors.white
        : dark;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: _isPaletteHex(hex)
            ? 'Cor ${_colorNameOf(hex)}'
            : 'Cor atual, personalizada',
        child: InkResponse(
          radius: size / 2 + 4,
          onTap: _saving
              ? null
              : () {
                  // Tocar na já escolhida não "suja" o formulário.
                  if (_sameHex(_color, hex)) return;
                  HapticFeedback.selectionClick();
                  setState(() => _color = hex);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            padding: EdgeInsets.all(selected ? 3 : 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                width: 2,
                color: selected
                    ? ring.withValues(alpha: 0.9)
                    : Colors.transparent,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              child: selected
                  ? Icon(LucideIcons.check, size: size * 0.4, color: onSwatch)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Membros — protagonistas ──────────────────────────────────────────────

  /// Pilha de avatares sobrepostos no cabeçalho da seção (líderes primeiro,
  /// mesma gramática dos cards da lista) + bolha de excedente. Decorativa
  /// pro leitor de tela: a contagem já está dita no subtítulo.
  Widget _buildHeaderAvatarStack() {
    const maxShown = 4;
    final ordered = _ordered;
    final shown = ordered.take(maxShown).toList();
    final extra = ordered.length - shown.length;
    final bg = ThemeHelpers.backgroundColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return ExcludeSemantics(
      child: Row(
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
                    color: _accent,
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
      ),
    );
  }

  /// Vazio que ensina — trio de "assentos" esperando gente, o que fazer e,
  /// depois de uma tentativa de salvar, o aviso em vermelho.
  Widget _buildMembersEmpty() {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adicione quem faz parte do time. Depois, toque no papel de cada '
            'pessoa para definir quem lidera.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: secondary,
            ),
          ),
          if (_membersError) ...[
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        LucideIcons.circleAlert,
                        size: 14,
                        color: _danger,
                      ),
                    ),
                  ),
                  const TextSpan(
                    text: 'Adicione pelo menos uma pessoa para salvar.',
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: _danger,
              ),
            ),
          ],
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
        tone: _amberText,
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
                errorBuilder: (_, _, _) => monogram(),
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
                color: AppColors.message.warningText,
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

  /// Linha de membro: o nome ganha a largura toda; papel (tocável) + e-mail
  /// vão na 2ª linha — em 320dp com fonte 130% o nome não vira "Mari…".
  Widget _buildMemberRow(_DraftMember m) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _buildRoleChip(m),
                    if (m.email.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: secondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Remover da equipe',
            onPressed: _saving ? null : () => _removeMember(m),
            icon: Icon(LucideIcons.x, size: 18, color: secondary),
          ),
        ],
      ),
    );
  }

  /// Papel tocável — mostra o papel atual (Líder com coroa âmbar ↔ Membro) e
  /// alterna no toque; o leitor de tela ouve o estado e o que o toque faz.
  Widget _buildRoleChip(_DraftMember m) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isLeader = m.isLeader;
    final tone = isLeader ? _amber : secondary;
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: isLeader ? 'Toque para tornar membro' : 'Toque para tornar líder',
        child: Material(
          color: tone.withValues(alpha: isLeader ? 0.14 : 0.08),
          shape: StadiumBorder(
            side: BorderSide(
              color: tone.withValues(alpha: isLeader ? 0.45 : 0.28),
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _saving
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(
                      () => m.role = isLeader ? 'member' : 'leader',
                    );
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.crown,
                    size: 12,
                    color: isLeader ? _amber : secondary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isLeader ? 'Líder' : 'Membro',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: isLeader ? _amberText : secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddMemberButton() {
    return Semantics(
      button: true,
      child: Material(
        color: _teamColor.withValues(alpha: _isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _saving ? null : _addMember,
          borderRadius: BorderRadius.circular(14),
          splashColor: _teamColor.withValues(alpha: 0.14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _teamColor.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.userPlus, size: 17, color: _accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Adicionar membro',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _accent,
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

  // ─── Separadores — filetes sólidos (hairline da casa) ─────────────────────

  Widget _rowDivider({double indent = 0}) => Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        color: ThemeHelpers.borderLightColor(context),
      );

  /// Entre seções: sai da margem esquerda e corre até a borda.
  Widget _sectionSeparator() => Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 28, 0, 28),
        child: Container(
          height: 1,
          color: ThemeHelpers.borderLightColor(context),
        ),
      );

  // ─── Barra de salvar — neutro cancela, verde confirma ─────────────────────
  //
  // Cancelar dimensiona pela largura do próprio rótulo (nunca espremido num
  // Expanded) e o rótulo não quebra linha; Salvar ocupa o resto com FittedBox
  // — aguenta fontes de acessibilidade maiores sem partir "Cancela\r". Em
  // tablet/landscape acompanha a coluna do formulário (mesmo teto e entalhe).

  Widget _buildSaveBar() {
    final onConfirm = ThemeHelpers.onPrimaryColor(context);
    final g = _gutters(MediaQuery.sizeOf(context).width);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16 + g.left,
        10,
        16 + g.right,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
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
                // Salvando: continua verde (esmaecido) e o spinner aparece —
                // o cinza padrão de desabilitado apagava o spinner branco.
                disabledBackgroundColor: _confirm.withValues(alpha: 0.6),
                disabledForegroundColor: onConfirm,
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
              // Título de uma palavra: com fonte enorme encolhe um pouco em
              // vez de quebrar no meio ("Configuraçõ/es").
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    color: ThemeHelpers.textColor(context),
                    height: 1.05,
                    fontSize: 21,
                  ),
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

/// Barra de texto do skeleton alinhada à esquerda — filho direto da
/// ListView seria esticado na largura toda.
class _SkelLine extends StatelessWidget {
  const _SkelLine(this.width, this.height);

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: SkeletonText(width: width, height: height),
      );
}

/// Um requisito do trilho do topo — barra que acende em verde quando está
/// cumprido (vermelho se faltou ao tentar salvar), ícone de estado, nome do
/// requisito e o valor ou o que falta. Em coluna (padrão) a barra fica em
/// cima; [stacked] (tela estreita + fonte grande) vira linha com a barra à
/// esquerda e o valor à direita. Tocável nos dois jeitos.
class _NeedSegment extends StatelessWidget {
  const _NeedSegment({
    required this.label,
    required this.value,
    required this.done,
    required this.alert,
    required this.doneTone,
    required this.alertTone,
    this.stacked = false,
    this.onTap,
  });

  final String label;
  final String value;
  final bool done;
  final bool alert;
  final Color doneTone;
  final Color alertTone;
  final bool stacked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Trilho vazio visível nos dois temas (no escuro o borderLight é o que
    // aparece sobre o grafite).
    final track = isDark
        ? ThemeHelpers.borderLightColor(context)
        : ThemeHelpers.borderColor(context);
    final tone = done
        ? doneTone
        : alert
            ? alertTone
            : null;
    final icon = Icon(
      done
          ? LucideIcons.circleCheck
          : alert
              ? LucideIcons.circleAlert
              : LucideIcons.circleDashed,
      size: 14,
      color: tone ?? secondary.withValues(alpha: 0.75),
    );
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.1,
      color: ThemeHelpers.textColor(context),
    );
    final valueStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: alert ? alertTone : secondary,
    );
    final bar = BoxDecoration(
      color: tone ?? track,
      borderRadius: BorderRadius.circular(2),
    );

    final Widget body;
    if (stacked) {
      body = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 3,
              height: 22,
              decoration: bar,
            ),
            const SizedBox(width: 10),
            icon,
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: valueStyle,
              ),
            ),
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              height: 3,
              decoration: bar,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                icon,
                const SizedBox(width: 6),
                // Rótulo de uma palavra: encolhe um pouco antes de cortar.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: labelStyle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ],
        ),
      );
    }

    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: body,
        ),
      ),
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
