# Re-verificação de paridade web × app (03/10/2026): Financeiro, Usuários e Dashboards

Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, linhas 848–1240. Conferido no código atual de `dreamkeysapp/lib` (inclui os commits de 29/09 a 03/10, como o `de39749`, painel executivo), do `intellisys-CRM/src` (web), do `intellisys-CRM-Back/src` e do `intellisys-financeiro/apps/api`. Os caminhos `imobx-front`/`imobx` da auditoria correspondem a `intellisys-CRM`/`intellisys-CRM-Back`.

**Legenda**
- **Situação:** feito / parcial / falta / n/a (não se aplica mais).
- **Deploy:** "s" quando a correção ou o comportamento depende de deploy do back.
- **Esforço:** P / M / G.

## Resumo por domínio

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

## O que quebra o app ou o login

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

## Meu Financeiro, Comissões e Recebimentos do corretor

| ID | P | Lacuna | Situação | Evidência | Deploy | Esforço |
|---|---|---|---|---|---|---|
| fin-01 | P0 (FORA→reativar) | Cliente HTTP do financeiro (PIN, softAuth, troca de empresa) | ✅ **feito (03/10, fase 1)**: `features/finance/core/finance_api_client.dart` (+ multipart na fase 2) | `settings_service.dart:38-41` (`_kFinanceBaseUrl`, só para preferências); nenhum `finance_api_service`/`X-Finance-Pin`/428 em lib | n | M |
| fin-02 | P0 (FORA→reativar) | Tela Meu Financeiro | ✅ **feito (03/10)**: fase 1 + drill-downs, status, período personalizado e clique no mês na fase 2 (`features/finance/meu_financeiro`) | nenhuma ref. a `broker-dashboard`; back `broker-earnings.controller.ts:69` | n | G |
| fin-03 | P0 (FORA→reativar) | PIN do Financeiro | ✅ **feito (03/10, fase 1)**: `features/finance/pin` | nenhuma ref. a `/auth/pin`/`X-Finance-Pin` | n | M |
| fin-04 | P0 (FORA→reativar) | Pedir adiantamento | ✅ **feito (03/10, fase 2)**: `features/finance/adiantamento` (saldo livre sem endpoint para o corretor — ver plano) | nenhuma ref. a `commission-advances` | n | M |
| fin-05 | P0 (FORA→reativar) | Solicitações (lista e nova) | ✅ **feito (03/10, fase 2)**: `features/finance/solicitacoes` (lista, detalhe, nova/editar, anexos base64 5 MB) | nenhuma ref. a `request-tipos`/`/requests` | n | G |
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

## Usuários, Equipes, Permissões, Empresa, Perfil e Configurações

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

## Dashboards, SDR, Leads e Campanhas

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

## Novos: cobrança, acesso e plano (fora da auditoria de 29/09)

| ID | P | Lacuna | Situação | Evidência | Deploy | Esforço |
|---|---|---|---|---|---|---|
| NEW-01 | **P0** | Conta gerenciada com trial ou graça vencidos (ou assinatura suspensa): o titular cai em /settings sem aviso nem forma de assinar; o colaborador não é checado e toma 403 na Home e em Imóveis. O web tem modal in-app e `/system-unavailable` | ✅ **feito (03/10)**: `SubscriptionAccessGate` (`shared/services/subscription_access_gate.dart`) decide no login (todos os papéis, após a empresa) e no splash; titular → `/subscription-required` (planos, minha assinatura, painel web, chamados, perfil), colaborador → `/system-unavailable`, ambos em `features/subscriptions/pages/access_blocked_page.dart`; `AppRoutes` redireciona qualquer outra rota enquanto bloqueado; 403 do `SubscriptionGuard` no meio da sessão reabre a checagem (`api_service.dart`). Lê `billingRegime` (managed só bloqueia em status terminal, como o web) e `isExpiringSoon` (aviso de "trial termina em N dias" ainda não exibido). Testes: `test/shared/services/subscription_access_gate_test.dart` | app: `login_flow_service.dart:245-281`, `login_page.dart:172-251`, `subscription_service.dart:89-102` (ignora `billingRegime`/`isExpiringSoon`). Web: `SubscriptionGuardNew.tsx:291-406`. Back: `subscriptions.service.ts:1532-1556` (`managed_exempt`), `subscription.guard.ts:24-104`, `dashboard.controller.ts:58`, `properties.controller.ts:184-191` | n | M |
| NEW-02 | **P0 cond.** | Plano "só Financeiro": 403 em todas as rotas de CRM; Home travada em "Sem permissão", sem alternativa no app | ✅ **feito (03/10, não depende do deploy)**: `shared/utils/crm_product_access.dart` espelha `hasCrmProduct` do back; empresa com módulos e sem CRM → `/crm-unavailable` ("O plano da empresa não inclui o CRM", painel web, chamado, perfil; rotas de plataforma liberadas). `CompanyService.choosePreferredCompany` prefere uma empresa com CRM quando o usuário tem as duas. usr-04 continua parcial | back `crm-product-access.interceptor.ts:36-110` (commit `848dac00`, 02/10); app sem `hasCrmProduct`; `dashboard_page.dart:865-876` | **s** | M |

Para corrigir NEW-01:
1. Tratar `hasAccess=false` autoritativo como estado bloqueante próprio, e não como `redirect` para /settings.
2. Para o titular gerenciado, mostrar a tela de assinatura com as rotas permitidas do web (planos, minha assinatura, chamados, perfil). Isso inclui registrar as rotas de sub-01.
3. Para o colaborador, chamar `check-access` também e mostrar "sistema indisponível".
4. Ler `billingRegime` e `isExpiringSoon` para avisar o fim do trial.
