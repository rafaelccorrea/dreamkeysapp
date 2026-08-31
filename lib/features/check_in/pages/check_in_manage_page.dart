import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/check_in_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Gestão do check-in — o que só o gestor faz.
///
/// Reúne num lugar só as quatro ações que no web moram espalhadas na tela de
/// histórico: registrar o check-in por alguém, liberar um check-in fora da
/// janela, soltar o bloqueio semanal e ler o histórico dessas intervenções.
/// A lista de check-ins continua na tela de histórico — aqui é ação, não
/// consulta.
class CheckInManagePage extends StatefulWidget {
  const CheckInManagePage({super.key});

  @override
  State<CheckInManagePage> createState() => _CheckInManagePageState();
}

class _CheckInManagePageState extends State<CheckInManagePage> {
  bool _loading = true;
  String? _error;
  int _errorStatus = 0;

  CheckInVisibleUsers _visible = CheckInVisibleUsers.empty;
  List<CheckInBlock> _blocks = const [];
  List<CheckInAuditEntry> _audit = const [];

  /// Id em ação — trava só a linha, não a tela inteira.
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
    });
    // Record `.wait` em vez de `Future.wait([...])`: preserva o tipo de cada
    // resposta em vez de rebaixar tudo para Object.
    final (visibleRes, blocksRes, auditRes) = await (
      CheckInService.instance.getVisibleUsers(),
      CheckInService.instance.listBlocks(),
      CheckInService.instance.listAudit(limit: 60),
    ).wait;
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (visibleRes.success && visibleRes.data != null) {
        _visible = visibleRes.data!;
      }
      if (blocksRes.success && blocksRes.data != null) {
        _blocks = blocksRes.data!.where((b) => !b.isReleased).toList();
      }
      if (auditRes.success && auditRes.data != null) {
        _audit = auditRes.data!;
      }
      // Só é erro de tela quando NADA veio — seção vazia não é falha.
      if (!visibleRes.success && !blocksRes.success && !auditRes.success) {
        _error = visibleRes.message ?? 'Erro ao carregar a gestão de check-in';
        _errorStatus = visibleRes.statusCode;
      }
    });
  }

  Future<void> _refresh() async => _bootstrap();

  // ── Ações ──────────────────────────────────────────────────────────────────

  Future<CheckInUser?> _pickPerson(String titulo) async {
    if (_visible.users.isEmpty) {
      _snack('Nenhum colaborador no seu escopo.', error: true);
      return null;
    }
    return showModalBottomSheet<CheckInUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PersonSheet(title: titulo, users: _visible.users),
    );
  }

  Future<void> _forceCheckIn() async {
    final pessoa = await _pickPerson('Registrar check-in por');
    if (pessoa == null || !mounted) return;
    final nota = await _askNote(
      title: 'Registrar check-in',
      subtitle:
          'O check-in de ${_nameOf(pessoa)} será registrado ignorando janela, '
          'raio e bloqueio. A pessoa é notificada.',
      hint: 'Motivo (opcional)',
      confirmLabel: 'Registrar',
      accent: _emerald(context),
    );
    if (nota == null || !mounted) return;

    setState(() => _busyId = pessoa.id);
    final res = await CheckInService.instance.forceCheckIn(
      userId: pessoa.id,
      note: nota.isEmpty ? null : nota,
    );
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!res.success) {
      _snack(res.message ?? 'Não foi possível registrar.', error: true);
      return;
    }
    _snack('Check-in de ${_nameOf(pessoa)} registrado.');
    unawaited(_bootstrap());
  }

  Future<void> _grantException() async {
    final pessoa = await _pickPerson('Liberar fora do horário');
    if (pessoa == null || !mounted) return;

    final horas = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DurationSheet(personName: _nameOf(pessoa)),
    );
    if (horas == null || !mounted) return;

    final ate = DateTime.now().add(Duration(hours: horas));
    setState(() => _busyId = pessoa.id);
    final res = await CheckInService.instance.grantException(
      userId: pessoa.id,
      validUntil: ate,
    );
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!res.success) {
      _snack(res.message ?? 'Não foi possível liberar.', error: true);
      return;
    }
    _snack(
      'Liberação válida até ${DateFormat('HH:mm').format(ate)} '
      'para ${_nameOf(pessoa)}.',
    );
    unawaited(_bootstrap());
  }

  Future<void> _unblock(CheckInBlock bloqueio) async {
    final nome = _nameOf(bloqueio.user);
    final motivo = await _askNote(
      title: 'Liberar bloqueio',
      subtitle:
          '$nome volta a poder fazer check-in nesta semana. O motivo fica '
          'registrado no histórico.',
      hint: 'Motivo da liberação',
      confirmLabel: 'Liberar',
      accent: _emerald(context),
      required: true,
    );
    if (motivo == null || !mounted) return;

    setState(() => _busyId = bloqueio.id);
    final res = await CheckInService.instance.unblock(
      userId: bloqueio.userId,
      reason: motivo,
    );
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!res.success) {
      _snack(
        res.message ?? 'Não foi possível liberar o bloqueio.',
        error: true,
      );
      return;
    }
    _snack('Bloqueio de $nome liberado.');
    unawaited(_bootstrap());
  }

  /// Folha de texto reaproveitada pelas três ações. Devolve `null` quando o
  /// gestor desiste e a string (possivelmente vazia) quando confirma.
  Future<String?> _askNote({
    required String title,
    required String subtitle,
    required String hint,
    required String confirmLabel,
    required Color accent,
    bool required = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoteSheet(
        title: title,
        subtitle: subtitle,
        hint: hint,
        confirmLabel: confirmLabel,
        accent: accent,
        required: required,
      ),
    );
  }

  // ── Utilitários ────────────────────────────────────────────────────────────

  String _nameOf(CheckInUser? u) {
    final nome = u?.name?.trim();
    if (nome != null && nome.isNotEmpty) return nome;
    final email = u?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'colaborador';
  }

  Color _emerald(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF34D399)
      : const Color(0xFF059669);

  void _snack(String message, {bool error = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : (isDark
                  ? AppColors.status.greenDarkMode
                  : AppColors.status.green),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Icon(
              error ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tela ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Gestão do check-in',
      showBottomNavigation: false,
      body: _loading
          ? _buildSkeleton()
          : _error != null
          ? AppErrorState.fromApi(
              message: _error,
              statusCode: _errorStatus,
              onRetry: _refresh,
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ManageHeader(
                      scope: _visible.scope,
                      people: _visible.users.length,
                      blocked: _blocks.length,
                    ),
                    const SizedBox(height: 22),
                    _SectionLabel(
                      icon: LucideIcons.zap,
                      label: 'AÇÕES',
                      accent: _emerald(context),
                    ),
                    const SizedBox(height: 10),
                    _ActionRow(
                      icon: LucideIcons.userCheck,
                      title: 'Registrar check-in por alguém',
                      subtitle:
                          'Ignora janela, raio e bloqueio. A pessoa é avisada.',
                      accent: _emerald(context),
                      onTap: _forceCheckIn,
                    ),
                    const SizedBox(height: 8),
                    _ActionRow(
                      icon: LucideIcons.unlock,
                      title: 'Liberar fora do horário',
                      subtitle:
                          'Vale por até 24h e é consumida no primeiro check-in.',
                      accent: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0284C7),
                      onTap: _grantException,
                    ),
                    const SizedBox(height: 26),
                    _SectionLabel(
                      icon: LucideIcons.lock,
                      label:
                          'BLOQUEIOS DA SEMANA'
                          '${_blocks.isEmpty ? '' : ' · ${_blocks.length}'}',
                      accent: _blocks.isEmpty
                          ? ThemeHelpers.textSecondaryColor(context)
                          : (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFFFB7185)
                                : const Color(0xFFE11D48)),
                    ),
                    const SizedBox(height: 10),
                    if (_blocks.isEmpty)
                      _QuietLine(
                        icon: LucideIcons.checkCircle2,
                        text: 'Ninguém bloqueado nesta semana.',
                      )
                    else
                      ..._blocks.map(
                        (b) => _BlockRow(
                          block: b,
                          name: _nameOf(b.user),
                          busy: _busyId == b.id,
                          onUnblock: () => _unblock(b),
                        ),
                      ),
                    const SizedBox(height: 26),
                    _SectionLabel(
                      icon: LucideIcons.history,
                      label: 'HISTÓRICO DE AÇÕES',
                      accent: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(height: 10),
                    if (_audit.isEmpty)
                      _QuietLine(
                        icon: LucideIcons.fileText,
                        text: 'Nenhuma intervenção registrada até agora.',
                      )
                    else
                      ..._audit.map(
                        (a) => _AuditRow(
                          entry: a,
                          targetName: _nameOf(a.targetUser),
                          actorName: a.isSystem ? 'Sistema' : _nameOf(a.actor),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 22, width: 200, borderRadius: 8),
          const SizedBox(height: 10),
          SkeletonBox(height: 34, borderRadius: 8),
          const SizedBox(height: 24),
          SkeletonBox(height: 14, width: 120, borderRadius: 6),
          const SizedBox(height: 10),
          SkeletonBox(height: 60, borderRadius: 14),
          const SizedBox(height: 8),
          SkeletonBox(height: 60, borderRadius: 14),
          const SizedBox(height: 26),
          SkeletonBox(height: 14, width: 160, borderRadius: 6),
          const SizedBox(height: 10),
          SkeletonBox(height: 52, borderRadius: 12),
        ],
      ),
    );
  }
}

