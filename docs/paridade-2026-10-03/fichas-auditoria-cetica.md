# Auditoria cética: Ficha de Venda e Ficha de Proposta, web × app (03/10/2026)

Esta auditoria foi adversarial e somente leitura. O objetivo foi provar que a paridade **não** está em 100%. Nenhum código foi alterado e nada foi commitado.

## Execução (03/10/2026, até 11h40) — status

A coluna "Status" de cada linha agora diz como ela ficou.
- **P1 (10/10) ✅**, incluindo a P-C2 corrigida no app e no web.
- **P2:**
  - nenhum pendente: V-L4 e V-L9 ✅ em 2026-10-03 (tarde);
  - 4 diferenças conscientes com motivo: V-A5, P-L2, P-L4 e P-C9 (só o armazenamento);
  - V-K1..V-K5 mantidas;
  - todo o resto ✅.
- **Web:**
  - P-C2/P-C4: `CreatePurchaseProposalPage.tsx` + `utils/purchaseProposalEdicao.ts` (com spec);
  - V-C5: `CreateSaleFormPage.tsx`;
  - P-K1 e P-C8: `ProposalSignaturesModalPrivate.tsx` e o rótulo "Tabelião".
- **Back:** a ficha de venda cancelada ou excluída não gera mais envio de assinatura (`sale-form-signature.service.ts` + `sale-form-signature.cancelada.spec.ts`). As regras RN-FICHA-ASSINATURA-CANCELADA-01 e RN-PROPOSTA-EDICAO-01 estão no obsidian.
- **Verificação:**
  - `flutter analyze` sem erros; os avisos restantes já existiam e ficam fora das fichas;
  - `flutter test`: 495 testes verdes;
  - jest do back: 8/8 nos specs tocados;
  - vitest da web: 38/38 nos specs tocados.
- Nada foi testado em aparelho e nada foi commitado.

Base: o código atual de três repositórios:
- app: `dreamkeysapp/lib`;
- web: `intellisys-CRM/src`;
- back: `intellisys-CRM-Back/src`.

O doc `fichas-venda-proposta.md` serviu só para saber o que já foi declarado como feito e quais diferenças são conscientes. Nada foi testado em aparelho.

Caminhos curtos usados nas tabelas:
- **web**: tudo relativo a `intellisys-CRM/src` (`pages/`, `components/`, `routes/`, `utils/`, `hooks/`);
- **app**: tudo relativo a `dreamkeysapp/lib` (`features/…`, `shared/…`, `core/…`). Quando o caminho aparece sem pasta (ex.: `sale_form_signatures_sheet.dart`), ele está em `features/sale_forms/widgets/` ou em `features/proposals/widgets/`, conforme a tela;
- **back**: tudo relativo a `intellisys-CRM-Back/src`.

Coluna "Consciente":
- **sim (R10/R11/R12/R13)**: são as 4 diferenças conscientes ("Não se aplica") do doc.
- **sim (R9/P10/R6)**: são outras diferenças que o doc assumiu de forma explícita.
- **não**: a diferença não foi declarada.
- **errado no doc**: o doc afirma "sem diferença", mas há diferença.

## Veredito

**Não está 100%.** A estrutura principal está pareada:
- payload × DTO, nos dois sentidos;
- validações por aba e por etapa;
- regras do menu;
- filtros e `/stats`;
- corpo do envio de assinaturas;
- upload de anexo com `contentType`.

Mesmo assim, ficam **10 P1** (2 delas são suspeitas) e **58 P2**. Não há nenhuma P0: nada que perca dado ou quebre o fluxo principal de forma garantida. Das linhas abaixo, só 4 estão entre as diferenças conscientes do doc. Além disso, um item que o doc declara "sem diferença" está errado (reenvio por e-mail na proposta, P-L2).

## P1

