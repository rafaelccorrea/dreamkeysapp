# Financeiro no app: plano de integração (03/10/2026)

Especificação para levar o módulo Financeiro ao app Flutter seguindo o mesmo esquema do web, inclusive o PIN de 2 horas. Foi feita só com leitura de código, sem alterar nada. Complementa `financeiro-usuarios-dashboards.md` (fin-01 a fin-28).

**Caminhos usados nas evidências**
- **WEB:** `intellisys-CRM/src`
- **FIN:** `intellisys-financeiro/apps/api/src`
- **APP:** `dreamkeysapp/lib`

---

## 1. Resumo

- **Quem atende:** o Financeiro é um microserviço próprio, NestJS sob `/api/v1`, em `https://api.financeiro.intellisysbr.com/api/v1` (`.env.production:11`). O web conversa com ele por um cliente axios separado e manda:
  - o **JWT do próprio CRM** (sem troca de token);
  - **`X-Company-ID`**, com o UUID da empresa ativa no CRM;
  - **`X-Finance-Pin`**, o token do PIN.
- **Onde vale o PIN:** em toda tela `/financeiro/*`, inclusive no Meu Financeiro do corretor. É um PIN pessoal de 4 dígitos.
- **O token do PIN:**
  - é um JWT curto, válido por **2 h**, renovado pelo uso (janela deslizante);
  - sem ele, a API responde **428 `FINANCE_PIN_REQUIRED`**, mas só se o servidor tiver `FINANCE_PIN_ENFORCED=true`;
  - 5 erros seguidos bloqueiam por 15 min;
  - quem esqueceu recebe um código de 6 dígitos por e-mail.
- **No app hoje:** só existem as preferências de aviso do financeiro (`APP shared/services/settings_service.dart:32-41,469-560`). Faltam o cliente, o PIN, as telas, o gating, o sino e os deep links.
- **Escopo recomendado para o app (mobile-first):**
  - modo **"pessoal"** para todos: Meu Financeiro, Solicitações (lista, nova e detalhe), pedir adiantamento;
  - **"Para aprovar"** (fila "Meu aval" da Central) para quem tem `approvals:view`;
  - sino do financeiro com deep links.
  - O restante (contas a pagar e a receber, DRE, cadastros, acessos…) continua só no web.

---

## 2. PIN de acesso

### 2.1 Constantes e regras (back)

| Regra | Valor | Evidência |
|---|---|---|
| Header de requisição | `X-Finance-Pin` | FIN `modules/auth/finance-pin.regras.ts:14` |
| Header de resposta com token renovado | `X-Finance-Pin-Token` (exposto no CORS) | `finance-pin.regras.ts:17`; FIN `main.ts:59-60` |
| Validade do token | `PIN_TOKEN_TTL_S = 2*60*60` | `finance-pin.regras.ts:19-20` |
| Reemissão pelo uso | só quando o token tem mais de 5 min (`PIN_RENOVAR_APOS_MS`) | `finance-pin.regras.ts:21-22`; `finance-pin.interceptor.ts:61-65` |
| Freio | 5 erros, depois bloqueio de 15 min | `finance-pin.regras.ts:26-27`; `finance-pin.service.ts:142-163` |
| PIN fraco (recusado) | não tem 4 dígitos, dígitos repetidos ou sequência (1234, 4321) | `finance-pin.regras.ts:45-54` |
| Código de 428 | `FINANCE_PIN_REQUIRED` | `finance-pin.regras.ts:30`; `finance-pin.interceptor.ts:50-58` |
| Interruptor da exigência | `FINANCE_PIN_ENFORCED === 'true'` | `finance-pin.regras.ts:36-38` |
| Rotas sem PIN | `/auth/*`, `/health`, o sino (`/notifications`, `unread-count`, `:id/read`, `mark-all-read`, `socket-ticket`, `preferences`), `/financial/receipt-lock`, `/repasses/earnings` | `finance-pin.regras.ts:73-84` |
| Identidade do token | `userKey` (`sub`, ou `crm:<sub>` sem vínculo). **Não depende da empresa**: trocar de empresa não tranca | `finance-pin.service.ts:43-50,94-96` |
| Revogação | redefinir o PIN derruba os tokens anteriores (Map em memória; um restart perde a lista, aceito) | `finance-pin.service.ts:60-65,326-327` |
| Caminho quente | validar o token não toca no banco (só HMAC) | `finance-pin.service.ts:55-58,177-179` |

### 2.2 Endpoints (todos com `DualJwtAuthGuard` e sem papel exigido; FIN `modules/auth/finance-pin.controller.ts`)

| Método | Path | Body | Resposta | Erros |
|---|---|---|---|---|
| GET | `/auth/pin/status` | – | `{configurado: bool, bloqueadoAte: ISO\|null}` | – |
| POST | `/auth/pin/setup` | `{pin}` | `{token, expiraEm}` (criar já desbloqueia) | 400 PIN fraco; 409 já tem PIN |
| POST | `/auth/pin/verify` | `{pin}` | `{token, expiraEm}` | 404 sem PIN; 422 `PIN_INCORRETO` + `tentativasRestantes`; 429 + `bloqueadoAte` |
| POST | `/auth/pin/refresh` | – (manda o header `X-Finance-Pin`) | `{token, expiraEm}` | 401 token vencido |
| POST | `/auth/pin/esqueci` | `{}` | `{enviadoPara: "e***@x", expiraEm}` | 404 sem PIN; 429 `PIN_CODIGO_RECENTE` (1 envio/min); 503 `PIN_EMAIL_FALHOU`; 400 sem e-mail |
| POST | `/auth/pin/redefinir` | `{codigo (6 dígitos), pin}` | `{token, expiraEm}` (solta o bloqueio) | 400 código errado ou vencido (5 erros invalidam o código; vale 10 min); 400 PIN fraco; 404 |
| DELETE | `/admin-users/:id/pin` | – | `{redefinido}` | redefinição feita por quem administra Acessos. Fica fora do app |

Fontes: controller `:34-69`; service `:98-346`; o web chama tudo com `softAuth` (WEB `services/financeiroApi.ts:600-634`).

### 2.3 Como o web guarda e expira o PIN

- **Store:** fica em `localStorage['imobx:finance-pin'] = {token, expiraEm (ms, lido do exp do JWT), emitidoEm}` (WEB `services/financePinStore.ts:21,85-96`). Antes de 23/09 ficava em `sessionStorage`. Vale para todas as abas, que se sincronizam pelo evento `storage` (`:107-112`).
- **Interceptor:** é o mesmo nos 4 clientes do financeiro (`financePinStore.ts:133-150`):
  - injeta `X-Finance-Pin` em toda chamada;
  - grava o `x-finance-pin-token` que vier na resposta;
  - no 428 com o código, tranca.
- **Portão** (`components/financeiro/FinancePinGate.tsx`):
  - tranca sozinho quando o token vence, por timer, sem chamar a API (`:44-54`);
  - qualquer uso da tela (`pointerdown`, `keydown`, `wheel`) chama `POST /auth/pin/refresh` se o token tiver mais de **10 min** (`:25-26,56-76`); um 401 nessa chamada tranca;
  - **na entrada**, mostra só o PIN, porque o shell chama a API ao montar. **Depois do primeiro desbloqueio**, a expiração mostra o PIN por cima da tela, sem desmontá-la, e o formulário não se perde (`:81-106`);
  - fases: `carregando` → `criar` (digita e confirma) | `digitar` → `codigo` (6 dígitos) → `novo` (digita e confirma) (`:31-38,117-251`);
  - no 429, mostra contagem regressiva; no 409 (PIN criado em outra aba), vai para `digitar`; no 404 em `digitar` (o PIN foi redefinido), vai para `criar` (`:232-243`);
  - o botão "Voltar ao CRM" leva ao `/dashboard` (`:368`).
