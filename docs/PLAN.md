# Nexo — plano de evolução (21/10/2026)

Origem: `prompt-claude-code-nexo.md` (sessão de conciliação com o assistente).
Fora do escopo por decisão do dono: **tudo de apostas** (5.6, lista oficial
de bets). O resto segue em fases, cada uma com testes e commit próprio.

## Andamento (23/10/2026)

| Fase | Situação |
|---|---|
| 1 Fundação | Feita (`413b637`): regra do fechamento, transferências sem categoria, renda fixa × extra. |
| 2 Conciliação | Feita (`6cbd78c`): `reconciliation.dart`, `inbox_reconciler.dart`, caixa "Para revisar". |
| 3 MCP | Feita no código (`191faec`); **migration `202610210006` e redeploy do `nexo-mcp` pendentes**. |
| 4 Orçamento vivo | Feita (`746eaae`): quanto posso gastar, ritmo ideal, orçamento proporcional. Rollover e Flex ficaram. |
| 5 Recorrentes | Parcial (`539cbc7`): alertas de valor/duplicidade, "não vou renovar". Despesa dividida ficou. |
| 6 Navegação | Não iniciada. |
| 7 Extras | Não iniciada. |

## Diagnóstico da arquitetura atual

- **Local-first.** O dinheiro mora no SQLite de cada aparelho (Flutter,
  schema 25). Toda gravação passa por `ledgerTransaction`/`DBHelper.operation`
  e vira operação no diário de sincronização (Supabase `nexo-sync`). Saldos
  são consequência das operações; o servidor guarda o diário e um espelho
  (`entities`, `balances`), não aplica regras financeiras.
- **Open Finance (Pluggy).** A Edge Function `pluggy-sync` lê contas e
  transações (35 dias), normaliza (`normalize.ts`) e grava **sugestões** no
  servidor. O app traz as sugestões para `notification_suggestions` e a
  pessoa confirma/ignora (`PluggyInbox`); confirmar cria o lançamento com id
  fixo `notification:pluggy:<id>`. Nada vira dinheiro sozinho.
- **Assistente (MCP).** A Edge Function `nexo-mcp` lê o espelho e enfileira
  pedidos (`nexo_mcp_private.commands`, 38 tipos). O app reivindica e executa
  com as próprias regras (`AssistantCommands` + `AssistantMoreCommands`).
- **Cartão.** Faturas são derivadas de `BillingCycle.forDate` (data da compra
  + dia de fechamento); pagamentos em `card_invoice_payments` chaveados pela
  data de fechamento (`cycle_end`).

## O que já existia antes deste plano

| Item do prompt | Situação |
|---|---|
| Ajuste de saldo neutro (5.4) | Feito em 1.10.0: `adjust_account_balance` → `account.adjust` = editar o saldo no app (sem receita/gasto). |
| Pagamento de fatura (5.1) | Existe (transferência ligada ao ciclo, `card_invoice_payments`; `pay_card_invoice` no MCP). O "Pedido desconhecido" era o app 1.9.0. |
| Funções do MCP recusadas (2.3) | Causa: app antigo. Resolvido em 1.10.0; falta o servidor saber o que o app aceita (fase 3). |
| Orçamento: ritmo, por dia, sugestões | Feito em 1.10.0 (planejamento, `budget_insights.dart`). |
| Ritmo do mês, previsão de saldo, resumo semanal | Existem no início (`NexoSpendingPace`, `CashTimeline`, `WeekSummary`). |
| Detecção de assinaturas | `subscription_detector.dart`. |
| Regras de importação | `import_rules` (texto contém → categoria). Base para 5.3. |

## Causas encontradas no código

1. **Fatura dividida errado (2.1):** `BillingCycle` põe a compra feita *no dia
   do fechamento* na fatura que fecha. No Nubank (e na maioria dos bancos
   brasileiros) o dia do fechamento é o "melhor dia de compra": entra na
   próxima. 33 pontos de uso fazem `start <= data < end + 1 dia`.
2. **Transferências com categoria de gasto (2.8):** `addTransfer` grava as
   duas pontas com a primeira categoria de despesa da lista.
