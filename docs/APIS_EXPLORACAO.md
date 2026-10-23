# Nexo — exploração de APIs (Etapa 1, 23/10/2026)

Inventário pedido no prompt "Open Finance (Pluggy), brapi e as próximas
melhorias". **Nenhum código foi alterado nesta etapa e nenhuma chamada foi
feita às conexões reais.** Evidências: documentação oficial lida em
23/10/2026 e consultas a APIs **públicas** (BrasilAPI, Banco Central, brapi
sem chave), sem dado pessoal.

Legenda de situação: **USAMOS** · **DISPONÍVEL, NÃO USAMOS** · **NÃO VEM
(nas suas conexões/plano)** · **PAGO** · **A CONFIRMAR** (precisa do portal
da Pluggy).

> **Limitação desta rodada:** o MCP da Pluggy (portal: `debug_item`,
> `summarize_of_calls`, `list_webhook_events`…) não está conectado nesta
> sessão. Tudo marcado **A CONFIRMAR** depende dele. Para conectar:
> `claude mcp add --transport http pluggy-docs https://mcp.pluggy.ai/mcp`
> e entrar com a conta do dashboard da Pluggy.

---

## 0. O que o Nexo usa hoje (código)

- `supabase/functions/pluggy-sync`: só **leituras** — `POST /auth`,
  `GET /items/{id}`, `GET /accounts?itemId=`, `GET /v2/transactions`
  (cursor, janela de **35 dias**). Lê no máximo 1×/hora por item (5 min se
  forçado). Nenhum endpoint de pagamento. Nenhum webhook.
- Transação vira **sugestão** (`normalize.ts`): usa `type`, `status`,
  `description`, `amount`/`amountInAccountCurrency`, `operationType` só como
  texto, `creditCardMetadata.installmentNumber/totalInstallments`.
  **Não usa** `billId`, `providerId`, `paymentData`, `purchaseDate`,
  `payeeMCC`, `creditData`, `bankData`, `/bills`, `/investments`,
  `/items/{id}/resources`, consentimento.
- Investimentos: cotação **brapi** (`/api/v2/stocks/quote`, token opcional do
  usuário, cache, 1 rodada/15 min); CDI pela série **SGS 12** do Banco
  Central (1.10.0).
- Android já tem: **leitura de notificações de bancos**
  (`FinancialNotificationListener.kt` + parser; Nubank, Mercado Pago, Inter,
  PicPay) que vira sugestão na caixa; **widgets** na tela inicial (contas,
  orçamento, lançamento rápido, `home_widget`).

---

## 1. Pluggy

