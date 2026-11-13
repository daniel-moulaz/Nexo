# Ações dos EUA no Nexo (1.16.0, schema 28)

Decisões de 13/11/2026 para controlar ações em dólar (NVDA no Inter Global) junto com a
carteira brasileira (Rico), sem confundir moedas nem contar duas vezes.

## Cotação

| Fonte | Ações dos EUA | Custo e chave | Decisão |
|---|---|---|---|
| brapi (já usada) | Página do NVDA existe, mas o preço é de fechamento (EOD) e a API de ativos americanos fica nos planos pagos. Sem token, a API responde `MISSING_TOKEN` | plano pago | continua só para a B3 |
| Stooq | O endereço CSV testado respondeu "página não existe" | sem chave | descartada |
| Yahoo Finance | Responde sem chave (testado: NVDA em USD), mas é uma API não oficial, sem termos para esse uso | sem chave | descartada |
| Alpha Vantage | 25 chamadas por dia no plano grátis | chave | pouco folgada |
| **Finnhub** | `/quote` com preço atual das ações dos EUA | grátis, 60 chamadas/min, chave | **escolhida** |

A chave fica no segredo `FINNHUB_API_KEY` da função `market-quotes` do Supabase. O app manda
só os tickers, com a sessão da pessoa dona, e recebe preço em dólar e hora. A função guarda
cada resposta por 1 minuto. Se falhar (sem chave, limite, rede), o app mantém o último preço e
mostra a data e a origem ("Cotação dos EUA · 12/11/2026 · US$ 1 = R$ 5,4321"). O gráfico de
preço e os dados de mercado da brapi só aparecem para ativos da B3.

## Moeda e custódia

- **Ativo:** `currency` (`BRL` ou `USD`) e `fx_micros`, o câmbio (reais por dólar) do último
  preço. País sai da moeda (BRL → Brasil, USD → EUA). Corretora é o campo `institution`, que já
  existia (Rico, Inter Global).
- **Operação:** `cents` na moeda do ativo, mais `brl_cents`, o valor em reais **do dia da
  operação** (obrigatório em dólar, ausente em reais), e `tax_cents`, o imposto retido num
  provento (o `cents` é o líquido que chegou).
- **Posição:** os campos de sempre (`cost`, `value`, `realized`, `income`) ficam em reais, então
  toda soma de carteira, patrimônio, CDI e gráficos continua certa sem mudança. Os campos
  `native*` ficam em dólar. Resultado separado em **efeito do preço** (o que a ação andou, no
  câmbio de hoje) e **efeito do câmbio** (o que o dólar andou sobre o custo); os dois somam a
  variação.
- **Câmbio do dia:** o mesmo que as contas em dólar já usam no total do app. Quando as taxas
  carregam, os ativos em dólar recebem a taxa (`investment.fx`, escrita derivada como a
  cotação). Conta em dólar e ação em dólar nunca discordam em reais.

## Câmbio (reais → dólares)

É uma transferência entre contas de moedas diferentes: sai R$ 550 do Inter, chegam US$ 100 no
Inter Global. O formulário pede **o valor que chegou** e mostra o câmbio efetivo e quanto ficou
abaixo da cotação de referência (spread, IOF e tarifas juntos). Os lançamentos se chamam
"Câmbio enviado" e "Câmbio recebido" e não contam como gasto nem receita. A compra da ação sai
da conta em dólar; o app recusa uma conta em reais para um ativo em dólar.

## Banco de dados

Schema 27 → 28 só **acrescenta** quatro colunas com padrão igual ao que cada linha antiga já
significava (reais): `investments.currency`, `investments.fx_micros`,
`investment_operations.brl_cents`, `investment_operations.tax_cents`. Não apaga nem reescreve
linhas. Testado numa base criada no formato antigo e na migração 24 → 28. **Celular e PC
precisam ser atualizados juntos:** uma versão antiga não conhece as colunas novas e recusaria
uma operação em dólar vinda do outro aparelho.

## O que fica manual e o que fica automático

| O quê | Como |
|---|---|
| Preço das ações dos EUA | Automático, pela função `market-quotes`, depois de criar a chave |
| Câmbio do dia para avaliar | Automático, o mesmo das contas |
| Câmbio feito (R$ → US$) | Manual: valor que saiu e valor que chegou |
| Compra, venda, provento em dólar | Manual, no app ou pelo Claude (print da ordem → `add_investment` / `record_investment_operation`) |
| Conta em reais do Inter | Open Finance (Pluggy), como hoje |
| Inter Global (conta em dólar) e Rico | Manual. A cobertura de Open Finance do Pluggy lista o Inter, mas nada indica a conta global em dólar; a Rico aparece como conector direto, não regulado. Não foi testado com credenciais |

**Print da ordem:** o caminho mais curto é o que o Daniel já usa: mandar o print ao Claude, que
lê ticker, quantidade, preço, data e corretora e chama `add_investment` com `currency: "USD"` e
`fx_rate`. Um leitor de print dentro do app ficou de fora: sem exemplos reais de ordens do Inter
para testar, ele erraria em silêncio.

## Proventos e imposto

O app só **registra** líquido, retido e o valor em reais do dia. Não calcula imposto nem mostra
regra fiscal na tela. Pelas fontes consultadas (13/11/2026), desde a Lei 14.754/2023 dividendos
do exterior entram no ajuste anual a 15%, e o imposto retido nos EUA pode ser compensado; as
fontes divergem sobre o efeito exato. Confirme com a Receita ou um contador.

## Testes

- `test/foreign_investments_test.dart`: posição em duas moedas, venda pelo custo em reais da
  data, provento com retenção, efeito do preço + câmbio = variação, tickers (BBAS3F, BRK.B, F),
  patrimônio sem dupla contagem, conta em dólar, migração 28, cotação com falha (503, rede,
  moeda errada, data futura).
- `test/ledger_test.dart`: câmbio R$ 550 → US$ 100 move os dois saldos e não vira gasto.
- `test/investments_screen_test.dart`: formulário em dólar até o detalhe com efeito do câmbio.
- `tool/test_nexo_mcp.mjs`: ferramentas em dólar, totais por corretora, moeda e país,
  patrimônio com conta em dólar, câmbio exige `received_amount`.
- `tool/test_market_quotes.mjs`: a função de cotação, sem rede.
