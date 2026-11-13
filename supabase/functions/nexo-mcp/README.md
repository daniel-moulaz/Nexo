# nexo-mcp — conector do Claude

Servidor MCP (Streamable HTTP, sem estado) que dá ao Claude acesso ao acervo
sincronizado de uma pessoa. Lê o espelho do `nexo-sync` e transforma mudanças em
**pedidos** que um aparelho da pessoa grava com as regras do próprio app. O servidor
nunca grava dinheiro.

Matriz de cobertura, regras e evidências: [`docs/mcp-paridade.md`](../../../docs/mcp-paridade.md).

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `index.ts` | Entrada da Edge Function: token do conector, chamadas RPC com a chave de serviço, auditoria |
| `mcp.ts` | Protocolo MCP, lista de ferramentas, `idempotency_key` em toda escrita, instruções que o Claude lê |
| `finance.ts` | Espelho das regras de consumo do app (`FinanceRules`, `FinancialAnalysis`) |
| `tools.ts` | Leituras básicas: resumo, contas, categorias, lançamentos, contas a vencer, carteira |
| `actions.ts` | Fila de pedidos, status, idempotência, ids do que está sendo criado, lançar/corrigir/apagar, Open Finance |
| `more_actions.ts` | Recorrentes, orçamentos, categorias, objetivos, fatura |
| `all_actions.ts` | Contas, objetivos, investimentos (reais e dólar), empréstimos, emprestado, bens, desejos, faturas |
| `portfolio.ts` | Posição em duas moedas, a mesma regra do app: custo em reais da data, efeito do preço e do câmbio |
| `queue.ts` | Versão mínima por pedido (dólar pede a 1.16.0) e a mensagem de endereço recusado |
| `push.ts` | Aviso silencioso aos celulares (Firebase Cloud Messaging), opcional |
| `parity_actions.ts` | Paridade com as telas: tipos de gasto, configurações, lotes, desfazer, análises, banco × Nexo |
| `envelopes.ts`, `settings.ts`, `invoices.ts` | Tipos de gasto, registro de configurações e faturas, espelhando o app |

## Ciclo de um pedido

1. A ferramenta valida contra o espelho e chama `nexo_mcp_enqueue_v3` (tipo `entidade.acao`,
   argumentos, chave opcional, versão mínima do app). A mesma chave, ou o mesmo pedido em 10
   minutos, devolve o primeiro (`deduplicated: true`). Sem a migration da 1.17.0, cai para
   `nexo_mcp_enqueue_v2`.
2. Com o segredo `FCM_SERVICE_ACCOUNT`, a função manda um aviso silencioso aos celulares do
   acervo. Sem ele, o celular confere sozinho a cada 15 minutos; o PC na bandeja, a cada 20 s.
3. Um aparelho pega o pedido (`nexo_mcp_claim`): um por vez por acervo, do mais antigo ao mais
   novo. Um aparelho abaixo da versão mínima, ou que não conhece o tipo, deixa o pedido para
   outro, sem pular a fila (`docs/FILA_DO_CLAUDE_2026_11.md`).
4. O app aplica pelos mesmos métodos das telas e devolve `done` (com o que mudou, para desfazer)
   ou `rejected` (com o motivo).
5. `get_request_status` diz "gravado no Nexo", "pendente" ou "recusado", com a última
   conferência de cada aparelho; `undo_request` desfaz; `list_requests` lista.

O app informa os tipos que sabe aplicar (`nexo_mcp_report_device`); o servidor recusa na hora o
tipo que nenhum aparelho conhece ("atualize o app").

## Testes

```
node tool/test_nexo_mcp.mjs          # ferramentas, protocolo, espelhos das listas do app
node tool/validate_sync_sql.mjs      # migrations no PostgreSQL local (PGlite)
flutter test test/mcp_app_parity_test.dart test/assistant_parity_test.dart
```

## Publicar

Depois de aplicar as migrations no `nexo-sync`, na ordem dos nomes:

```
supabase functions deploy nexo-mcp --no-verify-jwt
```

O conector usa token próprio (no fim da URL ou em `Authorization: Bearer`), não a sessão do
Supabase; por isso a verificação de JWT fica desligada.

### Adicionar no Claude

Configurações → Conectores → Adicionar conector personalizado, nome Nexo, URL inteira gerada
no app (Sincronizar dispositivos → Claude (IA) → Conectar ao Claude). O Claude avisa que "não
foi possível determinar como este servidor faz login": é esperado, porque a chave está na URL
e não há login. Escolha **Continuar mesmo assim**. Se as ferramentas não aparecerem, a chave
foi desconectada ou a URL foi copiada cortada: a resposta 401 diz qual dos dois. Gere outra no
app (menu do conector › Gerar outro endereço): o histórico de pedidos fica, porque pertence ao
acervo, e o endereço antigo só para depois que o novo aparece. Remover e adicionar de novo o
conector no Claude tira o Nexo das conversas já abertas ("MCP server removed from
configuration"): abra uma conversa nova.

O endereço não expira sozinho. OAuth exigiria publicar `/.well-known` na raiz do domínio, o que
uma função do Supabase não faz sem domínio próprio (pago); por isso a chave continua no endereço.

## Cotações dos EUA (`market-quotes`)

Função separada, chamada pelo app com a sessão do Supabase da pessoa dona
(`NEXO_QUOTES_OWNER`, ou `NEXO_PLUGGY_OWNER` se ausente). Recebe só tickers (até 20) e
devolve o preço em dólar e a hora da última negociação, pelo `/quote` da Finnhub. A chave
fica no segredo `FINNHUB_API_KEY` e nunca chega ao app. Respostas valem 1 minuto em memória.

```
node tool/test_market_quotes.mjs
supabase secrets set FINNHUB_API_KEY=...        # chave gratuita em finnhub.io
supabase functions deploy market-quotes --no-verify-jwt
```

Sem a chave, a função responde 503 e o app mantém o último preço, com a data.

Histórico: cada cotação pedida também vira o fechamento daquele dia em
`nexo_market_private.daily_closes` (migration `202611130002_market_history.sql`), e `{"history":
"NVDA"}` devolve os fechamentos guardados para o gráfico do app. Com o segredo opcional
`ALPHAVANTAGE_API_KEY` (plano grátis, 25 consultas por dia), o primeiro gráfico de um ticker vem
preenchido com os últimos ~100 pregões, uma vez só. Sem ele, o gráfico começa no dia em que o
ativo passa a ser consultado.
