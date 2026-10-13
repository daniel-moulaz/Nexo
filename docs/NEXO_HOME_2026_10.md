# Home 1.5.4+20 — visibilidade e uso diário

## Motivo e escopo

O usuário considerou a 1.5.3 insuficiente: melhorias em recorrentes e dívidas não mudaram a primeira tela. Esta rodada reorganiza a Home e seus acessos, sem migration, backend, sincronização remota ou alteração nas regras de lançamento. Branch `codex/nexo-home-dashboard`, derivada do estado de `feat/nexo-financial-visibility-ux`.

## Pesquisa de produto e uso

Consulta realizada em 13/10/2026. Referências conceituais, sem copiar código, assets ou textos.

| Referência | Aprendizado aplicado ao Nexo |
| --- | --- |
| [Copilot — Dashboard](https://help.copilot.money/en/articles/6045480-dashboard-tab-overview) | Tornar a situação do mês e os próximos compromissos visíveis na primeira página. Usar comparação equivalente de períodos. O Nexo não presume renda futura para oferecer um valor livre para gastar. |
| [Quicken — Projected cash flow](https://www.quicken.com/features/projected-cashflow) e [Simplifi — previsão](https://support.simplifi.quicken.com/en/articles/3357429-using-projected-cash-flow) | Uma linha do tempo ajuda a perceber falta de caixa antes do próximo recebimento. Exibir somente compromissos cadastrados e explicar as limitações. |
| [YNAB — metas por categoria](https://www.ynab.com/features/goal-tracking) | Destacar o valor ainda disponível nos orçamentos, além do percentual consumido. Saldo bancário não é autorização para gastar. |
| [Monarch — recorrentes](https://www.monarchmoney.com/features/recurring) | Colocar vencimentos próximos e acesso ao calendário no contexto da decisão diária. |
| [Minhas Finanças/Nimtech — Google Play](https://play.google.com/store/apps/details?hl=pt-BR&id=cicero.minhasfinancas) | Avaliações visíveis elogiam previsibilidade, personalização e simplicidade. Valorizar passado, presente e futuro em uma navegação compreensível. |
| [Organizze — Google Play](https://play.google.com/store/apps/details?hl=pt-BR&id=com.organizze.android) | Avaliações elogiam relatórios e também relatam atrito com automação/conciliação. Preservar revisão explícita, distinção entre fatura e consumo e atalhos compreensíveis. |

As amostras de avaliações encontradas incluem comentários de 2023/2024. São sinais qualitativos de necessidades, não uma pesquisa representativa nem prova de falha atual desses produtos. Não se usou popularidade como substituto de validação contábil.

## O que mudou

- Topo com saldo atual em contas, dívida total dos cartões incluídos, diferença após cartões e previsão para o fim do mês.
- Resumo mensal imediatamente abaixo: entrou, gastou, barras comparativas com o período anterior e maior categoria. Setas permitem consultar meses anteriores; o mês atual compara até o mesmo dia do mês anterior.
- Atalhos grandes para despesa, receita, dívidas e recorrentes. O formulário continua exigindo confirmação antes de gravar.
- Alerta de vencimentos atrasados, com valor e acesso à agenda.
- Previsão visual diária de 7, 30 ou 90 dias, entradas/saídas previstas, aviso de menor saldo negativo e próximos vencimentos com abertura do item correspondente.
- Gráfico por categoria, detalhes dos lançamentos e fechamento mensal acessíveis na Home.
- Orçamentos mostram quanto resta, quanto foi usado e o limite. A regra existente inclui pendências e isso é informado.
- Cartões mostram dívida restante e fatura do ciclo atual separadamente; últimos lançamentos permitem abrir e repetir lançamentos comuns, sempre em revisão. Movimentações neutras não podem ser repetidas/editadas como despesas pelo novo atalho da Home.
- Layout em duas colunas no desktop, com largura máxima de 1760 px. Layout de uma coluna no celular, sem lista extensa de cartões no topo.
- Privacidade oculta valores, distribuição por categoria, comparação e gráfico futuro. Textos ampliados e valores grandes foram exercitados.

## Semântica e arquitetura

`CashTimeline` transforma o resultado do `CashForecast` existente em pontos diários somente de leitura. O primeiro ponto é o saldo atual. Atrasados entram no primeiro fechamento diário uma única vez; os demais movimentos entram na data correspondente. O menor ponto é um saldo de fim de dia, sem prometer a ordem intradiária dos pagamentos.

Não há previsão de salário ou compras sem cadastro. Contratos de empréstimo e dinheiro emprestado entre pessoas não são inseridos automaticamente na previsão; continuam disponíveis em Dívidas. Alertas de dados incompletos do motor existente levam à agenda.

`CardCommitment` e `currentInvoiceRemaining` preservam as correções locais anteriores de saldo e ciclo: pagar fatura diminui o dinheiro na conta e a dívida do cartão, sem aumentar o consumo novamente. Transferências e reservas continuam neutras. Reembolso não vira renda normal no detalhamento de Entrou.

A navegação do mês afeta receitas/despesas/categorias. Saldos, previsão e orçamentos atuais permanecem identificados como situação de hoje. A agenda recebe o mesmo horizonte selecionado na Home, inclusive 90 dias ou fim do mês.

Schema antes/depois: **23 → 23**. Banco `expensy.db`, identidade Android `com.ma.expensy` e configuração de assinatura preservados. Nenhum dado real foi incluído nas fixtures, capturas de revisão ou documentação.

## Validação

Pré-voo: dependências resolvidas, análise limpa e 184 testes aprovados antes da implementação.

Novos testes cobrem atrasados aplicados uma vez, limite do período, conversão de moeda, falta de caixa antes do salário, transferência neutra, fatura contada uma vez, pendência sem débito atual, privacidade, meses anteriores, horizonte da agenda, reembolsos no detalhamento e valores grandes com texto ampliado. As capturas de revisão usam exclusivamente dados fictícios.

- `dart format` aplicado aos arquivos desta rodada; `flutter analyze --no-pub`: nenhuma ocorrência.
- `flutter test --no-pub --concurrency=1`: **196 testes aprovados** (184 de base + 12 novos).
- Capturas sintéticas e widget tests em 360×800, 412×915 (modo escuro e escala de texto 1,5), 1280×720, 1366×768, 1920×1080 e 2560×1440. Casos adicionais em 320 px, descrições longas e valores de nove dígitos. Revisão visual das capturas mobile e desktop.
- Correções encontradas nessa validação: material dos botões para feedback de toque visível; título e marcador de data adaptados ao texto ampliado; valores dos lançamentos/vencimentos abaixo da descrição para não esmagar as linhas em telas pequenas; drilldown de receitas sem reembolsos; horizonte preservado ao abrir a agenda.
- Esc foi exercitado somente pelo teste de widget já existente, nunca por Computer Use.

Builds e instalação serão registrados após sua conclusão. As demais alterações preexistentes do workspace foram preservadas; o pacote é compilado sobre esse estado de trabalho, não sobre um checkout limpo apenas dos novos commits da Home.

## Limitações mantidas

- Não há sincronização entre PC e Android nesta versão. Cada instalação continua local e independente.
- O resumo de 3/7 dias existente continua local e sob demanda; esta rodada não cria um agendamento nem integração com bots.
- A previsão depende da qualidade dos cadastros e do suporte do motor existente; não representa todos os gastos futuros possíveis.
- Homologação funcional completa do Windows continua um trabalho separado; build e testes de layout não equivalem a percorrer todos os fluxos do executável.
