# Changelog

## [1.12.14] - 2026-10-28
### Novo
- **Cupom pela câmera (Android):** o botão de câmera no formulário de lançamento, e "Escanear cupom" na paleta, fotografam o cupom ou comprovante e preenchem valor, data e estabelecimento com reconhecimento de texto no próprio aparelho (Google ML Kit, sem enviar a imagem a lugar nenhum). Nada é salvo sem confirmar. No Windows o botão não aparece.
### Base
- Finais de linha padronizados em LF no repositório (`.gitattributes`).

## [1.12.13] - 2026-10-28
### Dinheiro
- **Até a próxima renda:** "quanto posso gastar" conta de uma renda à outra (a maior receita recorrente marca o ciclo), não até o fim do mês; mostra o que ainda sai até lá e avisa quando a renda do ciclo está prevista mas não registrada.
- **"É a renda do mês?":** uma entrada grande sem recorrente, enquanto a renda do ciclo falta, vira um aviso no Hoje; "É a renda" marca o lançamento como a renda e o plano passa a contar a partir dela.
- **Contas anuais provisionadas:** IPVA, seguro e matrícula cadastrados como recorrentes anuais ou semestrais entram no "posso gastar" como a parte de cada mês, até o mês em que vencem.
- **Objetivos travados:** o cadeado no objetivo tira o valor guardado do "saldo em contas" do Hoje.
### Entrada e revisão
- **Categoria aprendida** no formulário (a sugestão muda enquanto você digita a descrição; as mais usadas vêm primeiro) e na caixa "Para revisar".
- **Parece recorrente:** na revisão de uma cobrança que se repete, um toque abre o cadastro do recorrente já preenchido.
- **Banco lido em…:** a caixa "Para revisar" diz a hora da última leitura e quando a próxima costuma chegar.
### Telas
- **Agenda em grade:** o mês como calendário com entradas e saídas por dia; toque num dia filtra a lista. **Exportar .ics** leva os compromissos para o calendário do celular ou do PC.
- **Análises:** "De onde veio, para onde foi" (fluxo das receitas para as categorias) e "Por estabelecimento".
- **Investir:** patrimônio ao longo do tempo (contas + aportes ao custo, 6 meses) com proventos, índices do Banco Central (IPCA 12 meses, Selic, dólar PTAX) e **importação das negociações da B3** (Excel da área do investidor), sem duplicar o que já entrou.
- **Personalizar o Hoje:** ordem e visibilidade dos cartões, pela paleta ("Personalizar o Hoje").
- Listas vazias com o botão da ação (contas, cartões, orçamento, bens, desejos, dinheiro emprestado); rótulos de leitura de tela nos números do Hoje e nos pills.
### Base
- **Diagnóstico local:** falhas de sincronização, login e Open Finance deixam um registro sem valores em Ajuda › Diagnóstico.
- **Português único:** os 11 idiomas gerados saíram; o app é PT-BR. O seletor de idioma saiu das Configurações e do onboarding (que ficou com quatro passos).
- Leitor de cupom: parser pronto e testado (`receipt_parser.dart`); a câmera ainda não está ligada.

## [1.12.12] - 2026-10-28
### Projeto independente
- Últimas menções ao nome antigo fora do código: `docs/legacy` apagada, CHANGELOG começa na 1.11.0, README e LICENSE só com o crédito MIT exigido, link do GitHub nas Configurações apontando para o repositório do Nexo, mensagem de backup inválido e chave de boas-vindas do onboarding com o nome Nexo.
- Histórico do git publicado reescrito para começar no Nexo (commit raiz com a base MIT, depois só commits do dono); backup completo guardado localmente. Detalhes em `docs/NEXO_PROJETO_INDEPENDENTE_2026_10.md`.

