# Pesquisa de referências (28/10/2026)

Pesquisa feita para a evolução do Nexo. Cada item separa **o que foi verificado**
(página oficial ou fonte citada, com link) de **hipótese** (leitura minha, não
confirmada) e termina com a **adaptação proposta** para o Nexo, com complexidade,
impacto e prioridade. Complementa `docs/REFERENCIA_AUVP_FINANCAS_2026_10.md`
(AUVP Finanças, explorado em 27/10 com acesso real).

Método: busca web em 28/10/2026 e leitura das páginas oficiais quando acessíveis.
Páginas que recusaram o acesso (Revolut help, Status Invest, Monarch/features) estão
marcadas; para elas valem só as fontes secundárias citadas.

## 1. Organização financeira

### YNAB (You Need A Budget)
- **Verificado** ([ynab.com/the-four-rules](https://www.ynab.com/the-four-rules)): a página
  oficial hoje apresenta cinco princípios "For": *For Now* ("Decide what you need your money
  to do before you get paid again"), *For Later* ("Anticipate irregular expenses"), *For Ease*
  ("Get a month ahead on bills"), *For You* e *For Change* ("your plan for it can change at
  any time"). Resenhas de 2026 ([Penny Hoarder](https://www.thepennyhoarder.com/budgeting/ynab-review/),
  [freenance](https://freenance.io/products/ynab-review-2026-budgeting-app-worth-it-european-investors/))
  citam o relatório *Age of Money* (idade do dinheiro gasto), metas por categoria e
  planejador de dívidas (avalanche e bola de neve).
- **Problema que resolve:** gastar dinheiro que já existe, não o que vai entrar; absorver
  gastos irregulares sem susto.
- **Para o Nexo:** o app já tem envelopes por % da renda e "quanto posso gastar". Faltam
  (a) **gastos irregulares provisionados** (seguro, IPVA, matrícula: dividir o valor anual
  por mês e mostrar "reservado para…"), e (b) um indicador de **folga**: há quantos dias de
  despesas o saldo livre cobre (versão simples do *Age of Money*, calculável com o que já
  existe em `spendable.dart`). Complexidade média / impacto alto / **P1**.

### Monarch
- **Verificado** ([monarch.com](https://www.monarch.com/)): orçamento flexível, **detecção
  automática de recorrentes** ("streaming services, gyms, and app memberships"), metas de
  poupança, patrimônio com contas, cartões, empréstimos, imóveis e investimentos, relatórios
  de gastos/renda/patrimônio ao longo do tempo, uso em casal e com consultor. A página
  oficial não cita Sankey nem assistente de IA; resenhas
  ([freenance](https://freenance.io/products/monarch-money-review-2026-mint-replacement-budget-app/),
  [hometechhacker](https://hometechhacker.com/one-year-with-monarch-money-why-im-still-using-it/))
  citam o gráfico Sankey de fluxo de caixa no celular (06/2026) e "Goals 3.0" com alocação de
  fundos em vez de rastreio por transação.
- **Hipótese:** o Sankey funciona porque mostra, numa imagem, de onde a renda veio e para
  onde foi, sem pedir leitura de tabela.
- **Para o Nexo:** (a) **recorrentes detectadas a partir do Open Finance**: o
  `subscription_detector.dart` já acha padrões nos lançamentos; estender para sugerir
  "cadastrar como recorrente" direto na caixa "Para revisar". Complexidade média / impacto
  alto / **P1**. (b) **Sankey do mês** em Análises (renda → envelopes → categorias).
  Complexidade média / impacto médio / **P2**.

### Copilot
- **Verificado** ([ajuda oficial, 20/08/2026](https://intercom.help/copilotmoney/en/articles/8182433-copilot-intelligence-for-spending)):
  categorização por modelo **por usuário**, treinado nas transações revisadas; entra só
  depois de **30 revisões**; quando a confiança é baixa não aplica previsão; previsão
  aplicada ganha um selo; se errar, as duas melhores alternativas aparecem no topo da lista;
  a orientação é "keep your To Review inbox at 0".
- **Para o Nexo:** o app tem regras por texto (`import_rules_service.dart`) e contas
  lembradas (`notification_preferences.dart`). Falta **aprender a categoria pelo histórico
  de confirmações** (descrição normalizada → categoria mais confirmada, com contagem como
  confiança e sem aplicar abaixo de um limiar), mostrando as duas alternativas no topo ao
  corrigir. Local, sem rede, sem custo. Complexidade média / impacto alto / **P1**.

### Mobills e Organizze (Brasil)
- **Verificado** ([mobills.com.br](https://www.mobills.com.br/)): conexão de contas e
  cartões, orçamentos mensais, objetivos; sem preços na home. Relato no Reclame Aqui
  (07/2026) de sincronização parcial por Open Finance.
  ([organizze.com.br](https://www.organizze.com.br/)): **conexão com ChatGPT, Claude ou
  Manus** para perguntar sobre saldos, gastos e cartões (teste de 7 dias); Open Finance com
  até 90 dias de histórico e checagem até 6× por dia; limites por categoria; alertas de
  contas; categorização automática e leitura de recibo por IA; multiplataforma; sem anúncios.
- **Leitura:** o Nexo já faz o que o Organizze vende como novidade (conector para o Claude)
  e é local-first. A diferença de produto está na **frequência do Open Finance** (o Nexo lê
  uma vez por dia pelo Meu Pluggy) e na **leitura de recibo**.
- **Para o Nexo:** (a) escanear cupom/nota (câmera + OCR local via ML Kit) já está no
  roadmap; complexidade alta / impacto médio / **P3**. (b) Mostrar na caixa "Para revisar"
  a hora da última leitura do banco e o horário esperado da próxima, para alinhar
  expectativa. Complexidade baixa / impacto médio / **P1**.

### PocketGuard
- **Verificado por resenhas** ([Clark](https://clark.com/personal-finance-credit/budgeting-saving/pocketguard/),
  [CNBC Select](https://www.cnbc.com/select/pocketguard-budgeting-app-review/)): "In My
  Pocket" = renda − contas − metas − essenciais; o app estima renda e contas a partir das
  transações e pede confirmação.
- **Para o Nexo:** "Quanto posso gastar" já é isso. O que falta é a **confirmação da
  renda esperada** quando ela cai em dias variáveis (o dono relatou isso): ao detectar uma
  entrada grande sem recorrente associada, perguntar "é a renda do mês?" e usá-la na conta.
  Complexidade baixa / impacto alto / **P1**.

## 2. Bancos e carteiras digitais

### Nubank
- **Verificado** ([Assistente de Pagamentos](https://nubank.com.br/nu/conta/assistente-de-pagamentos)):
  débito automático, Pix agendado, débito automático da fatura e buscador de boletos num só
  lugar; "nenhuma conta será debitada automaticamente sem o seu consentimento" e aviso antes
  de cada transação. "Meus limites" do cartão com barra de limite disponível; limites Pix
  por período; "Modo Rua".
- **Leitura:** a força é juntar **tudo que vai sair** numa lista com datas e um aviso antes.
- **Para o Nexo:** a Agenda já lista vencimentos. Falta o **aviso na véspera por
  compromisso** (já existe lembrete genérico) e uma visão "**o que sai até o salário**"
  (até a próxima renda prevista), que é o horizonte real de quem recebe em dia variável.
  Complexidade baixa / impacto alto / **P1**.

### Monzo
- **Verificado** ([monzo.com/features/pots](https://monzo.com/features/pots)): até 20
  *Pots*; "Hide or lock Pots to stay on track"; contas podem ser debitadas direto de um Pot
  ("Set up Direct Debits and standing orders to come directly from a Pot"); *Savings Pots*
  com juros. [Comunidade/Trends](https://community.monzo.com/t/better-way-to-balance-your-money-in-trends-is-here/136721):
  gráfico do saldo do mês com pagamentos futuros e uma meta única de gasto mensal.
- **Para o Nexo:** o conceito de Pot é o **envelope com dinheiro de verdade** (reserva
  por objetivo). O Nexo tem objetivos com aportes e conta "Reserva". A adaptação é
  **travar/ocultar** um objetivo (não contar no "saldo em contas" nem no "quanto posso
  gastar") e ligar contas recorrentes a um objetivo (ex.: "IPVA" sai do envelope "Carro").
  Complexidade média / impacto médio / **P2**.

### Revolut
- **Verificado via help e resenhas** ([help.revolut.com](https://help.revolut.com/help/accounts/budget-and-analytics/how-can-i-see-my-spending-and-income-analytics/);
  a página "How does Analytics work" recusou o acesso): visão diária/semanal/mensal/anual,
  comparação com período anterior, por categoria, comerciante e lugar, gráficos em barra,
  pizza e linha, categorias personalizadas, orçamento por categoria em planos pagos.
- **Para o Nexo:** Análises já compara meses. Falta o corte **por comerciante** (top
  estabelecimentos do mês) e a alternância rápida de granularidade (semana/mês/ano) no mesmo
  gráfico. Complexidade baixa / impacto médio / **P2**.

### Wise, Trade Republic, C6, Inter
- **Verificado:** Wise Jars guardam dinheiro em qualquer moeda e não podem ser gastos
  direto ([help](https://www.wise.com/help/articles/2978074/what-are-jars-and-how-can-i-keep-money-in-them)).
  Trade Republic teve um redesign em 2022 criticado por esconder valores-chave
  ([Mobiflip](https://www.mobiflip.de/shortnews/verschlimmbessert-trade-republic-hat-ein-neues-design/amp/)),
  com pedidos de **modo privacidade** e **visão compacta**.
- **Lição:** a crítica ao Trade Republic é o aviso contra redesenhos que trocam densidade
  útil por espaço em branco. O Nexo já tem modo privacidade (olho no Hoje); manter os
  números-chave visíveis sem rolagem é critério de aceitação de qualquer redesenho.
- C6 e Inter não tiveram páginas oficiais úteis nos resultados; sem afirmações.

## 3. Investimentos

### Kinvo e Status Invest
- **Verificado:** Kinvo consolida investimentos de várias instituições, com projeções,
  evolução patrimonial e ativos internacionais; comprado pelo BTG em 2021
  ([Finsiders](https://finsidersbrasil.com.br/noticias-sobre-fintechs/btg-pactual-paga-r-72-pela-kinvo-plataforma-de-consolidacao-de-investimentos-para-reforcar-marca-digital));
  análise de 07/2026 relata duplicação de ordens e divergência de saldo
  ([Renova Invest](https://renovainvest.com.br/?p=19889)). Status Invest: carteira com
  rentabilidade mensal e histórica no plano grátis; importação pela B3 limitada aos últimos
  18 meses; plano Bull com múltiplas carteiras e metas de patrimônio
  ([iDinheiro](https://www.idinheiro.com.br/investimentos/status-invest/)). A página oficial
  recusou o acesso.
- **Para o Nexo:** o Investir já separa aporte de valorização e tem CDI como referência.
  O que os consolidadores têm e o Nexo não: **patrimônio ao longo do tempo** (série
  mensal do total investido + contas) e **proventos por mês**. Ambos calculáveis com
  `investment_operations`. Complexidade média / impacto médio / **P2**. Importação do
  extrato da B3 (Excel) segue no roadmap como **P3**.

## 4. Calendário e produtividade

### Fantastical
- **Verificado** ([flexibits.com/fantastical](https://flexibits.com/fantastical)): entrada
  em linguagem natural ("Lunch with Sarah at 1pm tomorrow"), visões dia/semana/mês/trimestre/
  ano, *DayTicker* compacto, tarefas ao lado de eventos que **passam para o dia seguinte
  quando atrasadas**, *Calendar Sets* por contexto, 14 widgets.
- **Para o Nexo:** (a) **lançar por texto** ("mercado 45,90 ontem no roxo"): o parser
  precisa de valor, data relativa, conta/cartão e categoria por palavra-chave; o resto vem
  dos padrões já existentes em `entry_defaults.dart`/`entry_suggestions.dart`.
  Complexidade média / impacto alto / **P1**. (b) Agenda com **visão de mês** além da
  lista, e vencidos "passando" para hoje como as tarefas do Fantastical. Complexidade
  média / impacto médio / **P2**.

### Structured
- **Verificado** ([App Store](https://apps.apple.com/app/id1499198946)): linha do tempo
  única juntando calendário e tarefas; *replanning* reagenda o que ficou para trás.
- **Para o Nexo:** o "replanejar" cabe nos Recorrentes: quando um vencimento passa sem
  registro, oferecer "pular", "pagar hoje" ou "mover para…" em um toque (hoje há Pular e
  Registrar). Complexidade baixa / impacto médio / **P2**.

### Linear, Raycast, Superhuman (paleta de comandos)
- **Verificado** ([Superhuman](https://blog.superhuman.com/how-to-build-a-remarkable-command-palette/),
  [techinterview](https://www.techinterview.org/post/3233475212/build-command-palette-cmd-k/)):
  Cmd/Ctrl+K abre um diálogo com busca difusa sobre um registro de comandos; a Superhuman
  usa a paleta para **ensinar atalhos**; Linear mantém a paleta plana, Raycast aninha.
- **Para o Nexo:** uma **busca global** que acha telas ("Agenda", "Fatura do roxo"),
  ações ("Nova despesa", "Transferir", "Conferir com o banco") e lançamentos, com Ctrl+K no
  Windows e a lupa do Hoje no celular; cada ação mostra o atalho ao lado. Complexidade
  média / impacto alto no desktop, médio no celular / **P1**.

### Todoist, Notion Calendar, Things 3
- Os resultados foram fracos ou de terceiros; sem afirmações verificadas. **Hipótese** a
  partir do uso conhecido: recorrência por frase ("todo dia 5") e entrada rápida com teclado
  são o padrão; já cobertos pelas adaptações acima.

## 5. Design

### Material 3 Expressive
- **Verificado** ([developer.android.com, Wear](https://developer.android.com/design/ui/wear/guides/get-started/design-language)):
  paletas tonais mais profundas, tipografia com eixos variáveis, formas que arredondam ou
  afiam cantos por estado, movimento que "spatially connects surfaces". Orientação
  secundária ([skill comunitária](https://tessl.io/registry/skills/github/ivan-magda/mobile-design-skills/mobile-design-android)):
  aplicar em poucos "momentos" por tela, não em tudo.
- **Para o Nexo:** o sistema plano de cartões (raio 20, borda fina) já segue essa linha.
  O que falta: **movimento com propósito** (transição do mês ao trocar, número que
  "conta" ao atualizar) e **cantos por estado** só nos elementos de ação. Complexidade
  baixa / impacto médio / **P2**. Evitar: sombras, gradientes e efeitos sem função
  (lição do Trade Republic).

## 6. O que a pesquisa não sustenta

- Transformar o Nexo em "super app" com produtos bancários: a diferença do Nexo é ler os
  bancos, não ser um.
- Gamificação e "desafios": nenhuma fonte verificada mostrou ganho de uso; fica fora.
- Modelos de IA em nuvem para categorizar: o Copilot mostra que um modelo **por usuário**
  com limiar de confiança basta, e no Nexo isso pode ser local (contagem por descrição).

## Prioridades consolidadas (entram no plano de evolução)

| # | Adaptação | Origem | Prioridade |
|---|---|---|---|
| 1 | Busca global / paleta de comandos (Ctrl+K, lupa) | Linear, Raycast, Superhuman | P1 |
| 2 | Lançar por texto em linguagem natural | Fantastical, Todoist | P1 |
| 3 | Categoria aprendida pelo histórico, com confiança | Copilot | P1 |
| 4 | Recorrentes sugeridas a partir do Open Finance | Monarch | P1 |
| 5 | "O que sai até a próxima renda" + confirmação da renda do mês | Nubank, PocketGuard | P1 |
| 6 | Gastos irregulares provisionados + dias de folga | YNAB | P1 |
| 7 | Hora da última leitura do banco e da próxima | Organizze | P1 |
| 8 | Objetivos travados fora do "posso gastar"; contas ligadas a objetivo | Monzo | P2 |
| 9 | Sankey do mês; corte por comerciante; granularidade | Monarch, Revolut | P2 |
| 10 | Patrimônio ao longo do tempo; proventos por mês | Kinvo, Status Invest | P2 |
| 11 | Agenda em mês; replanejar vencido em um toque | Fantastical, Structured | P2 |
| 12 | Movimento com propósito no sistema visual | Material 3 Expressive | P2 |
| 13 | Cupom por câmera; extrato B3 | Organizze, Status Invest | P3 |
