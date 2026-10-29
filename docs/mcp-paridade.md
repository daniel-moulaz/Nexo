# Paridade entre o app Nexo e o conector Claude (MCP)

Matriz central do pedido "o Claude tem o app na mão" (29/10/2026, versão **1.13.0+52**,
schema **27**). Cada linha é uma tela ou ação do app, a ferramenta MCP equivalente e o
estado. O inventário inicial, antes da implementação, está no fim.

**Estado:** implementado e testado localmente. **Não publicado:** falta aplicar a
migration `202610290001_mcp_parity.sql` no `nexo-sync`, republicar a Edge Function
`nexo-mcp` e instalar a 1.13.0 no celular e no PC (ver "Publicação").

## Resumo

| Medida | Antes | Depois |
|---|---|---|
| Ferramentas do conector | 64 | 98 |
| Ações de tela cobertas por completo (linhas da tabela "Depois") | 19 de 67 (28%) | 67 de 67 (**100%**) |
| Escritas do app sem ferramenta nem motivo registrado | não medido | 0 (teste falha se surgir uma) |
| Desfazer pedido do Claude | não | sim, pelo Claude e pelo app |
| Pedido repetido duplica | podia | não (chave por pedido e janela de 10 min) |
| Dois aparelhos gravando pedidos ao mesmo tempo | podia | não (um de cada vez, na ordem) |

"Aplicáveis" exclui o que não é decisão de tela (sincronização, segurança do aparelho,
arquivos), listado em "Fora do conector, e por quê".

## Depois

Legenda: **ok** cobre o que a tela faz, com os mesmos números e as mesmas regras.

