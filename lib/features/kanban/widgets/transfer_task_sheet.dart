import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_helpers.dart';
import '../controllers/kanban_controller.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';

String _serializePreService(Iterable<String> values) {
  final cleaned =
      values.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList();
  if (cleaned.isEmpty) return '';
  if (cleaned.length == 1) return cleaned.first;
  return jsonEncode(cleaned);
}

List<String> _parsePreServiceStored(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return [];
  if (s.startsWith('[')) {
    try {
      final parsed = jsonDecode(s) as dynamic;
      if (parsed is List) {
        return parsed
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}
  }
  return [s];
}

String _preServiceTokenForUser(KanbanUser u) {
  final nameTrim = u.name.trim();
  final email = u.email.trim();
  if (email.isNotEmpty && nameTrim.isNotEmpty) {
    return '$nameTrim ($email)';
  }
  if (nameTrim.isNotEmpty) return nameTrim;
  if (email.isNotEmpty) return email;
  return u.id;
}

String _todayYmd() {
  final d = DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Bottom sheet editorial: transferência entre funis (mesmo contrato do web).
class TransferTaskSheet extends StatefulWidget {
  const TransferTaskSheet({super.key, required this.task});

  final KanbanTask task;

  @override
  State<TransferTaskSheet> createState() => _TransferTaskSheetState();
}

class _TransferTaskSheetState extends State<TransferTaskSheet> {
  final KanbanService _kanbanService = KanbanService.instance;
  late String _transferDateYmd;
  String? _toProjectId;
  final Set<String> _selectedTokens = {};
  final TextEditingController _notes = TextEditingController();
  bool _loadingMembers = true;
  bool _submitting = false;
  String? _loadError;
  List<KanbanUser> _memberUsers = [];

  KanbanTask get task => widget.task;

  static const Color _routeInk = Color(0xFF4F46E5);
  static const Color _routeMuted = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _transferDateYmd = _todayYmd();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String? _originProjectId(KanbanController c) {
    final fromTask = task.projectId?.trim();
    if (fromTask != null && fromTask.isNotEmpty) return fromTask;
    final fromCtrl = c.projectId?.trim();
    if (fromCtrl != null && fromCtrl.isNotEmpty) return fromCtrl;
    return null;
  }

  Future<void> _loadMembers() async {
    final c = context.read<KanbanController>();
    final pid = _originProjectId(c);
    if (pid == null) {
      setState(() {
        _loadingMembers = false;
        _loadError = 'Funil atual não identificado.';
      });
      return;
    }
    setState(() {
      _loadingMembers = true;
      _loadError = null;
    });
    final res = await _kanbanService.getProjectMembers(pid);
    if (!mounted) return;
    if (res.success && res.data != null) {
      final users = res.data!.map((m) => m.user).toList();
      final tokensFromCard = _parsePreServiceStored(task.preService);
      final preselected = <String>{};
      for (final u in users) {
        final t = _preServiceTokenForUser(u);
        if (tokensFromCard.contains(t) ||
            tokensFromCard.contains(u.name.trim()) ||
            tokensFromCard.contains(u.email.trim())) {
          preselected.add(t);
        }
      }
      setState(() {
        _memberUsers = users;
        _selectedTokens.addAll(preselected);
        _loadingMembers = false;
      });
    } else {
      setState(() {
        _loadingMembers = false;
        _loadError = res.message ?? 'Não foi possível carregar membros do funil.';
      });
    }
  }

  DateTime? _parseYmd(String ymd) {
    try {
      final p = ymd.split('-');
      if (p.length != 3) return null;
      return DateTime(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate() async {
    final initial = _parseYmd(_transferDateYmd) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) {
        final t = Theme.of(ctx);
        return Theme(
          data: t.copyWith(
            colorScheme: t.colorScheme.copyWith(
              primary: _routeInk,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      String two(int x) => x.toString().padLeft(2, '0');
      setState(() {
        _transferDateYmd = '${picked.year}-${two(picked.month)}-${two(picked.day)}';
      });
    }
  }

  Future<void> _submit() async {
    final c = context.read<KanbanController>();
    final origin = _originProjectId(c);
    if (origin == null) return;
    if (_toProjectId == null || _toProjectId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o funil de destino.')),
      );
      return;
    }
    if (_selectedTokens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos uma pessoa em pré-atendimento.'),
        ),
      );
      return;
    }
    final pre = _serializePreService(_selectedTokens);
    if (pre.isEmpty) return;

    setState(() => _submitting = true);
    final ok = await c.transferTask(
      task.id,
      KanbanTransferTaskPayload(
        toProjectId: _toProjectId!,
        transferDate: _transferDateYmd,
        preService: pre,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card transferido.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(c.error ?? 'Falha na transferência.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final border = ThemeHelpers.borderColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final c = context.watch<KanbanController>();
    final originId = _originProjectId(c);
    final projects = c.projects
        .where((p) => p.id != originId && p.status == KanbanProjectStatus.active)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final displayDate = _parseYmd(_transferDateYmd);
    final dateLine = displayDate != null
        ? DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(displayDate)
        : _transferDateYmd;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(color: border.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
                  blurRadius: 44,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _TransferGrabber(color: border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 12, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TransferGlyphMark(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MOVIMENTAÇÃO',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.35,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Transferência de funil',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.65,
                                height: 1.02,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: _TransferTimelineStrip(
                    stepsDone: [
                      true,
                      _toProjectId != null &&
                          projects.any((p) => p.id == _toProjectId),
                      _selectedTokens.isNotEmpty,
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _SectionNum(
                        n: '01',
                        title: 'Data da transferência',
                        subtitle:
                            'Registro contábil do movimento — formato ISO enviado à API.',
                        accent: _routeInk,
                        borderColor: border,
                      ),
                      const SizedBox(height: 10),
                      _DateEditorialCard(
                        iso: _transferDateYmd,
                        prose: dateLine,
                        borderColor: border,
                        onTap: _submitting ? null : _pickDate,
                      ),
                      const SizedBox(height: 26),
                      _SectionNum(
                        n: '02',
                        title: 'Funil de destino',
                        subtitle:
                            'Somente funis ativos da mesma empresa. O card é movido, não duplicado.',
                        accent: _routeInk,
                        borderColor: border,
                      ),
                      const SizedBox(height: 12),
                      if (projects.isEmpty)
                        _EmptyFunnelCallout(
                          borderColor: border,
                          message:
                              'Não há outros funis ativos nesta lista. Abra outro funil no seletor do quadro e tente de novo.',
                        )
                      else
                        ...projects.map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ProjectRail(
                              name: p.name,
                              selected: _toProjectId == p.id,
                              enabled: !_submitting,
                              onTap: () =>
                                  setState(() => _toProjectId = p.id),
                            ),
                          ),
                        ),
                      const SizedBox(height: 26),
                      _SectionNum(
                        n: '03',
                        title: 'Pré-atendimento',
                        subtitle:
                            'Quem qualificou o lead neste funil — obrigatório; valores gravados como no CRM web.',
                        accent: _routeInk,
                        borderColor: border,
                      ),
                      const SizedBox(height: 12),
                      if (_loadingMembers)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            ),
                          ),
                        )
                      else if (_loadError != null)
                        _EmptyFunnelCallout(
                          borderColor: border,
                          isError: true,
                          message: _loadError!,
                        )
                      else if (_memberUsers.isEmpty)
                        _EmptyFunnelCallout(
                          borderColor: border,
                          message:
                              'Sem membros listados neste funil para pré-atendimento.',
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _memberUsers.map((u) {
                            final token = _preServiceTokenForUser(u);
                            final on = _selectedTokens.contains(token);
                            return _MemberLatticeChip(
                              user: u,
                              selected: on,
                              enabled: !_submitting,
                              onTap: () {
                                setState(() {
                                  if (on) {
                                    _selectedTokens.remove(token);
                                  } else {
                                    _selectedTokens.add(token);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 26),
                      _SectionNum(
                        n: '04',
                        title: 'Notas da operação',
                        subtitle: 'Opcional — visível no histórico de transferência.',
                        accent: _routeInk,
                        borderColor: border,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notes,
                        enabled: !_submitting,
                        minLines: 3,
                        maxLines: 5,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Ex.: repasse ao corretor da base, contexto da visita…',
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          contentPadding:
                              const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: border.withValues(alpha: 0.35),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: border.withValues(alpha: 0.35),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: _routeInk.withValues(alpha: 0.65),
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    12,
                    22,
                    14 + mq.padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: border.withValues(alpha: 0.35)),
                    ),
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: isDark ? 0.22 : 0.38),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(
                            'Cancelar',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: muted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _routeInk.withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: _routeInk,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: (_loadingMembers || _submitting)
                                  ? null
                                  : _submit,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 12,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_submitting)
                                      const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    else ...[
                                      const Icon(
                                        Icons.swap_horiz_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Transferir card',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Editorial pieces ──────────────────────────────────────────────────────

class _TransferGrabber extends StatelessWidget {
  const _TransferGrabber({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _TransferGlyphMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6366F1),
            Color(0xFF4338CA),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4338CA).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.hub_rounded, color: Colors.white, size: 28),
    );
  }
}

class _TransferTimelineStrip extends StatelessWidget {
  const _TransferTimelineStrip({required this.stepsDone});

  final List<bool> stepsDone;

  @override
  Widget build(BuildContext context) {
    const labels = ['Data', 'Destino', 'Pré'];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    if (i > 0)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              colors: stepsDone[i - 1]
                                  ? [
                                      _TransferTaskSheetState._routeInk,
                                      _TransferTaskSheetState._routeInk
                                          .withValues(alpha: 0.35),
                                    ]
                                  : [
                                      _TransferTaskSheetState._routeMuted
                                          .withValues(alpha: 0.25),
                                      _TransferTaskSheetState._routeMuted
                                          .withValues(alpha: 0.15),
                                    ],
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: stepsDone[i]
                            ? _TransferTaskSheetState._routeInk
                            : _TransferTaskSheetState._routeMuted
                                .withValues(alpha: 0.35),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: 1.5,
                        ),
                        boxShadow: [
                          if (stepsDone[i])
                            BoxShadow(
                              color: _TransferTaskSheetState._routeInk
                                  .withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                        ],
                      ),
                    ),
                    if (i < 2)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              colors: stepsDone[i]
                                  ? [
                                      _TransferTaskSheetState._routeInk,
                                      _TransferTaskSheetState._routeInk
                                          .withValues(alpha: 0.35),
                                    ]
                                  : [
                                      _TransferTaskSheetState._routeMuted
                                          .withValues(alpha: 0.25),
                                      _TransferTaskSheetState._routeMuted
                                          .withValues(alpha: 0.15),
                                    ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionNum extends StatelessWidget {
  const _SectionNum({
    required this.n,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.borderColor,
  });

  final String n;
  final String title;
  final String subtitle;
  final Color accent;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
            color: accent.withValues(alpha: 0.1),
          ),
          child: Text(
            n,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: accent,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateEditorialCard extends StatelessWidget {
  const _DateEditorialCard({
    required this.iso,
    required this.prose,
    required this.borderColor,
    required this.onTap,
  });

  final String iso;
  final String prose;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor.withValues(alpha: 0.38)),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: isDark ? 0.2 : 0.42),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _TransferTaskSheetState._routeInk.withValues(alpha: 0.12),
                  border: Border.all(
                    color: _TransferTaskSheetState._routeInk.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: _TransferTaskSheetState._routeInk,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      iso,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prose,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.edit_calendar_outlined,
                color: borderColor.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectRail extends StatelessWidget {
  const _ProjectRail({
    required this.name,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = ThemeHelpers.borderColor(context);
    final accent = _TransferTaskSheetState._routeInk;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.65)
                  : border.withValues(alpha: 0.32),
              width: selected ? 1.35 : 1,
            ),
            color: selected
                ? accent.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.22),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? accent : border,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: border.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberLatticeChip extends StatelessWidget {
  const _MemberLatticeChip({
    required this.user,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final KanbanUser user;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  String _initials() {
    final n = user.name.trim();
    if (n.isEmpty) return '?';
    final p = n.split(RegExp(r'\s+'));
    if (p.length == 1) return p.first.substring(0, 1).toUpperCase();
    return (p.first[0] + p.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = ThemeHelpers.borderColor(context);
    final accent = _TransferTaskSheetState._routeInk;
    final label = user.name.trim().isNotEmpty ? user.name : user.email;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : border.withValues(alpha: 0.28),
            ),
            color: selected
                ? accent.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.28),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: accent.withValues(alpha: 0.22),
                child: Text(
                  _initials(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_rounded, size: 18, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFunnelCallout extends StatelessWidget {
  const _EmptyFunnelCallout({
    required this.borderColor,
    required this.message,
    this.isError = false,
  });

  final Color borderColor;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = isError ? const Color(0xFFB91C1C) : _TransferTaskSheetState._routeInk;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.35)),
        color: c.withValues(alpha: 0.06),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: c,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isError ? c : ThemeHelpers.textSecondaryColor(context),
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
