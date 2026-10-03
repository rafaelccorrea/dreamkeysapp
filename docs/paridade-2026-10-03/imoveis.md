# Paridade web × app — Imóveis (verificação e fechamento 03/10/2026)

Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, seção "## Imóveis" (45 lacunas), mais as pendências do card do funil. Conferido no código dos três repos (app a partir de `675b686`; inclui `fa64c2e`).

- A **verificação da manhã** está nas tabelas por severidade (colunas "Evidência no app" e "Web / back" descrevem o estado anterior).
- O que foi executado está em duas levas: **"Execução no app (03/10/2026)"** (manhã) e **"Fechamento (03/10/2026, tarde)"**.
- **Todas as linhas estão ✅.** As que são "não se aplica" trazem a justificativa verificável.

## Resumo

| Severidade | Itens | Feitos | Parciais | Faltam |
|---|---|---|---|---|
| P0 | 9 | **9** | 0 | 0 |
| P1 | 19 | **19** | 0 | 0 |
| P2 | 17 | **17** (imoveis-41 = não se aplica, justificado) | 0 | 0 |
| **Auditoria** | **45** | **45** | **0** | **0** |
| Card do funil (extras) | 14 | **14** (teto de área = não se aplica) | 0 | 0 |

- **Todos os P0 estão fechados.** A edição pelo app não corrompe mais tipo, status, booleanos nem captadores. Duplicidade, "Sem CEP", áreas e negociação seguem o web.
- **Correção de premissa.** O back **não** recusa campo desconhecido. `intellisys-CRM-Back/src/main.ts:225-226` usa `whitelist: true, forbidNonWhitelisted: false`, então campo fora do DTO é **descartado em silêncio**. O risco é a chave "sumir", não dar 400.
- **Back.** As três pendências do back foram resolvidas no código (ver "Mudanças no back"). **Exige deploy, e antes dele o ensure/migration das 7 colunas do endereço do proprietário.**
- **Bugs novos, fora da auditoria:**
  1. ✅ (03/10) **A exportação do app nunca funcionou.** O app fazia `GET /properties/export`, mas o back só tem `@Post('export')`. O GET caía em `GET :id` com `ParseUUIDPipe` e voltava 400.
  2. ✅ (03/10) **O toggle "Apenas inativos" não filtrava nada.** O app mandava `isActive=false`, que o `GET /properties` não lê. Agora é `portfolioScope=inactive`.
  3. ✅ (03/10) **Preço "0.00" aparecia como "R$ 0"** na lista e no detalhe, em vez de "não se aplica".
  4. ✅ (03/10, back) **"Linha premium" não gravava, no web e no app.** `isSitePremiumLine` entrou no `UpdatePropertyDto`.
  5. ✅ (03/10, app) **Área multiplicada na edição.** A conversão de área do wizard tirava o ponto como milhar: "120.5" (como a edição preenche) virava 1205 m² ao salvar. Corrigido em cpp (parse de área). **Vale conferir na base se há imóveis com área ×10/×100 gravados pelo app.**

## Execução no app (03/10/2026, manhã)

Feito no app seguindo a "Ordem de execução" (back não alterado). Todo campo novo enviado foi conferido no DTO do back.