## [1.12.11] - 2026-10-28
### Novo
- **Buscar ou fazer:** a lupa do Hoje e Ctrl+K no Windows abrem uma paleta que acha telas (Agenda, Orçamento, Mês em revisão…), ações (nova despesa, nova receita, transferir, Para revisar), contas e cartões e lançamentos pela descrição. Enter executa o primeiro resultado; no Windows os atalhos aparecem ao lado.
- **Lançar por texto:** uma linha como "mercado 45,90 ontem no roxo" vira o formulário já preenchido com valor, data, conta e categoria; nada é salvo sem confirmar. Entende "hoje/ontem/anteontem", "dia 5", dias da semana, datas "27/10", valores com vírgula ou ponto, "R$", "recebi/salário/reembolso" para receitas, o nome da conta ou do cartão, e a categoria pelo nome ou por palavras comuns (mercado, uber, farmácia, aluguel…).
- **Categoria aprendida:** o que você confirmou antes para a mesma descrição vira a sugestão (só com duas ou mais confirmações e maioria clara), com a segunda opção à mão. Por enquanto alimenta o lançamento por texto; a caixa "Para revisar" entra em seguida.
### Qualidade
- Teste que abre as nove telas principais a 412 px com texto 1,5× e falha em qualquer overflow.
- Documentos novos: auditoria do produto e do código, pesquisa de referências com fontes, plano de evolução P0–P3, relatório do projeto independente.

## [1.12.10] - 2026-10-28
### Projeto independente
- O pacote Dart chama-se `nexo` (405 imports reescritos); as classes do app, das rotas e da transição de subida passam a `NexoApp`, `NexoRoute` e `NexoSlideUpRoute`.
- O banco local passa a `nexo.db`: na primeira abertura o app dobra o write-ahead log no arquivo, fecha e renomeia o arquivo antigo e seus sidecars; se a renomeação falhar, o nome antigo continua valendo. Coberto por `test/database_rename_test.dart`.
- Canais nativos `nexo/quick_add`, `nexo/quick_add_stream` e `nexo/privacy`; projeto CMake `nexo`; sonda nativa do listener removida.
- `LICENSE` com o aviso do Nexo acima do aviso MIT da base de código (exigido pela licença); README e docs sem o nome antigo. Mantidos por decisão do dono: `applicationId` `com.ma.expensy` e os ids internos dos canais de notificação. Relatório em `docs/NEXO_PROJETO_INDEPENDENTE_2026_10.md`.

## [1.12.9] - 2026-10-27
### Removido
Depois do Open Finance e do conector MCP, estas partes faziam de novo o que outras já fazem (análise em `docs/REVISAO_SOBREPOSICOES_2026_10.md`):
- **Monitoramento de notificações:** o serviço Android que lia notificações dos bancos, a tela Configurações › Automação e a permissão de acesso a notificações. "Para revisar" passa a receber só o Open Finance; "Esquecer contas sugeridas" ficou no menu dessa caixa e as regras de categoria continuam em Importar extrato.
- **Revisão financeira** (arquivo de 3 ou 7 dias): o fechamento semanal e o cartão "Sua semana" abrem "Mês em revisão".
- **Previsão detalhada** e **Dívidas e compromissos:** o atalho "Dívidas" do Hoje virou "Agenda"; o pill "Cartões" e "Ver tudo" abrem Contas e cartões; o botão de empréstimos abre Empréstimos.
- Telas sem nenhum caminho de navegação apagadas do código: Estatísticas, Análise anual, Insights, Despesas v2 com Receitas e Conversor de moedas.

## [1.12.8] - 2026-10-27
### Visual
- **Mais:** grupos em cartões planos com divisórias entre os itens, ícones numa só cor e abertura animada; o item morto "Orçamentos e objetivos" saiu e o subtítulo de "Sincronizar dispositivos" deixou de dizer que a sincronização está inativa.
- **Windows:** a barra lateral usa os mesmos nomes da barra do celular (Extrato, Orçamento, Investir). `tool/screen_gallery.dart` agora também renderiza a aba Objetivos e o layout de 1280 px de cada aba.
- **Abertura:** a janela de abertura do Android mostra a marca (N dourado) centralizada em 96 dp, com um PNG por densidade; a cor de fundo do ícone no tema escuro passou a ser a da marca. A imagem antiga do splash saiu do app.

