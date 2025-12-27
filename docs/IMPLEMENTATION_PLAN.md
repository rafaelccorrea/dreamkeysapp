# 📋 Plano de Implementação - App Dream Keys Corretor

## 🎯 Visão Geral

Este documento organiza a implementação do aplicativo em etapas progressivas, priorizando funcionalidades essenciais e construindo sobre elas de forma incremental.

---

## ✅ Etapa 0: Concluída

### Status: ✅ COMPLETO

- [x] **Autenticação Básica**
  - [x] Tela de Login
  - [x] Integração com API (`/auth/login`)
  - [x] Validação de formulário
  - [x] Tratamento de erros
  - [x] Loading overlay com animação Lottie
  - [x] Navegação para Dashboard após login
  - [x] Logout

- [x] **Biometria**
  - [x] Verificação de disponibilidade
  - [x] Login com biometria
  - [x] Armazenamento seguro de credenciais
  - [x] Checkbox para salvar credenciais

- [x] **Estrutura Base**
  - [x] Organização de pastas (core, features, shared)
  - [x] Sistema de temas (light/dark mode)
  - [x] Rotas e navegação
  - [x] Splash screen
  - [x] Dashboard básico

---

## 🚀 Etapa 1: Dashboard e Dados do Usuário

### Prioridade: ALTA | Estimativa: 3-5 dias

#### 1.1 Dashboard Completo
- [ ] Integrar API do Dashboard (`GET /dashboard/user`)
- [ ] Cards de estatísticas:
  - [ ] Propriedades
  - [ ] Clientes
  - [ ] Compromissos
  - [ ] Comissões
  - [ ] Tarefas
- [ ] Performance e Ranking
- [ ] Gamificação (pontos, nível, conquistas)
- [ ] Atividades recentes
- [ ] Compromissos próximos
- [ ] Metas mensais (gráficos)
- [ ] Métricas de conversão

#### 1.2 Serviços e Modelos
- [ ] Criar `DashboardService`
- [ ] Criar modelos de dados (DashboardResponse, Stats, Performance, etc.)
- [ ] Cache local dos dados do dashboard
- [ ] Atualização automática/refresh

#### 1.3 Componentes Visuais
- [ ] Cards de estatísticas reutilizáveis
- [ ] Gráficos de performance (usando charts)
- [ ] Timeline de atividades
- [ ] Lista de compromissos
- [ ] Progresso de metas (barras, gráficos)

---

## 🏠 Etapa 2: Gestão de Propriedades

### Prioridade: ALTA | Estimativa: 5-7 dias

#### 2.1 Listagem de Propriedades
- [ ] Tela de listagem com paginação
- [ ] Filtros (status, tipo, cidade, preço)
- [ ] Busca por título/código/endereço
- [ ] Card de propriedade (imagem, título, preço, status)
- [ ] Pull-to-refresh
- [ ] Loading states

#### 2.2 Detalhes da Propriedade
- [ ] Tela de detalhes completa
- [ ] Galeria de imagens (carrossel)
- [ ] Informações básicas (tipo, status, preço)
- [ ] Endereço completo
- [ ] Detalhes (quartos, banheiros, área, etc.)
- [ ] Características/features
- [ ] Documentos associados
- [ ] Despesas/expenses
- [ ] Clientes relacionados
- [ ] Ações (editar, marcar como vendido/alugado)

#### 2.3 CRUD de Propriedades
- [ ] Tela de criar propriedade
- [ ] Formulário completo com validações
- [ ] Upload de imagens múltiplas
- [ ] Seleção de características
- [ ] Tela de editar propriedade
- [ ] Excluir propriedade (com confirmação)

#### 2.4 Serviços e Modelos
- [ ] Criar `PropertyService`
- [ ] Modelos de dados (Property, PropertyList, PropertyFilters)
- [ ] Upload de imagens
- [ ] Cache de propriedades

---

## 👥 Etapa 3: Gestão de Clientes

### Prioridade: ALTA | Estimativa: 4-6 dias

#### 3.1 Listagem de Clientes
- [ ] Tela de listagem com paginação
- [ ] Filtros (tipo: comprador/vendedor, status)
- [ ] Busca por nome/email/telefone
- [ ] Card de cliente (nome, tipo, contato)
- [ ] Indicador de propriedades relacionadas

#### 3.2 Detalhes do Cliente
- [ ] Tela de detalhes completa
- [ ] Informações de contato
- [ ] Dados pessoais (CPF/CNPJ)
- [ ] Endereço
- [ ] Preferências de busca
- [ ] Propriedades relacionadas
- [ ] Histórico de notas
- [ ] Timeline de interações

