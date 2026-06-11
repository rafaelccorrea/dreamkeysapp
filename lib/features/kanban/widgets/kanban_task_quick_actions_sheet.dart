import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/broker_contact_actions.dart';
import '../../../shared/utils/broker_message_templates.dart';
import '../../../shared/utils/kanban_task_contact_helper.dart';
import '../../appointments/models/appointment_model.dart';
import '../../appointments/pages/create_appointment_page.dart';
import '../controllers/kanban_controller.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';
import 'edit_task_modal.dart';
import 'task_details_modal.dart';
import 'transfer_task_sheet.dart';

/// Ações rápidas do corretor no card do funil (WhatsApp, ligar, agenda…).
Future<void> showKanbanTaskQuickActions(
  BuildContext context,
  KanbanTask task, {
  KanbanController? controller,
}) async {
  final pageContext = context;
  final c = controller ?? context.read<KanbanController>();
  final perms = c.permissions;

  KanbanTask enriched = task;
  if (task.contacts == null || task.contacts!.isEmpty) {
    final res = await KanbanService.instance.getTaskById(task.id);
    if (res.success && res.data != null) {
      enriched = res.data!;
    }
  }

  final name = KanbanTaskContactHelper.leadDisplayName(enriched);
  final phone = KanbanTaskContactHelper.leadPhone(enriched);
  final propertyHint = KanbanTaskContactHelper.propertyHint(enriched);

  if (!pageContext.mounted) return;

  await showModalBottomSheet<void>(
    context: pageContext,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enriched.title,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (phone != null)
                  Text(
                    phone,
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.chat_rounded, color: AppColors.status.success),
            title: const Text('WhatsApp'),
            subtitle: const Text('Abrir conversa com template'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final msg = BrokerMessageTemplates.leadFollowUp(
                leadName: name,
                propertyTitle: propertyHint,
              );
              await BrokerContactActions.openWhatsApp(
                pageContext,
                phone,
                message: msg,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.phone_rounded),
            title: const Text('Ligar'),
            enabled: phone != null,
            onTap: () {
              Navigator.pop(sheetContext);
              BrokerContactActions.callPhone(pageContext, phone);
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_rounded),
            title: const Text('Agendar visita'),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.of(pageContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => CreateAppointmentPage(
                    initialTitle: 'Visita — $name',
                    initialType: AppointmentType.visit,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Ver detalhes'),
            onTap: () {
              Navigator.pop(sheetContext);
              showModalBottomSheet<void>(
                context: pageContext,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                barrierColor: Colors.black54,
                builder: (ctx) => TaskDetailsModal(task: enriched),
              );
            },
          ),
          if (perms?.canTransfer ?? perms?.canEditTasks ?? false)
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Transferir funil'),
              onTap: () {
                Navigator.pop(sheetContext);
                showModalBottomSheet<void>(
                  context: pageContext,
                  isScrollControlled: true,
                  builder: (ctx) => TransferTaskSheet(task: enriched),
                );
              },
            ),
          if (perms?.canEditTasks ?? true)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(sheetContext);
                showModalBottomSheet<void>(
                  context: pageContext,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom,
                    ),
                    child: EditTaskModal(task: enriched),
                  ),
                );
              },
            ),
          ListTile(
            leading: Icon(Icons.open_in_new_rounded, color: Colors.grey.shade600),
            title: const Text('Abrir negociação'),
            onTap: () {
              Navigator.pop(sheetContext);
              Navigator.of(pageContext).pushNamed(
                AppRoutes.kanbanTaskDetails(enriched.id),
              );
            },
          ),
        ],
      ),
    ),
  );
}
