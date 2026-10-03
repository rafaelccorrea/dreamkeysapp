# Relatório — Paridade app × web (Intellisys)

> Card: [ANÁLISE] Mobile — levantamento do que falta parear com a web (Edson Jr) · funil Tecnologia - Intellisys
> Gerado em 03/10/2026. Retrato do momento: as correções em andamento continuam marcando ✅ nos relatórios por domínio da pasta docs/paridade-2026-10-03/.

## Sumário
1. Paridade web × app — verificação de 03/10/2026
2. Paridade web × app — Imóveis (verificação 03/10/2026)
3. Paridade web × app — Ficha de Venda e Ficha de Proposta (03/10/2026)
4. Paridade web × app — re-verificação 03/10/2026
5. Paridade web × app (re-verificação 03/10/2026): WhatsApp, Chat interno, Notificações e CRM/Kanban
6. Re-verificação de paridade web × app (03/10/2026): Financeiro, Usuários e Dashboards
7. Paridade web × app: Locações/Docs, Integrações, Transversal (re-verificação de 03/10/2026)

---

## Paridade web × app — verificação de 03/10/2026

Card do funil **Tecnologia - Intellisys**: *[ANÁLISE] Mobile — levantamento do que falta parear com a web* (Edson Jr).
Base: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, re-conferida item a item contra o código ATUAL do app, da web
(`intellisys-CRM`) e do back (`intellisys-CRM-Back`, `intellisys-financeiro`). Verificação por código, não no aparelho.
"Depende do back" = a rota/DTO existe no `master` do back; produção não foi conferida.

### Placar

| Domínio | Itens | Feito | Parcial | Falta | Relatório |
|---|---|---|---|---|---|
| Imóveis | 45 (+14 do card) | 19 | 10 | 16 | [imoveis.md](imoveis.md) |
| Fichas de Venda e Proposta | itens do card + comparação tela a tela | 6 do card | — | 1 P0 · ~9 P1 · ~20 P2 | [fichas-venda-proposta.md](fichas-venda-proposta.md) |
| Fichas de Locação · Clientes · Agenda | 84 | 19 | 3 | 62 | [locacao-clientes-agenda.md](locacao-clientes-agenda.md) |
| WhatsApp · Chat · Notificações · Kanban | 62 | 8 | 5 | 49 | [whatsapp-chat-kanban.md](whatsapp-chat-kanban.md) |
| Meu Financeiro · Usuários · Dashboards | 95 | 21 | 11 | 61 (+2 n/a) | [financeiro-usuarios-dashboards.md](financeiro-usuarios-dashboards.md) |
| Locações · Integrações · Transversal | 103 | 16 | 11 | 76 | [locacoes-integracoes-transversal.md](locacoes-integracoes-transversal.md) |

Todos os P0 da auditoria de 29/09 que estavam no escopo (Imóveis, WhatsApp/Chat, Usuários, Dashboards, Integrações,
Transversal) estão de fato feitos. Os P0 abertos são NOVOS ou estavam fora do escopo.

### O que QUEBRA o app hoje (prioridade máxima)

1. **Login / cobrança (NEW-01)** — titular com trial vencido ou assinatura suspensa entra sem aviso e sem onde assinar; o colaborador da conta leva 403 na Home e em Imóveis.
2. **Plano "só Financeiro" (NEW-02)** — o back recusa as rotas de CRM com 403; o app trava em "Sem permissão" (depende do deploy do back).
3. **Chat** — "Excluir conversa" em conversa direta sempre falha (rota de sair de grupo → 400).
4. **Meu Site (integ-F1)** — editar/reordenar seção sem seções salvas apaga o formulário de captação do site público.
5. **Fichas** — anexo da ficha física recusado na venda e na proposta (upload sem tipo de arquivo).
6. **Imóveis** — Exportar nunca funcionou (GET × POST); "Apenas inativos" não filtra; preço 0 aparece como "R$ 0".
7. **Transversais** — telefone com DDI 55 gravado errado; CNPJ alfanumérico não digita; tipo "Assinatura" da agenda dá 400; upload com token vencido falha; deep link de ficha de venda com id inválido; várias ações sem checagem de permissão terminam em 403 (agenda, check-in, vistorias, chaves, fichas de locação).

### Decisões de escopo a revisar

- **Meu Financeiro, PIN, adiantamento, Solicitações (fin-01 a fin-05)** — fora do escopo em 29/09; com o Financeiro como prioridade nº 1 desde 02/10, sugerido voltar como P0.
- **Fichas de Locação (6 P0) e Locações (12 itens)** — seguem fora do escopo pela decisão de 29/09.
- **Web-only** — ~23 itens de Integrações/Meu Site/Portais e Transversal são candidatos a sair do escopo do app.

### Pendências do BACK descobertas

- `isSitePremiumLine` ("linha premium") fora do DTO do PATCH de imóvel: não grava nem na web.
- Endereço estruturado do proprietário e filtros de faixa de preço/suítes/salas sem suporte no back.
- `/kanban/.../capabilities` inexistente; `transferDate` descartado na criação do card.
- Provável conflito de rotas na proposta (`whatsapp-envio` capturado por `:signatureId`).
- WhatsApp por QR Code: nota de voz e documento chegam como vídeo.

### Execução (em andamento em 03/10)

- **[MOBILE] Imóveis** — bugs rápidos + itens do card (aprovação parcial, abas do portfólio, recentes, catálogo, permuta, atalhos de status).
- **[MOBILE] Fichas** — upload, DISPAROS MANYCHAT, equipes, vínculo com imóvel, trava/assinaturas, detalhe + auditoria, exportação.
- **P0 transversais** — login/cobrança, plano só Financeiro, excluir conversa, Meu Site, DDI/CNPJ, agenda, upload/token, deep link e checagens de permissão.

Cada relatório de domínio é atualizado com ✅ no que for resolvido.

---

## Paridade web × app — Imóveis (verificação 03/10/2026)

Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, seção "## Imóveis" (45 lacunas), mais as pendências do card do funil. Conferido no código atual dos três repos (app até `675b686`; inclui `fa64c2e`). As tabelas abaixo são a verificação da manhã; o que foi executado depois no app está em **"Execução no app (03/10/2026)"** (marcado com ✅).

### Resumo

| Severidade | Itens | Feitos | Parciais | Faltam |
|---|---|---|---|---|
| P0 | 9 | **9** | 0 | 0 |
| P1 | 19 | 5 | 7 | 7 |
| P2 | 17 | 5 | 3 | 9 |
| **Auditoria** | **45** | **19** | **10** | **16** |
| Card do funil (extras) | 14 | 4 (+1 não se aplica) | 6 | 3 |

- **Todos os P0 estão fechados.** A edição pelo app não corrompe mais tipo, status, booleanos nem captadores. Duplicidade, "Sem CEP", áreas e negociação seguem o web.
- **Correção de premissa.** O back **não** recusa campo desconhecido. `intellisys-CRM-Back/src/main.ts:225-226` usa `whitelist: true, forbidNonWhitelisted: false`, então campo fora do DTO é **descartado em silêncio**. O risco é a chave "sumir", não dar 400.
- **Back.** Todos os endpoints que o app precisa já existem no código atual do back: `duplicate-check`, `owner-check`, `portfolio-counts`, `recent-deals`, `presentation-pdf`, `:id/views`, `geocode-location`, `stale-for-user`, `property-catalog`, `vote PUT`, `mark-seen` e `approval-chat-inbox`. Só dois itens pedem mudança no back. Ver a seção "Depende do back".
- **Bugs novos, fora da auditoria:**
  1. ✅ (03/10) **A exportação do app nunca funcionou.** O app faz `GET /properties/export` (`lib/shared/services/property_service.dart:3032,3042`), mas o back só tem `@Post('export')` (`properties.controller.ts:4237`). O GET cai em `GET :id` com `ParseUUIDPipe` e volta 400.
  2. ✅ (03/10) **O toggle "Apenas inativos" não filtra nada.** O app manda `isActive=false` (`properties_page.dart:654-668`), e o `GET /properties` não lê esse parâmetro. O certo é `portfolioScope=inactive`.
  3. ✅ (03/10) **Preço "0.00" aparece como "R$ 0".** Na lista (`properties_page.dart:3421-3425`) e no detalhe (`property_values_section.dart:91,101`), em vez de "não se aplica".
  4. **"Linha premium" não grava, no web e no app.** Os dois mandam `isSitePremiumLine` no `PATCH /properties/:id` (app: `property_detail_extras_service.dart:614`; web: `PropertyDetailsPage.tsx:1537`). O campo não está em `UpdatePropertyDto` (`update-property.dto.ts:53`), e o whitelist o descarta. A correção é no back.

### Execução no app (03/10/2026)

Feito no app seguindo a "Ordem de execução" (back não alterado). Todo campo novo enviado foi conferido no DTO atual do back. `flutter analyze` sem erro/aviso novo (224 issues no projeto, todas pré-existentes; 33 em `features/properties` + `property_service`, eram 34) e `flutter test` com 127 testes passando (30 novos em `test/features/properties/`).

| Item | Status | Onde |
|---|---|---|
| Bug 1 / imoveis-26: exportar | ✅ `POST /properties/export?format=` com `{ filters }` da lista (aba, busca, filtros), prévia `dryRun` (total, escopo, teto) e entrega pela folha de arquivo (compartilhar/salvar). Nome do arquivo vem do `Content-Disposition` | ps `exportProperties`/`previewExport`/`toExportFilters`; `widgets/export_import_dialog.dart`; PP `_handlePropertiesOverflowAction` |
| imoveis-27: gate de exportar/importar | ✅ cada metade só com `property:export` / `property:import`; o item do menu some sem nenhuma | `export_import_dialog.dart`; PP `_PropertiesOverflowSheet` |
| Bug 2: "Apenas inativos" | ✅ vira `portfolioScope=inactive` (= aba Inativos); estado antigo `isActive=false` em cache é migrado | PP `_onlyInactive`/`_toggleOnlyInactive`/`_restoreCachedState` |
| Bug 3: preço "0.00" | ✅ lista: só os preços > 0 (venda+locação mostra os dois; nenhum = "Preço não informado"); detalhe: "Não se aplica" no lugar de "R$ 0"; médias da lista ignoram 0 | `utils/property_price_display.dart`; PP `_formatMainPrice`; `widgets/details/property_values_section.dart` |
| imoveis-F4: apagar e-mail do proprietário | ✅ edição manda `ownerEmail: null` quando vazio; criação não manda | cpp (payload) |
| imoveis-14: `pendingChangeRequest` / `resubmittedForApproval` | ✅ parse no `Property`; edição avisa o que foi para aprovação (azul) ou o reenvio à fila (âmbar), textos do web. Também nas observações internas do detalhe | ps `PropertyPendingChangeRequest`/`PropertyResubmission`; `utils/property_save_feedback.dart`; cpp; DP `_saveInternalNotes` |
| imoveis-22: mudar voto | ✅ quem já votou abre a folha com o voto marcado e confirma por `PUT` ("Alterar voto"); POST com 409 refaz como PUT; lista quem votou e como | `services/property_approval_service.dart` `castVote`; `models/property_change_request.dart` `ApprovalVoteEntry`; `widgets/approval_info_sheets.dart`; `pages/property_approvals_page.dart` |
| imoveis-23: abas + contagem | ✅ Todos, Disponíveis, Em negociação, Vendidos, Locados, Pendentes, Recusados, Outros, Inativos, com o número de `GET /properties/portfolio-counts` (mesmos filtros, sem a aba) | ps `PortfolioScope`, `getPortfolioCounts`; PP `_buildPortfolioScopeStrip` |
| imoveis-15/16 + card: atalhos no menu da lista | ✅ "Alterar status" (inclui vendido/locado), "Ativar/Desativar" (gestão) e "Publicar/Ocultar do site", reaproveitando as folhas do detalhe | PP `_showPropertyQuickActionsSheet`, `_toggleSitePublication` |
| Bloqueio por aprovação financeira | ✅ com `hasPendingFinancialApproval`, a folha "Alterar status" (lista e detalhe) tira Vendido/Alugado e explica | ps; `widgets/details/property_status_change_sheet.dart`; `utils/property_publish_rules.dart` |
| imoveis-F2 + `publishableImageCount` | ✅ Publicar/Ocultar no menu da lista e no do detalhe; publicar exige ativo, Disponível e 5 fotos (`publishableImageCount`, fallback nas fotos válidas). A aba Site do detalhe também trava "Publicar" com o motivo | `utils/property_publish_rules.dart`; PP; DP; `widgets/details/property_site_tab.dart` |
| Tela "Vendidos e Locados recentemente" | ✅ `GET /properties/recent-deals` (Todos/Vendidos/Locados, "Só os meus", paginação); abre pelo menu "Ações do portfólio" | `pages/recent_deals_page.dart`; ps `getRecentDeals`; PP |
| Catálogo + `extraRooms` | ✅ `GET /property-catalog`: cômodos extras com quantidade no wizard (mantém os gravados que saíram do catálogo; na edição só vai se mudou) e infraestrutura somada às características | cpp `_buildExtraRoomsSection`, `_loadPropertyCatalog`; `utils/property_form_extras.dart`; ps `getPropertyCatalog` |
| imoveis-12: permuta | ✅ "Aceita permuta? *" (Sim/Não + valor máximo) na etapa Valores, obrigatório como no web (rascunho isento); `acceptsExchange`/`exchangeMaxValue` no payload (na edição só se mudou) e no rascunho local | cpp `_buildExchangeSection`; `utils/property_form_extras.dart` |
| imoveis-11: equipe | ✅ com equipes disponíveis (ou a regra da empresa) a equipe é obrigatória na criação e na edição; saiu "— Não vincular —" | cpp `_teamRequired` |
| imoveis-09: limites próprios | ✅ removidos: título ≥ 3, descrição ≥ 10, rua/bairro/cidade ≥ 2, UF por regex (fica só ≤ 2), quartos < 50, banheiros/vagas < 20, suítes < 50, telefone ≥ 10, documento ≥ 11, aluguel < 999.999,99. Mantidos os tetos do DTO (título 255, descrição 5000, cidade/bairro 100, telefone 20) | cpp (`_validateCurrentStep`, `_findFirstStepValidationError`, validators) |
| imoveis-25: filtros e ordenação | **parcial** ✅ ordenação (opções do web), finalidade e código no drawer; o drawer agora limpa de verdade ao desmarcar (antes o `copyWith` mantinha o filtro anterior) | ps `PropertyFilters` (`sortBy`, `sortOrder`, `finalidade`, `code`, `withAdvancedFilters`); `widgets/property_filters_drawer.dart` |
| imoveis-28: galeria | **parcial** ✅ mostrar/ocultar a foto no site (`PUT /gallery/:id { showOnPublicSite }`) na galeria em tela cheia do detalhe | DP `_toggleCurrentSiteVisibility`; `services/property_detail_extras_service.dart` `setImageShowOnPublicSite` |

#### Ficou pendente (e por quê)

- **imoveis-10 (captadores por papel + responsáveis), G.** Pede tela de escolha de usuários por papel (venda/locação) com a regra `evaluateCaptorSlots`, lista de responsáveis e cuidado na edição (troca de captador é campo protegido e abre solicitação). Grande demais para fazer junto sem risco; o app segue gravando o usuário logado na criação.
- **imoveis-13 (demais ~28 campos do wizard), G.** Feito só `extraRooms` + catálogo. Faltam rooms, builtYear, unidade/torre/andar, garantias, isHighStandard etc. O endereço estruturado do proprietário depende do back (não está no DTO).
- **imoveis-25 (resto).** Faltam ownerName/Phone, number, unidade/torre/quadra/lote, createdFrom/To, captorsTeamId, teamId, responsibleUserId, sector e `listDeletedOnly` (filtro de excluídos). Faixas de venda/aluguel, suítes e rooms **dependem do back** (o `GET /properties` não lê).
- **imoveis-28 (resto), M.** Reordenar fotos (`PUT /gallery/reorder`, já existe em `gallery_service.dart` sem uso) e upload de vídeo (`POST /gallery/upload-video`). Obs.: `GalleryService.updateImage` usa `PATCH /gallery/:id`, mas a rota do back é `PUT` (método sem uso hoje; não mexi no service compartilhado).
- **Linha premium (`isSitePremiumLine`)**: continua sem gravar — correção no back (ver "Depende do back").
- Fora deste lote (não pedidos agora): imoveis-29, 33, 34, 35, 36, 37, 38, 39, 41, F3; título de fallback da IA.

Abreviações: **cpp** = `lib/features/properties/pages/create_property_page.dart` · **ps** = `lib/shared/services/property_service.dart` · **DP** = `lib/features/properties/pages/property_details_page.dart` · **PP** = `lib/features/properties/pages/properties_page.dart` · **PC** = `intellisys-CRM-Back/src/properties/properties.controller.ts` · **MA** = `intellisys-CRM-Back/src/properties/controllers/property-multi-approval.controller.ts` · web = `intellisys-CRM/src/...` (a auditoria chama de `imobx-front`).

Esforço: P = pequeno (≤ 1 dia) · M = médio · G = grande.

---

### P0 (9): todos feitos

