# Paridade web × app (re-verificação 03/10/2026): WhatsApp, Chat interno, Notificações e CRM/Kanban

Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, linhas 377 a 662. Conferido contra o código atual dos três repositórios.

**Commits do app desde 29/09:** e7f9723, dea66d3, de39749, 5174723, ecd6989, 5f589be, fa64c2e e bumps de versão.

**Commits do back desde 28/09:**
- e783b5d6, 73ee5f22 a d4af7972: IA do WhatsApp, webhook, hierarquia de usuários e escopo de admin por empresa.
- 9ec51ed3: `dueDate: null` no update do card.
- f9a00be3: busca do quadro inclui perdidos.

**Legenda:**
- **Situação:** feito / parcial / ainda falta / não se aplica mais.
- **Deploy back?:** s quando o endpoint ou o campo ainda não existe no `intellisys-CRM-Back/src`.
- **Esforço:** P (pequeno), M (médio), G (grande).

Nas evidências, "web" é `intellisys-CRM/src` e "back" é `intellisys-CRM-Back/src`.

## Resumo por domínio

| Domínio | Itens | Feito | Parcial | Ainda falta | Dependem do back |
|---|---|---|---|---|---|
| WhatsApp | 22 | 6 (01, 02, 03, 10, 19, 23) | 3 (04, 11, 22) | 13 | 0 (só a renovação de mídia do 03, que é opcional) |
| Chat interno | 5 | 1 (chat-01) | 1 (chat-03) | 3 | 0 |
| Notificações | 5 | 1 (notif-04) | 0 | 4 | 0 |
| CRM/Kanban | 30 | 0 | 1 (kanban-12) | 29 | 2 (kanban-02 capabilities e kanban-v01 transferDate, ambos com contorno no app) |
| **Total** | **62** | **8** | **5** | **49** | **2** |

**WhatsApp**
- Os P0 (assumir, enviar mídia, ver mídia) estão feitos.
- Desde a auditoria também foram feitos template com cabeçalho e idioma (10), validação das variáveis (23) e o painel de disponibilidade/roleta dos SDRs (19).
- Muita coisa já foi portada para Dart e ainda não está ligada à tela: `motivoDaFalha`, `falhaPedeTemplate`, `conteudoDaBolha`, `podeResponder`. Isso barateia os itens 04, 11, 12 e 22.

**Chat**
- A lista de salas foi corrigida (P0 feito).
- O menu da sala continua só com "Deletar", que chama `leave`. Isso **quebra em conversa direta** (ver abaixo).
- Grupos, reações, respostas e o socket de digitação/presença continuam pendentes.

**Notificações**
- As preferências foram refeitas: matriz categoria × canal em `/user-preferences`.
- Continuam pendentes: abas, alertas do financeiro, filtro por `category` no servidor e listagem por empresa ativa.

**Kanban**
- Nenhuma funcionalidade de kanban entrou desde 29/09.
- O `TaskDocumentFolderPanel` foi criado, mas não está ligado à ficha.
- Todos os endpoints existem no back, exceto `/kanban/tasks/:id/capabilities` e o `transferDate` no `CreateKanbanTaskDto`.

## O que QUEBRA o app

1. ✅ **(corrigido em 03/10)** **QUEBRA: "Excluir conversa" em conversa direta sempre falha (chat).** Agora o app usa `delete-for-me` (qualquer sala) e `delete-for-all` (grupo, admin/criador, regra do web); o último admin é avisado antes de tentar sair (`chat_page.dart` `_isLastGroupAdmin`/`_canDeleteRoomForAll`; `chat_api_service.dart` `deleteRoomForMe`/`deleteRoomForAll`).
   - O app chama `POST /chat/rooms/:id/leave` para qualquer sala (`lib/features/chat/pages/chat_page.dart:274-277`, menu em `:1555-1560`).
   - No back, essa rota é `leaveGroup` e responde 400 "Esta funcionalidade é apenas para grupos" (`chat/chat.controller.ts:416-434`, `chat/chat.service.ts:2291-2293`). O último admin de um grupo também recebe 400.
   - Correção: usar `delete-for-me` / `delete-for-all` (`chat.controller.ts:436, 451`). É o chat-03.
   - Esforço P. Não depende de deploy.