Fontes: [faturas](https://docs.pluggy.ai/en/docs/products/credit-card-bills),
[parcelas e ciclo](https://docs.pluggy.ai/en/docs/products/credit-card-installments),
[transações](https://docs.pluggy.ai/en/docs/products/transactions),
[contas](https://docs.pluggy.ai/en/docs/products/accounts),
[investimentos](https://docs.pluggy.ai/en/docs/products/investments),
[item/Meu Pluggy](https://docs.pluggy.ai/en/docs/connections/item),
[webhooks](https://docs.pluggy.ai/en/docs/developer-tools/webhooks-ref),
[recorrentes](https://docs.pluggy.ai/en/docs/intelligence/recurring-payments),
[limites operacionais](https://docs.pluggy.ai/docs/rate-limits-of),
[rate limit da API](https://docs.pluggy.ai/docs/rate-limits).

### 1.1 Meu Pluggy (confirmado na documentação)
- O item original no Meu Pluggy atualiza **a cada 24 h**, independente do
  plano. O item "espelho" que o Nexo vê **não pode ser atualizado pela API**
  (sem `PATCH`), **não tem auto-sync próprio** e **recebe webhooks**
  normalmente.
- Consequência: o botão "atualizar agora" do Nexo só relê o que a Pluggy já
  tem; dado novo do banco chega no máximo 1×/dia. **Caso 2.1** é estrutural:
  o app precisa dizer "dados do banco até HH:MM de DD/MM", nunca lista vazia.

### 1.2 Faturas `/bills` — **DISPONÍVEL, NÃO USAMOS**
- Campos: `id`, `dueDate`, `totalAmount`, `totalAmountCurrencyCode`,
  `minimumPaymentAmount`, `allowsInstallments`, `financeCharges[]`
  (`LATE_PAYMENT_REMUNERATIVE_INTEREST`, `LATE_PAYMENT_FEE`,
  `LATE_PAYMENT_INTEREST`, `IOF`, `OTHER`), `payments[]` (`valueType`
  `FULL_PAYMENT`/`MINIMUM_PAYMENT`/`OTHER`, `paymentDate`, `paymentMode`
  ex. PIX, `amount`).
- **Obrigatória** em conexões Open Finance reguladas (Nubank, Inter, BTG,
  Mercado Pago via Meu Pluggy devem trazer — **A CONFIRMAR** por item).
- Regra de quitação: `totalAmount(N) + Σ financeCharges(N+1) = Σ payments(N+1)`.
- Resolve **2.8** (total oficial, mínimo, vencimento, encargos, pagamentos
  reconhecidos) e é a base de **2.10**.

### 1.3 Transações de cartão
- Ciclo: `PENDING` **sem** `billId` → quando a fatura **vence**, a Pluggy
  rebusca com o id da fatura → `POSTED` **com** `billId` → webhook
  `transactions/updated`. Como a atualização diária só olha **7 dias**,
  essa mudança pode só chegar por webhook.
- Atenção: o `billId` só aparece **no vencimento**, não no fechamento. Entre
  o fechamento (19) e o vencimento (26) a fatura fechada existe em `/bills`,
  mas as compras ainda estão `PENDING` sem `billId`. A regra do fechamento
  da 1.11 continua necessária nessa janela.
- Parcelas: dois padrões por banco (todas de uma vez com `billPostDate`
  interno, ou mês a mês). **Sem id que agrupe** as parcelas de uma compra.
- `operationType` no cartão: `PAGAMENTO`, `PAGAMENTO_FATURA` (a Pluggy cria
  quando o banco não informa), `TARIFA`, `ESTORNO`, `CASHBACK`, `OUTROS`.
  **Hoje usamos só como texto**; usar de verdade resolve "pagamento lançado
  como transferência comum" (2.8).
- `purchaseDate`, `payeeMCC`, `cardNumber`: citados no prompt; a página de
  parcelas não os lista — **A CONFIRMAR** na referência da API.

### 1.4 Contas `/accounts`
- `creditData`: `creditLimit`, `availableCreditLimit`, `minimumPayment`,
  `balanceCloseDate`, `balanceDueDate`, `balanceForeignCurrency`,
  `isLimitFlexible`, `disaggregatedCreditLimits`. **DISPONÍVEL, NÃO
  USAMOS** → limite real e alerta de 97% de uso (2.8), fechamento/vencimento
  oficiais em vez de digitados.
- `bankData`: `closingBalance` (saldo contábil incluindo bloqueado),
  `automaticallyInvestedBalance`, cheque especial. A documentação **não**
  tem campo de "saldo reservado". Hipótese para 2.4: a "Reserva por gasto"
  do Mercado Pago pode aparecer como **investimento CDB** (caixinha) — ver
  1.7. **A CONFIRMAR** no item do Mercado Pago.
- `balance` da conta: saldo do banco. **Oportunidade grande para 2.7:**
  comparar com o saldo do Nexo e sugerir o ajuste neutro com um toque.

### 1.5 Transações de conta
- `operationType`: `PIX`, `TED`, `DOC`, `BOLETO`, `SAQUE`, `DEPOSITO`,
  `OUTROS`… (lista completa na referência). Usar para rendimento/resgate e
  transferências.
- `paymentData` (`payer`/`receiver` com `name`, `documentNumber`, ISPB…):
  a documentação diz que vem em **conectores diretos**; não garante em Open
  Finance. **A CONFIRMAR** nas suas conexões. Se vier, "Pix para mim mesmo"
  passa a ser reconhecido pelo **CPF**, sem depender do nome.
- `providerId`: id estável do Open Finance. **NÃO USAMOS** e deveríamos:
  quando a Pluggy apaga e recria uma transação com id novo, hoje a sugestão
  aparece de novo.
- `status PENDING` também cobre **Pix agendado** com data futura.

### 1.6 Itens, consentimento e saúde — **parcialmente usamos**
- Usamos `status`/`executionStatus`/`error`/`consentExpiresAt` em
  `itemHealth`. **Não usamos** `GET /items/{id}/resources` (o que o banco
  compartilhou), `resourcesCollectedAt`, `hasResourcesPendingAuthorization`,
  nem a data da última atualização para mostrar "dados até…".
- Eventos de webhook úteis: `item/updated`, `item/error`,
  `item/waiting_user_input`, `item/waiting_user_action`,
  `connector/status_updated` (banco instável).

### 1.7 Investimentos `/investments` — **DISPONÍVEL, NÃO USAMOS**
- Tipos: renda fixa (CDB etc.), fundos, previdência, **EQUITY (STOCK, FII,
  BDR)**, ETF, COE. **Caixinhas/cofrinhos aparecem como CDB.**
- Open Finance: rentabilidade `null`; `rate`/`rateType`/`fixedAnnualRate` =
  taxa **contratada**; `amountWithdrawal` = disponível para resgate;
  `taxes` = IR, `taxes2` = IOF.
- Ações em corretora via Open Finance: a documentação não confirma.
  **A CONFIRMAR** se as suas ~R$ 140 em ações aparecem (BTG?).

### 1.8 Inteligência — **PAGO / A CONFIRMAR**
- `category` e `merchant` (nome, razão social, **CNPJ**, CNAE) exigem o nível
  **Pro**. API de recorrentes (`POST enrichment-api…/recurring-payments`)
  exige Categorização: ligada no período de **trial**, depois premium via
  Vendas. Não está claro se funciona com itens do Meu Pluggy.
- Alternativa gratuita: nossa detecção própria (já existe) + CNPJ pela
  BrasilAPI quando houver CNPJ no texto/`paymentData`.

### 1.9 Pagamentos (só registro)
- Pix, Pix agendado, Pix Automático, Smart Transfers existem na Pluggy.
  **Fora do escopo** (regra do projeto: nada de movimentar dinheiro fora do
  app). Registro apenas.

### 1.10 Webhooks — **DISPONÍVEL, NÃO USAMOS**
- Responder **2xx em até 10 s** e processar depois. Até **3 tentativas**
  (imediato, ~15 min, ~2 h). `400/401/403/404/405` **não** são reenviados →
  usar `5xx` para falha temporária.
- `eventId` igual para o mesmo evento → idempotência. `transactions/*` **não**
  traz `clientUserId` → mapear pelo `itemId` (já guardamos os itens por dono).
- `transactions/created` traz `createdTransactionsLink`;
  `transactions/updated` traz `transactionIds` (buscar em lotes de 500).
- Segurança: IP de origem publicado **52.67.145.81**; **cabeçalhos
  customizados só via API** (não pelo dashboard) → criar o webhook por API
  com um cabeçalho secreto guardado como secret da função.
- Ganho: compras viram sugestão minutos depois da atualização diária, e o
  `PENDING → POSTED` com `billId` chega sem depender da janela de 7 dias.

---

## 2. Orçamento de chamadas do Open Finance (4.C)

Limites da rede (por CPF, por banco, por produto, por mês), compartilhados
com qualquer outro app conectado ao mesmo banco:

| Produto | Limite | Quando a Pluggy busca |
|---|---|---|
| Lista/detalhe de contas | 4 | criação e a cada 7 dias |
| Saldo | 420 | toda atualização |
| Transações recentes (1–6 dias) | 240 | toda atualização |
| Transações antigas (7–365 dias) | 4 | criação e a cada 7 dias |
| Faturas | ~30 (~1/dia) | — |

- Quem gasta o limite é a **execução do item** (Pluggy ↔ banco). O espelho
  do Meu Pluggy é atualizado só pelo original (1×/dia ≈ 30 execuções/mês,
  bem abaixo de 240).
- As leituras do `pluggy-sync` (`GET` na Pluggy) leem o que a Pluggy já
  guardou. A documentação **implica, mas não afirma**, que isso não consome
  o limite da rede → **A CONFIRMAR** com `summarize_of_calls`.
- O que **gastaria** limite à toa: reconectar o banco (refaz histórico de 12
  meses, limite de 4/mês) e criar itens duplicados para o mesmo banco.
  Recomendação: nunca reconectar sem necessidade, um item por banco, e
  passar a ler por webhook (menos leituras, mesmo dado).
- Rate limit da API Pluggy (por IP/minuto): `GET /transactions` 360/min,
  `PATCH /items` 20/min. Folga enorme para o nosso uso.

---

## 3. brapi

Fontes: [llms.txt](https://brapi.dev/llms.txt), [pricing](https://brapi.dev/pricing.md)
(atualizado 16/09/2026).

| Plano | Preço | Req./mês | Ativos/req. | Histórico | Atualização |
|---|---|---|---|---|---|
| Free | R$ 0 | 15.000 | 1 | 3 meses | 30 min |
| Startup | R$ 119,99/mês | 150.000 | 10 | 1 ano | 15 min |
| Pro | R$ 139,99/mês | 500.000 | 20 | 10+ anos | 5 min |

- **Free:** só cotações (ações, ETF, BDR, FII) e dividendos "limitados".
  **Macro, câmbio, cripto e fundamentos: Startup+. Tesouro Direto e FII
  detalhado: Pro.** Sem chave, só PETR4, MGLU3, VALE3, ITUB4.
- Seu plano: **A CONFIRMAR** (o app usa a chave que você cadastrou; um 403
  diz o plano necessário).
- Rotas úteis: `/api/v2/stocks/quote`, `/api/v2/stocks/historical`,
  `/api/v2/stocks/dividends` (data-com e pagamento), `/api/v2/fii/dividends`,
  `/api/v2/tickers/resolve` e `/renames` (ticker antigo), `/api/v2/macro`,
  `/api/v2/currency` (PTAX), `/api/v2/treasury/*`.
- Recomendação: **não pagar**. Macro e câmbio vêm de graça do Banco
  Central (4); Tesouro, dos dados abertos do Tesouro (4). Usar a brapi só
  para cotação e, se o seu plano permitir, dividendos.

## 4. Banco Central e dados abertos (gratuitos, sem dado pessoal)

Consultados hoje (`api.bcb.gov.br`, `olinda.bcb.gov.br`):

| Série | Código SGS | Evidência |
|---|---|---|
| CDI diário (% a.d.) | **12** | 0,051660 em set/2026 (já usamos) |
| Selic diária | **11** | igual ao CDI no período |
| CDI anualizado (% a.a.) | **4389** | 13,90 em set/2026 |
| Selic meta (% a.a.) | **432** | 13,75; publica datas futuras até o próximo Copom |
| IPCA mensal | **433** | 0,82 em set/2026 (`ultimos/N` voltou vazio; usar intervalo de datas) |
| IPCA 12 meses | **13522** | 4,58 em set/2026 |
| PTAX dólar | Olinda `CotacaoDolarDia` | 5,0277 venda em 21/10/2026 |

- Cuidados: séries diárias recusam janela ≥ 10 anos (406) e pedidos sem
  `dataFinal`; `ultimos/N` limitado; dados sob ODbL (citar fonte).
- **Tesouro Direto:** os dados abertos do Tesouro Transparente publicam
  preço e taxa diários dos títulos (CSV, gratuito) — alternativa ao plano
  Pro da brapi. **A AVALIAR** o tamanho e a frequência.

## 5. Outras fontes (5.11)

| Fonte | Custo | Privacidade | Situação | Resolve |
|---|---|---|---|---|
| **BrasilAPI feriados** (`/api/feriados/v1/{ano}`) | grátis | nenhum dado enviado | testado: nacionais 2026 ok; estaduais/municipais não vêm | 5.5 (D+2, D+0) |
| **BrasilAPI CNPJ** (`/api/cnpj/v1/{cnpj}`) | grátis | envia só CNPJ de empresa | testado: `razao_social`, `nome_fantasia` (às vezes vazio), `cnae_fiscal` | categorização, 2.2/2.9 |
| **BrasilAPI bancos** (`/api/banks/v1/{código}`) | grátis | nenhum | testado: nome e ISPB (260 = Nu Pagamentos) | exibição |
| BrasilAPI taxas (`/api/taxas/v1`) | grátis | nenhum | testado, mas **defasado** (Selic 13,75 / CDI 13,65 vs. 13,90 no BC) → preferir SGS | — |
| Notificações dos bancos (Android) | grátis | só no aparelho | **USAMOS** (já existe) | 2.1 (tempo real) |
| Widget Android (`home_widget`) | grátis | — | **USAMOS** (contas, orçamento, lançamento rápido); falta "quanto posso gastar" e alerta de caixa | 5.4/5.12 |
| FCM (push de dados) + WorkManager | grátis | o push leva só um aviso, sem dado financeiro | não usamos; exige Firebase no app | 2.11 |
| Bot do Telegram | grátis | mensagens passam pelo Telegram | não usamos; exige servidor (Edge Function) e token | lançar por texto |
| WhatsApp Cloud API | pago, regras da Meta | dados passam pela Meta | não recomendado | — |
| NFC-e (QR do cupom, SEFAZ-MG) | grátis, sem API oficial | consulta pública da nota | exigiria raspagem do portal; **avaliar termos** antes; plano B foto + IA | dividir compra por categoria |
| Pix BR Code (`br_code_pix`) | grátis | só no aparelho | não usamos; avaliar qualidade do pacote | sugerir recebedor/valor |
| B3 Área do Investidor (API) | licença paga para empresas | — | inviável; **importar o Excel** exportado | posições e proventos |
| Google Agenda | grátis | eventos com vencimentos na sua agenda | não usamos; o MCP do Google Agenda já está conectado ao Claude | vencimentos, "não vou renovar" |
| Splitwise | grátis (API) | saldos com amigos | opcional; só se as divisões crescerem | Spotify família |
| Sentry (Flutter) | grátis até a cota do plano Developer | exige `beforeSend` sem valores/descrições | não usamos | qualidade |

---

## 6. Oportunidades priorizadas

| # | Oportunidade | Ganho | Fonte | Esforço | Risco | Pago? |
|---|---|---|---|---|---|---|
| 1 | **"Dados do banco até…"** por conexão + aviso "os dados de hoje ainda não chegaram" (app e MCP) | 2.1 resolvido | `GET /items` (já lemos) | P | baixo | não |
| 2 | **Fatura oficial** (`/bills`: total, mínimo, vencimento, encargos, pagamentos) + conferência com a fatura do Nexo + pagamento reconhecido por `PAGAMENTO_FATURA` | 2.8 | Pluggy | M | médio (mexe em como a fatura é mostrada; a contagem continua do Nexo) | não |
| 3 | **Limite real do cartão** (`creditData`) com alerta perto do limite | 2.8 (97%) | Pluggy | P | baixo | não |
| 4 | **Previsão de caixa até cada vencimento** com alerta antecipado e opções reais (renda esperada, resgate a tempo, pagamento parcial e custo; nunca aposta) | 2.10 | dados do Nexo + `/bills` | M | baixo (só mostra) | não |
| 5 | **"Quanto consigo levantar até a data X"** com D+2 da B3, D+0 do Tesouro até 13h, liquidez diária, feriados | 2.10 | BrasilAPI feriados + Nexo | M | baixo | não |
| 6 | **Saldo do banco × saldo do Nexo** com ajuste neutro sugerido em um toque | 2.7 | `/accounts.balance` | P | baixo (ajuste só com confirmação) | não |
| 7 | **Webhooks** no lugar da leitura periódica + `providerId` | 2.1, 2.8, menos leituras | Pluggy | M | médio (função pública nova, segredo) | não |
| 8 | Conciliação com `operationType` e `providerId` (e `paymentData`/CPF se vier) | 2.2–2.5 | Pluggy | P | baixo | não |
| 9 | **Resumo diário/semanal** + `get_daily_digest` no MCP | 2.1, 2.9 | Nexo | P | baixo | não |
| 10 | Marcar gasto como **pontual** (fora de médias e previsões) | 2.7 | Nexo | P | médio (muda médias) | não |
| 11 | Benchmark CDI **e IPCA**, PTAX para assinatura em dólar (+IOF) | 2.9 | SGS/Olinda | P | baixo | não |
| 12 | Investimentos/caixinhas do Open Finance (`/investments`) cruzados com brapi | 2.4, 2.10 | Pluggy | M | baixo | não |
| 13 | Pedidos do assistente com o app fechado (FCM + WorkManager) | 2.11 | Firebase | G | médio (nova dependência, permissão de notificação) | não |
| 14 | Agenda de proventos | investimentos | brapi (se o plano permitir) | P | baixo | talvez |
| 15 | Criptografia ponta a ponta da sincronização | segurança | — | G | **alto** (o MCP deixa de ler o servidor; tudo passa a depender do aparelho) | não |
| 16 | NFC-e por QR, bot do Telegram, Splitwise, import do Excel da B3 | conveniência | vários | M–G | médio | não |

P = pequeno (≤ 1 dia), M = médio, G = grande.

## 7. Decisões que esperam você (por impacto)

1. **Conectar o MCP da Pluggy** (comando acima) para eu confirmar o que
   cada conexão traz (`/bills`, `creditData`, `paymentData`, investimentos,
   ações) e medir as chamadas — sem isso, 2, 3, 7, 8 e 12 ficam em hipótese.
2. **Ordem de implementação:** proponho 1 → 3 → 6 → 9 → 4 → 5 → 2 → 8 → 7
   → 11 → 12 → 10 → 13. As primeiras são baixo risco e resolvem 2.1, 2.7,
   2.8 e 2.10 rápido; webhooks (7) depois, porque exigem publicar função e
   cadastrar o webhook por API (precisa do seu ok).
3. **Mudanças na forma de contar** (exigem seu ok explícito): fatura oficial
   como referência visual (2), marcar "pontual" fora das médias (10).
4. **Firebase (13):** adiciona dependência do Google e permissão de
   notificação no celular — confirmar se quer.
5. **brapi:** seu plano atual (Free?) e se quer dividendos (pago) ou só
   cotação.
6. **Criptografia ponta a ponta (15):** decisão de arquitetura — trocaria o
   MCP que lê o servidor por processamento só no aparelho.
7. **NFC-e/Telegram/Splitwise/B3:** quais interessam.

## 8. Divergências entre o prompt e a documentação

- `billId` aparece **no vencimento**, não no fechamento (o prompt diz
  "quando a fatura fecha" em um ponto e "quando vence" em outro).
- Recorrentes da Pluggy: **premium** após o trial; pode não estar disponível.
- `purchaseDate`, `payeeMCC`, `cardNumber`: não constam nas páginas lidas;
  conferir na referência da API.
- "Saldos reservados" em `bankData`: a documentação não tem esse campo; a
  caixinha deve vir como investimento CDB.
- BrasilAPI taxas está defasada em relação ao Banco Central.