| ID | Lacuna | App | Evidência no app | Web / back | Back? | Esforço |
|---|---|---|---|---|---|---|
| imoveis-01 | 16 tipos; tipo desconhecido não vira 'house' | **feito** | ps:339-379 (16 tipos), ps:909-911 (`typeRaw`), cpp:2498-2509 e cpp:3247 (não manda `type` desconhecido intocado) | back `entities/property.entity.ts:38-55` | não | — |
| imoveis-02 | 17 status (inclui `pending_publication` e os 9 do funil) | **feito** | ps:383-407, ps:432-489 (`isRentalFunnel`, `shortLabel`), ps:910-912 (`statusRaw`), cpp:3228/3323-3325 | back `property.entity.ts:57-88` | não | — |
| imoveis-03 | PATCH zera 9 booleanos e preços | **feito** | cpp:3307-3320: os booleanos só vão na criação. Preço vazio ainda vai como 0 (cpp:3269-3280), igual ao web (`utils/buildCreatePropertyApiPayload.ts:230-251`) | — | não | — |
| imoveis-04 | PATCH regrava captadores | **feito** | cpp:3335-3362: a edição não manda `capturedByIds`. Só manda `captorAssignments` (só o principal) quando a finalidade muda | back `update-property.dto.ts:705` | não | — |
| imoveis-05 | Duplicidade / 409 | **feito** | ps:2387 (`checkDuplicate`), ps:2426/2442 (409), cpp:1847-1879, cpp:3442-3494 (`duplicateConfirmedByUser`), `widgets/property_duplicate_sheet.dart` | PC:2215, `create-property.dto.ts:223` | não | — |
| imoveis-06 | Sem CEP → 'N/A' | **feito** | cpp:116-118, 982-983, 3256, 5055-5114 | `create-property.dto.ts:48` | não | — |
| imoveis-07 | Regra de áreas invertida | **feito** | cpp:1561-1597, 2812, 2825 (total opcional, construída obrigatória exceto terreno, teto 99.999.999,99). Ressalva: a geração por IA ainda exige área total (cpp:1263, 1915) | web `CreatePropertyPage.tsx:3767-3790`; back `properties.service.ts:5731-5735` | não | P (ressalva) |
| imoveis-08 | Negociação obriga mínimo | **feito** | cpp:1639-1675 | web `CreatePropertyPage.tsx:3809-3824` | não | — |
| imoveis-F1 | Editar vendido volta para 'Disponível' | **feito** | cpp:3221-3238, 3323-3328 (`omitWorkflowFieldsOnEdit`; o app nunca manda status na edição) | web `buildCreatePropertyApiPayload.ts:162-177,203-208` | não | — |

### P1 (19): 5 feitos · 7 parciais · 7 faltam

| ID | Lacuna | App | Evidência no app | Web / back | Back? | Esforço |
|---|---|---|---|---|---|---|
| imoveis-09 | Limites próprios do app | ✅ **feito 03/10** (cpp) · era falta | título ≥ 3 / descrição ≥ 10: cpp:1378, 1398, 1433, 1447, 4848, 4879. Quartos < 50: cpp:1600. Banheiros/vagas < 20: cpp:1613, 1626. Cidade/bairro 2-100: cpp:1499-1522. UF por regex: cpp:1536. Telefone ≥ 10: cpp:1733. Documento ≥ 11: cpp:1746. Aluguel < 999.999,99: cpp:2898 | web `CreatePropertyPage.tsx:3714-3880` só exige campo não vazio | não | P |
| imoveis-10 | Captadores por papel + responsáveis | **falta** | cpp:3330-3334: grava só o usuário logado em `capturedById`, `capturedByIds` e `responsibleUserIds`. Não há UI | web `CreatePropertyPage.tsx:3727-3731` (`evaluateCaptorSlots`); back `create-property.dto.ts:766,797,812` | não | G |
| imoveis-11 | Equipe sempre obrigatória | ✅ **feito 03/10** (cpp) · era parcial | O setup modal exige equipe na criação (`property_creation_setup_modal.dart:296-297`), mas o wizard deixa escolher "Não vincular" (cpp:4969-4972). A validação só vale com `teamId` em `_formRequiredKeys` (cpp:2665). O seletor some sem equipes (cpp:4942) | web `CreatePropertyPage.tsx:3732` | não | P |
| imoveis-12 | Permuta (`acceptsExchange` + `exchangeMaxValue`) | ✅ **feito 03/10** (cpp) · era parcial | O detalhe mostra (`widgets/details/property_values_section.dart:343-351`; parse em ps:708-711, 1085-1088). O wizard não tem: nenhuma ocorrência em cpp | web `utils/propertyExchange.ts:15-44`, `CreatePropertyPage.tsx:3825`; back `create-property.dto.ts:407,448`, `update-property.dto.ts:376,417` | não | P |
| imoveis-13 | ~30 campos do wizard | **falta** | O payload (cpp:3240-3377) não tem rooms, extraRooms, builtYear, alternativeCode, unitFloor, floors, buildings, elevators, sunPosition, propertySituation, lotArea/lotMeasureType, propertyUnity, tower, unitTypology, visitTime, siteContact, houseRules, nearby, garantias (5), ownersPercentage/ownersRate, siteMetaDescription, isHighStandard, hasPlaque, hasExclusivity, isPrivate, isSitePremiumLine. O app não consome `GET /property-catalog` | back `create-property.dto.ts:309-1097`; `property-catalog/property-catalog.controller.ts:25`. O endereço estruturado do proprietário (`ownerZipCode`, `ownerStreet`…) **não está no DTO**: o web manda e o back descarta | parcial (endereço do proprietário) | G |
| imoveis-14 | `pendingChangeRequest` / `resubmittedForApproval` | ✅ **feito 03/10** (ps, cpp, `utils/property_save_feedback.dart`) · era falta | ps:2457 devolve só `Property`. cpp:3530-3531 mostra "atualizada com sucesso!". Nenhuma ocorrência no `lib` | back `properties.service.ts:6940-6944`, `property-response.dto.ts:1128`; web `CreatePropertyPage.tsx:4552-4610` | não | P |
| imoveis-15 | Marcar vendido/locado | ✅ **feito 03/10** (PP, `property_status_change_sheet.dart`) · era parcial | Detalhe: "Alterar status" (DP:1356-1372, 5155-5162 → `widgets/details/property_status_change_sheet.dart:82-187`). Lista: nada (PP:4940-4984). Sem bloqueio `hasPendingFinancialApproval`. `markAsSold`/`markAsRented` (ps:2803, 2845) sem uso | PC:3436, 3485, 3535 | não | P |
| imoveis-16 | Ativar/desativar (+ parcial por finalidade) | ✅ **feito 03/10** (PP) · era parcial | O detalhe tem: DP:1391-1418, 5175-5181, `widgets/details/property_activation_sheet.dart:182, 369, 453` (escopo all/sale/rent). A lista não tem | PC:4019, 4066; `dto/deactivate-property.dto.ts` | não | P |
| imoveis-18 | Seção Proprietário + `canViewOwnerData`/`ownerDataRestricted` | **feito** | ps:670-675, 1062-1066; DP:4387-4394; `property_owner_section.dart:34-43` | `property-response.dto.ts:1070,1080` | não | — |
| imoveis-19 | Autorização: certificado, PDF assinado, selo e link no histórico | **feito** | DP:7806-7815, `property_owner_auth_certificate.dart:148,432`, `property_detail_extras_service.dart:540-546`, `property_history_entry_tile.dart:139-189,311`. Ressalva: o certificado fica dentro de Documentos e some se esse módulo estiver desligado (DP:7797-7803) | PC:483 | não | (P) |
| imoveis-20 | Card da ficha de venda vinculada | **feito** | ps:716-717, 1092; DP:4477-4492 | `property-response.dto.ts:1108` | não | — |
| imoveis-21 | Negociação, extraRooms, dados complementares no detalhe | **feito** | `property_values_section.dart:48-54, 330-404`; DP:6331-6337 (extraRooms); DP:4377-4384 (`property_additional_info_section.dart`). `rooms` não aparece, e o web também não mostra | — | não | — |
| imoveis-22 | Mudar voto (PUT) e ver os votos | ✅ **feito 03/10** (`property_approval_service.dart`, `approval_info_sheets.dart`) · era falta | Só tem POST `castVote` (`services/property_approval_service.dart:1102-1121`, chamado em `property_approvals_page.dart:587`). `approval_info_sheets.dart:812-952` mostra só os contadores | MA:296 (PUT), MA:257 (voting-status) | não | P |
| imoveis-23 | Abas Locados / Em negociação / Outros / Inativos + contagem | ✅ **feito 03/10** (PP, ps) · era falta | O enum de escopo tem só available/pending/rejected/sold (ps:1693-1697). Abas em PP:788-830. Não chama `portfolio-counts` | PC:2836-2887; `utils/property-list-query.util.ts:63-72`; web `types/property.ts:633-668` | não | M |
| imoveis-24 | "Todos" sem `includeInactive` | **feito** | PP:299-300, 322 | web `utils/buildCombinedPropertyFilters.ts:41-60` | não | — |
| imoveis-25 | Filtros e ordenação | **parcial** (03/10: + ordenação, finalidade, código; resto pendente) | Tem: type, status, city, state, neighborhood, faixa de preço, área, quartos, banheiros, vagas, destaque, busca, onlyMyData (ps:1756-1784). `street` e `condominiumId` só vêm da sugestão de busca (PP:311-316). O CEP aparece no drawer (`property_filters_drawer.dart:551`) mas não vai na query. Faltam sortBy/sortOrder, ownerName/Phone, number, unidade/torre/quadra/lote, createdFrom/To, captorsTeamId, teamId, responsibleUserId, finalidade, sector, listDeletedOnly | back lê pelo controller (PC:2711-2754). Faixas venda/aluguel, suites e rooms **não** são lidas pelo back | não (exceto as faixas) | G |
| imoveis-26 | Exportar gera arquivo + dryRun | ✅ **feito 03/10** (ps, `export_import_dialog.dart`) · era falta (e quebrado) | `widgets/export_import_dialog.dart:33` (TODO). ps:3032/3042 usa **GET**, e o back é POST. Não manda filtros nem dryRun | PC:4237-4294 (POST, `dryRun`); web `services/propertyApi.ts:2256-2300` | não | P/M |
| imoveis-28 | Galeria: reordenar, ocultar do site, vídeo | **parcial** (03/10: + ocultar do site; reordenar e vídeo pendentes) | O vídeo é exibido no detalhe (DP:2648-2655, 10167-10177). Faltam upload de vídeo, reordenar (`gallery_service.dart:343` sem uso) e o toggle `showOnPublicSite` (parse em ps:1206/1283, sem UI) | back `gallery/gallery.controller.ts:554` (upload-video), :673 (reorder), :800 (PUT) | não | M |
| imoveis-F2 | Atalho Publicar/Ocultar do site | ✅ **feito 03/10** (PP, DP) · era parcial | Não está no sheet da lista nem no do detalhe. Existe "Republicar" (DP:1373-1390) e a aba Site, que só aparece sem esteira de aprovação (DP:4175-4191) | web `PropertiesPage.tsx:3276-3279, 3383-3408` | não | P |

### P2 (17): 5 feitos · 3 parciais · 9 faltam

| ID | Lacuna | App | Evidência no app | Web / back | Back? | Esforço |
|---|---|---|---|---|---|---|
| imoveis-17 | Aba Visualizações | **feito** | DP:4161-4171, 4217-4228; `property_viewers_tab.dart` | PC:3635 | não | — |
| imoveis-27 | Exportar/Importar sem permissão | ✅ **feito 03/10** (`export_import_dialog.dart`, PP) · era falta | PP:3757-3763 sem gate. `core/constants/app_permissions.dart:15` não tem `property:import` | PC:4238, 4392 | não | P |
| imoveis-29 | owner-check | **falta** | nenhuma ocorrência | PC:2230; web `propertyApi.ts:561` | não | P |
| imoveis-30 | Aba Site | **feito\*** | DP:4170, 4229-4242; `property_site_tab.dart:99,128`. \*A linha premium não persiste (bug 4 do resumo, no back) | `update-property.dto.ts` sem `isSitePremiumLine` | **sim** (premium) | P (back) |
| imoveis-31 | Revisões + restaurar + effectiveChanges | **feito** | DP:5804-5813; `property_detail_extras_service.dart:402-441`; `property_history_entry_tile.dart:320-337` | PC:3859, 3891 | não | — |
| imoveis-32 | Apresentação em PDF | **feito** | DP:991, 1307-1323; `property_presentation_pdf_sheet.dart:30-60` (compartilhar/salvar); `property_presentation_service.dart:38` | PC:417 | não | — |
| imoveis-33 | Conversa de aprovação | **parcial** | Editar/apagar feitos (`property_approval_service.dart:752-802`, DP:857-939). Faltam `mark-seen` e a caixa de conversas | MA:417, MA:223 | não | M |
| imoveis-34 | Change requests "minhas" + selo "Edição pendente" | **parcial** | O serviço aceita mine/propertyId (`property_approval_service.dart:1128-1138`), mas a tela não usa (`property_approvals_page.dart:203-205`). Sem `pending-property-ids` | `property-change-requests.controller.ts:63-78, 101` | não | P |
| imoveis-35 | lastActivity no card | **falta** | pede `includeLastActivity=true` (ps:1984) mas não faz o parse | `property-list-query.util.ts:45,130` | não | P |
| imoveis-36 | Telas de configuração | **falta** | só lê `approval-settings/active` e `form-settings` (ps:2034, 2064) | PC:213-282; `protected-owner-data.controller.ts:39` | não | G |
| imoveis-37 | Mapa da carteira | **falta** | nenhuma ocorrência | PC:3012; web `pages/PropertiesMapExplorer.tsx` | não | G |
| imoveis-38 | Relatório de captações | **falta** | só a estatística em `features/analytics/pages/advanced_analytics_page.dart:85-135` | `analytics/captures-analytics.controller.ts:157`; web `pages/CapturesReportPage.tsx` | não | M |
| imoveis-39 | Lembrete stale | **falta** | nenhuma ocorrência | `properties-stale-for-user.controller.ts:40`; web `components/modals/StalePropertiesModal.tsx` | não | M |
| imoveis-40 | Desvincular cliente | **feito** | DP:7187-7260 | — | não | — |
| imoveis-41 | Geocode / lat-long | **parcial** | "Atualizar no mapa" no detalhe (DP:1777-1816, 8441-8463). O wizard não envia lat/long | PC:3585; `create-property.dto.ts:247` | não | P |
| imoveis-F3 | Análise preditiva (IA) | **falta** | `ai_service.dart:339-346` existe, mas nada o chama | `ai-assistant.controller.ts:133`; web `PropertiesPage.tsx:3438` | não | M |
| imoveis-F4 | Apagar e-mail do proprietário | ✅ **feito 03/10** (cpp) · era falta | cpp:3298 manda `''` (o DTO transforma em undefined) | web `buildCreatePropertyApiPayload.ts:301-307` | não | P |

### Card do funil (pendências citadas)

| Pendência | App | Evidência | Back? | Esforço |
|---|---|---|---|---|
| Permuta obrigatória (`acceptsExchange` + `exchangeMaxValue`) | ✅ **feito 03/10** | = imoveis-12. Só aparece no detalhe. Back: o campo é opcional (`properties.service.ts:5692-5715`); a obrigatoriedade é só do web | não | P |
| Cômodos/infra extras do catálogo (`GET /property-catalog` + `extraRooms`) | ✅ **feito 03/10** (cpp) | DP:6331. O app não chama `/property-catalog` | não | M |
| "Alterar status" + 9 status do funil | ✅ **feito 03/10** (também na lista) | Feito no detalhe (`property_status_change_sheet.dart:96-156, 327-357`; DP:1356-1372). Falta na lista | não (`change-property-status.dto.ts:11` `@IsEnum(PropertyStatus)` já tem os 17) | P |
| `pendingChangeRequest` no PATCH | ✅ **feito 03/10** | = imoveis-14 | não | P |
| `canViewOwnerData` / `ownerDataRestricted` | **feito** | = imoveis-18 | não | — |
| `publishableImageCount` | ✅ **feito 03/10** (`utils/property_publish_rules.dart`) | 0 ocorrências no `lib`. A aba Site não valida quantas fotos há | não (`property-response.dto.ts:485`) | P |
| Preço "0.00" = não se aplica; venda+locação mostra os dois | ✅ **feito 03/10** (`utils/property_price_display.dart`) | Os dois preços preenchidos aparecem certos. Com um deles 0, aparece "R$ 0" (PP:3421-3425; `property_values_section.dart:91,101`). `parseDouble` faz "0.00" → 0.0 (ps:849-857) | não | P |
| Vídeo na galeria (`mediaType`, `hasVideo`) | **parcial** | Parse em ps:1198-1276 e ps:1096. Exibição no detalhe feita. Faltam o badge na lista (`hasVideo` sem uso) e o upload | não | M |
| Apresentação em PDF (baixar + compartilhar) | **feito** | = imoveis-32 | não | — |
| Tela "Vendidos e Locados recentemente" | ✅ **feito 03/10** (`pages/recent_deals_page.dart`) | nenhuma ocorrência no `lib` | não (PC:2903-3010; web `pages/RecentDealsPage.tsx`, `properties.routes.tsx:573-589`) | M |
| Imóvel excluído em modo consulta | **parcial** | O detalhe em modo consulta está feito (ps:845, DP:334-337, 3217-3222). Não há como chegar a ele pela lista: falta o filtro `listDeletedOnly` | não (`property-list-query.util.ts:47,132`) | P |
| Título por IA não trava o cadastro | **parcial** | A falha da IA é silenciosa (cpp:1976-1977), mas não há título de fallback: a revisão exige título ≥ 3 (cpp:1760-1779). A geração nem roda sem área total (cpp:1915-1917) | não (web `CreatePropertyPage.tsx:3480` `fallbackTitleAfterAiMiss`) | P |
| Teto de área | **feito / não se aplica** | Não existe teto de 400 m² no web nem no back. O "400" é o HTTP 400 amigável acima de 99.999.999,99 (`properties.service.ts:5561,5732`). O app usa o mesmo teto (cpp:1565) | não | — |
| Step MCMV oculto na criação | **feito** | O wizard tem 7 etapas, sem MCMV (cpp:55), e não manda `mcmv*` | não | — |
| Placeholder sem foto | **feito** | PP:3035, 5199-5236, 5276-5285; DP:2819-2849 | não | — |