2. **Tipos de notificação novos: não derrubam o app.**
   - O app lê `type` como String (`notification_model.dart:73`), sem enum, `byName` nem `firstWhere` sem `orElse`.
   - Tipo desconhecido cai no estilo genérico (`notification_type_style.dart:411-415`) e no rótulo "Notificação" (`notification_navigation.dart:85-86`).
   - Se não houver destino, aparece o toast "não abre nenhuma tela". No push, abre a Home com o painel (`app_push_service.dart:647-651`).
   - Cerca de 45 tipos do enum do back (`entities/notification.entity.ts:14-146`) estão sem ícone e sem rótulo próprio no app:
     - check-in (8 tipos)
     - assinatura (6)
     - `financial_approval_*` (3)
     - imóveis: ofertas, despesas, aprovações, edição, assinatura física (14)
     - `proposal_finalized`, `proposal_stage_completed`, `document_signed` e `document_rejected`
     - checklist (2)
     - leads: instagram, custom, `whatsapp_new_message`, `meta_campaign_scheduled_created`, `mcmv_lead_followup`, `kanban_lead_lost`, `kanban_lead_idle_rotation_warning`, `subtask_reminder`
     - `chaves_na_mao_feed_stale`

   O efeito é visual (ícone e rótulo genéricos), não crash.
3. **Risco latente de parse (não quebra hoje).**
   - `NotificationModel.fromJson` usa `DateTime.parse(createdAt/updatedAt)` e um cast duro de `metadata` (`notification_model.dart:84, 88-89`).
   - Um item malformado derruba a página inteira da lista REST.
   - Hoje o back sempre envia esses campos.
4. **Contratos: nenhuma quebra.** Desde 28/09:
   - Não houve commit em `src/chat`, `src/notifications` nem `user-preferences` do back.
   - No WhatsApp, só IA/webhook. O shape do groupByPhone, de `/messages` e de `/send` não mudou.
   - No Kanban, nenhum campo foi removido ou renomeado. O `ValidationPipe` usa `whitelist: true` e `forbidNonWhitelisted: false` (`main.ts:224-228`), então campo extra é descartado e não dá 400.
   - `GET/PUT /kanban/projects/:projectId/quick-updates` continua no back (`projects.controller.ts:422/440`).
5. **Mudanças de comportamento a observar (não são quebra).**
   - **Back e783b5d6:** admin ou manager pelo papel global só passa direto em empresa a que está vinculado. Pode gerar 403 novo em funil de outra empresa.
   - **Back f9a00be3:** a busca do quadro passou a trazer leads perdidos.
   - **Socket de subtarefa:** agora emite `task_updated` com o card-pai completo. Vale confirmar que `KanbanController._aoCardMudar` aceita esse payload.
   - **Mensagens de teste da IA:** chegam com `webhookData.aiTest=true` e aparecem como conversa real. Nem o app nem o web filtram.
   - **Canal QR, risco anterior do back:** em `whatsapp-baileys.service.ts:2165-2174`, tudo que não é `image/*` sai como vídeo. Nota de voz e documento enviados pelo app chegam como vídeo. A correção é no back e o web tem o mesmo problema.
   - **`GET /whatsapp/messages/:id` não existe no back.** O app já trata o 404: para de tentar e relê a thread (`whatsapp_service.dart:275-294`).

## WhatsApp

Nas evidências desta tabela, "conversation_page" é `lib/features/whatsapp/pages/whatsapp_conversation_page.dart`, "service" é `lib/features/whatsapp/services/whatsapp_service.dart`, "models" é `lib/features/whatsapp/models/whatsapp_models.dart`, "bubble" é `widgets/whatsapp_message_bubble.dart` e "controller" é o back `whatsapp/whatsapp.controller.ts`.