| # | Diferença | Tela | Sev. | Evidência web | Evidência app | Status | Consciente |
|---|---|---|---|---|---|---|---|
| V-A1 | No detalhe, o card "Assinaturas" abre a folha em qualquer status, inclusive em ficha **cancelada**. Sem assinatura assinada, a aba "Novo envio" aparece e "Gerar links" funciona, porque o back não barra ficha cancelada (back `sale-form-signature.service.ts:665-694` só recusa "Ficha já assinada"). No web o modal só abre com update e com a ficha não finalizada, não cancelada e não excluída | Venda / Detalhe → Assinaturas | P1 | `pages/SaleFormsPage.tsx:2505,2555` | `features/sale_forms/pages/sale_form_detail_page.dart:639-646`; `sale_form_signatures_sheet.dart:1161-1172` | ✅ app: `saleFormSignaturesBlockReason` (`sale_form_row_rules.dart`) bloqueia card do detalhe e "Novo envio" (excluída/cancelada/finalizada/sem update); **back**: `sale-form-signature.service.ts` recusa criar envio em ficha cancelada/excluída (400, antes de qualquer efeito), teste `sale-form-signature.cancelada.spec.ts` (5) | não |
| V-C1 | Na edição, todo corretor, captador, SDR ou "outros" aparece como "Participante". O `GET :id` não traz `nome` em `corretores[]` (back `sale-forms.service.ts:623-666` só preenche o nome no export). O web resolve o nome pela lista de membros | Venda / Edição, Comissões | P1 | `pages/CreateSaleFormPage.tsx:3311-3314,4161-4169` | `features/sale_forms/pages/create_sale_form_page.dart:976` | ✅ nome via vinculados + `GET /users/company-members` (`services/sale_form_members_service.dart`) | não |
| V-C2 | Gerência legada sem `gestorId` (só com `nome`): o web casa o id pelo nome e, mesmo sem casar, salva a linha. O app deixa `userId=null` e barra o salvar com "Selecione o usuário de cada participante da comissão." | Venda / Edição, Comissões | P1 | `CreateSaleFormPage.tsx:3969-3976,4071-4080` | `create_sale_form_page.dart:999,1755-1758` | ✅ casa o id pelo nome; sem casar, salva a linha só com `nome` como o web (teste em `sale_form_create_parity_test.dart`) | não |
| V-C3 | Timeout de criar/editar: 120 s no web, 30 s no app (padrão do `ApiService`). Se o back passar de 30 s, o app mostra erro com a ficha talvez já criada e com o rascunho mantido. O usuário pode reenviar e duplicar a ficha | Venda / Salvar | P1 | `services/saleFormsApi.ts:14,739-751` | `shared/services/api_service.dart:265-271`; `core/constants/api_constants.dart:755` | ✅ criar/editar com 120 s (`kSaleFormSaveTimeout`; `timeout` opcional em `api_service` post/patch, padrão de 30 s intocado) | não |
| V-L1 | A notificação "proposta finalizada" (`actionUrl /fichas-venda/nova?propostaId=X`) abre no web a Nova ficha já preenchida com a proposta. No app ela cai na lista. O `prefillProposalId` existe na página, mas ninguém o passa (é código morto) | Venda / Deep link → Criação | P1 | `utils/notificationNavigation.rotas.spec.ts:118`; `CreateSaleFormPage.tsx:2526-2534,3108-3125` | `shared/utils/app_deep_link.dart:317-338` (comentário em :320); `create_sale_form_page.dart:440,446,716`; quem abre a página não passa o parâmetro: `sale_forms_page.dart:230`, `sale_form_row_actions.dart:96` | ✅ `sale_form_new_from_proposal.dart` (`abrirNovaFichaDaProposta`): permissão, rascunho da proposta, modal de tipo, formulário preenchido, assinaturas após criar; deep link/push `/fichas-venda/nova?propostaId=` → rota `/sale-forms/new?proposalId=` | não |
| D-1 | O dashboard de venda não tem filtros de corretor, equipe, unidade nem status. O web tem a `OverviewFiltersBar` e manda `userIds`/`teamIds`/`unitIds`/`status`. O app só manda o período, e o service nem aceita esses ids | Venda / Dashboard | P1 | `pages/SaleFormsDashboardPage.tsx:484-496,814-826` | `features/sale_forms/pages/sale_forms_dashboard_page.dart:141-145`; `shared/services/sale_form_overview_service.dart:283-298` | ✅ folha de filtros (corretor/equipe/unidade/status) com escopo do papel; manda `userIds/teamIds/unitIds/status` (`sale_form_overview_service.dart`, `sale_forms_overview_filters_sheet.dart`) | não |
| D-2 | O dashboard de venda não leva às fichas. No web, KPI, fatia do donut, linha do ranking e "Compartilhadas" abrem a lista filtrada (`FichasListDrawer`). No app nada disso é clicável | Venda / Dashboard | P1 | `SaleFormsDashboardPage.tsx:583-746,860-862,874,940,979,1033-1041` | `sale_forms_dashboard_page.dart:343,912` (só estes `onTap`) | ✅ KPIs, fatias dos donuts, rankings e Compartilhadas abrem `sale_forms_drill_down_sheet.dart` (lista filtrada → detalhe) | não |
| P-L1 | Botão "Continuar" da linha (etapa máxima ≥ 2 e etapa 2 ainda não enviada, ou etapa 3): o web abre a **edição** (`/fichas-proposta/:id/editar`). O app abre a folha de **assinaturas** da etapa atual | Proposta / Lista | P1 | `pages/PurchaseProposalsPage.tsx:2889-2899,3102-3112` | `features/proposals/widgets/proposal_card.dart:116-118`; `features/proposals/pages/proposals_page.dart:578` | ✅ "Continuar" abre a edição (`proposalAtalhoDaLinha`, `proposal_edit_rules.dart`) | não |
| P-C1 | A edição por deep link (`/fichas-proposta/:id/editar`, `highlightProposal`) não exige `proposal:update` (nem o módulo). O web protege essa rota com `PermissionRoute 'proposal:update'`. No app, quem não tem a permissão abre o formulário editável e só leva 403 ao salvar | Proposta / Edição | P1 | `routes/domains/fichas.routes.tsx:240-247,257-264` | `core/routes/app_routes.dart:844-855`; `app_deep_link.dart:302,310,314,431` | ✅ guarda `proposal:update` (+ módulo) dentro de `CreateProposalPage` e na rota `/proposals/:id/edit` (`app_routes.dart`) | não |
| P-C2 | O back recusa `PATCH` em proposta finalizada (back `purchase-proposals.service.ts:837-839`). O app avisa "ao salvar reinicia as assinaturas", faz o `PATCH` primeiro, leva o 400 e nunca chega a `reiniciar-fluxo-assinaturas`. **O web faz o mesmo**: aqui não há diferença app × web, e sim os dois clientes contradizendo o back. Chega-se lá pelo deep link | Proposta / Edição | P1 | `pages/CreatePurchaseProposalPage.tsx:1286,1415-1518,2338-2351` | `features/proposals/pages/create_proposal_page.dart:568,1051-1097,1651` | ✅ **app e web**: finalizada/cancelada/excluída abre só leitura (app) / toast + volta à lista (web); saiu a promessa de reiniciar assinaturas em finalizada. Regra do back: PATCH recusa (`purchase-proposals.service.ts:833-842`), registrada como RN-PROPOSTA-EDICAO-01 no obsidian; web `utils/purchaseProposalEdicao.ts` + spec | não (o doc, no item 4, dá o fluxo como feito) |