### Depende do back

- **`isSitePremiumLine` no PATCH.** Incluir no `UpdatePropertyDto` ou gravar via `site-showcase`. Hoje a "Linha premium" não persiste no web nem no app.
- **Endereço estruturado do proprietário** (`ownerZipCode`, `ownerStreet`…). Não está no DTO, então o web também perde esses dados. Resolver no back antes de levar ao app (parte de imoveis-13).
- **Faixas `min/maxSalePrice`, `min/maxRentPrice`, `suites`, `rooms` na listagem.** O back não lê esses parâmetros (parte de imoveis-25).
- Fora isso, tudo o que falta é trabalho **só no app**: endpoints e campos já existem no back atual. Não verifiquei se o back de produção está igual ao `master`.

### Ordem de execução sugerida

1. **Bugs rápidos que afetam dado ou uso (P):**
   - exportação: trocar GET por POST, salvar e compartilhar o arquivo, dryRun e filtros (imoveis-26), mais o gate de permissão (imoveis-27);
   - "Apenas inativos" → `portfolioScope=inactive`;
   - `ownerEmail: null` na edição (imoveis-F4);
   - preço 0 = não se aplica;
   - aviso de `pendingChangeRequest` (imoveis-14).
2. **Wizard sem travas indevidas (P):** remover os limites próprios (imoveis-09), equipe obrigatória (imoveis-11), permuta no wizard (imoveis-12), título de fallback da IA e sem exigir área total para a IA.
3. **Aprovação (P):** PUT do voto com lista de votos (imoveis-22), selo "Edição pendente" e toggle "Minhas" (imoveis-34), `mark-seen` (imoveis-33).
4. **Ações na lista (P):** reaproveitar os sheets do detalhe no menu do card: alterar status / vendido / locado com bloqueio financeiro (imoveis-15), ativar/desativar (imoveis-16), Publicar/Ocultar com `publishableImageCount` (imoveis-F2 + card).
5. **Carteira (M):** abas Locados / Em negociação / Outros / Inativos com `portfolio-counts` (imoveis-23), `lastActivity` no card (imoveis-35), badge de vídeo, filtro de Excluídos e os demais filtros e ordenação (imoveis-25).
6. **Tela "Vendidos e Locados recentemente"** (`recent-deals`, M).
7. **Cadastro completo (G):** captadores por papel e responsáveis (imoveis-10); campos extras com `/property-catalog` e `extraRooms` (imoveis-13), depois de o back aceitar o endereço do proprietário; owner-check (imoveis-29); lat/long (imoveis-41).
8. **Galeria (M):** upload de vídeo, reordenar, mostrar no site (imoveis-28).
9. **Resto dos P2:** caixa de conversas (imoveis-33), stale (imoveis-39), análise preditiva (imoveis-F3), relatório de captações (imoveis-38), mapa (imoveis-37), telas de configuração (imoveis-36).
10. **Back (em paralelo, outro dono):** `isSitePremiumLine` no `UpdatePropertyDto`, endereço estruturado do proprietário e faixas de preço/suites/rooms na listagem.

---

## Paridade web × app — Ficha de Venda e Ficha de Proposta (03/10/2026)

### Execução (03/10/2026, no app) — status

1ª rodada (03/10, manhã): itens P0/P1. 2ª rodada (03/10, tarde): todos os P2, rascunho da proposta, trava por tela e a correção do back (P4). **Nada pendente**: toda linha abaixo está ✅ ou "não se aplica" com o motivo. `flutter analyze` sem erro/aviso novo nos arquivos tocados (os erros do analyze geral estão em `features/properties`, frente de Imóveis em andamento); `flutter test` 100% (294 testes). Back: teste novo do módulo passando e typecheck sem erro no recorte. Nada testado em aparelho.

| Ordem | Item | Status |
|---|---|---|
| 1 | V1 + P1 — `contentType` no upload de anexo | ✅ `shared/utils/ficha_anexo_content_type.dart` (pdf/jpg/jpeg/png/webp → mimetype aceito pelo back), usado em `sale_forms_service.dart` e `purchase_proposals_service.dart` |
| 2 | Item 6 — "DISPAROS MANYCHAT" e legado | ✅ `features/sale_forms/sale_form_media_sources.dart` (oficial + legado = `MIDIAS_ORIGEM_FICHA_VENDA_COMPLETA`); na edição o valor gravado é mantido e entra como opção se estiver fora da lista (inclusive o `'DISPAROS'` antigo do app) |
| 3 | V3 — equipes com `useInSaleForms=true` | ✅ `SaleFormLookupService.equipesDeFichas()` (`GET /teams?useInSaleForms=true`) no modal de tipo e também no "Trocar equipe" (o web usa o mesmo filtro em `SaleFormsPage.tsx:3110`) |
| 4 | V2 — imóvel pelo código + `propertyId` | ✅ Busca `GET /properties?code=` sem vendido/alugado, preenche o endereço e grava `propertyId` (DTO `sale-form-auth.dto.ts:361`); mexer no código desfaz o vínculo; na edição vai `null` sem vínculo, como o web. Aviso do status atual do imóvel (`linkedPropertyFinalizeNotice`). Lógica em `features/sale_forms/sale_form_property_link.dart` |
| 5 | V7 — trava reavaliada | ✅ Igual ao web: `SignatureLockRouteObserver` (`sale_form_signature_lock_sheet.dart`, registrado em `main.dart` com 1 linha em `navigatorObservers`) consulta a cada tela nova (push/replace/volta; diálogos e folhas não contam), menos nas telas que o web pula (`/`, login, recuperação de senha, 2FA, `/sale-forms…`, `/rental-forms…`; as telas de ficha sem nome se marcam com `marcarTelaDeFicha`). Continua também na Home e ao voltar ao primeiro plano. O back sobe o contador no máximo 1×/dia por ficha (`isSameUtcDay`), então o intervalo caiu de 90 s para 2 s (só junta rajadas). Regra em `signature_lock_policy.dart` (`signatureLockRotaIgnorada`) |
| 5 | V8 — assinaturas após criar | ✅ A criação devolve `SaleFormCreatedResult` e a lista abre `showSaleFormSignaturesSheet` da ficha nova (edição não abre, como o web) |
| 6 | V4 — detalhe completo | ✅ `sale_form_detail_page.dart`: dados gerais, comprador/vendedor e cônjuges completos, imóvel (endereço, vínculo com o cadastro) ou empreendimento, financeiro (confissão, financiamento 100%, descrição), parcelas, comissões (função, %/valor fixo, gerências, nota), colaboradores, usuários vinculados e registro |
| 6 | V5 — histórico / Raio-X | ✅ `pages/sale_form_audit_page.dart` com `getAuditoria`, linha do tempo, antes → depois formatado como o web (datas, R$, CPF/CNPJ, telefone, CEP, status, JSON de comissões) e sem as mudanças só de formato. Lógica em `sale_form_audit_display.dart` |
| 7 | V6 — exportação XLSX | ✅ Não existe endpoint no back (o web monta no navegador com SheetJS). O app faz o mesmo: `listForExport` (páginas de 100, `includeLastAuditChanges=true`, até 5000) + `sale_forms_relatorio_export.dart` (abas «Relatório fichas», «Auditoria detalhada», «Como ler», mesmas colunas) + gerador XLSX próprio sem dependência nova (`xlsx/simple_xlsx.dart`). Sai pela folha padrão de Compartilhar / Salvar no aparelho |
| 8 | V9 — rascunho da venda | ✅ `ficha_draft_store.dart` (por usuário e empresa, versão no JSON); autosave a cada 2 s e ao sair, só na criação e só quando há algo preenchido; ao tocar "Nova ficha" com rascunho: "Retomar rascunho" / "Começar do zero"; apagado ao criar |
| 8 | P2 — rascunho da proposta | ✅ `features/proposals/utils/proposal_draft.dart` (serializador próprio; "em branco" como o web: compara com o formulário inicial, ignora a equipe, conta usuários vinculados; ao restaurar descarta nascimento = hoje). Grava pelo `FichaDraftStore` tipo `'proposta'`; autosave a cada 2 s e ao sair, só na criação; apagado ao criar; toast "Seu rascunho foi recuperado". "Nova proposta" com rascunho: "Retomar rascunho" / "Começar nova" / "Descartar" (diálogo do web). `create_proposal_page.dart` (parâmetro `rascunho`), `proposals_page.dart`. A rota nomeada `AppRoutes.proposalCreate` não passa pela pergunta, mas nada no app a usa |
| 9 | V15 | ✅ Motivo de cancelar/excluir/distratar ≥ 5 caracteres (`FichaActionReasonDto`); falha ao vincular usuários avisa (venda e proposta). **Filtros persistidos**: `sale_forms_filters_storage.dart` (espelho de `saleFormsFiltersStorage.ts`: busca, status, criadores, equipes, unidade, datas, ordenação e "Apenas excluídas", por empresa, vencem em 30 dias, ids/valores saneados). **Nascimento**: picker não passa de hoje e a regra da aba barra data futura pré-preenchida (`saleFormBirthDateFutureError`) |
| 9 | V10 | ✅ `processing` = "Em processamento" / curto "Em processo" (iguais a `saleFormStatusLabel`/`ShortLabel`); o hero mostra "N aguardando assinatura · N em andamento" separados como os chips do web (`saleFormsHeroResumo`) |
| 9 | V11 | ✅ Linha da lista com a rastreabilidade do web (`saleFormTraceabilityOneLine`): `lastAudit.summary`, senão exclusão, cancelamento, desativação automática (`ativo=false`, com ícone de alerta), recusa da trava (data + justificativa), criação e atualização (`sale_form_list_display.dart`, `sale_form_card.dart`) |
| 9 | V12 | ✅ `nivel` como o web: mantém o gravado; renumera 1..n entre TODAS as gerências (inclusive sem %) só quando uma entra/sai (`saleFormGerenciaNiveis`) |
| 9 | V13 | ✅ `saleUnitId` = unidade de venda configurada (`GET /sistema/sale-units-config?activeOnly=true`) com o mesmo nome da "Unidade responsável"; ao criar, a unidade da equipe escolhida é sugerida quando ainda não há unidade (`SaleFormTypeChoice.teamUnitId`) |
| 9 | V14 | ✅ `AutentiqueStatusService` (`useAutentiqueStatus`): integração inativa desativa "Gerar links" com a mensagem do web; falha na consulta não trava |
| 9 | P3 | ✅ Reenvio por WhatsApp só aparece com `canResend` (`GET …/assinaturas/whatsapp-envio`, rota corrigida no back) e link; o retorno diz o que saiu (enviados, sem telefone, falhas) e "Nenhuma mensagem enviada." quando nada saiu. Mantido porque o back suporta e a ficha de venda do web usa a mesma trava (o web da proposta não oferece) |
| 9 | P5 | ✅ Autentique inativa trava Enviar/Gerar link na proposta (mesmo serviço do V14) |
| 9 | P6 | ✅ `create` espera 400 ms e tenta de novo em 409 `DUPLICATE_ENTRY` (`proposalCreateShouldRetry`), como `purchaseProposalsApi.ts:269-288` |
| 9 | P7 | ✅ `proposalAnexoAprovadoMsg`: "Anexo aprovado. Etapa N+1 liberada." / "Anexo enviado e aprovado. …" (textos do web) |
| 9 | P8 | ✅ "PDF + assinado (.zip)" no modal de assinaturas (quando há etapa assinada) e no menu da linha (finalizada ou após a etapa 1); sem assinado o back devolve só o PDF e a tela avisa |
| 9 | P9 | ✅ `/fichas-proposta?highlightProposal=:id` e `/fichas-proposta/:id/editar` abrem a proposta (`app_deep_link.dart`, 3 testes novos) |
| 9 | P10 | ✅ `ProposalSignature.statusLabel` com os rótulos do web (Assinado, Rejeitado, Visualizado, Aprovado, Pendente). Única diferença consciente: cancelada aparece "Cancelado" (o web mostra "Pendente", o que engana) |
| — | P4 (back) | ✅ **Corrigido no back**: `GET :id/assinaturas/whatsapp-envio` agora é declarado antes de `GET :id/assinaturas/:signatureId` (`purchase-proposals.controller.ts`). Teste `purchase-proposals.controller.routes.spec.ts` (3 casos) lê os metadados das rotas e falha se qualquer rota da proposta ou da ficha de venda for sombreada por outra com parâmetro declarada antes (a ficha de venda já estava certa). Registrado no obsidian do back |

Somente análise; nenhum código foi alterado. Base: código atual dos três repos (app `dreamkeysapp/lib`, web `intellisys-CRM/src`, back `intellisys-CRM-Back/src`, este último em sincronia com `origin/master`, HEAD `0a666b14` de 02/10). O deploy do back não foi conferido em produção: "depende do back = s" quer dizer que a rota ou o DTO já existe no `master` do back. Nada foi testado em aparelho.

### Resumo (da análise inicial — todos os achados abaixo já foram resolvidos, ver "Execução")

- **As pendências do card estão quase todas resolvidas no app.**
  - O app só usa os endpoints JWT `/sistema/fichas-venda` e `/sistema/fichas-proposta`. Não sobrou nenhuma chamada à ficha pública por CPF, que foi removida do back.
  - Comissões ("outros", parcelamento e travas), reassinatura da proposta, limite de 2000 caracteres e PDF sem bloqueio por `ativo` já estão espelhados.
- **Falta 1 item do card: "DISPAROS MANYCHAT".**
  - O app ainda grava `'DISPAROS'`.
  - Pior: ao editar uma ficha que veio do web com `'DISPAROS MANYCHAT'` ou com um valor legado, o app descarta a mídia, porque ela não está na lista. O usuário fica obrigado a escolher de novo e grava o valor antigo.
- **2 itens do card não se aplicam ao app** (Nova Venda por ficha e Conversa da venda): são do módulo Financeiro (`intellisys-financeiro`, `/sales/...`), que o app não tem. As notificações `SALE_COMMENT` e `SIGNATURE_PENDING` vêm do back do financeiro, que o app não consome. Mesmo que chegassem, o tipo é `String` com `default`, então não quebram.
- **Achado novo, P0:** o upload de anexo (ficha física) do app vai sem `contentType`. O pacote `http` manda então `application/octet-stream`, e o back recusa com "Tipo inválido. Use PDF, JPEG, PNG ou WEBP." Acontece na venda e na proposta.
- **Achados novos, P1 (venda):**
  - O app não busca o imóvel nem grava `propertyId`.
  - A lista de equipes do modal de tipo é pedida sem `useInSaleForms=true`.
  - O detalhe mostra só um resumo, e a auditoria ("Raio-X") e a exportação XLSX não aparecem.
  - A trava de assinatura é verificada uma vez por sessão.
  - O modal de assinaturas não abre depois de criar a ficha.
  - Não há rascunho local (isso vale para a venda e para a proposta).

### Tabela — pendências do card do funil