| ID | Prio | Situação | Evidência app | Evidência web/back | Deploy back? | Esforço |
|---|---|---|---|---|---|---|
| whatsapp-01 Assumir | P0 | feito | service:301-319 (`claimConversation`); conversation_page:128-131, 1213-1215, 1248-1254 | controller:3493 | n | – |
| whatsapp-02 Enviar mídia | P0 | feito (ressalva do canal QR acima) | service:431-506 (`sendMedia`: oficial image/file; QR media/caption; 90s); bandeja em conversation_page:725, 786, 1797; voz em `whatsapp_gravador_de_voz.dart` | controller:1123-1138; `whatsapp-unofficial.controller.ts:320` | n | – |
| whatsapp-03 Ver mídia | P0 | feito | bubble:367-399; `whatsapp_midia_da_bolha.dart`; `whatsapp_tocador_de_audio.dart`; renovação em conversation_page:406-430 | `GET /whatsapp/messages/:id` não existe (o app trata o 404) | n (a rota seria melhoria) | – |
| whatsapp-04 Responder citando | P1 | parcial: mostra a citação, mas não responde | Mostra em models:281-284, 406-407 e bubble:285-358. Falta o gesto, a faixa "Respondendo a…" e `replyToMessageId` no `sendText` (service:351-416). `podeResponder` está sem uso (`whatsapp_message_content.dart:378`) | controller:1341, 1428; unofficial:376 | n | P/M |
| whatsapp-05 Alocar para SDR | P1 | ainda falta | Não há assign no service. Dá para reaproveitar `SdrRouletteService.list()` (`lib/features/sdr/roleta/services/sdr_roulette_service.dart:59`) | controller:3245 (assign), 2915 (config), 3739 (sdr-availability) | n | M |
| whatsapp-06 Etiquetas | P1 | ainda falta | models:455-470 não lê `tags`; não há métodos no service | `whatsapp.service.ts:7006`; controller:3962-4044 | n | M |
| whatsapp-07 Venda/Locação | P1 | ainda falta | models:455-470 não lê `intent`; o menu (conversation_page:1245-1270) não tem as marcas | controller:3274; `service.ts:7003` | n | P |
| whatsapp-08 Recorte/Histórico de atendimentos | P2 | ainda falta | `getMessages` sem desde/ate (service:214-227) | controller:3515 | n | M |
| whatsapp-09 Nova conversa | P1 | ainda falta | `whatsapp_inbox_page.dart` não tem o botão; o template sheet já aceita telefone | web `WhatsAppMessagesList.tsx:1827-1845` | n | P |
| whatsapp-10 Template com header/idioma | P1 | feito | service:538-555; `whatsapp_send_template_sheet.dart:435-468` | `whatsapp-sender.service.ts:443-452` | n | – |
| whatsapp-11 Janela fechada no número de envio | P2 | parcial | conversation_page:97, 152-162, 627-662 detecta a falha só no envio da sessão. Não lê `webhookData` das falhas já gravadas. `falhaPedeTemplate` está sem uso (`message_content.dart:626`) | só front | n | P |
| whatsapp-12 Motivo da falha e Reenviar | P1 | ainda falta (base portada) | bubble:543-553 só mostra "Falhou". `motivoDaFalha` está sem uso (`message_content.dart:445-672`). Não há `resendMessage` | controller:3301 | n | P |
| whatsapp-14 Filtros da inbox | P1 | ainda falta | models:798-837 sem direction, status, tagIds, assignedToId e timeStatus | controller:2637, 3933 (sdr-pool) | n | M |
| whatsapp-16 Card: janela 24h, prazo e responsável | P2 | ainda falta | `whatsapp_conversation_card.dart`; o modelo não lê `lastInboundAt`/`lastActivityAt` | `service.ts:7001-7002`; controller:3571 | n | M |
| whatsapp-17 Criar tarefa e tarefas do contato | P1 | ainda falta | ausente (`kanbanTaskId` só aparece em conversation_page:909-911) | controller:997 | n | M |
| whatsapp-18 Mensagens prontas no composer | P1 | ainda falta | `getQuickMessages` (service:617) não é usado no composer; não há CRUD | unofficial:543-639 | n | M |
| whatsapp-19 Disponibilidade dos SDRs | P1 | feito (30/09) | `lib/features/sdr/roleta/**`; acesso em `whatsapp_inbox_page.dart:384-391`; gate em `sdr_roulette_page.dart:40`; rota em `app_routes.dart:410` | controller:3739-3910 | n | – |
| whatsapp-20 Agendar, editar enviada, opções de imóveis | P2 | ainda falta | ausente | unofficial:388, 412-527; controller:2573 | n | M |
| whatsapp-21 Insights da IA e dashboard de atrasos | P2 | ainda falta | ausente | controller:2609, 3652 | n | M |
| whatsapp-22 Bolha de reação, localização e contato | P1 | parcial: a prévia está pronta, a bolha não | Prévia via `previaDaMensagem` (models:367-370). A bolha usa só `message.message` (bubble:109-110), e localização e contato continuam "Abra no painel" (bubble:400-415). `conteudoDaBolha` e afins estão sem uso | só front | n | P/M |
| whatsapp-23 Variáveis do template obrigatórias | P1 | feito | `whatsapp_send_template_sheet.dart:410-426`, 439-445 (lista posicional) e 451-454 (filtro de vazias só no modo manual) | – | n | – |
| whatsapp-24 Gate do "Finalizar" | P2 | ainda falta | conversation_page:1265-1269 sem gate; `_canViewMessages` já existe em :112 | web `WhatsAppConversationViewer.tsx:6025-6039` | n | P |
| (sobra do 13) Poll de reserva na inbox | – | ainda falta | `whatsapp_inbox_page.dart:91-113` só tem socket | – | n | P |
| (sobra do 15) Aviso "buscando em todas as abas" | – | ainda falta | – | – | n | P |

