import 'package:intl/intl.dart';

import '../models/kanban_models.dart';

/// Interpolação das variáveis `{{...}}` das mensagens do funil.
///
/// O vocabulário é o MESMO que o backend já fala em
/// `kanban-column-cadence.helpers.ts#applyCadenceTemplate` e
/// `kanban-action-executor.service.ts#applyTemplate` — nada de token novo:
/// uma mensagem escrita na web (cadência da coluna / ação da coluna) precisa
/// renderizar igual quando o corretor a dispara pela mão, aqui no app.
///
/// Duas divergências DELIBERADAS, por serem texto lido por gente:
/// • `{{taskDueDate}}` sai em `dd/MM/yyyy` (o backend manda ISO, ilegível
///   dentro de uma mensagem de WhatsApp);
/// • `{{taskPriority}}` sai no rótulo em pt-BR (`Alta`), não na chave crua.
/// Fora isso, mesmo conjunto e mesma precedência (whatsapp → phone, etc.).
class KanbanMessageVars {
  const KanbanMessageVars({
    required this.task,
    this.contactName,
    this.contactPhone,
    this.contactEmail,
    this.propertyLabel,
    this.brokerName,
  });

  final KanbanTask task;

  /// Pessoa que vai RECEBER a mensagem, quando ela não é o cliente titular:
  /// o contato avulso do card (lead de campanha, que nem tem cliente) ou uma
  /// das linhas de "outros contatos" (esposa, sócio…).
  ///
  /// Tem prioridade sobre o nome do cliente de propósito: a saudação é para
  /// quem abre a conversa. O backend não enxerga `task.contacts` — ele cai no
  /// título do card — e o app tem o dado na mão.
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;

  /// Imóvel vinculado (`property.title` / `Imóvel <code>`). NÃO é token:
  /// o interpolador do backend não conhece variável de imóvel, então ele só
  /// alimenta os modelos locais, montados em Dart.
  final String? propertyLabel;

  /// Corretor dono do card (`task.assignedTo?.name`). Mesma regra do imóvel:
  /// entra no texto dos modelos locais, nunca como `{{...}}`.
  final String? brokerName;

  static const List<String> vocabulary = <String>[
    'clientName',
    'clientFirstName',
    'clientPhone',
    'clientEmail',
    'taskTitle',
    'taskDescription',
    'taskId',
    'taskPriority',
    'taskDueDate',
  ];

  String get clientName {
    final receiver = contactName?.trim();
    if (receiver != null && receiver.isNotEmpty) return receiver;
    final fromClient = task.client?.name.trim();
    if (fromClient != null && fromClient.isNotEmpty) return fromClient;
    return task.title.trim();
  }

  /// `true` quando o nome veio de GENTE (contato tocado ou cliente
  /// vinculado). Quando não veio, `clientName` cai no TÍTULO do card — que
  /// em lead de campanha é "Lead Campanha Idealle 31626" e viraria um
  /// "Olá Lead, tudo bem?" na cara do cliente. Os modelos locais usam isto
  /// para simplesmente não saudar pelo nome; a interpolação de `{{...}}`
  /// segue igual à do backend (o fallback pelo título é a regra de lá).
  bool get hasRealName {
    final receiver = contactName?.trim();
    if (receiver != null && receiver.isNotEmpty) return true;
    final fromClient = task.client?.name.trim();
    return fromClient != null && fromClient.isNotEmpty;
  }

  String get clientFirstName {
    final parts = clientName.split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  String get clientPhone {
    // O número REALMENTE tocado manda; sem ele, a precedência do backend
    // (whatsapp antes de phone).
    final receiver = contactPhone?.trim();
    if (receiver != null && receiver.isNotEmpty) return receiver;
    final wa = task.client?.whatsapp?.trim();
    if (wa != null && wa.isNotEmpty) return wa;
    return task.client?.phone?.trim() ?? '';
  }

  String get clientEmail {
    final receiver = contactEmail?.trim();
    if (receiver != null && receiver.isNotEmpty) return receiver;
    return task.client?.email?.trim() ?? '';
  }

  /// Primeiro nome do corretor — assinatura curta nos modelos locais.
  String? get brokerFirstName {
    final n = brokerName?.trim();
    if (n == null || n.isEmpty) return null;
    return n.split(RegExp(r'\s+')).first;
  }

  Map<String, String> get values => <String, String>{
        'clientName': clientName,
        'clientFirstName': clientFirstName,
        'clientPhone': clientPhone,
        'clientEmail': clientEmail,
        'taskTitle': task.title,
        'taskDescription': task.description ?? '',
        'taskId': task.id,
        'taskPriority': task.priority?.label ?? '',
        'taskDueDate': task.dueDate == null
            ? ''
            : DateFormat('dd/MM/yyyy').format(task.dueDate!),
      };

  /// Troca os `{{token}}` conhecidos. Token DESCONHECIDO fica visível de
  /// propósito (o backend também deixa) — o corretor edita o texto antes de
  /// enviar e enxergar o buraco é melhor do que apagá-lo em silêncio.
  String apply(String template) {
    var out = template;
    values.forEach((key, value) {
      out = out.replaceAll('{{$key}}', value);
    });
    return out;
  }
}