| # | Item | App | Evidência | Depende do back | Esforço | Sev. |
|---|---|---|---|---|---|---|
| 1 | Ficha/proposta pública por CPF removida; usar JWT | **Feito** | App: `core/constants/api_constants.dart:618-722` (só `/sistema/fichas-*`). Nenhuma referência a ficha pública em `lib/`. Back: `src/public/**` não tem mais controller de ficha/proposta. Controllers JWT: `sale-forms/sale-forms.controller.ts:62`, `purchase-proposals/purchase-proposals.controller.ts:62` | s (já no master) | — | — |
| 2 | Modelos de documento por empresa (sem o conteúdo fixo da União) | ✅ **Feito no PDF (resolvido no back)**; tela de configuração **não se aplica**: é administrativa e o app não tem nenhuma tela de configuração das fichas (o app só consome o PDF já resolvido pelo back) | Back: `document-models/document-models.service.ts:135` `resolveForCompany`, usado em `public/services/sale-form.service.ts:3175` e `public/services/purchase-proposal.service.ts:1616`. O app baixa o PDF do back (`shared/services/sale_forms_service.dart:1337`, `purchase_proposals_service.dart:1275`) e não tem texto fixo da União nas fichas; a única ocorrência é o filtro de signatários institucionais, espelho do web/back, em `sale_forms_service.dart:1041-1057`. Web: a configuração fica em `/fichas-venda/modelos-documentos` (`pages/SaleFormDocumentModelsConfigPage.tsx`), sem equivalente no app | s | M (se quiserem a tela no app) | P2 |
| 3a | Comissões: função "outros" | **Feito** | App: `features/sale_forms/pages/create_sale_form_page.dart:192,914`. Back DTO: `sale-forms/dto/sale-form-auth.dto.ts:815` | s | — | — |
| 3b | Parcelamento da comissão | **Feito** | App: `create_sale_form_page.dart:534,819-824,1455-1462,2597-2635`; `sale_form_rules.dart:351-358`. Back: DTO `:755-764`, regra em `sale-forms.service.ts:1756-1764` | s | — | — |
| 3c | Travas de comissão por empresa | **Feito** | App: `sale_forms_service.dart:1131-1143` (`GET /sistema/mandatory-signer-config/settings/sale-form-commission-rules`), `create_sale_form_page.dart:665,1327`. Back: `mandatory-signer-config.controller.ts:169` | s | — | — |
| 4 | Reassinatura da proposta após mudar valor | **Feito** | App: `features/proposals/pages/create_proposal_page.dart:549-571` (`_reinicioDecision`, igual a `getReinicioDecision` do web), `:828-869` (confirmação, PATCH e `reiniciar-fluxo-assinaturas`). Web: `pages/CreatePurchaseProposalPage.tsx:869-897,1417-1531`. Back: `purchase-proposals.controller.ts:419`. Obs.: o guard `PROPOSTA_ASSINADA_VALOR_ALTERADO` (`public/services/purchase-proposal.service.ts:1360-1375`) só existe no fluxo público; o PATCH JWT não o tem, e nem o web nem o app enviam `confirmarAlteracaoComAssinatura` | s | — | — |
| 5 | Condições de Pagamento ≤ 2000 caracteres | **Feito** | App: `create_proposal_page.dart:600-603` (validação) e `:2005-2010` (`maxLength: 2000`). Web: `CreatePurchaseProposalPage.tsx:2002-2004`. Back: o DTO da proposta não tem `@MaxLength` (`proposal-auth.dto.ts:185-188`); o limite está só nos clientes | n | — | — |
| 6 | Mídia "DISPAROS" → "DISPAROS MANYCHAT" | ✅ **Feito 03/10** (era: Falta) | App: `create_sale_form_page.dart:44` ainda tem `'DISPAROS'`; `:744-745` descarta, na edição, qualquer mídia fora da lista (o legado do web e o próprio `'DISPAROS MANYCHAT'`). Web: `constants/midiasOrigemFichaVenda.ts:22` e lista completa com legado em `:70-83`. Back normaliza no dashboard: `shared/fichas-dashboard/media-source-normalizer.ts:25-30` | n | P | **P1** (dado gravado diferente e perda do valor ao editar) |
| 7 | PDF não bloqueia por `ativo=false` (só `deletedAt`) | **Feito** | App: `features/sale_forms/widgets/sale_form_row_rules.dart:76` (`canPdf = export && finalizada && !deleted`, sem `ativo`). Web: `pages/SaleFormsPage.tsx:2505-2524`. Back: `public/services/sale-form.service.ts:2118` ("Não bloqueamos por `ativo=false`") e `sale-forms.controller.ts:420-429` | s | — | — |
| 8 | Nova Venda com origem por ficha (select + preenchimento automático) | **Não se aplica** (é do módulo Financeiro — `intellisys-financeiro`, `/sales/...` —, frente própria; não é tela das fichas) | Web: `components/financeiro/vendas/DrawerVendaForm.tsx:1089-1244,2852-2899` (`financeiroApi.listFichasVenda`/`getFichaPrefill`, back `intellisys-financeiro`). O app não tem `features/financeiro` nem "Nova venda" | s (financeiro) | G (o módulo inteiro) | — |
| 9a | Conversa por ficha de venda (`/sales/:id/comments`) | **Não se aplica** (é da venda do Financeiro, `/sales/:id`, não da ficha `/sistema/fichas-venda`; fica com a frente do Financeiro, `fin-20`) | Web: `services/financeiroApi.ts:4782-4858`, `components/financeiro/vendas/DrawerVendaChat.tsx`. Back: `intellisys-financeiro/apps/api/src/modules/vendas/sale-chat.controller.ts`. Já registrado como `fin-20` (P2) na auditoria de 29/09 | s (financeiro) | M | P2 |
| 9b | Notificações `SALE_COMMENT` e `SIGNATURE_PENDING` sem quebrar o switch | ✅ **OK (não quebra)**; entregá-las ao app **não se aplica** às fichas (vêm do back do Financeiro) | App: `features/notifications/models/notification_model.dart:4,73` (`type` é `String`); `utils/notification_navigation.dart:33-87` (`default: 'Notificação'`); `widgets/notification_list.dart:95-102` (alvo nulo vira aviso discreto). Os dois tipos vêm de `intellisys-financeiro` (`packages/shared/src/types/notification-catalog.ts:259-271`), que o app não consulta | n | — | P2 (o corretor não recebe no app "ficha aguardando sua assinatura" do financeiro) |

### Tabela — diferenças novas (comparação tela a tela)

#### Ficha de venda

| # | Diferença | App | Evidência | Depende do back | Esforço | Sev. |
|---|---|---|---|---|---|---|
| V1 | Upload de anexo sem `contentType`; o back recusa | ✅ **Feito 03/10** | App: `shared/services/sale_forms_service.dart:2080-2085` (`http.MultipartFile` sem `contentType`, então vai como `octet-stream`). Back: `sale-forms.controller.ts:516-531` (filtro por mimetype). Web: `FichaVendaAnexosModalPrivate.tsx:288` | n | P | **P0** |
| V2 | Imóvel não é buscado pelo código e `propertyId` não é gravado | ✅ Feito 03/10 | Web: `CreateSaleFormPage.tsx:3251-3293,3640,3892-3895`. App: o payload em `create_sale_form_page.dart:1426-1435` não tem `propertyId`. Back DTO: `sale-form-auth.dto.ts:361`. Efeito: a ficha do app não fica ligada ao imóvel, que não vira "Vendido" ao concluir | s | M | P1 |
| V3 | Equipes do modal de tipo sem `useInSaleForms=true` | ✅ Feito 03/10 | Web: `SaleFormTypeModal.tsx:137-143`. App: `features/sale_forms/widgets/sale_form_type_modal.dart:72-83` filtra no aparelho. Back: `teams.controller.ts:148-155` só amplia a lista para quem tem `view_all` quando recebe o parâmetro, então um gestor pode ver "Nenhuma equipe habilitada" | s | P | P1 |
| V4 | Detalhe resumido (o web abre o formulário completo só para leitura) | ✅ Feito 03/10 | Web: `CreateSaleFormPage.tsx:2252-2262,2549`. App: `pages/sale_form_detail_page.dart:288-391` (faltam cônjuges, parcelas, usuários vinculados e o imóvel completo) | s | M | P1 |
| V5 | Auditoria / "Raio-X" da ficha | ✅ Feito 03/10 | Web: `SaleFormsPage.tsx:3074-3095`. App: `sale_forms_service.dart:1850` `getAuditoria` sem nenhuma tela que o use. Back: `sale-forms.controller.ts:355` | s | M | P1 |
| V6 | Exportar relatório XLSX da lista | ✅ Feito 03/10 (gerado no app, como o web) | Web: `SaleFormsPage.tsx:3561-3597`, `ExportSaleFormsRelatorioModal.tsx:205-224`, `utils/saleFormsRelatorioExport.ts` | s | M | P1 |
| V7 | Trava de assinatura verificada só uma vez por sessão | ✅ Feito 03/10 (Home, primeiro plano, saída da ficha; intervalo 90 s) | Web: `routes/SignatureLockGate.tsx:160-184` (verifica a cada rota; o modal não fecha). App: `features/dashboard/pages/dashboard_page.dart:84-94` (flag estática) e `widgets/sale_form_signature_lock_sheet.dart:189-193` | s | P | P1 |
| V8 | Modal de assinaturas não abre depois de criar a ficha | ✅ Feito 03/10 | Web: `CreateSaleFormPage.tsx:4032`. App: `create_sale_form_page.dart:1603` (só dá `pop`) | s | P | P1 |
| V9 | Rascunho local ("Retomar rascunho") | ✅ Feito 03/10 | Web: `CreateSaleFormPage.tsx:2439,2541-2553,3172-3184` | n | M | P1/P2 |
| V10 | Rótulo do status `processing` ("Em processamento" × "Em assinatura"/"Assinando") e contador somado ao "aguardando" | ✅ Feito 03/10 (2ª rodada) | Web: `SaleFormsPage.tsx:1766,3368-3384`. App: `sale_forms_service.dart:34,48`, `pages/sale_forms_page.dart:435,717` | n | P | P2 |
| V11 | Rastreio na linha: `lastAudit.summary`, recusa da trava (data e motivo), aviso de "desativada automaticamente" (`ativo=false`) | ✅ Feito 03/10 (2ª rodada) | Web: `SaleFormsPage.tsx:1844-1873,1906-1911,3703-3713`. App: `widgets/sale_form_card.dart` não lê esses campos | s | P | P2 |
| V12 | Nível das gerências renumerado 1..n (o web mantém o `nivel` do estado), o que muda o rótulo no PDF | ✅ Feito 03/10 (2ª rodada) | Web: `CreateSaleFormPage.tsx:3970,4371-4374`. App: `create_sale_form_page.dart:1479-1488`. PDF: `public/services/sale-form.service.ts:3773,3954` | s | P | P2 |
| V13 | `saleUnitId` não enviado / unidade não sugerida pela equipe | ✅ Feito 03/10 (2ª rodada) | Web: `CreateSaleFormPage.tsx:2961-2966,2979-2992,3819`. App: `create_sale_form_page.dart:1387-1392,2209-2236` (o back deduz pela `saleUnit`) | s | P | P2 |
| V14 | Integração Autentique não é verificada antes de "Gerar links" | ✅ Feito 03/10 (2ª rodada) | Web: `SaleFormSignatureModalPrivate.tsx:125,1371-1379`. App: `widgets/sale_form_signatures_sheet.dart:364-441` | s | P | P2 |
| V15 | Pequenos: filtros não persistidos; falha ao vincular usuários ignorada; nascimento aceita data futura; motivo de cancelar/excluir aceita menos de 5 caracteres (o back exige 5) | ✅ Feito 03/10 (motivo ≥ 5, aviso de vínculo, filtros persistidos, nascimento futuro) | App: `sale_forms_page.dart:51`; `create_sale_form_page.dart:1581-1583,1619-1626`; `widgets/sale_form_row_actions.dart:319`. Back: `ficha-action-reason.dto.ts:18` | n | P | P2 |

#### Ficha de proposta

| # | Diferença | App | Evidência | Depende do back | Esforço | Sev. |
|---|---|---|---|---|---|---|
| P1 | Upload de anexo sem `contentType`; o back recusa | ✅ **Feito 03/10** | App: `shared/services/purchase_proposals_service.dart:1604-1609`. Back: `purchase-proposals.controller.ts:279-295`. Web: `purchaseProposalsApi.ts:355-362` | n | P | **P0** |
| P2 | Rascunho local ("Retomar rascunho") | ✅ Feito 03/10 (2ª rodada) | Web: `CreatePurchaseProposalPage.tsx:1019-1035`, `PurchaseProposalsPage.tsx:2196-2216` | n | M | P1/P2 |
| P3 | Reenvio por WhatsApp oferecido sem checar disponibilidade e com toast "iniciado" mesmo quando nada foi enviado | ✅ Feito 03/10 (só com `canResend`; retorno real do envio) | App: `features/proposals/widgets/proposal_signatures_sheet.dart:540-547,1046-1047`. Back: `proposal-notification.service.ts:170-204` | s | P | P2 |
| P4 | Bug no back: `GET :id/assinaturas/whatsapp-envio` é capturado por `GET :id/assinaturas/:signatureId`, declarado antes (não testado) | ✅ Corrigido no back 03/10 (com teste) | `purchase-proposals.controller.ts:549` antes de `:621` | s (correção no back) | P | P2 |
| P5 | Autentique inativa não trava o envio | ✅ Feito 03/10 | Web: `ProposalSignaturesModalPrivate.tsx:144,488-492` | s | P | P2 |
| P6 | Sem nova tentativa em 409 `DUPLICATE_ENTRY` na criação | ✅ Feito 03/10 | Web: `purchaseProposalsApi.ts:269-288`. App: `purchase_proposals_service.dart:1014-1035` | n | P | P2 |
| P7 | Mensagem de etapa liberada após aprovar anexo (o app anuncia a etapa atual; o web, a próxima) | ✅ Feito 03/10 | App: `proposal_signatures_sheet.dart:607-609`. Web: `PropostaAnexosModalPrivate.tsx:479-486` | n | P | P2 |
| P8 | Sem opção de baixar PDF com o assinado (ZIP) | ✅ Feito 03/10 | App: `purchase_proposals_service.dart:1264-1272` (sempre `incluirAutentique=false`). Web: `purchaseProposalsApi.ts:549-605` | s | P | P2 |
| P9 | Deep link `?highlightProposal=` abre só a lista | ✅ Feito 03/10 | Web: `notificationNavigation.ts:269-271`. App: `shared/utils/app_deep_link.dart:302-304` | n | P | P2 |
| P10 | Rótulos de status da assinatura ("Aguardando assinatura" × "Pendente"; `approved` aparece cru) | ✅ Feito 03/10 | App: `purchase_proposals_service.dart:535-551`. Web: `ProposalSignaturesModalPrivate.tsx:474-483` | n | P | P2 |

**Confirmado sem diferença na proposta:**
- payload `buyer*`/`propertyData`/`financialData`/`observations`;
- abas e etapas 1-2-3;
- validações (`features/proposals/utils/proposal_form_rules.dart`);
- vínculo com a ficha de venda (`features/sale_forms/services/sale_form_proposal_link_service.dart:98`);
- `POST :id/usuarios`, filtros, contadores e lista de excluídas;
- histórico, sync, link e reenvio por e-mail;
- a proposta não tem mídia de origem nem no web nem no app.

**Confirmado sem diferença na venda:**
- validação por aba (`sale_form_rules.dart:214-387` × `CreateSaleFormPage.tsx:1688-1957`);
- filtros, ordenações e `/stats`;
- tipos e limite de anexos;
- corpo de envio de assinaturas e filtro de signatários obrigatórios;
- reenvio, sync, link, invalidar e a tela de assinaturas pendentes;
- menu de ações (`sale_form_row_rules.dart`).

**Telas de configuração que só existem no web:**
- `/fichas-venda/unidades`;
- `/fichas-venda/signatarios-obrigatorios`;
- `/fichas-venda/modelos-documentos`;
- `/fichas/dashboard` (consolidado).

**Não se aplica** ao app: são telas administrativas de configuração da empresa (unidades, signatários obrigatórios, modelos de documento) e o painel consolidado; o app consome o resultado delas pelo back (unidades no select, signatários obrigatórios no envio, modelo no PDF) e já tem o painel de fichas de venda (`sale_forms_dashboard_page.dart`).

### Ordem de execução sugerida (executada inteira em 03/10 — ver "Execução" no topo)

1. **V1 + P1: `contentType` no upload de anexo (P0, esforço P, só no app).** Definir o tipo pela extensão (`pdf`, `jpg`/`jpeg`, `png`, `webp`) com `MediaType` nos dois services. Seguir o padrão que `client_service.dart` e `chat_api_service.dart` já usam.
2. **Item 6: DISPAROS MANYCHAT (P1, P).** Trocar o valor na lista. Na edição, aceitar o valor gravado mesmo fora da lista, como o `MIDIAS_ORIGEM_FICHA_VENDA_COMPLETA` do web: incluir o legado e manter o valor atual como opção.
3. **V3: `useInSaleForms=true` no `listTeams` do modal de tipo (P1, P).**
4. **V2: busca de imóvel por código e `propertyId` no payload, com `null` ao trocar o código (P1, M).**
5. **V7 + V8: trava de assinatura reavaliada a cada rota (ou ao voltar do detalhe), e modal de assinaturas aberto depois de criar a ficha (P1, P).**
6. **V4 + V5: detalhe completo (somente leitura) e aba ou sheet de auditoria (P1, M).**
7. **V6: exportação XLSX da lista (P1, M).**
8. **V9 + P2: rascunho local na venda e na proposta (P1/P2, M).**
9. **P2 restantes, em lote:** V10–V15, P3, P5–P10. P4 vai para o back.

**Fora do escopo das fichas:** Nova Venda por ficha, Conversa da venda e as notificações do financeiro (itens 8, 9a e 9b). Entram quando o app tiver o módulo Financeiro (ver `fin-20` na auditoria de 29/09).

---

## Paridade web × app — re-verificação 03/10/2026

