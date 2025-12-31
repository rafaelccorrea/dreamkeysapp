import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/inspection_model.dart';
import '../services/inspection_service.dart';

/// Página de detalhes de uma vistoria
class InspectionDetailsPage extends StatefulWidget {
  final String inspectionId;

  const InspectionDetailsPage({super.key, required this.inspectionId});

  @override
  State<InspectionDetailsPage> createState() => _InspectionDetailsPageState();
}

class _InspectionDetailsPageState extends State<InspectionDetailsPage> {
  final InspectionService _inspectionService = InspectionService.instance;
  final ImagePicker _imagePicker = ImagePicker();

  Inspection? _inspection;
  bool _isLoading = true;
  bool _isLoadingHistory = false;
  bool _isUploadingPhoto = false;
  String? _errorMessage;
  List<InspectionHistoryEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _loadInspection();
    _loadHistory();
  }

  Future<void> _loadInspection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _inspectionService.getInspectionById(
        widget.inspectionId,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _inspection = response.data!;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar vistoria';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro de conexão: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoadingHistory = true;
    });

    try {
      final response = await _inspectionService.getHistory(widget.inspectionId);

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _history = response.data!;
            _isLoadingHistory = false;
          });
        } else {
          setState(() {
            _isLoadingHistory = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _uploadPhoto() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tirar Foto'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Selecionar da Galeria'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _isUploadingPhoto = true;
      });

      final file = File(pickedFile.path);
      final response = await _inspectionService.uploadPhoto(
        widget.inspectionId,
        file,
      );

      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });

        if (response.success && response.data != null) {
          setState(() {
            _inspection = response.data!;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Foto adicionada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao fazer upload da foto'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _removePhoto(String photoUrl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.status.error,
              size: 20,
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirmar Remoção')),
          ],
        ),
        content: const Text('Tem certeza que deseja remover esta foto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _inspectionService.removePhoto(
        widget.inspectionId,
        photoUrl,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _inspection = response.data!;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Foto removida com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao remover foto'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _changeStatus(InspectionStatus newStatus) async {
    String title = '';
    String message = '';
    IconData icon = Icons.info;
    Color? iconColor;

    switch (newStatus) {
      case InspectionStatus.inProgress:
        title = 'Iniciar Vistoria';
        message = 'Tem certeza que deseja iniciar esta vistoria?';
        icon = Icons.play_arrow;
        iconColor = Colors.orange;
        break;
      case InspectionStatus.completed:
        title = 'Concluir Vistoria';
        message = 'Tem certeza que deseja marcar esta vistoria como concluída?';
        icon = Icons.check_circle;
        iconColor = Colors.green;
        break;
      case InspectionStatus.cancelled:
        title = 'Cancelar Vistoria';
        message = 'Tem certeza que deseja cancelar esta vistoria?';
        icon = Icons.cancel;
        iconColor = Colors.red;
        break;
      default:
        title = 'Alterar Status';
        message = 'Tem certeza que deseja alterar o status desta vistoria?';
        icon = Icons.info;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: ThemeHelpers.textSecondaryColor(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Icon
            Icon(icon, size: 48, color: iconColor ?? AppColors.primary.primary),
            const SizedBox(height: 16),
            // Title
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Message
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            // Buttons
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: Icon(icon),
                    label: const Text('Confirmar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor ?? AppColors.primary.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final now = DateTime.now();
      final updateData = UpdateInspectionDto(
        status: newStatus,
        startDate:
            newStatus == InspectionStatus.inProgress &&
                _inspection?.startDate == null
            ? now
            : null,
        completionDate:
            newStatus == InspectionStatus.completed &&
                _inspection?.completionDate == null
            ? now
            : null,
      );

      final response = await _inspectionService.updateInspection(
        widget.inspectionId,
        updateData,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          await _loadInspection();
          await _loadHistory();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Status atualizado com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao atualizar status'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteInspection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.status.error),
            const SizedBox(width: 12),
            const Expanded(child: Text('Confirmar Exclusão')),
          ],
        ),
        content: const Text(
          'Tem certeza que deseja excluir esta vistoria? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _inspectionService.deleteInspection(
        widget.inspectionId,
      );

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Vistoria excluída com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao excluir vistoria'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _requestFinancialApproval() async {
    if (_inspection == null ||
        _inspection!.value == null ||
        _inspection!.value! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'A vistoria deve ter um valor maior que zero para solicitar aprovação',
          ),
          backgroundColor: AppColors.status.warning,
        ),
      );
      return;
    }

    if (_inspection!.hasFinancialApproval) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Esta vistoria já possui uma aprovação financeira solicitada',
          ),
          backgroundColor: AppColors.status.info,
        ),
      );
      return;
    }

    try {
      final approvalData = CreateInspectionApprovalDto(
        inspectionId: widget.inspectionId,
        amount: _inspection!.value!,
        notes: 'Aprovação financeira para vistoria: ${_inspection!.title}',
      );

      final response = await _inspectionService.requestApproval(approvalData);

      if (mounted) {
        if (response.success) {
          await _loadInspection();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Aprovação financeira solicitada com sucesso',
              ),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao solicitar aprovação'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _addHistoryEntry() async {
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.textSecondaryColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Adicionar ao Histórico',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        descriptionController.dispose();
                        Navigator.pop(context, false);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Text Field
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição',
                    hintText: 'Descreva o evento ou alteração',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                  maxLength: 500,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Campo obrigatório';
                    }
                    return null;
                  },
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                // Buttons
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.pop(context, true);
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          descriptionController.dispose();
                          Navigator.pop(context, false);
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
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

    if (result != true || descriptionController.text.trim().isEmpty) {
      descriptionController.dispose();
      return;
    }

    try {
      final historyData = CreateInspectionHistoryDto(
        description: descriptionController.text.trim(),
      );

      final response = await _inspectionService.addHistoryEntry(
        widget.inspectionId,
        historyData,
      );

      descriptionController.dispose();

      if (mounted) {
        if (response.success) {
          await _loadHistory();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Entrada adicionada ao histórico'),
              backgroundColor: AppColors.status.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response.message ?? 'Erro ao adicionar ao histórico',
              ),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      descriptionController.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Color _getStatusColor(InspectionStatus status) {
    switch (status) {
      case InspectionStatus.scheduled:
        return Colors.blue;
      case InspectionStatus.inProgress:
        return Colors.orange;
      case InspectionStatus.completed:
        return Colors.green;
      case InspectionStatus.cancelled:
        return Colors.red;
    }
  }

  Color _getTypeColor(InspectionType type) {
    switch (type) {
      case InspectionType.entry:
        return Colors.blue;
      case InspectionType.exit:
        return Colors.red;
      case InspectionType.maintenance:
        return Colors.orange;
      case InspectionType.sale:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
    final currencyFormat = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );

    return AppScaffold(
      title: 'Detalhes da Vistoria',
      showBottomNavigation: false,
      actions: [
        if (_inspection != null)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  Navigator.of(context)
                      .pushNamed(AppRoutes.inspectionEdit(widget.inspectionId))
                      .then((_) => _loadInspection());
                  break;
                case 'delete':
                  _deleteInspection();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(width: 8),
                    Text('Editar'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Excluir', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
      ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(height: 16),
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadInspection,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar Novamente'),
                    ),
                  ],
                ),
              ),
            )
          : _inspection == null
          ? const Center(child: Text('Vistoria não encontrada'))
          : RefreshIndicator(
              onRefresh: () async {
                await _loadInspection();
                await _loadHistory();
              },
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header com título e status
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.cardBackgroundColor(context),
                        border: Border(
                          bottom: BorderSide(
                            color: ThemeHelpers.borderLightColor(context),
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _inspection!.title,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(
                                    _inspection!.status,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _inspection!.status.label,
                                  style: TextStyle(
                                    color: _getStatusColor(_inspection!.status),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _getTypeColor(
                                    _inspection!.type,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _inspection!.type.label,
                                  style: TextStyle(
                                    color: _getTypeColor(_inspection!.type),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Ações rápidas
                    if (_inspection!.status == InspectionStatus.scheduled)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        child: CustomButton(
                          text: 'Iniciar Vistoria',
                          icon: Icons.play_arrow,
                          onPressed: () =>
                              _changeStatus(InspectionStatus.inProgress),
                        ),
                      ),

                    if (_inspection!.status == InspectionStatus.inProgress)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        child: CustomButton(
                          text: 'Concluir Vistoria',
                          icon: Icons.check_circle,
                          onPressed: () =>
                              _changeStatus(InspectionStatus.completed),
                        ),
                      ),

                    // Informações principais
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(theme, 'Informações Gerais'),
                          const SizedBox(height: 16),
                          _buildInfoRow(
                            context,
                            theme,
                            'Data Agendada',
                            dateTimeFormat.format(_inspection!.scheduledDate),
                            Icons.calendar_today,
                          ),
                          if (_inspection!.startDate != null) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              theme,
                              'Data de Início',
                              dateTimeFormat.format(_inspection!.startDate!),
                              Icons.play_arrow,
                            ),
                          ],
                          if (_inspection!.completionDate != null) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              theme,
                              'Data de Conclusão',
                              dateTimeFormat.format(
                                _inspection!.completionDate!,
                              ),
                              Icons.check_circle,
                            ),
                          ],
                          if (_inspection!.description != null &&
                              _inspection!.description!.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle(theme, 'Descrição'),
                            const SizedBox(height: 8),
                            Text(
                              _inspection!.description!,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],

                          // Propriedade
                          if (_inspection!.property != null) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle(theme, 'Propriedade'),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () {
                                final propertyId = _inspection!.property!['id']
                                    ?.toString();
                                if (propertyId != null) {
                                  Navigator.of(context).pushNamed(
                                    AppRoutes.propertyDetails(propertyId),
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ThemeHelpers.cardBackgroundColor(
                                    context,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: ThemeHelpers.borderLightColor(
                                      context,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.home,
                                      color: AppColors.primary.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _inspection!.property!['title']
                                                    ?.toString() ??
                                                'Sem título',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          if (_inspection!
                                                  .property!['address'] !=
                                              null)
                                            Text(
                                              _inspection!.property!['address']
                                                  .toString(),
                                              style: theme.textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          // Vistoriador
                          if (_inspection!.inspector != null) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle(theme, 'Vistoriador'),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: ThemeHelpers.cardBackgroundColor(
                                  context,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ThemeHelpers.borderLightColor(context),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    child: Text(
                                      (_inspection!.inspector!['name']
                                                  ?.toString() ??
                                              'U')[0]
                                          .toUpperCase(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _inspection!.inspector!['name']
                                                  ?.toString() ??
                                              'Sem nome',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        if (_inspection!.inspector!['email'] !=
                                            null)
                                          Text(
                                            _inspection!.inspector!['email']
                                                .toString(),
                                            style: theme.textTheme.bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Valor e Aprovação Financeira
                          if (_inspection!.value != null) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle(theme, 'Valor'),
                            const SizedBox(height: 12),
                            Text(
                              currencyFormat.format(_inspection!.value),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary.primary,
                              ),
                            ),
                            if (!_inspection!.hasFinancialApproval &&
                                _inspection!.value! > 0) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _requestFinancialApproval,
                                  icon: const Icon(Icons.request_quote),
                                  label: const Text(
                                    'Solicitar Aprovação Financeira',
                                  ),
                                ),
                              ),
                            ],
                            if (_inspection!.hasFinancialApproval) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      _inspection!.approvalStatus == 'approved'
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : _inspection!.approvalStatus ==
                                            'rejected'
                                      ? Colors.red.withValues(alpha: 0.1)
                                      : Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _inspection!.approvalStatus == 'approved'
                                          ? Icons.check_circle
                                          : _inspection!.approvalStatus ==
                                                'rejected'
                                          ? Icons.cancel
                                          : Icons.pending,
                                      color:
                                          _inspection!.approvalStatus ==
                                              'approved'
                                          ? Colors.green
                                          : _inspection!.approvalStatus ==
                                                'rejected'
                                          ? Colors.red
                                          : Colors.orange,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _inspection!.approvalStatus ==
                                                'approved'
                                            ? 'Aprovação Financeira Concedida'
                                            : _inspection!.approvalStatus ==
                                                  'rejected'
                                            ? 'Aprovação Financeira Rejeitada'
                                            : 'Aguardando Aprovação Financeira',
                                        style: TextStyle(
                                          color:
                                              _inspection!.approvalStatus ==
                                                  'approved'
                                              ? Colors.green
                                              : _inspection!.approvalStatus ==
                                                    'rejected'
                                              ? Colors.red
                                              : Colors.orange,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],

                          // Responsável
                          if (_inspection!.responsibleName != null) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle(theme, 'Responsável'),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              context,
                              theme,
                              'Nome',
                              _inspection!.responsibleName!,
                              Icons.person,
                            ),
                            if (_inspection!.responsibleDocument != null) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                theme,
                                'Documento',
                                _inspection!.responsibleDocument!,
                                Icons.badge,
                              ),
                            ],
                            if (_inspection!.responsiblePhone != null) ...[
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                context,
                                theme,
                                'Telefone',
                                _inspection!.responsiblePhone!,
                                Icons.phone,
                              ),
                            ],
                          ],

                          // Observações
                          if (_inspection!.observations != null &&
                              _inspection!.observations!.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle(theme, 'Observações'),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: ThemeHelpers.cardBackgroundColor(
                                  context,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ThemeHelpers.borderLightColor(context),
                                ),
                              ),
                              child: Text(
                                _inspection!.observations!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],

                          // Fotos
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSectionTitle(theme, 'Fotos'),
                              if (_isUploadingPhoto)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.add_photo_alternate),
                                  onPressed: _uploadPhoto,
                                  tooltip: 'Adicionar Foto',
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_inspection!.photos.isEmpty)
                            Container(
                              width: double.infinity,
                              height: 200,
                              decoration: BoxDecoration(
                                color: ThemeHelpers.cardBackgroundColor(
                                  context,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ThemeHelpers.borderLightColor(context),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.photo_library_outlined,
                                    size: 48,
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Nenhuma foto adicionada',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: ThemeHelpers.textSecondaryColor(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: _inspection!.photos.length,
                              itemBuilder: (context, index) {
                                final photoUrl = _inspection!.photos[index];
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        photoUrl,
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.grey[300],
                                                child: const Icon(
                                                  Icons.broken_image,
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          onPressed: () =>
                                              _removePhoto(photoUrl),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                          // Histórico
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSectionTitle(theme, 'Histórico'),
                              TextButton.icon(
                                onPressed: _addHistoryEntry,
                                icon: const Icon(Icons.add),
                                label: const Text('Adicionar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isLoadingHistory)
                            const Center(child: CircularProgressIndicator())
                          else if (_history.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: ThemeHelpers.cardBackgroundColor(
                                  context,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: ThemeHelpers.borderLightColor(context),
                                ),
                              ),
                              child: Text(
                                'Nenhum registro no histórico',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textSecondaryColor(
                                    context,
                                  ),
                                ),
                              ),
                            )
                          else
                            ..._history.map((entry) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ThemeHelpers.cardBackgroundColor(
                                    context,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: ThemeHelpers.borderLightColor(
                                      context,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (entry.user != null)
                                          CircleAvatar(
                                            radius: 16,
                                            child: Text(
                                              (entry.user!['name']
                                                          ?.toString() ??
                                                      'U')[0]
                                                  .toUpperCase(),
                                            ),
                                          ),
                                        if (entry.user != null)
                                          const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (entry.user != null)
                                                Text(
                                                  entry.user!['name']
                                                          ?.toString() ??
                                                      'Usuário',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              Text(
                                                DateFormat(
                                                  'dd/MM/yyyy HH:mm',
                                                ).format(entry.createdAt),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          ThemeHelpers.textSecondaryColor(
                                                            context,
                                                          ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      entry.description,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              border: Border(
                bottom: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 250, height: 24),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SkeletonText(width: 100, height: 20, borderRadius: 8),
                    const SizedBox(width: 8),
                    SkeletonText(width: 100, height: 20, borderRadius: 8),
                  ],
                ),
              ],
            ),
          ),
          // Content skeleton
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info sections
                SkeletonText(
                  width: 150,
                  height: 20,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
                ...List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SkeletonBox(width: 20, height: 20, borderRadius: 4),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonText(
                                width: 100,
                                height: 14,
                                margin: const EdgeInsets.only(bottom: 4),
                              ),
                              SkeletonText(width: double.infinity, height: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Property card skeleton
                SkeletonText(
                  width: 150,
                  height: 20,
                  margin: const EdgeInsets.only(bottom: 12),
                ),
                SkeletonCard(
                  height: 80,
                  child: Row(
                    children: [
                      SkeletonBox(width: 48, height: 48, borderRadius: 8),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonText(
                              width: double.infinity,
                              height: 18,
                              margin: const EdgeInsets.only(bottom: 4),
                            ),
                            SkeletonText(width: 200, height: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Photos skeleton
                SkeletonText(
                  width: 100,
                  height: 20,
                  margin: const EdgeInsets.only(bottom: 12),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return SkeletonBox(
                      width: double.infinity,
                      height: 100,
                      borderRadius: 8,
                    );
                  },
                ),
                const SizedBox(height: 24),
                // History skeleton
                SkeletonText(
                  width: 100,
                  height: 20,
                  margin: const EdgeInsets.only(bottom: 12),
                ),
                ...List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SkeletonCard(
                      child: Row(
                        children: [
                          SkeletonBox(width: 32, height: 32, borderRadius: 16),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonText(
                                  width: 120,
                                  height: 14,
                                  margin: const EdgeInsets.only(bottom: 4),
                                ),
                                SkeletonText(
                                  width: 80,
                                  height: 12,
                                  margin: const EdgeInsets.only(bottom: 8),
                                ),
                                SkeletonText(
                                  width: double.infinity,
                                  height: 16,
                                ),
                              ],
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
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    ThemeData theme,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