| Item | Status | Onde |
|---|---|---|
| Bug 1 / imoveis-26: exportar | ✅ `POST /properties/export?format=` com `{ filters }` da lista (aba, busca, filtros), prévia `dryRun` (total, escopo, teto) e entrega pela folha de arquivo (compartilhar/salvar). Nome do arquivo vem do `Content-Disposition` | ps `exportProperties`/`previewExport`/`toExportFilters`; `widgets/export_import_dialog.dart`; PP `_handlePropertiesOverflowAction` |
| imoveis-27: gate de exportar/importar | ✅ cada metade só com `property:export` / `property:import`; o item do menu some sem nenhuma | `export_import_dialog.dart`; PP `_PropertiesOverflowSheet` |
| Bug 2: "Apenas inativos" | ✅ vira `portfolioScope=inactive` (= aba Inativos); estado antigo `isActive=false` em cache é migrado | PP `_onlyInactive`/`_toggleOnlyInactive`/`_restoreCachedState` |
| Bug 3: preço "0.00" | ✅ lista: só os preços > 0 (venda+locação mostra os dois; nenhum = "Preço não informado"); detalhe: "Não se aplica" no lugar de "R$ 0"; médias da lista ignoram 0 | `utils/property_price_display.dart`; PP `_formatMainPrice`; `widgets/details/property_values_section.dart` |
| imoveis-F4: apagar e-mail do proprietário | ✅ edição manda `ownerEmail: null` quando vazio; criação não manda | cpp (payload) |
| imoveis-14: `pendingChangeRequest` / `resubmittedForApproval` | ✅ parse no `Property`; edição avisa o que foi para aprovação (azul) ou o reenvio à fila (âmbar), textos do web. Também nas observações internas do detalhe | ps `PropertyPendingChangeRequest`/`PropertyResubmission`; `utils/property_save_feedback.dart`; cpp; DP `_saveInternalNotes` |
| imoveis-22: mudar voto | ✅ quem já votou abre a folha com o voto marcado e confirma por `PUT` ("Alterar voto"); POST com 409 refaz como PUT; lista quem votou e como | `services/property_approval_service.dart` `castVote`; `models/property_change_request.dart`; `widgets/approval_info_sheets.dart`; `pages/property_approvals_page.dart` |
| imoveis-23: abas + contagem | ✅ Todos, Disponíveis, Em negociação, Vendidos, Locados, Pendentes, Recusados, Outros, Inativos, com o número de `GET /properties/portfolio-counts` | ps `PortfolioScope`, `getPortfolioCounts`; PP `_buildPortfolioScopeStrip` |
| imoveis-15/16 + card: atalhos no menu da lista | ✅ "Alterar status" (inclui vendido/locado), "Ativar/Desativar" (gestão) e "Publicar/Ocultar do site" | PP `_showPropertyQuickActionsSheet`, `_toggleSitePublication` |
| Bloqueio por aprovação financeira | ✅ com `hasPendingFinancialApproval`, "Alterar status" tira Vendido/Alugado e explica | ps; `widgets/details/property_status_change_sheet.dart`; `utils/property_publish_rules.dart` |
| imoveis-F2 + `publishableImageCount` | ✅ Publicar/Ocultar na lista e no detalhe; publicar exige ativo, Disponível e 5 fotos | `utils/property_publish_rules.dart`; PP; DP; `widgets/details/property_site_tab.dart` |
| Tela "Vendidos e Locados recentemente" | ✅ `GET /properties/recent-deals` | `pages/recent_deals_page.dart`; ps `getRecentDeals`; PP |
| Catálogo + `extraRooms` | ✅ `GET /property-catalog`: cômodos extras com quantidade no wizard e infraestrutura somada às características | cpp `_buildExtraRoomsSection`, `_loadPropertyCatalog`; `utils/property_form_extras.dart` |
| imoveis-12: permuta | ✅ "Aceita permuta? *" (Sim/Não + valor máximo), obrigatório como no web (rascunho isento) | cpp `_buildExchangeSection`; `utils/property_form_extras.dart` |
| imoveis-11: equipe | ✅ com equipes disponíveis (ou a regra da empresa) a equipe é obrigatória na criação e na edição | cpp `_teamRequired` |
| imoveis-09: limites próprios | ✅ removidos os limites que o web não tem; mantidos só os tetos do DTO | cpp (`_validateCurrentStep`, `_findFirstStepValidationError`, validators) |
| imoveis-25 (1ª parte) | ✅ ordenação, finalidade e código; o drawer limpa de verdade ao desmarcar | ps `PropertyFilters`; `widgets/property_filters_drawer.dart` |
| imoveis-28 (1ª parte) | ✅ mostrar/ocultar a foto no site na galeria em tela cheia do detalhe | DP `_toggleCurrentSiteVisibility`; `services/property_detail_extras_service.dart` |

## Fechamento (03/10/2026, tarde)

Tudo o que estava pendente foi fechado no app e no back.