| Tela / ação do app | Ferramenta MCP | Estado | Observação |
|---|---|---|---|
| Hoje: resumo do mês, saldos, cartões | get_financial_summary, get_accounts, get_card_invoices | ok | |
| Hoje: resumo do dia | get_daily_digest | ok | |
| Hoje: personalizar cartões | set_setting (`homeCards`) | ok | vale no aparelho que gravar |
| Hoje: "é a renda do mês?" | update_transaction (`recurring_income_id`) | ok | só metadado; saldo igual |
| Hoje: objetivos travados | set_setting (`lockedGoalIds`) | ok | compartilhada |
| Extrato: listar, buscar, filtrar | list_transactions, get_transaction | ok | situação, subcategoria, faixa de valor, "conta como consumo", paginação |
| Lançar (como o formulário) | add_transaction | ok | subcategoria, pendente com vencimento, gasto pontual, parcelas |
| Editar qualquer campo | update_transaction | ok | tipo, subcategoria, situação, vencimento, gasto pontual |
| Apagar | delete_transaction | ok | transferência nas duas pontas |
| Marcar pago / pendente | settle_transaction, update_transaction | ok | |
| Duplicar | duplicate_transaction | ok | |
| Dividir em parcelas | split_transaction | ok | total preservado; centavos na 1ª |
| Alterar em lote por filtro | update_transactions | ok | dry_run; com filtro exige expected_count |
| Apagar em lote por filtro | delete_transactions | ok | dry_run; estorna saldos |
| Acertos antigos como receita → ajuste neutro | convert_to_balance_adjustment | ok | saldo igual; deixa de ser receita |
| Transferir | add_transfer | ok | |
| Orçamentos: ver | get_budgets | ok | semana da configuração compartilhada; limite cheio e proporcional |
| Orçamentos: criar, alterar | set_budget, update_budget | ok | `full_period`: cheio ou proporcional no mês de criação |
| Orçamentos: apagar | delete_budget | ok | |
| Por tipo de gasto: ver | get_spending_types | ok | ressalva: sem renda de referência, a meta em R$ vem da renda do ciclo, que só o app calcula |
| Por tipo de gasto: Classificar | set_category_type | ok | uma ou várias categorias |
| Por tipo de gasto: Ajustar | set_spending_targets | ok | renda e %; soma 100 |
| Objetivos: ver | get_goals | ok | |
| Objetivos: criar, alterar, concluir, excluir | add_goal, update_goal, delete_goal | ok | cor, prazo, concluído |
| Objetivos: guardar, retirar | move_goal | ok | `move_money: false` = só contábil, sem mexer em conta |
| Contas: ver | get_accounts | ok | |
| Contas: criar, alterar, excluir | add_account, update_account, delete_account | ok | conta de pagamento, mínimo, lembrete, total dos bancos, cor |
| Conferir saldo com o banco | get_bank_accounts, adjust_account_balance | ok | soma várias contas do banco vinculadas à mesma do Nexo |
| Vincular conta do banco | link_bank_account | ok | não mexe em saldo |
| Fatura do cartão com extrato | get_card_invoices (`include_transactions`) | ok | compra no dia do fechamento vai para a seguinte |
| Fatura oficial do banco ao lado | get_bank_accounts | ok | |
| Pagar fatura | pay_card_invoice | ok | transferência ligada ao ciclo |
| Reabrir fatura (apagar pagamento) | delete_transaction | ok | id do pagamento no extrato da fatura |
| Categorias: ver | get_categories | ok | tipo de gasto, cor, ícone, uso |
| Categorias: criar, renomear, editar, excluir | add_category, rename_category, update_category, delete_category | ok | |
| Categorias: juntar | merge_categories | ok | dry_run |
| Subcategorias | update_transaction, update_transactions | ok | no app a subcategoria é texto do lançamento |
| Recorrentes: ver, efetivar, pular | get_recurring, pay_recurring, skip_recurring | ok | valor real diferente do previsto |
| Recorrentes: criar, alterar, excluir | add_recurring, update_recurring, delete_recurring | ok | frequência, tipo, observação, lembrete, sem fim |
| Agenda: contas a vencer | get_upcoming_bills, get_cash_projection | ok | |
| Investir: carteira | get_investment_summary, get_investments | ok | operações com id |
| Investir: cadastrar, operar, preço | add_investment, record_investment_operation, update_investment_price | ok | |
| Investir: retirar da carteira | archive_investment | ok | só posição zerada |
| Investir: apagar operação | delete_investment_operation | ok | estorna a conta |
| Investir: vincular operação antiga a conta | link_investment_operation | ok | |
| Empréstimos: ver, pagar, pular | get_loans, pay_loan_installment, skip_loan_installment | ok | |
| Empréstimos: criar, alterar, excluir | add_loan, update_loan, delete_loan | ok | |
| Empréstimos: apagar pagamento | delete_loan_payment | ok | |
| Emprestado e devido: ver, registrar, quitar | get_lended, add_lended, settle_lended | ok | |
| Emprestado e devido: alterar, excluir | update_lended, delete_lended | ok | conta corrigida pela diferença |
| Pessoas | update_person, delete_person | ok | |
| Bens | get_assets, add_asset, update_asset, delete_asset | ok | |
| Desejos | get_wishlist, add_wishlist_item, update_wishlist_item, delete_wishlist_item | ok | |
| Para revisar: listar | list_suggestions | ok | |
| Para revisar: confirmar com edição | confirm_suggestion | ok | conta, categoria, tipo, descrição, subcategoria, observação |
| Para revisar: como transferência | confirm_suggestion_as_transfer | ok | |
| Para revisar: ignorar, por filtro | ignore_suggestions | ok | prévia |
| Regras automáticas de categoria | get_import_rules, save_import_rule, delete_import_rule | ok | |
| Dados do banco até quando | get_bank_sync_status | ok | |
| Pedir leitura dos bancos | refresh_bank_data | ok | servidor lê no máximo 1×/hora |
| Configurações | get_settings, set_setting | ok | semana, alertas, lembrete diário, tema, cor, fonte, vibração, nome, moeda, esconder valores |
| Análises: por categoria, agrupado | get_spending_by_category, get_spending_breakdown | ok | conta, subcategoria, dia da semana, tipo de gasto, estabelecimento |
| Análises: tendência, patrimônio, projeção | get_monthly_trend, get_net_worth, get_cash_projection | ok | taxa de poupança, menor saldo previsto |
| Pedidos do Claude: situação, lista | get_request_status, list_requests | ok | |
| Desfazer pedido | undo_request; botão Desfazer no app | ok | recusa se algo mudou depois |
| Registro "feito pelo Claude" no app | Sincronizar dispositivos › Feito pelo Claude | ok | |
| O que dá para fazer | describe_app_capabilities | ok | gerado do código; o teste confere com a lista de ferramentas |

## Fora do conector, e por quê

| Ação do app | Motivo |
|---|---|
| PIN, biometria, bloqueio | segurança do aparelho; não deve ser mudada de fora |
| Login, sincronização, conflitos de sync, conectar o Claude | credenciais e consentimento da pessoa |
| Conectar ou reconectar banco no Meu Pluggy | feito pela pessoa no site do Pluggy, com o login do banco |
| Backup, restaurar, exportar arquivo, importar extrato/B3/.ics | arquivo no aparelho; restaurar substitui o acervo inteiro |
| Cupom pela câmera, lançar por texto, paleta | atalhos de entrada que terminam em add_transaction, que o Claude já usa |
| Cotações e índices (brapi, IPCA, Selic, PTAX) | dados públicos de mercado; o Claude consulta a web; preço manual por update_investment_price |
| Anexos, etiquetas, pausar recorrente | o app não tem (pausar: end_date ou skip_recurring) |
| Ajuda, diagnóstico | leitura local, sem dado financeiro |

As escritas internas (aplicar sync, ouro pela cotação, normalização de abertura, restaurar,
importação de outro app, semear configurações) estão listadas com o motivo em
`lib/sync/app_actions.dart`.