## Chat interno

| ID | Prio | Situação | Evidência app | Evidência web/back | Deploy back? | Esforço |
|---|---|---|---|---|---|---|
| chat-01 Lista `{rooms, archivedRooms}` | P0 | feito (dea66d3) | `chat_api_service.dart:111-158` (objeto, lista e 304); `chat_page.dart:81-84, 440-444`; `chat_unread_controller.dart:107-136` | back `chat.controller.ts:81` | n | – |
| chat-02 Editar e criar grupo | P1 | ainda falta | `edit_group_chat_page.dart:14-29` ainda é placeholder; não há "Novo grupo". Os métodos do service já existem (`chat_api_service.dart:238-492`) | back `chat.controller.ts:373, 395, 466, 485, 509, 539` | n | G |
| chat-03 Silenciar, arquivar e apagar para mim/todos | P1 | parcial: ✅ apagar para mim/todos feito em 03/10 (QUEBRA 1 resolvida); faltam silenciar e arquivar na UI | `chat_page.dart:792-806, 1465, 1522` mostram o estado; menu só `delete` → `leaveRoom` (`:274-277, 1555-1579`). Não há mute nem delete-for-* no service. `archiveRoom`/`unarchiveRoom` existem (`:539, 571`), mas sem UI | back `chat.controller.ts:325, 337, 349, 361, 436, 451` | n | P |
| chat-04 Responder, reagir, editar, apagar e recibos | P1 | ainda falta | `chat_models.dart:343-366` sem `replyToMessage`/`reactions`. `editMessage`/`deleteMessage` existem no service (`:934, 984`), mas sem UI | back `chat.controller.ts:294, 592, 615, 640, 658` | n | G |
| chat-05 Socket: digitação, presença, reações, remoção | P2 | ainda falta | `chat_socket_service.dart:172-363` não trata typing, presence, reaction, deleted_for_me nem removed | back `chat.gateway.ts:828, 743/767, 1101, 1133, 1338, 1423` | n | M |

## Notificações

