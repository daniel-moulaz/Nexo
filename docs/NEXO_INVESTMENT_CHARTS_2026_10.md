# Gráficos de investimentos — 1.6.4+25

## Experiência

A aba Investir mantém o acesso direto pela navegação inferior. O painel “Carteira em gráficos” alterna entre distribuição por ativo, resultado das posições abertas e proventos registrados, sem empilhar três painéis. A busca abaixo filtra a lista de ativos; o painel continua representando a carteira inteira.

- Distribuição: valor atual, seis maiores posições e demais agrupadas; toque abre o ativo.
- Resultado: valor atual menos custo remanescente, até oito posições; ganhos verdes e perdas vermelhas. Não inclui vendas realizadas nem proventos.
- Proventos: recebimentos registrados nos seis meses do calendário, com valores mensais e total; não é previsão.
- Detalhe do ativo: linha de fechamento ajustado, janelas de um e três meses, data/preço ao tocar e datas efetivamente disponíveis.
- Modo privado oculta gráficos, valores e percentuais.

## Referências e escolhas

[Gorila](https://gorila.com.br/para-investidores/) e [Investidor10](https://investidor10.com.br/conteudo/gerenciador-de-carteira-de-investimentos-investidor10-como-funciona-e-quais-recursos-oferece-121429/) inspiram a separação entre composição e resultado. A apresentação de gráficos por ativo também aparece no [material público da Rico](https://riconnect.rico.com.vc/blog/rico-novidades/). São referências conceituais; nenhum asset ou interface proprietária foi copiado. A área privada da AUVP não foi inspecionada.

## API e integridade

Contrato: [brapi — histórico](https://brapi.dev/docs/acoes/historico), `/api/v2/stocks/historical`, um símbolo por consulta, `range=3mo`, `interval=1d`. A série usa exclusivamente `adjustedClose`; não mistura fechamentos brutos. A variação exibida é entre os pontos do gráfico, nunca apresentada como rentabilidade pessoal. Não há simulação de TWR, CDI ou histórico patrimonial a partir da posição atual.

Consulta somente com cotações habilitadas, ao abrir um ativo compatível. Cache local de dados públicos por ativo; atualização automática após 12 horas, tentativa limitada a cada 30 minutos. Cotações e histórico compartilham uma fila para evitar requisições simultâneas. Autorização no cabeçalho, sem redirecionamentos; resposta limitada e validada. Divergência de símbolo, valores inválidos, falta de cobertura ou restrição do plano preservam o cache e mostram mensagem compreensível. A disponibilidade depende do ativo e do plano contratado pelo usuário.

Não há alteração de schema (24), banco, lançamentos, custos ou saldos. A integração não envia quantidades, posições financeiras ou transações. Os logotipos e indicadores de mercado da versão anterior permanecem disponíveis.

## Validação

Testes novos cobrem parsing, dados ajustados, duplicatas, identidade do ativo, autenticação, cache, limitação de consulta, fila e recuperação após falha; widgets em 320, 412 e 1280 px; distribuição, barras, proventos, privacidade e histórico salvo offline. Os testes de tela existentes continuam cobrindo criação/venda/preço sem movimentação involuntária do caixa.

Resultados em 19/10/2026:

- `dart format` aplicado aos sete arquivos Dart deste lote; `flutter analyze --no-pub` sem problemas.
- `flutter test --no-pub --concurrency=1`: **265 testes aprovados**.
- Quatro capturas adicionais com dados sintéticos e fontes reais: 320×740, 412×915 (escuro), 1280×720 e 1920×1080. Sem overflow; distribuição e legenda lado a lado no desktop.
- Android Release gerado e instalado por atualização, preservando identidade e assinatura existentes. Confirmado `com.ma.expensy`, versão **1.6.4+25**.
- Revisão no celular real: acesso pela aba Investir, distribuição e legenda, alternância para resultado, estado vazio de proventos, abertura do detalhe e histórico real retornado pela brapi, seleção de um/três meses. Nenhum registro financeiro foi criado ou editado. Proventos preenchidos e modo privado foram verificados com fixtures nos testes, sem contaminar a base real.
- Windows Release x64 gerado e bundle completo empacotado. Layout validado por widgets/capturas; esta rodada não constitui nova homologação manual integral do executável Windows.
- Cache offline validado automaticamente; conectividade do celular não foi desligada.

Artefatos locais (não versionados):

- `build/distribution/Nexo-1.6.4+25-android.apk` — SHA256 `2415738E563600D521B6A93783173BD6A0AFC7185D26ABFE44A505749909B060`.
- `build/distribution/Nexo-1.6.4+25-windows-x64.zip` — SHA256 `65D4403669BA2E6F7963331EF1857A68F42FFB7D5E9629B8DE8FE57E6AB589DA`.

Nenhuma captura privada, token, exportação ou banco integra este documento. Alterações locais preexistentes e não relacionadas foram preservadas fora do commit.