- **Logout:** apaga a chave (WEB `services/authStorage.ts:292-295`).
- **Quem precisa do PIN:** todo papel, em toda rota `/financeiro/*`, inclusive as abertas (WEB `routes/domains/financeiro.routes.tsx:272-278,306-312`). O widget de ganhos do dashboard do CRM, o sino e a trava de comprovante não pedem PIN.

### 2.4 Fluxo proposto para o app (o mesmo do web)

```
Tocar em "Financeiro" (qualquer tela do módulo)
  │
  ├─ FinancePinStore.tokenValido()?  (secure storage: token + expiraEm)
  │     ├─ sim ──► abre a tela; as chamadas levam X-Finance-Pin
  │     └─ não ──► FinancePinPage
  │                  GET /auth/pin/status
  │                  ├─ configurado=false ──► CRIAR (4 díg.) ─► CONFIRMAR ─► POST /setup ─► token
  │                  └─ configurado=true
  │                        ├─ bloqueadoAte>agora ─► contagem regressiva (+ "Esqueci meu PIN")
  │                        └─ DIGITAR ─► POST /verify
  │                               ├─ 200 ─► guarda token ─► volta à tela pedida
  │                               ├─ 422 ─► "Restam N tentativas"
  │                               ├─ 429 ─► bloqueio até bloqueadoAte
  │                               └─ 404 ─► CRIAR
  │                  "Esqueci meu PIN" ─► POST /esqueci ─► CÓDIGO (6 díg.)
  │                        ─► PIN NOVO ─► CONFIRMAR ─► POST /redefinir ─► token
  │
  Durante o uso:
  ├─ resposta com X-Finance-Pin-Token ─► substitui o token (janela deslizante)
  ├─ toque/rolagem com token >10 min sem chamada ─► POST /auth/pin/refresh (1 em voo)
  ├─ app volta do background ─► se agora ≥ expiraEm, tranca (PIN por cima, sem desmontar)
  ├─ timer até expiraEm ─► tranca
  ├─ 428 FINANCE_PIN_REQUIRED ─► apaga o token e mostra o PIN por cima
  └─ logout / troca de usuário ─► apaga o token (troca de EMPRESA não apaga: o token é da pessoa)
```

Equivalentes no mobile: o token vai para o **`flutter_secure_storage`**, já usado em `APP shared/services/secure_storage_service.dart:10-25`. Ele sobrevive ao fechamento do app dentro das 2 h, como o `localStorage` do web vale entre abas. A apagar em `clearTokens()`, `clearAuthSessionKeepCredentials()` e `clearAllAuthData()` (`:179,302,316`).

---

## 3. Contrato de autenticação com a API do Financeiro

| Item | Regra | Evidência |
|---|---|---|
| Base URL | `VITE_FINANCEIRO_API_URL` = `https://api.financeiro.intellisysbr.com/api/v1`. No app já existe `--dart-define=FINANCE_API_BASE_URL` com o mesmo valor padrão | WEB `config/apiConfig.ts:169-203`; `.env.production:11`; APP `settings_service.dart:38-41` |
| Identidade | `Authorization: Bearer <access token do CRM>`, sem troca. O back aceita o JWT próprio, o JWT DreamKeys ou faz delegação para `GET /auth/profile` do core | WEB `financeiroApi.ts:429-439`; FIN `common/guards/dual-jwt-auth.guard.ts:6-84` |
| Empresa | `X-Company-ID: <UUID da empresa ativa no CRM>` em **todas** as chamadas, inclusive `/auth/*` (o `/auth/me` usa esse header para `companyDenial`) | WEB `financeiroApi.ts:441-445`; FIN `modules/auth/dreamkeys-jwt.strategy.ts:143,227-250` |
| PIN | `X-Finance-Pin: <token>`; ler o `X-Finance-Pin-Token` da resposta | seção 2 |
| Timeout | 30 s é o teto (criar solicitação: 120 s; upload: 90 s) | WEB `financeiroApi.ts:418-422`; regra de ouro em `intellisys-CRM/CLAUDE.md` |
| 401 | **Não desloga.** Fora do módulo não faz nada. Dentro dele, pergunta à API principal (`GET /auth/profile`) e deixa o refresh e logout do cliente principal decidirem. Um 401 do financeiro pode significar só "este usuário não alcança o financeiro" | WEB `services/sessionAuthority.ts:1-74`; `financeiroApi.ts:467-476` |
| 403 de empresa | `code: COMPANY_NO_ACCESS` (sem acesso) ou `COMPANY_NOT_PROVISIONED` (empresa sem o módulo no financeiro). Mostrar "troque de empresa" ou "empresa sem Financeiro", nunca "sem permissão" | WEB `financeiroApi.ts:6406-6420,6743-6765` |
| 403 de papel | corpo `{code, role, permission, allowedRoles[], message}`. Mostrar quem pode, traduzindo o papel | WEB `financeiroApi.ts:6421-6449`; FIN `common/guards/assert-permissao.ts:18-39` |
| 423 Locked | trava de comprovante: escrita bloqueada por título aprovado há mais de 48 h sem comprovante. O corpo traz `receiptLock` | FIN `modules/financial/receipt-lock/receipt-lock.interceptor.ts:123-139` |
| 428 | PIN (seção 2) | – |
| Identidade no módulo | `GET /auth/me` → `FinanceMe {linked, userId, name, email, role, permissoes[], concedidas[], revogadas[], cargo, permissoesDoCargo[], companies[], companyDenial?, podeVerSino?, receiveNotifications?}`. Um 404 (back antigo) significa "sem gating" | WEB `types/financeiro.ts:4827-4906`; `financeiroApi.ts:577-596` |
| Gate de **módulo** | a empresa precisa ter `financial_management` em `availableModules`, **sem bypass** de papel (nem admin/master) | WEB `financeiro.routes.tsx:249-260` |
| Gate de **crachá** | `financial:access` (permissão do CRM), ou papel master/admin, para as telas de gestão (inclui Aprovações e a página Adiantamentos). **Não é exigido** em Meu Financeiro, Solicitações e Acompanhamento | WEB `financeiro.routes.tsx:122-137,287-317`; `components/layout/Drawer.tsx:1350-1370` |
| Gate de **tela** | matriz papel × tela, mais as exceções por pessoa ou cargo (`isFinanceTelaPermitida`). Com `linked:false`, não há gating | WEB `config/financeVisibility.ts:163-204,477-499` |
| Plano "só Financeiro" | `planType==='financeiro'`, ou módulos só de plataforma, add-ons e `financial_management`: para essa empresa, o sistema é o Financeiro | WEB `utils/empresaSoFinanceiro.ts:24-78`; APP `shared/utils/crm_product_access.dart` |

**Armadilha no app:** `ApiService.buildOutboundHeaders(endpoint:)` **não envia `X-Company-ID` para endpoints `/auth/*`** (APP `shared/services/api_service.dart:60-66,181-182`). No cliente do financeiro, `X-Company-ID` tem de ser posto à mão em todas as chamadas, ou o helper tem de ser chamado com um endpoint neutro. O helper também já faz o refresh proativo do JWT (`:134-150`), o que é útil.

---

## 4. Visibilidade por papel e escopo do app

Matriz do web (WEB `config/financeVisibility.ts:150-204`; Central: FIN `packages/shared/src/types/auth.ts:181-187`):

