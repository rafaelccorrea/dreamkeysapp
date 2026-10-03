# Paridade web × app — Ficha de Venda e Ficha de Proposta (03/10/2026)

## Execução (03/10/2026, no app) — status

1ª rodada (03/10, manhã): itens P0/P1. 2ª rodada (03/10, tarde): todos os P2, rascunho da proposta, trava por tela e a correção do back (P4). **Nada pendente**: toda linha abaixo está ✅ ou "não se aplica" com o motivo. `flutter analyze` sem erro/aviso novo nos arquivos tocados (os erros do analyze geral estão em `features/properties`, frente de Imóveis em andamento); `flutter test` 100% (343 testes na suíte, que inclui os das outras frentes). Back: teste novo do módulo passando e typecheck sem erro no recorte. Nada testado em aparelho.

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

### 3ª rodada (03/10, manhã) — auditoria cética

Fonte: `fichas-auditoria-cetica.md`. A coluna "Status" de cada linha de lá diz como ela ficou.
- **10 P1 ✅:**
  - V-A1, com barreira também no back;
  - V-C1, V-C2, V-C3 (120 s);
  - V-L1, D-1, D-2, P-L1, P-C1;
  - P-C2, corrigido no app e no web: proposta finalizada não é mais editável, coerente com o back.
- **P2:** quase todos ✅.
  - Pendentes por prazo: V-L4 (modo "Relatório fichas" na linha) e V-L9 (paginação).
  - Diferenças conscientes: V-A5 e P-L4 ("Assinar" só abre o link do back) e P-L2 (o back tem `reenviar-email`).
- **Correção deste doc:** o "reenvio por e-mail" da proposta, que aparece em "Confirmado sem diferença na proposta" mais abaixo, só existe no app. Ele fica como diferença consciente porque a rota existe no back.

### Revisão tela a tela (2ª rodada, 03/10) — achados novos e como ficaram

| # | Achado | Status |
|---|---|---|
| R1 | Venda — detalhe montava o menu com o `GET /:id`, que não traz `assinaturasTotal` (só a listagem traz): "Editar" liberado com assinaturas ativas, "Cancelar assinaturas (reenvio)" e "Cancelar todas" sumiam | ✅ `saleFormComResumoDeAssinaturas` (`sale_form_list_display.dart`): o detalhe usa as contagens de `listSignatures` (mesma conta do back: só canceladas fora) nas regras, no menu e no `canInvalidate` da folha |
| R2 | Venda — "Apenas excluídas" restaurado/enviado sem `sale_form:view_all` (back 403) | ✅ Só restaura e só envia `listDeletedOnly` com `view_all`, como o web |
| R3 | Venda — lista abria com só `view_team`/`view_all` (back exige `SALE_FORM_VIEW`) | ✅ Tela exige `sale_form:view` (rota do web e `GET /sistema/fichas-venda`). O drawer é da frente do Financeiro e não foi tocado; quem chegar lá sem `view` vê "sem acesso", não um 403 |
| R4 | Venda — faltava "Alterar tipo da ficha" | ✅ Barra "tipo · equipe — Alterar tipo" no topo da aba Geral (criação e edição fora de processamento/finalizada, `canChangeSaleFormType`); abre o modal de tipo em modo alteração (já marcado, "Aplicar"), mantém o que foi preenchido |
| R5 | Venda — edição não conferia o status recém-lido | ✅ `saleFormEdicaoBloqueada`: finalizada/cancelada/excluída/em processamento → avisa e troca para o detalhe (só leitura), como o web ao abrir `/editar` |
| R6 | Venda — limite de 10 vinculados podia ser ultrapassado pelos participantes da comissão | ✅ `saleFormVinculadosErro`: o salvar barra quando vinculados + participantes > 10 e leva à aba Vincular. Diferença de forma consciente: o app escolhe participante em qualquer usuário e o vincula ao salvar (o web só lista vinculados) — o resultado gravado é o mesmo |
| R7 | Venda — modal de tipo já vinha com "terceiros" | ✅ Nada marcado; "Continuar" exige tipo e equipe (web) |
| R8 | Venda — "Trocar equipe" sem os filtros do web | ✅ `saleFormEquipeElegivel(paraTrocarEquipe: true)`: `useInSaleForms !== false` e sem equipe pessoal |
| R9 | Venda — reenvio individual por WhatsApp só olhava `canResend` | ✅ Exige também `autoSendEnabled` (mesma trava do lote). O individual é a mais no app (o web só tem o lote); mantido porque usa a rota oficial do back |
| R10 | Venda — "Cancelar todas" no app exige também `sale_form:update`, ficha não cancelada e assinatura ativa (web: só `canInvalidateSignatures`) | **Não se aplica** (diferença consciente): o `POST :id/invalidar-assinaturas` exige `SALE_FORM_UPDATE` e recusa sem assinatura ativa; o app só esconde o que o back recusaria |
| R11 | Venda — "Cancelar ficha" só existe no app | **Não se aplica** (decisão anterior mantida): usa o `PATCH :id/cancelar` oficial, nunca em finalizada (lá vale o distrato, como no web) |
| R12 | Venda — anexos: o modal do web não está em nenhuma tela; o app libera aprovar/rejeitar também para `master` | **Não se aplica**: o app é hoje a única tela de anexos da ficha; `master` passa em todas as permissões (`role_access_rules.dart`), igual ao back |
| R13 | Venda — app trava 120 parcelas (web não); app não manda vendedor/imóvel em Lançamento/MCMV | **Não se aplica**: 120 é o `@Max` do `ParcelamentoComissaoDto` do back (o web só descobre no erro); campo omitido mantém o gravado, mesmo resultado |

Somente análise; nenhum código foi alterado. Base: código atual dos três repos (app `dreamkeysapp/lib`, web `intellisys-CRM/src`, back `intellisys-CRM-Back/src`, este último em sincronia com `origin/master`, HEAD `0a666b14` de 02/10). O deploy do back não foi conferido em produção: "depende do back = s" quer dizer que a rota ou o DTO já existe no `master` do back. Nada foi testado em aparelho.

## Resumo (da análise inicial — todos os achados abaixo já foram resolvidos, ver "Execução")

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

## Tabela — pendências do card do funil

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

## Tabela — diferenças novas (comparação tela a tela)

### Ficha de venda

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

### Ficha de proposta

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

## Ordem de execução sugerida (executada inteira em 03/10 — ver "Execução" no topo)

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