**Verificação:**
- **`flutter analyze`** (de `X:\`): 0 erros no projeto. No recorte de imóveis (`lib/features/properties`, serviços tocados e testes) são 31 infos, sem erro nem aviso; eram 33.
- **`flutter test`:** a suíte inteira passa (495 testes), 156 deles em `test/features/properties` (eram 30 de manhã).
- **Back:** `npx tsc --noEmit` limpo e `npx jest src/properties/utils` com 9 suítes e 109 testes passando.

### App

| Item | Status | Onde |
|---|---|---|
| imoveis-10: captadores por papel + responsáveis | ✅ Seção "Captação e responsáveis *" na etapa 1 (cpp ~5165): um cartão por papel (venda/locação) com a regra de slots do web (`evaluateCaptorSlots`: finalidade define o obrigatório, mesma pessoa pode ocupar os dois, sempre ≥ 1 captador), botão "Mesmos da venda/locação" e lista de responsáveis (responsável começa com o usuário logado só na criação; captadores sem pré-seleção, como o web). Usuários de `GET /admin/users`, como o web; 403 mostra o aviso do web. Validação na etapa e antes de salvar (rascunho isento). Edição: carrega do imóvel (ps lê `role` de cada captador); **só manda o que mudou**: troca de pessoa → `capturedByIds` + `captorAssignments`; só papel/finalidade → `captorAssignments`; responsáveis só se mudou o conjunto ou o principal. **Troca de captador abre pedido de aprovação:** a resposta é tratada como no web (`CreatePropertyPage.tsx` ~4559-4594): aviso azul de `pendingChangeRequest` (`utils/property_save_feedback.dart`) e recarga do detalhe com o valor vigente | `utils/property_captor_slots.dart`; `services/property_captor_users_service.dart`; `widgets/property_captors_section.dart`; cpp; ps; `test/.../property_captors_test.dart` |
| imoveis-13: ~30 campos do wizard | ✅ Igual ao web (`CreatePropertyPage.tsx` 7140-7432, `buildCreatePropertyApiPayload.ts` 345-411), nomes conferidos no DTO:<br>• **Salas:** `rooms` no lugar de Quartos para Comercial.<br>• **Ficha adicional** (etapa Medidas e detalhes): isHighStandard, hasPlaque, hasExclusivity, isPrivate, as 5 garantias (bail, suretyBond, bondApplication, credpagoGuarantee, guarantor), builtYear, alternativeCode, unitFloor, floors, buildings, elevators, sunPosition, propertySituation, lotArea/lotMeasureType, propertyUnity, visitTime, siteContact, ownersPercentage/ownersRate, houseRules, nearby, siteMetaDescription.<br>• **Linha premium:** `isSitePremiumLine` na revisão, com "Publicar no site".<br>• **Catálogo:** `/property-catalog` (já de manhã).<br>• **Edição** manda só o que mudou (apagado = `null`); rascunho local guarda tudo. **Não se aplica:** `tower` e `unitTypology` não existem no wizard do web (só no filtro, `PropertyFiltersDrawer.tsx:525`) | `utils/property_extra_fields.dart`; `widgets/property_extra_fields_form.dart`; cpp; ps (`rooms`); `test/.../property_wizard_extra_fields_test.dart` |
| imoveis-13: endereço estruturado do proprietário | ✅ CEP (ViaCEP, mesmo serviço do endereço do imóvel), UF, rua, número, complemento, bairro e cidade, com os nomes do web (`ownerZipCode`… ). O `ownerAddress` de texto é montado das partes como no web. Na edição vai só o que mudou. O detalhe mostra o endereço montado das partes (resposta do back: `owner.{zipCode, street, …}`), respeitando `canViewOwnerData`/`ownerDataRestricted` | `utils/property_owner_address.dart`; cpp; ps (owner); `widgets/details/property_owner_section.dart` |
| imoveis-25: filtros e ordenação | ✅ Todos os filtros do web no drawer, com nomes de query iguais aos do web e centralizados (ps `PropertyListQueryKeys`):<br>• **Faixas e quantidades:** `minSalePrice`/`maxSalePrice`, `minRentPrice`/`maxRentPrice`, `suites`, `rooms`.<br>• **Endereço:** `zipCode` (o CEP agora vai na query), `number`, `propertyUnity`, `tower`, `block`, `lot`, `sector` (12 sugestões).<br>• **Pessoas e equipes:** `ownerName`, `ownerPhone`, `teamId`, `captorsTeamId`, `responsibleUserId`, `responsibleWithoutCaptor`.<br>• **Datas:** `createdFrom`/`createdTo`.<br>• **Excluídos:** `listDeletedOnly`, atalho "Somente excluídos" para quem pode excluir; o card mostra a pílula "Excluído" e abre o detalhe em modo consulta.<br>Os mesmos filtros vão para `portfolio-counts` e para o export. "Limpar" mantém aba, "minhas" e busca | ps `PropertyFilters`/`_extendedParams`/`PropertyListQueryKeys`; `widgets/property_filters_drawer.dart`; PP; `test/.../property_filters_query_test.dart` |
| imoveis-28: galeria | ✅ "Gerenciar fotos e vídeo" no detalhe, em Ações rápidas, para quem edita (DP ~6565). Abre uma tela própria com:<br>• **Fotos:** reordenar (arrastar ou mover; `PUT /gallery/reorder { imageIds }` só com fotos, como o web; volta a ordem se der erro), capa, mostrar/ocultar no site, excluir e adicionar.<br>• **Vídeo:** enviar, trocar e remover (`POST /gallery/upload-video`), com os limites do web: MP4/MOV/WebM, 150 MB, 100 s.<br>• **Duração:** medida com `video_player`. Se não der para medir, o envio é bloqueado com a mensagem do web.<br>• **Capa:** um quadro tirado com `fc_native_video_thumbnail` vai no campo `thumbnail`, como o web faz no navegador; o back não gera capa nem duração (`gallery.service.ts:612-720`).<br>• **Pacotes novos no pubspec:** `video_player ^2.14.1` e `fc_native_video_thumbnail ^3.0.1`, que pedem `pod install` no iOS.<br>`GalleryService.updateImage` agora usa **PUT** (era PATCH), com os campos aceitos pelo back. Na web a gestão fica na edição; no app fica no detalhe, a um toque da edição | `widgets/details/property_gallery_manager_page.dart`; `utils/gallery_media_rules.dart`; `lib/shared/services/gallery_service.dart` (`updateImage`, `uploadVideo`); DP; `test/.../gallery_media_rules_test.dart` |
| imoveis-29: owner-check | ✅ Ao avançar a etapa Proprietário (só no cadastro), chama `POST /properties/owner-check` com o payload do web. Folha "Este proprietário já possui imóveis" com o selo do que coincidiu (CPF/CNPJ ou telefone); "Voltar e revisar" / "Continuar cadastro". Não pergunta de novo se os dados não mudaram. Se a consulta falhar, segue com aviso, como o web | `services/property_owner_check_service.dart`; `widgets/property_owner_gate.dart`; `widgets/property_duplicate_sheet.dart`; cpp |
| imoveis-30: aba Site / linha premium | ✅ O app já mandava e lia `isSitePremiumLine`; o back agora grava (ver "Mudanças no back") | `property_detail_extras_service.dart`; back `update-property.dto.ts` |
| imoveis-33: conversa de aprovação | ✅ Caixa de conversas (`GET /properties/approval-chat-inbox`) aberta pelo botão "Conversas · N" da tela de aprovações, como o botão da fila na web. Mostra totais, não lidas, busca, "Abrir imóvel" e o selo Cadastro/Site. Ao abrir uma conversa chama `POST …/approval-thread/mark-seen` | `pages/approval_chat_inbox_page.dart`; `models/approval_chat_inbox_item.dart`; `services/property_approval_service.dart` (`markApprovalThreadSeen`, `getApprovalChatInbox`); `pages/property_approvals_page.dart` |
| imoveis-34: "minhas" + selo "Edição pendente" | ✅ Chips "Minhas" (`mine=true`, para revisores) e "Imóvel: …" (`propertyId`) nas solicitações. Selo "Edição pendente" no card da lista via `GET /property-change-requests/pending-property-ids` | `utils/change_request_filters.dart`; `pages/property_approvals_page.dart`; `services/property_list_signals_service.dart`; PP |
| imoveis-35: lastActivity no card | ✅ Parse de `lastActivity` (`PropertyLastActivity`) e linha "Evento · data · usuário" no card, com os rótulos do histórico do web | ps; PP |
| imoveis-36: telas de configuração | ✅ Hub "Configurações de imóveis" no menu "Ações do portfólio", com quatro telas:<br>• **Regras do formulário:** `form-settings`, `PATCH approval-settings`, catálogo.<br>• **Aprovações:** regras, votação, aprovadores e revogação.<br>• **Campos protegidos.**<br>• **Dados do proprietário:** `/protected-owner-data/users` e `/scope`.<br>As permissões são as do web: `property:manage_approval_settings`, ou master/admin; em Dados do proprietário, `property:view_protected_owner_data`, e só admin/master alteram. Na web o hub fica em Configurações; no app fica no menu da lista porque o drawer é de outro módulo | `pages/property_settings_hub_page.dart`, `property_form_settings_page.dart`, `property_approval_settings_page.dart`, `property_protected_fields_page.dart`, `owner_data_visibility_page.dart`; `services/property_settings_service.dart`; `widgets/property_settings_kit.dart`; `core/constants/app_permissions.dart`; PP |
| imoveis-37: mapa da carteira | ✅ `GET /properties/map` com os filtros da lista e "Pesquisar nesta área" (`n/s/e/w`):<br>• **Navegação:** abas, busca, "Só os meus".<br>• **Pinos:** com preço, coloridos por cidade, valor, operação, tipo ou status (cores e faixas do web), com legenda e agrupamento.<br>• **Avisos e médias:** aviso de corte em 120 e médias da área visível.<br>• **Lista agrupada** como alternativa ao mapa.<br>• **Card do pino:** abrir imóvel, vista de rua, WhatsApp e copiar link.<br>• **Filtros:** botão "Filtros" que abre a mesma gaveta da lista; o mapa aceita todos os filtros da lista (back ajustado).<br>• **Lugares próximos:** mesma fonte do web (Overpass/OpenStreetMap, dois espelhos), raio de 1,8 km, 4 categorias, até 8 por categoria, ligado por padrão. Diferença: abaixo do zoom 11 e sem imóvel selecionado pede para aproximar.<br>• **Tela cheia:** botão maximizar; o voltar do sistema sai dela.<br>Tiles CARTO, os mesmos do detalhe. Gate `property:view` | `pages/properties_map_page.dart`; `services/property_map_service.dart`; `services/nearby_places_service.dart`; PP; `test/.../property_map_service_test.dart`, `nearby_places_service_test.dart` |
| imoveis-38: relatório de captações | ✅ `GET /analytics/captures/report` com período, "todo o cadastro", inativos, equipes, captadores e responsáveis:<br>• **Indicadores:** cartões, Top 5 de captadores e de equipes, lista com busca.<br>• **Exportação:** planilha com 4 abas e 42 colunas, igual ao web.<br>• **Para gestão:** auditoria de trocas de responsável e de downloads de imagens.<br>Gate igual ao web | `pages/captures_report_page.dart`; `services/captures_report_service.dart`; `features/clients/utils/client_spreadsheet.dart` (`buildXlsxSheets`); PP; `test/.../captures_report_service_test.dart` |
| imoveis-39: lembrete de imóveis parados | ✅ `GET /properties/stale-for-user`, uma vez por sessão, como o web. Na web dispara no layout geral; no app, ao abrir a lista de imóveis, porque dashboard/login são de outro módulo. Reaparição igual ao web, gravada no aparelho: "Lembrar depois" 12 h, "Atualizar" 24 h, "Adiar 7 dias" 7 dias. Busca, filtro por urgência e seleção em lote | `widgets/stale_properties_sheet.dart`; `utils/property_list_signals.dart`; PP; `test/.../property_list_signals_test.dart` |
| imoveis-41: geocode / lat-long no wizard | ✅ **não se aplica** (fica igual ao web). O web não manda latitude/longitude no wizard: não há ocorrência em `CreatePropertyPage.tsx` nem em `buildCreatePropertyApiPayload.ts`. O back geocodifica sozinho pelo endereço e depois pelo CEP (`properties.service.ts:3089-3104` na criação, `6244-6266` na edição sem coordenadas). O detalhe tem "Atualizar no mapa" (`geocode-location`) | — |
| imoveis-F3: análise preditiva | ✅ "Análise preditiva" no menu do card, para imóvel Disponível e com o módulo `ai_assistant`. Usa `POST /ai-assistant/predictive/sales` com `analysisType: 'single'`. Mostra dias estimados, probabilidades em 30/60/90 dias, preço sugerido, fatores e recomendações; os erros 400/403/404/429 usam os textos do web | `widgets/predictive_analysis_sheet.dart`; `lib/shared/services/ai_service.dart`; PP |
| imoveis-07 (ressalva) | ✅ A IA não exige mais área total, só tipo e cidade, como o web; área total só vai se for ≥ 1 | cpp; `lib/shared/services/ai_service.dart` |
| imoveis-19 (ressalva) | ✅ O certificado de autorização aparece mesmo com o módulo Documentos desligado, como no web (topo da seção) | DP (seção Documentos) |
| Card: título de fallback da IA | ✅ Porte do `propertyFallbackTitle.ts` do web. Se a IA falha, não responde ou volta sem título, o título é montado com os dados e o aviso usa o texto do web. Também ao finalizar com título vazio e no rascunho | `utils/property_fallback_title.dart`; cpp |
| Card: vídeo (badge + upload) | ✅ Pílula "Vídeo" na miniatura do card com `hasVideo` (extra do card do funil; a lista do web não tem). Upload em imoveis-28 | PP; `property_gallery_manager_page.dart` |
| Card: imóvel excluído pela lista | ✅ `listDeletedOnly` ("Somente excluídos") leva ao detalhe em modo consulta | ps; PP |

### Mudanças no back (`intellisys-CRM-Back`)

| Pendência | O que mudou | Arquivos | Migration / deploy |
|---|---|---|---|
| `isSitePremiumLine` no PATCH | O campo entrou no `UpdatePropertyDto` (aceita boolean e "true"/"false"). A coluna já existia. Tratado como `isFeatured`: com "toda edição passa por aprovação", vira solicitação. Sair do site, vender ou locar zera o campo. Ganhou rótulo e diff de auditoria | `src/properties/dto/update-property.dto.ts`; `src/properties/utils/property-protected-fields.util.ts`; `property-update-diff.util.ts` | só deploy |
| Endereço estruturado do proprietário | `ownerZipCode`, `ownerStreet`, `ownerNumber`, `ownerComplement`, `ownerNeighborhood`, `ownerCity`, `ownerState` no Create e no Update DTO. Normalização: vazio limpa, CEP só dígitos, `00000000` do rascunho vira null, UF em maiúsculas. Resposta em `owner.{zipCode, street, number, complement, neighborhood, city, state}`. Vale a mesma restrição de `ownerName`/`ownerPhone` e a mesma máscara no histórico | `src/entities/property.entity.ts`; `dto/create-property.dto.ts`; `dto/update-property.dto.ts`; `dto/property-response.dto.ts`; `properties.service.ts`; `property-history.service.ts`; novo `src/properties/utils/property-owner-address.util.ts` (+ spec) | **Sim.** 7 colunas nullable (`owner_zip_code` … `owner_state`): migration `src/migrations/20723000000000-AddPropertyOwnerStructuredAddress.ts` e ensure idempotente `scripts/ensure-property-owner-address-columns.js`. **Rodar o ensure antes do deploy**, porque a entidade já mapeia as colunas e, sem elas, toda consulta em `properties` falha. **Não foi rodado em banco nenhum** |
| Filtros da listagem | `minSalePrice`/`maxSalePrice` e `minRentPrice`/`maxRentPrice`: preço nulo ou 0 nunca entra; limite ≤ 0 é ignorado. `suites` e `rooms`: valor exato, como `bedrooms`. `zipCode`: compara só dígitos e aceita CEP parcial. Vale em `GET /properties`, `portfolio-counts`, `map` e `POST export` (`filters`). O `GET /properties/map` passou a usar o mesmo `buildPropertyListFilters` da lista e agora também lê `ownerPhone`, `number`, `propertyUnity`, `tower`, `block`, `lot`, `createdFrom` e `createdTo`, que o web já mandava e eram descartados. Os nomes são os do `PropertyFilters` do web, que já os mandava; o web não precisou de ajuste | novo `src/properties/utils/property-list-range-filters.util.ts` (+ spec); `property-list-query.util.ts` (+ spec); `properties.controller.ts`; `properties.service.ts` | só deploy |

**Observações para o dono do back (não bloqueiam a paridade):**
- **Permissão da galeria:** as rotas de `gallery` declaram `PROPERTY_UPDATE`, mas o controller não tem `PermissionsGuard`, então a permissão não é cobrada.
- **Reclassificação de captadores:** o web manda `captorAssignments` em todo salvamento. Com a aprovação de edição ligada, isso abre pedido de aprovação mesmo sem troca real. O app só manda quando os papéis ou a finalidade mudam.

## Pendências

Nenhuma. As únicas dependências externas são o deploy do back e o ensure das colunas do endereço do proprietário, descritos acima.

Até o deploy:
- o endereço estruturado do proprietário é descartado pelo back;
- a linha premium não grava na edição;
- as faixas de preço, suítes, salas e CEP não filtram.

Abreviações: **cpp** = `lib/features/properties/pages/create_property_page.dart` · **ps** = `lib/shared/services/property_service.dart` · **DP** = `lib/features/properties/pages/property_details_page.dart` · **PP** = `lib/features/properties/pages/properties_page.dart` · **PC** = `intellisys-CRM-Back/src/properties/properties.controller.ts` · **MA** = `intellisys-CRM-Back/src/properties/controllers/property-multi-approval.controller.ts` · web = `intellisys-CRM/src/...` (a auditoria chama de `imobx-front`).

Esforço: P = pequeno (≤ 1 dia) · M = médio · G = grande.

---

## P0 (9): todos feitos

| ID | Lacuna | App | Evidência no app | Web / back | Back? | Esforço |
|---|---|---|---|---|---|---|
| imoveis-01 | 16 tipos; tipo desconhecido não vira 'house' | ✅ **feito** | ps (16 tipos, `typeRaw`); cpp não manda `type` desconhecido intocado | back `entities/property.entity.ts:38-55` | não | — |
| imoveis-02 | 17 status (inclui `pending_publication` e os 9 do funil) | ✅ **feito** | ps (`isRentalFunnel`, `shortLabel`, `statusRaw`) | back `property.entity.ts:57-88` | não | — |
| imoveis-03 | PATCH zera 9 booleanos e preços | ✅ **feito** | Os booleanos só vão na criação ou quando mudam (ficha adicional, 03/10 tarde). Preço vazio vai como 0, igual ao web | — | não | — |
| imoveis-04 | PATCH regrava captadores | ✅ **feito** | A edição só manda captadores/papéis quando mudam (03/10 tarde, `utils/property_captor_slots.dart`) | back `update-property.dto.ts:705` | não | — |
| imoveis-05 | Duplicidade / 409 | ✅ **feito** | ps (`checkDuplicate`, 409); cpp (`duplicateConfirmedByUser`); `widgets/property_duplicate_sheet.dart` | PC:2215, `create-property.dto.ts:223` | não | — |
| imoveis-06 | Sem CEP → 'N/A' | ✅ **feito** | cpp | `create-property.dto.ts:48` | não | — |
| imoveis-07 | Regra de áreas invertida | ✅ **feito** (ressalva da IA fechada em 03/10) | Total opcional; construída obrigatória exceto terreno; teto 99.999.999,99. A IA não exige área total. O parse de área com ponto decimal também foi corrigido | web `CreatePropertyPage.tsx:3767-3790`; back `properties.service.ts:5731-5735` | não | — |
| imoveis-08 | Negociação obriga mínimo | ✅ **feito** | cpp | web `CreatePropertyPage.tsx:3809-3824` | não | — |
| imoveis-F1 | Editar vendido volta para 'Disponível' | ✅ **feito** | cpp (`omitWorkflowFieldsOnEdit`; o app nunca manda status na edição) | web `buildCreatePropertyApiPayload.ts:162-177,203-208` | não | — |

## P1 (19): todos feitos

| ID | Lacuna | App | Evidência (estado da manhã → onde foi fechado) | Web / back | Back? | Esforço |
|---|---|---|---|---|---|---|
| imoveis-09 | Limites próprios do app | ✅ **feito 03/10** | Ver "Execução no app" | web `CreatePropertyPage.tsx:3714-3880` | não | P |
| imoveis-10 | Captadores por papel + responsáveis | ✅ **feito 03/10** | Antes: só o usuário logado, sem UI. Ver "Fechamento" | web `CreatePropertyPage.tsx:3727-3731`; back `create-property.dto.ts:766,797,812` | não | G |
| imoveis-11 | Equipe sempre obrigatória | ✅ **feito 03/10** | Ver "Execução no app" | web `CreatePropertyPage.tsx:3732` | não | P |
| imoveis-12 | Permuta | ✅ **feito 03/10** | Ver "Execução no app" | web `utils/propertyExchange.ts`; back `create-property.dto.ts:407,448` | não | P |
| imoveis-13 | ~30 campos do wizard + endereço do proprietário | ✅ **feito 03/10** | Antes: o payload não tinha os campos, e o endereço do proprietário não estava no DTO. Ver "Fechamento" e "Mudanças no back" | back `create-property.dto.ts:309-1097` | **sim (feito)** | G |
| imoveis-14 | `pendingChangeRequest` / `resubmittedForApproval` | ✅ **feito 03/10** | Ver "Execução no app" | back `property-response.dto.ts:1128`; web `CreatePropertyPage.tsx:4552-4610` | não | P |
| imoveis-15 | Marcar vendido/locado | ✅ **feito 03/10** | Ver "Execução no app" | PC:3436, 3485, 3535 | não | P |
| imoveis-16 | Ativar/desativar (+ parcial por finalidade) | ✅ **feito 03/10** | Ver "Execução no app" | PC:4019, 4066 | não | P |
| imoveis-18 | Seção Proprietário + `canViewOwnerData`/`ownerDataRestricted` | ✅ **feito** | `property_owner_section.dart` (agora com o endereço estruturado) | `property-response.dto.ts:1070,1080` | não | — |
| imoveis-19 | Autorização: certificado, PDF assinado, selo e link no histórico | ✅ **feito** (ressalva fechada em 03/10) | O certificado não some mais quando o módulo Documentos está desligado | PC:483 | não | — |
| imoveis-20 | Card da ficha de venda vinculada | ✅ **feito** | ps; DP | `property-response.dto.ts:1108` | não | — |
| imoveis-21 | Negociação, extraRooms, dados complementares no detalhe | ✅ **feito** | `property_values_section.dart`; `property_additional_info_section.dart` | — | não | — |
| imoveis-22 | Mudar voto (PUT) e ver os votos | ✅ **feito 03/10** | Ver "Execução no app" | MA:296, MA:257 | não | P |
| imoveis-23 | Abas + contagem | ✅ **feito 03/10** | Ver "Execução no app" | PC:2836-2887 | não | M |
| imoveis-24 | "Todos" sem `includeInactive` | ✅ **feito** | PP | web `utils/buildCombinedPropertyFilters.ts:41-60` | não | — |
| imoveis-25 | Filtros e ordenação | ✅ **feito 03/10** | Antes: faltavam ordenação, proprietário, unidade, datas, equipes, excluídos e faixas, e o CEP não ia na query. Ver "Fechamento" | PC:2711-2754; back passou a ler faixas, suítes, salas e CEP | **sim (feito)** | G |
| imoveis-26 | Exportar gera arquivo + dryRun | ✅ **feito 03/10** | Ver "Execução no app" | PC:4237-4294 | não | P/M |
| imoveis-28 | Galeria: reordenar, ocultar do site, vídeo | ✅ **feito 03/10** | Antes: sem reordenar nem upload de vídeo, e `updateImage` usava PATCH. Ver "Fechamento" | back `gallery/gallery.controller.ts:554, 673, 800` | não | M |
| imoveis-F2 | Atalho Publicar/Ocultar do site | ✅ **feito 03/10** | Ver "Execução no app" | web `PropertiesPage.tsx:3276-3279, 3383-3408` | não | P |

## P2 (17): todos feitos

| ID | Lacuna | App | Evidência | Web / back | Back? | Esforço |
|---|---|---|---|---|---|---|
| imoveis-17 | Aba Visualizações | ✅ **feito** | `property_viewers_tab.dart` | PC:3635 | não | — |
| imoveis-27 | Exportar/Importar sem permissão | ✅ **feito 03/10** | Ver "Execução no app" | PC:4238, 4392 | não | P |
| imoveis-29 | owner-check | ✅ **feito 03/10** | Ver "Fechamento" | PC:2230; web `propertyApi.ts:561` | não | P |
| imoveis-30 | Aba Site (linha premium) | ✅ **feito 03/10** | O back aceita `isSitePremiumLine` no PATCH | `update-property.dto.ts` | **sim (feito)** | P |
| imoveis-31 | Revisões + restaurar + effectiveChanges | ✅ **feito** | `property_history_entry_tile.dart` | PC:3859, 3891 | não | — |
| imoveis-32 | Apresentação em PDF | ✅ **feito** | `property_presentation_pdf_sheet.dart` | PC:417 | não | — |
| imoveis-33 | Conversa de aprovação | ✅ **feito 03/10** | Ver "Fechamento" (mark-seen + caixa de conversas) | MA:417, MA:223 | não | M |
| imoveis-34 | Change requests "minhas" + selo "Edição pendente" | ✅ **feito 03/10** | Ver "Fechamento" | `property-change-requests.controller.ts:63-78, 101` | não | P |
| imoveis-35 | lastActivity no card | ✅ **feito 03/10** | Ver "Fechamento" | `property-list-query.util.ts:45,130` | não | P |
| imoveis-36 | Telas de configuração | ✅ **feito 03/10** | Ver "Fechamento" | PC:213-282; `protected-owner-data.controller.ts:39` | não | G |
| imoveis-37 | Mapa da carteira | ✅ **feito 03/10** | Ver "Fechamento" | PC:3012; web `pages/PropertiesMapExplorer.tsx` | não | G |
| imoveis-38 | Relatório de captações | ✅ **feito 03/10** | Ver "Fechamento" | `captures-analytics.controller.ts:157`; web `CapturesReportPage.tsx` | não | M |
| imoveis-39 | Lembrete stale | ✅ **feito 03/10** | Ver "Fechamento" | `properties-stale-for-user.controller.ts:40`; web `StalePropertiesModal.tsx` | não | M |
| imoveis-40 | Desvincular cliente | ✅ **feito** | DP | — | não | — |
| imoveis-41 | Geocode / lat-long | ✅ **não se aplica no wizard** (justificado em "Fechamento"); "Atualizar no mapa" no detalhe já existia | O web não envia lat/long no wizard, e o back geocodifica (`properties.service.ts:3089-3104, 6244-6266`) | PC:3585 | não | — |
| imoveis-F3 | Análise preditiva (IA) | ✅ **feito 03/10** | Ver "Fechamento" | `ai-assistant.controller.ts:133`; web `PropertiesPage.tsx:3438` | não | M |
| imoveis-F4 | Apagar e-mail do proprietário | ✅ **feito 03/10** | Ver "Execução no app" | web `buildCreatePropertyApiPayload.ts:301-307` | não | P |

## Card do funil (pendências citadas)

| Pendência | App | Evidência | Back? |
|---|---|---|---|
| Permuta obrigatória | ✅ **feito 03/10** | = imoveis-12 | não |
| Cômodos/infra extras do catálogo | ✅ **feito 03/10** | cpp `_buildExtraRoomsSection` | não |
| "Alterar status" + 9 status do funil | ✅ **feito 03/10** (detalhe e lista) | `property_status_change_sheet.dart`; PP | não |
| `pendingChangeRequest` no PATCH | ✅ **feito 03/10** | = imoveis-14 | não |
| `canViewOwnerData` / `ownerDataRestricted` | ✅ **feito** | = imoveis-18 | não |
| `publishableImageCount` | ✅ **feito 03/10** | `utils/property_publish_rules.dart` | não |
| Preço "0.00" = não se aplica | ✅ **feito 03/10** | `utils/property_price_display.dart` | não |
| Vídeo na galeria (`mediaType`, `hasVideo`) | ✅ **feito 03/10** | Exibição no detalhe, badge na lista e upload (imoveis-28) | não |
| Apresentação em PDF | ✅ **feito** | = imoveis-32 | não |
| Tela "Vendidos e Locados recentemente" | ✅ **feito 03/10** | `pages/recent_deals_page.dart` | não |
| Imóvel excluído em modo consulta | ✅ **feito 03/10** | "Somente excluídos" (`listDeletedOnly`) leva ao detalhe em modo consulta | não |
| Título por IA não trava o cadastro | ✅ **feito 03/10** | `utils/property_fallback_title.dart`; a IA não exige área total | não |
| Teto de área | ✅ **não se aplica** | Não existe teto de 400 m² no web nem no back. O "400" é o HTTP 400 acima de 99.999.999,99 (`properties.service.ts:5561,5732`), e o app usa o mesmo teto | não |
| Step MCMV oculto na criação | ✅ **feito** | O wizard tem 7 etapas, sem MCMV | não |
| Placeholder sem foto | ✅ **feito** | PP; DP | não |