3. **Renda inflada (2.7):** Pix entre contas próprias confirmado como
   receita; o normalizador só reconhece transferência por palavras fortes.

## Fases

### Fase 1 — Fundação
- `BillingCycle`: compra no dia do fechamento vai para a próxima fatura;
  limite exclusivo `until` usado em todos os pontos; a chave da fatura
  continua sendo a data de fechamento (pagamentos já registrados casam).
- Transferências sem categoria (novas); exibição/relatórios tratam pontas de
  transferência como "Transferência" mesmo nas antigas (sem reescrever dados).
- Renda fixa × extra nas análises: receita vinda de recorrente = fixa.
- Teste de aceite com o cenário da seção 7 (nomes fictícios): outubro
  R$ 420,92, novembro R$ 213,59, total R$ 634,51.

### Fase 2 — Conciliação e inbox "Para revisar"
- Normalização de nomes (`Ifd*`, `Mp *`, `Pg *`, números, CNPJ).
- Casamento fuzzy sugestão ↔ lançamento manual (valor 50%, texto 35%, data
  15%; ±7 dias); ≥85 vincula sozinho, 60–85 "na dúvida" com o par.
- Automáticos: transferência entre contas próprias (nome do titular
  configurável + par de mesmo valor em ±1 dia), pagamento+estorno no mesmo
  dia, "Reserva por gasto"/"Dinheiro retirado", rendimentos abaixo de um
  limite. Resolvidos ficam fora da inbox, com motivo e desfazer.
- Regras: condições (contém/regex, valor/faixa, conta, tipo) e ações
  (categoria, subcategoria, renomear, transferência, ignorar). "Sempre fazer
  isso?" ao corrigir.
- Ações em lote na inbox.

### Fase 3 — Sincronização e MCP
- **Por que os pedidos ainda dependem de um aparelho:** as regras de dinheiro
  (saldos, faturas, objetivos, parcelas) vivem no app e o servidor só tem o
  diário. Executar no servidor duplicaria toda a contabilidade em TypeScript
  e criaria dois "donos" do saldo (risco de criar/apagar dinheiro, regra 6).
  Em vez disso: o PC aberto executa (já acontece) e o celular processa a
  fila também em segundo plano quando possível.
- Capacidades versionadas: o app publica os tipos que entende; o MCP recusa
  com mensagem acionável ("atualize o Nexo para X") em vez de "Pedido
  desconhecido".
- `get_card_invoices` (fechada, atual, pago, restante) no MCP; prévia antes
  de ignorar sugestões em lote; status com idade do pedido.

### Fase 4 — Orçamento vivo
- "Quanto posso gastar" (renda fixa − contas fixas previstas − orçamentos −
  metas) no mês e por dia, no início.
- Ritmo excluindo recorrentes, com linha pontilhada do ritmo ideal.
- Orçamento criado no meio do período conta a partir da criação, com limite
  proporcional no primeiro período.

### Fase 5 — Recorrentes e divididas
- Alerta de variação de valor e de cobrança duplicada.
- "Não vou renovar": lembrete X dias antes.
- Despesa dividida: valor cheio + quanto cada um deve; o custo real entra no
  orçamento.

### Fase 6 — Navegação e acabamento
- Proposta: Hoje · Transações · Orçamento · Cartões · Mais. Dark mode de
  primeira classe já existe; revisar contraste e estados vazios.

### Fase 7 — Extras
- Mês em revisão; onboarding guiado; guardar parte da sobra.

## Riscos e decisões

- Mudar a regra do fechamento move compras feitas no dia do fechamento para a
  fatura seguinte em todo o histórico: é o comportamento do banco. As chaves
  de pagamento não mudam.
- `billId` da Pluggy (fonte da verdade da fatura) exige guardar o id da
  fatura na sugestão e no lançamento (migração de schema). Fica para depois
  da fase 2; a regra do fechamento corrige o caso observado.
- Webhooks da Pluggy exigem cadastrar a URL no painel (ação do dono) e uma
  função pública nova; ficam documentados, sem ativar dados reais sem ok.
- Testes nunca usam a base pessoal; fixtures com nomes fictícios.