| Papel | Telas relevantes |
|---|---|
| CORRETOR | meu-dashboard, vendas, pipeline, comissões, solicitações, acompanhamento, adiantamentos, notificações. **Não aprova** |
| GESTOR / DIRETOR (comercial) | o mesmo do corretor, mais metas e **aprovações**. Na prática decidem só a fonte REQUEST, nas etapas GESTOR e DIRETORIA da cadeia |
| RH / GESTOR_MARKETING | meu-dashboard, solicitações, acompanhamento, adiantamentos, notificações (RH também equipes) |
| ANALISTA_FINANCEIRO | todas as operacionais, **sem** aprovações |
| GERENTE / DIRETOR_FINANCEIRO / ADMIN | tudo (aprovam as 5 fontes) |
| PENDENTE (sem papel) | só adiantamentos |

**Escopo recomendado para o app.** Mobile-first: o uso no celular é consultar o próprio dinheiro e pedir ou decidir rápido. Lançamento, conciliação e relatórios são trabalho de mesa.

| # | Tela no app | Quem vê | Equivale no web | Por que entra |
|---|---|---|---|---|
| A | **PIN** (criar, digitar, esqueci) | todos | `FinancePinGate` | pré-requisito |
| B | **Meu Financeiro** (KPIs, próximos recebimentos, minhas vendas, fichas aguardando assinatura, adiantamentos, minhas solicitações) | todos com o módulo | `/financeiro/meu-dashboard` | fin-02/07/08/09/13; é o principal uso do corretor |
| C | **Solicitações** (lista própria com filtros por status e período) | todos com o módulo | `/financeiro/solicitacoes` | fin-05/21. O Acompanhamento hoje só redireciona para cá (WEB `pages/financeiro/AcompanhamentoPage.tsx:18-27`) |
| D | **Detalhe da solicitação** (cadeia, comentários, anexos, cancelar, editar ou corrigir reprovada) | o dono | modal dentro da lista | fin-06 |
| E | **Nova solicitação** (tipo → campos dinâmicos → anexos) | todos com o módulo | `NovaSolicitacao` + `DrawerSolicitacaoForm` | fin-05/28 |
| F | **Pedir adiantamento** (motor `ADIANTAMENTO_COMISSAO`) | todos (`commission-advances:create` vem por padrão até para PENDENTE) | `DrawerAdiantamentoForm` | fin-04/12 |
| G | **Para aprovar** (sub-aba "Meu aval": aprovar e reprovar REQUEST; os outros tipos só leitura ou "abrir no web") | `approvals:view` e (`financial:access` ou admin/master) | `/financeiro/aprovacoes/decisao/meu-aval` | fin-19. Gestor e diretor decidem pedidos no celular |
| H | **Sino do financeiro** com deep links para B, D e G | `podeVerSino` | `financeNotificationsApi` | fin-14/15 |
| I | Card "Meu dinheiro" na Home (`/repasses/earnings`, sem PIN) | com o módulo | widget do `UserDashboardPage` | fin-13 |

**Fora do escopo (só web):**
- contas a pagar e a receber, bancos, cartões, DRE, DFC, orçamento, cadastros, acessos, autonomia, extras e cauções, repasses de gestão;
- vendas, pipeline e comissões de gestão, metas;
- dashboard de solicitações;
- as sub-abas de Execução e Registro da Central, e a aprovação de adiantamento, que exige `feePercent`.

No app, quem não tem a tela vê um aviso para usar o web, sem item morto.

---

## 5. Endpoints por tela

### B. Meu Financeiro

**Na montagem: tudo em paralelo, sem cascata.**

| Chamada | Query | Resposta (resumo) | Back |
|---|---|---|---|
| GET `/repasses/broker-dashboard` | `brokerId?` | `totals{devido, recebido, retido, aReceber, travado?, bonificacao?, saldoAdiantamento, saldoDevedor}`, `brokers[]`, `mensal[{month, recebido, retido, previsto}]`, `aguardandoAssinatura{count, valor}`, `adiantamentoAprovado?{count, valor}` | FIN `repasses/broker-earnings.controller.ts:69`; chave `repasses:view-own` |
| GET `/repasses/broker-dashboard/proximos` | `page, pageSize=6, search, status (CSV), from, to (YYYY-MM-DD), sortBy (venda\|previsto\|valor), sortDir, visao, brokerId` | `{data[{repasseId, saleId, origem, fichaVenda, valor, status, previstoPara, emAtraso?}], total, page, pageSize}` | `:81` |
| GET `/repasses/broker-dashboard/vendas` | `page, pageSize=8, search, situacao (a-receber\|quitadas\|retencao\|sem-assinatura), sortBy, sortDir, brokerId` | lista paginada: totais por venda, `papeis`, `parcelas`, `bonusRate` | `:133` |
| GET `/commission-advances` | `page, pageSize=5, search, brokerId` | `CommissionAdvance{code, value, feePercent, chargedValue, status, sales[], debit}` | `commission-advances.controller.ts:68` |
| GET `/requests` | `page=1, pageSize=5` | ver C (só se a tela `solicitacoes` estiver liberada) | `requests.controller.ts:132` |

**Condicionais e sob demanda:**
- GET `/repasses/broker-dashboard/assinaturas`, só se `aguardandoAssinatura.count > 0` (`:112`);
- GET `/repasses/broker-dashboard/vendas/:saleId` (detalhe da venda, `:164`);
- GET `/repasses/:id/origem` (origem do repasse, `:42`);
- **Não portar** o paliativo `?status=APROVADO` sem paginação. Usar `adiantamentoAprovado` do resumo e, se faltar, mostrar "–".

**Regras de exibição:**
- O período (Este mês, 30, 90 dias, Tudo, mês do gráfico) vale **só** para `/proximos`. Mês corrente: `from` aberto para pegar os atrasados.
- Busca com debounce de 400 ms.
- O seletor de corretor só aparece quando `brokers.length > 1`.
- Ocultar valores é só máscara local, guardada em preferência.
- Atualização automática a cada 60 s com o app em primeiro plano, ao voltar ao app e em cada push do financeiro (debounce de 1,5 s). Descartar respostas atrasadas com um contador de sequência.
- Um 403 nos adiantamentos bloqueia só aquela seção.
- Botão "Solicitar adiantamento" leva a F.

Fonte: WEB `pages/financeiro/MeuFinanceiroPage.tsx:283,338,579-584,656-717,766-1092,1141-1180,2045-2077`.

### C. Solicitações (lista)

- GET `/requests/dashboard` e GET `/requests` (`page, pageSize=20, search, status, type, from, to, companyId`) **em paralelo**. Sem `alvoTipo`, o back devolve só os pedidos da pessoa.
- Status: PENDENTE, APROVADO, REPROVADO, CANCELADO, EM_PROCESSAMENTO, CONCLUIDO.
- Prioridade: BAIXA, MEDIA, ALTA, URGENTE.
- `RequestSummary`: `id, code, type, tipoId, status, priority, title, amountRequested, amountApproved, paymentMethod, company, requester, category, approvals[{level, role, status, comment, approver, decidedAt}], avisoLancamento?, createdAt`.
- Fonte: WEB `types/financeiro.ts:2547,2568,2585`; FIN `requests.controller.ts:50,132`.
- O app **não** expõe as visões de equipe, setor ou consolidado (`requests:view-others`, `/requests/escopo-alvos`). Fica para o web.

### D. Detalhe da solicitação

- **Ao abrir:** GET `/requests/:id` → `RequestDetail` = resumo + `permissoes{podeDecidir, podeEditar, podeReenviar, podeCancelar, …}`, `comments[]`, `attachments[]`, `payables[]`, `beneficiaries[]`. Os botões seguem `permissoes` do back.
- A trilha de auditoria (`/audit-logs`) fica fora do app.
- **Ações:**
  - **comentar:** POST `/requests/:id/comments {body}` (não vazio; `requests:comment`);
  - **cancelar:** PATCH `/requests/:id/cancel {reason? ≤500}`. Só o dono, e só antes de processar ou de ter título;
  - **editar** (PENDENTE) **ou corrigir reprovada** (REPROVADO): PATCH `/requests/:id`; a correção leva `mensagem ≤1000`. O valor fica travado se alguma etapa já aprovou;
  - **anexar depois:** ver E;
  - **remover anexo:** DELETE `/requests/:id/attachments/:attId`.