## [1.12.7] - 2026-10-27
### Marca
- **Ícone novo:** N dourado de traço único sobre fundo quase preto, no Android (adaptativo, com versão monocromática para ícones temáticos do Android 13+) e no Windows. Fonte em `docs/brand/nexo-mark.svg`.
### Visual
- **Passe pelo app inteiro:** as catorze telas que ainda tinham barra colorida (Categorias, Bens, Dinheiro emprestado, Empréstimos, Desejos, Patrimônio, Estatísticas, Análise anual, Transferir, Conversor, Backup, Configurações, pessoa e empréstimo) passam ao cabeçalho plano com título pesado.
- **"+" no cabeçalho** em Categorias, Bens, Dinheiro emprestado, Empréstimos e Desejos; nenhum botão flutuante cobre as listas.
- Resumos de Bens e Dinheiro emprestado em cartões planos com pills; cartão "Fluxo dos próximos 30 dias" sem tingimento; "Mês em revisão" plano com o seletor de mês no topo.
- Títulos e headlines vêm do tema (pesados, números tabulares); as linhas de chips da Agenda e dos Recorrentes rolam na horizontal em vez de quebrar; estados vazios com margem e texto centralizado; o formulário de importação respira entre o botão de regras e o campo da conta.
### Hoje
- **"Revisar"** (cobranças para conferir) no lugar de "Transferir" nas ações rápidas; transferências continuam em Contas e no "+".
### Segurança
- **Biometria abre sozinha:** ao abrir o app bloqueado, o pedido de digital/senha do aparelho aparece sem toque; o botão continua para repetir.

## [1.12.6] - 2026-10-27
### Visual
- **Extrato:** seletor de mês no topo (com "todos os meses"); a busca vale para todos os meses e diz isso; entradas, saídas e resultado do que está na tela em três pills planos.
- **Contas e Investir:** o botão "+" fica no cabeçalho, como no Orçamento; nenhum botão flutuante cobre as listas.
- Cartões das Análises no mesmo estilo plano.

## [1.12.5] - 2026-10-27
### Visual
- **Hoje redesenhada:** seletor de mês no topo; quatro números em cartões planos (saldo em contas, resultado, receitas, despesas); cartões, "após cartões" e previsão numa linha; **"Saídas por dia"** com o mês em calendário, média por dia, maior dia e dias sem saída. O cartão de resumo do mês perdeu as setas (o seletor do topo manda).
- **Cartões planos** com borda fina em todo o app, no lugar do preenchimento tingido.

## [1.12.4] - 2026-10-27
Referências: AUVP Minhas Finanças ([comparação](docs/REFERENCIA_AUVP_FINANCAS_2026_10.md)), Copilot, Monarch, Material 3. Direção visual em `docs/DESIGN_2026_10.md`; o que vem depois em `docs/ROADMAP_2026_11.md`.

### Adicionado
- **Barra inferior:** Hoje · Extrato · Orçamento · **Investir** · Mais. Contas e cartões abrem pelo cartão de saldo do Hoje e por Mais.
- **Tipos de gasto (envelopes) por % da renda**, no modelo dos 6 orçamentos da AUVP (Custos fixos 30, Conforto 15, Metas 15, Prazeres 10, Conhecimento 5, Liberdade financeira 25), editáveis; renda de referência = renda fixa do mês, ajustável. Cada categoria de despesa tem um tipo (sugestão pelo nome); aportes contam em Liberdade financeira e depósitos em objetivos contam em Metas. Só planejamento.
- **Cobrança para conferir:** descrições que parecem tarifa, seguro, anuidade, proteção, capitalização ou serviço do banco viram aviso no Hoje, para reconhecer ou conferir com o banco.
- **Ajuda** dentro do app (Mais → Ajuda), pesquisável no texto inteiro, com as regras do Nexo.
- Formulário: **"Salvar e adicionar outro"**. Análises: receitas × despesas em **6 meses ou 1 ano**.
- Conector do assistente: receitas para Claude Code, Cursor, VS Code, Gemini CLI e Codex.