// ─── Cabeçalho ───────────────────────────────────────────────────────────────

class _ManageHeader extends StatelessWidget {
  final String scope;
  final int people;
  final int blocked;

  const _ManageHeader({
    required this.scope,
    required this.people,
    required this.blocked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final indigo = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final escopo = switch (scope) {
      'all' => 'toda a empresa',
      'team' => 'sua equipe',
      _ => 'você',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.shieldCheck, size: 13, color: indigo),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                'ESCOPO: ${escopo.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: indigo,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          blocked == 0
              ? 'Semana sem pendências'
              : '$blocked ${blocked == 1 ? 'pessoa bloqueada' : 'pessoas bloqueadas'}',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            height: 1.1,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          people == 0
              ? 'Você ainda não tem colaboradores no seu escopo de check-in.'
              : 'Você responde pelo check-in de $people '
                    '${people == 1 ? 'pessoa' : 'pessoas'}.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: muted,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// ─── Section label (mesma gramática das outras telas de check-in) ────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 13, color: accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              fontSize: 10.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: muted.withValues(alpha: 0.22)),
        ),
      ],
    );
  }
}

// ─── Linha de ação ───────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.11),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.chevronRight, size: 16, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Linha de bloqueio ───────────────────────────────────────────────────────

class _BlockRow extends StatelessWidget {
  final CheckInBlock block;
  final String name;
  final bool busy;
  final VoidCallback onUnblock;