## Como funciona

- **Um registro de ações.** `lib/sync/app_actions.dart` liga cada nome de operação gravada
  pelo app (toda escrita passa por `ledgerTransaction`/`DBHelper.operation`) às ferramentas
  que fazem o mesmo. `test/mcp_app_parity_test.dart` lê o código e **falha** se surgir uma
  escrita sem ferramenta nem motivo, se uma ferramenta citada não existir, se uma
  configuração do app ficar sem acesso, se o app e o servidor discordarem dos tipos de pedido
  ou se esta matriz não citar uma ferramenta.
- **Mesmo caminho da tela.** O servidor só valida e enfileira. O app aplica cada pedido pelos
  mesmos métodos das telas (`AssistantCommands`, `AssistantMoreCommands`,
  `AssistantParityCommands`), com as mesmas regras de saldo, fatura e consumo.
- **Ordem.** O servidor entrega um pedido por vez por acervo, do mais antigo ao mais novo; o
  PC espera enquanto o celular grava. Um pedido pode usar o `new_id` de algo criado num pedido
  anterior ainda pendente (categoria, conta, objetivo).
- **Idempotência.** `idempotency_key` em toda ferramenta de escrita; sem chave, o mesmo pedido
  repetido em 10 minutos devolve o primeiro. No aparelho, um pedido entregue de novo não é
  aplicado duas vezes.
- **Desfazer.** O app guarda, no resultado do pedido, o que ele mudou: valor anterior e
  posterior de cada linha e o delta de saldo, tirados do journal de sincronização. Desfazer é
  outro pedido (ou o botão do app), que só aplica se tudo estiver como o pedido deixou e
  sincroniza como qualquer operação. Pedidos que mexem em mais de 200 KB de dados e pedidos
  feitos sem sincronização ativa não guardam como desfazer e dizem isso.
- **Lotes.** `dry_run` mostra quantos e quais; com filtro, aplicar exige `expected_count`
  igual ao da prévia. Transferências e investimentos ficam fora de lotes.
- **Tipos novos não exigem migration.** O servidor aceita qualquer tipo no formato
  `entidade.acao` que algum aparelho tenha informado saber aplicar. Campos novos de
  ferramentas antigas viajam num tipo novo (`transaction.edit`, `budget.save`,
  `account.edit`…), para que um app antigo recuse em vez de ignorar o campo.
- **Configurações.** Renda de referência, % por tipo de gasto, início da semana e objetivos
  travados ficam na tabela sincronizada `shared_settings` (schema 27): iguais no celular e no
  PC. As demais são de cada aparelho, que as informa ao servidor.

## Regras de negócio preservadas

- Fatura do cartão: compra no dia do fechamento entra na fatura seguinte; pagamento depois do
  fechamento abate a fatura fechada (`pay_card_invoice`, invoice `closed`). Conferido no
  cenário sintético com fechamento 19, vencimento 26 e limite R$ 650.
- Acerto com o extrato é sempre `adjust_account_balance`; acertos antigos lançados como receita
  viram ajuste neutro (`convert_to_balance_adjustment`), sem mudar o saldo.
- Retirar de objetivo devolve à conta; reserva só contábil usa `move_goal` com
  `move_money: false`.
- Orçamento criado no meio do período continua proporcional por padrão (como no app);
  `full_period: true` o torna cheio desde o 1º dia.
- Transferência, reserva, aporte, pagamento de fatura e ajuste não contam como consumo; pendente
  não sai do saldo.

## Avaliado e não implementado: resgate com liquidação futura (D+2)

Hoje o app recusa operação de investimento com data futura. Para um resgate D+2 sem bagunçar
o saldo, a proposta é: a venda entra na data do pregão (a posição cai), e o dinheiro entra na
conta como **receita pendente** com vencimento na data de liquidação, ligada à operação; a
pessoa ou o Claude confirma quando cair. Exige mexer em `InvestmentRepository._cash`, na
exclusão e no vínculo de operações e numa forma de "efetivar" o caixa de uma operação, que hoje
o Extrato bloqueia. É caminho de dinheiro em uso real: fica como próximo lote, com testes
próprios. Enquanto isso, o Claude registra o resgate na data em que o dinheiro cai.

## Evidências (29/10/2026)

| Verificação | Resultado |
|---|---|
| Servidor (Node, `tool/test_nexo_mcp.mjs`) | 53/53, incluindo as 37 anteriores sem mudança |
| SQL (PGlite, `tool/validate_sync_sql.mjs`) | 53/53, 5 novos da migration |
| App (Flutter, `test/assistant_parity_test.dart`) | 18 cenários, a maioria com captura de sync, incluindo desfazer |
| Regressão de paridade (`test/mcp_app_parity_test.dart`) | 5/5 |
| Cópia local do acervo real, leitura (`test/real_parity`, `tool/real_parity/check.mjs`) | 53/53 números iguais entre app e servidor (meses, orçamentos, tipos de gasto, faturas); nenhum valor impresso |
| Cópia local do acervo real, escrita | 4 pedidos aplicados e desfeitos; banco idêntico ao original. Achou e corrigiu um defeito de reversão em linhas gravadas antes do schema 26 |