### Visual
- Hoje: saudação com o dia no lugar do slogan; pills do saldo sem cortes; uma linha rolável de atalhos; no máximo 4 avisos; comparação com o mês anterior diz "sem base" em vez de milhares de por cento.
- Extrato: título igual ao da aba, filtros numa linha, busca com dica curta, "Pago" omitido nas linhas.
- Orçamento, Investir e Mais: cabeçalhos no mesmo padrão; o botão flutuante do Orçamento virou ação do cabeçalho.
- "R$ 1.234,56" com um espaço em todo o app.

### Banco de dados
- Schema **26**: coluna `envelope` em `categories`.

## [1.12.3] - 2026-10-27
### Adicionado
- **Gasto pontual:** marque uma despesa como "Pontual" (antes "Extraordinária") e ela fica fora do ritmo do mês, das comparações com o mês anterior, das sugestões de orçamento e da média que diz quantos meses a reserva cobre. Continua no saldo, no total do mês e no "quanto posso gastar". As telas avisam quando pontuais ficaram fora de uma comparação.
- **Dados do banco ao abrir o app:** o Nexo busca o que os bancos enviaram ao abrir ou voltar ao app (no máximo a cada 15 minutos), sem esperar "Para revisar". Só chegam sugestões; nada vira lançamento sozinho.

## [1.12.2] - 2026-10-23
### Adicionado
- **Conta principal com vários bancos:** contas do banco vinculadas à mesma conta do Nexo são somadas e comparadas de uma vez, com um único ajuste neutro.
- Na fatura do cartão, botão para vincular ao cartão do banco quando ainda não há vínculo.

### Corrigido
- Depois de vincular, a fatura e o limite do banco aparecem na hora (antes esperavam até 10 minutos).

## [1.12.1] - 2026-10-23
### Adicionado
- **Fatura do banco ao lado da fatura do Nexo** (Open Finance, hoje só o Nubank expõe): total oficial, vencimento, mínimo, encargos e a diferença para o Nexo. O banco é a referência final; a diferença indica compras a conferir. Nada é lançado ou pago a partir dela.

### Servidor
- Migration `202610230002_pluggy_bills.sql` e `pluggy-sync` guardando as faturas oficiais (só totais, datas e somas).

## [1.12.0] - 2026-10-23
Dados do banco (Meu Pluggy) usados para conferir, nunca para criar dinheiro sozinhos.

### Adicionado
- **Saldo do banco × saldo do Nexo:** por conta vinculada, com a diferença e um ajuste neutro em um toque (não vira receita nem gasto).
- **"Dados do banco até…":** última movimentação recebida de cada banco, no app e para o assistente; aviso quando o dia ainda não chegou (o Open Finance atualiza uma vez por dia).
- **Limite real do cartão** vindo do banco, com alerta perto do limite.
- **Resumo do dia:** "como foi meu dia?" no assistente (`get_daily_digest`) e o dia anterior no início.
- **Vencimento que o caixa não cobre:** aviso antes da data com opções reais, incluindo quanto dá para resgatar até lá (D+2 úteis em ações/FIIs/ETFs, D+0 em renda fixa, feriados de mercado).
- **Navegação:** Hoje · Extrato · Orçamento · Contas · Mais (investimentos em Mais) e **"Mês em revisão"**.

### Corrigido
- Frescor do banco calculado pela movimentação mais recente: a data do espelho do Meu Pluggy fica parada na criação.