## P2: Ficha de Venda

| # | Diferença | Tela | Sev. | Evidência web | Evidência app | Status | Consciente |
|---|---|---|---|---|---|---|---|
| V-L2 | A linha não mostra Vendedor, Unidade nem Equipe (o card mobile do web mostra Vendedor e Unidade) | Lista | P2 | `SaleFormsPage.tsx:3756-3763,4071-4082` | `features/sale_forms/widgets/sale_form_card.dart:60-77` | ✅ linha com Vendedor, Unidade e Equipe (`sale_form_card.dart`) | não |
| V-L3 | Imóvel na linha: o web mostra o endereço completo ou, em Lançamento/MCMV, incorporadora · empreendimento · unidade. O app mostra "Cód. + bairro" e, em Lançamento/MCMV, nada | Lista | P2 | `utils/saleFormsPropertyLine.ts:22-57,72-87`; `SaleFormsPage.tsx:3784,4088-4089` | `sale_form_card.dart:64-68` | ✅ endereço completo ou incorporadora · empreendimento · unidade | não |
| V-L4 | Falta o modo "Relatório fichas" na lista: data da compra, gestor, corretor externo, comissão e "Raio-X completo" direto da linha. No app o Raio-X só abre pelo detalhe | Lista | P2 | `SaleFormsPage.tsx:3550-3571,3638-3731,3842-3951` | `sale_form_card.dart`; `sale_form_detail_page.dart:656-677` | ✅ **feito 03/10 (tarde)**: abas "Lista operacional" × "Relatório fichas" na lista; a linha do relatório traz Nº, status, data da compra, endereço, valor da venda, comissão total, gestor, rastreio e o botão "Raio-X completo" (`widgets/sale_form_report_row.dart`, `pages/sale_forms_page.dart`) | não |
| V-L5 | Exportar XLSX: o web abre um modal para ajustar o recorte e só manda `userIds` com `view_all`. O app exporta o recorte da lista sem editar e manda `userIds` sempre | Lista / Exportação | P2 | `components/modals/ExportSaleFormsRelatorioModal.tsx:249-305` (`:283-287`) | `features/sale_forms/pages/sale_forms_page.dart:304-352` | ✅ folha de recorte antes de exportar (modo exportação de `sale_forms_filters_sheet.dart`); `userIds` só com `view_all`; recorte vazio avisa | não |
| V-L6 | O filtro do web já abre com "Data da venda" = hoje (de/até). O app abre vazio. Aqui o app está mais certo | Filtros | P2 | `components/sale-forms/SaleFormsFiltersDrawer.tsx:131-144,160-161` | `features/sale_forms/widgets/sale_forms_filters_sheet.dart:116-117` | ✅ filtro abre com Data da venda = hoje, como o web (a exportação não usa esse padrão) | não |
| V-L7 | Rascunho: o web mostra na lista "Retomar rascunho (salvo …)" e um X para descartar. O app só pergunta ao tocar "Nova ficha" | Lista | P2 | `SaleFormsPage.tsx:3427-3466` | `sale_forms_page.dart:208-290` | ✅ "Retomar rascunho · salvo …" com X na lista | não |
| V-L8 | "Nova ficha" sem `sale_form:create`: o web esconde o botão, o app mostra com cadeado | Lista | P2 | `SaleFormsPage.tsx:3467` | `sale_forms_page.dart:454,700-756` | ✅ "Nova ficha" some sem `sale_form:create` | não |
| V-L9 | Paginação: o web tem páginas numeradas e escolha de 10/20/30/50 por página, salva. O app usa rolagem infinita fixa em 20 | Lista | P2 | `SaleFormsPage.tsx:2652-2693,4152-4210` | `sale_forms_page.dart:59,100-106` | ✅ seletor "Por página" 10/20/30/50 (padrão 20) no rodapé, salvo por empresa com os filtros e usado como `limit` (back aceita até 100, `@Max(100)`); rolagem infinita mantida de N em N; rodapé "Página X de Y · N fichas" (`total` do back). Arquivos: `sale_forms_filters_storage.dart` (`sanitizeSaleFormsPageSize`), `pages/sale_forms_page.dart` (`_RodapePaginacao`, `_mudarItensPorPagina`); teste `test/features/sale_forms/sale_forms_page_size_test.dart`. Páginas numeradas viram rolagem infinita (mesmo conjunto e ordem) | não |
| V-L10 | Rótulo do distrato: web "Em distrato — aguardando anexo no Financeiro"; app "Em distrato" | Lista | P2 | `SaleFormsPage.tsx:1762-1764` | `shared/services/sale_forms_service.dart:154-158` | ✅ "Em distrato — aguardando anexo no Financeiro" (pílula usa o curto, como a pílula do web) | não |
| V-L11 | O detalhe `/sale-forms/:id`, aberto por deep link, não tem `PermissionRoute sale_form:view` (o web tem). Sem a permissão, a tela abre e recebe 403 | Deep link → Detalhe | P2 | `fichas.routes.tsx:223-229` | `app_routes.dart:831-841` | ✅ rota `/sale-forms/:id` com módulo + `sale_form:view` (`app_routes.dart`) | não |
| V-L12 | Deep links: `/fichas/dashboard`, `/fichas-venda/dashboard` e `/fichas-proposta/dashboard` vão para a lista. `/fichas-venda/:id/editar` cai na lista (o web abre a edição). `/fichas-proposta/nova` vai para a lista | Deep links | P2 | `fichas.routes.tsx:38-81,205-220,239-254` | `app_deep_link.dart:305-338` | ✅ dashboards (consolidado → venda, como o web), `/fichas-venda/:id/editar` → edição, `/fichas-proposta/nova` → `abrirNovaProposta` (`app_deep_link.dart`, 21 testes) | não |
| V-A2 | "PDF original" não aparece na aba de envio, só na aba Status: não dá para baixar o PDF antes de gerar os links | Assinaturas | P2 | `components/modals/SaleFormSignatureModalPrivate.tsx:1342-1353` | `sale_form_signatures_sheet.dart:815-820` (`_buildSendTab` 1158-1437 não tem) | ✅ "PDF original" também na aba de envio | não |
| V-A3 | A caixa de status do WhatsApp não tem os botões de ação ("Ir para Signatários obrigatórios", "configurações do WhatsApp", "Trocar número"). O app escreve "(sistema web)" | Assinaturas | P2 | `SaleFormSignatureModalPrivate.tsx:687-732,988-1000` | `sale_form_signatures_sheet.dart:998-1080` | ✅ botões do web; as telas de configuração só existem no web e abrem no navegador | não |
| V-A4 | Assinatura cancelada ou expirada: o web mantém copiar, e-mail e WhatsApp. O app esconde todas as ações | Assinaturas | P2 | `SaleFormSignatureModalPrivate.tsx:1027` | `sale_form_signatures_sheet.dart:1891-1895` | ✅ copiar/e-mail/WhatsApp também em cancelada/expirada (o back não recusa o link) | não |
| V-A5 | Botão "Assinar" na linha do próprio usuário: só existe no app | Assinaturas | P2 | ausente em `SaleFormSignatureModalPrivate.tsx` | `sale_form_signatures_sheet.dart:510-525,925` | diferença consciente: "Assinar" só abre o link que o back devolve para o próprio signatário | não |
| V-A6 | Trava: o web sempre oferece "Ir para a ficha" (vai à edição). O app só oferece quando não há link e abre o detalhe | Trava de assinatura | P2 | `components/modals/SaleFormSignatureLockModal.tsx:146-149,207-214` | `sale_form_signature_lock_sheet.dart:293-300,471-508` | ✅ "Ir para a ficha" sempre; com update abre a edição (que cai em só leitura quando bloqueada, como o web) | não |
| V-A7 | Depois da recusa, o web consulta a trava de novo (`checkStatus`). O app só tira a ficha da lista local | Trava de assinatura | P2 | `routes/SignatureLockGate.tsx:205-207` | `sale_form_signature_lock_sheet.dart:273-287` | ✅ reconsulta a trava após a recusa (falha de rede mantém a lista local) | não |
| V-A8 | Raio-X: o web mostra "Informações extras" sempre e "Ver registro técnico (JSON)". O app só mostra os metadados quando não há mudança e não tem o JSON | Auditoria | P2 | `SaleFormsPage.tsx:4439-4532` | `features/sale_forms/pages/sale_form_audit_page.dart:257-267` | ✅ "Informações extras" sempre que há metadados + "Ver registro técnico (JSON)" | não |
| V-A9 | Raio-X: o web mostra o e-mail de quem alterou e frases próprias para "sem mudança" (`linked_users_add`). O app mostra só o nome | Auditoria | P2 | `SaleFormsPage.tsx:4432-4436,4477-4483` | `sale_form_audit_page.dart:253-256` | ✅ e-mail de quem alterou e frases de "sem mudança" do web | não |
| V-A10 | O detalhe não mostra "Compartilhar com outras unidades" (`sharedUnitIds`) | Detalhe | P2 | `CreateSaleFormPage.tsx:3499-3507,4960-4994` | `sale_form_detail_page.dart:320-334` | ✅ detalhe mostra "Compartilhar com outras unidades" | não |
| V-A11 | Anexo pendente: web "Pendente"; app "Aguardando aprovação" | Anexos | P2 | `components/modals/FichaVendaAnexosModalPrivate.tsx:327-331` | `sale_forms_service.dart:629-637` | ✅ "Pendente" | não |
| V-C4 | `captadores[]`/`captador` aninhados no corretor: o web preserva no salvar e soma na trava. O app não lê, não reenvia e não soma (DTO `sale-form-auth.dto.ts:817-822`) | Criação/Edição, Comissões | P2 | `CreateSaleFormPage.tsx:3963-3967`; `utils/saleFormCommissionRules.ts:59` | `create_sale_form_page.dart:971-989,1780-1801,1960-1977` | ✅ lê, reenvia e soma `captadores[]` na trava; consciente: o app preserva `captador` (singular) que o web descarta (DTO aceita, evita perda) | não |
| V-C5 | `generalGroup=false`: o web manda `undefined` (desmarcar na edição não grava); o app grava `false`. O dado fica diferente; o bug é do web | Geral | P2 | `CreateSaleFormPage.tsx:3823` | `create_sale_form_page.dart:1826` | ✅ **corrigido no web** (`CreateSaleFormPage.tsx`: `generalGroup === true`); DTO `@IsBoolean` grava false | não |
| V-C6 | Erros 400 do back: o web marca o campo (`parseApiValidationErrors`); o app só mostra um toast | Salvar | P2 | `CreateSaleFormPage.tsx:4038-4045` | `create_sale_form_page.dart:2042-2049` | ✅ erros 400 marcam os campos e abrem a etapa do 1º erro | não |
| V-C7 | RG: o web aceita só dígitos (`00.000.000-0`, máx. 12). O app aceita texto livre | Pessoas | P2 | `CreateSaleFormPage.tsx:3574,5164`; `utils/masks.ts:127-134` | `create_sale_form_page.dart:2860` | ✅ RG com a máscara do web | não |
| V-C8 | "Unidade responsável": o app oferece "Não se aplica" e cai para texto livre sem unidades (grava `saleUnit` sem `unitId`). O web não oferece nenhum dos dois | Geral | P2 | `CreateSaleFormPage.tsx:2918-2938,4926-4944` | `create_sale_form_page.dart:2715-2731` | ✅ só a lista de unidades; valor antigo fora da lista fica como opção "(indisponível)" | não |
| V-C9 | Sugestões de profissão (`PROFISSOES_COMUNS`) só no web | Pessoas | P2 | `CreateSaleFormPage.tsx:2240-2250,5188,6684-6688` | `create_sale_form_page.dart:2867` | ✅ sugestões de profissão (lista do web) | não |
| V-C10 | Limites de tamanho (RG, número e bairro 50; CPF/CNPJ 18; celular 16; CEP 9): o web limita, o app não | Pessoas/Imóvel | P2 | `CreateSaleFormPage.tsx:5152,5164,5210,5222,5246` | `create_sale_form_page.dart:2855-2906` | ✅ limites iguais ao web (o "bairro 50" não existe no web) | não |
| V-C11 | Mensagens diferentes: "Unidade de venda" × "Unidade responsável"; "Telefone inválido (mín. 10 dígitos)" × "Celular inválido (DDD + número)"; texto do nome do cônjuge | Validação | P2 | `CreateSaleFormPage.tsx:1707,1736,1757` | `features/sale_forms/sale_form_rules.dart:307,326,456` | ✅ mensagens do web; consciente: descrição do pagamento cita "Não se aplica", nome do botão no app | não |
| D-3 | Período padrão do dashboard: mês corrente no web, últimos 30 dias no app. Os presets também diferem | Dashboard | P2 | `SaleFormsDashboardPage.tsx:274-287` | `sale_forms_dashboard_page.dart:25,65,90-133` | ✅ mês corrente + presets do web | não |
| D-4 | Os filtros do dashboard não ficam guardados (o web guarda em `dashboard:sale-forms:overview:v1`) | Dashboard | P2 | `SaleFormsDashboardPage.tsx:243,299-318,520-527` | `sale_forms_dashboard_page.dart:57-74` | ✅ guardado no aparelho com o JSON do web (chave por empresa/usuário) | não |
| D-5 | O gráfico de evolução só mostra VGV (o web mostra VGV, VGC e finalizadas) | Dashboard | P2 | `SaleFormsDashboardPage.tsx:748-757,919` | `sale_forms_dashboard_page.dart:285-292` | ✅ VGV, VGC e finalizadas | não |
| D-6 | Falta o donut "VGV por unidade"; o card de compartilhadas some quando o total é 0 | Dashboard | P2 | `SaleFormsDashboardPage.tsx:966-1016` | `sale_forms_dashboard_page.dart:295-298` | ✅ donut "VGV por unidade"; Compartilhadas sempre (com 0) dentro da seção por unidade, como o web | não |
| M-1 | Menu: "Fichas de venda" e "Assinaturas pendentes" aparecem com só `view_team`/`view_all` (o web exige `sale_form:view`). Quem cai aí vê "sem acesso" | Menu | P2 | `components/layout/Drawer.tsx:522-538`; `fichas.routes.tsx:107,124` | `shared/widgets/app_drawer.dart:1030-1034,1409`; `core/constants/app_permissions.dart:116-119` | ✅ módulo + `sale_form:view` + uma ação (`fichas_menu_rules.dart`, teste) | não (o R3 reconhece mas não resolve) |
| M-3 | Os dashboards não têm item próprio no menu (no web: "Dash Fichas Venda/Proposta"). Quem tem a permissão do dashboard mas não tem `view` da lista não chega a eles | Menu | P2 | `Drawer.tsx:337-354` | `sale_forms_page.dart:425-431`; `proposals_page.dart:445-450` | ✅ itens "Dash Fichas Venda/Proposta" no menu | não |
| M-4 | As rotas nomeadas dos dashboards não têm guarda (o web usa `ModuleRoute` + permissão com `noRoleBypass`). Hoje só se entra por ícone já filtrado | Rotas | P2 | `fichas.routes.tsx:43-81` | `app_routes.dart:821-822,846-847` | ✅ rotas dos dashboards com módulo + `*:view_dashboard` | não |
| V-K1 | "Cancelar ficha" só existe no app | Menu | P2 | ausente em `SaleFormsPage.tsx:2467-2612` | `features/sale_forms/widgets/sale_form_row_rules.dart:103-104`; `sale_form_actions_sheet.dart:150-156` | confirmada (mantida) | **sim (R11)** |
| V-K2 | "Cancelar todas" exige mais no app (update, ficha não cancelada, assinatura ativa) | Assinaturas | P2 | `SaleFormSignatureModalPrivate.tsx:921`; `SaleFormsPage.tsx:4269-4271` | `sale_form_signatures_sheet.dart:295-307`; `sale_form_row_actions.dart:62` | confirmada (mantida) | **sim (R10)** |
| V-K3 | Aprovar/rejeitar anexo liberado também para `master` | Anexos | P2 | `FichaVendaAnexosModalPrivate.tsx:250` | `sale_form_anexos_sheet.dart:65-68` | confirmada (mantida) | **sim (R12)** |
| V-K4 | Trava de 120 parcelas e vendedor/imóvel omitidos em Lançamento/MCMV | Criação | P2 | conforme o doc | conforme o doc | confirmada (mantida) | **sim (R13)** |
| V-K5 | Reenvio individual por WhatsApp só no app | Assinaturas | P2 | — | `sale_form_signatures_sheet.dart:933-934` | confirmada (mantida; individual só na pendente) | sim (R9) |

