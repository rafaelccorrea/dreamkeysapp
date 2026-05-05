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
const List<(String, String)> _kLeadSources = <(String, String)>[
  ('', 'Selecione a mídia'),
  ('WhatsApp', 'WhatsApp'),
  ('Site', 'Site'),
  ('Landing Page', 'Landing Page'),
  ('Meta', 'Meta (Facebook/Instagram)'),
  ('Indicação', 'Indicação'),
  ('Presencial Imobiliária', 'Presencial Imobiliária'),
  ('Google', 'Google'),
  ('Chaves na Mão', 'Chaves na Mão'),
  ('ImóvelWeb', 'ImóvelWeb'),
  ('ManyChat', 'ManyChat'),
  ('Telefone', 'Telefone'),
  ('Placa', 'Placa'),
  ('Outro', 'Outro'),
];

String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

bool _isValidEmail(String s) {
  final t = s.trim();
  if (t.isEmpty) return true;
  return RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(t);
}

/// Aceita valores como "350000", "1.234,56", "1234.56".
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

/// Modal para criar negociação (card) — paridade de campos com o web (`CreateTaskPage`).
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

  KanbanPriority? _selectedPriority = KanbanPriority.medium;
  DateTime? _dueDate;
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

  final Set<String> _involvedUserIds = {};

  List<KanbanUser> _memberUsers = [];
  bool _loadingMembers = false;

  bool _isLoading = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _selectedColumnId = widget.columnId;
    _dueDate = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    _contactRows.add(_ContactRowEditors());
    _titleController.addListener(() {
      if (mounted) setState(() {});
    });
    _descriptionController.addListener(() {
      if (mounted) setState(() {});
    });
    _internalNotesController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadCurrentUserId().then((_) {
      if (mounted) {
        setState(() {
          _assigneeId = _currentUserId;
        });
        _loadProjectMembers();
      }
    });
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
          setState(() {
            _currentUserId =
                payload['sub']?.toString() ?? payload['userId']?.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CREATE_TASK_MODAL] Erro ao obter userId: $e');
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
            KanbanUser(
              id: _currentUserId!,
              name: 'Eu',
              email: '',
            ),
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
          var aid = _assigneeId ?? _currentUserId;
          if (users.isEmpty) {
            _assigneeId = aid;
          } else if (aid == null || !users.any((u) => u.id == aid)) {
            final curIn =
                _currentUserId != null &&
                    users.any((u) => u.id == _currentUserId);
            _assigneeId =
                curIn ? _currentUserId : users.first.id;
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
      if (mounted) {
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Título deve ter pelo menos 3 caracteres')),
      );
      return;
    }

    for (var i = 0; i < _contactRows.length; i++) {
      final row = _contactRows[i];
      final em = row.email.text.trim();
      if (em.isNotEmpty && !_isValidEmail(em)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('E-mail inválido no contato ${i + 1}')),
        );
        return;
      }
      final ph = _digitsOnly(row.phone.text);
      if (ph.isNotEmpty && (ph.length < 10 || ph.length > 11)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Telefone do contato ${i + 1}: use 10 ou 11 dígitos',
            ),
          ),
        );
        return;
      }
    }

    if (_selectedColumnId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione a etapa (coluna)')),
      );
      return;
    }

    if (_dueDate != null) {
      final today = DateTime(DateTime.now().year, DateTime.now().month,
          DateTime.now().day);
      final d = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day);
      if (d.isBefore(today)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data de vencimento não pode ser anterior a hoje'),
          ),
        );
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
      priority: _selectedPriority ?? KanbanPriority.medium,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(controller.error ?? 'Erro ao criar negociação'),
            backgroundColor: Colors.red,
          ),
        );
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
                    'Negociação criada, mas houve erro ao salvar pessoas envolvidas',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Negociação criada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<KanbanColumn> _realColumns(KanbanController c) {
    return c.displayColumns
        .where((col) => !KanbanSyntheticColumns.isSyntheticId(col.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<KanbanController>();
    final columns = _realColumns(controller);

    if (columns.isNotEmpty &&
        !columns.any((c) => c.id == _selectedColumnId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedColumnId = columns.first.id);
        }
      });
    }

    final columnValue = columns.isEmpty
        ? null
        : (columns.any((c) => c.id == _selectedColumnId)
            ? _selectedColumnId
            : columns.first.id);

    final inputDeco = InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: ThemeHelpers.cardBackgroundColor(context),
    );

    final media = MediaQuery.of(context);
    final sheetHeight = media.size.height * 0.92;

    return SizedBox(
      height: sheetHeight,
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.textSecondaryColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.handshake_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nova negociação',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                      if (columns.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: columnValue,
                          decoration: InputDecoration(
                            labelText: 'Etapa do funil *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            filled: true,
                            fillColor:
                                ThemeHelpers.cardBackgroundColor(context),
                          ),
                          items: columns
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.title),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selectedColumnId = v);
                            }
                          },
                        ),
                      if (columns.isNotEmpty) const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        maxLength: 200,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        decoration: inputDeco.copyWith(
                          labelText: 'Título *',
                          hintText: 'Nome da negociação',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Título é obrigatório';
                          }
                          return null;
                        },
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_titleController.text.length}/200',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        maxLength: 300,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        decoration: inputDeco.copyWith(
                          alignLabelWithHint: true,
                          labelText: 'Descrição',
                          counterText:
                              '${_descriptionController.text.length}/300',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if ((v ?? '').length > 300) {
                            return 'Máximo 300 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _internalNotesController,
                        maxLines: 4,
                        maxLength: 2000,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        decoration: inputDeco.copyWith(
                          alignLabelWithHint: true,
                          labelText: 'Observação interna',
                          hintText:
                              'Permuta, forma de pagamento, detalhes da negociação…',
                          counterText:
                              '${_internalNotesController.text.length}/2000',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if ((v ?? '').length > 2000) return 'Máximo 2000';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _totalValueController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\.,R$\s]'),
                          ),
                        ],
                        decoration: inputDeco.copyWith(
                          labelText: 'Valor total (R\$)',
                          hintText: 'Ex.: 350000 ou 1.234,56',
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<KanbanPriority>(
                        value: _selectedPriority,
                        decoration: inputDeco.copyWith(labelText: 'Prioridade'),
                        items: KanbanPriority.values.map((priority) {
                          return DropdownMenuItem(
                            value: priority,
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Color(int.parse(
                                      priority.color
                                          .replaceFirst('#', '0xFF'),
                                    )),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(priority.label),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedPriority = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickDueDate,
                              child: InputDecorator(
                                decoration: inputDeco.copyWith(
                                  labelText: 'Data de vencimento',
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_dueDate != null)
                                        IconButton(
                                          icon: const Icon(Icons.clear, size: 20),
                                          onPressed: () {
                                            setState(() => _dueDate = null);
                                          },
                                        ),
                                      const Icon(Icons.calendar_today, size: 20),
                                    ],
                                  ),
                                ),
                                child: Text(
                                  _dueDate != null
                                      ? '${_dueDate!.day.toString().padLeft(2, '0')}/${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.year}'
                                      : 'Sem prazo',
                                  style: TextStyle(
                                    color: _dueDate != null
                                        ? ThemeHelpers.textColor(context)
                                        : ThemeHelpers.textSecondaryColor(
                                            context,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_loadingMembers)
                        const LinearProgressIndicator(minHeight: 2),
                      if (_memberUsers.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _assigneeId,
                          decoration: inputDeco.copyWith(
                            labelText: 'Responsável',
                          ),
                          items: _memberUsers
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u.id,
                                  child: Text(
                                    u.name.isNotEmpty ? u.name : u.email,
                                    overflow: TextOverflow.ellipsis,
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
                      const SizedBox(height: 8),
                      if (_memberUsers.length > 1) ...[
                        Text(
                          'Pessoas envolvidas',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _memberUsers.map((u) {
                            if (u.id == _assigneeId) return const SizedBox.shrink();
                            final on = _involvedUserIds.contains(u.id);
                            return FilterChip(
                              label: Text(
                                u.name.isNotEmpty ? u.name : u.email,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'Cliente (opcional)',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_pickedClient != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_pickedClient!.name),
                          subtitle: Text(_pickedClient!.id),
                          trailing: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _pickedClient = null;
                                _clientSearchController.clear();
                                _clientSuggestions.clear();
                              });
                            },
                          ),
                        )
                      else ...[
                        TextField(
                          controller: _clientSearchController,
                          decoration: inputDeco.copyWith(
                            hintText: 'Digite ao menos 2 letras para buscar',
                            prefixIcon: const Icon(Icons.person_search),
                          ),
                          onChanged: _scheduleClientSearch,
                        ),
                        if (_clientSuggestions.isNotEmpty)
                          Card(
                            margin: const EdgeInsets.only(top: 6),
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _clientSuggestions.length,
                              itemBuilder: (ctx, i) {
                                final c = _clientSuggestions[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(c.name),
                                  subtitle: Text(
                                    c.phone ?? c.email ?? '',
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _pickedClient = c;
                                      _clientSuggestions.clear();
                                      _clientSearchController.clear();
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Imóvel (opcional)',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_pickedProperty != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_pickedProperty!.title),
                          subtitle: Text(
                            [
                              if (_pickedProperty!.code != null)
                                _pickedProperty!.code,
                              if (_pickedProperty!.city != null)
                                _pickedProperty!.city,
                            ].whereType<String>().join(' · '),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _pickedProperty = null;
                                _propertySearchController.clear();
                                _propertySuggestions.clear();
                              });
                            },
                          ),
                        )
                      else ...[
                        TextField(
                          controller: _propertySearchController,
                          decoration: inputDeco.copyWith(
                            hintText: 'Digite ao menos 2 letras',
                            prefixIcon: const Icon(Icons.home_work_outlined),
                          ),
                          onChanged: _schedulePropertySearch,
                        ),
                        if (_propertySuggestions.isNotEmpty)
                          Card(
                            margin: const EdgeInsets.only(top: 6),
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _propertySuggestions.length,
                              itemBuilder: (ctx, i) {
                                final p = _propertySuggestions[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(p.title),
                                  subtitle: Text(
                                    [
                                      if (p.code != null) p.code,
                                      if (p.city != null) p.city,
                                    ].whereType<String>().join(' · '),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _pickedProperty = p;
                                      _propertySuggestions.clear();
                                      _propertySearchController.clear();
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _sourceDropdown.isEmpty ? '' : _sourceDropdown,
                        decoration: inputDeco.copyWith(
                          labelText: 'Mídia / origem',
                        ),
                        items: _kLeadSources
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.$1,
                                child: Text(e.$2),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() => _sourceDropdown = v ?? '');
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _campaignController,
                        decoration: inputDeco.copyWith(
                          labelText: 'Campanha (texto livre)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _metaCampaignIdController,
                        decoration: inputDeco.copyWith(
                          labelText: 'ID campanha Meta (opcional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _systemCampaignIdController,
                        decoration: inputDeco.copyWith(
                          labelText: 'ID campanha do sistema (UUID, opcional)',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Contatos da negociação',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _contactRows.add(_ContactRowEditors());
                              });
                            },
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Adicionar'),
                          ),
                        ],
                      ),
                      ...List.generate(_contactRows.length, (i) {
                        final row = _contactRows[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Contato ${i + 1}',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_contactRows.length > 1)
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: theme.colorScheme.error,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            row.dispose();
                                            _contactRows.removeAt(i);
                                          });
                                        },
                                      ),
                                  ],
                                ),
                                TextField(
                                  controller: row.name,
                                  decoration: inputDeco.copyWith(
                                    labelText: 'Nome',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: row.phone,
                                  keyboardType: TextInputType.phone,
                                  decoration: inputDeco.copyWith(
                                    labelText: 'Telefone',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: row.email,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: inputDeco.copyWith(
                                    labelText: 'E-mail',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: row.jobTitle,
                                  decoration: inputDeco.copyWith(
                                    labelText: 'Cargo',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: row.birthDate,
                                  decoration: inputDeco.copyWith(
                                    labelText: 'Nascimento (AAAA-MM-DD)',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  16 + media.padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  border: Border(
                    top: BorderSide(
                      color: ThemeHelpers.borderColor(context),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _isLoading ? null : _save,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Criar negociação'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }
}