| ID | Prio | Situação | Evidência app | Evidência web/back | Deploy back? | Esforço |
|---|---|---|---|---|---|---|
| notif-01 Abas e contagem por origem no sino | P2 | ainda falta | `notification_center.dart:365` (`markAllAsRead` sem category); `notifications_page.dart:91-97` só tem chip filtrado no cliente | back `notification.controller.ts:107, 311` | n | M |
| notif-02 Alertas do financeiro | P1 | ainda falta | Não há cliente de `/notifications` do financeiro; `notification_list.dart:96`. A base URL do financeiro em `settings_service.dart:33-41` pode ser reaproveitada | web `financeNotificationsApi.ts:195-231` (microserviço financeiro) | n | M |
| notif-03 `category` no servidor | P2 | ainda falta | `notification_controller.dart:44-66, 295-296, 356-360` (até 5 páginas); `notification_model.dart:250-283` sem category | back `notification-query.dto.ts`; `notification.controller.ts:55, 107` | n | P |
| notif-04 Preferências de notificação | P1 | feito (dea66d3) | `settings_service.dart:29-30, 327-453, 469-551`; `notification_preferences_page.dart`; `settings_page.dart:287`. Sobra `ApiConstants.settings` sem uso (`api_constants.dart:235`) | back `user-preferences.controller.ts:37, 53, 59` | n | – |
| notif-06 Sino lista todas as empresas | P2 | ainda falta | `notification_service.dart:22-34, 95-100` (`/all-companies`); `controller:491-501` | back `notification.controller.ts:55` vs `:82` | n | P |

## CRM / Kanban

Nas evidências desta tabela, "modal" é `lib/features/kanban/widgets/task_details_modal.dart`, "models" é `lib/features/kanban/models/kanban_models.dart`, "service" é `lib/features/kanban/services/kanban_service.dart` e "ctrl" é o back `kanban/kanban.controller.ts`.

