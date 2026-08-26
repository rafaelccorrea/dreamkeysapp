import 'kanban_message_vars.dart';

/// De onde veio o modelo — a etiqueta que o corretor lê na linha.
enum KanbanMessageSource {
  /// Modelo local do app (sempre existe, mesmo sem permissão de WhatsApp).
  local,

  /// Cadência configurada NA COLUNA atual do funil
  /// (`GET /kanban/columns/:id/cadence` → `messageText`).
  cadence,

  /// Biblioteca "mensagem pronta" da empresa
  /// (`GET /whatsapp/unofficial/quick-messages`).
  library,

  /// Sem modelo — o corretor escreve do zero.
  blank,
}

/// Um item da lista de modelos do sheet.
class KanbanMessageTemplate {
  const KanbanMessageTemplate({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
  });

  final String id;
  final String title;

  /// Texto JÁ interpolado (o sheet nunca mostra `{{token}}` que ele conhece).
  final String body;

  final KanbanMessageSource source;

  /// Prévia de uma linha para a linha da lista.
  String get preview => body.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Modelos LOCAIS de primeiro contato / retomada.
///
/// Ficam no app de propósito: a biblioteca da empresa
/// (`whatsapp_quick_messages`) exige `whatsapp:view`, o seed só rodou para
/// empresas antigas e empresa nova nasce com a lista VAZIA. Sem esse conjunto
/// o corretor abriria o sheet sem nenhuma opção.
///
/// Nome do lead entra pelo token oficial `{{clientFirstName}}` (mesma língua
/// do backend) — e SÓ quando existe nome de gente (`hasRealName`); imóvel e
/// corretor entram como TEXTO montado aqui, porque o interpolador do backend
/// não tem variável para nenhum dos dois.
class KanbanWhatsAppTemplates {
  const KanbanWhatsAppTemplates._();

  static List<KanbanMessageTemplate> build(KanbanMessageVars vars) {
    final property = vars.propertyLabel?.trim();
    final hasProperty = property != null && property.isNotEmpty;

    // Trechos que só existem quando há imóvel vinculado — nada de frase
    // pela metade quando o card não tem imóvel.
    final sobreImovel = hasProperty ? ' sobre o imóvel $property' : '';
    final noImovel = hasProperty ? ' no imóvel $property' : '';
    final doImovel = hasProperty ? ' do imóvel $property' : '';
    final aoImovel = hasProperty ? ' ao imóvel $property' : '';
    // Sem imóvel vinculado a pergunta do pós-visita ficaria oca
    // ("O que você achou?") — cai na própria visita.
    final daVisita = hasProperty ? ' do imóvel $property' : ' da visita';

    // Saudação: só chama pelo nome quando existe NOME DE GENTE. Sem cliente
    // e sem contato, `{{clientFirstName}}` cairia no título do card e o lead
    // receberia "Olá Lead, tudo bem?" — melhor cumprimentar sem nome.
    final n = vars.hasRealName ? ' {{clientFirstName}}' : '';

    final broker = vars.brokerFirstName;
    // Sem "o/a" e sem "corretor(a)": a assinatura precisa servir a qualquer
    // pessoa do time sem concordância de gênero remendada com parênteses.
    final assinatura =
        (broker == null || broker.isEmpty) ? '' : ' Aqui é $broker.';

    final raw = <KanbanMessageTemplate>[
      KanbanMessageTemplate(
        id: 'local:primeiro-contato',
        title: 'Primeiro contato',
        source: KanbanMessageSource.local,
        body: 'Olá$n, tudo bem?$assinatura '
            'Recebi seu interesse$noImovel e queria entender melhor o que '
            'você procura. Podemos conversar por aqui?',
      ),
      KanbanMessageTemplate(
        id: 'local:retomada',
        title: 'Retomar contato',
        source: KanbanMessageSource.local,
        body: 'Oi$n, tudo certo? '
            'Passando para retomar nossa conversa$sobreImovel. '
            'Ainda faz sentido para você neste momento?',
      ),
      KanbanMessageTemplate(
        id: 'local:visita',
        title: 'Convidar para visita',
        source: KanbanMessageSource.local,
        body: 'Olá$n! Consigo agendar uma visita$aoImovel '
            'ainda esta semana. Você prefere durante o dia ou no fim da tarde?',
      ),
      KanbanMessageTemplate(
        id: 'local:perfil',
        title: 'Entender o que procura',
        source: KanbanMessageSource.local,
        body: 'Oi$n! Para eu separar as melhores opções, '
            'me confirma três coisas: bairro de preferência, quantos quartos '
            'e o valor que você tem em mente?',
      ),
      KanbanMessageTemplate(
        id: 'local:pos-visita',
        title: 'Depois da visita',
        source: KanbanMessageSource.local,
        body: 'Oi$n! O que você achou$daVisita? '
            'Seu retorno me ajuda a acertar em cheio nas próximas opções.',
      ),
      KanbanMessageTemplate(
        id: 'local:negociacao',
        title: 'Andamento da negociação',
        source: KanbanMessageSource.local,
        body: 'Olá$n, tudo bem? '
            'Sobre a negociação$doImovel: ficou alguma dúvida que eu possa '
            'esclarecer para seguirmos com a proposta?',
      ),
    ];

    // A interpolação acontece uma vez só, aqui — o sheet recebe texto pronto.
    return raw
        .map(
          (t) => KanbanMessageTemplate(
            id: t.id,
            title: t.title,
            body: vars.apply(t.body),
            source: t.source,
          ),
        )
        .toList();
  }
}
