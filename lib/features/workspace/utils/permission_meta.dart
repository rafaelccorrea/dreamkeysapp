import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Metadados de exibição para categorias e ações de permissão — paridade com
/// `imobx-front/src/utils/permissionCategoryMapping.ts`, mas usando ícones
/// Lucide (sem emojis, conforme o padrão visual da casa) e rótulos em PT.
class PermissionMeta {
  PermissionMeta._();

  // ─── Categorias → rótulo legível ───────────────────────────────────────
  static const Map<String, String> _categoryLabels = {
    'user': 'Usuários',
    'users': 'Usuários',
    'property': 'Propriedades',
    'properties': 'Propriedades',
    'inspection': 'Vistorias',
    'financial': 'Financeiro',
    'reports': 'Relatórios',
    'settings': 'Configurações',
    'company': 'Empresas',
    'gallery': 'Galeria',
    'session': 'Sessões',
    'team': 'Times',
    'teams': 'Times',
    'kanban': 'Funil de Vendas',
    'crm': 'Funil de Vendas',
    'client': 'Clientes',
    'clients': 'Clientes',
    'key': 'Chaves',
    'keys': 'Chaves',
    'gamification': 'Gamificação',
    'rental': 'Aluguéis',
    'calendar': 'Calendário',
    'commission': 'Comissões',
    'commissions': 'Comissões',
    'note': 'Notas',
    'notes': 'Notas',
    'document': 'Documentos',
    'documents': 'Documentos',
    'visit': 'Relatório de Visita',
    'performance': 'Performance',
    'reward': 'Prêmios',
    'rewards': 'Prêmios',
    'asset': 'Patrimônio',
    'assets': 'Patrimônio',
    'mcmv': 'Minha Casa Minha Vida',
    'audit': 'Auditoria',
    'checklist': 'Checklists',
    'match': 'Matches',
    'subscription': 'Assinaturas',
    'notification': 'Notificações',
    'public': 'Site Público',
    'automation': 'Automação',
    'workflow': 'Workflows',
    'integration': 'Integrações',
    'integrations': 'Integrações',
    'api': 'API',
    'system': 'Sistema',
    'bi': 'Inteligência de Negócios',
    'marketing': 'Marketing',
    'custom-field': 'Campos Personalizados',
    'appointment': 'Agendamentos',
    'competition': 'Competições',
    'prize': 'Prêmios',
    'analytics': 'Análises',
    'public_analytics': 'Análise Multicanal',
    'condominium': 'Condomínios',
    'empreendimento': 'Empreendimentos',
    'whatsapp': 'WhatsApp',
    'insurance': 'Seguros',
    'credit_analysis': 'Análise de Crédito',
    'collection': 'Cobranças',
    'sale_unit': 'Unidades de Venda',
    'unit': 'Unidades (Filiais)',
    'units': 'Unidades (Filiais)',
    'proposal': 'Fichas de Proposta',
    'proposals': 'Fichas de Proposta',
    'sale_form': 'Fichas de Vendas',
    'sale_forms': 'Fichas de Vendas',
    'rental_form': 'Fichas de Locação',
    'rental_forms': 'Fichas de Locação',
    'ticket': 'Suporte e Tickets',
    'tickets': 'Suporte e Tickets',
    'check_in': 'Check-in',
  };

  // ─── Categorias → ícone Lucide ─────────────────────────────────────────
  static const Map<String, IconData> _categoryIcons = {
    'user': LucideIcons.users,
    'users': LucideIcons.users,
    'property': LucideIcons.house,
    'properties': LucideIcons.house,
    'inspection': LucideIcons.clipboardCheck,
    'financial': LucideIcons.wallet,
    'reports': LucideIcons.chartBar,
    'settings': LucideIcons.settings,
    'company': LucideIcons.building2,
    'gallery': LucideIcons.image,
    'session': LucideIcons.lock,
    'team': LucideIcons.usersRound,
    'teams': LucideIcons.usersRound,
    'kanban': LucideIcons.kanban,
    'crm': LucideIcons.kanban,
    'client': LucideIcons.contact,
    'clients': LucideIcons.contact,
    'key': LucideIcons.key,
    'keys': LucideIcons.key,
    'gamification': LucideIcons.trophy,
    'rental': LucideIcons.house,
    'calendar': LucideIcons.calendar,
    'commission': LucideIcons.banknote,
    'commissions': LucideIcons.banknote,
    'note': LucideIcons.stickyNote,
    'notes': LucideIcons.stickyNote,
    'document': LucideIcons.fileText,
    'documents': LucideIcons.fileText,
    'visit': LucideIcons.mapPin,
    'performance': LucideIcons.chartLine,
    'reward': LucideIcons.gift,
    'rewards': LucideIcons.gift,
    'asset': LucideIcons.landmark,
    'assets': LucideIcons.landmark,
    'mcmv': LucideIcons.house,
    'audit': LucideIcons.search,
    'checklist': LucideIcons.listChecks,
    'match': LucideIcons.target,
    'subscription': LucideIcons.creditCard,
    'notification': LucideIcons.bell,
    'public': LucideIcons.globe,
    'automation': LucideIcons.bot,
    'workflow': LucideIcons.zap,
    'integration': LucideIcons.plug,
    'integrations': LucideIcons.plug,
    'api': LucideIcons.link,
    'system': LucideIcons.cpu,
    'bi': LucideIcons.trendingUp,
    'marketing': LucideIcons.megaphone,
    'custom-field': LucideIcons.tag,
    'appointment': LucideIcons.calendarClock,
    'competition': LucideIcons.medal,
    'prize': LucideIcons.gift,
    'analytics': LucideIcons.chartPie,
    'public_analytics': LucideIcons.chartPie,
    'condominium': LucideIcons.building,
    'empreendimento': LucideIcons.building2,
    'whatsapp': LucideIcons.messageCircle,
    'insurance': LucideIcons.shield,
    'credit_analysis': LucideIcons.clipboardCheck,
    'collection': LucideIcons.creditCard,
    'sale_unit': LucideIcons.store,
    'unit': LucideIcons.building2,
    'units': LucideIcons.building2,
    'proposal': LucideIcons.fileSignature,
    'proposals': LucideIcons.fileSignature,
    'sale_form': LucideIcons.fileText,
    'sale_forms': LucideIcons.fileText,
    'rental_form': LucideIcons.fileText,
    'rental_forms': LucideIcons.fileText,
    'ticket': LucideIcons.ticket,
    'tickets': LucideIcons.ticket,
    'check_in': LucideIcons.mapPinCheck,
  };