## P2: Ficha de Proposta

| # | Diferença | Tela | Sev. | Evidência web | Evidência app | Status | Consciente |
|---|---|---|---|---|---|---|---|
| P-L2 | Reenvio de e-mail por assinatura só existe no app; o modal do web só tem "Copiar/Gerar link" e "WhatsApp" | Assinaturas | P2 | `components/modals/ProposalSignaturesModalPrivate.tsx:815-848` | `features/proposals/widgets/proposal_signatures_sheet.dart:560-567,1086-1089` | diferença consciente: o back tem `POST :id/assinaturas/:signatureId/reenviar-email` (`purchase-proposals.controller.ts:611-634`); mantido | **errado no doc** (dado como "sem diferença") |
| P-L3 | Depois de "Enviar por e-mail", o web fecha o modal e recarrega a lista; o app mantém a folha aberta | Assinaturas | P2 | `ProposalSignaturesModalPrivate.tsx:341-344`; `PurchaseProposalsPage.tsx:3285-3289` | `proposal_signatures_sheet.dart:473-479` | ✅ fecha a folha e recarrega a lista | não |
| P-L4 | Botão "Assinar" (link do próprio signatário) só existe no app | Assinaturas | P2 | ausente em `ProposalSignaturesModalPrivate.tsx:815-848` | `proposal_signatures_sheet.dart:542-558,1875` | diferença consciente: só abre o link que o back devolve (`POST :id/assinaturas/:signatureId/link`) | não |
| P-L5 | Aprovar/rejeitar anexo: no web, só no modal de Anexos (que abre só com etapa disponível). No app, na aba Histórico, sempre acessível | Anexos | P2 | `ProposalSignaturesModalPrivate.tsx:429,734-744`; `components/modals/PropostaAnexosModalPrivate.tsx:647` | `proposal_signatures_sheet.dart:1280-1284` | ✅ só gestor, anexo pendente e etapa disponível (`proposalPodeDecidirAnexo`) | não |
| P-L6 | Busca: o web busca ao digitar (400 ms); o app só busca ao confirmar | Lista | P2 | `PurchaseProposalsPage.tsx:2287-2295` | `proposals_page.dart:483` | ✅ busca ao digitar (400 ms) | não |
| P-L7 | O topo da lista não tem: escopo ("vendo todas / as suas"), "N unidades de venda", aviso de rascunho em aberto, barra de composição da carteira | Lista | P2 | `PurchaseProposalsPage.tsx:2566-2636` | `proposals_page.dart:597-700` | ✅ escopo, N unidades, rascunho em aberto e barra de composição (`proposal_list_header.dart`) | não |
| P-L8 | Sem permissão, o web esconde "Enviar para assinatura", "Editar" e "Nova Proposta"; o app mostra com cadeado | Lista / Ações | P2 | `PurchaseProposalsPage.tsx:1954,1969,2642,2803` | `features/proposals/widgets/proposal_actions_sheet.dart:75-88`; `proposal_row_actions.dart:67-70`; `proposals_page.dart:473` | ✅ esconde sem permissão | não |
| P-L9 | O atalho de assinatura da linha força a etapa no web (`etapa: 1`/`2`); no app usa `p.etapa` | Lista → Assinaturas | P2 | `PurchaseProposalsPage.tsx:2869,2883,3082,3096` | `proposals_page.dart:351,578` | ✅ força etapa 1/2 como o web | não |
| P-C3 | Sem "Baixar PDF (Etapa N)" das 3 etapas e sem "Assinaturas (Comprador/Proprietário)" dentro do formulário de edição. A etapa 3 e as etapas travadas não têm PDF no app | Edição | P2 | `CreatePurchaseProposalPage.tsx:2376-2480` | `create_proposal_page.dart:1232-1233,1561`; `proposal_signatures_sheet.dart:487-496`; `proposal_row_actions.dart:73` | ✅ "Assinaturas" e "Baixar PDF (Etapa 1/2/3)" na edição | não |
| P-C4 | Proposta excluída abre editável pelo deep link e o back recusa (back `purchase-proposals.service.ts:833-835`). Igual ao web, mas contradiz o back | Edição | P2 | `CreatePurchaseProposalPage.tsx:1173-1177` | `create_proposal_page.dart:538-542` | ✅ excluída: só leitura no app e volta à lista no web | não |
| P-C5 | CEP automático: o app não refaz a busca do mesmo CEP depois de apagar/redigitar ou depois de um erro (`_lastAutoCep` nunca é zerado). A mensagem de erro também difere | Proponente/Imóvel/Proprietário | P2 | `hooks/useCepAutofill.ts:54-60,66-69` | `create_proposal_page.dart:1261-1263,2126-2132` | ✅ refaz o CEP; "Erro ao buscar CEP" | não |
| P-C6 | Aviso de validação: web "Preencha os campos obrigatórios antes de continuar."; app "Revise os campos marcados em vermelho…" | Todas as etapas | P2 | `CreatePurchaseProposalPage.tsx:1564` | `create_proposal_page.dart:1001-1002` | ✅ texto do web | não |
| P-C7 | Asterisco de "Equipe": no web aparece sempre; no app só na criação | Dados da proposta | P2 | `CreatePurchaseProposalPage.tsx:1341,1935` | `create_proposal_page.dart:2202` | ✅ asterisco sempre | não |
| P-C8 | Rótulos diferentes com o mesmo valor gravado: regimes de bens, "Notário / Tabelião", aba "Dados da Proposta" × "Proposta" | Várias | P2 | `CreatePurchaseProposalPage.tsx:901,2079-2082,2250` | `features/proposals/utils/proposal_form_rules.dart:271-276`; `create_proposal_page.dart:49,2370` | ✅ rótulos do web (e o web corrigido para "Tabelião") | não |
| P-C9 | Rascunho: o web grava a cada 700 ms e restaura ao recarregar; o app grava a cada 2 s e só restaura por "Retomar". Os rascunhos ficam em lugares separados (um não aparece no outro) | Criação | P2 | `CreatePurchaseProposalPage.tsx:968-993,1025` | `create_proposal_page.dart:246-249`; `features/proposals/utils/proposal_draft.dart` | ✅ autosave 700 ms; consciente: armazenamentos separados (localStorage × aparelho) e sem F5 no app | parcial (o doc cita 2 s) |
| M-2 | Menu: "Fichas de proposta" aparece com só `proposal:view_team`/`view_all` (o web exige `proposal:view`); a tela mostra "bloqueado" | Menu | P2 | `Drawer.tsx:540-547`; `fichas.routes.tsx:141` | `app_drawer.dart:1025-1029`; `proposals_page.dart:404-413` | ✅ módulo + `proposal:view` + uma ação | não |
| P-K1 | Assinatura cancelada aparece como "Cancelado" (o web mostra "Pendente") | Assinaturas | P2 | conforme o doc | conforme o doc | ✅ web alinhada: assinatura cancelada agora "Cancelado" também no web | sim (P10) |