- Fonte: WEB `components/financeiro/solicitacoes/SolicitacaoDetalhePage.tsx:211,324,342,367,447-511`; FIN `requests.controller.ts:168,189,239,263,285`.

### E. Nova solicitação

1. GET `/request-tipos` (`?companyId`; cache de 60 s por empresa) → `tipos[{id, nome, motor: PAGAMENTO|REEMBOLSO|ADIANTAMENTO_COMISSAO, naturezaIds, camposBase{campo:{visivel, obrigatorio}}, campos[{chave, rotulo, kind: TEXTO|TEXTO_LONGO|NUMERO|MOEDA|DATA|LISTA|SIM_NAO, opcoes, obrigatorio}]}], naturezas[]`. Se a chamada falhar, abre o formulário sem tipo. O motor `ADIANTAMENTO_COMISSAO` desvia para F.
2. **Em paralelo** (`allSettled`, com aviso de qual lista faltou):
   - GET `/companies`, `/financial/cost-centers`, `/financial/suppliers` (cadastros; cache de 60 s);
   - GET `/requests/categories`;
   - GET `/financial/credit-cards?companyId`, só se o meio de pagamento for cartão.
3. **Validações:**
   - obrigatórios: empresa, `type`, título, justificativa e `amountRequested > 0`;
   - cartão: `creditCardId`, `purchaseDate` e parcelas de 1 a 120;
   - rateio: a soma tem de bater com o valor (±0,01);
   - campos do tipo marcados como obrigatórios;
   - tipo "Outros" exige descrição em `notes`;
   - não há teto de valor (o valor só define a alçada).
4. POST `/requests`, com timeout de 120 s.
   - **Body:** `type, tipoId, naturezaId, camposExtras, title, justification, amountRequested, companyId, priority, categoryId, costCenterId, supplierId (não vai no reembolso), department, paymentMethod, notes, beneficiaries, qtdAnexos, creditCardId, purchaseDate, installments`.
   - Um 201 pode trazer `avisoLancamento`: mostrar aviso persistente.
5. **Anexos, depois do 201,** um de cada vez:
   - multipart `POST /financial/anexos/upload` (até 30 MB) + `POST /requests/:id/attachments {name,url}`;
   - no 403 ou 404 (caso do corretor), usar o caminho antigo `POST /requests/:id/attachments/upload {filename, base64, mimeType}`, com **limite de 5 MB**;
   - tipos aceitos: pdf, jpg, jpeg, png, webp;
   - recomendação para o app: usar direto o base64 de 5 MB para quem não tem `attachments:attach`;
   - falha de anexo vira aviso, não erro.
6. **Rascunho** por tipo, por usuário e empresa, guardado localmente e apagado no 201.
7. **409 ou timeout:** consultar GET `/requests?companyId&page=1&pageSize=20` e procurar o mesmo título, valor e empresa criado há menos de 10 min.
   - Achou: dizer que foi criada e "não envie de novo".
   - Não achou: mostrar o erro e manter o rascunho.

Fonte: WEB `components/financeiro/solicitacoes/tipos/NovaSolicitacao.tsx:51-103`; `DrawerSolicitacaoForm.tsx:207-278,343-352,435-442,519-526,698-754,786-922`; `anexosDaNovaSolicitacao.ts`; `utils/anexosFinanceiro.ts:16,63,253-307`; `desfechoDaCriacao.ts:72-77`; FIN `requests.dto.ts:45-80`; `requests.service.ts:1037-1537`; `request-tipos.controller.ts:30-36`.

### F. Pedir adiantamento

- **Ao abrir:** GET `/companies` e GET `/repasses?brokerId=<me.userId>` (para listar vendas e somar o "a receber" dos repasses PENDING e APPROVED).
- GET `/commission-advances/broker-balance/:brokerId` exige `view-staff`, **que o corretor não tem**. O web toma 403 e silencia.
- **Envio:** POST `/commission-advances`.
  - **Body:** `{companyId, brokerId: me.userId, saleId, saleIds? (se >1), description, value ≥0,01, notes?}`.
  - **Não enviar** `feePercent` nem `capOverrideReason` (sem `:approve` ou `override-cap`, o back responde 400).
  - Se o back recusar `saleIds`, reenviar só com `saleId`.
- **Regras no back:**
  - `saldoLivre = aReceber − adiantamentos em aberto − estornos − pedidos SOLICITADO/APROVADO`;
  - acima do saldo, **400** com o máximo;
  - `aReceber ≤ 0` passa para o aprovador;
  - erros possíveis: só 400, 403 e 404 (não há 409 nem 422).
- **Histórico:** a lista de B (GET `/commission-advances`, sem `visao`, que já é "minha visão").
- Fonte: WEB `components/financeiro/adiantamentos/DrawerAdiantamentoForm.tsx:266-289,346-404,454-518`; `enviarAdiantamento.ts:32-48`; FIN `commission-advances/commission-advances.controller.ts:48,68,80`; `commission-advances.service.ts:407-662`.

### G. Para aprovar (client próprio no web: WEB `services/approvalsApi.ts`)

- **Ao abrir, em paralelo:**
  - GET `/approvals/summary` (contagens por situação; o app usa o número de `MEU_AVAL` como badge);
  - GET `/approvals/queue?situacao=MEU_AVAL&page&pageSize&sortBy&sortDir&search`.
  - Não enviar parâmetros iguais ao padrão: o back usa `forbidNonWhitelisted`.
  - Item: `{source, id, code, title, companyName, counterparty, amount (string), dueDate, stage, canActByMe, blockedReason, priority, etapaAtual, possivelDuplicata?}`.
- **Detalhe sob demanda:** GET `/approvals/item?source&id` → `campos, anexos, cadeia[{nivel, papel, status, aprovador, decididoEm, comentario}]`.
- **Decidir:** POST `/approvals/bulk {action: approve|reprove, reason?, items[{source, id, confirmarDuplicidade?}]}`.
  - Vale para um item ou para vários (1 a 200), em fatias de 10 no cliente.
  - Resposta: `{succeeded[], failed[{source, id, error, code?, suspeitos?}]}`.
  - Reprovar exige motivo com **≥5 caracteres** (máximo de 500 no web).
  - `failed.code=LANCAMENTO_EM_DOBRO`: perguntar e reenviar com `confirmarDuplicidade:true`.
- **Fontes e chaves:**
  - REQUEST decide quem a cadeia designou;
  - PAYABLE e DEAL_COST exigem chaves do financeiro;
  - **ADVANCE não vai pelo lote:** usa `POST /commission-advances/:id/approve {feePercent}`. No app, mostrar como "abrir no web" ou deixar só a reprovação;
  - REPASSE não se decide.
- **Erros:**
  - 403 por item vem dentro de `failed`;
  - 409: "já decidida por outra pessoa". Recarregar a fila;
  - 423: trava de comprovante.
- Não há badge no menu do web, nem polling (o summary só roda na página). No app, o summary na abertura do drawer pode alimentar um badge.
- Fonte: WEB `components/financeiro/aprovacoes/centralSituacoes.ts:45-203`; `pages/financeiro/AprovacoesPage.tsx:362-363,415-522`; `services/approvalsApi.ts:63-445`; FIN `approvals/approvals.controller.ts:50-108`; `approvals.service.ts:74,111-149,183,1132,1243`.

### H. Sino do financeiro (fora do PIN)

