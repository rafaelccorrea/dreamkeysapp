# Paridade Web × Mobile — o que FALTA no app

> Gerado em 06/07/2026 cruzando o inventário completo do `imobx-front` (~200 rotas, 14 domínios)
> com o inventário completo do `dreamkeysapp` (265 arquivos Dart).
> Legenda: **[GAP]** não existe no app · **[PARCIAL]** existe mas incompleto · `[master]`/`[admin]`/`[config]` = público-alvo restrito no web.

---

## A. DOMÍNIOS INTEIROS AUSENTES NO MOBILE

### A1. Locações (módulo `rental_management`) [GAP]
- Gestão de locações: lista, criar, detalhe, editar (`/rentals`)
- Dashboard de locações
- **Fichas de locação** (lista + editor + link público para o cliente)
- Inquilinos (variante de clientes `?type=renter`)
- Cotação de seguros (`/insurance/quote`)
- Fluxos de locação (workflows configuráveis) [config]
- Análise de crédito (+ settings) [config]
- Régua de cobrança (+ regras CRUD) [config]

### A2. Financeiro ERP (módulo `financial_management`, empresa União) [GAP]
- Dashboard financeiro e Relatórios
- Dia a dia: Contas a Pagar, Contas a Receber, Recorrentes, Contas Bancárias
- Ciclo da venda: Vendas, Confissão de Dívidas (pipeline), Comissões por Tier, Metas & Ranking, Dashboard de Vendas (BI), Repasses
- Aprovações: Solicitações (+ dashboard + detalhe), Autonomia
- Configuração: Cadastros, Orçamento, Hierarquia, Equipes & Tiers, Administração

### A3. Relatórios de Visita (módulo `visit_report`) [GAP]
- Lista de visitas (`/visits`), criar/editar relatório de visita
- Gestão de relatórios (`/visit-reports`)
- Assinatura pública do relatório pelo cliente (link `/public/assinatura-visita/:token`)
- Visitas no kanban (`/kanban/visit-reports`)

### A4. Condomínios & Empreendimentos [GAP]
- CRUD completo de condomínios + detecção de duplicados
- CRUD de empreendimentos + página de detalhe
- (no app hoje só existem como *seletor* dentro do cadastro de imóvel)

### A5. Gamificação / Prêmios / Competições [GAP] [OCULTAR DO MENU — Edson (16/07/2026): Gamificação E Prêmios/Resgates ocultos como no web; implementar telas + rotas, mas SEM itens no drawer]
- Dashboard de gamificação (+ settings [config])
- Catálogo de resgates, Meus resgates, Aprovar resgates, Gerenciar/criar/editar recompensas
- Competições (CRUD) + prêmios de competições
- (no app existe apenas a seção "conquistas" no dashboard)

### A6. Metas (Goals) [admin] [GAP]
- CRUD de metas + analytics por meta

### A7. MCMV — gestão [GAP]
- Leads MCMV (lista + detalhe), Blacklist, Templates
- (no app o MCMV aparece só como campos nos formulários de cliente/imóvel)

### A8. Patrimônio / Assets (módulo `asset_management`) [GAP]
- CRUD de ativos + detalhe

### A9. Checklists standalone [GAP]
- Lista, criar, detalhe, editar (`/checklists`)
- (no app só existe seção de checklist dentro do detalhe do imóvel)

### A10. Automações (módulo `automations`) [admin] [GAP]
- Lista, criar, detalhe, histórico de execuções

### A11. Tickets / Suporte / Ajuda [GAP]
- Meus tickets (+ detalhe), gestão dev (União), Central de Ajuda/FAQ
- (existe repo `intellisys-tickets` — avaliar reuso)

### A12. WhatsApp inbox + SDR [GAP]
- Caixa de conversas WhatsApp (`/whatsapp`)
- Dashboard SDR e configurações do SDR IA [config]
- Pré-atendimento com IA, templates, lead claim