  // ─── Ações (parte após ":") → rótulo curto PT ──────────────────────────
  static const Map<String, String> _actionLabels = {
    'view': 'Visualizar',
    'create': 'Criar',
    'update': 'Editar',
    'delete': 'Excluir',
    'read': 'Consultar',
    'approve': 'Aprovar',
    'reject': 'Rejeitar',
    'import': 'Importar',
    'export': 'Exportar',
    'manage': 'Gerenciar',
    'manage_permissions': 'Gerenciar permissões',
    'transfer': 'Transferir',
    'manage_visibility': 'Gerenciar visibilidade',
    'manage_members': 'Gerenciar membros',
    'manage_users': 'Gerenciar usuários',
    'view_history': 'Ver histórico',
    'view_analytics': 'Ver análises',
    'checkout': 'Registrar retirada',
    'return': 'Registrar devolução',
    'share': 'Compartilhar',
    'download': 'Baixar',
    'calculate': 'Calcular',
    'redeem': 'Solicitar resgate',
    'deliver': 'Marcar entregue',
    'link': 'Vincular',
    'manage_status': 'Gerenciar status',
    'view_team': 'Ver por equipe',
    'view_company': 'Ver da empresa',
    'compare': 'Comparar',
    'send': 'Enviar',
    'receive': 'Receber',
    'assign': 'Atribuir',
    'review': 'Revisar',
    'cancel': 'Cancelar',
    'configure': 'Configurar',
    'distribute': 'Distribuir',
    'approve_availability': 'Aprovar disponibilidade',
    'reject_availability': 'Recusar disponibilidade',
    'approve_publication': 'Aprovar publicação',
    'reject_publication': 'Recusar publicação',
    'manage_approval_settings': 'Config. de aprovação',
    'do': 'Fazer',
    'manage_settings': 'Configurações',
  };

  /// Rótulo legível da categoria. Tenta o mapa; deriva do nome se preciso.
  static String categoryLabel(String? category, [String? permissionName]) {
    final key = _norm(category);
    if (key.isNotEmpty && _categoryLabels.containsKey(key)) {
      return _categoryLabels[key]!;
    }
    // Deriva do prefixo do nome (formato "categoria:acao").
    if (permissionName != null && permissionName.contains(':')) {
      final prefix = _norm(permissionName.split(':').first);
      if (_categoryLabels.containsKey(prefix)) return _categoryLabels[prefix]!;
      return _humanize(prefix);
    }
    if (key.isEmpty || key == 'other' || key == 'null') {
      return 'Permissões Gerais';
    }
    return _humanize(key);
  }

  static IconData categoryIcon(String? category, [String? permissionName]) {
    final key = _norm(category);
    if (_categoryIcons.containsKey(key)) return _categoryIcons[key]!;
    if (permissionName != null && permissionName.contains(':')) {
      final prefix = _norm(permissionName.split(':').first);
      if (_categoryIcons.containsKey(prefix)) return _categoryIcons[prefix]!;
    }
    return LucideIcons.shieldCheck;
  }

  /// Rótulo curto da ação (parte após o primeiro ":") — usado em cada toggle.
  static String actionLabel(String permissionName) {
    final idx = permissionName.indexOf(':');
    if (idx < 0) return _humanize(permissionName);
    final action = _norm(permissionName.substring(idx + 1));
    if (_actionLabels.containsKey(action)) return _actionLabels[action]!;
    // tenta última parte (ex.: lead:view)
    final last = action.split(RegExp(r'[:_]')).last;
    if (_actionLabels.containsKey(last)) return _actionLabels[last]!;
    return _humanize(action);
  }

  static String _norm(String? s) =>
      (s ?? '').trim().toLowerCase().replaceAll('-', '_');

  static String _humanize(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[_\-:]'), ' ').trim();
    if (cleaned.isEmpty) return 'Geral';
    return cleaned
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