- **REST:** GET `/notifications` (com `X-Company-ID`), PATCH `/notifications/:id/read`, POST `/notifications/mark-all-read`. O web conta os não lidos pela lista e não usa `/unread-count`.
- **Socket.io:**
  - POST `/notifications/socket-ticket` → `{ticket, path:'/finance-socket'}`;
  - conexão na origem da base URL, `path=/finance-socket`, `transports:['websocket']`, ticket em `auth.ticket`;
  - eventos: `finance:ready`, `finance:unauthorized`, `finance:notification {type, saleId?, dealId?, payableId?, requestId?}`;
  - reconexão com backoff de 2 a 60 s e ticket novo a cada tentativa;
  - polling de segurança a cada 60 s em primeiro plano.
- No sino unificado, o id vira `fin:<id>` para saber para qual back mandar o "lida".
- **Deep links:**

| Notificação | Destino no app |
|---|---|
| `requestId` (SUA_VEZ, APPROVAL_PENDING, APPROVED, REPROVED) | D. Se a pessoa for aprovadora, D com as ações ou G |
| ADVANCE_APPROVAL_PENDING | G, ou "abrir no web" |
| PAYABLE_* / RECEIVABLE_* / SALE_COMMENT / `dealId` | "abrir no web" |

- Fonte: FIN `notifications/notifications.controller.ts:28-102`; `notifications.gateway.ts:16,84-107`; WEB `services/financeNotificationsApi.ts:31-38,126-200`; `services/financeNotificationsSocket.ts:28-122`; `hooks/useNotifications.ts:547,612,900-929`.

### I. "Meu dinheiro" na Home

- GET `/repasses/earnings?brokerId?` (sem PIN; `repasses:view-own`) → `{saldoAdiantamento, saldoDevedor, totals, brokers[]}`.
- Uma chamada por montagem. Falha silenciosa esconde o card.
- Só aparece com o módulo `financial_management`.
- Tocar no card leva a B, que pede o PIN.
- Fonte: WEB `financeiroApi.ts:3761`; `hooks/useBrokerEarnings.ts`; `pages/UserDashboardPage.tsx:141`.

---

## 6. O que o app já tem e onde encaixar

| Item | Estado | Evidência |
|---|---|---|
| Base URL do financeiro | só como constante privada das preferências | APP `shared/services/settings_service.dart:38-41` |
| Preferências de aviso do financeiro | feito (GET/PUT `/notifications/preferences`) | `settings_service.dart:469-560`; `features/settings/pages/notification_preferences_page.dart:100-146` |
| Headers e refresh do JWT | `ApiService.buildOutboundHeaders` + `garantirTokenFresco` (atenção à armadilha do `/auth/*`, seção 3) | `shared/services/api_service.dart:134-225` |
| Armazenamento seguro | `FlutterSecureStorage`, chave da empresa `intellisys_selected_company_id` | `shared/services/secure_storage_service.dart:10-25,179-326` |
| Biometria | `BiometricService` (local_auth, `biometricOnly`) | `shared/services/biometric_service.dart` |
| Gate de módulo | `ModuleAccessService.hasCompanyModule/hasPermission`. O mapa ainda usa `financial:view…` (fin-17); trocar para `financial:access` | `shared/services/module_access_service.dart:405-409,455,474` |
| Plano só-Financeiro | `/crm-unavailable` | `shared/utils/crm_product_access.dart`; `core/routes/app_routes.dart:411,507` |
| Drawer | sem grupo Financeiro. `/commissions` é código morto oculto | `shared/widgets/app_drawer.dart:1093,1804`; `app_routes.dart:287,803` |
| Deep links | `/financeiro/*` cai em "sem tela" | `shared/utils/app_deep_link.dart:448`; `features/notifications/widgets/notification_list.dart:96` |
| Sino | contagem só do core | `features/notifications/services/notification_counts_service.dart:24` |
| Socket.io | já existe `socket_io_client` (chat) | `features/chat/services/chat_socket_service.dart:116` |
| Padrão de feature | `features/<x>/{models,pages,services,widgets}`; service singleton `X.instance` devolvendo `ApiResponse<T>`; estado com `provider` e `ChangeNotifier` | `features/goals/services/goal_service.dart:10-50` |

### Estrutura proposta

```
lib/features/finance/
  core/
    finance_config.dart          // base URL (dart-define FINANCE_API_BASE_URL), timeouts
    finance_api_client.dart      // http + headers (Bearer, X-Company-ID SEMPRE, X-Finance-Pin),
                                 // captura X-Finance-Pin-Token, 428→lock, 401 sem logout,
                                 // mapeia erros: COMPANY_*, allowedRoles, 423, 409, timeout
    finance_errors.dart          // FinanceError {status, code, message, allowedRoles, empresa…}
    finance_pin_store.dart       // ChangeNotifier: token/expiraEm/emitidoEm em secure storage;
                                 // timer de expiração; refresh por uso (>10 min); clear no logout
    finance_me_service.dart      // GET /auth/me (cache por empresa; reset na troca de empresa)
    finance_visibility.dart      // porte de PERMISSAO_DA_TELA + MATRIZ + isFinanceTelaPermitida (só telas do app)
  pin/
    pages/finance_pin_page.dart  // fases criar/digitar/código/novo; teclado numérico próprio
    widgets/finance_pin_gate.dart// envolve as páginas; PIN por cima quando expira
  meu_financeiro/ {models, services/meu_financeiro_service.dart, pages, widgets}
  solicitacoes/  {models, services/requests_service.dart, pages(lista, detalhe, nova), widgets(campos_do_tipo)}
  adiantamento/  {services/commission_advance_service.dart, pages/pedir_adiantamento_page.dart}
  aprovacoes/    {services/approvals_service.dart, pages/para_aprovar_page.dart, widgets}
  notificacoes/  {finance_notifications_service.dart, finance_socket_service.dart}
```

- **Rotas** (`core/routes/app_routes.dart`):
  - `/financeiro` (índice);
  - `/financeiro/meu-dashboard`, `/financeiro/solicitacoes`, `/financeiro/solicitacoes/:id`, `/financeiro/solicitacoes/nova`;
  - `/financeiro/adiantamento/novo`, `/financeiro/aprovacoes`.
  - Todas envolvidas por `FinancePinGate`.
  - Paths iguais aos do web, para os deep links casarem 1:1.
- **Drawer:** grupo "Financeiro", visível se `hasCompanyModule('financial_management')`.
  - Meu Financeiro e Solicitações: sempre.
  - Para aprovar: `(financial:access || master/admin) && isFinanceTelaPermitida(me,'aprovacoes')`.
- **Logout:** `FinancePinStore.clear()` junto de `clearTokens()`.
- **Troca de empresa:** recarregar `/auth/me` e as telas abertas. O PIN continua valendo.
- **Plano só-Financeiro:** depois da Etapa 3, `/crm-unavailable` pode oferecer "Abrir o Financeiro" ou ir direto para Meu Financeiro.

---

## 7. Ordem de implementação (etapas pequenas e testáveis)