  const _BlockRow({
    required this.block,
    required this.name,
    required this.busy,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rose = isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3.5,
            height: 34,
            decoration: BoxDecoration(
              color: rose,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
                Text(
                  block.reasonLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onUnblock,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: emerald.withValues(alpha: isDark ? 0.16 : 0.09),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: emerald.withValues(alpha: isDark ? 0.34 : 0.24),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.unlock, size: 13, color: emerald),
                      const SizedBox(width: 6),
                      Text(
                        'Liberar',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: emerald,
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

// ─── Linha de auditoria ──────────────────────────────────────────────────────

class _AuditRow extends StatelessWidget {
  final CheckInAuditEntry entry;
  final String targetName;
  final String actorName;

  const _AuditRow({
    required this.entry,
    required this.targetName,
    required this.actorName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    // Cor por significado: liberar é verde, bloquear/desfazer é vermelho,
    // registrar pelo gestor é azul.
    final Color tone = switch (entry.action) {
      'unblock' || 'grant_exception' =>
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
      'weekly_block' || 'undo_check_in' =>
        isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48),
      _ => isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
    };
    final quando = entry.createdAt;
    final nota = entry.note;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.actionLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$targetName · por $actorName'
                  '${quando != null ? ' · ${DateFormat('dd/MM HH:mm').format(quando.toLocal())}' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (nota != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    nota,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Linha de estado vazio ───────────────────────────────────────────────────

class _QuietLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _QuietLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: muted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Folha: escolher pessoa ──────────────────────────────────────────────────

class _PersonSheet extends StatefulWidget {
  final String title;
  final List<CheckInUser> users;
  const _PersonSheet({required this.title, required this.users});

  @override
  State<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<_PersonSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final indigo = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final termo = _search.text.trim().toLowerCase();
    final lista = termo.isEmpty
        ? widget.users
        : widget.users
              .where(
                (u) =>
                    (u.name ?? '').toLowerCase().contains(termo) ||
                    (u.email ?? '').toLowerCase().contains(termo),
              )
              .toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COLABORADOR',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Buscar pelo nome',
                        prefixIcon: Icon(
                          LucideIcons.search,
                          size: 16,
                          color: muted,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      indigo.withValues(alpha: 0.35),
                      indigo.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: lista.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
                        child: Text(
                          'Ninguém encontrado com esse nome.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
                        itemCount: lista.length,
                        itemBuilder: (_, i) {
                          final u = lista[i];
                          final nome = (u.name?.trim().isNotEmpty ?? false)
                              ? u.name!.trim()
                              : (u.email ?? 'Sem nome');
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.pop(context, u),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      LucideIcons.user,
                                      size: 15,
                                      color: indigo,
                                    ),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Text(
                                        nome,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: ThemeHelpers.textColor(
                                                context,
                                              ),
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    Icon(
                                      LucideIcons.chevronRight,
                                      size: 15,
                                      color: muted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Folha: por quanto tempo vale a liberação ────────────────────────────────

/// O backend recusa liberação acima de 24h, então a folha só oferece prazos
/// dentro do limite — melhor que um seletor de data que devolve 400.
class _DurationSheet extends StatelessWidget {
  final String personName;
  const _DurationSheet({required this.personName});

  static const _opcoes = <int, String>{
    1: 'Uma hora',
    2: 'Duas horas',
    4: 'Quatro horas',
    8: 'Até o fim do expediente',
    24: 'Vinte e quatro horas',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sky = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final agora = DateTime.now();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LIBERAÇÃO VALE POR',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.8,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    personName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    sky.withValues(alpha: 0.35),
                    sky.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
                children: _opcoes.entries.map((e) {
                  final ate = agora.add(Duration(hours: e.key));
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, e.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.timer, size: 15, color: sky),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    e.value,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: ThemeHelpers.textColor(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Até ${DateFormat('dd/MM HH:mm').format(ate)}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              LucideIcons.chevronRight,
                              size: 15,
                              color: muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Folha: confirmar com observação ─────────────────────────────────────────

class _NoteSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String hint;
  final String confirmLabel;
  final Color accent;
  final bool required;

  const _NoteSheet({
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.confirmLabel,
    required this.accent,
    required this.required,
  });

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final preenchido = _controller.text.trim().isNotEmpty;
    final podeConfirmar = !widget.required || preenchido;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: muted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  onChanged: (_) => setState(() {}),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  maxLines: 3,
                  minLines: 2,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          // O tema global pinta TextButton de vermelho;
                          // "Cancelar" nunca é destrutivo.
                          foregroundColor: ThemeHelpers.textSecondaryColor(
                            context,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: podeConfirmar
                            ? () => Navigator.pop(
                                context,
                                _controller.text.trim(),
                              )
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: FittedBox(
                          child: Text(
                            widget.confirmLabel,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
