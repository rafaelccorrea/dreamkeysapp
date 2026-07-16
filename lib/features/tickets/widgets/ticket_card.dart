import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../models/ticket_models.dart';

/// Item da lista de tickets — **linha flush** (sem card/sombra), mesmo DNA
/// das listas de comissões/chaves: glyph tonal da categoria, status + título +
/// resumo no meio, prioridade e data à direita. Toca para abrir o detalhe.
class TicketCard extends StatelessWidget {
  final Ticket ticket;
  final VoidCallback? onTap;

  const TicketCard({super.key, required this.ticket, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final statusTone = ticketStatusColor(context, ticket.status);
    final categoryTone = ticketCategoryColor(context, ticket.category);
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
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Glyph tonal da categoria.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: categoryTone.withValues(alpha: isDark ? 0.16 : 0.1),
                  border: Border.all(
                    color: categoryTone.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  ticketCategoryIcon(ticket.category),
                  color: categoryTone,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _StatusPill(
                            label: ticket.status.label,
                            color: statusTone,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            ticket.category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: neutral,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ticket.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: neutral,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 3,
                      children: [
                        if (ticket.attendantLabel != null)
                          _SpecBit(
                            icon: LucideIcons.headset,
                            text: ticket.attendantLabel!,
                            color: neutral,
                          )
                        else
                          _SpecBit(
                            icon: LucideIcons.hourglass,
                            text: 'Aguardando atendimento',
                            color: neutral,
                          ),
                        if (ticket.lastReplyAt != null)
                          _SpecBit(
                            icon: LucideIcons.messageCircle,
                            text: 'Resposta ${_relative(ticket.lastReplyAt!)}',
                            color: neutral,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Prioridade (só quando pesa) + data de abertura.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showPriority)
                    _StatusPill(
                      label: ticket.priority.label,
                      color: priorityTone,
                    )
                  else
                    Icon(LucideIcons.chevronRight, size: 16, color: neutral),
                  const SizedBox(height: 6),
                  if (ticket.createdAt != null)
                    Text(
                      _dateLabel(ticket.createdAt!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: neutral,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                ],
              ),
            ],
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

/// Mini-item de metadado (ícone + texto compacto).
class _SpecBit extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SpecBit({required this.icon, required this.text, required this.color});

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
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Pílula de status — tint da cor + texto na cor (grammar do app).
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
