import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/match_model.dart';
import '../../../shared/widgets/custom_text_field.dart';

/// Modal para ignorar match com motivo
class IgnoreMatchModal extends StatefulWidget {
  final Match match;
  final Function(IgnoreReason reason, String? notes) onIgnore;

  const IgnoreMatchModal({
    super.key,
    required this.match,
    required this.onIgnore,
  });

  @override
  State<IgnoreMatchModal> createState() => _IgnoreMatchModalState();
}

class _IgnoreMatchModalState extends State<IgnoreMatchModal> {
  IgnoreReason? _selectedReason;
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ThemeHelpers.borderLightColor(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ignorar Match',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Por favor, selecione o motivo para ignorar este match.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 24),

                // Motivos
                ...IgnoreReason.values.map((reason) {
                  return RadioListTile<IgnoreReason>(
                    title: Row(
                      children: [
                        Icon(
                          _getReasonIcon(reason),
                          size: 20,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(reason.label)),
                      ],
                    ),
                    value: reason,
                    groupValue: _selectedReason,
                    onChanged: (value) {
                      setState(() {
                        _selectedReason = value;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  );
                }),

                const SizedBox(height: 16),

                // Campo de notas
                CustomTextField(
                  controller: _notesController,
                  label: 'Notas (opcional)',
                  prefixIcon: const Icon(Icons.note_outlined),
                  maxLines: 3,
                ),

                const SizedBox(height: 24),

                // Botões
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _selectedReason == null
                            ? null
                            : () {
                                widget.onIgnore(
                                  _selectedReason!,
                                  _notesController.text.trim().isEmpty
                                      ? null
                                      : _notesController.text.trim(),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Ignorar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getReasonIcon(IgnoreReason reason) {
    switch (reason) {
      case IgnoreReason.priceTooHigh:
        return Icons.arrow_upward;
      case IgnoreReason.priceTooLow:
        return Icons.arrow_downward;
      case IgnoreReason.locationBad:
        return Icons.location_off;
      case IgnoreReason.alreadyShown:
        return Icons.visibility_off;
      case IgnoreReason.clientNotInterested:
        return Icons.sentiment_dissatisfied;
      case IgnoreReason.propertySold:
        return Icons.sell;
      case IgnoreReason.other:
        return Icons.more_horiz;
    }
  }
}

