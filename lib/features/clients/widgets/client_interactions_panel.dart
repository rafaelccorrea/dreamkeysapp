import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';

/// Painel de interações com o cliente — timeline cronológica + criação rápida.
class ClientInteractionsPanel extends StatefulWidget {
  final String clientId;

  const ClientInteractionsPanel({super.key, required this.clientId});

  @override
  State<ClientInteractionsPanel> createState() =>
      _ClientInteractionsPanelState();
}

class _ClientInteractionsPanelState extends State<ClientInteractionsPanel> {
  final ClientService _clientService = ClientService.instance;
  List<ClientInteraction> _interactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInteractions();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  Future<void> _loadInteractions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response =
          await _clientService.getClientInteractions(widget.clientId);
      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          _interactions = List<ClientInteraction>.from(response.data!)
            ..sort((a, b) {
              final aTime = _safeDate(a.interactionAt ?? a.createdAt);
              final bTime = _safeDate(b.interactionAt ?? b.createdAt);
              return bTime.compareTo(aTime);
            });
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar interações';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro de conexão';
        _isLoading = false;
      });
    }
  }

  DateTime _safeDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> _showCreateInteractionModal() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreateInteractionSheet(
        clientId: widget.clientId,
      ),
    );

    if (result == true) {
      _loadInteractions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, accent, theme),
            const SizedBox(height: 14),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              _buildErrorState(context)
            else if (_interactions.isEmpty)
              _buildEmptyState(context)
            else
              _buildTimeline(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: accent.withValues(alpha: 0.10),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Icon(Icons.history_rounded, color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Linha do tempo',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _interactions.isEmpty
                    ? 'Acompanhe ligações, visitas e propostas registradas'
                    : '${_interactions.length} interação${_interactions.length == 1 ? '' : 'ões'} registrada${_interactions.length == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _showCreateInteractionModal,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text(
            'Nova',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.10),
        border: Border.all(
          color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.10),
            ),
            child: Icon(
              Icons.forum_outlined,
              size: 30,
              color: accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhuma interação registrada',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Comece registrando contatos, visitas e propostas para manter o histórico organizado.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showCreateInteractionModal,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Registrar interação'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.status.error.withValues(alpha: 0.06),
        border: Border.all(
          color: AppColors.status.error.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 36,
            color: AppColors.status.error,
          ),
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadInteractions,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _interactions.length,
      itemBuilder: (context, index) {
        final isLast = index == _interactions.length - 1;
        return _buildTimelineItem(
          context,
          _interactions[index],
          isLast: isLast,
        );
      },
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    ClientInteraction interaction, {
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Linha vertical do timeline
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.30),
                    width: 4,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color:
                        accent.withValues(alpha: 0.20),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Conteúdo do card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: ThemeHelpers.cardBackgroundColor(context),
                  border: Border.all(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            interaction.title?.trim().isNotEmpty == true
                                ? interaction.title!
                                : 'Interação registrada',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              height: 1.2,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          tooltip: 'Excluir',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minHeight: 24,
                            minWidth: 24,
                          ),
                          onPressed: () => _confirmDelete(interaction),
                        ),
                      ],
                    ),
                    if (interaction.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        interaction.notes,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _metaChip(
                          context,
                          icon: Icons.access_time,
                          label: _formatDateTime(
                            interaction.interactionAt ?? interaction.createdAt,
                          ),
                        ),
                        if (interaction.createdBy != null)
                          _metaChip(
                            context,
                            icon: Icons.person_outline,
                            label: interaction.createdBy!.name,
                          ),
                      ],
                    ),
                    if (interaction.attachments.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: interaction.attachments.map((a) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color:
                                  accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_file,
                                    size: 13, color: accent),
                                const SizedBox(width: 5),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 160),
                                  child: Text(
                                    a.name ?? 'Anexo',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: muted),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String dateTime) {
    try {
      final dt = DateTime.parse(dateTime).toLocal();
      return DateFormat("dd 'de' MMM, HH:mm", 'pt_BR').format(dt);
    } catch (_) {
      return dateTime;
    }
  }

  Future<void> _confirmDelete(ClientInteraction interaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.status.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Excluir interação?')),
          ],
        ),
        content: const Text(
          'Esta ação remove permanentemente a interação. Não será possível desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final response = await _clientService.deleteClientInteraction(
      widget.clientId,
      interaction.id,
    );
    if (!mounted) return;

    if (response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Interação excluída com sucesso!'),
          backgroundColor: AppColors.status.success,
        ),
      );
      _loadInteractions();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Erro ao excluir interação'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }
}

