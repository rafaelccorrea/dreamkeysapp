import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../controllers/kanban_controller.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';

/// Opções de mídia / origem — mesma lista base do CRM web (`CreateTaskPage`).
const List<(String value, String label, IconData icon, Color? color)>
    _kLeadSources = <(String, String, IconData, Color?)>[
  ('WhatsApp', 'WhatsApp', Icons.chat_rounded, Color(0xFF25D366)),
  ('Site', 'Site', Icons.language_rounded, null),
  ('Landing Page', 'Landing Page', Icons.web_asset_rounded, null),
  ('Meta', 'Meta (Facebook/Instagram)', Icons.public_rounded, Color(0xFF1877F2)),
  ('Indicação', 'Indicação', Icons.group_rounded, null),
  (
    'Presencial Imobiliária',
    'Presencial Imobiliária',
    Icons.storefront_rounded,
    null,
  ),
  ('Google', 'Google', Icons.travel_explore_rounded, Color(0xFF4285F4)),
  ('Chaves na Mão', 'Chaves na Mão', Icons.vpn_key_rounded, null),
  ('ImóvelWeb', 'ImóvelWeb', Icons.apartment_rounded, null),
  ('ManyChat', 'ManyChat', Icons.forum_rounded, null),
  ('Telefone', 'Telefone', Icons.call_rounded, null),
  ('Placa', 'Placa', Icons.signpost_rounded, null),
  ('Outro', 'Outro', Icons.more_horiz_rounded, null),
];

const Map<KanbanPriority, ({Color fg, Color bg, String label})>
    _kPriorityPalette = {
  KanbanPriority.low: (fg: Color(0xFF10B981), bg: Color(0xFFECFDF5), label: 'Baixa'),
  KanbanPriority.medium: (fg: Color(0xFFF59E0B), bg: Color(0xFFFFFBEB), label: 'Média'),
  KanbanPriority.high: (fg: Color(0xFFEF4444), bg: Color(0xFFFEF2F2), label: 'Alta'),
  KanbanPriority.urgent:
      (fg: Color(0xFFDC2626), bg: Color(0xFFFEE2E2), label: 'Urgente'),
};

String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

bool _isValidEmail(String s) {
  final t = s.trim();
  if (t.isEmpty) return true;
  return RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(t);
}

double? _parseMoneyBr(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'[R$\s]'), '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    if (lastComma > lastDot) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    s = s.replaceAll(',', '.');
  }
  return double.tryParse(s);
}

String? _sourceForApi(String raw) {
  final t = _trimOrNull(raw);
  if (t == null) return null;
  if (t.toUpperCase() == 'PLACA') return 'Placa';
  return t;
}

String? _trimOrNull(String? s) {
  final t = s?.trim() ?? '';
  if (t.isEmpty) return null;
  return t;
}

String _initials(String s) {
  final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class _ContactRowEditors {
  _ContactRowEditors()
      : name = TextEditingController(),
        phone = TextEditingController(),
        email = TextEditingController(),
        jobTitle = TextEditingController(),
        birthDate = TextEditingController();

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController jobTitle;
  final TextEditingController birthDate;

  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    jobTitle.dispose();
    birthDate.dispose();
  }

  KanbanTaskContactInput toInput() {
    return KanbanTaskContactInput(
      name: name.text,
      phone: phone.text,
      email: email.text,
      jobTitle: jobTitle.text,
      birthDate: birthDate.text,
    );
  }
}

/// Página de criação de negociação — paridade com `CreateTaskPage` (web):
/// hero, secções com ícone, `FieldCard`s, `StagePicker` horizontal,
/// linhas de 2/4 colunas em ecrã largo e blocos colapsáveis.
class CreateTaskModal extends StatefulWidget {
  final String columnId;
  final String teamId;

  const CreateTaskModal({
    super.key,
    required this.columnId,
    required this.teamId,
  });

  @override
  State<CreateTaskModal> createState() => _CreateTaskModalState();
}

