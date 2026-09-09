import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Metadados de exibição para categorias e ações de permissão — paridade com
/// `imobx-front/src/utils/permissionCategoryMapping.ts`, mas usando ícones
/// Lucide (sem emojis, conforme o padrão visual da casa) e rótulos em PT.
class PermissionMeta {
  PermissionMeta._();

  // ─── Categorias → rótulo legível ───────────────────────────────────────
  // Paridade EXATA com o web (`permissionCategoryMapping.ts` → CATEGORY_LABELS):
  // os grupos precisam bater 1:1 com a tela de editar usuário da web.
  static const Map<String, String> _categoryLabels = {
    'user': 'Gestão de Usuários',
    'users': 'Gestão de Usuários',
    'property': 'Gestão de Propriedades',
    'properties': 'Gestão de Propriedades',
    'inspection': 'Gestão de Vistorias',
    'financial': 'Gestão Financeira',
    'reports': 'Relatórios',
    'settings': 'Configurações',
    'company': 'Gestão de Empresas',
    'gallery': 'Galeria',
    'session': 'Gestão de Sessões',
    'team': 'Gestão de Times',
    'teams': 'Gestão de Times',
    'kanban': 'Funil de Vendas',
    'crm': 'Funil de Vendas',
    'client': 'Gestão de Clientes',
    'clients': 'Gestão de Clientes',
    'key': 'Gestão de Chaves',
    'keys': 'Gestão de Chaves',
    'gamification': 'Gamificação',
    'rental': 'Gestão de Aluguéis',
    'calendar': 'Calendário e Agendamentos',
    'commission': 'Gestão de Comissões',
    'commissions': 'Gestão de Comissões',
    'note': 'Gestão de Notas',
    'notes': 'Gestão de Notas',
    'document': 'Gestão de Documentos',
    'documents': 'Gestão de Documentos',
    'visit': 'Relatório de Visita',
    'performance': 'Painel de Performance',
    'reward': 'Gestão de Prêmios',
    'rewards': 'Gestão de Prêmios',
    'asset': 'Gestão Patrimonial',
    'assets': 'Gestão Patrimonial',
    'mcmv': 'Minha Casa Minha Vida (MCMV)',
    'audit': 'Auditoria',
    'checklist': 'Gestão de Checklists',
    'match': 'Sistema de Matches',
    'subscription': 'Gestão de Assinaturas',
    'subscriptions': 'Gestão de Assinaturas',
    'notification': 'Notificações',
    'public': 'Site Público',
    'public_site': 'Site Público',
    'automation': 'Automação',
    'workflow': 'Automação de Workflows',
    'integration': 'Integrações',
    'integrations': 'Integrações',
    'api': 'API e Integrações',
    'system': 'Sistema',
    'bi': 'Inteligência de Negócios',
    'business-intelligence': 'Inteligência de Negócios',
    'marketing': 'Marketing',
    'custom-field': 'Campos Personalizados',
    'appointment': 'Agendamentos',
    'competition': 'Competições',
    'prize': 'Prêmios',
    'analytics': 'Análises e Relatórios',
    'public_analytics': 'Análise Multicanal',
    'condominium': 'Gestão de Condomínios',
    'condominiums': 'Gestão de Condomínios',
    'empreendimento': 'Gestão de Empreendimentos',
    'empreendimentos': 'Gestão de Empreendimentos',
    'whatsapp': 'WhatsApp',
    'insurance': 'Gestão de Seguros',
    'credit_analysis': 'Análise de Crédito',
    'collection': 'Gestão de Cobranças',
    'sale_unit': 'Gestão de unidades de venda',
    'sale_units': 'Gestão de unidades de venda',
    'unit': 'Gestão de Unidades (Filiais)',
    'units': 'Gestão de Unidades (Filiais)',
    'proposal': 'Gestão de fichas de proposta',
    'proposals': 'Gestão de fichas de proposta',
    'sale_form': 'Gestão de fichas de vendas',
    'sale_forms': 'Gestão de fichas de vendas',
    'rental_form': 'Gestão de fichas de locação',
    'rental_forms': 'Gestão de fichas de locação',
    'locacao_controllership': 'Controladoria da Locação',
    'locacao_contract': 'Contratos de Locação',
    'locacao_kanban': 'Esteira da Locação',
    'locacao_pipeline': 'CRM Comercial da Locação',
    'locacao_key': 'Chaveiro da Locação',
    'locacao_config': 'Configurações da Locação',
    'locacao_attachment': 'Anexos da Locação',
    'lead_distribution': 'Distribuição de Leads',
    'backup': 'Backups',
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
    'subscriptions': LucideIcons.creditCard,
    'condominiums': LucideIcons.building,
    'empreendimentos': LucideIcons.building2,
    'sale_units': LucideIcons.store,
    'business-intelligence': LucideIcons.trendingUp,
    'public_site': LucideIcons.globe,
    'backup': LucideIcons.databaseBackup,
    'lead_distribution': LucideIcons.split,
    'locacao_controllership': LucideIcons.chartBar,
    'locacao_contract': LucideIcons.fileText,
    'locacao_kanban': LucideIcons.kanban,
    'locacao_pipeline': LucideIcons.house,
    'locacao_key': LucideIcons.key,
    'locacao_config': LucideIcons.settings,
    'locacao_attachment': LucideIcons.paperclip,
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

  /// Descrição amigável do que a permissão LIBERA — paridade 1:1 com o web
  /// (`permissionDescriptions.ts`). Nunca mostra o nome técnico do banco.
  static const Map<String, String> _permissionDescriptions = {
    // Gestão de Times
    'team:view': 'Visualizar equipes',
    'team:create': 'Criar equipes',
    'team:update': 'Editar equipes',
    'team:delete': 'Excluir equipes',
    // Gestão de Usuários
    'user:view': 'Visualizar usuários',
    'user:create': 'Criar usuários',
    'user:update': 'Editar usuários',
    'user:transfer': 'Transferir usuário entre empresas',
    'user:delete': 'Excluir usuários',
    // Gestão de Clientes
    'client:view': 'Visualizar clientes',
    'client:create': 'Criar clientes',
    'client:update': 'Editar clientes',
    'client:delete': 'Excluir clientes',
    // Gestão de Imóveis
    'property:view': 'Visualizar imóveis',
    'property:create': 'Criar imóveis',
    'property:update': 'Editar imóveis',
    'property:delete': 'Excluir imóveis',
    'property:import': 'Importar imóveis em lote',
    'property:export': 'Exportar imóveis em lote',
    'property:approve_availability': 'Aprovar disponibilidade de imóveis',
    'property:reject_availability': 'Rejeitar disponibilidade de imóveis',
    'property:approve_publication': 'Aprovar publicação de imóveis no site',
    'property:reject_publication': 'Rejeitar publicação de imóveis no site',
    'property:manage_approval_settings':
        'Gerenciar configurações de aprovação de imóveis',
    'property:download_images': 'Baixar imagens do imóvel',
    // Gestão de Vistorias
    'inspection:view': 'Visualizar vistorias',
    'inspection:create': 'Criar vistorias',
    'inspection:update': 'Editar vistorias',
    'inspection:delete': 'Excluir vistorias',
    // Gestão de Chaves
    'key:view': 'Visualizar chaves',
    'key:create': 'Criar chaves',
    'key:update': 'Editar chaves',
    'key:delete': 'Excluir chaves',
    // Gestão de Locações / Aluguéis
    'rental:view': 'Visualizar locações e contratos',
    'rental:create': 'Criar locações',
    'rental:update': 'Editar locações',
    'rental:delete': 'Excluir locações',
    'rental:approve': 'Aprovar locações e contratos',
    'rental:reject': 'Rejeitar locações e contratos',
    'rental:read': 'Consultar dados de locações',
    'rental:manage': 'Gerenciar locações',
    'rental:checkout': 'Registrar retirada de chaves (locação)',
    'rental:return': 'Registrar devolução de chaves (locação)',
    'rental:manage_payments': 'Gerenciar pagamentos de locações',
    'rental:manage_workflows': 'Gerenciar fluxos de trabalho (locações)',
    'rental:view_dashboard': 'Visualizar painel de locações',
    'rental:view_financials': 'Visualizar dados financeiros das locações',
    // Módulo Locação — famílias próprias
    'locacao_controllership:view': 'Visualizar controladoria da locação',
    'locacao_controllership:create':
        'Criar registros na controladoria da locação',
    'locacao_controllership:edit': 'Editar controladoria da locação',
    'locacao_contract:view': 'Visualizar contratos de locação',
    'locacao_contract:generate': 'Gerar contratos de locação',
    'locacao_contract:approve': 'Aprovar contratos de locação',
    'rental_form:approve': 'Decidir aprovação de fichas',
    'locacao_kanban:view_own': 'Visualizar a esteira da locação',
    'locacao_kanban:create': 'Criar cards na esteira da locação',
    'locacao_kanban:move': 'Mover cards na esteira da locação',
    'locacao_kanban:configure':
        'Configurar a esteira da locação (avanço forçado)',
    'locacao_pipeline:view': 'Visualizar CRM comercial da locação',
    'locacao_pipeline:create': 'Criar leads no CRM comercial da locação',
    'locacao_pipeline:edit': 'Editar leads no CRM comercial da locação',
    'locacao_pipeline:delete': 'Excluir leads no CRM comercial da locação',
    'locacao_key:view': 'Visualizar chaveiro e retiradas de chaves',
    'locacao_key:manage': 'Cadastrar e editar chaves do chaveiro',
    'locacao_key:checkout': 'Retirar e devolver chaves (recepção)',
    'locacao_config:view': 'Visualizar configurações da locação',
    'locacao_config:manage':
        'Gerenciar configurações da locação (cláusulas, garantias, critérios)',
    'locacao_attachment:view': 'Visualizar e baixar anexos da locação',
    'locacao_attachment:create': 'Enviar anexos da locação',
    'locacao_attachment:delete': 'Excluir anexos da locação',
    'lead_distribution:view': 'Visualizar webhooks de ficha',
    'lead_distribution:manage_config': 'Configurar webhooks de ficha',
    // Gestão Financeira
    'financial:view': 'Visualizar registros financeiros',
    'financial:create': 'Criar registros financeiros',
    'financial:update': 'Editar registros financeiros',
    'financial:delete': 'Excluir registros financeiros',
    'financial:rh':
        'RH: leitura de equipes, elegibilidade, repasses e comissões',
    'financial:marketing':
        'Marketing: despesas com centro de custo de marketing',
    // Kanban
    'kanban:view': 'Visualizar quadros Kanban',
    'kanban:create': 'Criar quadros Kanban',
    'kanban:export': 'Exportar cards e negociações do funil (planilha XLSX/CSV)',
    'kanban:import': 'Importar negociações para o funil (planilha XLSX/CSV)',
    'kanban:update': 'Editar quadros Kanban',
    'kanban:delete': 'Excluir quadros Kanban',
    'kanban:view_history': 'Visualizar histórico do Kanban',
    'kanban:manage_validations_actions':
        'Gerenciar validações e ações do Kanban',
    'kanban:manage_column_cadence':
        'Configurar cadência WhatsApp automática por coluna no Kanban',
    'kanban:project:create': 'Criar projetos Kanban',
    'kanban:view_analytics':
        'Visualizar métricas e analytics do Funil de Vendas',
    'kanban:view_transferred_tasks':
        'Ver e editar cards do funil transferidos por mim',
    'kanban:manage_users': 'Gerenciar permissões dos usuários no Kanban',
    'kanban:view_all_teams':
        'Ver todos os funis, tarefas e subtarefas da empresa (uso típico: SDR/pré-atendimento)',
    'kanban:view_global_funnel':
        'Acessar o Funil Global da empresa (quadro consolidado em raias por funil)',
    'backup:view':
        'Acessar central de backups (leads e imóveis), baixar e repetir exportações',
    // Gestão de fichas de proposta
    'proposal:view':
        'Visualizar fichas de proposta que criou ou em que foi vinculado',
    'proposal:view_team':
        'Ver também fichas da equipe (criador ou participante no escopo das equipes)',
    'proposal:view_all': 'Visualizar todas as fichas de proposta da empresa',
    'proposal:create': 'Criar fichas de proposta',
    'proposal:update': 'Editar fichas de proposta',
    'proposal:delete': 'Excluir fichas de proposta',
    'proposal:export': 'Exportar fichas de proposta',
    'proposal:view_dashboard':
        'Acessar dashboard de fichas de proposta (KPIs, funil e rankings)',
    'proposal:generate': 'Gerar proposta com IA',
    // Gestão de fichas de vendas
    'sale_form:view':
        'Visualizar fichas de venda que criou ou em que foi vinculado',
    'sale_form:view_team':
        'Ver também fichas da equipe (criador ou participante no escopo das equipes)',
    'sale_form:view_all': 'Visualizar todas as fichas de venda da empresa',
    'sale_form:create': 'Criar fichas de venda',
    'sale_form:update': 'Editar fichas de venda',
    'sale_form:delete': 'Excluir fichas de venda',
    'sale_form:export': 'Exportar fichas de venda',
    'sale_form:view_dashboard':
        'Acessar dashboard de fichas de venda (KPIs, funil e rankings)',
    'sale_form:manage_mandatory_signers':
        'Configurar signatários obrigatórios para fichas de venda e propostas',
    // Unidades (filiais)
    'unit:view': 'Visualizar unidades (filiais)',
    'unit:manage': 'Gerenciar unidades (filiais) e seus gestores',
    'sale_unit:manage':
        'Gerenciar unidades de venda (vínculos, visibilidade e configurações da unidade)',
    // Gestão de fichas de locação
    'rental_form:view':
        'Visualizar fichas de locação que criou ou em que foi vinculado',
    'rental_form:view_team':
        'Ver também fichas de locação da equipe (criador ou participante no escopo das equipes)',
    'rental_form:view_all': 'Visualizar todas as fichas de locação da empresa',
    'rental_form:create': 'Criar fichas de locação',
    'rental_form:update': 'Editar fichas de locação',
    'rental_form:delete': 'Excluir fichas de locação',
    'rental_form:export': 'Exportar fichas de locação',
    // Relatório de Visita
    'visit:view': 'Visualizar relatórios de visita (próprios)',
    'visit:create': 'Criar relatórios de visita',
    'visit:update': 'Editar relatórios de visita e gerar link de assinatura',
    'visit:delete': 'Excluir relatórios de visita',
    'visit:manage': 'Gestão de visitas (ver todos os relatórios da empresa)',
    // Check-in por localização
    'check_in:do': 'Fazer check-in por localização',
    'check_in:view': 'Visualizar check-ins',
    'check_in:manage_settings':
        'Configurar check-in (raio, duração, localização)',
    // Gamificação
    'gamification:view': 'Visualizar gamificação',
    'gamification:create': 'Criar gamificação',
    'gamification:update': 'Editar gamificação',
    'gamification:delete': 'Excluir gamificação',
    // Competições
    'competition:view': 'Visualizar competições',
    'competition:create': 'Criar competições',
    'competition:edit': 'Editar competições',
    'competition:delete': 'Excluir competições',
    'competition:manage': 'Gerenciar competições',
    // Prêmios
    'prize:view': 'Visualizar prêmios',
    'prize:create': 'Criar prêmios',
    'prize:edit': 'Editar prêmios',
    'prize:delete': 'Excluir prêmios',
    'prize:deliver': 'Marcar prêmio como entregue',
    // Sistema de Resgates (Rewards)
    'reward:view': 'Visualizar prêmios para resgate',
    'reward:create': 'Criar prêmios para resgate',
    'reward:update': 'Editar prêmios para resgate',
    'reward:delete': 'Excluir prêmios para resgate',
    'reward:redeem': 'Solicitar resgate de prêmios',
    'reward:approve': 'Aprovar/Rejeitar resgates',
    'reward:deliver': 'Marcar resgate como entregue',
    // Notas
    'note:view': 'Visualizar notas',
    'note:create': 'Criar notas',
    'note:update': 'Editar notas',
    'note:delete': 'Excluir notas',
    'note:share': 'Compartilhar notas',
    // Comissões
    'commission:view': 'Visualizar comissões',
    'commission:create': 'Criar comissões',
    'commission:update': 'Editar comissões',
    'commission:delete': 'Excluir comissões',
    // Sessões
    'session:view': 'Visualizar sessões',
    'session:create': 'Criar sessões',
    'session:update': 'Editar sessões',
    'session:delete': 'Excluir sessões',
    // Assinaturas
    'subscriptions:view': 'Visualizar assinaturas',
    'subscriptions:create': 'Criar assinaturas',
    'subscriptions:update': 'Editar assinaturas',
    'subscriptions:delete': 'Excluir assinaturas',
    // Análise de Crédito
    'credit_analysis:view': 'Visualizar análises de crédito',
    'credit_analysis:create': 'Criar análises de crédito',
    'credit_analysis:review': 'Revisar análises de crédito',
    // Régua de Cobrança
    'collection:view': 'Visualizar régua de cobrança',
    'collection:manage': 'Gerenciar régua de cobrança',
    // Suporte (tickets)
    'ticket:view': 'Visualizar tickets de suporte que abriu',
    'ticket:create':
        'Abrir tickets de suporte para a equipe de desenvolvimento',
    // Performance
    'performance:view': 'Visualizar performance própria',
    'performance:compare':
        'Comparar performance (inclui visualização própria, de equipe e da empresa)',
    'performance:view_team': 'Visualizar performance da equipe',
    'performance:view_company': 'Visualizar performance da empresa',
  };

  /// Descrição do que a permissão libera. Usa o mapa curado (paridade com o
  /// web); se não houver, cai para a [fallback] do backend e, por fim, deriva
  /// "Categoria · Ação". Nunca expõe o nome técnico do banco.
  static String permissionDescription(String permissionName, {String? fallback}) {
    final key = permissionName.trim();
    final mapped = _permissionDescriptions[key];
    if (mapped != null) return mapped;
    final fb = fallback?.trim();
    if (fb != null && fb.isNotEmpty) return fb;
    if (key.contains(':')) {
      return '${categoryLabel(key.split(':').first, key)} · ${actionLabel(key)}';
    }
    return actionLabel(key);
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