### A13. Central de Integrações [config] [GAP]
- Hub de integrações (status configurada/pendente, progresso X/Y)
- Configs: WhatsApp (oficial/QR Baileys/monitoramento), Chat Pro, Meta Campaigns (+ campanhas, leads, logs de webhook, anúncios, agendadas), Google Ads, GA4, Instagram (+ automações/logs/dashboard), Grupo ZAP, Properties API, Chaves na Mão, Imovelweb, Autentique, Lead Distribution (+ análise), Custom Leads webhook, Ficha Webhooks (+ docs), Zezin (config/ask), Políticas de notificação de leads
- **Zezin (assistente IA conversacional)** — candidato natural a mobile

### A14. Site público / Analytics [GAP]
- Meu Site (config do site público), Link in Bio
- Análise Multicanal (`/analytics/public-site`)
- Analytics avançado e Property Analytics (`/dashboard/advanced-analytics`, `/dashboard/property-analytics`)
- Comparar Corretores / Comparar Equipes

### A15. Assinaturas & plataforma [admin/master] [GAP]
- Minha Assinatura, Gerenciar Assinaturas (+ detalhe), Planos, Plano Customizado
- Cobrança do sistema (BillingControl) [master]
- Monitoria Online [master], Domínios de sites públicos [master]
- Hierarquia organizacional (`/hierarchy`), Unidades/filiais (`/units`)
- Backups / exportação de leads (`/crm/leads/exportacao`)
- Registro de conta (register), onboarding "criar primeira empresa"

---

## B. FEATURES QUE EXISTEM NO APP, MAS INCOMPLETAS

### B1. Fichas de venda [PARCIAL]
- [GAP] **Dashboard de fichas** (KPIs, VGV por corretor/equipe/unidade, ranking) — serviço `getStats` já existe no app, sem UI
- [GAP] Modo "Relatório" da lista + exportação do relatório
- [GAP] Envio para assinatura pelo app (modal Autentique: signatários obrigatórios da empresa + detectados do PDF, link WhatsApp/copiar, reenvio em lote, cancelar assinaturas p/ reedição)
- [GAP] Baixar PDF (sem assinatura) e PDF assinado (único/ZIP)
- [GAP] Transferir responsabilidade / trocar equipe / ver usuários vinculados / ver motivo de cancelamento
- [GAP] Config de signatários obrigatórios + lembretes WhatsApp + "reenviar agora" [config]
- [GAP] Config de unidades de venda [config]
- [PARCIAL] Detalhe é read-only "Fase 1" (web permite edição rica por etapa)
- Divergência: modal de tipo no app = imóvel/empreendimento; web = Terceiros/Lançamento/Casa Minha Vida — alinhar

### B2. Fichas de proposta [PARCIAL]
- [GAP] Dashboard de propostas (KPIs, série temporal, export Excel/PDF)
- [GAP] Histórico da proposta (modal)
- [GAP] Contraproposta (`contraPropostaApi`)
- [GAP] PDF por etapa (Etapa 1/2/3) — app tem PDF, conferir por etapa
- [GAP] Indicadores de etapa de assinatura (Comprador/Proprietário/Corretor) e trava de edição por snapshot de etapa assinada

### B3. Comissões [PARCIAL — hoje 100% leitura]
- [GAP] Aprovar / Rejeitar (com motivo) / Processar pagamento / Editar comissão
- [GAP] Calculadora & configuração pessoal de comissão (taxas, custos, impostos, benefícios, meta mensal)

