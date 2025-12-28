import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/match_model.dart';

/// Card de match
class MatchCard extends StatelessWidget {
  final Match match;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;
  final VoidCallback onView;

  const MatchCard({
    super.key,
    required this.match,
    required this.onAccept,
    required this.onIgnore,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor = match.getScoreColor();
    final scoreLabel = match.getScoreLabel();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      color: ThemeHelpers.cardBackgroundColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com score
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scoreColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (match.matchScore >= 90)
                        const Text(
                          '🔥',
                          style: TextStyle(fontSize: 16),
                        ),
                      const SizedBox(width: 4),
                      Text(
                        '${match.matchScore}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scoreLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scoreColor,
                    ),
                  ),
                ),
                if (match.status == MatchStatus.pending)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'NOVO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Imagem da propriedade
          if (match.property.mainImage != null ||
              (match.property.images != null &&
                  match.property.images!.isNotEmpty))
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                image: DecorationImage(
                  image: NetworkImage(
                    match.property.mainImage?.url ??
                        match.property.images?.first.url ??
                        '',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // Informações
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Propriedade
                Row(
                  children: [
                    Icon(
                      Icons.home_outlined,
                      size: 20,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        match.property.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (match.property.address != null ||
                    match.property.city != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            [
                              match.property.neighborhood,
                              match.property.city,
                            ]
                                .where((e) => e != null && e.isNotEmpty)
                                .join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (match.property.salePrice != null ||
                    match.property.rentPrice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      match.property.salePrice != null
                          ? 'R\$ ${_formatPrice(match.property.salePrice!)}'
                          : 'R\$ ${_formatPrice(match.property.rentPrice!)}/mês',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.primary.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                const Divider(height: 32),

                // Cliente
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary.primary.withOpacity(0.1),
                      backgroundImage: match.client.avatar != null
                          ? NetworkImage(match.client.avatar!)
                          : null,
                      child: match.client.avatar == null
                          ? Text(
                              match.client.name.isNotEmpty
                                  ? match.client.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: AppColors.primary.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            match.client.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (match.client.phone != null)
                            Text(
                              match.client.phone!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const Divider(height: 32),

                // Motivos do match
                Text(
                  'Por que é um match:',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ...match.matchDetails.reasons.take(3).map(
                      (reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: AppColors.primary.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                reason,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                const SizedBox(height: 16),

                // Botões de ação
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onView,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Ver Detalhes'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onIgnore,
                        icon: const Icon(Icons.close),
                        label: const Text('Ignorar'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: onAccept,
                        icon: const Icon(Icons.check),
                        label: const Text('Aceitar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
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

  String _formatPrice(double price) {
    return price.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match.group(1)}.',
        );
  }
}