#### 3.3 CRUD de Clientes
- [ ] Tela de criar cliente
- [ ] Formulário com validações (CPF/CNPJ)
- [ ] Definir preferências de busca
- [ ] Tela de editar cliente
- [ ] Adicionar/editar notas

#### 3.4 Serviços e Modelos
- [ ] Criar `ClientService`
- [ ] Modelos de dados (Client, ClientList, ClientPreferences)
- [ ] Validações de CPF/CNPJ
- [ ] Cache de clientes

---

## 📅 Etapa 4: Agenda e Compromissos

### Prioridade: MÉDIA | Estimativa: 4-5 dias

#### 4.1 Visualização de Agenda
- [ ] Tela de agenda (semanal/mensal)
- [ ] Lista de compromissos do dia
- [ ] Filtros por tipo e status
- [ ] Indicadores visuais (cor por tipo/status)

#### 4.2 CRUD de Compromissos
- [ ] Tela de criar compromisso
- [ ] Formulário com seleção de cliente e propriedade
- [ ] Seleção de data/hora
- [ ] Tipo de compromisso (visita, reunião, vistoria, assinatura)
- [ ] Tela de detalhes do compromisso
- [ ] Editar compromisso
- [ ] Cancelar compromisso (com motivo)

#### 4.3 Ações sobre Compromissos
- [ ] Confirmar compromisso
- [ ] Concluir compromisso (com notas e próximos passos)
- [ ] Reagendar compromisso
- [ ] Notificações de lembretes

#### 4.4 Serviços e Modelos
- [ ] Criar `AppointmentService`
- [ ] Modelos de dados (Appointment, AppointmentList)
- [ ] Integração com calendário do dispositivo (opcional)

---

## 🎯 Etapa 5: Match de Imóveis

### Prioridade: MÉDIA | Estimativa: 3-4 dias

#### 5.1 Listagem de Matches
- [ ] Tela de matches
- [ ] Cards de match (imóvel + cliente + score)
- [ ] Razões do match
- [ ] Filtros por status

#### 5.2 Ações sobre Matches
- [ ] Aceitar match
- [ ] Rejeitar match (com motivo)
- [ ] Ignorar match
- [ ] Visualizar detalhes do match

#### 5.3 Notificações de Match
- [ ] Notificação de novos matches
- [ ] Badge de contagem de matches pendentes

#### 5.4 Serviços e Modelos
- [ ] Criar `MatchService`
- [ ] Modelos de dados (Match, MatchList)

---

## 💰 Etapa 6: Comissões e Financeiro

### Prioridade: MÉDIA | Estimativa: 4-5 dias

#### 6.1 Listagem de Comissões
- [ ] Tela de comissões
- [ ] Filtros por status e período
- [ ] Resumo total (pendentes, aprovadas, pagas)
- [ ] Cards de comissão (imóvel, cliente, valor, status)

#### 6.2 Detalhes da Comissão
- [ ] Tela de detalhes
- [ ] Informações do imóvel e cliente
- [ ] Breakdown de valores
- [ ] Histórico de status
- [ ] Informações de pagamento

#### 6.3 Cálculo de Comissão
- [ ] Tela/calculadora de comissão
- [ ] Input de preço de venda
- [ ] Percentual de comissão
- [ ] Divisão entre corretores
- [ ] Cálculo de impostos
- [ ] Valor líquido

#### 6.4 Serviços e Modelos
- [ ] Criar `CommissionService`
- [ ] Modelos de dados (Commission, CommissionSummary)

---

## 💬 Etapa 7: Chat e Comunicação

### Prioridade: MÉDIA | Estimativa: 5-7 dias

#### 7.1 Listagem de Conversas
- [ ] Tela de conversas
- [ ] Cards de conversa (nome, última mensagem, não lidas)
- [ ] Indicador de não lidas
- [ ] Ordenação por última mensagem

#### 7.2 Tela de Chat
- [ ] Interface de chat
- [ ] Lista de mensagens (ordenada por data)
- [ ] Input de mensagem
- [ ] Envio de mensagem de texto
- [ ] Envio de arquivos/imagens
- [ ] Indicador de digitação
- [ ] Indicador de lido/entregue
- [ ] Scroll automático para última mensagem

#### 7.3 WebSocket/Real-time
- [ ] Integração com Socket.IO
- [ ] Receber mensagens em tempo real
- [ ] Indicador de digitação em tempo real
- [ ] Status online/offline dos usuários
- [ ] Notificações de novas mensagens

#### 7.4 Tipos de Chat
- [ ] Chat direto (corretor para cliente)
- [ ] Chat relacionado a propriedade
- [ ] Chat em grupo (se aplicável)

