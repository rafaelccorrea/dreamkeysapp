import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/services/auth_service.dart';

/// Tela principal do aplicativo (Dashboard)
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background.background,
      appBar: AppBar(
        title: const Text(
          'Dream Keys',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        elevation: 0,
        backgroundColor: AppColors.primary.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              // TODO: Implementar notificações
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notificações em breve'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 12),
                    Text('Sair'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Saudação
              Text(
                'Bem-vindo de volta! 👋',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.text.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gerencie seus imóveis e clientes de forma fácil',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.text.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Cards de resumo (placeholder)
              _buildSummaryCards(context, theme),
              const SizedBox(height: 32),

              // Seção de ações rápidas
              Text(
                'Ações Rápidas',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.text.text,
                ),
              ),
              const SizedBox(height: 16),
              _buildQuickActions(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            context: context,
            theme: theme,
            title: 'Imóveis',
            value: '0',
            icon: Icons.home_outlined,
            color: AppColors.primary.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryCard(
            context: context,
            theme: theme,
            title: 'Clientes',
            value: '0',
            icon: Icons.people_outlined,
            color: AppColors.secondary.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.text.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.text.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        _buildQuickActionCard(
          context: context,
          theme: theme,
          title: 'Adicionar Imóvel',
          subtitle: 'Cadastre um novo imóvel',
          icon: Icons.add_home_work_outlined,
          onTap: () {
            // TODO: Navegar para cadastro de imóvel
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Funcionalidade em breve'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildQuickActionCard(
          context: context,
          theme: theme,
          title: 'Adicionar Cliente',
          subtitle: 'Cadastre um novo cliente',
          icon: Icons.person_add_outlined,
          onTap: () {
            // TODO: Navegar para cadastro de cliente
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Funcionalidade em breve'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildQuickActionCard(
          context: context,
          theme: theme,
          title: 'Relatórios',
          subtitle: 'Visualize seus relatórios',
          icon: Icons.assessment_outlined,
          onTap: () {
            // TODO: Navegar para relatórios
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Funcionalidade em breve'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.border.borderLight,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.text.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.text.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Tem certeza que deseja sair?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      // Limpar token
      AuthService.instance.logout();
      
      // Navegar para login
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    }
  }
}