## Contagem

- **P0: 0**
- **P1: 10.** São 8 confirmadas e 2 suspeitas: V-C3 (timeout) e, em parte, V-C2, cuja frequência nas fichas não foi medida. P-C2 não é diferença app × web: os dois clientes contradizem o back.
- **P2: 58.**
  - Venda, incluindo dashboard e menu: 41, das quais 4 conscientes (R10, R11, R12, R13) e 1 também assumida (R9).
  - Proposta: 17, das quais 1 consciente (P10).
  - **52 P2 não estão declaradas.** Uma delas contradiz o doc (P-L2).

## Conferido sem diferença (não entra na contagem)

**Ficha de Venda:**
- payload de criação/edição × `sale-form-auth.dto.ts`: `propertyId`, `saleUnitId`/`unitId`, confissão, financiamento 100%, parcelamento, travas de comissão;
- validação por aba;
- parâmetros da lista e `/stats`;
- regras do menu;
- modos de PDF;
- distrato, transferir, trocar equipe;
- corpo do envio de assinaturas e dos signatários extras;
- upload de anexo (`contentType`, 15 MB, tipos);
- recusa da trava (mínimo de 10 caracteres);
- tela de assinaturas pendentes.

**Ficha de Proposta:**
- payload × `CreateProposalAuthDto`;
- máscaras e validações das etapas 1 e 2;
- regra de reinício das assinaturas;
- etapa 3 (até 10 usuários);
- equipe com `useInSaleForms`;
- 409 com nova tentativa;
- filtros e os 7 `sortBy`;
- cancelar/excluir com motivo;
- `vincular-ficha-venda`;
- `/stats`;
- histórico;
- deep link `highlightProposal`;
- correção P4 no back (`whatsapp-envio` declarado antes de `:signatureId`);
- dashboard de proposta.