Escopo: Fichas de Locação/Análise de crédito · Clientes/Proprietários/Documentos · Agenda/Visitas/Check-in/Vistorias.
Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md` (linhas 25–375). Código conferido: app `dreamkeysapp/lib` (HEAD 675b686), web `intellisys-CRM/src`, back `intellisys-CRM-Back/src`.
Legenda: **Deploy** = depende de deploy do back (s/n). **Esforço** P/M/G.

### Resumo

| Domínio | Itens | Feito | Parcial | Falta | Falta por severidade |
|---|---|---|---|---|---|
| Fichas de Locação + Análise de crédito | 27 | 0 | 0 | 27 | P0: 6 (todos "FORA" por decisão do Edson 29/09) · P1: 12 · P2: 9 |
| Clientes, Proprietários, Documentos | 34 | 17 | 3 | 14 | P0: 0 · P1: 1 (+2 parciais) · P2: 13 (+1 parcial) |
| Agenda, Visitas, Check-in, Vistorias | 23 | 2 | 0 | 21 | P0: 0 · P1: 3 · P2: 18 |
| **Total** | **84** | **19** | **3** | **62** | P0: 6 · P1: 16 (+2 parc.) · P2: 40 (+1 parc.) |

**O que quebra o app:** nada novo. Desde 29/09 o back só mexeu nestes domínios em `autentique-webhook/sync` (ficha não "ressuscita" por link antigo — sem mudança de contrato), `visit-report-pdf.service.ts` (`pipe: true` no Puppeteer) e permissões (nova rota `GET /permissions/user/:id/history` + `PLATFORM_PERMISSION_PREFIXES` para planos só-Financeiro; nenhuma permissão foi removida ou renomeada). O web mantém os mesmos 7 status de ficha (`rentalApplicationFormsApi.ts:18-25`). Continuam como falhas em runtime, já existentes antes:
- ✅ **agenda-01** (resolvido em 03/10): o tipo `signature` era oferecido no criar, editar e filtro, e o back responde **400** (o enum do back não tem `signature`, `appointment.entity.ts:17-26`).
- **fichaloc-07**: `submitted`/`pre_approved`/`rejected` aparecem como "Pendente" (`rental_form_model.dart:33,87-89`). Não trava, mas mostra o status errado.
- **clientes-24**: o filtro UF fica marcado como ativo e não filtra nada (o back ignora `state`).
- 403 previsíveis em ações sem gate: agenda-03/04, checkin-04/05, vistorias-01.

Commits do app desde 29/09 em escopo: `dea66d3` e `ecd6989` (clientes, documentos, visitas). Locação, agenda, check-in e vistorias **não foram tocados**.

---

### Fichas de Locação e Análise de crédito

Nenhum arquivo de `features/rental_forms` ou `features/credit_analysis` mudou desde 29/09.

| ID | Sev | Situação | Evidência (app / web-back) | Deploy | Esforço |
|---|---|---|---|---|---|
| fichaloc-01 garantia | P0 (FORA) | Falta | sem `garantia`/`opcoes-garantia` em `rental_forms/` / web `RentalLocacaoFormBody.tsx` | n | M |
| fichaloc-03 aba Imóvel/lastro | P0 (FORA) | Falta | sem `lastro`/`vincular` no service / `rentalApplicationFormsApi.ts` | n | G |
| fichaloc-05 relação de documentos | P0 (FORA) | Falta | `rental_form_sections.dart` lista genérica inalterada | n | P |
| fichaloc-06 Assinar (Autentique) | P0 (FORA) | Falta | `rental_share_link_sheet.dart:15` só abre WhatsApp; não há "Assinar" | n | P |
| fichaloc-07 status 7→4 | P0 (FORA) | Falta | `rental_form_model.dart:33` enum com 4 valores; `:87-89` default pending / web `:18-25` com 7 | n | P |
| fichaloc-25 proprietário sempre validado | P0 (FORA) | Falta | `rental_form_editor_page.dart` `_validateForFinish` inalterado | n | P |
| fichaloc-02 estrutura de abas | P1 | Falta | `rental_form_sections.dart` mantém o passo Fiador fixo | n | M |
| fichaloc-04 anexos por documento | P1 | Falta | `rental_form_sections.dart:475` "…pelo painel web" | n | M |
| fichaloc-08 gate rental:view | P1 | Falta | `app_drawer.dart:1137` `rental_form:view` / web `Drawer.tsx:954-956` `rental:view` | n | P |
| fichaloc-09 validação de formato | P1 | Falta | `_validateForFinish` só checa vazio | n | M |
| fichaloc-11 Ver/baixar PDF | P1 | Falta | sem `/pdf` no service | n | P |
| fichaloc-12 Solicitar aprovação | P1 | Falta | sem `rental-form-approvals` no app | n | M |
| fichaloc-13 tela Aprovação de fichas | P1 | Falta | sem rota; web `Drawer.tsx:967-973` | n | M |
| fichaloc-14 Análise de crédito FC | P1 | Falta | app só usa `/credit-analysis` (`credit_analysis_service.dart:16-19`); web `Drawer.tsx:959-965` | n | G |
| fichaloc-15 Cliente cadastrado | P1 | Falta | sem `apply-to-ficha` no app | n | M |
| fichaloc-16 Gerar contrato / Criar ou Abrir locação | P1 | Falta | modelo sem `rentalId` | n | M |
| fichaloc-17 picker usa /admin/users | P1 | Falta | `rental_form_editor_page.dart:1989` `AdminUsersService.listUsers` | n | P |
| fichaloc-18 conferência (gate-report etc.) | P1 | Falta | sem `gate-report`/`area-cliente` | n | G |
| fichaloc-10 tarifa/assinatura default | P2 | Falta | `rental_form_sections.dart:292-293` sem default | n | P |
| fichaloc-19 campos condicionais | P2 | Falta | sem FIELD_VISIBILITY | n | P |
| fichaloc-20 CEP automático | P2 | Falta | sem `CepService` em rental_forms | n | P |
| fichaloc-21 formNumber/cabeçalho | P2 | Falta | sem `formNumber` no modelo | n | P |
| fichaloc-22 menu link do cliente | P2 | Falta | `rental_form_card.dart` `_MoreMenu` inalterado | n | P |
| fichaloc-23 ordem das seções | P2 | Falta | inalterado | n | P |
| fichaloc-24 régua só leitura | P2 | Falta | `credit_analysis_settings_page.dart:258` "Somente leitura…" | n | P |
| fichaloc-26 empresaCep | P2 | Falta | sem `empresaCep` | n | P |
| fichaloc-27 contagens/filtro/busca | P2 | Falta | `rental_forms_page.dart` paginação de 20 inalterada | n | P |

### Clientes, Proprietários e Documentos do cliente

| ID | Sev | Situação | Evidência (app / web-back) | Deploy | Esforço |
|---|---|---|---|---|---|
| clientes-01 obrigatórios | P0 | Feito | `client_form_page.dart:1373,1394` (só nome e telefone); CEP/UF validam só formato `:1682-1699` | n | — |
| clientes-02 captador | P0 | Feito | `client_form_page.dart:312-315,478-504` preserva; seletor `:1580-1588` | n | — |
| clientes-03 cônjuge | P1 | Feito | `client_service.dart:800-871` (/spouses); `client_form_page.dart:2470-2565` | n | — |
| clientes-04 datas prof./crédito/características | P1 | Feito | `client_form_page.dart:1879-1909,2039,2244-2296` | n | — |
| clientes-05 renda→situação→cargo, telefone dup. | P1 | Feito | `client_form_page.dart:430,469,1856-1863`; nome ≥3 `:1375` | n | — |
| clientes-08 exportar | P1 | Feito | `clients_page.dart:2268-2354` (xlsx + share) | n | — |
| clientes-09 planilha de erros + modelo | P1 | Feito | `async_excel_import_modal.dart:1008-1058` | n | — |
| clientes-10 permissões | P1 | Feito | `clients_page.dart:42-46,316-331`; `client_details_page.dart:107,291`; `client_form_page.dart:172-173` (gate dentro da página, não na rota) | n | — |
| clientes-11 atendimento: anexos/editar | P1 | **Parcial** | service multipart pronto (`client_service.dart:612-691`), mas o painel só chama create sem arquivos (`client_interactions_panel.dart:648-655`); não há Editar nem limite de 150 | n | P |
| clientes-18 dinheiro na edição | P1 | Feito | `client_form_page.dart:378-383` `_moneyText` usa CurrencyInputFormatter | n | — |
| clientes-20 Clientes da Locação (/v1/locacao/people) | P1 | Falta | nada em `lib/`; web `Drawer.tsx:1019-1025` | n | G |
| clientes-23 busca com debounce | P1 | Feito | `clients_page.dart:264-288` (400 ms; 0 ou 3+). Ainda não descarta respostas fora de ordem (falta o contador) | n | — |
| documentos-01 menu Documentos | P1 | Feito | `app_drawer.dart:1085-1090,1698-1749` | n | — |
| documentos-02 enviar p/ assinatura | P1 | Feito | `send_document_for_signature_page.dart` (gate `:417`) | n | — |
| documentos-03 baixar no detalhe | P1 | Feito | `document_details_page.dart:173-182,676-687` | n | — |
| documentos-04 aprovar/recusar/excluir | P1 | Feito | `documents_page.dart:212-318,928-1003`; detalhe `:258,283` | n | — |
| documentos-05 permissões/módulo | P1 | Feito | `document_permissions.dart`; `documents_page.dart:763-771` | n | — |
| documentos-06 assinaturas: entrada e ações | P1 | Feito | `documents_page.dart:799`; `signatures_page.dart:184-185,627,920` | n | — |
| documentos-07 Pastas CRM | P1 | **Parcial** | `document_folder_service.dart` e `task_document_folder_panel.dart` existem, mas **nada importa o painel**; não há tela/rota Pastas CRM nem item no drawer (web `Drawer.tsx:1196-1203`) | n | M |
| clientes-06 CEP→endereço | P2 | Falta | sem `CepService` em `features/clients` | n | P |
| clientes-07 accountType/contractType | P2 | Falta | `client_form_page.dart:2072-2076` (checking/savings/salary); contractType texto livre `:1873-1875` | n | P |
| clientes-12 checklists no detalhe | P2 | Falta | nada em `client_details_page.dart` | n | P |
| clientes-13 detalhe com mais dados | P2 | Falta | `client_details_page.dart:927-1018` sem admissão, tipo de conta ou salários; cônjuge sem RG/nascimento `:1020+` | n | P |
| clientes-14 card (origem, cônjuge, financeiro, Desde) | P2 | Falta | `clients_page.dart:1195-1224` (mostra contato, responsável, captador e "atualizado") | n | P |
| clientes-15 KPIs com filtro | P2 | Feito | `clients_page.dart:254,611-654` (`getStatistics(filters)`) | n | — |
| clientes-16 filtro Responsável / Inativos | P2 | Falta | `client_filters_drawer.dart:364-368` só "Apenas ativos"; sem responsável | n | P |
| clientes-17 ficha completa a partir do card | P2 | Falta | `app_routes.dart:524-525` `const ClientFormPage()` sem argumentos | n | P |
| clientes-19 cidade preferida IBGE | P2 | Falta | `client_form_page.dart:2113-2116` texto livre | n | M |
| documentos-08 tags e pré-vínculo | P2 | **Parcial** | `create_document_page.dart:17,56-58` aceita `initialPropertyId`; sem campo Tags, sem `clientId` inicial; drawer de filtros sem tags | n | P |
| clientes-21 IA do cliente | P2 | Falta | sem followup/classify em `lib/` | n | M |
| clientes-22 matches | P2 | Falta (aguarda decisão do Edson) | `feature_visibility.dart:17` `matchesEnabled => false` | n | P |
| proprietarios-01 visibilidade do proprietário | P2 | Falta | sem `protected-owner-data`; web `Drawer.tsx:2035-2043` | n | M |
| clientes-24 filtro UF inócuo | P2 | Falta | `client_filters_drawer.dart:109,276-285` envia `state`; o back ainda não filtra (`clients.service.ts` sem `filters.state`) | s, se a opção for suportar no back | P |
| clientes-25 anexo do atendimento não abre | P2 | Falta | `client_interactions_panel.dart:418-459` Container sem onTap | n | P |

### Agenda, Visitas, Check-in, Vistorias

| ID | Sev | Situação | Evidência (app / web-back) | Deploy | Esforço |
|---|---|---|---|---|---|
| visitas-01 menu Visitas | P0 | Feito | `app_drawer.dart:1071-1078,1266,1289`; `visit_report_access.dart:40-50` | n | — |
| agenda-01 tipo "Assinatura" (**400 no back**) ✅ | P1 | **Feito (03/10)**: `AppointmentType.selectable` (sem `signature`) no criar, editar e filtro; legado `signature` vira "Outro" ao editar | `appointment_model.dart:195`; ofertado em `create_appointment_page.dart:787`, `edit_appointment_page.dart:867`, `appointment_filters_sheet.dart:301` / back `appointment.entity.ts:17-26` | n | P |
| agenda-03 editar/excluir/status sem gate ✅ | P1 | **Feito (03/10)**: detalhe exige criador + `calendar:update`/`calendar:delete` (mesma regra do web e do back); botões desabilitados e fluxo de status oculto sem direito | nenhum `hasPermission`/criador em `features/appointments`; `app_permissions.dart` sem calendar:* | n | P |
| checkin-01 tela de configurações | P1 | Falta | `check_in_service.dart:991-995` só GET; web `Drawer.tsx:749-755` | n | G |
| agenda-02 título 3–200 | P2 | Falta | sem minLength/maxLength nas páginas | n | P |
| agenda-04 calendar:create ✅ | P2 | **Feito (03/10)**: `calendar_page.dart` esconde os atalhos de criar e bloqueia `_openCreate` sem `calendar:create` | sem gate em `calendar_page.dart` | n | P |
| agenda-05 início no passado | P2 | Falta | `create_appointment_page.dart:221` `firstDate: now-1d` | n | P |
| agenda-06 tipo pré-selecionado | P2 | Falta | `create_appointment_page.dart:104` `_type = visit` | n | P |
| agenda-07 "Criado por" e copiar endereço | P2 | Falta | sem bloco do criador nem Clipboard em `appointment_details_page.dart` | n | P |
| agenda-08 busca por texto | P2 | Falta | `calendar_page.dart:1031` só "Buscar pessoa…" | n | P |
| agenda-09 permitir sobreposição | P2 | Feito (em outro lugar) | `settings_page.dart:668,1103-1111` grava `calendarAllowOverlappingSlots` (não está na ScheduleSettingsPage) | n | — |
| agenda-10 snooze 15 min | P2 | Falta | `api_constants.dart:264` sem uso | n | M |
| checkin-02 exportar Excel | P2 | Falta | `check_in_list_page.dart` sem exportação | n | M |
| checkin-03 gate do módulo visit_report | P2 | Falta | `app_drawer.dart:1051-1060` sem `hasCompanyModule('visit_report')` | n | P |
| checkin-04 Histórico sem check_in:view | P2 | ✅ Feito (03/10) | ícone e link do histórico só com `check_in:view` (ou admin/master); `check_in/utils/check_in_access.dart` | n | P |
| checkin-05 manager libera gestão | P2 | ✅ Feito (03/10) | gestão só admin/master ou `check_in:manage_settings`, sem bypass de `manager` (igual `PermissionsGuard` do back e `CheckInPage.tsx`) | n | P |
| vistorias-01 permissões | P2 | ✅ Feito (03/10) | lista: "Nova vistoria" só com `inspection:create`; detalhe: editar/status/fotos/histórico com `inspection:update`, excluir com `inspection:delete`, pedir aprovação financeira com `inspection:create` (POST /inspection-approval); criar/editar bloqueiam sem a permissão | n | P |
| vistorias-02 checklist no detalhe | P2 | Falta | sem `checklist` nas páginas | n | P |
| vistorias-03 remover entrada do histórico | P2 | Falta | `removeHistoryEntry` sem chamada nas páginas | n | P |
| vistorias-04 vistoriador por papel | P2 | Falta | sem filtro por role em create/edit | n | P |
| vistorias-05 máscara de documento/telefone | P2 | Falta | `create_inspection_page.dart:306-309`, `edit_inspection_page.dart:385-388` usam unmask | n | P |
| vistorias-06 Vistorias no menu | P2 | Falta | `app_drawer.dart:28` ainda diz hidden; web `Drawer.tsx:1075-1081` visível (Locação) | n | P |
| vistorias-07 tipo pré-selecionado | P2 | Falta | `create_inspection_page.dart:38` `_selectedType = entry` | n | P |

### Observações

- Nenhum item depende de deploy do back. Os endpoints que o app precisa (`/v1/locacao/*`, `/v1/rental-form-approvals`, `/check-in/settings` PUT, `/appointments/:id/snooze`, `/protected-owner-data`) já existem no back. A única exceção é clientes-24, e só se a opção escolhida for o back passar a suportar `state`.
- Os 6 P0 que faltam são todos de Fichas de Locação, marcados "FORA" pelo Edson em 29/09. Se a locação voltar ao escopo, comece por fichaloc-07 e fichaloc-06 (P, sem dependência).
- Ganhos rápidos (P, sem deploy) que eliminam erro 400/403 em produção: agenda-01, agenda-03, agenda-04, checkin-04, checkin-05, vistorias-01.

---

## Paridade web × app (re-verificação 03/10/2026): WhatsApp, Chat interno, Notificações e CRM/Kanban

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

### Resumo por domínio

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

### O que QUEBRA o app

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

### WhatsApp

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

### Chat interno

| ID | Prio | Situação | Evidência app | Evidência web/back | Deploy back? | Esforço |
|---|---|---|---|---|---|---|
| chat-01 Lista `{rooms, archivedRooms}` | P0 | feito (dea66d3) | `chat_api_service.dart:111-158` (objeto, lista e 304); `chat_page.dart:81-84, 440-444`; `chat_unread_controller.dart:107-136` | back `chat.controller.ts:81` | n | – |
| chat-02 Editar e criar grupo | P1 | ainda falta | `edit_group_chat_page.dart:14-29` ainda é placeholder; não há "Novo grupo". Os métodos do service já existem (`chat_api_service.dart:238-492`) | back `chat.controller.ts:373, 395, 466, 485, 509, 539` | n | G |
| chat-03 Silenciar, arquivar e apagar para mim/todos | P1 | parcial: ✅ apagar para mim/todos feito em 03/10 (QUEBRA 1 resolvida); faltam silenciar e arquivar na UI | `chat_page.dart:792-806, 1465, 1522` mostram o estado; menu só `delete` → `leaveRoom` (`:274-277, 1555-1579`). Não há mute nem delete-for-* no service. `archiveRoom`/`unarchiveRoom` existem (`:539, 571`), mas sem UI | back `chat.controller.ts:325, 337, 349, 361, 436, 451` | n | P |
| chat-04 Responder, reagir, editar, apagar e recibos | P1 | ainda falta | `chat_models.dart:343-366` sem `replyToMessage`/`reactions`. `editMessage`/`deleteMessage` existem no service (`:934, 984`), mas sem UI | back `chat.controller.ts:294, 592, 615, 640, 658` | n | G |
| chat-05 Socket: digitação, presença, reações, remoção | P2 | ainda falta | `chat_socket_service.dart:172-363` não trata typing, presence, reaction, deleted_for_me nem removed | back `chat.gateway.ts:828, 743/767, 1101, 1133, 1338, 1423` | n | M |

### Notificações

| ID | Prio | Situação | Evidência app | Evidência web/back | Deploy back? | Esforço |
|---|---|---|---|---|---|---|
| notif-01 Abas e contagem por origem no sino | P2 | ainda falta | `notification_center.dart:365` (`markAllAsRead` sem category); `notifications_page.dart:91-97` só tem chip filtrado no cliente | back `notification.controller.ts:107, 311` | n | M |
| notif-02 Alertas do financeiro | P1 | ainda falta | Não há cliente de `/notifications` do financeiro; `notification_list.dart:96`. A base URL do financeiro em `settings_service.dart:33-41` pode ser reaproveitada | web `financeNotificationsApi.ts:195-231` (microserviço financeiro) | n | M |
| notif-03 `category` no servidor | P2 | ainda falta | `notification_controller.dart:44-66, 295-296, 356-360` (até 5 páginas); `notification_model.dart:250-283` sem category | back `notification-query.dto.ts`; `notification.controller.ts:55, 107` | n | P |
| notif-04 Preferências de notificação | P1 | feito (dea66d3) | `settings_service.dart:29-30, 327-453, 469-551`; `notification_preferences_page.dart`; `settings_page.dart:287`. Sobra `ApiConstants.settings` sem uso (`api_constants.dart:235`) | back `user-preferences.controller.ts:37, 53, 59` | n | – |
| notif-06 Sino lista todas as empresas | P2 | ainda falta | `notification_service.dart:22-34, 95-100` (`/all-companies`); `controller:491-501` | back `notification.controller.ts:55` vs `:82` | n | P |

### CRM / Kanban

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

---

## Re-verificação de paridade web × app (03/10/2026): Financeiro, Usuários e Dashboards

Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, linhas 848–1240. Conferido no código atual de `dreamkeysapp/lib` (inclui os commits de 29/09 a 03/10, como o `de39749`, painel executivo), do `intellisys-CRM/src` (web), do `intellisys-CRM-Back/src` e do `intellisys-financeiro/apps/api`. Os caminhos `imobx-front`/`imobx` da auditoria correspondem a `intellisys-CRM`/`intellisys-CRM-Back`.

**Legenda**
- **Situação:** feito / parcial / falta / n/a (não se aplica mais).
- **Deploy:** "s" quando a correção ou o comportamento depende de deploy do back.
- **Esforço:** P / M / G.

### Resumo por domínio

| Domínio | Itens | Feito | Parcial | Falta | n/a | P0 que ainda faltam |
|---|---|---|---|---|---|---|
| Meu Financeiro / Comissões | 26 | 1 | 1 | 24 | 0 | fin-01 (parcial), fin-02, fin-03, fin-04, fin-05 |
| Usuários / Equipes / Empresa / Perfil / Config. | 35 | 13 | 7 | 15 | 0 | nenhum |
| Dashboards / SDR / Leads / Campanhas | 32 | 7 | 3 | 20 | 2 | nenhum |
| **Novos, cobrança e acesso (fora da auditoria)** | 2 | 2 ✅ | 0 | 0 | 0 | nenhum (NEW-01 e NEW-02 feitos em 03/10) |
| **Total** | **95** | **21** | **11** | **61** | **2** | **7** |

- **Financeiro:** fora as preferências de avisos (fin-25), nada mudou. O app ainda não tem um cliente real do microserviço: não há PIN, nem softAuth, nem tratamento de 428. A única base URL do financeiro está dentro de `settings_service.dart`.
  - Na auditoria, fin-01 a fin-05 estão marcados "FORA" (Edson, 29/09).
  - Desde 02/10 o Financeiro é a prioridade. **É preciso reclassificar esses itens como P0 ativos.**
  - Todos os endpoints existem no código do back financeiro. O app já aponta para `api.financeiro.intellisysbr.com`, mas não confirmei daqui que essa URL está no ar.
  - Nada desta seção quebra o app hoje. Notificações e links `/financeiro/*` só mostram o toast "sem tela".
- **Usuários:**
  - Os P0 estão resolvidos de verdade: usr-01 (criar usuário) e eq-01 (criar equipe).
  - O login com 2FA obrigatório também (auth-2fa-setup).
  - Preferências (`/user-preferences`), notificações por categoria, edição de empresa e os toggles de 2FA e "app para todos" estão feitos.
  - Faltam as telas órfãs (Unidades, Hierarquia, Backups, Assinaturas, Master), excluir usuário, reset de 2FA e os gates de telefone e CPF.
  - **Risco novo:** com o plano "só Financeiro", salvar usuário pode falhar (usr-04).
- **Dashboards:**
  - Os 4 P0 estão feitos: dash-01 (visão executiva), sdr-01 (Dash SDR no menu), sdr-02 (`lists=none`) e leads-01 (Roleta).
  - Filtros, drill-down e recorte por equipe do SDR também estão feitos.
  - sdr-04 (abas) e sdr-06 (CAC) não se aplicam mais: o web passou a mostrar só a aba Funil.
  - Faltam o dashboard do gestor, Leads perdidos, campanhas (Meta e Sistema), "Meus ganhos" e GA4.

### O que quebra o app ou o login

1. ✅ **(resolvido em 03/10 — ver tabela "Novos")** **NEW-01 (P0, login e cobrança):** conta **gerenciada** com o trial ou a graça vencidos, ou assinatura suspensa ou expirada.
   - **Titular admin/owner:** o `login_flow_service.dart:269-280` devolve um `redirect`, tratado como sucesso, para **/settings (Preferências)**. A mensagem ("configure no painel web") não aparece, porque o toast só sai no erro (`login_page.dart:172-251`). Também não há telas de assinatura alcançáveis (as 4 estão órfãs, ver sub-01). No web, o titular gerenciado vê o `SubscriptionRequiredModal` dentro do sistema, com acesso mínimo para assinar, abrir chamado e editar o perfil (`SubscriptionGuardNew.tsx:291-345`).
   - **Colaborador:** o app não checa nada. No web ele vai para `/system-unavailable` (`SubscriptionGuardNew.tsx:405-406`).
   - **O que bloqueia de fato no back:** o `SubscriptionGuard` global roda antes do `JwtAuthGuard` e, sem `req.user`, deixa passar. Só bloqueiam os controllers que o aplicam explicitamente: **dashboard** (`dashboard.controller.ts:58`), **properties** (`properties.controller.ts:184-191`) e **goals**.
   - **Efeito no app:** Home e Imóveis em 403 "assinatura suspensa", com erro genérico. O resto do app funciona.
   - **O app também ignora** `billingRegime`, `managed_exempt` e `isExpiringSoon`. Não há aviso de "seu trial termina em N dias".
   - Não depende de deploy: o back está assim desde 07/2026. Esforço M.