O cenário dos testes é sintético, montado com as regras do caso relatado (cartão com
fechamento 19, vencimento 26 e limite R$ 650; renda de referência; orçamento criado no meio
do mês; objetivo só contábil; ajuste antigo como receita). A cópia real ficou só em `build/` e foi
apagada depois.

## Publicação (precisa do dono, nesta ordem)

1. Aplicar `supabase/migrations/202610290001_mcp_parity.sql` no `nexo-sync` (SQL Editor). Não
   apaga nada; muda restrições da fila e cria funções.
2. Republicar a Edge Function `nexo-mcp` (verify JWT desligado, como hoje). Ela usa as funções
   novas e cai para as antigas se a migration ainda não estiver aplicada.
3. Instalar a 1.13.0+52 **no celular e no PC**. Um aparelho com app antigo para de
   sincronizar quando receber a primeira configuração compartilhada (tabela nova), até ser
   atualizado; nada se perde.

## Antes (inventário de 29/10/2026)

| Tela / ação do app | Ferramenta MCP | Estado | Observação |
|---|---|---|---|
| Hoje: resumo do mês, saldos, cartões | get_financial_summary, get_accounts, get_card_invoices | ok | |
| Hoje: personalizar cartões | — | ausente | preferência do aparelho |
| Hoje: "é a renda do mês?" | — | ausente | |
| Extrato: listar e buscar | list_transactions, get_transaction | parcial | sem filtro por situação, valor, subcategoria |
| Lançamento: criar | add_transaction | parcial | sem subcategoria, pendente, vencimento, parcelas, gasto pontual |
| Lançamento: editar | update_transaction | parcial | só valor, descrição, categoria, conta, data, observação |
| Lançamento: apagar | delete_transaction | ok | |
| Lançamento: marcar pago | settle_transaction | ok | |
| Lançamento: marcar pendente | — | ausente | |
| Lançamento: duplicar / dividir em parcelas | — | ausente | |
| Lançamentos em lote | — | ausente | |
| Transferir | add_transfer | ok | |
| Orçamento: listar | get_budgets | parcial | semana assumida no domingo |
| Orçamento: criar/alterar | set_budget | parcial | sem limite cheio no mês de criação |
| Orçamento: apagar | delete_budget | ok | |
| Por tipo de gasto: ver, Classificar, Ajustar | — | ausente | lacuna do caso real; valores só no aparelho |
| Objetivos: listar, guardar/retirar, criar/alterar/excluir | get_goals, move_goal, add_goal, update_goal, delete_goal | parcial | sem retirada só contábil, sem concluir |
| Contas: listar, criar, excluir, conferir saldo | get_accounts, add_account, delete_account, adjust_account_balance | ok | |
| Contas: alterar | update_account | parcial | sem conta de pagamento, mínimo, lembrete |
| Cartão: fatura | get_card_invoices | parcial | sem os lançamentos |
| Cartão: pagar fatura | pay_card_invoice | ok | |
| Saldo do banco × Nexo, fatura oficial | — | ausente | |
| Categorias | get_categories, add_category, rename_category, delete_category | parcial | sem tipo de gasto, cor, ícone, mesclar |
| Ajustes antigos como receita → neutro | — | ausente | |
| Recorrentes | get_recurring, pay_recurring, skip_recurring, add_recurring, update_recurring, delete_recurring | parcial | sem frequência/tipo/observação na alteração |
| Investir | get_investment_summary, get_investments, add_investment, record_investment_operation, update_investment_price | parcial | sem retirar da carteira, apagar e vincular operação |
| Empréstimos | get_loans, pay_loan_installment, skip_loan_installment | parcial | sem criar, alterar, excluir |
| Emprestado | get_lended, add_lended, settle_lended | parcial | sem alterar, excluir, pessoas |
| Bens, desejos | get_assets, add_asset, update_asset, delete_asset, get_wishlist, add_wishlist_item, update_wishlist_item, delete_wishlist_item | ok | |
| Para revisar | list_suggestions, confirm_suggestion, ignore_suggestions | parcial | sem transferência, sem subcategoria |
| Regras de categoria | — | ausente | |
| Dados do banco até quando | get_bank_sync_status | ok | |
| Configurações | — | ausente | |
| Análises | get_spending_by_category | parcial | sem tendência, patrimônio, projeção, agrupamentos |
| Desfazer, registro no app | — | ausente | |
