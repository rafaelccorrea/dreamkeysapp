# Paridade web × app — re-verificação 03/10/2026

Escopo: Fichas de Locação/Análise de crédito · Clientes/Proprietários/Documentos · Agenda/Visitas/Check-in/Vistorias.
Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md` (linhas 25–375). Código conferido: app `dreamkeysapp/lib` (HEAD 675b686), web `intellisys-CRM/src`, back `intellisys-CRM-Back/src`.
Legenda: **Deploy** = depende de deploy do back (s/n). **Esforço** P/M/G.

## Resumo

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

## Fichas de Locação e Análise de crédito

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

## Clientes, Proprietários e Documentos do cliente

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
| clientes-11 atendimento: anexos/editar | P1 | ✅ Feito 03/10 (sessão líder): editar registro (PUT com `retainAttachmentKeys` — escolhe quais anexos atuais manter), anexar até 10 arquivos de até 20 MB (limites do back), título ≤150 com contador; removido o "mínimo 4 caracteres" que só o app tinha. `client_interactions_panel.dart` · era: **Parcial** | service multipart pronto (`client_service.dart:612-691`), mas o painel só chama create sem arquivos (`client_interactions_panel.dart:648-655`); não há Editar nem limite de 150 | n | P |
| clientes-18 dinheiro na edição | P1 | Feito | `client_form_page.dart:378-383` `_moneyText` usa CurrencyInputFormatter | n | — |
| clientes-20 Clientes da Locação (/v1/locacao/people) | P1 | Falta | nada em `lib/`; web `Drawer.tsx:1019-1025` | n | G |
| clientes-23 busca com debounce | P1 | Feito | `clients_page.dart:264-288` (400 ms; 0 ou 3+). Descarta respostas fora de ordem pelo contador `_loadSeq` (`clients_page.dart:182,207`) — conferido 03/10 | n | — |
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

## Agenda, Visitas, Check-in, Vistorias

| ID | Sev | Situação | Evidência (app / web-back) | Deploy | Esforço |
|---|---|---|---|---|---|
| visitas-01 menu Visitas | P0 | Feito | `app_drawer.dart:1071-1078,1266,1289`; `visit_report_access.dart:40-50` | n | — |
| agenda-01 tipo "Assinatura" (**400 no back**) ✅ | P1 | **Feito (03/10)**: `AppointmentType.selectable` (sem `signature`) no criar, editar e filtro; legado `signature` vira "Outro" ao editar | `appointment_model.dart:195`; ofertado em `create_appointment_page.dart:787`, `edit_appointment_page.dart:867`, `appointment_filters_sheet.dart:301` / back `appointment.entity.ts:17-26` | n | P |
| agenda-03 editar/excluir/status sem gate ✅ | P1 | **Feito (03/10)**: detalhe exige criador + `calendar:update`/`calendar:delete` (mesma regra do web e do back); botões desabilitados e fluxo de status oculto sem direito | nenhum `hasPermission`/criador em `features/appointments`; `app_permissions.dart` sem calendar:* | n | P |
| checkin-01 tela de configurações | P1 | Falta | `check_in_service.dart:991-995` só GET; web `Drawer.tsx:749-755` | n | G |
| agenda-02 título 3–200 | P2 | ✅ Feito 03/10 (criar e editar, contador 200) · era: Falta | sem minLength/maxLength nas páginas | n | P |
| agenda-04 calendar:create ✅ | P2 | **Feito (03/10)**: `calendar_page.dart` esconde os atalhos de criar e bloqueia `_openCreate` sem `calendar:create` | sem gate em `calendar_page.dart` | n | P |
| agenda-05 início no passado | P2 | ✅ Feito 03/10 (dias passados desabilitados; início no passado bloqueia com a mensagem da web) · era: Falta | `create_appointment_page.dart:221` `firstDate: now-1d` | n | P |
| agenda-06 tipo pré-selecionado | P2 | ✅ Feito 03/10 (nasce sem tipo, como a web; rodapé pede "Escolha o tipo") · era: Falta | `create_appointment_page.dart:104` `_type = visit` | n | P |
| agenda-07 "Criado por" e copiar endereço | P2 | ✅ Feito 03/10 ("CRIADO POR" no bloco Registro; botão copiar no Local) · era: Falta | sem bloco do criador nem Clipboard em `appointment_details_page.dart` | n | P |
| agenda-08 busca por texto | P2 | Falta | `calendar_page.dart:1031` só "Buscar pessoa…" | n | P |
| agenda-09 permitir sobreposição | P2 | Feito (em outro lugar) | `settings_page.dart:668,1103-1111` grava `calendarAllowOverlappingSlots` (não está na ScheduleSettingsPage) | n | — |
| agenda-10 snooze 15 min | P2 | Falta | `api_constants.dart:264` sem uso | n | M |
| checkin-02 exportar Excel | P2 | Falta | `check_in_list_page.dart` sem exportação | n | M |
| checkin-03 gate do módulo visit_report | P2 | Falta | `app_drawer.dart:1051-1060` sem `hasCompanyModule('visit_report')` | n | P |
| checkin-04 Histórico sem check_in:view | P2 | ✅ Feito (03/10) | ícone e link do histórico só com `check_in:view` (ou admin/master); `check_in/utils/check_in_access.dart` | n | P |
| checkin-05 manager libera gestão | P2 | ✅ Feito (03/10) | gestão só admin/master ou `check_in:manage_settings`, sem bypass de `manager` (igual `PermissionsGuard` do back e `CheckInPage.tsx`) | n | P |
| vistorias-01 permissões | P2 | ✅ Feito (03/10) | lista: "Nova vistoria" só com `inspection:create`; detalhe: editar/status/fotos/histórico com `inspection:update`, excluir com `inspection:delete`, pedir aprovação financeira com `inspection:create` (POST /inspection-approval); criar/editar bloqueiam sem a permissão | n | P |
| vistorias-02 checklist no detalhe | P2 | ✅ Feito 03/10 (seção Checklist com as traduções e cores da web; `inspection_checklist.dart` + teste) · era: Falta | sem `checklist` nas páginas | n | P |
| vistorias-03 remover entrada do histórico | P2 | ✅ Feito 03/10 (lixeira por entrada com confirmação, só com inspection:update) · era: Falta | `removeHistoryEntry` sem chamada nas páginas | n | P |
| vistorias-04 vistoriador por papel | P2 | Falta | sem filtro por role em create/edit | n | P |
| vistorias-05 máscara de documento/telefone | P2 | ✅ Feito 03/10 (grava com máscara, igual à web) · era: Falta | `create_inspection_page.dart:306-309`, `edit_inspection_page.dart:385-388` usam unmask | n | P |
| vistorias-06 Vistorias no menu | P2 | Falta | `app_drawer.dart:28` ainda diz hidden; web `Drawer.tsx:1075-1081` visível (Locação) | n | P |
| vistorias-07 tipo pré-selecionado | P2 | ✅ Feito 03/10 (nasce sem tipo; "Tipo é obrigatório") · era: Falta | `create_inspection_page.dart:38` `_selectedType = entry` | n | P |

## Observações

- Nenhum item depende de deploy do back. Os endpoints que o app precisa (`/v1/locacao/*`, `/v1/rental-form-approvals`, `/check-in/settings` PUT, `/appointments/:id/snooze`, `/protected-owner-data`) já existem no back. A única exceção é clientes-24, e só se a opção escolhida for o back passar a suportar `state`.
- Os 6 P0 que faltam são todos de Fichas de Locação, marcados "FORA" pelo Edson em 29/09. Se a locação voltar ao escopo, comece por fichaloc-07 e fichaloc-06 (P, sem dependência).
- Ganhos rápidos (P, sem deploy) que eliminam erro 400/403 em produção: agenda-01, agenda-03, agenda-04, checkin-04, checkin-05, vistorias-01.
