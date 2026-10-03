# Paridade web × app — verificação de 03/10/2026

Card do funil **Tecnologia - Intellisys**: *[ANÁLISE] Mobile — levantamento do que falta parear com a web* (Edson Jr).
Base: `docs/PARIDADE_AUDITORIA_2026-09-29.md`, re-conferida item a item contra o código ATUAL do app, da web
(`intellisys-CRM`) e do back (`intellisys-CRM-Back`, `intellisys-financeiro`). Verificação por código, não no aparelho.
"Depende do back" = a rota/DTO existe no `master` do back; produção não foi conferida.

## Placar

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

## O que QUEBRA o app hoje (prioridade máxima)

1. **Login / cobrança (NEW-01)** — titular com trial vencido ou assinatura suspensa entra sem aviso e sem onde assinar; o colaborador da conta leva 403 na Home e em Imóveis.
2. **Plano "só Financeiro" (NEW-02)** — o back recusa as rotas de CRM com 403; o app trava em "Sem permissão" (depende do deploy do back).
3. **Chat** — "Excluir conversa" em conversa direta sempre falha (rota de sair de grupo → 400).
4. **Meu Site (integ-F1)** — editar/reordenar seção sem seções salvas apaga o formulário de captação do site público.
5. **Fichas** — anexo da ficha física recusado na venda e na proposta (upload sem tipo de arquivo).
6. **Imóveis** — Exportar nunca funcionou (GET × POST); "Apenas inativos" não filtra; preço 0 aparece como "R$ 0".
7. **Transversais** — telefone com DDI 55 gravado errado; CNPJ alfanumérico não digita; tipo "Assinatura" da agenda dá 400; upload com token vencido falha; deep link de ficha de venda com id inválido; várias ações sem checagem de permissão terminam em 403 (agenda, check-in, vistorias, chaves, fichas de locação).

## Decisões de escopo a revisar

- **Meu Financeiro, PIN, adiantamento, Solicitações (fin-01 a fin-05)** — fora do escopo em 29/09; com o Financeiro como prioridade nº 1 desde 02/10, sugerido voltar como P0.
- **Fichas de Locação (6 P0) e Locações (12 itens)** — seguem fora do escopo pela decisão de 29/09.
- **Web-only** — ~23 itens de Integrações/Meu Site/Portais e Transversal são candidatos a sair do escopo do app.

## Pendências do BACK descobertas

- `isSitePremiumLine` ("linha premium") fora do DTO do PATCH de imóvel: não grava nem na web.
- Endereço estruturado do proprietário e filtros de faixa de preço/suítes/salas sem suporte no back.
- `/kanban/.../capabilities` inexistente; `transferDate` descartado na criação do card.
- Provável conflito de rotas na proposta (`whatsapp-envio` capturado por `:signatureId`).
- WhatsApp por QR Code: nota de voz e documento chegam como vídeo.

## Execução (em andamento em 03/10)

- **[MOBILE] Imóveis** — bugs rápidos + itens do card (aprovação parcial, abas do portfólio, recentes, catálogo, permuta, atalhos de status).
- **[MOBILE] Fichas** — upload, DISPAROS MANYCHAT, equipes, vínculo com imóvel, trava/assinaturas, detalhe + auditoria, exportação.
- **P0 transversais** — login/cobrança, plano só Financeiro, excluir conversa, Meu Site, DDI/CNPJ, agenda, upload/token, deep link e checagens de permissão.

Cada relatório de domínio é atualizado com ✅ no que for resolvido.