2. ✅ **(resolvido no app em 03/10 — ver tabela "Novos")** **NEW-02 (P0 condicional, depende de deploy):** empresa no **plano "só Financeiro"**. Vem dos commits `4d56e505` e `848dac00` do back, de 02/10, já no `origin/master`. Não confirmei o deploy.
   - O `CrmProductAccessInterceptor` responde 403 a todas as rotas de CRM (`dashboard`, `kanban`, `properties`, `whatsapp`…) (`crm-product-access.interceptor.ts:36-110`).
   - **Efeito na Home:** o app não desloga, mas a Home fica travada em "Sem permissão" (`dashboard_page.dart:865-876`; `company_overview_view.dart:178-180`). Agenda e subtarefas dão 403 em segundo plano.
   - **Sem saída pelo app:** ele não tem o Financeiro, então esse usuário não tem nada útil para fazer nele.
   - **Usuários:** salvar um usuário com permissão de CRM sem módulo mapeado falha sempre (ver usr-04).
   - O plano nasce inativo, então o risco se limita às empresas que o master migrar. Esforço M: detectar "empresa sem CRM" e mostrar uma Home ou estado próprio.
3. **usr-04 (parcial):** o editor de permissões não aplica `permissaoCabeNoSoFinanceiro`. Numa empresa só-Financeiro, o PUT ou POST de usuário falha (`permission_rules.dart:231`; back `permissions.service.ts:1018-1021`).
4. **Riscos menores:**
   - Equipe exige uma unidade ativa, e a tela de Unidades está órfã (org-01). Empresa sem unidade não cria equipe pelo app.
   - usr-13 deixa abrir a tela de Usuários e tomar 403.
   - Sem reset de 2FA (usr-10), quem troca de celular depende do web.

---

### Meu Financeiro, Comissões e Recebimentos do corretor

| ID | P | Lacuna | Situação | Evidência | Deploy | Esforço |
|---|---|---|---|---|---|---|
| fin-01 | P0 (FORA→reativar) | Cliente HTTP do financeiro (PIN, softAuth, troca de empresa) | parcial | `settings_service.dart:38-41` (`_kFinanceBaseUrl`, só para preferências); nenhum `finance_api_service`/`X-Finance-Pin`/428 em lib | n | M |
| fin-02 | P0 (FORA→reativar) | Tela Meu Financeiro | falta | nenhuma ref. a `broker-dashboard`; back `broker-earnings.controller.ts:69` | n | G |
| fin-03 | P0 (FORA→reativar) | PIN do Financeiro | falta | nenhuma ref. a `/auth/pin`/`X-Finance-Pin` | n | M |
| fin-04 | P0 (FORA→reativar) | Pedir adiantamento | falta | nenhuma ref. a `commission-advances` | n | M |
| fin-05 | P0 (FORA→reativar) | Solicitações (lista e nova) | falta | nenhuma ref. a `request-tipos`/`/requests` | n | G |
| fin-06 | P1 | Detalhe da solicitação | falta | ausente | n | M |
| fin-07 | P1 | Lista do KPI (próximos) | falta | nenhuma ref. a `broker-dashboard/proximos` | n | M |
| fin-08 | P1 | Minhas vendas | falta | nenhuma ref. a `broker-dashboard/vendas` | n | M |
| fin-09 | P1 | Fichas aguardando assinatura | falta | nenhuma ref. a `broker-dashboard/assinaturas` | n | M |
| fin-10 | P1 | Consulta da venda e origem do repasse | falta | nenhuma ref. a `/repasses/` | n | M |
| fin-12 | P1 | Histórico e saldo de adiantamentos | falta | ausente | n | M |
| fin-13 | P1 | "Meu dinheiro" no dashboard | falta | `dashboard_page.dart:1281` (só o comentário); nenhuma ref. a `repasses/earnings` | n | M |
| fin-14 | P1 | Notificações do financeiro no sino | falta | nenhum prefixo `fin:`; `notification_counts_service.dart:24` só do core | n | M |
| fin-16 | P1 | Seletor CRM \| Financeiro | falta | `app_drawer.dart` sem grupo Financeiro | n | M |
| fin-19 | P1 | Central de Aprovações | falta | nenhuma ref. a `/approvals` | n | G |
| fin-11 | P2 | Drill por corretor | falta | depende de fin-02 | n | P |
| fin-15 | P2 | Deep link `/financeiro/*` | falta | `app_deep_link.dart:439-442` (default null); `notification_list.dart:96` | n | P |
| fin-17 | P2 | Gating `financial:access` + matriz `/auth/me` | falta | `module_access_service.dart:406-409,474` ainda `financial:view…` | n | M |
| fin-20 | P2 | Conversa da venda | falta | ausente | n | M |
| fin-21 | P2 | Bloco "Minhas solicitações" | falta | depende de fin-02/05 | n | P |
| fin-22 | P2 | Gráfico mensal | falta | depende de fin-02 | n | M |
| fin-23 | P2 | Auto-refresh e ocultar valores | falta | depende de fin-02 | n | P |
| fin-24 | P2 | Vendas, Confissão e Tabela de comissões | falta | ausente | n | G |
| fin-25 | P2 | Preferências de avisos do financeiro | **feito** | `settings_service.dart:469-533`; `notification_preferences_page.dart:100-146,1098-1206` | n | – |
| fin-27 | P2 | Banner da trava de comprovante (48h) | falta | nenhuma ref. a `receipt-lock` | n | P |
| fin-28 | P2 | Rascunho e 409 na solicitação | falta | depende de fin-05 | n | P |

Obs.: `/commissions` continua como código morto e não quebra nada (`app_routes.dart:280,700-701`; oculto em `app_drawer.dart:1809`). É o mesmo cenário da fin-18, refutada na auditoria.

### Usuários, Equipes, Permissões, Empresa, Perfil e Configurações

| ID | P | Lacuna | Situação | Evidência | Deploy | Esforço |
|---|---|---|---|---|---|---|
| usr-01 | P0 | Criar Corretor/Gestor falha | **feito** | `create_user_page.dart:220-235,281-287` | n | – |
| eq-01 | P0 | Criar equipe sem `unitId` | **feito** | `team_form_page.dart:450-460,487,496`; `company_team_service.dart:113-116,154` | n | – |
| cfg-01 | P1 | Preferências em `/settings` inexistente | feito | `settings_service.dart:29-30,346` (`/user-preferences`) | n | – |
| cfg-02 | P1 | Notificação por categoria | feito | `notification_preferences_page.dart:15-17,151`; `settings_page.dart:284` | n | – |
| org-01 | P1 | Unidades órfã | falta | `organization_units_page.dart:21` sem rota nem drawer | n | P |
| emp-01 | P1 | Editar empresa | feito | `edit_company_page.dart:297,400,450,486`; `profile_page.dart:267` | n | – |
| emp-02 | P1 | Toggles de 2FA obrigatório e app para todos | feito | `profile_page.dart:210,239`; `company_admin_service.dart:298,311` | n | – |
| usr-02 | P1 | Editar dados do usuário | parcial | `edit_user_page.dart:370-379` envia nome, e-mail, senha, tags e cargo; o site público não tem switch (:377) | n | P |
| usr-03 | P1 | Zerar ou remover as obrigatórias | feito | `permission_rules.dart:476-479,556` | n | – |
| usr-04 | P1 | Plano, alçada, proprietário e ocultas | parcial | módulo :229-233, alçada :237, ocultas :134, owner :373. Falta a regra do plano só-Financeiro (`permission_rules.dart:231`) | **s** | P |
| usr-06 | P1 | Ativar/desativar por `isActiveInCompany` | feito | `users_page.dart:268,294,310,1483` | n | – |
| usr-07 | P1 | Prévia do funil e redistribuição | feito | `users_page.dart:2026,2056,2074`; `admin_users_service.dart:537` | n | – |
| prf-01 | P1 | Limpar tags e telefone | feito | `edit_profile_page.dart:167-173` | n | – |
| prf-03 | P1 | Tags do perfil não salvavam | feito | `edit_profile_page.dart:184`; `tag_service.dart:121,149` | n | – |
| auth-2fa-setup | P1 | Configurar 2FA no login | feito | `login_flow_service.dart:79,125,158`; `login_page.dart:157-167`; `two_factor_setup_page.dart:75,127-178` | n | – |
| org-02 | P2 | Hierarquia órfã | falta | `organization_hierarchy_page.dart:19` sem referência | n | P |
| org-03 | P2 | Backups órfã | falta | `organization_backups_page.dart:36` sem referência | n | P |
| sub-01 | P2 | Assinaturas órfãs (**relevante para NEW-01**) | parcial (03/10): rotas `/subscription`, `/subscription/plans`, `/subscription/manage[/:id]` registradas e alcançáveis pela tela de bloqueio; falta item no drawer/perfil | 4 páginas em `features/subscriptions` sem rota; `app_drawer.dart:1740` é Assinaturas de documentos | n | P |
| emp-03 | P2 | Criar e excluir empresa | falta | `company_admin_service.dart:139-323` sem POST/DELETE | n | M |
| usr-05 | P2 | Papel Proprietário e rótulos | parcial | edição OK (`edit_user_page.dart:323-325,430`); na criação, Gestor ainda travado (`create_user_page.dart:347-351`) | n | P |
| usr-08 | P2 | Excluir usuário | falta | sem `deleteUser` em `admin_users_service.dart` | n | P |
| usr-09 | P2 | Compartilhar com empresas | falta | nenhuma ref. a `/admin/users/share` | n | M |
| usr-10 | P2 | Reset de 2FA e desativação em massa | falta | nenhuma ref. a `reset-2fa`/`deactivate-many` | n | M |
| usr-11 | P2 | `can-create` e validações | parcial | telefone e documento alinhados (`create_user_page.dart:211-218`); falta `/admin/users/can-create` | n | P |
| usr-12 | P2 | Perfis prontos, tags e cargo | parcial | tags e cargo OK (`create_user_page.dart:282-287`); faltam os perfis prontos | n | M |
| usr-13 | P2 | Usuários abre com módulo OU permissão | falta | `users_page.dart:341-342` ainda com `\|\|` | n | P |
| eq-02 | P2 | Aviso dos funis na exclusão da equipe | falta | `api_constants.dart:739` declarado, sem uso | n | P |
| prf-02 | P2 | Último acesso, empresas e score | parcial | empresas OK (`profile_page.dart:124-130`); faltam last-login e score | n | M |
| cfg-03 | P2 | Dispositivos, analytics e agenda | parcial | sobreposição da agenda OK (`settings_page.dart:1103-1111`); faltam dispositivos, analytics e backup/export | n | M |
| mst-01 | P2 | Telas Master órfãs | falta | 3 páginas de `platform_admin` sem rota | n | P |
| org-04 | P2 | WorkspacePage inalcançável | falta | `app_routes.dart:740`, sem `pushNamed` | n | P |
| eq-03 | P2 | Salvar equipe sem membros | feito | `team_form_page.dart:460` | n | – |
| usr-14 | P2 | `listManagers` com inativos e corte em 100 | falta | `admin_users_service.dart:321-326` | n | P |
| usr-15 | P2 | Vagas do plano e selo de check-in | falta | `AdminUser` sem `checkInActive`; `can-create` não é chamado | n | P |
| prf-04 | P2 | Gates de telefone e CPF | falta | nenhuma ref. a `pendingOneTimeDocumentReview` | n | M |