| ID | Prio | Situação | Evidência app | Evidência web/back | Deploy back? | Esforço |
|---|---|---|---|---|---|---|
| kanban-01 Título só o criador edita | P1 | ainda falta | modal:1755 (`canEditTitle: _canEdit`); `KanbanTask` não lê `createdBySystem` | back `kanban/utils/kanban-title-edit.util.ts` | n | P |
| kanban-02 Permissões por card | P1 | ainda falta | modal:948-950; `kanban_page.dart:1660`; service:2418 sem chamador | `/kanban/tasks/:id/capabilities` **não existe** no back; o web usa o fallback `resolveKanbanTaskPermissions` | s só para capabilities (portar o fallback resolve sem deploy) | M |
| kanban-04 Líder gerencia tags | P1 | ainda falta | modal:955-960; `KanbanPermissions` sem `canFilterByUsers` | back `kanban.dto.ts:3173` | n | P |
| kanban-05 Card sem responsável | P1 | ainda falta | `edit_task_modal.dart:573-575` (validator); models:1977-1980 | `UpdateKanbanTaskDto.assignedToId` é opcional | n | P |
| kanban-06 Leads perdidos | P1 | ainda falta | ausente | ctrl:1880, 1897, 1914, 1933 | n | G |
| kanban-07 Exportação órfã | P1 | ainda falta | `organization_backups_page.dart:37` sem rota; `organization_access.dart:41` só tem `backup:view` | ctrl:1295-1562 | n | P |
| kanban-09 Filtros do funil | P1 | ainda falta | `kanban_filters_drawer.dart:192-300` | back `kanban.dto.ts:2070` | n | M |
| kanban-10 Dados da campanha Meta | P1 | ainda falta | `KanbanTask` sem `customFields`/`metaFormId` | web `TaskDetailsPage.tsx:9225-9300` | n | P |
| kanban-11 Transferência, campanha, cor e financiamento | P1 | ainda falta | o DTO já tem `cardColor`/`clientFinancingApproved` (models:1920, 2063), mas não há UI | `UpdateTaskFieldsDto` aceita os campos | n | M |
| kanban-12 Pasta de documentos | P1 | parcial | `lib/features/documents/widgets/task_document_folder_panel.dart:34` existe e não é usado; a ficha tem `TabController(length: 8)` (modal:226); faltam a página Pastas CRM e o badge | back `document-folders.controller.ts:36` | n | M |
| kanban-13 CRUD de funis e histórico | P1 | ainda falta | service:1482, 1780, 1820, 1848, 1923 sem chamadores | back `projects.controller.ts` | n | G |
| kanban-14 Funil Global e Visão Unificada | P1 | ainda falta | ausente | ctrl:247-363 | n | G |
| kanban-15 Detalhe da subtarefa | P1 | ainda falta | `kanban_subtask_service.dart` sem comments/history | `kanban-subtasks.controller.ts:383, 477, 508, 567` | n | M |
| kanban-16 Minhas tarefas: escopo e filtros | P1 | ainda falta | `kanban_subtasks_list_page.dart:214` (`onlyMine: !isPrivileged`) | – | n | M |
| kanban-17 Gerenciar usuários do Kanban | P1 | ainda falta | ausente | ctrl:549-621; `board-permission-audit.controller` | n | G |
| kanban-18 Distribuir leads em massa | P1 | ainda falta | `kanban_page.dart:3014-3020` (seleção só com Excluir); `redistributeFunnelLeads` existe em `workspace/services/admin_users_service.dart:429` | ctrl:2682, 2712 | n | M |
| kanban-19 Busca global de leads | P1 | ainda falta | ausente | ctrl:407, 481, 514 | n | M |
| kanban-v01 transferDate na criação | P1 | ainda falta | models:1750-1887 sem `transferDate`; `create_task_modal.dart:140` | **`CreateKanbanTaskDto` (`kanban.dto.ts:173-431`) também não tem o campo**: o web também perde o valor | s (contorno no app: criar e depois `PUT /tasks/:id/fields`) | P |
| kanban-03 Flags de board-permissions/me | P2 | ainda falta | models:1388-1425 | o `/board` já traz `canCommentTasks`, `canViewHistory` e `canManageFiles` (dto:3196-3200); `/me` em ctrl:549 | n | P |
| kanban-08 Validações ao mover | P2 | ainda falta | service:1090 (`ApiResponse<void>`) | – | n | M |
| kanban-20 Importar negociações | P2 | ainda falta | ausente | ctrl:1202 | n | M |
| kanban-21 Colunas: reordenar, validações, columnTagName | P2 | ainda falta | `kanban_controller.dart:737` sem chamador | ctrl:1139 | n | G |
| kanban-22 Badges do card | P2 | ainda falta | nenhum `subtasksCount` no app | – | n | P |
| kanban-23 Tipo de funil | P2 | ainda falta | só `wonLabelForFunnelType` (models:2631) | `UpdateKanbanTaskDto` tem `customField1/2` | n | M |
| kanban-24 Anexos e escolha de funil na criação | P2 | ainda falta | `create_task_modal.dart` | ctrl:2010 | n | P |
| kanban-25 Nova tarefa escolhendo o card-pai | P2 | ainda falta | `kanban_subtasks_list_page.dart` | – | n | P |
| kanban-v02 Desvincular cliente/imóvel | P2 | ainda falta | models:1908-1912 (comentário desatualizado) | `@IsOptional` aceita null | n | P |
| kanban-v03 Descrição na ficha | P2 | ainda falta | modal:2016 | `clearDescription` já existe no DTO | n | P |
| kanban-v04 Atualizações rápidas por card | P2 | ainda falta | service:2482-2505; `api_constants.dart:402` (a rota por projeto ainda funciona) | ctrl:1707, 1725 | n | P |
| kanban-v05 Sincronizar pessoas envolvidas | P2 | ainda falta | ausente | o web faz no cliente (`utils/backfillKanbanCreatorInvolved.ts`) com endpoints que já existem (ctrl:2423-2496) | n | P |
| kanban-v06 Valor obrigatório em negociação | P2 | ainda falta | nenhum `strictPipeline` no app | web `funnelTypeConfig.ts:67, 152-156` | n | P |
