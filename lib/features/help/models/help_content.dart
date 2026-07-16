// Conteúdo estático da Central de Ajuda — porte 1:1 do `FaqPage.tsx` do
// imobx-front (QUICK_LINKS, GUIDES e FAQ_CATEGORIES). Sem endpoint: são
// perguntas frequentes de uso do sistema, agrupadas por área.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';

class FaqItem {
  final String question;
  final String answer;

  const FaqItem({required this.question, required this.answer});
}

class FaqCategory {
  final String id;
  final String title;
  final String emoji;
  final List<FaqItem> items;

  const FaqCategory({
    required this.id,
    required this.title,
    required this.emoji,
    required this.items,
  });
}

class HelpQuickLink {
  final String label;
  final String description;
  final String route;
  final IconData icon;

  const HelpQuickLink({
    required this.label,
    required this.description,
    required this.route,
    required this.icon,
  });
}

class HelpGuide {
  final String id;
  final String title;
  final String summary;
  final IconData icon;
  final List<String> steps;
  final String ctaLabel;
  final String ctaRoute;

  const HelpGuide({
    required this.id,
    required this.title,
    required this.summary,
    required this.icon,
    required this.steps,
    required this.ctaLabel,
    required this.ctaRoute,
  });
}

/// Rota da tela de tickets (registrada centralmente no AppRoutes).
const String kHelpTicketsRoute = '/tickets';

const List<HelpQuickLink> helpQuickLinks = [
  HelpQuickLink(
    label: 'CRM / Kanban',
    description: 'Gerencie seus leads no funil',
    route: AppRoutes.kanban,
    icon: LucideIcons.squareKanban,
  ),
  HelpQuickLink(
    label: 'Imóveis',
    description: 'Cadastro e portfólio',
    route: AppRoutes.properties,
    icon: LucideIcons.home,
  ),
  HelpQuickLink(
    label: 'Fichas de Venda',
    description: 'Negociações e documentos',
    route: AppRoutes.saleForms,
    icon: LucideIcons.fileText,
  ),
  HelpQuickLink(
    label: 'Clientes',
    description: 'Base de contatos',
    route: AppRoutes.clients,
    icon: LucideIcons.contact,
  ),
  HelpQuickLink(
    label: 'Agenda',
    description: 'Compromissos e visitas',
    route: AppRoutes.calendar,
    icon: LucideIcons.calendar,
  ),
  HelpQuickLink(
    label: 'Suporte',
    description: 'Abrir um chamado',
    route: kHelpTicketsRoute,
    icon: LucideIcons.lifeBuoy,
  ),
];

