import '../../core/routes/app_routes.dart';

/// Resolve URLs/payloads de notificação e push para rotas do app mobile.
///
/// Regra de ouro: só devolve rota que EXISTE no `AppRoutes.generateRoute`.
/// Caminho sem tela correspondente devolve `null` e o CHAMADOR decide o
/// fallback (push: Home + painel de notificações; lista in-app: não navega).
/// O catch-all antigo (`return path`) empurrava URLs do web — financeiro,
/// assinaturas, permissões — direto pra "Página não encontrada".
///
/// PERMISSÕES: aqui não se pré-filtra nada. Navegamos e a tela/backend
/// negam quando for o caso — as regras de acesso vivem no back.
///
/// Ofertas e Matches estão OCULTAS no app (ver `FeatureVisibility`): deep
/// links dessas áreas caem no detalhe do imóvel quando há `propertyId`,
/// senão no fallback do chamador. Nunca nas telas escondidas.
///
/// LINK EXTERNO (25/09/2026): a notificação "Assine a ficha" traz como
/// `actionUrl` o short link do Autentique — host de fora do sistema. Isso
/// não é rota do app nem do SPA: o destino digno é o NAVEGADOR. Por isso
/// existe [resolveTarget], que separa "rota interna" de "URL externa";
/// [resolve] continua devolvendo só rota interna, para os chamadores que
/// nunca abrem navegador (app links do `DeepLinkService`).
class AppDeepLink {
  AppDeepLink._();

  /// Domínios do sistema. Um `actionUrl` absoluto nesses hosts é o SPA
  /// (`${FRONTEND_URL}/kanban/task/{id}`) e continua resolvendo por PATH;
  /// qualquer outro host é link de terceiro (Autentique, portal…) e abre
  /// fora do app. `intellisysbr.com` é o mesmo domínio dos app links do
  /// `DeepLinkService`; `dreamkeys.com.br` é a API. Localhost e IPs de rede
  /// privada cobrem o front local em desenvolvimento.
  static const Set<String> _systemHostSuffixes = <String>{
    'intellisysbr.com',
    'dreamkeys.com.br',
  };

  static final RegExp _privateNetworkHost = RegExp(
    r'^(localhost|127\.\d+\.\d+\.\d+|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)$',
  );

  /// `true` quando [host] pertence ao sistema (SPA, API ou ambiente local).
  static bool isSystemHost(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    if (_privateNetworkHost.hasMatch(h)) return true;
    for (final suffix in _systemHostSuffixes) {
      if (h == suffix || h.endsWith('.$suffix')) return true;
    }
    return false;
  }

