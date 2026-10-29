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
| `all_actions.ts` | Contas, objetivos, investimentos, empréstimos, emprestado, bens, desejos, faturas |
| `parity_actions.ts` | Paridade com as telas: tipos de gasto, configurações, lotes, desfazer, análises, banco × Nexo |
| `envelopes.ts`, `settings.ts`, `invoices.ts` | Tipos de gasto, registro de configurações e faturas, espelhando o app |

## Ciclo de um pedido

1. A ferramenta valida contra o espelho e chama `nexo_mcp_enqueue_v2` (tipo `entidade.acao`,
   argumentos, chave opcional). A mesma chave, ou o mesmo pedido em 10 minutos, devolve o
   primeiro (`deduplicated: true`).
2. Um aparelho com o app aberto pega o pedido (`nexo_mcp_claim`): um por vez por acervo, do mais
   antigo ao mais novo.
3. O app aplica pelos mesmos métodos das telas e devolve `done` (com o que mudou, para desfazer)
   ou `rejected` (com o motivo).
4. `get_request_status` diz "gravado no Nexo", "pendente" ou "recusado"; `undo_request` desfaz;
   `list_requests` lista.

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