class _CreateTaskModalState extends State<CreateTaskModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _internalNotesController = TextEditingController();
  final _totalValueController = TextEditingController();
  final _campaignController = TextEditingController();
  final _metaCampaignIdController = TextEditingController();
  final _systemCampaignIdController = TextEditingController();

  final _clientSearchController = TextEditingController();
  final _propertySearchController = TextEditingController();

  final KanbanService _kanbanService = KanbanService.instance;

  KanbanPriority _selectedPriority = KanbanPriority.medium;
  DateTime? _dueDate;
  DateTime? _transferDate;
  String _selectedColumnId = '';
  String? _assigneeId;

  KanbanProjectLinkedClient? _pickedClient;
  KanbanProjectLinkedProperty? _pickedProperty;

  final List<KanbanProjectLinkedClient> _clientSuggestions = [];
  final List<KanbanProjectLinkedProperty> _propertySuggestions = [];

  Timer? _clientDebounce;
  Timer? _propertyDebounce;

  String _sourceDropdown = '';

  final List<_ContactRowEditors> _contactRows = [];
  bool _expandSource = false;
  bool _expandContacts = false;
  bool _expandInvolved = false;

  final Set<String> _involvedUserIds = {};

  List<KanbanUser> _memberUsers = [];
  bool _loadingMembers = false;

  bool _isLoading = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _selectedColumnId = widget.columnId;
    final n = DateTime.now();
    _dueDate = DateTime(n.year, n.month, n.day);
    _contactRows.add(_ContactRowEditors());
    _titleController.addListener(_rebuild);
    _descriptionController.addListener(_rebuild);
    _internalNotesController.addListener(_rebuild);
    _loadCurrentUserId().then((_) {
      if (!mounted) return;
      setState(() => _assigneeId = _currentUserId);
      _loadProjectMembers();
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _internalNotesController.dispose();
    _totalValueController.dispose();
    _campaignController.dispose();
    _metaCampaignIdController.dispose();
    _systemCampaignIdController.dispose();
    _clientSearchController.dispose();
    _propertySearchController.dispose();
    _clientDebounce?.cancel();
    _propertyDebounce?.cancel();
    for (final r in _contactRows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        final payload = JwtUtils.decodeToken(token);
        if (payload != null) {
          if (!mounted) return;
          setState(() {
            _currentUserId =
                payload['sub']?.toString() ?? payload['userId']?.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CREATE_TASK_PAGE] userId: $e');
    }
  }

  Future<void> _loadProjectMembers() async {
    final controller = context.read<KanbanController>();
    final projectId = controller.projectId;
    if (projectId == null || projectId.isEmpty) return;

    KanbanProject? project;
    for (final p in controller.projects) {
      if (p.id == projectId) {
        project = p;
        break;
      }
    }

    if (project?.isPersonal == true) {
      if (_currentUserId != null && mounted) {
        setState(() {
          _memberUsers = [
            KanbanUser(id: _currentUserId!, name: 'Eu', email: ''),
          ];
          _assigneeId ??= _currentUserId;
        });
      }
      return;
    }

    setState(() => _loadingMembers = true);
    try {
      final response = await _kanbanService.getProjectMembers(projectId);
      if (!mounted) return;
      if (response.success && response.data != null) {
        final users = response.data!.map((m) => m.user).toList();
        setState(() {
          _memberUsers = users;
          _loadingMembers = false;
          final aid = _assigneeId ?? _currentUserId;
          if (users.isEmpty) {
            _assigneeId = aid;
          } else if (aid == null || !users.any((u) => u.id == aid)) {
            final curIn = _currentUserId != null &&
                users.any((u) => u.id == _currentUserId);
            _assigneeId = curIn ? _currentUserId : users.first.id;
          } else {
            _assigneeId = aid;
          }
        });
      } else {
        setState(() {
          _loadingMembers = false;
          if (_currentUserId != null) {
            _memberUsers = [
              KanbanUser(id: _currentUserId!, name: 'Eu', email: ''),
            ];
            _assigneeId ??= _currentUserId;
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMembers = false;
        if (_currentUserId != null) {
          _memberUsers = [
            KanbanUser(id: _currentUserId!, name: 'Eu', email: ''),
          ];
          _assigneeId ??= _currentUserId;
        }
      });
    }
  }

  void _scheduleClientSearch(String query) {
    _clientDebounce?.cancel();
    final controller = context.read<KanbanController>();
    final pid = controller.projectId;
    if (pid == null || pid.isEmpty) return;

    _clientDebounce = Timer(const Duration(milliseconds: 380), () async {
      final q = query.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _clientSuggestions.clear());
        return;
      }
      final resp = await _kanbanService.getProjectClients(pid, search: q);
      if (!mounted) return;
      if (resp.success && resp.data != null) {
        setState(() {
          _clientSuggestions
            ..clear()
            ..addAll(resp.data!);
        });
      }
    });
  }

  void _schedulePropertySearch(String query) {
    _propertyDebounce?.cancel();
    final controller = context.read<KanbanController>();
    final pid = controller.projectId;
    if (pid == null || pid.isEmpty) return;

    _propertyDebounce = Timer(const Duration(milliseconds: 380), () async {
      final q = query.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _propertySuggestions.clear());
        return;
      }
      final resp = await _kanbanService.getProjectProperties(pid, search: q);
      if (!mounted) return;
      if (resp.success && resp.data != null) {
        setState(() {
          _propertySuggestions
            ..clear()
            ..addAll(resp.data!);
        });
      }
    });
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? first,
      firstDate: first,
      lastDate: first.add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _dueDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _pickTransferDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _transferDate ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _transferDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    if (title.length < 3) {
      _showError('Título deve ter pelo menos 3 caracteres');
      return;
    }

    for (var i = 0; i < _contactRows.length; i++) {
      final row = _contactRows[i];
      final em = row.email.text.trim();
      if (em.isNotEmpty && !_isValidEmail(em)) {
        _showError('E-mail inválido no contato ${i + 1}');
        return;
      }
      final ph = _digitsOnly(row.phone.text);
      if (ph.isNotEmpty && (ph.length < 10 || ph.length > 11)) {
        _showError('Telefone do contato ${i + 1}: use 10 ou 11 dígitos');
        return;
      }
    }

    if (_selectedColumnId.isEmpty) {
      _showError('Selecione a etapa do funil');
      return;
    }

    if (_dueDate != null) {
      final today = DateTime(DateTime.now().year, DateTime.now().month,
          DateTime.now().day);
      final d = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day);
      if (d.isBefore(today)) {
        _showError('Data de vencimento não pode ser anterior a hoje');
        return;
      }
    }

    setState(() => _isLoading = true);

    final controller = context.read<KanbanController>();
    final contacts = _contactRows.map((r) => r.toInput()).toList();

    final dto = CreateTaskDto(
      title: title,
      description: _trimOrNull(_descriptionController.text),
      columnId: _selectedColumnId,
      priority: _selectedPriority,
      dueDate: _dueDate,
      assignedToId: _assigneeId,
      projectId: controller.projectId,
      totalValue: _parseMoneyBr(_totalValueController.text),
      clientId: _pickedClient?.id,
      propertyId: _pickedProperty?.id,
      source: _sourceForApi(_sourceDropdown),
      campaign: _trimOrNull(_campaignController.text),
      metaCampaignId: _trimOrNull(_metaCampaignIdController.text),
      systemCampaignId: _trimOrNull(_systemCampaignIdController.text),
      internalNotes: _trimOrNull(_internalNotesController.text),
      contacts: contacts,
    );

    try {
      final task = await controller.createTask(dto);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (task == null) {
        _showError(controller.error ?? 'Erro ao criar negociação');
        return;
      }

      final assignee = _assigneeId;
      final creator = _currentUserId;
      final involved = <String>{};
      for (final id in _involvedUserIds) {
        if (id.isNotEmpty && id != assignee) involved.add(id);
      }
      if (creator != null && creator.isNotEmpty) involved.add(creator);

      if (involved.isNotEmpty) {
        final invResp =
            await _kanbanService.setInvolvedUsers(task.id, involved.toList());
        if (!invResp.success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                invResp.message ??
                    'Negociação criada — falha ao salvar pessoas envolvidas',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Negociação criada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Erro: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  List<KanbanColumn> _realColumns(KanbanController c) {
    return c.displayColumns
        .where((col) => !KanbanSyntheticColumns.isSyntheticId(col.id))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<KanbanController>();
    final columns = _realColumns(controller);
    final accent = _accent(context);

    if (columns.isNotEmpty &&
        !columns.any((c) => c.id == _selectedColumnId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedColumnId = columns.first.id);
      });
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Hero(
              title: 'Nova negociação',
              subtitle: controller.team?.name == null
                  ? 'Crie um novo card no funil'
                  : 'Em ${controller.team!.name}',
              onClose: () => Navigator.of(context).pop(),
              accent: accent,
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 720;
                    return ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        wide ? 32 : 16,
                        20,
                        wide ? 32 : 16,
                        140,
                      ),
                      children: [
                        if (columns.isNotEmpty)
                          _PageSection(
                            icon: Icons.view_column_rounded,
                            title: 'Etapa do funil',
                            required: true,
                            child: _StagePicker(
                              columns: columns,
                              selectedId: _selectedColumnId,
                              onPick: (id) =>
                                  setState(() => _selectedColumnId = id),
                              accent: accent,
                            ),
                          ),
                        _PageSection(
                          icon: Icons.signpost_rounded,
                          title: 'Dados básicos',
                          child: _basicsBody(wide),
                        ),
                        _PageSection(
                          icon: Icons.group_rounded,
                          title: 'Responsável e equipe',
                          child: _ownerProjectBody(wide),
                        ),
                        _PageSection(
                          icon: Icons.person_outline_rounded,
                          title: 'Cliente e imóvel',
                          subtitle: 'Vincule a pessoa e o imóvel da negociação',
                          child: _entityBody(wide),
                        ),
                        _CollapsibleSection(
                          icon: Icons.campaign_rounded,
                          title: 'Mídia de origem',
                          badge: 'Opcional',
                          expanded: _expandSource,
                          onToggle: () =>
                              setState(() => _expandSource = !_expandSource),
                          child: _sourceBody(wide),
                        ),
                        _CollapsibleSection(
                          icon: Icons.contacts_rounded,
                          title: 'Contatos',
                          badge: _contactRows.where((r) => r.toInput().hasAny).isEmpty
                              ? 'Opcional'
                              : '${_contactRows.where((r) => r.toInput().hasAny).length} preenchido(s)',
                          expanded: _expandContacts,
                          onToggle: () => setState(
                            () => _expandContacts = !_expandContacts,
                          ),
                          child: _contactsBody(wide),
                        ),
                        _CollapsibleSection(
                          icon: Icons.diversity_3_rounded,
                          title: 'Pessoas envolvidas',
                          badge: _involvedUserIds.isEmpty
                              ? 'Opcional'
                              : '${_involvedUserIds.length} selecionada(s)',
                          expanded: _expandInvolved,
                          onToggle: () => setState(
                            () => _expandInvolved = !_expandInvolved,
                          ),
                          child: _involvedBody(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              top: BorderSide(color: ThemeHelpers.borderColor(context)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              TextButton(
                onPressed:
                    _isLoading ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const Spacer(),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              FilledButton.icon(
                onPressed: _isLoading ? null : _save,
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Criar negociação'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- BASICS ----------

  Widget _basicsBody(bool wide) {
    final desc = _FieldCard(
      icon: Icons.description_outlined,
      iconColor: const Color(0xFF6366F1),
      label: 'Descrição',
      sublabel: 'Visível para todos os membros do funil',
      meta: '${_descriptionController.text.length}/300',
      child: TextFormField(
        controller: _descriptionController,
        maxLines: 4,
        maxLength: 300,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        decoration: _flatDecoration(
          hint: 'Descreva o contexto desta negociação',
        ).copyWith(counterText: ''),
        textCapitalization: TextCapitalization.sentences,
        validator: (v) {
          if ((v ?? '').length > 300) return 'Máx. 300 caracteres';
          return null;
        },
      ),
    );

    final notes = _FieldCard(
      icon: Icons.lock_outline_rounded,
      iconColor: const Color(0xFFF59E0B),
      label: 'Observação interna',
      sublabel: 'Apenas equipe — não exposta ao cliente',
      meta: '${_internalNotesController.text.length}/2000',
      child: TextFormField(
        controller: _internalNotesController,
        maxLines: 4,
        maxLength: 2000,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        decoration: _flatDecoration(
          hint: 'Ex.: aceita permuta, forma de pagamento, financiamento',
        ).copyWith(counterText: ''),
      ),
    );

    final priorityCard = _FieldCard(
      icon: Icons.flag_rounded,
      iconColor: _kPriorityPalette[_selectedPriority]!.fg,
      label: 'Prioridade',
      sublabel: _kPriorityPalette[_selectedPriority]!.label,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: KanbanPriority.values.map((p) {
          final pal = _kPriorityPalette[p]!;
          final selected = p == _selectedPriority;
          return ChoiceChip(
            avatar: CircleAvatar(
              radius: 6,
              backgroundColor: pal.fg,
            ),
            label: Text(pal.label),
            selected: selected,
            onSelected: (_) => setState(() => _selectedPriority = p),
            selectedColor: pal.fg.withValues(alpha: 0.18),
            side: BorderSide(
              color: selected
                  ? pal.fg
                  : ThemeHelpers.borderColor(context),
            ),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? pal.fg : ThemeHelpers.textColor(context),
            ),
          );
        }).toList(),
      ),
    );

    final dueCard = _FieldCard(
      icon: Icons.calendar_today_rounded,
      iconColor: const Color(0xFF3B82F6),
      label: 'Vencimento',
      sublabel: _dueDate == null
          ? 'Opcional'
          : _shortDate(_dueDate!),
      child: _DateButton(
        value: _dueDate,
        onTap: _pickDueDate,
        onClear: () => setState(() => _dueDate = null),
        placeholder: 'Selecionar data',
      ),
    );

    final transferCard = _FieldCard(
      icon: Icons.swap_horiz_rounded,
      iconColor: const Color(0xFF8B5CF6),
      label: 'Transferência',
      sublabel: _transferDate == null
          ? 'Opcional'
          : _shortDate(_transferDate!),
      child: _DateButton(
        value: _transferDate,
        onTap: _pickTransferDate,
        onClear: () => setState(() => _transferDate = null),
        placeholder: 'Selecionar data',
      ),
    );

    final valueCard = _FieldCard(
      icon: Icons.payments_rounded,
      iconColor: const Color(0xFF10B981),
      label: 'Valor total',
      sublabel: _totalValueController.text.isEmpty
          ? 'R\$ 0,00'
          : 'R\$ ${_totalValueController.text}',
      child: TextFormField(
        controller: _totalValueController,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d\.,R$\s]')),
        ],
        decoration: _flatDecoration(hint: 'Ex.: 350000 ou 1.234,56'),
        onChanged: (_) => setState(() {}),
      ),
    );

    final titleCard = _FieldCard(
      icon: Icons.title_rounded,
      iconColor: const Color(0xFF6366F1),
      label: 'Título',
      required: true,
      sublabel: 'Como você vai identificar esta negociação no quadro',
      meta: '${_titleController.text.length}/200',
      child: TextFormField(
        controller: _titleController,
        maxLength: 200,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        textCapitalization: TextCapitalization.sentences,
        decoration: _flatDecoration(
          hint: 'Ex.: Apto 3 dorms — Centro / Família Silva',
        ).copyWith(counterText: ''),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Título é obrigatório';
          if (v.trim().length < 3) return 'Mínimo 3 caracteres';
          return null;
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titleCard,
        const SizedBox(height: 12),
        wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: desc),
                  const SizedBox(width: 12),
                  Expanded(child: notes),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [desc, const SizedBox(height: 12), notes],
              ),
        const SizedBox(height: 12),
        _gridQuad(
          wide: wide,
          children: [priorityCard, dueCard, transferCard, valueCard],
        ),
      ],
    );
  }

  Widget _gridQuad({required bool wide, required List<Widget> children}) {
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i < children.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 10),
            Expanded(child: children[1]),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[2]),
            const SizedBox(width: 10),
            Expanded(child: children[3]),
          ],
        ),
      ],
    );
  }

  // ---------- OWNER & PROJECT ----------

  Widget _ownerProjectBody(bool wide) {
    final controller = context.read<KanbanController>();
    final ownerCard = _FieldCard(
      icon: Icons.person_pin_rounded,
      iconColor: _accent(context),
      label: 'Responsável',
      sublabel: 'Quem vai cuidar deste card',
      child: _loadingMembers
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : DropdownButtonFormField<String>(
              initialValue: _assigneeId,
              decoration: _flatDecoration(),
              items: _memberUsers
                  .map(
                    (u) => DropdownMenuItem(
                      value: u.id,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor:
                                _accent(context).withValues(alpha: 0.18),
                            child: Text(
                              _initials(u.name.isEmpty ? u.email : u.name),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _accent(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              u.name.isNotEmpty ? u.name : u.email,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _assigneeId = v;
                  if (v != null) _involvedUserIds.remove(v);
                });
              },
            ),
    );

    String projectName = '—';
    for (final p in controller.projects) {
      if (p.id == controller.projectId) {
        projectName = p.name;
        break;
      }
    }

    final projectCard = _FieldCard(
      icon: Icons.signpost_outlined,
      iconColor: const Color(0xFF6366F1),
      label: 'Funil',
      sublabel: 'Definido pelo seletor de funil',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: ThemeHelpers.cardBackgroundColor(context),
          border: Border.all(color: ThemeHelpers.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 18, color: ThemeHelpers.textSecondaryColor(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                projectName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: _accent(context).withValues(alpha: 0.14),
              ),
              child: Text(
                'FIXO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _accent(context),
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: ownerCard),
          const SizedBox(width: 12),
          Expanded(child: projectCard),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [ownerCard, const SizedBox(height: 12), projectCard],
    );
  }

  // ---------- ENTITY (Cliente / Imóvel) ----------

  Widget _entityBody(bool wide) {
    final clientCard = _FieldCard(
      icon: Icons.person_rounded,
      iconColor: const Color(0xFF8B5CF6),
      label: 'Cliente',
      sublabel: 'Pessoa relacionada à negociação (opcional)',
      child: _pickedClient != null
          ? _entityPreview(
              icon: Icons.person_rounded,
              accent: const Color(0xFF8B5CF6),
              title: _pickedClient!.name,
              subtitle: _pickedClient!.phone ?? _pickedClient!.email ?? '',
              onClear: () => setState(() {
                _pickedClient = null;
                _clientSearchController.clear();
                _clientSuggestions.clear();
              }),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _entityEmpty(
                  icon: Icons.person_outline_rounded,
                  text: 'Nenhum cliente vinculado — busque abaixo (opcional).',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _clientSearchController,
                  decoration: _flatDecoration(
                    hint: 'Digite ao menos 2 letras…',
                    prefix: Icons.person_search_rounded,
                  ),
                  onChanged: _scheduleClientSearch,
                ),
                if (_clientSuggestions.isNotEmpty)
                  _suggestionList(
                    items: _clientSuggestions
                        .map(
                          (c) => _SuggestItem(
                            title: c.name,
                            subtitle: c.phone ?? c.email ?? '',
                            onTap: () => setState(() {
                              _pickedClient = c;
                              _clientSuggestions.clear();
                              _clientSearchController.clear();
                            }),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
    );

    final propertyCard = _FieldCard(
      icon: Icons.home_rounded,
      iconColor: const Color(0xFF10B981),
      label: 'Imóvel',
      sublabel: 'Imóvel relacionado à negociação (opcional)',
      child: _pickedProperty != null
          ? _entityPreview(
              icon: Icons.home_rounded,
              accent: const Color(0xFF10B981),
              title: _pickedProperty!.title,
              subtitle: [
                if (_pickedProperty!.code != null) '#${_pickedProperty!.code}',
                if (_pickedProperty!.city != null) _pickedProperty!.city,
              ].whereType<String>().join(' · '),
              onClear: () => setState(() {
                _pickedProperty = null;
                _propertySearchController.clear();
                _propertySuggestions.clear();
              }),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _entityEmpty(
                  icon: Icons.home_outlined,
                  text: 'Nenhum imóvel vinculado — busque abaixo (opcional).',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _propertySearchController,
                  decoration: _flatDecoration(
                    hint: 'Digite ao menos 2 letras…',
                    prefix: Icons.home_work_outlined,
                  ),
                  onChanged: _schedulePropertySearch,
                ),
                if (_propertySuggestions.isNotEmpty)
                  _suggestionList(
                    items: _propertySuggestions
                        .map(
                          (p) => _SuggestItem(
                            title: p.title,
                            subtitle: [
                              if (p.code != null) '#${p.code}',
                              if (p.city != null) p.city,
                            ].whereType<String>().join(' · '),
                            onTap: () => setState(() {
                              _pickedProperty = p;
                              _propertySuggestions.clear();
                              _propertySearchController.clear();
                            }),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: clientCard),
          const SizedBox(width: 12),
          Expanded(child: propertyCard),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [clientCard, const SizedBox(height: 12), propertyCard],
    );
  }

  // ---------- SOURCE ----------

  Widget _sourceBody(bool wide) {
    final sourceField = _FieldCard(
      icon: Icons.public_rounded,
      iconColor: const Color(0xFF0EA5E9),
      label: 'Mídia de origem',
      sublabel: 'Onde o lead surgiu',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _kLeadSources.map((s) {
          final selected = _sourceDropdown == s.$1;
          final fg = s.$4 ?? _accent(context);
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              setState(() {
                _sourceDropdown = selected ? '' : s.$1;
                if (s.$1 != 'Meta') _metaCampaignIdController.clear();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: selected
                    ? fg.withValues(alpha: 0.16)
                    : ThemeHelpers.cardBackgroundColor(context),
                border: Border.all(
                  color: selected
                      ? fg.withValues(alpha: 0.7)
                      : ThemeHelpers.borderColor(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.$3, size: 16, color: selected ? fg : ThemeHelpers.textSecondaryColor(context)),
                  const SizedBox(width: 6),
                  Text(
                    s.$2,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? fg
                          : ThemeHelpers.textColor(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );

    final campaignField = _FieldCard(
      icon: Icons.campaign_outlined,
      iconColor: const Color(0xFF6366F1),
      label: 'Campanha',
      sublabel: 'Texto livre do nome',
      child: TextFormField(
        controller: _campaignController,
        decoration: _flatDecoration(hint: 'Ex.: Lançamento Vila Madalena'),
      ),
    );

    final metaField = _FieldCard(
      icon: Icons.facebook_rounded,
      iconColor: const Color(0xFF1877F2),
      label: 'ID campanha Meta',
      sublabel: 'Quando o lead vem do Meta',
      child: TextFormField(
        controller: _metaCampaignIdController,
        decoration: _flatDecoration(hint: '12345…'),
      ),
    );

    final systemField = _FieldCard(
      icon: Icons.qr_code_rounded,
      iconColor: const Color(0xFF0F766E),
      label: 'ID campanha do sistema',
      sublabel: 'UUID, opcional',
      child: TextFormField(
        controller: _systemCampaignIdController,
        decoration: _flatDecoration(hint: '00000000-…'),
      ),
    );

    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sourceField,
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: campaignField),
              const SizedBox(width: 12),
              Expanded(child: metaField),
              const SizedBox(width: 12),
              Expanded(child: systemField),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sourceField,
        const SizedBox(height: 12),
        campaignField,
        const SizedBox(height: 12),
        metaField,
        const SizedBox(height: 12),
        systemField,
      ],
    );
  }

  // ---------- CONTACTS ----------

  Widget _contactsBody(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate(_contactRows.length, (i) {
          final row = _contactRows[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: ThemeHelpers.cardBackgroundColor(context),
              border: Border.all(color: ThemeHelpers.borderColor(context)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          _accent(context).withValues(alpha: 0.16),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _accent(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Contato ${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    if (_contactRows.length > 1)
                      IconButton(
                        tooltip: 'Remover',
                        icon: Icon(Icons.delete_outline_rounded,
                            color: Theme.of(context).colorScheme.error),
                        onPressed: () => setState(() {
                          row.dispose();
                          _contactRows.removeAt(i);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: row.name,
                              decoration: _flatDecoration(
                                label: 'Nome',
                                hint: 'Ex.: Paulo C.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: row.phone,
                              keyboardType: TextInputType.phone,
                              decoration: _flatDecoration(
                                label: 'Telefone',
                                hint: '(00) 00000-0000',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: row.email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _flatDecoration(
                                label: 'E-mail',
                                hint: 'email@exemplo.com',
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: row.name,
                            decoration:
                                _flatDecoration(label: 'Nome'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: row.phone,
                            keyboardType: TextInputType.phone,
                            decoration:
                                _flatDecoration(label: 'Telefone'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: row.email,
                            keyboardType: TextInputType.emailAddress,
                            decoration:
                                _flatDecoration(label: 'E-mail'),
                          ),
                        ],
                      ),
                const SizedBox(height: 8),
                wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: row.jobTitle,
                              decoration:
                                  _flatDecoration(label: 'Cargo'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: row.birthDate,
                              decoration: _flatDecoration(
                                label: 'Nascimento (AAAA-MM-DD)',
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: row.jobTitle,
                            decoration:
                                _flatDecoration(label: 'Cargo'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: row.birthDate,
                            decoration: _flatDecoration(
                              label: 'Nascimento (AAAA-MM-DD)',
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _contactRows.add(_ContactRowEditors())),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Adicionar contato'),
          ),
        ),
      ],
    );
  }

  // ---------- INVOLVED ----------

  Widget _involvedBody() {
    if (_loadingMembers) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_memberUsers.length <= 1) {
      return _entityEmpty(
        icon: Icons.diversity_3_outlined,
        text: 'Sem mais membros disponíveis neste funil.',
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _memberUsers
          .where((u) => u.id != _assigneeId)
          .map((u) {
        final on = _involvedUserIds.contains(u.id);
        return FilterChip(
          avatar: CircleAvatar(
            radius: 12,
            backgroundColor: _accent(context).withValues(alpha: 0.18),
            child: Text(
              _initials(u.name.isEmpty ? u.email : u.name),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _accent(context),
              ),
            ),
          ),
          label: Text(u.name.isNotEmpty ? u.name : u.email),
          selected: on,
          onSelected: (sel) {
            setState(() {
              if (sel) {
                _involvedUserIds.add(u.id);
              } else {
                _involvedUserIds.remove(u.id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  // ---------- HELPERS ----------

  String _shortDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  Widget _entityPreview({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: accent.withValues(alpha: 0.22),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remover',
            icon: const Icon(Icons.close_rounded),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  Widget _entityEmpty({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 18, color: ThemeHelpers.textSecondaryColor(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionList({required List<_SuggestItem> items}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
        ),
        itemBuilder: (ctx, i) {
          final s = items[i];
          return ListTile(
            dense: true,
            title: Text(s.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: s.subtitle.isEmpty ? null : Text(s.subtitle),
            trailing:
                const Icon(Icons.arrow_forward_rounded, size: 18),
            onTap: s.onTap,
          );
        },
      ),
    );
  }

  InputDecoration _flatDecoration({
    String? label,
    String? hint,
    IconData? prefix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix != null ? Icon(prefix, size: 20) : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ThemeHelpers.borderColor(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ThemeHelpers.borderColor(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _accent(context), width: 1.4),
      ),
      filled: true,
      fillColor: Theme.of(context).scaffoldBackgroundColor,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

class _SuggestItem {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  _SuggestItem({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

// =====================================================================
// HERO + SEÇÕES + FIELDCARD + STAGE PICKER + DATE BUTTON
// =====================================================================

class _Hero extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final Color accent;

  const _Hero({
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cool = const Color(0xFF0891B2);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  accent.withValues(alpha: 0.22),
                  cool.withValues(alpha: 0.12),
                ]
              : [
                  accent.withValues(alpha: 0.10),
                  cool.withValues(alpha: 0.06),
                ],
        ),
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Fechar',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onClose,
          ),
          const SizedBox(width: 4),
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent, cool],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KANBAN · NEGOCIAÇÃO',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool required;
  final Widget child;

  const _PageSection({
    required this.icon,
    required this.title,
    this.subtitle,
    this.required = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: accent.withValues(alpha: 0.14),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: ThemeHelpers.textColor(context),
                        ),
                        children: [
                          TextSpan(text: title),
                          if (required)
                            const TextSpan(
                              text: ' *',
                              style: TextStyle(color: Color(0xFFEF4444)),
                            ),
                        ],
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? badge;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _CollapsibleSection({
    required this.icon,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onToggle,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: accent.withValues(alpha: 0.14),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: accent.withValues(alpha: 0.12),
                      ),
                      child: Text(
                        badge!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? sublabel;
  final String? meta;
  final bool required;
  final Widget child;

  const _FieldCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.child,
    this.sublabel,
    this.meta,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Color.alphaBlend(
          iconColor.withValues(alpha: isDark ? 0.05 : 0.04),
          ThemeHelpers.cardBackgroundColor(context),
        ),
        border: Border.all(
          color: iconColor.withValues(alpha: isDark ? 0.30 : 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: iconColor.withValues(alpha: 0.18),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: ThemeHelpers.textColor(context),
                        ),
                        children: [
                          TextSpan(text: label),
                          if (required)
                            const TextSpan(
                              text: ' *',
                              style: TextStyle(color: Color(0xFFEF4444)),
                            ),
                        ],
                      ),
                    ),
                    if (sublabel != null)
                      Text(
                        sublabel!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                  ],
                ),
              ),
              if (meta != null)
                Text(
                  meta!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _StagePicker extends StatelessWidget {
  final List<KanbanColumn> columns;
  final String selectedId;
  final ValueChanged<String> onPick;
  final Color accent;

  const _StagePicker({
    required this.columns,
    required this.selectedId,
    required this.onPick,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final total = columns.length;
    final selectedIdx = columns.indexWhere((c) => c.id == selectedId);
    final selected = selectedIdx >= 0 ? columns[selectedIdx] : null;

    Color stageColor(KanbanColumn col) {
      final raw = col.color;
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          return Color(int.parse(raw.replaceFirst('#', '0xFF')));
        } catch (_) {}
      }
      return accent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Onde a negociação entra no funil. Pode mover o card depois.',
                style: TextStyle(
                  fontSize: 12,
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: (selected != null
                        ? stageColor(selected)
                        : accent)
                    .withValues(alpha: 0.16),
              ),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: (selected != null ? stageColor(selected) : accent),
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: selectedIdx >= 0
                          ? (selectedIdx + 1).toString().padLeft(2, '0')
                          : '—',
                    ),
                    TextSpan(
                      text: '  de  ${total.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: columns.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final c = columns[i];
              final col = stageColor(c);
              final selected = c.id == selectedId;
              return _StageItem(
                index: i,
                total: total,
                title: c.title,
                color: col,
                selected: selected,
                onTap: () => onPick(c.id),
              );
            },
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: stageColor(selected).withValues(alpha: 0.10),
              border: Border.all(
                color: stageColor(selected).withValues(alpha: 0.42),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: stageColor(selected), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeHelpers.textColor(context),
                      ),
                      children: [
                        TextSpan(
                          text: selected.title,
                          style:
                              const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(text: '  ·  '),
                        TextSpan(
                          text: selectedIdx == 0
                              ? 'Início do funil'
                              : selectedIdx == total - 1
                                  ? 'Final do funil'
                                  : 'Etapa ${selectedIdx + 1} de $total',
                          style: TextStyle(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w600,
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
      ],
    );
  }
}

class _StageItem extends StatelessWidget {
  final int index;
  final int total;
  final String title;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StageItem({
    required this.index,
    required this.total,
    required this.title,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = index == 0
        ? 'Início'
        : index == total - 1
            ? 'Final'
            : 'Etapa ${index + 1}';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? color.withValues(alpha: 0.16)
              : ThemeHelpers.cardBackgroundColor(context),
          border: Border.all(
            color: selected
                ? color
                : ThemeHelpers.borderColor(context),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: selected
                        ? color
                        : color.withValues(alpha: 0.18),
                  ),
                  child: Text(
                    (index + 1).toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : color,
                    ),
                  ),
                ),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: color, size: 18),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? color : ThemeHelpers.textColor(context),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textSecondaryColor(context),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final String placeholder;

  const _DateButton({
    required this.value,
    required this.onTap,
    required this.onClear,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final t = value != null
        ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
        : placeholder;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border.all(color: ThemeHelpers.borderColor(context)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: value != null
                      ? ThemeHelpers.textColor(context)
                      : ThemeHelpers.textSecondaryColor(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (value != null)
              IconButton(
                tooltip: 'Limpar',
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClear,
              )
            else
              const Icon(Icons.calendar_month_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