#### 7.5 Serviços e Modelos
- [ ] Criar `ChatService`
- [ ] Integração com Socket.IO client
- [ ] Modelos de dados (Conversation, Message)
- [ ] Cache local de mensagens

---

## 📋 Etapa 8: Kanban e Tarefas

### Prioridade: BAIXA | Estimativa: 4-5 dias

#### 8.1 Listagem de Tarefas
- [ ] Tela de listagem (lista ou kanban)
- [ ] Filtros por status, prioridade, responsável
- [ ] Cards de tarefa

#### 8.2 Visualização Kanban
- [ ] Board Kanban (To Do, In Progress, Done)
- [ ] Arrastar e soltar tarefas (drag & drop)
- [ ] Atualização de status ao arrastar

#### 8.3 CRUD de Tarefas
- [ ] Criar tarefa
- [ ] Editar tarefa
- [ ] Excluir tarefa
- [ ] Atribuir responsável
- [ ] Definir prioridade e data de vencimento
- [ ] Vincular a propriedade/cliente

#### 8.4 Serviços e Modelos
- [ ] Criar `TaskService`
- [ ] Modelos de dados (Task, TaskList, KanbanBoard)

---

## 🎯 Etapa 9: Metas e Performance

### Prioridade: BAIXA | Estimativa: 3-4 dias

#### 9.1 Visualização de Metas
- [ ] Tela de metas
- [ ] Cards de meta (título, progresso, porcentagem)
- [ ] Gráficos de progresso
- [ ] Filtros por tipo e status

#### 9.2 CRUD de Metas
- [ ] Criar meta
- [ ] Editar meta
- [ ] Visualizar detalhes da meta

#### 9.3 Performance Individual
- [ ] Tela de performance
- [ ] Gráficos de evolução
- [ ] Comparação com período anterior
- [ ] Ranking e posição

#### 9.4 Serviços e Modelos
- [ ] Criar `GoalService` e `PerformanceService`
- [ ] Modelos de dados (Goal, Performance, Ranking)

---

## 🏆 Etapa 10: Gamificação

### Prioridade: BAIXA | Estimativa: 3-4 dias

#### 10.1 Status de Gamificação
- [ ] Tela de gamificação
- [ ] Pontos totais e nível atual
- [ ] Barra de progresso para próximo nível
- [ ] Breakdown de pontos por categoria

#### 10.2 Conquistas
- [ ] Lista de conquistas
- [ ] Conquistas desbloqueadas vs disponíveis
- [ ] Detalhes de cada conquista

#### 10.3 Ranking
- [ ] Tela de ranking
- [ ] Ranking semanal/mensal/anual
- [ ] Posição atual destacada
- [ ] Top 10/20 corretores

#### 10.4 Serviços e Modelos
- [ ] Criar `GamificationService`
- [ ] Modelos de dados (GamificationStatus, Achievement, Ranking)

---

## 📄 Etapa 11: Documentos

### Prioridade: BAIXA | Estimativa: 3-4 dias

#### 11.1 Listagem de Documentos
- [ ] Tela de documentos
- [ ] Filtros por entidade (propriedade, cliente) e tipo
- [ ] Cards de documento (nome, tipo, tamanho, data)

#### 11.2 Upload de Documentos
- [ ] Upload de arquivo
- [ ] Seleção de entidade associada
- [ ] Preview de imagem (se aplicável)
- [ ] Progresso de upload

#### 11.3 Visualização de Documentos
- [ ] Visualizar documento (PDF, imagem)
- [ ] Download de documento
- [ ] Excluir documento

#### 11.4 Assinatura Digital (Futuro)
- [ ] Preparação para integração com Assinafy
- [ ] Tela de envio para assinatura
- [ ] Status de assinatura

#### 11.5 Serviços e Modelos
- [ ] Criar `DocumentService`
- [ ] Modelos de dados (Document, DocumentList)
- [ ] Upload de arquivos

---

## 🔑 Etapa 12: Chaves e Visitas

### Prioridade: BAIXA | Estimativa: 2-3 dias

#### 12.1 Listagem de Chaves
- [ ] Tela de chaves
- [ ] Filtros por status (disponível, emprestada)
- [ ] Cards de chave (propriedade, código, status)

#### 12.2 Gestão de Chaves
- [ ] Solicitar chave (com data de retorno e motivo)
- [ ] Devolver chave
- [ ] Histórico de empréstimos

#### 12.3 Serviços e Modelos
- [ ] Criar `KeyService`
- [ ] Modelos de dados (Key, KeyList)

---

## 👤 Etapa 13: Perfil e Configurações

### Prioridade: MÉDIA | Estimativa: 2-3 dias

#### 13.1 Perfil do Usuário
- [ ] Tela de perfil
- [ ] Visualizar informações
- [ ] Editar informações (nome, telefone)
- [ ] Upload de avatar
- [ ] Alterar senha

