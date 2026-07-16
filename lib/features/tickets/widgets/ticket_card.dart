import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/ticket_models.dart';

/// Item da lista de tickets — linha SÓBRIA e flush: indicador lateral FINO
/// (3px) na cor do status, tipografia protagonista (título primeiro) e
/// metadados neutros em texto puro. A cor só aparece onde tem significado:
/// status à esquerda, prioridade à direita quando pesa (alta/urgente).
/// Toca para abrir o detalhe.
class TicketCard extends StatelessWidget {
  final Ticket ticket;
  final VoidCallback? onTap;

  const TicketCard({super.key, required this.ticket, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final statusTone = ticketStatusColor(context, ticket.status);
    final priorityTone = ticketPriorityColor(context, ticket.priority);

    final description = ticket.description
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final showPriority =
        ticket.priority == TicketPriority.high ||
        ticket.priority == TicketPriority.urgent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Indicador lateral fino de status — a assinatura da linha.
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: statusTone,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Título protagonista.
                      Text(
                        ticket.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      // Status (na cor semântica) · categoria — texto, sem pílula.
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              ticket.status.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: statusTone,
                                height: 1.2,
                              ),
                            ),
                          ),
                          Text(
                            '  ·  ',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: neutral.withValues(alpha: 0.7),
                              height: 1.2,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              ticket.category.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: neutral,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: neutral,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        children: [
                          if (ticket.attendantLabel != null)
                            _MetaBit(
                              icon: LucideIcons.headset,
                              text: ticket.attendantLabel!,
                              color: neutral,
                            )
                          else
                            _MetaBit(
                              icon: LucideIcons.hourglass,
                              text: 'Aguardando atendimento',
                              color: neutral,
                            ),
                          if (ticket.lastReplyAt != null)
                            _MetaBit(
                              icon: LucideIcons.messageCircle,
                              text: 'Resposta ${_relative(ticket.lastReplyAt!)}',
                              color: neutral,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Data à direita; prioridade só quando pesa (texto na cor).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (ticket.createdAt != null)
                      Text(
                        _dateLabel(ticket.createdAt!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: neutral,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                        ),
                      ),
                    if (showPriority) ...[
                      const SizedBox(height: 5),
                      Text(
                        ticket.priority.label,
                        style: TextStyle(
                          color: priorityTone,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 15,
                      color: neutral.withValues(alpha: 0.6),
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

  static String _dateLabel(DateTime date) {
    return DateFormat('dd/MM/yy', 'pt_BR').format(date.toLocal());
  }

  static String _relative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date.toLocal());
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays == 1) return 'ontem';
    if (diff.inDays < 30) return 'há ${diff.inDays} dias';
    return DateFormat('dd/MM/yy', 'pt_BR').format(date.toLocal());
  }
}

/// Mini-item de metadado (ícone + texto compacto, neutro).
class _MetaBit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MetaBit({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