### Dashboards, SDR, Leads e Campanhas

| ID | P | Lacuna | Situação | Evidência | Deploy | Esforço |
|---|---|---|---|---|---|---|
| dash-01 | P0 | Visão executiva para admin/master | **feito** | `dashboard_page.dart:68,277`; `dashboard_overview_service.dart:29,42,104-113` | n | – |
| sdr-01 | P0 | Dash SDR no menu com gate de CRM | **feito** | `app_drawer.dart:1103-1105,1204-1219`; `sdr_dashboard_page.dart:107-109` | n | – |
| sdr-02 | P0 | `lists=none` | **feito** | `sdr_dashboard_filters.dart:180,193-196`; `sdr_service.dart:107` | n | – |
| leads-01 | P0 | Roleta de SDRs | **feito** | `sdr_roulette_service.dart:10-28`; `app_routes.dart:1045`; `whatsapp_inbox_page.dart:391` | n | – |
| dash-02 | P1 | Dashboard do gestor/líder | falta | nenhuma ref. a `manager/conversion-funnel`/`manager/overview` | n | G |
| sdr-03 | P1 | Filtros do SDR | feito | `sdr_dashboard_filters.dart:101-106,227-232`; `sdr_service.dart:341-414` | n | – |
| sdr-04 | P1 | 11 abas | n/a | o web só mostra Funil (`sdrDashboardVisibleTabs.ts:6`) | n | – |
| sdr-05 | P1 | Drill-down dos KPIs | feito | `sdr_dashboard_page.dart:896-954`; `sdr_dash_detalhe_sheet.dart:15` | n | – |
| sdr-09 | P1 | Recorte por equipe igual ao web | feito | `sdr_dashboard_filters.dart:204-223`; `sdr_service.dart:346` | n | – |
| leads-02 | P1 | Leads perdidos | falta | nenhuma ref. a `recovery-lost-leads` | n | M |
| leads-03 | P1 | Backups/Exportação órfã | falta | `OrganizationBackupsPage` sem rota | n | M |
| camp-01 | P1 | Gestão de campanhas Meta | falta | só `campaigns/list` usado no filtro (`sdr_service.dart:392`) | n | G |
| camp-02 | P1 | Campanhas do Sistema (CRUD) | falta | só leitura (`sdr_service.dart:414`) | n | M |
| camp-03 | P1 | Leads Meta e logs do webhook | falta | nenhuma ref. a `webhook-leads` | n | M |
| camp-04 | P1 | "Configure pelo painel web" | falta | `integration_details_page.dart:336,901-946`; `integrations_page.dart:586` | n | M |
| dash-03 | P1 | Meus ganhos / Meu Financeiro | falta | nenhuma ref. a `repasses/earnings` (= fin-02/fin-13) | n | G |
| an-01 | P1 | Dash Fichas Proposta | parcial | página, rota e atalho existem (`app_routes.dart:285,729`; `proposals_page.dart:376`); falta o item no drawer | n | P |
| an-02 | P1 | Análise de Imóveis: menu e gate | falta | `property_analytics_page.dart:66` só `performance:view_company`; sem drawer | n | P |
| sdr-06 | P2 | metaSpend/CAC | n/a (provável) | aba Campanhas oculta no web | n | – |
| sdr-07 | P2 | Exportar Dash SDR | falta | sem exportação em `features/sdr` | n | M |
| sdr-08 | P2 | Alias `/sdr/dashboard` | falta | só `/sdr` (`app_routes.dart:407,1041`) | n | P |
| leads-04 | P2 | Notificações de leads | falta | ausente | n | M |
| leads-05 | P2 | Dedupe de leads | falta | ausente | n | M |
| leads-06 | P2 | Distribuição de leads | falta | ausente | n | G |
| dash-04 | P2 | KPIs e blocos do corretor | falta | sem `recentActivities`; ranking e conversão ocultos (`dashboard_page.dart:236-251`) | n | P |
| dash-05 | P2 | Cards respeitam `property:view`/`client:view` | falta | sem gate em `dashboard_page.dart` | n | P |
| dash-06 | P2 | compareWith padrão `none` | parcial | executivo OK (`dashboard_filters_drawer.dart:102`); pessoal ainda `previous_period` (:123; `dashboard_page.dart:145`) | n | P |
| dash-07 | P2 | Pendências, subtarefas e ações rápidas | falta | ausente (`dashboard_page.dart:222-261`) | n | M |
| an-03 | P2 | Seção GA4 na Multicanal | falta | nenhuma ref. a `ga4/report` | n | M |
| an-04 | P2 | Dash Fichas Venda no menu | falta | só o botão em `sale_forms_page.dart:262` | n | P |
| an-05 | P2 | campaignOwnership e exportar Multicanal | falta | ausente | n | P |
| an-06 | P2 | Permissão estrita (sem bypass de papel) | parcial | Propostas estrito (`proposals_dashboard_page.dart:47-50`); Fichas Venda com bypass e sem `sale_forms` (`sale_forms_page.dart:262-264`) | n | P |

### Novos: cobrança, acesso e plano (fora da auditoria de 29/09)

| ID | P | Lacuna | Situação | Evidência | Deploy | Esforço |
|---|---|---|---|---|---|---|
| NEW-01 | **P0** | Conta gerenciada com trial ou graça vencidos (ou assinatura suspensa): o titular cai em /settings sem aviso nem forma de assinar; o colaborador não é checado e toma 403 na Home e em Imóveis. O web tem modal in-app e `/system-unavailable` | ✅ **feito (03/10)**: `SubscriptionAccessGate` (`shared/services/subscription_access_gate.dart`) decide no login (todos os papéis, após a empresa) e no splash; titular → `/subscription-required` (planos, minha assinatura, painel web, chamados, perfil), colaborador → `/system-unavailable`, ambos em `features/subscriptions/pages/access_blocked_page.dart`; `AppRoutes` redireciona qualquer outra rota enquanto bloqueado; 403 do `SubscriptionGuard` no meio da sessão reabre a checagem (`api_service.dart`). Lê `billingRegime` (managed só bloqueia em status terminal, como o web) e `isExpiringSoon` (aviso de "trial termina em N dias" ainda não exibido). Testes: `test/shared/services/subscription_access_gate_test.dart` | app: `login_flow_service.dart:245-281`, `login_page.dart:172-251`, `subscription_service.dart:89-102` (ignora `billingRegime`/`isExpiringSoon`). Web: `SubscriptionGuardNew.tsx:291-406`. Back: `subscriptions.service.ts:1532-1556` (`managed_exempt`), `subscription.guard.ts:24-104`, `dashboard.controller.ts:58`, `properties.controller.ts:184-191` | n | M |
| NEW-02 | **P0 cond.** | Plano "só Financeiro": 403 em todas as rotas de CRM; Home travada em "Sem permissão", sem alternativa no app | ✅ **feito (03/10, não depende do deploy)**: `shared/utils/crm_product_access.dart` espelha `hasCrmProduct` do back; empresa com módulos e sem CRM → `/crm-unavailable` ("O plano da empresa não inclui o CRM", painel web, chamado, perfil; rotas de plataforma liberadas). `CompanyService.choosePreferredCompany` prefere uma empresa com CRM quando o usuário tem as duas. usr-04 continua parcial | back `crm-product-access.interceptor.ts:36-110` (commit `848dac00`, 02/10); app sem `hasCrmProduct`; `dashboard_page.dart:865-876` | **s** | M |

Para corrigir NEW-01:
1. Tratar `hasAccess=false` autoritativo como estado bloqueante próprio, e não como `redirect` para /settings.
2. Para o titular gerenciado, mostrar a tela de assinatura com as rotas permitidas do web (planos, minha assinatura, chamados, perfil). Isso inclui registrar as rotas de sub-01.
3. Para o colaborador, chamar `check-access` também e mostrar "sistema indisponível".
4. Ler `billingRegime` e `isExpiringSoon` para avisar o fim do trial.

---

## Paridade web × app: Locações/Docs, Integrações, Transversal (re-verificação de 03/10/2026)

Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, linhas 1242–1672. Código conferido no estado atual do app (HEAD `675b686`, árvore limpa). Desde 29/09 não houve commits em `rentals`, `keys`, `condominiums`, `assets`, `tickets` nem em `notes_service`. Em `documents` houve 3 commits.

Legenda: **Back?** indica se depende de deploy do back (s/n). **Esforço**: P/M/G. **Quebra?** marca o que corrompe dado, devolve 400/403 ou trava o usuário. Os caminhos de evidência são relativos a `lib/`.

### Resumo por domínio

| Domínio | Itens | Feito | Parcial | Ainda falta | Web-only (candidato a sair) | Quebra hoje |
|---|---|---|---|---|---|---|
| Locações, Chaves, Patrimônio, Condomínios, Empreendimentos, Documentos, Anotações, Tickets | 34 | 6 | 1 | 27 (12 são Locação, fora do escopo) | tickets-01, cond-03, emp-05, loc-09 | chaves-01 (403), chaves-02 (dado inconsistente) |
| Integrações, Meu Site, Link in Bio, Portais | 37 | 4 | 4 | 29 | 14 itens: integ-06 a 11 e 13 a 20; integ-05 também é candidato | **integ-F1** (o site perde o formulário de captação) |
| Transversal | 32 | 6 | 6 | 20 | transv-12 (Migração), 13 (Master/Register/1ª empresa), 16, 17 (Suporte Dev) e o editor de funis (11) | transv-03, 04, 06, 08, 20, 21, 22, 23, 25 |
| **Total** | **103** | **16** | **11** | **76** | ~23 | 12 |

- **Documentos:** os 3 P0 (doc-01, 03, 05) estão confirmados no código. Também foram feitos doc-02 (baixar), doc-04 (assinaturas no detalhe) e doc-06 (excluir, aprovar e ações em lote). Faltam tags (doc-07) e a tela de Pastas CRM (doc-08: o serviço existe, a tela não).
- **Locação** (loc-01 a 12, transv-06 e transv-10): continua tudo ausente. Por decisão do Edson em 29/09, fica fora do escopo. Atenção à exceção transv-06: Fichas de Locação está visível no menu com o gate errado.
- **Condomínios, Empreendimentos, Chaves, Patrimônio, Anotações e Tickets:** nada mudou desde 29/09.
- **Integrações:** os 3 P0 de 29/09 (integ-01, 02, 03) estão confirmados. A F1 continua aberta e é o único item do domínio que destrói dado: **sugestão é promovê-la a P0**. O esforço é P e não depende do back.
- **Transversal:** os P0 (transv-01, 02, x01) estão confirmados. Os itens que quebram hoje são todos P1/P2 e nenhum depende de deploy do back.
- **Reclassificar transv-09 (Meu Financeiro):** estava FORA em 29/09, mas desde 02/10 o Financeiro é a prioridade número 1.
- **Back:** nenhuma lacuna verificada depende de deploy do back. Todas são trabalho só do app.

#### P0 que ainda faltam
- **loc-01**: Locações sem entrada no menu. Fora do escopo (decisão de 29/09).
- **loc-02**: parcela criada no app sai sem boleto/PIX. Fora do escopo (decisão de 29/09).
- **integ-F1** (proposta de promoção a P0): os presets do app não têm `lead_form`. Salvar seções com `homeBlocks` vazio apaga o formulário de captação do site público.

#### Quebra o app hoje (fora os P0)
- **transv-20**: telefone com DDI 55 é gravado errado.
- **transv-21**: CNPJ alfanumérico não pode ser digitado.
- **transv-03 e transv-04**: bypass de gestor e bypass de módulo levam a 403.
- ✅ **transv-06**: gate de Fichas de Locação (resolvido em 03/10).
- **transv-08**: Check-in aparece para empresa sem o módulo.
- ✅ **transv-22**: upload falha com token expirado (resolvido em 03/10: refresh proativo).
- ✅ **transv-23**: deep link `fichas-venda/assinaturas-pendentes` abre um id inválido (resolvido em 03/10).
- **transv-25**: rotas sem guarda de módulo/permissão.
- **chaves-01**: ações de chave sem permissão levam a 403.
- **chaves-02**: dá para criar uma chave já "Perdida" ou "Em uso".

---

### 1. Locações, Chaves, Patrimônio, Condomínios, Empreendimentos, Documentos, Anotações, Tickets

| ID | Prio | Lacuna | Situação | Evidência | Back? | Esforço | Quebra? | Nota |
|---|---|---|---|---|---|---|---|---|
| loc-01 | P0 | Locações sem entrada no app | ainda falta (fora do escopo) | shared/widgets/app_drawer.dart:1080-1082 (Locações oculto), 1133-1137 | n | P | não | Decisão de 29/09 |
| loc-02 | P0 | Criar parcela não gera boleto/PIX | ainda falta (fora do escopo) | features/rentals/services/rental_service.dart (sem create-and-charge) | n | M | sim, se a tela for exposta | Inalcançável enquanto loc-01 não for feito |
| doc-01 | P0 | Biblioteca sem entrada no menu | **feito** | app_drawer.dart:1088-1090, 1695-1749 (Biblioteca + Assinaturas) | n | P | não | — |
| doc-03 | P0 | Enviar para assinatura (Autentique) | **feito** | documents/pages/send_document_for_signature_page.dart:26-33 (batch, validações); document_details_page.dart:185-190, 1127 | n | M | não | — |
| doc-05 | P0 | Tela de assinaturas: link e reenvio | **feito** | documents/pages/signatures_page.dart:184, 905-929 (abrir, copiar, reenviar) | n | P | não | Acessível pelo drawer |
| loc-03 | P1 | Gerar, cancelar e editar cobrança; multa por parcela | ainda falta (fora do escopo) | rentals/ sem generate-charge/cancel | n | M | não | — |
| loc-05 | P1 | Travas de análise de crédito | ainda falta (fora do escopo) | rentals/ sem creditAnalysis | n | M | não | — |
| loc-06 | P1 | Pró-rata, checklist e documentos no formulário | ainda falta (fora do escopo) | rental_models.dart sem proRataEnabled/checklistId | n | M | não | — |
| loc-07 | P1 | Criar locação a partir da ficha | ainda falta (fora do escopo) | rental_forms/ não referencia /rentals | n | M | não | — |
| loc-08 | P1 | Detalhe sem checklist, documentos e seguros | ainda falta (fora do escopo) | rental_details_page.dart | n | M | não | — |
| loc-11 | P1 | Locação v2: Chaves & Retiradas | ainda falta (fora do escopo) | sem key-checkouts/keys-v1 em lib/ | n | G | não | — |
| loc-12 | P1 | Locação v2: Comercial, Esteira, Gerar contrato | ainda falta (fora do escopo) | sem features/locacao | n | G | não | — |
| cond-01 | P1 | Upload e remoção de imagens do condomínio | ainda falta | condominium_service.dart sem upload | n | M | não | — |
| cond-02 | P1 | Excluir com reatribuição de imóveis | ainda falta | condominiums_page.dart:316 (DELETE direto); condominium_service.dart:130 | n | M | não (mostra a recusa do back) | — |
| emp-01 | P1 | Obra/entrega, ficha técnica, tour, vídeo | ainda falta | development_form_page.dart (sem stage/towers/tourVirtualUrl) | n | M | não | — |
| emp-02 | P1 | Logo obrigatória | ainda falta | development_form_page.dart:36 ("upload multipart fora do escopo mobile") | n | M | sim (cria empreendimento sem logo, que o web exige) | — |
| emp-04 | P1 | Espelho do prédio | ainda falta | development_detail_page.dart (sem unidades) | n | G | não | — |
| doc-02 | P1 | "Baixar" era um TODO | **feito** | document_details_page.dart:173-182, 676-687 | n | P | não | — |
| doc-04 | P1 | Assinaturas no detalhe (enviar e reenviar) | **feito** | document_details_page.dart:113-133, 300-312, 1246-1264 | n | M | não | — |
| doc-06 | P1 | Excluir, aprovar e rejeitar (unitário e em lote) | **feito** | document_details_page.dart:245-295; documents_page.dart:212, 244, 262-322 (seleção em lote) | n | M | não | — |
| doc-08 | P1 | Pastas CRM (/crm/document-folders) | parcial | document_folder_service.dart:116 (`list` existe, sem tela); só task_document_folder_panel.dart usa o serviço | n | M | não | — |
| loc-04 | P2 | Parcelas em lote | ainda falta (fora do escopo) | — | n | M | não | — |
| loc-09 | P2 | Configurações e workflows de locação | ainda falta (fora do escopo) | rental_service.dart:234 (só GET) | n | M | não | web-only |
| loc-10 | P2 | Filtro "Só vencidos" | ainda falta (fora do escopo) | rental_models.dart sem `vencidas` | s (confirmar o DTO) | P | não | — |
| chaves-01 | P2 | Nenhuma checagem de permissão key:* | ✅ feito (03/10: criar/editar/excluir/retirar/devolver com `key:create/update/delete/checkout/return` em keys_page, key_card e create_key_page) | keys/ sem hasPermission; core/routes/app_routes.dart:647-655 sem gate | n | P | sim (403 nas ações) | Chega-se pelo detalhe do imóvel (property_details_page.dart:6838) |
| chaves-02 | P2 | Status na criação da chave | ✅ feito (03/10: criação envia sempre `available`, como o web; status só na edição) | keys/pages/create_key_page.dart:341-360 (chips sem `keyId != null`) | n | P | sim (permite criar chave já "Perdida" ou "Em uso") | — |
| patr-01 | P2 | Valor do patrimônio obrigatório | ainda falta | assets/pages/create_asset_page.dart:276-281 (sem `*` e sem validator) | n | P | não (envia 0, aceito por @Min(0)) | — |
| cond-03 | P2 | Duplicados de condomínios | ainda falta | ausente | n | M | não | web-only (curadoria administrativa) |
| cond-04 | P2 | "Ver imóveis do condomínio" | ainda falta | condominiums/ sem rota para properties | n | P | não | — |
| emp-03 | P2 | Galeria, plantas, obra, material | ainda falta | development_service.dart sem upload | n | G | não | — |
| emp-05 | P2 | Modelo de documentos e alternar ativo fora do formulário | ainda falta | development_detail_page.dart:367-396 (só mostra o selo) | n | M | não | O editor do modelo de documentos é web-only |
| doc-07 | P2 | Tags no cadastro e no filtro | ainda falta | create_document_page.dart (sem tags); document_filters_drawer.dart:48-50 | n | P | não | O detalhe já mostra as tags (document_details_page.dart:464-527) |
| notas-01 | P2 | Tipo da anotação pelo plano | ainda falta | shared/services/notes_service.dart:140 (`'type': 'advanced'` fixo) | n | P | não | — |
| tickets-01 | P2 | Fila de suporte da União e triagem | ainda falta | tickets/services/ticket_service.dart (sem update); ticket_detail_page.dart:310 | n | M | não | web-only (uso interno da União) |