### B4. CRM / Kanban [PARCIAL — board forte, gestão fraca]
- [GAP] Lista de funis (`/kanban/funis`) + criar/editar/excluir/duplicar funil
- [GAP] Funil global e Visão unificada
- [GAP] Leads perdidos: pool + recuperação + config on/off
- [GAP] Distribuir leads em massa (assistente: redistribuir/transferir com rodízio)
- [GAP] Permissões do kanban por usuário (`/kanban/permissions`) [config]
- [GAP] Regras de cor dos cards [config]
- [GAP] Métricas & Insights (páginas + insights IA por coluna)
- [GAP] Validações de coluna, Ações de coluna, Campos customizados, Distribuição por ociosidade [config]
- [GAP] Pastas de documentos do CRM (+ progresso da pasta no card)
- [GAP] Sub-negociação (criar deal filho)
- [GAP] Histórico de projetos (por equipe/projeto)
- [GAP] Renomear funil inline, sincronizar pessoas envolvidas, chips de meta/setor/webhook
- [GAP] Indicador de colaboração em tempo real (outro usuário movendo card)
- [GAP] Copiar/compartilhar resumo do card (texto WhatsApp)

### B5. Imóveis [PARCIAL — CRUD forte, periferia ausente]
- [GAP] Mapa explorador (heatmap + clusters)
- [GAP] Relatório de captações
- [GAP] Despesas do imóvel: telas criar/editar (app exibe seção)
- [GAP] Análise preditiva (IA) por imóvel (modal valor/tempo de venda)
- [GAP] Configs: fluxo de aprovação, formulário de cadastro, campos protegidos [config]
- [GAP] Chat/inbox de conversas de aprovação (web tem inbox dedicado)
- [GAP] Fila "Solicitações de edição" e "Autorização do proprietário" — conferir cobertura das 6 abas do web
- [GAP] Exportação da fila de aprovações com escopo/filtros
- [GAP] Toggle "somente excluídos" (auditoria) e "ativar/desativar imóvel"
- [GAP] Galeria: vídeo do imóvel (1×, 150MB, 1:40, thumbnail), crop 1:1 obrigatório, reordenar por arrastar (+ multi-seleção em bloco), definir capa, toggle "mostrar no site" por foto, HEIC/HEIF
- [GAP] Marca d'água: modal automático se empresa sem watermark
- [GAP] Copiar link do site / "Ver no site"
- [GAP] Busca por localização com autocomplete (condomínio/rua/bairro) + banners de escopo removíveis
- [GAP] Nota de qualidade (score) como filtro min/máx + modal explicativo (app tem painel de score no form)
- [GAP] Galeria global (`/gallery`) e página fullscreen dedicada

### B6. Clientes [PARCIAL — quase paridade]
- [GAP] Resumo de conversas (IA) e Classificação do lead (IA) no detalhe
- [GAP] Jobs de importação: status, planilha de erros para download
- [GAP] Variante Inquilinos (`?type=renter`)
- [GAP] Indicadores de matches/cônjuge/origem do lead no card

### B7. Agenda [PARCIAL]
- [GAP] Visões semana/dia (app tem mês/agenda)
- [GAP] "Ver agendamentos de": toda a empresa / multi-seleção de colaboradores (admin/gestor)
- [GAP] Eventos recorrentes (chip/lógica de recorrência)
- [GAP] Preferência "permitir compromissos simultâneos"
- [GAP] Card "Próximo compromisso" com countdown de urgência (app tem spotlight simples)

### B8. Colaboradores [PARCIAL]
- [GAP] **Criar usuário** (app só edita) — inclui validação email/CPF, perfis de permissão, tags
- [GAP] Vincular usuário a outras empresas (transferência entre empresas do dono)
- [GAP] Resetar 2FA de usuário [admin]
- [GAP] Desativação com redistribuição de leads + reatribuição de imóveis (modal com resumo)
- [GAP] Toggle visibilidade no site público (isAvailableForPublicSite)
- [GAP] Widget de assentos/cobrança (usuários inclusos/adicionais/custo)
- [GAP] Filtros extras: com/sem avatar, nunca acessou, faixa de último login; dot de presença; badge "Na empresa" (check-in)
- [GAP] **Equipes: criar/editar/excluir + gerir membros** (serviço pronto no app, sem UI) + aviso de exclusão em cascata de funis + "equipes por usuário"

