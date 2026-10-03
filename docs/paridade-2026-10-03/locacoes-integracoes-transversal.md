# Paridade web × app: Locações/Docs, Integrações, Transversal (re-verificação de 03/10/2026)

Fonte: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, linhas 1242–1672. Código conferido no estado atual do app (HEAD `675b686`, árvore limpa). Desde 29/09 não houve commits em `rentals`, `keys`, `condominiums`, `assets`, `tickets` nem em `notes_service`. Em `documents` houve 3 commits.

Legenda: **Back?** indica se depende de deploy do back (s/n). **Esforço**: P/M/G. **Quebra?** marca o que corrompe dado, devolve 400/403 ou trava o usuário. Os caminhos de evidência são relativos a `lib/`.

## Resumo por domínio

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

### P0 que ainda faltam
- **loc-01**: Locações sem entrada no menu. Fora do escopo (decisão de 29/09).
- **loc-02**: parcela criada no app sai sem boleto/PIX. Fora do escopo (decisão de 29/09).
- **integ-F1** (proposta de promoção a P0): os presets do app não têm `lead_form`. Salvar seções com `homeBlocks` vazio apaga o formulário de captação do site público.

### Quebra o app hoje (fora os P0)
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

## 1. Locações, Chaves, Patrimônio, Condomínios, Empreendimentos, Documentos, Anotações, Tickets

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

## 2. Integrações, Meu Site, Link in Bio, Portais

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

## 3. Transversal

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

### Correção extra (03/10/2026, sessão líder)

- **chaves-F1 — Editar chave abria o formulário vazio** ✅: `CreateKeyPage` nunca buscava a chave na edição; o formulário vinha em branco e salvar sobrescrevia nome/descrição/local/observações com vazio. Agora carrega por `getKeyById` antes de mostrar (com carregando, erro e "Tentar de novo"); o imóvel aparece só para consulta, porque o `UpdateKeyDto` do back não troca o imóvel de uma chave. Arquivo: `lib/features/keys/pages/create_key_page.dart`.