### 2. Integrações, Meu Site, Link in Bio, Portais

| ID | Prio | Lacuna | Situação | Evidência | Back? | Esforço | Quebra? | Nota |
|---|---|---|---|---|---|---|---|---|
| integ-01 | P0 | Salvar links da Bio apagava lead_form, ícone e subtítulo | **feito** | features/public_site/models/bio_page_model.dart:116-195 | n | P | não (era sim) | — |
| integ-02 | P0 | DNS: CNAME legado em vez de registro A | **feito** | public_site_config_model.dart:881-1061; public_site_page.dart:285-290 | n | P | não (era sim) | — |
| integ-03 | P0 | E-mail vazio dava 400 | **feito** | public_site_config_model.dart:92, 454 (`_nullIfBlank`); public_site_page.dart:563-569 | n | P | não (era sim) | — |
| integ-04 | P1 | Config do WhatsApp (Oficial, QR, distribuição) | ainda falta | integrations/pages/integration_details_page.dart:936-946 ("Configure pelo painel web") | n | G | não | Reconectar o QR tem valor no celular. API Oficial e IA de grupos são web-only |
| integ-05 | P1 | Autentique: chave de API e ambiente | ainda falta | integration_details_page.dart:299-301 | n | P | não | Candidato a web-only (configurado uma vez) |
| integ-06 | P1 | Grupo ZAP | ainda falta | integration_details_page.dart:936 | n | G | não | web-only |
| integ-07 | P1 | Chaves na Mão | ainda falta | idem | n | G | não | web-only |
| integ-08 | P1 | Imovelweb | ainda falta | integrations_service.dart:439-441 | n | G | não | web-only |
| integ-09 | P1 | Webhook de Leads | ainda falta | integrations_service.dart:368-395 | n | M | não | web-only |
| integ-10 | P1 | Webhook de Fichas | ainda falta | integrations_service.dart:397-416 | n | G | não | web-only |
| integ-11 | P1 | Config Meta | ainda falta | integrations_service.dart:427-430 | n | M | não | web-only |
| integ-12 | P1 | Gestão de campanhas Meta | ainda falta | shared/utils/app_deep_link.dart:360-366 (cai no hub) | n | G | não | Lista, pausa e métricas servem no celular. Criar campanha é web-only |
| integ-13 | P1 | Leads Meta e logs do webhook | ainda falta | ausente | n | M | não | web-only |
| integ-14 | P1 | Campanhas do Sistema | ainda falta | integrations_service.dart:85-94 | n | M | não | web-only |
| integ-15 | P1 | Google Ads/GA4 (OAuth) | ainda falta | integration_model.dart:402 | n | M | não | web-only |
| integ-16 | P1 | API de Imóveis: chaves | ainda falta | integrations_service.dart:296-315 | n | M | não | web-only |
| integ-17 | P1 | ChatPro | ainda falta | integrations_service.dart:109-111 | n | M | não | web-only |
| integ-18 | P1 | Atribuição por Grupo WhatsApp | ainda falta | integrations_service.dart:170-192 | n | M | não | web-only |
| integ-20 | P1 | Dedupe e Notificações de Leads | ainda falta | ausente | n | M | não | web-only. Sobrepõe transv-28 |
| integ-21 | P1 | Drawer esconde a Central de quem só tem view | ainda falta | shared/widgets/app_drawer.dart:1108-1121 | n | P | não | Duplica transv-07 |
| integ-22 | P1 | Trocar template e comprar Premium | ainda falta | public_site_page.dart:2079 ("só pelo painel web") | n | M | não | — |
| integ-23 | P1 | Branding (cores, logo, favicon, capa) | parcial | public_site_config_model.dart:137-215 (hero* lido); public_site_page.dart:1931 (só leitura) | n | M | não | Falta a UI. O helper public_site_upload.dart existe sem uso |
| integ-24 | P1 | Redes, endereço, horário, selos, WhatsApp flutuante, GA | parcial | public_site_config_model.dart:376-496 (modelo completo, preservado no save); public_site_page.dart:135-142 (só 8 campos editáveis) | n | M | não | — |
| integ-25 | P1 | Funil e coluna dos leads do site | ainda falta | public_site_config_model.dart:709-742 (sem leadKanban*) | n | P | não | — |
| integ-26 | P1 | Adicionar/remover seções, settings, cabeçalho | ainda falta | public_site_config_model.dart:575-628 | n | M | não | — |
| integ-27 | P1 | Vitrine do Site | ainda falta | ausente | n | M | não | — |
| integ-28 | P1 | Domínio pending_ssl/failed e motivo da recusa | parcial | public_site_config_model.dart:60-70; public_site_page.dart:243-305 | n | P | não | `domainRejectionReason` não é lido |
| integ-29 | P1 | Bio: template, avatar, aparência, Premium | ainda falta | public_site/pages/bio_link_page.dart:42 ("ficam no painel web") | n | G | não | customization é preservada |
| integ-30 | P1 | Bio: botão de captação e funil | parcial | widgets/bio_link_edit_sheet.dart:63, 89-98; bio_page_model.dart:261-318 | n | P | não | Edita um lead_form existente, mas não cria nem escolhe funil |
| **integ-F1** | P1 → **P0 sugerido** | Presets sem lead_form: salvar seções apaga o formulário do site | ✅ **feito (03/10)** | `PublicSiteBlockCatalog.templatePresets` = cópia exata do back (`public-site-blocks.types.ts`) e do web (`publicSiteBlocks.ts`): todos com `lead_form` antes do `cta`, Premium com `ribbon` (não `stats`); catálogo ganhou rótulo/ícone de `lead_form` e `ribbon`. Teste: `test/features/public_site/public_site_home_blocks_test.dart` | n | P | não (era sim) | — |
| integ-19 | P2 | Notificações do WhatsApp | ainda falta | ausente | n | P | não | web-only |
| integ-31 | P2 | Analytics da Bio | ainda falta | bio_page_model.dart:416-433 | n | P | não | — |
| integ-32 | P2 | Preview-session e provedor de DNS | ainda falta | public_site_service.dart | n | P | não | — |
| integ-33 | P2 | Hub: filtros e "Falhando" | ainda falta | integrations_page.dart:143; integrations_service.dart:137 | n | P | não | — |
| integ-34 | P2 | Gate WhatsApp sem papel admin/manager | ainda falta | integration_model.dart:288 | n | P | sim (403, sem dano) | — |
| integ-35 | P2 | Deep links /integrations/x/config e /settings/* | ainda falta | app_deep_link.dart:360-366 | n | P | não | Sobrepõe transv-28 |
| integ-F2 | P2 | Textos de domínio falando em CNAME | **feito** | public_site_page.dart:647-655, 683; public_site_config_model.dart:1007-1061 | n | P | não | — |

### 3. Transversal

| ID | Prio | Lacuna | Situação | Evidência | Back? | Esforço | Quebra? | Nota |
|---|---|---|---|---|---|---|---|---|
| transv-01 | P0 | Cliente exigia e-mail, CPF, CEP e endereço | **feito** | features/clients/pages/client_form_page.dart:1347, 1373, 1394 | n | P | não (era sim) | — |
| transv-02 | P0 | Imóvel sem "CEP não aplicável" | **feito** | properties/pages/create_property_page.dart:118, 982, 1548, 2676, 3256, 5055 | n | M | não (era sim) | — |
| transv-x01 | P0 | 2FA obrigatório sem setup bloqueava o login | **feito** | auth/two_factor/pages/two_factor_setup_page.dart:30; shared/services/login_flow_service.dart:361 | n | M | não (era sim) | — |
| transv-03 | P1 | Bypass total para manager | ✅ **feito (03/10)** | module_access_service.dart usa `roleBypassesPermission` (shared/utils/role_access_rules.dart), espelho do `PermissionsGuard`: master tudo; admin tudo menos `user:create`; manager só `performance:view_company` e `property:update/delete/approve_publication/reject_publication`. Teste: test/shared/utils/role_access_rules_test.dart | n | P | não (era sim) | Gestor sem permissão explícita deixa de ver ações que o back recusaria |
| transv-04 | P1 | Módulo ignorado para admin/gestor | ✅ **feito (03/10)** | `isModuleAvailableForCompany`: só master ignora o módulo (`ModuleAccessGuard`/`checkModuleAccess`). Enquanto a empresa não carregou, admin/gestor seguem liberados (evita sumir tela no 1º acesso; o back decide) | n | P | não (era sim) | — |
| transv-06 | P1 | Fichas de Locação: rental_form:view em vez de rental:view | ✅ **feito (03/10)** | app_drawer.dart (canSeeRentalForms → `rental:view`); rental_forms_page.dart (gate da tela → `RentalFormPermissions.listView`); ações seguem `rental_form:*` como no web | n | P | não (era sim) | — |
| transv-09 | P1 | Meu Financeiro e Solicitações | ainda falta | sem features/my_finance | n | G | não | **Reclassificar: Financeiro é prioridade desde 02/10** |
| transv-10 | P1 | Locação v2 (/locacao/*) | ainda falta (fora do escopo) | sem features/locacao | n | G | não | Decisão de 29/09 |
| transv-11 | P1 | Funis, Visão Unificada, Leads perdidos | ainda falta | ausente | n | G | não | O editor de funil é candidato a web-only |
| transv-14 | P1 | Visitas, Dash SDR, Análise de Imóveis no menu | parcial | Visitas: app_drawer.dart:1076-1078; SDR: 1103-1105; Análise: rota em app_routes.dart:428, sem item | n | P | não | Falta só a Análise de Imóveis |
| transv-15 | P1 | Dash Fichas Proposta | **feito** | app_routes.dart:285, 729; proposals_page.dart:371-376 | n | M | não | — |
| transv-18 | P1 | Busca global de leads | ainda falta | sem search-leads/my-leads-summary | n | M | não | — |
| transv-19 | P1 | Modais globais (telefone, CPF, imóveis desatualizados) | ainda falta | sem stale-for-user / document-self-service | n | M | não | — |
| transv-20 | P1 | Telefone com DDI 55 cortado | ✅ **feito (03/10)** | `Masks.brPhoneDigits` (masks.dart) tira o DDI de números com 12/13 dígitos começando por 55 (regra do web); usado por `Masks.phone`/`unmaskPhone`, `PhoneInputFormatter` (colar/autopreencher) e `Validators.phone`. Teste: test/shared/utils/phone_cnpj_normalization_test.dart | n | P | não (era sim) | DDD 55 (RS) com 11 dígitos fica intacto |
| transv-21 | P1 | CNPJ alfanumérico recusado | ✅ **feito (03/10)** | `Masks.cnpj`/`unmaskCnpj`, `CnpjInputFormatter` e `Validators.cnpj`/`isValidCnpj` aceitam [A-Z0-9]{12}+2 DVs (ASCII−48, igual ao `CNPJAlfanumericoValidator` do back); teclado com letras em estate_form_sections, MaskedTextField e CpfCnpjTextField (máscara dinâmica `Masks.cpfOrCnpj`); create_user_page e vistorias enviam o documento com letras | n | P | não (era sim) | Pendente: rental_form_editor_page (Locação, fora do escopo) usa o formatter novo mas com teclado numérico; rental_form_page tem máscara própria só numérica |
| transv-24 | P1 | Deep link "proposta finalizada → ficha" | parcial | create_sale_form_page.dart:442, 656 (aceita a proposta); app_deep_link.dart:302-320 (vai para a lista) | n | P | não | — |
| transv-x03 | P1 | Chat interno sem item no menu | ainda falta | app_drawer.dart:26-28, 2165-2178 (sem item) | n | P | não | — |
| transv-x04 | P1 | Ficha de venda a partir de proposta | **feito** | create_sale_form_page.dart:23, 1591; proposal_picker_sheet.dart:64, 120 | n | M | não | — |
| transv-05 | P2 | Menu: view + ação; noRoleBypass | parcial | só Visitas aplica a regra (app_drawer.dart:1076); os demais usam hasPermission simples (1001-1022) | n | M | não | — |
| transv-07 | P2 | Gates de Integrações e Empreendimentos | ainda falta | app_drawer.dart:1108-1121, 1539, 1566 | n | P | não | Duplica integ-21 |
| transv-08 | P2 | Check-in sem o módulo visit_report | ✅ feito (03/10) | app_drawer.dart usa `CheckInAccess.canSeeCheckIn`: módulo `visit_report` (back: `@RequireModule(VISIT_REPORT)` no `CheckInController`) + permissão de check-in; bypass só master/admin | n | P | não (era sim) | — |
| transv-12 | P2 | Vendidos/Locados, Captações, Migração, Conversas de aprovação | ainda falta | ausente | n | M | não | Migração é web-only |
| transv-13 | P2 | Telas órfãs | ainda falta | Units/Hierarchy/Backups/Master/Subscription/Register sem rota | n | M | não | Master, Register e 1ª empresa são web-only. Assinaturas pendentes já está no drawer (app_drawer.dart:1413) |
| transv-16 | P2 | Configs de fichas e do imóvel | ainda falta | só serviços de leitura | n | G | não | Candidato a web-only |
| transv-17 | P2 | Documentos, Pastas CRM, PDI, Suporte Dev | parcial | Biblioteca e Assinaturas no drawer (app_drawer.dart:1713, 1737) | n | G | não | Suporte Dev é web-only |
| transv-22 | P2 | Multipart sem refresh e sem retry em 401 | ✅ **feito (03/10, refresh proativo)** | `buildOutboundHeaders` chama `garantirTokenFresco(120s)` antes de montar o header (cobre os 16 serviços multipart que usam o helper); `profile_service.uploadAvatar` também. Retry automático em 401 do multipart não foi feito (o corpo do `MultipartRequest` não é reaproveitável — exigiria mexer em cada serviço) | n | M | não (era sim) | — |
| transv-23 | P2 | Deep link fichas-venda/assinaturas-pendentes vira id | ✅ **feito (03/10)** | app_deep_link.dart: `assinaturas-pendentes` → `AppRoutes.saleFormsPendingSignatures` e entrou nos segmentos reservados; teste em app_deep_link_test.dart | n | P | não (era sim) | — |
| transv-25 | P2 | Rotas sem guarda de módulo/permissão | ✅ **feito (03/10, rotas de maior risco)** | `PermissionRoute` ganhou `module` e mostra "sem permissão/fora do plano" (antes tela em branco); app_routes.dart `_guarded` em Vistorias (`vistoria` + inspection:view/create/update), Chaves (`key_control` + key:view/create/update), Patrimônio (`asset_management` + asset:*), Régua de Cobrança (`credit_and_collection` + collection:*), como o web | n | M | não (era sim) | Pendente: demais rotas (checklists, MCMV, automações, condomínios etc.) — as telas já se auto-gateiam ou o web também não guarda; rotas de imóveis/fichas ficaram de fora (outro agente) |
| transv-26 | P2 | Máscara monetária sem milhar | parcial | cliente ok (client_form_page.dart:382); imóvel usa MoneyInputFormatter (create_property_page.dart:5912-6046) | n | P | não | — |
| transv-28 | P2 | Notif./Dedupe/Distribuição de leads e deep link /config | ainda falta | integration_model.dart:252; app_deep_link.dart:360-366 | n | M | não | Sobrepõe integ-20 e integ-35 |
| transv-30 | P2 | "Lembrar em 15 min" | ainda falta | só a constante (core/constants/api_constants.dart:264) | n | P | não | — |
| transv-x02 | P2 | Segurança da empresa no perfil | **feito** | profile/pages/profile_page.dart:138-142; company_admin_service.dart:300-318 | n | P | não | — |

#### Correção extra (03/10/2026, sessão líder)

- **chaves-F1 — Editar chave abria o formulário vazio** ✅: `CreateKeyPage` nunca buscava a chave na edição; o formulário vinha em branco e salvar sobrescrevia nome/descrição/local/observações com vazio. Agora carrega por `getKeyById` antes de mostrar (com carregando, erro e "Tentar de novo"); o imóvel aparece só para consulta, porque o `UpdateKeyDto` do back não troca o imóvel de uma chave. Arquivo: `lib/features/keys/pages/create_key_page.dart`.