const List<HelpGuide> helpGuides = [
  HelpGuide(
    id: 'novo-lead',
    title: 'Cadastrar e mover um lead no funil',
    summary: 'Do primeiro contato até a etapa certa do Kanban.',
    icon: LucideIcons.target,
    steps: [
      'Abra o CRM (Kanban) no menu e confira, no seletor do topo, se está no funil certo.',
      'Toque em "Novo lead" (ou no botão de adicionar na coluna de entrada do quadro).',
      'Preencha nome, telefone e origem do contato — a origem é o que alimenta os relatórios de campanha depois, então capriche nela.',
      'Salve. O card entra na coluna de entrada configurada para aquele funil/campanha.',
      'Arraste o card para a etapa que reflete a conversa (ex.: "Em atendimento", "Visita agendada").',
      'Abra o card para registrar anotações, agendar um retorno, anexar imóveis de interesse e ver todo o histórico de mudanças de etapa.',
      'Se o lead não vingar, marque como perdido com o motivo — ele sai das colunas normais, mas continua acessível na tela de Leads perdidos.',
    ],
    ctaLabel: 'Abrir o Kanban',
    ctaRoute: AppRoutes.kanban,
  ),
  HelpGuide(
    id: 'novo-imovel',
    title: 'Cadastrar um novo imóvel',
    summary: 'Registre o imóvel com fotos, características e publicação.',
    icon: LucideIcons.home,
    steps: [
      'Abra Imóveis no menu e toque em "Cadastrar imóvel".',
      'Preencha localização, tipo, valor e as características principais — quanto mais completo, melhor o imóvel aparece no site e nos portais.',
      'Faça o upload das fotos na ordem em que devem aparecer; a primeira vira a capa.',
      'Defina a captação (proprietário/corretor responsável) — isso alimenta o Relatório de Captações.',
      'Revise e salve. Se a empresa exige autorização do proprietário ou aprovação para disponibilizar/publicar, o imóvel entra na fila antes de ficar ativo.',
      'Campos protegidos (como valor) só mudam depois que um aprovador confirma a solicitação — a edição não vale na hora.',
    ],
    ctaLabel: 'Ir para Imóveis',
    ctaRoute: AppRoutes.properties,
  ),
  HelpGuide(
    id: 'ficha-venda',
    title: 'Gerar uma ficha de venda',
    summary: 'Formalize a negociação e emita os documentos.',
    icon: LucideIcons.fileText,
    steps: [
      'Se você acessa mais de uma imobiliária, confirme a empresa ativa — a ficha e o PDF são gerados na empresa selecionada.',
      'Abra Fichas de Venda no menu e toque em "Nova ficha".',
      'Selecione o imóvel e o cliente (ou cadastre o cliente na hora, se ainda não existir).',
      'Preencha valores, condições de pagamento, comissão e a data da venda.',
      'Confira os dados e gere a ficha — ela passa a valer para os dashboards de Fichas e para o cálculo de comissões.',
      'Baixe o PDF ou envie para assinatura digital. Se o download der erro 404, provavelmente a empresa ativa está errada: troque e tente de novo.',
    ],
    ctaLabel: 'Abrir Fichas de Venda',
    ctaRoute: AppRoutes.saleForms,
  ),
  HelpGuide(
    id: 'agendar-visita',
    title: 'Agendar uma visita e fazer check-in',
    summary: 'Marque o compromisso e comprove a presença no imóvel.',
    icon: LucideIcons.clipboardCheck,
    steps: [
      'Abra o card do lead no Kanban ou vá em Agenda e crie um novo compromisso.',
      'Escolha o tipo (visita), o imóvel, o cliente e a data/hora — você recebe um lembrete quando chegar perto.',
      'No dia, ao chegar ao imóvel, faça o Check-in pelo menu (Meu check-in) para registrar sua presença.',
      'O check-in tem uma janela de validade; se você esquecer de fechar/dar undo, o sistema avisa.',
      'A visita realizada fica no histórico do lead e conta para os relatórios de atividade da equipe.',
    ],
    ctaLabel: 'Abrir a Agenda',
    ctaRoute: AppRoutes.calendar,
  ),
  HelpGuide(
    id: 'abrir-chamado',
    title: 'Abrir um chamado de suporte',
    summary: 'Quando a dúvida não estiver aqui, fale com o time.',
    icon: LucideIcons.lifeBuoy,
    steps: [
      'Abra Suporte no menu e toque em "Abrir ticket".',
      'Descreva o problema com o máximo de detalhes: em que tela, o que você esperava e o que aconteceu.',
      'Inclua o passo a passo para reproduzir e o horário aproximado em que ocorreu — isso acelera muito a análise.',
      'Anexe prints que ajudem a entender o caso.',
      'Envie. Você acompanha as respostas pela conversa do próprio chamado e recebe as atualizações por e-mail.',
    ],
    ctaLabel: 'Abrir chamado',
    ctaRoute: kHelpTicketsRoute,
  ),
];