| Etapa | Entrega | Teste |
|---|---|---|
| 0 | `finance_config` + `finance_api_client` + `finance_errors` (sem tela); mover a base URL de `settings_service` para cá | unit: headers (X-Company-ID em `/auth/*`), captura de `X-Finance-Pin-Token`, mapeamento 401/403/423/428 |
| 1 | `FinancePinStore` (secure storage, expiração, refresh por uso, clear no logout) | unit com relógio falso: vence em 2 h; renova só com >10 min; 428 tranca |
| 2 | `FinancePinPage` + `FinancePinGate` (todas as fases, 422/429/409/404, esqueci/código/redefinir) | widget tests por fase; manual contra a API (PIN fraco, bloqueio de 15 min) |
| 3 | `/auth/me` + `finance_visibility` + grupo no drawer + rota índice | unit da matriz (CORRETOR, GESTOR, ANALISTA, `linked:false`, `companyDenial`) |
| 4 | Meu Financeiro, só leitura: resumo + próximos + vendas + adiantamentos + solicitações em `Future.wait`; ocultar valores; atualização a cada 60 s | medir o tempo até o primeiro dado (meta: a mais lenta, não a soma) |
| 5 | Drill-downs: detalhe da venda, origem do repasse, assinaturas | – |
| 6 | Solicitações: lista + dashboard + detalhe + comentar + cancelar | – |
| 7 | Nova solicitação: tipos, campos dinâmicos, cartão, anexos base64 de 5 MB, rascunho, 409/timeout | unit de validação e de `acharRecemCriada` |
| 8 | Pedir adiantamento | erro 400 de teto exibido com o máximo |
| 9 | Para aprovar: summary + fila MEU_AVAL + detalhe + bulk aprovar/reprovar + duplicidade + 409 | testar com usuário GESTOR |
| 10 | Sino `fin:` (REST + socket + polling de 60 s) e deep links `/financeiro/*` | push e notificação abrem a tela certa, passando pelo PIN |
| 11 | Card "Meu dinheiro" na Home + saída para o plano só-Financeiro + correção do mapa `financial:access` (fin-17) | – |

---

## 8. Riscos

- **Latência** (regra de ouro em `intellisys-CRM/CLAUDE.md` e `intellisys-financeiro/CLAUDE.md`):
  - cada ida custa ≥150 ms de rede, mais ~145 ms por statement no servidor (API em us-east-1, banco em sa-east-1);
  - no app: `Future.wait` na montagem, sem `await` em cascata;
  - uma requisição por recurso, nunca N chamadas por linha;
  - cadastros (empresas, centros de custo, fornecedores, tipos) em cache de 60 s; saldo, status e valor nunca em cache;
  - lote via `/approvals/bulk`;
  - em timeout de escrita, reconsultar antes de dizer que falhou.
  - O PIN não custa banco no caminho quente.
- **PIN no mobile:**
  - guardar o token **só** em secure storage, nunca o PIN em claro;
  - teclado numérico próprio, sem log do valor;
  - tela com `FLAG_SECURE` e `secureText` opcionais.
  - Ao ir para o background, sugerimos **trancar ou borrar** se o token estiver perto de vencer. A decisão está nas perguntas.
- **Biometria:** o back não tem endpoint para ela. As opções são:
  - (a) não ter (paridade exata, recomendado na v1);
  - (b) guardar o PIN no secure storage protegido por biometria e enviá-lo ao `/verify`, como o app já faz com a senha. Isso troca "algo que se sabe" por "algo que se tem" e precisa do aval do produto (Rafael).
  - Um 422 com o PIN guardado teria de apagá-lo.
- **Offline:** o Financeiro é dado de dinheiro. Nada de escrita offline. Leitura do último Meu Financeiro em cache com o carimbo "atualizado às HH:mm" é opcional. Rascunho local da solicitação, sim.
- **Ambiente:**
  - se `FINANCE_PIN_ENFORCED` estiver falso em produção, o app funciona sem PIN, mas a UX deve exigir o PIN do mesmo jeito (o web exige);
  - um 401 do financeiro nunca pode deslogar o app (bug "loga, mas sai" do web).
- **Corretor sem saldo no formulário:** `broker-balance` exige `view-staff`. O app não sabe o saldo livre antes de enviar e depende do 400 do back (o web tem o mesmo problema).

---

## 9. Perguntas em aberto

1. `FINANCE_PIN_ENFORCED` está `true` em produção, e `api.financeiro.intellisysbr.com` responde ao app (CORS não se aplica ao app, mas há WAF ou nginx)?
2. Biometria para destravar o PIN: pode (opção b) ou fica paridade estrita (opção a)?
3. Background: trancar ao sair do app, ou manter as 2 h como no web?
4. "Para aprovar" no app entra na v1? Com quais fontes: só REQUEST, ou também PAYABLE e DEAL_COST para o gerente e diretor financeiros? E o adiantamento, que exige `feePercent`?
5. O corretor deveria ver o saldo livre antes de pedir adiantamento? Hoje `broker-balance` exige `view-staff` e o web também fica sem saldo. Seria preciso um endpoint "meu saldo" no back.
6. Anexos do corretor: aceitar o limite de 5 MB do caminho base64, ou liberar o multipart de 30 MB para `contexto=request`?
7. Plano só-Financeiro: o app passa a abrir direto no Meu Financeiro em vez de `/crm-unavailable`?
8. Sem tela no app (contas a pagar, vendas…): o deep link abre o web no navegador ou só mostra um aviso?
9. O `X-Company-ID` do app (`intellisys_selected_company_id`) é o mesmo UUID cru que o web lê de `dream_keys_selected_company_id`, e não um ID ofuscado?

## Decisões do Edson (03/10/2026)

1. **Biometria opcional** para destravar o PIN: após o 1º PIN válido, o app pode guardar o PIN no armazenamento seguro e destravar com digital/rosto (opt-in, desligável no perfil). Sem endpoint novo no back — a biometria só libera o PIN guardado, que é conferido em `/auth/pin/verify` como sempre.
2. **Trancar ao sair do app**: ao voltar do segundo plano, o Financeiro pede o PIN de novo (ou a biometria, se ligada). O token de 2 h do back continua valendo como teto.
3. **Escopo v1 = corretor + "Para aprovar"**: Meu Financeiro, Solicitações (lista/detalhe/nova), pedir adiantamento, sino do Financeiro com deep links, card "Meu dinheiro" na Home e a fila "Para aprovar" para gestor/diretor/financeiro.
4. **Plano "só Financeiro"**: o app abre direto no Meu Financeiro (substitui a tela "plano não inclui o CRM" para essas empresas).
5. API de produção conferida no ar: `https://api.financeiro.intellisysbr.com/api/v1/health` → 200 (sha e0ddd20, 02/10 22:54Z).

---

## Execução — fase 1 (03/10/2026)

Escopo: etapas 0 a 4 do §7 (cliente, PIN, gating, Meu Financeiro) + biometria opcional, trava ao sair do app e plano "só Financeiro" (decisões 1, 2 e 4). Sem mudança no back, sem commit.

### Feito

