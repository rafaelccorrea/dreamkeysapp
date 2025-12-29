import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Skeleton para o quadro Kanban
class KanbanSkeleton extends StatelessWidget {
  const KanbanSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Skeleton do header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              bottom: BorderSide(
                color: ThemeHelpers.borderColor(context),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SkeletonBox(
                  height: 24,
                  width: 150,
                  borderRadius: 4,
                ),
              ),
              const SizedBox(width: 8),
              SkeletonBox(width: 40, height: 40, borderRadius: 8),
              const SizedBox(width: 8),
              SkeletonBox(width: 40, height: 40, borderRadius: 8),
            ],
          ),
        ),
        // Skeleton do seletor de projeto
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              bottom: BorderSide(
                color: ThemeHelpers.borderColor(context),
              ),
            ),
          ),
          child: Row(
            children: [
              SkeletonBox(width: 20, height: 20, borderRadius: 4),
              const SizedBox(width: 8),
              SkeletonBox(width: 100, height: 24, borderRadius: 8),
              const SizedBox(width: 12),
              SkeletonBox(width: 60, height: 20, borderRadius: 4),
              const SizedBox(width: 12),
              Expanded(
                child: SkeletonBox(
                  height: 40,
                  borderRadius: 8,
                ),
              ),
            ],
          ),
        ),
        // Skeleton dos filtros
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border(
              bottom: BorderSide(
                color: ThemeHelpers.borderColor(context),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SkeletonBox(
                  height: 40,
                  borderRadius: 8,
                ),
              ),
              const SizedBox(width: 12),
              SkeletonBox(width: 120, height: 40, borderRadius: 8),
            ],
          ),
        ),
        // Skeleton do quadro com colunas
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                3,
                (index) => _buildColumnSkeleton(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnSkeleton(BuildContext context) {
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 16),
      constraints: const BoxConstraints(
        minHeight: 200,
        maxHeight: 600,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header da coluna
          Row(
            children: [
              Expanded(
                child: SkeletonBox(
                  height: 20,
                  width: 100,
                  borderRadius: 4,
                ),
              ),
              SkeletonBox(width: 24, height: 24, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 8),
          SkeletonBox(
            height: 14,
            width: 60,
            borderRadius: 4,
          ),
          const SizedBox(height: 16),
          // Tarefas skeleton (limitado a 2 para evitar overflow)
          ...List.generate(
            2,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildTaskSkeleton(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSkeleton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          SkeletonBox(
            height: 16,
            width: double.infinity,
            borderRadius: 4,
            margin: const EdgeInsets.only(bottom: 8),
          ),
          // Descrição
          SkeletonBox(
            height: 14,
            width: double.infinity,
            borderRadius: 4,
            margin: const EdgeInsets.only(bottom: 8),
          ),
          SkeletonBox(
            height: 14,
            width: 150,
            borderRadius: 4,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          // Footer
          Row(
            children: [
              SkeletonBox(width: 8, height: 8, borderRadius: 4),
              const SizedBox(width: 8),
              SkeletonBox(width: 60, height: 16, borderRadius: 4),
              const Spacer(),
              SkeletonBox(width: 24, height: 24, borderRadius: 12),
            ],
          ),
        ],
      ),
    );
  }
}

