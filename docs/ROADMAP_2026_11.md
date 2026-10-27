# Nexo — o melhor app possível: plano de novembro/2026

Pedido do dono (27/10): visual, ferramentas, automações, APIs e
funcionalidades, sem pressa, com referências. Fontes: AUVP Minhas Finanças
([comparação](REFERENCIA_AUVP_FINANCAS_2026_10.md)) e seu roadmap público
(em andamento: importação em lote e "porcentagem da vida financeira";
feito: tags, edição em massa, filtro por tipo, descrição do Pix), Copilot
(categorização por aprendizado com ~93% de acerto, detecção de recorrência),
Monarch, Simplifi (previsão de 30 dias), YNAB (dinheiro com função),
Nubank e Inter (saldo em destaque, atalhos, valores ocultos), Material 3.
Dados do uso real (agregados, sem valores pessoais no repositório): um mês
de uso, renda em dias variáveis (salário, bolsa, trabalho extra),
alimentação é a categoria mais frequente, gastos pequenos (R$ 20–50) são a
maioria, cartão e conta usados meio a meio, 5 recorrentes cadastradas.

Fora do escopo por decisão do dono: qualquer função ligada a apostas.

## Regras que não mudam

Local-first; nada cria ou apaga dinheiro sozinho; transferência, reserva e
aporte não são consumo; pendente não debita; pagar fatura não duplica; o
assistente pede e o app grava. Toda automação sugere, e a pessoa confirma
(ou uma regra dela confirma).

## Nível 1 — já decidido, em andamento

| # | Item | Estado |
|---|---|---|
| 1 | Barra: Hoje · Extrato · Orçamento · Investir · Mais | feito (1.12.4) |
| 2 | Passe visual: títulos, chips, pills, "R$ ", comparação com base, saudação, cabeçalhos | feito (1.12.4) |
| 3 | **Envelopes por % da renda** (6 do método AUVP, editáveis; renda de referência = renda fixa, ajustável; tipo por categoria com sugestão pelo nome) | feito (1.12.4) |
| 4 | Alerta "cobrança para conferir" (tarifa, seguro, anuidade, proteção, capitalização) | próximo |
| 5 | Tags livres, com filtro e gráfico | próximo |
| 6 | Entradas × saídas 6M/1A no Hoje; "Saídas por dia" com média e maior dia | próximo |
| 7 | Conector MCP: receitas para Claude Code, Claude Desktop, Cursor, VS Code, Gemini CLI, Codex; validade do token | próximo |
| 8 | Formulário: "Salvar e adicionar outro"; filtro por faixa de valor | próximo |
| 9 | Ajuda no app, pesquisável, com as regras do Nexo | próximo |
| 10 | Checklist de primeiros passos | próximo |

Mês financeiro com dia de início: **descartado por enquanto**, porque a
renda cai em dias variáveis; o mês-calendário continua.

## Nível 2 — automações que tiram trabalho (minha recomendação)

| # | Item | Por quê | Esforço |
|---|---|---|---|
| 11 | **Categoria por aprendizado**: cada sugestão nova recebe a categoria que a pessoa deu da última vez a uma descrição parecida (normalizada), com confiança; um toque confirma; "sempre assim" vira regra | É o que o Copilot faz de melhor; hoje só há regras manuais e conciliação | médio |
| 12 | **Recorrência detectada no banco**: cobrança do mesmo lugar, valor parecido, todo mês → "parece uma assinatura; cadastrar recorrente?" | Spotify, Vivo e "água, luz e internet" seriam detectadas sozinhas | médio |
| 13 | **Lançar por texto**: "almoço 23 nubank" vira lançamento sem assistente (parser local: valor, conta, categoria aprendida, data relativa) | Gastos pequenos e frequentes pedem entrada de 3 segundos; funciona offline | médio |
| 14 | **Escanear cupom (QR da NFC-e)**: câmera lê o QR do cupom fiscal → valor, data e loja preenchidos | Mercado e farmácia emitem NFC-e; evita digitar; pede permissão de câmera (sensível: só com aprovação) | médio |
| 15 | **Widget "quanto posso gastar hoje"** na tela inicial do Android | O número mais útil do app, sem abrir o app; já há infraestrutura de widgets | baixo |
| 16 | **Resumo de domingo** por notificação local (semana, orçamentos, próximos vencimentos) | O assistente já tem "como foi meu dia"; a notificação traz quem não abre o app | baixo |
| 17 | **Contraparte do Pix** ("Pix enviado para Fulano") guardada no lançamento → casa com Dinheiro emprestado e com transferências entre contas próprias | A AUVP fez "Descrição - Pix"; no Nexo liga com o que já existe | baixo-médio |
| 18 | **Patrimônio ao longo do tempo**: foto mensal (contas + investimentos − dívidas) e gráfico | A tabela `net_worth_snapshots` existe e nunca foi usada | baixo |
| 19 | **Previsão de caixa 30/60/90 com "dia em que zera"** e aviso antecipado | Simplifi; o Nexo já tem a linha de previsão, falta o alerta | baixo |

## Nível 3 — APIs e integrações (gratuitas)

| # | Item | Fonte | Esforço |
|---|---|---|---|
| 20 | PTAX (câmbio) e IPCA pelo Banco Central: assinatura em dólar com IOF; "poder de compra" do salário | SGS/Olinda, sem chave | baixo |
| 21 | Importação do Excel da B3 (Área do Investidor): posições e proventos | Exportação manual da B3; sem API pública | médio |
| 22 | Preços do Tesouro Direto (Tesouro Transparente, CSV diário) para posições de Tesouro | CSV público | baixo |
| 23 | Agenda de vencimentos exportável (.ics) para o Google Calendar | Arquivo, sem API | baixo |
| 24 | Backup automático na nuvem da pessoa (Drive) | Android SAF | médio |
| 25 | Webhooks da Pluggy em vez de leitura periódica | Depende do plano; conferir no Meu Pluggy | médio |
| 26 | Assistente: `get_envelopes`, `get_cash_forecast`, `get_bank_invoice`, "como foi minha semana" | MCP próprio | baixo |

## Nível 4 — polimento contínuo

Mês em revisão em PDF para compartilhar; animações e transições
consistentes; Windows com o mesmo padrão visual; desempenho das listas com
muitos lançamentos; acessibilidade (tamanho de fonte, leitores de tela).

## Como será entregue

Lotes pequenos, cada um com testes, galeria de telas conferida, commit no
nome do dono e versão instalada no celular e no PC quando fizer diferença
no uso. Qualquer item com custo, dado real enviado a terceiro, permissão
sensível (câmera) ou publicação no servidor para antes e pergunta.