| Item | Onde (APP `lib/`) | Notas |
|---|---|---|
| Config (base URL `--dart-define=FINANCE_API_BASE_URL`, timeouts, headers) | `features/finance/core/finance_config.dart` | `settings_service.dart` passou a ler a base daqui (fonte única) |
| Cliente HTTP | `features/finance/core/finance_api_client.dart` | Bearer do CRM (renovado pela fila única do `ApiService.garantirTokenFresco`), **`X-Company-ID` em toda chamada, inclusive `/auth/*`** (não usa o `buildOutboundHeaders`), `X-Finance-Pin`, lê `x-finance-pin-token`; 428 `FINANCE_PIN_REQUIRED` tranca o store (só se o token recusado é o atual); **401 nunca desloga** (vira erro na tela, sem retry em laço); sem empresa não chama |
| Erros | `features/finance/core/finance_errors.dart` | `FinanceError` por família: `pinRequired`, `unauthorized`, `companyNoAccess`, `companyNotProvisioned` (mensagens de empresa, nunca "sem permissão"), `forbidden` (traduz `allowedRoles`), 404/409/423/429/422, rede |
| Estado do PIN | `features/finance/core/finance_pin_store.dart` | token em `FlutterSecureStorage` (chave `finance_pin_session`, apagada também em `SecureStorageService.clearTokens()`); dono = `sub` do JWT do CRM (outra pessoa no aparelho não herda); timer até o `exp`; renovação por uso (>10 min, 1 em voo; 401 tranca, rede não); **trava ao ir para o segundo plano** (`paused`/`hidden`; `inactive` não), com `holdBackgroundLock` para prompt de biometria/seletores; `clear()` no logout |
| Endpoints do PIN | `features/finance/pin/services/finance_pin_service.dart` | status, setup, verify, refresh, esqueci, redefinir; porte de `motivoPinFraco` (recusa 1111/1234 sem ida ao back) |
| Máquina de estados da tela | `features/finance/pin/controllers/finance_pin_controller.dart` | `loading → create → confirmCreate`, `enter`, `blocked` (contagem até `bloqueadoAte`), `code (6) → newPin → confirmNewPin`, `loadError`; 422 com "Restam N", 429 bloqueia, 404 em digitar → criar, 409 no setup → digitar, código errado volta ao código, `PIN_CODIGO_RECENTE` vai ao código |
| Tela do PIN | `features/finance/pin/widgets/finance_pin_view.dart` | teclado numérico próprio (o PIN não passa pelo teclado do sistema), pontos com "tremida" no erro, háptico, botão de biometria, "Esqueci meu PIN", "Sair do Financeiro" |
| Portão | `features/finance/pin/widgets/finance_pin_gate.dart` | módulo `financial_management` da empresa (sem bypass, nem master); na entrada só o PIN; depois do 1º desbloqueio o PIN cobre a tela **sem desmontá-la** (expirou, 428, voltou do segundo plano); toque renova o token |
| Biometria opcional | `features/finance/pin/services/finance_biometric_service.dart`, `pin/widgets/finance_biometric_tile.dart` | após o 1º PIN válido, convite "Destravar com digital/Face ID?" (opt-in; "Agora não" não pergunta de novo); o PIN fica no armazenamento seguro, por pessoa; a biometria só o libera e ele **sempre** passa por `/auth/pin/verify`; 422/404 com o PIN guardado o apaga; liga/desliga no **Perfil** (ligar pede o PIN uma vez); redefinir o PIN atualiza o guardado. `local_auth` e as permissões nativas (`USE_BIOMETRIC`/`USE_FINGERPRINT`, `NSFaceIDUsageDescription`, `FlutterFragmentActivity`) já existiam — nada adicionado |
| `/auth/me` + visibilidade | `features/finance/core/finance_me.dart`, `finance_visibility.dart` | cache de 60 s por empresa (cadastro, não valor); 404 = sem gating; matriz papel × tela das telas do app; `linked:false` sem gating |
| Meu Financeiro | `features/finance/meu_financeiro/{models,services,pages,widgets}` | resumo, próximos (por visão), vendas, adiantamentos, solicitações e `/auth/me` **em `Future.wait`** (teste garante as 6 chamadas em voo antes da 1ª resposta); KPIs (A receber em destaque + Recebido, Retido, Adiantamentos aprovados, Saldo devedor) que trocam a visão da lista; mensagem do topo; barra de composição; gráfico mensal; período (Tudo/Este mês/30/90 dias); busca com debounce de 400 ms; situação das vendas; "Ver mais" paginado; seletor de corretor quando `brokers > 1`; ocultar valores (preferência local); atualização a cada 60 s com a tela visível e destravada e ao destravar de novo; contador de sequência descarta resposta atrasada; 403 de papel bloqueia só a seção de adiantamentos; COMPANY_* com tela própria. Nada de valor em cache |
| Rotas | `features/finance/finance_routes.dart`; `core/routes/app_routes.dart` | `/financeiro` e `/financeiro/*` (paths do web) com o portão; na fase 1 todas abrem o Meu Financeiro |
| Menu | `shared/widgets/app_drawer.dart` | item "Meu Financeiro" com o módulo da empresa (sem `financial:access`) |
| Plano só Financeiro | `shared/services/subscription_access_gate.dart`, `features/subscriptions/pages/access_blocked_page.dart` | nova decisão `financeOnly` (`decideProductAccess`): sem CRM **e** com `financial_management` → login/splash abrem `/financeiro/meu-dashboard`; rotas de CRM redirecionam para lá; sem barra inferior. Sem CRM e sem Financeiro continua em `/crm-unavailable` |
| Logout | `shared/services/auth_service.dart` | `FinancePinStore.clear()` + `FinanceMeService.clear()` |
| fin-17 | `shared/services/module_access_service.dart` | mapa do módulo `financial_management` → `financial:access` |

Testes (`test/features/finance/`): `finance_pin_store_test` (2 h, renovação >10 min, 428, segundo plano, hold da biometria, dono, logout), `finance_api_client_test` (headers com `X-Company-ID` em `/auth/*`, token renovado, 428 tranca, 401 não desloga, COMPANY_*, rede, sem empresa), `finance_pin_controller_test` (todas as fases e erros), `finance_rules_test` (plano só Financeiro, matriz, formatação, paralelismo), `finance_pin_view_test` (widget).

### Pendente (fase 2)

- Etapa 5: drill-downs (detalhe da venda, origem do repasse, lista de assinaturas `/assinaturas`).
- Etapas 6–8: Solicitações (lista/detalhe/nova) e pedir adiantamento — os botões "Nova solicitação"/"Solicitar adiantamento"/"Ver todas" ainda não aparecem (sem item morto).
- Etapa 9: "Para aprovar" (a matriz `aprovacoes` já está em `finance_visibility.dart`).
- Etapa 10: sino `fin:` + socket + deep links `/financeiro/*` no `app_deep_link.dart`.
- Etapa 11: card "Meu dinheiro" na Home.
- Status rail da visão "a receber" e período personalizado/clique no mês do gráfico.
- Exceção por cargo da matriz: hoje só a concessão via `permissoesDoCargo` é considerada (a revogação por cargo precisa do preset do papel).
- Pergunta 1 em aberto: `FINANCE_PIN_ENFORCED` em produção — o app exige o PIN de qualquer jeito.

---

## Execução — fase 2 (03/10/2026)

Escopo: etapas 5 a 11 do §7 + o que ficou pendente da fase 1. Reusa o cliente, o PIN, o `/auth/me` e a matriz da fase 1 (nada duplicado). Sem mudança no back, sem commit.

### Feito