class _CreateInteractionSheet extends StatefulWidget {
  const _CreateInteractionSheet({required this.clientId});

  final String clientId;

  @override
  State<_CreateInteractionSheet> createState() =>
      _CreateInteractionSheetState();
}

class _CreateInteractionSheetState extends State<_CreateInteractionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _interactionAt = DateTime.now();
  String? _suggestedTitle;
  bool _isSaving = false;

  static const _suggestions = [
    {'icon': Icons.call_outlined, 'label': 'Ligação telefônica'},
    {'icon': Icons.chat_outlined, 'label': 'Mensagem WhatsApp'},
    {'icon': Icons.alternate_email_rounded, 'label': 'Email enviado'},
    {'icon': Icons.handshake_outlined, 'label': 'Visita / reunião'},
    {'icon': Icons.request_quote_outlined, 'label': 'Proposta enviada'},
    {'icon': Icons.house_outlined, 'label': 'Visita ao imóvel'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _interactionAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      locale: const Locale('pt', 'BR'),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_interactionAt),
    );
    if (pickedTime == null) return;
    setState(() {
      _interactionAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final response = await ClientService.instance.createClientInteraction(
        widget.clientId,
        notes: _notesController.text.trim(),
        title: _titleController.text.trim().isEmpty
            ? _suggestedTitle
            : _titleController.text.trim(),
        interactionAt: _interactionAt.toUtc().toIso8601String(),
      );

      if (!mounted) return;
      if (response.success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Interação registrada!'),
            backgroundColor: AppColors.status.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao registrar interação'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: ${e.toString()}'),
          backgroundColor: AppColors.status.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final dateLabel = DateFormat("EEEE, dd MMM yyyy 'às' HH:mm", 'pt_BR')
        .format(_interactionAt);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.backgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [accent, const Color(0xFF7C3AED)],
                          ),
                        ),
                        child: const Icon(
                          Icons.add_comment_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Registrar interação',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Sugestões rápidas',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestions.map((s) {
                      final label = s['label'] as String;
                      final icon = s['icon'] as IconData;
                      final selected = _suggestedTitle == label;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _suggestedTitle = label;
                            if (_titleController.text.trim().isEmpty) {
                              _titleController.text = label;
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? accent
                                : ThemeHelpers.cardBackgroundColor(context),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: selected
                                  ? accent
                                  : ThemeHelpers.borderLightColor(context),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: 14,
                                color:
                                    selected ? Colors.white : accent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: selected
                                      ? Colors.white
                                      : ThemeHelpers.textColor(context),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Título (opcional)',
                      hintText: 'Ex: Conversa sobre financiamento',
                      prefixIcon: const Icon(Icons.title_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 5,
                    minLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Detalhes da interação *',
                      hintText:
                          'O que foi conversado? Próximos passos? Decisões…',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Descreva os detalhes da interação';
                      }
                      if (value.trim().length < 4) {
                        return 'Mínimo 4 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _isSaving ? null : _pickDateTime,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: ThemeHelpers.cardBackgroundColor(context),
                        border: Border.all(
                          color: ThemeHelpers.borderLightColor(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              color: accent.withValues(alpha: 0.12),
                            ),
                            child: Icon(
                              Icons.calendar_month_outlined,
                              color: accent,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Data e hora',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: ThemeHelpers.textSecondaryColor(
                                        context),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateLabel,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: ThemeHelpers.textColor(context),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.edit_calendar_outlined,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                            _isSaving ? 'Salvando…' : 'Registrar',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
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
      ),
    );
  }
}