#### 13.2 Configurações
- [ ] Tela de configurações
- [ ] Notificações (email, push, SMS)
- [ ] Preferências de notificação (matches, mensagens, lembretes)
- [ ] Idioma
- [ ] Timezone

#### 13.3 Serviços e Modelos
- [ ] Criar `ProfileService` e `SettingsService`
- [ ] Modelos de dados (Profile, Settings)

---

## 🔔 Etapa 14: Notificações

### Prioridade: MÉDIA | Estimativa: 3-4 dias

#### 14.1 Listagem de Notificações
- [ ] Tela de notificações
- [ ] Lista de notificações
- [ ] Indicador de não lidas
- [ ] Filtro por não lidas

#### 14.2 Ações de Notificação
- [ ] Marcar como lida
- [ ] Marcar todas como lidas
- [ ] Navegação para item relacionado (actionUrl)

#### 14.3 Push Notifications (Futuro)
- [ ] Configuração de push notifications
- [ ] Receber notificações push
- [ ] Tratamento de notificações quando app está em background

#### 14.4 Serviços e Modelos
- [ ] Criar `NotificationService`
- [ ] Modelos de dados (Notification, NotificationList)

---

## 🔒 Etapa 15: Melhorias e Polimento

### Prioridade: VARIÁVEL | Estimativa: Contínuo

#### 15.1 Performance
- [ ] Otimização de imagens
- [ ] Lazy loading de listas
- [ ] Cache inteligente
- [ ] Redução de chamadas de API

#### 15.2 UX/UI
- [ ] Animações suaves
- [ ] Feedback visual consistente
- [ ] Estados vazios (empty states)
- [ ] Estados de erro amigáveis
- [ ] Loading states

#### 15.3 Offline (Futuro)
- [ ] Cache de dados essenciais
- [ ] Modo offline básico
- [ ] Sincronização quando voltar online

#### 15.4 Testes
- [ ] Testes unitários de serviços
- [ ] Testes de widgets
- [ ] Testes de integração

---

## 📊 Ordem Recomendada de Implementação

### Fase 1: Fundação (Semanas 1-2)
1. ✅ Etapa 0 - Autenticação (CONCLUÍDA)
2. 🚀 Etapa 1 - Dashboard Completo
3. 🏠 Etapa 2 - Gestão de Propriedades

### Fase 2: Operações Básicas (Semanas 3-4)
4. 👥 Etapa 3 - Gestão de Clientes
5. 📅 Etapa 4 - Agenda e Compromissos

### Fase 3: Funcionalidades Avançadas (Semanas 5-7)
6. 🎯 Etapa 5 - Match de Imóveis
7. 💰 Etapa 6 - Comissões e Financeiro
8. 💬 Etapa 7 - Chat e Comunicação

### Fase 4: Produtividade (Semanas 8-10)
9. 📋 Etapa 8 - Kanban e Tarefas
10. 👤 Etapa 13 - Perfil e Configurações
11. 🔔 Etapa 14 - Notificações

### Fase 5: Extras (Semanas 11+)
12. 🎯 Etapa 9 - Metas e Performance
13. 🏆 Etapa 10 - Gamificação
14. 📄 Etapa 11 - Documentos
15. 🔑 Etapa 12 - Chaves e Visitas
16. 🔒 Etapa 15 - Melhorias e Polimento

---

## 📝 Notas Importantes

### Decisões Técnicas
- **Estado Global**: Considerar Provider/Riverpod para estado compartilhado
- **Cache Local**: Usar Hive ou SQLite para cache
- **Charts**: Avaliar pacotes (flutter_charts, syncfusion_flutter_charts)
- **WebSocket**: socket_io_client para chat em tempo real
- **Upload de Arquivos**: image_picker para imagens, file_picker para documentos

### Dependências a Adicionar (conforme necessário)
```yaml
# Charts
syncfusion_flutter_charts: ^latest
# ou
fl_chart: ^latest

# WebSocket
socket_io_client: ^latest

# Imagens
image_picker: ^latest
cached_network_image: ^latest

# Cache
hive: ^latest
hive_flutter: ^latest

# File handling
file_picker: ^latest
open_filex: ^latest
```

### Boas Práticas
- Sempre criar serviços para comunicação com API
- Usar modelos de dados tipados
- Implementar tratamento de erros consistente
- Adicionar loading states em todas as operações assíncronas
- Validar dados no cliente antes de enviar para API
- Implementar paginação onde necessário
- Usar pull-to-refresh em listas
- Cachear dados quando apropriado

---

**Documento criado em**: 2025-01-26  
**Versão**: 1.0.0