const List<FaqCategory> faqCategories = [
  FaqCategory(
    id: 'geral',
    title: 'Primeiros passos',
    emoji: '🚀',
    items: [
      FaqItem(
        question: 'Como navego entre as áreas do sistema?',
        answer:
            'Use o menu lateral. Ele agrupa os módulos por tema (Dashboard, Vendas & CRM, Imóveis, Financeiro, Locações etc.). Toque em um grupo para expandir e ver as telas disponíveis. O que aparece depende sempre das permissões do seu perfil e dos módulos que a sua imobiliária contratou.',
      ),
      FaqItem(
        question: 'Não encontro um menu que outro colega tem. Por quê?',
        answer:
            'Três coisas definem o que você enxerga: as permissões do seu perfil, o seu papel (corretor, gestor, admin, master) e os módulos contratados pela empresa. Se um colega vê uma tela que você não vê, quase sempre é diferença de permissão ou de papel. Fale com o administrador da sua imobiliária para ajustar seu acesso — nem tudo pode ser liberado por conta própria.',
      ),
      FaqItem(
        question: 'Como troco entre tema claro e escuro?',
        answer:
            'Abra as configurações pelo menu e escolha o tema nas preferências. A escolha fica salva no seu dispositivo, então vale para os próximos acessos.',
      ),
      FaqItem(
        question: 'Trabalho em mais de uma imobiliária. Como troco de empresa?',
        answer:
            'Use o seletor de empresa. Ao trocar, TODOS os dados passam a refletir a empresa selecionada: leads, imóveis, fichas, relatórios e até a geração de PDFs. Por isso, antes de cadastrar, editar ou emitir qualquer documento, confirme qual empresa está ativa — a maior parte dos erros de "sumiu" ou "gerou errado" é a empresa trocada.',
      ),
      FaqItem(
        question: 'O sistema funciona no celular?',
        answer:
            'Sim — este aplicativo cobre os fluxos principais do dia a dia em campo (leads, imóveis, agenda, check-in de visita). Algumas telas administrativas e de configuração são mais confortáveis no computador, pela versão web. Se um recurso ainda não aparece no app, use o navegador do celular.',
      ),
      FaqItem(
        question: 'Fiquei um tempo parado e o sistema pediu login de novo.',
        answer:
            'Por segurança, a sessão expira após um período de inatividade e ao detectar problemas de autenticação. Basta entrar novamente; nada que você já salvou se perde. Se isso acontecer com muita frequência mesmo em uso ativo, pode ser algo na rede — nesse caso, abra um chamado.',
      ),
    ],
  ),
  FaqCategory(
    id: 'crm',
    title: 'Leads e CRM (Kanban)',
    emoji: '🎯',
    items: [
      FaqItem(
        question: 'Como movo um lead entre as etapas do funil?',
        answer:
            'No quadro Kanban, arraste o card de uma coluna para outra: a etapa é atualizada na hora e o histórico do lead registra quem moveu e quando. Se preferir, abra o card e altere a etapa pelos detalhes. Toda mudança fica no histórico, então dá para reconstruir a jornada do lead depois.',
      ),
      FaqItem(
        question: 'Por que não vejo os leads dos outros corretores?',
        answer:
            'O quadro respeita um escopo de visibilidade: por padrão cada corretor vê apenas os próprios leads, para não misturar carteiras. Quem tem permissão de gestão pode alternar entre "meus" e "todos" e filtrar por responsável. Se você precisa acompanhar a equipe e só vê os seus, verifique com o administrador se seu perfil tem a visão ampliada liberada.',
      ),
      FaqItem(
        question: 'Um lead sumiu do quadro. Ele foi excluído?',
        answer:
            'Provavelmente não. Leads marcados como perdidos deixam de aparecer nas colunas normais para não poluir o funil, mas continuam guardados. Vá em Leads perdidos para encontrá-los, ver o motivo da perda e, se fizer sentido, recuperá-los para o funil. Exclusão de verdade é rara e costuma exigir permissão específica.',
      ),
      FaqItem(
        question: 'Como filtro e busco leads no quadro?',
        answer:
            'Use os filtros do Kanban: responsável, origem, campanha, período, etiquetas e mais — os filtros são combináveis e a contagem de cada coluna se ajusta ao que está selecionado. Vale lembrar que o funil esconde os perdidos, então a soma das colunas pode ser menor que o total de leads que entraram na campanha.',
      ),
      FaqItem(
        question: 'Tenho vários funis. Como vejo tudo junto?',
        answer:
            'Além de cada funil individual, existe a Visão Unificada (na versão web), que agrega as raias de todos os funis da empresa em uma tela só. É útil para gestão enxergar o volume geral sem entrar funil por funil.',
      ),
      FaqItem(
        question:
            'O que acontece com um lead quando ele é perdido pela primeira vez?',
        answer:
            'Dependendo da configuração do funil, a primeira perda pode disparar uma redistribuição automática do lead para outro corretor, dando uma segunda chance de atendimento. Esse comportamento é ligado/desligado por funil ou globalmente pelo gestor. Se você não quer que leads perdidos sejam redistribuídos, peça para revisar essa configuração.',
      ),
    ],
  ),
  FaqCategory(
    id: 'imoveis',
    title: 'Imóveis, Fichas e Publicação',
    emoji: '🏠',
    items: [
      FaqItem(
        question: 'Como cadastro e publico um novo imóvel?',
        answer:
            'Acesse Imóveis e toque em cadastrar. Preencha dados, fotos e características e defina a captação. Se a empresa exige aprovação para disponibilizar ou publicar, o imóvel entra numa fila antes de ficar ativo no site/portais; quando o sistema de votação por aprovadores está ligado, ele só libera após o quórum mínimo de votos.',
      ),
      FaqItem(
        question: 'Editei um campo do imóvel e ele não mudou. O que houve?',
        answer:
            'Campos protegidos (como valor, responsável ou situação) não mudam na hora: sua edição vira uma solicitação de aprovação enviada a quem tem alçada. A alteração só passa a valer depois que o aprovador confirmar. Isso existe justamente para evitar mudanças sensíveis sem revisão. Gestores e aprovadores costumam editar esses campos direto.',
      ),
      FaqItem(
        question: 'Quem define quais campos são protegidos e quem aprova?',
        answer:
            'É configurado em Imóveis › Aprovações, na tela de configuração (regras de aprovação, campos protegidos e lista de aprovadores). Lá se liga o fluxo, escolhe quais campos exigem aprovação e quem pode aprovar disponibilidade e publicação. Só quem gerencia configurações de aprovação acessa essa tela.',
      ),
      FaqItem(
        question: 'A foto/imagem do imóvel não apareceu no portal. E agora?',
        answer:
            'Na maioria das vezes não é a imagem que "não subiu": é o portal que parou de puxar o feed. O feed é lido pelo portal (modelo pull), então quando ele para de puxar, imagens novas não aparecem mesmo estando certas no sistema. Confira a saúde da integração/feed na área de integrações; quando o feed volta a ser lido, as mídias aparecem. Editar o imóvel costuma "bumpar" a data de atualização e ajudar.',
      ),
      FaqItem(
        question: 'Não consigo baixar o PDF da ficha (erro 404).',
        answer:
            'Se você acessa mais de uma empresa, o sistema pode estar tentando gerar o PDF na empresa errada. Confirme a empresa ativa e tente de novo — é a causa mais comum desse 404. Persistindo, abra um chamado informando a ficha e a empresa; pode ser um vínculo específico daquele registro.',
      ),
      FaqItem(
        question: 'Como gero uma ficha de venda, proposta ou locação?',
        answer:
            'Cada tipo tem sua área (Fichas de Venda, Fichas Proposta, Fichas de Locação). Crie uma nova ficha, selecione imóvel e cliente, preencha valores e condições e gere. A ficha alimenta os dashboards correspondentes e, no caso de venda, o cálculo de comissões. Confirme a empresa ativa antes de gerar.',
      ),
    ],
  ),
  FaqCategory(
    id: 'agenda',
    title: 'Agenda, Visitas e Check-in',
    emoji: '📅',
    items: [
      FaqItem(
        question: 'Como agendo uma visita ou compromisso?',
        answer:
            'Você pode criar o compromisso direto na Agenda ou a partir do card do lead no Kanban, o que já vincula a visita ao contato. Escolha tipo, imóvel, cliente e data/hora. Perto do horário, o sistema mostra um lembrete (e você pode adiar em alguns minutos, se precisar).',
      ),
      FaqItem(
        question: 'Para que serve o check-in?',
        answer:
            'O check-in comprova que o corretor esteve no imóvel na visita. Você registra pelo menu Check-in (Meu check-in), e a gestão acompanha pela Lista de Check-in. Ele serve tanto para o histórico do lead quanto para relatórios de atividade da equipe.',
      ),
      FaqItem(
        question: 'Esqueci de encerrar/desfazer um check-in. Tem problema?',
        answer:
            'O check-in tem uma janela de validade e o sistema avisa quando ele fica pendente ou prestes a expirar, para você não esquecer aberto. Se precisar corrigir, use a opção de desfazer no próprio check-in. Casos que já passaram da janela podem exigir ajuste pela gestão.',
      ),
      FaqItem(
        question:
            'Recebi um lembrete de agendamento. Ele reaparece se eu fechar?',
        answer:
            'Cada agendamento é tratado de forma independente: ao fechar um lembrete, ele não fica reaparecendo, mas novos agendamentos sempre geram novos avisos. Há também a opção "lembrar novamente", que adia o aviso por alguns minutos em vez de dispensá-lo.',
      ),
    ],
  ),
  FaqCategory(
    id: 'documentos',
    title: 'Documentos e Assinaturas',
    emoji: '✍️',
    items: [
      FaqItem(
        question: 'Como envio um documento para assinatura digital?',
        answer:
            'A assinatura digital é integrada à geração de fichas/documentos: ao gerar, você pode enviar para assinatura em vez de só baixar o PDF. O envio usa a configuração de assinatura da sua empresa, então cada imobiliária assina com a própria conta/credencial.',
      ),
      FaqItem(
        question: 'Tentei enviar para assinatura e foi bloqueado. Por quê?',
        answer:
            'A assinatura depende de uma configuração ativa por empresa. Se a credencial de assinatura da sua imobiliária não estiver ativa/configurada, o envio é bloqueado de propósito (não há um fallback genérico). Peça ao administrador para revisar a configuração de assinatura da empresa.',
      ),
      FaqItem(
        question: 'Onde ficam guardados os documentos e modelos?',
        answer:
            'Em Documentos › Biblioteca você encontra os arquivos e modelos da empresa; há também as Pastas CRM para organizar documentos ligados ao relacionamento com clientes. O que você acessa depende das permissões do seu perfil.',
      ),
    ],
  ),
  FaqCategory(
    id: 'whatsapp',
    title: 'WhatsApp e Integrações',
    emoji: '💬',
    items: [
      FaqItem(
        question: 'Como conecto o WhatsApp da imobiliária?',
        answer:
            'A conexão é feita na área de Integrações e precisa de um administrador para configurar e autenticar o número. Depois de conectado, as conversas e o atendimento por IA passam a funcionar conforme o plano contratado. Um mesmo número atende a empresa toda; a distribuição das conversas segue as regras de atendimento configuradas.',
      ),
      FaqItem(
        question: 'A IA de atendimento respondeu algo errado. Como ajusto?',
        answer:
            'As respostas da IA usam a base de conhecimento da sua empresa (uma base própria por imobiliária). Quanto mais completa e correta essa base, melhores as respostas. Peça ao administrador para revisar e complementar o conteúdo — os ajustes valem para as próximas conversas, não retroagem às antigas.',
      ),
      FaqItem(
        question:
            'Os números de leads/campanha não batem com o painel de anúncios.',
        answer:
            'É esperado divergir um pouco, porque cada painel conta de um jeito. Os cards de campanha priorizam as conversões da própria plataforma de anúncios (para bater 1:1 com o painel dela), enquanto o CRM conta leads que entraram no funil — e ainda há o atraso de conversão (conversion lag), em que uma conversão é atribuída dias depois. Diferença pequena é normal; diferença grande e persistente, registre um chamado.',
      ),
      FaqItem(
        question: 'Os contatos únicos de WhatsApp não batem com o GA4.',
        answer:
            'Assim como nas campanhas, GA4 e CRM medem de formas diferentes e por janelas diferentes. Há uma integração específica para aproximar os contatos únicos do que o painel do GA4 mostra, mas pequenas diferenças de contagem entre as ferramentas são normais.',
      ),
    ],
  ),
  FaqCategory(
    id: 'relatorios',
    title: 'Relatórios e Desempenho',
    emoji: '📊',
    items: [
      FaqItem(
        question: 'Onde vejo o desempenho da equipe e dos corretores?',
        answer:
            'Em Performance você pode Comparar Corretores e Comparar Equipes, e nos Dashboards (Geral, Fichas de Venda, Fichas Proposta, SDR) tem as visões consolidadas. O que aparece depende do seu papel: gestores enxergam a equipe, corretores geralmente veem os próprios números.',
      ),
      FaqItem(
        question: 'O que é o Relatório de Captações?',
        answer:
            'É o relatório (em Imóveis › Relatório de Captações, para gestão) que acompanha as captações de imóveis. Ele inclui, entre outras coisas, uma seção de trocas de responsável, mostrando quando a captação mudou de corretor — útil para auditar mudanças na carteira.',
      ),
      FaqItem(
        question: 'Por que meus números diferem dos de outra tela/painel?',
        answer:
            'Telas diferentes podem contar coisas diferentes (leads que entraram x leads ativos no funil x conversões da plataforma de anúncios) e recortar por períodos distintos. Antes de concluir que há erro, confira o filtro de período, a empresa ativa e se a tela inclui ou exclui perdidos. Se ainda assim não fizer sentido, abra um chamado descrevendo as duas telas.',
      ),
    ],
  ),
  FaqCategory(
    id: 'conta',
    title: 'Minha conta e notificações',
    emoji: '👤',
    items: [
      FaqItem(
        question: 'Como altero minha senha?',
        answer:
            'Acesse as configurações do seu perfil. Se esqueceu a senha e nem consegue entrar, use "Esqueci minha senha" na tela de login para receber o link de redefinição por e-mail. Se o e-mail não chegar, confira a caixa de spam e se o endereço cadastrado está correto.',
      ),
      FaqItem(
        question: 'Como atualizo meus dados de perfil (nome, foto, contato)?',
        answer:
            'Abra o seu Perfil no menu. Nome, foto e contato que você define ali são os que aparecem para a equipe e podem sair nos documentos gerados, então mantenha atualizado.',
      ),
      FaqItem(
        question: 'Recebo notificações demais ou de menos. Dá para ajustar?',
        answer:
            'As notificações seguem suas preferências de usuário e as permissões do perfil. Ajuste o que puder nas preferências; regras que valem para a empresa toda (quem recebe o quê) são definidas pelo administrador. Notificações por e-mail de tickets, por exemplo, vão só para os envolvidos no chamado, não para a base inteira.',
      ),
      FaqItem(
        question: 'Preciso ativar as notificações do app?',
        answer:
            'Sim: o sistema pede permissão de notificação no primeiro acesso. Se você negou e quer reativar, libere nas configurações do celular (Ajustes › Notificações). Sem isso, os avisos de agendamentos, leads e tickets não chegam em tempo real.',
      ),
    ],
  ),
];

/// Normaliza texto para busca sem acento (paridade com o `normalize` do web).
String helpNormalize(String value) {
  const from = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  var out = value.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out;
}