| Item | Onde (APP `lib/features/finance/`) | Notas |
|---|---|---|
| Drill-downs | `meu_financeiro/models/drill_models.dart`, `widgets/drill_sheets.dart`, `widgets/finance_sheet.dart` | Tocar numa venda, num repasse (com venda) ou numa ficha aguardando assinatura abre a **Consulta da venda** (`/broker-dashboard/vendas/:saleId`: imóvel, cliente, venda, cronograma, quem participa, travado). Ícone "i" nas visões a receber/recebido/retido abre **De onde vem este repasse** (`/repasses/:id/origem`: venda/título, parcela, minha fatia, descontos, o que ainda vem, adiantamento a descontar). Seção **Fichas aguardando sua assinatura** (`/assinaturas`, pedida em paralelo no lote; aparece com `aguardandoAssinatura.count > 0`). Igual ao web, não há ação de assinar aqui |
| Filtros do Meu Financeiro | `meu_financeiro/pages/meu_financeiro_page.dart` | Rail **Status** (Em conferência/Pendente/Aprovado, seleção única, só na visão a receber; trocar de visão limpa); **Personalizar** (intervalo de datas); **clique no mês do gráfico** (filtra a visão ativa; mês atual sem `from` para incluir atrasados; outro toque desfaz; esmaece os outros meses); "limpar recorte". Gráfico agora mostra 6 meses para trás e 5 à frente |
| Solicitações — lista | `solicitacoes/pages/solicitacoes_page.dart` | `/requests` + `/requests/dashboard` **em paralelo**; contadores por status (tocar filtra); período (atalhos + personalizado); busca 400 ms; "Ver mais" |
| Solicitações — detalhe | `solicitacoes/pages/solicitacao_detalhe_page.dart` | cadeia, dados, rateio, títulos gerados, anexos (anexar/remover), conversa (≤1000), cancelar (motivo ≤500, 409 recarrega), editar (PENDENTE) / corrigir e reenviar (REPROVADO) — botões pelas `permissoes` do back, com o fallback do web |
| Solicitações — nova/editar | `solicitacoes/pages/solicitacao_form_page.dart`, `models/request_rules.dart` | escolha do tipo (`/request-tipos`; motor ADIANTAMENTO_COMISSAO desvia para o adiantamento; sem tipos abre o formulário legado), cadastros em paralelo com aviso de qual lista faltou (403 de centro de custo/fornecedor do corretor esconde o campo), campos base e do tipo (todos os `kind`), cartão (cartão, data, à vista/2–24x, aviso de compra passada), rateio (±0,01), "Outros" em `notes`, valor travado com etapa aprovada, `mensagem` na correção, rascunho local por tipo/pessoa/empresa (debounce 500 ms, apagado no 201), 120 s, **timeout/409 reconfere a lista** (`acharRecemCriada`) e avisa "NÃO envie de novo", `avisoLancamento` em aviso persistente |
| Anexos | `solicitacoes/widgets/anexo_picker.dart`, `services/requests_service.dart`, `core/finance_access.dart` | **Decisão 5 MB × 30 MB (pela API atual):** o multipart `/financial/anexos/upload` (30 MB) exige `attachments:attach` **e** `assertFinanceAccess` (só ADMIN/DIRETOR_FINANCEIRO/GERENTE_FINANCEIRO/ANALISTA_FINANCEIRO/FINANCEIRO) — `contexto=request` não muda nada. Então: **corretor e gestor comercial → base64 de 5 MB** (`/requests/:id/attachments/upload`); time financeiro → multipart 30 MB + vínculo, com queda para o base64 em 403/404. Tipos PDF/JPG/PNG/WebP checados no app (o caminho base64 não confere assinatura). Foto da câmera/galeria comprimida (qualidade 80, 2400 px). Um de cada vez, depois do 201; falha vira aviso |
| Pedir adiantamento | `adiantamento/pedir_adiantamento_page.dart`, `adiantamento_rules.dart` | empresas e (`/auth/me` → `/repasses?brokerId`) em paralelo; vendas agrupadas com "a receber" (PENDING+APPROVED), multi-seleção (≤30); descrição e valor ≥ 0,01 obrigatórios; corpo **sem** `feePercent`/`capOverrideReason`; fallback sem `saleIds`; o 400 do teto aparece com o máximo do back |
| Para aprovar | `aprovacoes/{approvals_models,approvals_service,para_aprovar_page}.dart` | gate: crachá do CRM (`financial:access` ou master/admin) **e** matriz `aprovacoes` (Gestor, Diretor, Gerente/Diretor financeiro, Admin; exceção concedida/revogada); summary + fila `MEU_AVAL` + `/auth/me` em paralelo; query sem os padrões do back; detalhe (`/approvals/item`: campos, cadeia, nomes dos anexos); aprovar/recusar (motivo 5–500) um item ou vários (segurar para selecionar), lote em fatias de 10; `LANCAMENTO_EM_DOBRO` pergunta por item e reenvia com `confirmarDuplicidade`; 409 vira "já decidida por outra pessoa"; `blockedReason` exibido; sem `approvals:decide-bulk` só vê. **Adiantamento**: aprovar abre a taxa (inicia em `feePercent`, atalhos 0/5/10/20, cobrado, saldo livre do corretor com `ignoreAdvanceId`, justificativa ≤400 acima do saldo) → `/commission-advances/:id/approve`; exige `commission-advances:approve`; recusar vai pelo lote |
| Sino do Financeiro | `notificacoes/finance_notifications_controller.dart`, `notificacoes/widgets/finance_bell_button.dart`, `core/finance_deep_link.dart` | sino nas telas do módulo (Meu Financeiro, Solicitações, Para aprovar), com badge de não lidas; `GET /notifications`, lida otimista, "marcar todas"; **Socket.IO como o web** (ticket por tentativa, `/finance-socket`, websocket, backoff 2→60 s) + polling de 60 s só em primeiro plano; aviso do socket também atualiza o Meu Financeiro (debounce 1,5 s); visível com `podeVerSino`/`receiveNotifications`/itens; desliga no logout. Deep links: solicitação → detalhe (quem aprova vai para "Para aprovar" nos avisos de "sua vez"), adiantamento → Para aprovar, venda/repasse → consulta da venda, débito → Meu Financeiro; contas a pagar/receber, pipeline e conversa da venda → **aviso claro "disponível só no computador"** |
| Rotas e deep links | `finance_routes.dart`, `core/finance_route_names.dart`, `core/widgets/finance_web_only_page.dart`; `shared/utils/app_deep_link.dart` (case `financeiro`); `core/routes/app_routes.dart` (1 linha: passa a rota com query) | `/financeiro/meu-dashboard[?venda=]`, `/solicitacoes[/nova\|/:id\|/:id/editar]`, `/aprovacoes/*`, `/adiantamentos/novo`, `/vendas?saleId=`; outras `/financeiro/*` abrem a página "só no web". Push/links do sino do CRM com `/financeiro/...` agora navegam |
| Card "Meu dinheiro" | `home/meu_dinheiro_card.dart`; `features/dashboard/pages/dashboard_page.dart` (1 linha + import) | uma chamada `/repasses/earnings` (sem PIN) por montagem, sem cache; `brokers[0]` como o web; Nas minhas vendas, Já recebi, Retido, Tenho a receber, travado e adiantamento em aberto; some sem o módulo/dado; toque → Meu Financeiro |
| Botões da fase 1 | Meu Financeiro | "Nova solicitação", "Ver todas" e linhas tocáveis em Minhas solicitações; "Solicitar adiantamento" (a seção aparece mesmo vazia); atalho **Para aprovar** com a contagem do Meu aval (só com o gate) |
| Menu | `shared/widgets/app_drawer.dart` | + "Solicitações" (módulo) e "Para aprovar" (crachá + matriz pelo `/auth/me` em cache) |
| Logout | `shared/services/auth_service.dart` | também para o sino/socket e limpa o cache de cadastros |

Testes: `test/features/finance/finance_fase2_test.dart` (validações e corpo da solicitação, reconciliação 409 com MockClient, anexos 5×30 MB, regras do adiantamento, quem aprova/decide/aprova adiantamento, motivo, fatias, query, taxa/teto, deep links e rotas, títulos, backoff/origem do socket, mês do gráfico, modelos dos drill-downs, card). `finance_rules_test` passou a exigir 7 chamadas em paralelo no Meu Financeiro.

### Pendente (e por quê)

- **Saldo livre antes de pedir adiantamento:** `broker-balance` exige `view-staff`; o app mostra o "a receber" das vendas e explica que o teto é conferido no envio (mesma limitação do web). Precisa de um endpoint "meu saldo" no back (pergunta 5).
- **Baixar anexos** (da solicitação e da Central): a API guarda `s3://…` sem rota de download/presign; o app lista os nomes. Precisa de endpoint no back.
- **Conversa da venda** e telas de gestão (contas a pagar/receber, pipeline, vendas): só no web — o app mostra aviso claro.
- **Sino unificado:** o sino do Financeiro fica nas telas do módulo (não mistura com o sino do CRM, que tem paginação/categorias próprias); o sino do CRM já navega para `/financeiro/*`.
- **Central:** só a sub-aba "Meu aval" (decisão do plano); Execução/Registro seguem no web.
- **Menu "Para aprovar"** usa o `/auth/me` em cache: antes da primeira abertura do Financeiro a matriz não barra (quem tem o crachá vê o item; a tela confere e mostra o motivo se o papel não aprova).
- Revogação da matriz por **cargo** continua simplificada (fase 1).