### B9. Perfil / Empresa [PARCIAL]
- [GAP] **Editar empresa** (logo, CNPJ, ViaCEP, lat/long GPS/geocode do check-in, marca d'água) [admin]
- [GAP] Criar empresa / excluir filial [admin]
- [GAP] Toggles por empresa: **App para todos** e **TOTP obrigatório** (recém-criados no web) [admin]
- [GAP] Sessões ativas (dispositivos conectados + encerrar sessão)
- [GAP] Configurar 2FA/TOTP do próprio usuário pelo app (setup; hoje só login com código)

### B10. Check-in [DESPRIORIZADO — Edson, 06/07/2026: "não usamos atualmente, segundo plano"]
- ~~[GAP] Configurações (habilitar, raio, duração)~~ — não investir aqui por ora

### B11. Chat [PARCIAL]
- [GAP] Reações a mensagens
- [GAP] Responder/quote (com scroll até a original)
- [GAP] Emoji picker, GIFs, stickers
- [GAP] Silenciar conversa (mute)
- [GAP] Apagar conversa "para todos"
- [GAP] Sala de suporte dedicada (type: support)
- [GAP] Quick Requests (solicitações integradas a fichas/propostas)
- [GAP] Indicador "digitando…" e presença online (conferir paridade do socket)

### B12. Documentos & Assinaturas [PARCIAL]
- [GAP] Fluxo "Enviar documento para assinatura" (página dedicada no web)
- [GAP] Pastas de documentos do CRM
- [GAP] Ações em massa da biblioteca (conferir: excluir múltiplos existe)

### B13. Anotações [PARCIAL]
- [GAP] **Editar anotação** (app cria/fixa/arquiva/exclui, não edita)

### B14. Dashboard [PARCIAL — bom, mas sem os módulos analíticos]
- [GAP] Funil de conversão interativo (clique na etapa → modal → navega)
- [GAP] Vendas × Meta × Projeção (gráfico com forecast)
- [GAP] Barra de saúde do pipeline (cards parados, atrasadas, vencem hoje, meta %, projeção)
- [GAP] Top performers, leads recentes, origem dos leads (donut), tipos de imóvel/região/integrações
- [GAP] Filtro multi-empresa no dashboard [admin/master]
- [GAP] Dashboards por papel (gestor tem visão de equipe própria no web)

### B15. Notificações & transversais [PARCIAL]
- [GAP] Troca automática de empresa ao tocar notificação de outra empresa
- [GAP] Cobertura dos ~25 tipos de notificação com deep-link (conferir mapa por tipo)
- [GAP] **Seletor de empresa para admin/owner** — no app só `master` troca de empresa; no web todo usuário multi-empresa tem o seletor no header
- [GAP] Busca global de leads (header do web)
- [GAP] Configurações: idioma e fuso horário são read-only no app
- [GAP] Preferências de notificação de leads [config]

---

## C. OBSERVAÇÕES PARA PRIORIZAÇÃO

1. **Ganhos rápidos** (serviço já existe no app, falta UI): dashboard de fichas de venda, CRUD de equipes, editar anotação, configurações de check-in, criar usuário.
2. **Alto impacto para corretor em campo**: relatórios de visita (com assinatura do cliente), mapa de imóveis, envio de assinaturas da ficha pelo celular, WhatsApp inbox, Zezin.
3. **Coisas de configuração pesada** [config] fazem menos sentido no celular — candidatas a ficarem só no web por decisão de produto (integrações, regras de cobrança, workflows, campos customizados).
4. **[master]** (billing da plataforma, monitoria, domínios) provavelmente nunca precisa ir para o app.
5. Divergências a alinhar (não são gaps, são diferenças): tipos de ficha de venda (app: imóvel/empreendimento × web: Terceiros/Lançamento/CMV) e drawer do app esconde features prontas (chat, documentos, vistorias, chaves, matches) que no web também são ocultas — confirmar se é intencional.