  /// Resolve o destino completo: rota interna OU URL externa.
  ///
  /// Ordem — e ela importa:
  ///  1. `metadata.externo == true` com `metadata.signatureUrl` válida →
  ///     externa. É o contrato explícito do back para "assine a ficha";
  ///  2. `actionUrl` absoluto http(s) em host que NÃO é do sistema →
  ///     externa. Cobre o push FCM, que leva `data.actionUrl` mas NÃO leva
  ///     `metadata` (ver `mobile-push.service.ts`);
  ///  3. senão, rota interna por [resolve]. A checagem externa vem ANTES
  ///     da resolução por entidade de propósito: o short link do Autentique
  ///     tem path opaco (`/abc123`) que não casa com rota nenhuma, e sem
  ///     esta ordem o fallback `sale_form_signature` → detalhe da ficha
  ///     engoliria o link e o usuário nunca chegaria ao documento.
  static AppDeepLinkTarget? resolveTarget({
    String? actionUrl,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) {
    final external = _externalFrom(actionUrl: actionUrl, metadata: metadata);
    if (external != null) return external;

    final route = resolve(
      actionUrl: actionUrl,
      entityType: entityType,
      entityId: entityId,
      metadata: metadata,
    );
    if (route == null || route.isEmpty) return null;
    return AppDeepLinkRoute(route);
  }

  /// Converte [actionUrl] web ou payload FCM em rota interna.
  ///
  /// URL externa (host fora do sistema) devolve `null` aqui — quem quer
  /// abrir navegador usa [resolveTarget].
  static String? resolve({
    String? actionUrl,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) {
    if (actionUrl != null && actionUrl.trim().isNotEmpty) {
      final mobile = _fromActionUrl(actionUrl.trim());
      if (mobile != null) return mobile;
    }
    if (entityType != null &&
        entityType.trim().isNotEmpty &&
        entityId != null &&
        entityId.trim().isNotEmpty) {
      return _fromEntity(entityType.trim(), entityId.trim(), metadata);
    }
    return null;
  }

  static String? fromPushData(Map<String, dynamic> data) {
    final target = targetFromPushData(data);
    return target is AppDeepLinkRoute ? target.route : null;
  }

  /// Versão de [fromPushData] que também enxerga link externo.
  static AppDeepLinkTarget? targetFromPushData(Map<String, dynamic> data) {
    return resolveTarget(
      actionUrl: data['actionUrl']?.toString() ?? data['url']?.toString(),
      entityType: data['entityType']?.toString(),
      entityId: data['entityId']?.toString() ?? data['id']?.toString(),
      metadata: data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
    );
  }

  static AppDeepLinkExternal? _externalFrom({
    String? actionUrl,
    Map<String, dynamic>? metadata,
  }) {
    // 1. Contrato explícito: metadata.externo + metadata.signatureUrl.
    final externo = metadata?['externo'];
    final isExterno = externo == true || externo?.toString() == 'true';
    if (isExterno) {
      final signatureUri = _httpUri(metadata?['signatureUrl']?.toString());
      if (signatureUri != null) return AppDeepLinkExternal(signatureUri);
    }
    // 2. actionUrl absoluto em host de terceiro.
    final actionUri = _httpUri(actionUrl);
    if (actionUri != null && !isSystemHost(actionUri.host)) {
      return AppDeepLinkExternal(actionUri);
    }
    return null;
  }

  /// `Uri` só quando for http(s) absoluto com host — o resto (relativo,
  /// `dreamkeys://`, lixo) não é link de navegador.
  static Uri? _httpUri(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// Segmentos de `/fichas-venda/{x}` que NÃO são id de ficha.
  static const Set<String> _saleFormReservedSegments = <String>{
    'nova',
    'novo',
    'new',
    'create',
    'dashboard',
    'editar',
    'edit',
  };

  static String? _fromActionUrl(String url) {
    // Sempre parsear como Uri — actionUrls do backend vêm relativas
    // (`/calendar?appointmentId={id}`) ou ABSOLUTAS (`${FRONTEND_URL}/kanban/
    // task/{id}?teamId=…`, caso do kanban/lead). Só path+query interessam.
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final path = uri.path;
    if (path.isEmpty) return null;
    return _normalizeMobilePath(path, uri.queryParameters);
  }

  static String? _normalizeMobilePath(
    String rawPath, [
    Map<String, String>? query,
  ]) {
    // O SPA web é servido sob /sistema — os links chegam COM e SEM o prefixo
    // (ex.: `/sistema/kanban/task/{id}` do comentário com menção e
    // `${base}/kanban/task/{id}` do buildKanbanTaskAbsoluteUrl).
    var path = rawPath;
    if (path == '/sistema') path = '/';
    if (path.startsWith('/sistema/')) {
      path = path.substring('/sistema'.length);
    }

    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    switch (segments.first) {
      // ── Kanban / CRM ────────────────────────────────────────────────
      case 'kanban':
        // /kanban/task/{id}[?teamId&projectId] — menção, transferência,
        // pessoa envolvida, reenvio…
        if (segments.length >= 3 &&
            segments[1] == 'task' &&
            segments[2].isNotEmpty) {
          return AppRoutes.kanbanTaskDetails(segments[2]);
        }
        // /kanban/subtasks/{id} não tem detalhe dedicado no app → lista
        // global de tarefas (paridade /kanban/tarefas).
        if (segments.length >= 2 &&
            (segments[1] == 'subtasks' || segments[1] == 'tarefas')) {
          return AppRoutes.kanbanSubtasks;
        }
        // /kanban?taskId={id} — lead reivindicado via WhatsApp.
        final taskIdFromQuery = query?['taskId'];
        if (taskIdFromQuery != null && taskIdFromQuery.isNotEmpty) {
          return AppRoutes.kanbanTaskDetails(taskIdFromQuery);
        }
        return AppRoutes.kanban;
      case 'tasks':
        // Formato legado /tasks/{id}.
        if (segments.length >= 2 && segments[1].isNotEmpty) {
          return AppRoutes.kanbanTaskDetails(segments[1]);
        }
        return AppRoutes.kanban;

      // ── Agenda ──────────────────────────────────────────────────────
      case 'calendar':
        // /calendar?appointmentId={id}     → lembrete (cron 15 min)
        // /calendar/appointments/{id}      → convite aceito/recusado
        // /calendar/details/{id}           → navegação do web
        // /calendar/invites/{inviteId}     → convite recebido
        final apptFromQuery = query?['appointmentId'];
        if (apptFromQuery != null && apptFromQuery.isNotEmpty) {
          return AppRoutes.calendarDetails(apptFromQuery);
        }
        if (segments.length >= 3 &&
            (segments[1] == 'appointments' || segments[1] == 'details')) {
          return AppRoutes.calendarDetails(segments[2]);
        }
        if (segments.length >= 2 && segments[1] == 'invites') {
          return AppRoutes.calendarInvites;
        }
        return AppRoutes.calendar;
      case 'appointments':
        if (segments.length >= 2 &&
            segments[1].isNotEmpty &&
            segments[1] != 'invites') {
          return AppRoutes.calendarDetails(segments[1]);
        }
        return AppRoutes.calendar;

      // ── Imóveis ─────────────────────────────────────────────────────
      case 'properties':
        if (segments.length == 1) return AppRoutes.properties;
        final second = segments[1];
        // Fila de aprovação (disponibilidade, publicação, edições…) —
        // rota real no app; a query (?tab=edit_requests) é ignorada.
        if (second == 'pending-approvals') return AppRoutes.propertyApprovals;
        // Ofertas está OCULTA: /properties/offers?propertyId={id} cai no
        // detalhe do imóvel; sem propertyId, fallback do chamador.
        if (second == 'offers') {
          final propertyId = query?['propertyId'];
          if (propertyId != null && propertyId.isNotEmpty) {
            return AppRoutes.propertyDetails(propertyId);
          }
          return null;
        }
        // Formato do web /properties/edit/{id} (status de solicitação de
        // alteração) → DETALHE do imóvel: é onde vivem histórico e painel
        // de comunicação; abrir o formulário pesado direto do push é
        // agressivo.
        if (second == 'edit' && segments.length >= 3) {
          return AppRoutes.propertyDetails(segments[2]);
        }
        if (second == 'create' || second == 'drafts-local') {
          return AppRoutes.properties;
        }
        // /properties/{id}, /properties/{id}?tab=updates (conversa de
        // aprovação — o detalhe tem o painel de comunicação),
        // /properties/{id}/matches (Matches oculto) e
        // /properties/{id}/expenses/{eid} (sem tela própria): tudo no
        // detalhe do imóvel.
        return AppRoutes.propertyDetails(second);

      // ── Clientes ────────────────────────────────────────────────────
      case 'clients':
        if (segments.length == 1) return AppRoutes.clients;
        if (segments[1] == 'new') return AppRoutes.clients;
        // /clients/{id} e /clients/{id}/matches (Matches oculto) → detalhe.
        return AppRoutes.clientDetails(segments[1]);

      // ── Fichas / propostas ──────────────────────────────────────────
      case 'proposals':
        if (segments.length >= 2 &&
            segments[1].isNotEmpty &&
            segments[1] != 'create') {
          return AppRoutes.proposalEdit(segments[1]);
        }
        return AppRoutes.proposals;
      case 'fichas-proposta':
        // /fichas-proposta?highlightProposal={id} — lista de propostas.
        return AppRoutes.proposals;
      case 'fichas-venda':
        // /fichas-venda/detalhes/{id} — assinou/recusou/finalizada (25/09/2026)
        // /fichas-venda/{id}          — atalho curto, mesmo destino
        // /fichas-venda/nova?propostaId={id}, /fichas-venda/dashboard… → lista.
        // Antes TUDO caía na lista e o usuário tinha que achar a ficha na mão.
        if (segments.length >= 3 &&
            segments[1] == 'detalhes' &&
            segments[2].isNotEmpty) {
          return AppRoutes.saleFormDetails(segments[2]);
        }
        if (segments.length == 2 &&
            segments[1].isNotEmpty &&
            !_saleFormReservedSegments.contains(segments[1])) {
          return AppRoutes.saleFormDetails(segments[1]);
        }
        return AppRoutes.saleForms;

      // ── Vistorias ───────────────────────────────────────────────────
      case 'inspection': // singular: aprovação de vistoria emite assim
      case 'inspections':
        if (segments.length >= 2 &&
            segments[1].isNotEmpty &&
            segments[1] != 'new') {
          return AppRoutes.inspectionDetails(segments[1]);
        }
        return AppRoutes.inspections;

      // ── Documentos (Assinafy) ───────────────────────────────────────
      case 'documents':
        if (segments.length >= 2 &&
            segments[1].isNotEmpty &&
            segments[1] != 'create') {
          return AppRoutes.documentDetails(segments[1]);
        }
        return AppRoutes.documents;

      // ── Checklists de venda ─────────────────────────────────────────
      case 'checklists':
        if (segments.length >= 2 &&
            segments[1].isNotEmpty &&
            segments[1] != 'create') {
          return AppRoutes.checklistDetails(segments[1]);
        }
        return AppRoutes.checklists;

      // ── Diversos com tela real ──────────────────────────────────────
      case 'check-in':
        return AppRoutes.checkIn;
      case 'dashboard':
        return AppRoutes.home;
      case 'chat':
        if (segments.length >= 2 && segments[1].isNotEmpty) {
          return AppRoutes.chatRoom(segments[1]);
        }
        return AppRoutes.chat;
      case 'integrations':
        // /integrations/{key} é rota real; caminhos mais fundos do web
        // (ex.: /integrations/meta-campaign/campaigns) caem no hub.
        if (segments.length == 2 && segments[1].isNotEmpty) {
          return '/integrations/${segments[1]}';
        }
        return AppRoutes.integrations;

      // ── Sem tela no app → fallback do chamador ──────────────────────
      // /notifications (tela legada — o app usa o painel/sheet),
      // /financial/*, /subscriptions, /permissions etc.
      default:
        return null;
    }
  }

  static String? _fromEntity(
    String entityType,
    String entityId,
    Map<String, dynamic>? metadata,
  ) {
    switch (entityType.toLowerCase()) {
      case 'task':
      case 'kanban_task':
      case 'lead':
      case 'lead_claim':
      case 'whatsapp_lead_claim':
        return AppRoutes.kanbanTaskDetails(entityId);
      case 'kanban_subtask':
        // Sem detalhe dedicado de subtarefa → lista global de tarefas.
        return AppRoutes.kanbanSubtasks;
      case 'appointment':
        return AppRoutes.calendarDetails(entityId);
      case 'appointment_invite':
        return AppRoutes.calendarInvites;
      case 'property':
        return AppRoutes.propertyDetails(entityId);
      // Ofertas/Matches ocultas e entidades satélites do imóvel: o destino
      // digno é o DETALHE do imóvel (metadata.propertyId), nunca as telas
      // escondidas. Sem propertyId → fallback do chamador.
      case 'property_match':
      case 'property_offer':
      case 'property_expense':
      case 'property_change_request':
        final propertyId = metadata?['propertyId']?.toString();
        if (propertyId != null && propertyId.isNotEmpty) {
          return AppRoutes.propertyDetails(propertyId);
        }
        return null;
      case 'client':
        return AppRoutes.clientDetails(entityId);
      case 'proposal':
      case 'purchase_proposal':
        return AppRoutes.proposalEdit(entityId);
      // Ficha de venda (25/09/2026): `sale_form` traz o id da ficha;
      // `sale_form_signature` traz o id da ASSINATURA, que não tem tela — a
      // ficha vem em `metadata.saleFormId`. O caso externo (assine) já foi
      // capturado antes em [resolveTarget]; aqui só chega assinou/recusou.
      case 'sale_form':
        return AppRoutes.saleFormDetails(entityId);
      case 'sale_form_signature':
        final saleFormId = metadata?['saleFormId']?.toString();
        if (saleFormId != null && saleFormId.isNotEmpty) {
          return AppRoutes.saleFormDetails(saleFormId);
        }
        return null;
      case 'inspection':
        return AppRoutes.inspectionDetails(entityId);
      case 'document':
        return AppRoutes.documentDetails(entityId);
      case 'checklist':
        return AppRoutes.checklistDetails(entityId);
      case 'check_in':
        return AppRoutes.checkIn;
      case 'note':
        return AppRoutes.notes;
      case 'message':
      case 'chat':
        return AppRoutes.chat;
      // Sem tela no app (financeiro, aprovação de vistoria, assinatura,
      // permissões, campanhas, feeds…): fallback do chamador.
      default:
        return null;
    }
  }
}

/// Destino resolvido de uma notificação/push (25/09/2026).
///
/// Duas formas, e só duas: [AppDeepLinkRoute] (rota nomeada do app, vai pro
/// `Navigator`) e [AppDeepLinkExternal] (URL http(s) de terceiro, vai pro
/// navegador via `url_launcher`). Quem consome faz `switch`/`is` — sem
/// campo mágico do tipo "isExternal + url nullable".
sealed class AppDeepLinkTarget {
  const AppDeepLinkTarget();
}

class AppDeepLinkRoute extends AppDeepLinkTarget {
  const AppDeepLinkRoute(this.route);
  final String route;
}

class AppDeepLinkExternal extends AppDeepLinkTarget {
  const AppDeepLinkExternal(this.uri);
  final Uri uri;
}