### Servidor
- Migrations `202610210006` e `202610230001` aplicadas; `nexo-mcp` e `pluggy-sync` republicados em 23/10.

## [1.11.0] - 2026-10-23
Evolução guiada pela sessão de conciliação de outubro (`docs/PLAN.md`). Apostas ficaram fora por decisão do dono.

### Corrigido
- **Fatura do cartão:** compra feita no dia do fechamento ("melhor dia de compra") entra na fatura seguinte, como no banco. As chaves de pagamento continuam as mesmas. Cenário real: outubro R$ 420,92, novembro R$ 213,59, total R$ 634,51.
- **Transferências sem categoria de gasto:** as novas nascem sem categoria; as antigas aparecem como "Transferência" (e ajustes como "Ajuste de saldo") em listas, exportação e assistente, sem reescrever dados.
- **Orçamento criado no meio do mês:** conta a partir da criação, com limite proporcional; os meses seguintes são cheios.

### Adicionado
- **"Para revisar":** conciliação automática das sugestões do banco (vincula ao lançamento existente, separa estorno, reserva, rendimento pequeno e Pix entre contas próprias; "Na dúvida" com "É o mesmo"; ações em lote com desfazer; regra "sempre usar esta categoria").
- **"Quanto posso gastar"** no início: por dia e no mês (renda fixa − contas fixas − pendentes − metas − gasto variável).
- **Ritmo do mês** só com gasto variável e linha pontilhada do ritmo ideal.
- **Renda fixa × extra** no mês.
- **Alertas de cobrança:** recorrente com valor diferente do previsto e cobrança repetida em poucos dias.
- **"Não vou renovar":** lembrete para cancelar antes da próxima cobrança.
- **Assistente (MCP):** faturas dos cartões (`get_card_invoices`), recusa clara quando o app instalado não conhece o pedido, tempo de espera no status e prévia antes de ignorar sugestões em lote. O app informa ao servidor o que sabe fazer.

### Ficou para depois
- Despesa dividida com reembolso abatendo o orçamento.
- `billId` da Pluggy como fonte da verdade da fatura e webhooks em vez de leitura periódica.
- Processar pedidos do assistente com o celular em segundo plano.
- Rollover e orçamento Flex; navegação Hoje · Transações · Orçamento · Cartões · Mais; mês em revisão; onboarding guiado.

## 1.2 a 1.10 — resumo (setembro e outubro de 2026)
Versões do Nexo antes deste registro detalhado; os detalhes estão nos documentos de cada rodada e no histórico de commits.

- **1.3:** previsão por período (hoje, 7, 15, 30 dias, fim do mês), regras locais para categorizar importações, busca combinada e CSV ([roadmap](docs/NEXO_ROADMAP.md)).
- **1.5:** Home analítica, análises com filtros e fechamento mensal ([NEXO_EVOLUTION_2026](docs/NEXO_EVOLUTION_2026.md)); Windows nativo 1.5.1 ([NEXO_DESKTOP](docs/NEXO_DESKTOP.md)); Home 1.5.4 ([NEXO_HOME_2026_10](docs/NEXO_HOME_2026_10.md)).
- **1.6:** investimentos ([NEXO_INVESTMENTS](docs/NEXO_INVESTMENTS.md)); 1.6.8 ativa a sincronização real entre celular e PC; 1.6.9 traz o Open Finance (Meu Pluggy) para o app.
- **1.7:** conector do Claude (1.7.0, leitura) e pedidos de lançar, corrigir e apagar gravados pelo app (1.7.1).
- **1.8:** nova Home.
- **1.9:** extrato por dia, cartões com visual de cartão, calendário de gastos e assinaturas.
- **1.10:** planejamento com limite diário e ritmo, comparação da carteira com o CDI, resumo da semana, formulário rápido e o assistente fazendo tudo o que o app faz.

Versões anteriores à 1.11.0 estão descritas nos documentos `docs/NEXO_*.md` de cada rodada.
