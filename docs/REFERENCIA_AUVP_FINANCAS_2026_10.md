# Referência: AUVP "Minhas Finanças" (Finanças+) × Nexo — 27/10/2026

Exploração só de leitura do app web da AUVP (`financas.auvp.com.br`), numa
conta de teste **vazia** (acesso gratuito de 45 dias). Vi a estrutura, os
formulários e a central de ajuda (43 respostas); não vi o comportamento com
dados. Nenhum dado foi cadastrado lá nem copiado para cá.

## O que é

Controlador financeiro do **método AUVP**: toda transação entra em um dos
**6 orçamentos** (Liberdade Financeira 25%, Custos Fixos 30%, Conforto 15%,
Metas 15%, Prazeres 10%, Conhecimento 5% da renda), e o app mostra o quanto
cada um usou da meta. Web, multi-dispositivo, Open Finance direto (banco →
app, só leitura), lançamento manual, recorrências, faturas, tags, API keys e
MCP para assistentes. Outros produtos do site: **Analítica** (fundamentos de
ações/FIIs, rankings, gratuito), **PIAR** (perfil de investidor) e
**Carteira** (curso).

## Comparação

| Recurso do Finanças+ | Nexo hoje |
|---|---|
| 6 orçamentos por **% da renda** ("Devo gastar / gasto / utilizado"; em Liberdade Financeira e Metas 100% é o objetivo) | Orçamentos **por categoria em R$**, "quanto posso gastar", ritmo. Não há agrupamento por tipo de gasto nem meta em % da renda. |
| **Mês financeiro** começando no dia do salário (ex.: 5 a 4), janela mostrada ao lado do mês | Só mês-calendário (configura-se o início da semana). |
| **Mês de referência** por transação, corrigível | Cartão tem ciclo pela regra do fechamento; conta usa a data. |
| **Tags** livres (várias por transação), filtro e gráfico "por tags" | Categoria + subcategoria (texto). Sem tags múltiplas. |
| Ocultar dos relatórios, transferência interna, observações | Tem ("não contar como gasto", transferência, observação). |
| "Saídas por dia": calendário do mês com média/dia, maior dia, dias sem saída | Calendário de gastos (1.9) e "dias sem gasto" no Mês em revisão. Sem "maior dia" e média/dia no calendário. |
| Histórico 3M/6M/1A de entradas × saídas no início | Comparação com o mês anterior, análises, fechamento. Sem gráfico de 6–12 meses no Hoje. |
| Recorrência **lança 24 meses à frente** (status Lançado/Previsto/Excluído/Encerrada; editar vale do próximo mês) | Projeção sem criar lançamentos (agenda, previsão). Não copiar: lançamento antecipado cria "dinheiro" futuro no histórico. |
| Faturas: fechadas + estimativa da próxima; só para cartões conectados; organizadas pelo vencimento | Ciclo pela regra do fechamento para qualquer cartão + **fatura oficial do banco** ao lado (1.12.1). Nexo cobre mais. |
| Contas: aviso × erro de conexão, "última sincronização", reconectar × remover | Estado por conexão (ok/erro/reconectar) e "dados do banco até…". Equivalente. |
| **Alerta de possível cobrança indevida** (Itaú: seguro/tarifa/serviço pela descrição) | Alertas de valor diferente e cobrança repetida. Sem detector de tarifa/seguro/anuidade. |
| "Classificar metas automaticamente": toda transação nova recebe meta sugerida; ajuste em lote | Regras de importação ("texto contém → categoria"), conciliação em "Para revisar", lote com desfazer. Parcial: não sugere categoria para tudo. |
| Formulário: "Salvar e adicionar outra"; filtros por tipo, conta, meta, tag e **faixa de valor**; lista ou calendário; paginação | Formulário rápido com lançamentos anteriores e atalhos de data. Não tem "salvar e adicionar outro" nem filtro por faixa de valor. |
| Importação do sistema antigo com resumo (importadas/duplicadas/falhas com motivo) | Importação CSV/OFX com revisão e deduplicação. Equivalente. |
| **API keys** (10, só leitura ou leitura+escrita, validade 30/90/365 dias, 60 req/min por rota) + MCP por OAuth com receitas para Claude Code, Claude Desktop, Gemini CLI, Codex CLI, Cursor e VS Code | Conector MCP com token na URL, escopo leitura/escrita, revogável, só com instrução para o Claude.ai. Sem validade e sem receitas para outros clientes. |
| **Central de ajuda** com busca no texto das respostas, "abrir sozinha / copiar link" | Explicações pontuais ("Como chego nisso"). Sem ajuda pesquisável. |
| Onboarding em 4 passos (renda, metas, contas, organizar a primeira) | Onboarding guiado ficou para depois (`PLAN.md`, fase 6). |
| "Ideias e bugs" dentro do app | Não se aplica (uso próprio). |
| Ocultar valores, tema claro/escuro, multi-dispositivo | Tem (privacidade, tema, sync). |
| Open Finance direto: ~1 ano de histórico ao conectar, só transações efetivadas, consentimento revogável no banco | Meu Pluggy: sugestões dos últimos 35 dias, saldos, limites e faturas. Janela menor por decisão (revisão). |

## O que vale trazer (ordem sugerida)

1. **Envelopes por % da renda.** Grupos de categorias (padrão AUVP: Liberdade
   Financeira, Custos Fixos, Conforto, Metas, Prazeres, Conhecimento;
   editáveis) com meta em % da **renda fixa** que o Nexo já conhece. Tela de
   Orçamento mostra "deveria / gastou / usado"; aportes e reservas contam em
   Liberdade Financeira e Metas (100% é o objetivo). Nada muda nos lançamentos:
   é só leitura sobre as categorias. Esforço médio.
2. **Mês financeiro com dia de início.** Configuração "meu mês começa no dia
   N"; resumo do mês, orçamentos, ritmo, "quanto posso gastar" e Mês em
   revisão passam a usar essa janela, mostrada ao lado do mês ("5 out – 4
   nov"). Esforço médio-alto: muitos pontos usam `DateTime(y, m)`. Só vale se
   a renda cair em dia diferente do 1º.
3. **Alerta de cobrança para conferir.** Padrões de descrição (seguro,
   tarifa, anuidade, proteção, capitalização, assistência) marcam sugestões e
   lançamentos de cartão com "cobrança para conferir", sem concluir nada.
   Esforço baixo.
4. **Tags livres.** Várias por lançamento, filtro, gráfico "por tags" e
   busca. Esforço médio (migration + sync + MCP).
5. **Entradas × saídas em 6M/1A** no Hoje ou em Análises. Esforço baixo.
6. **Conector MCP para outros clientes + validade do token.** Receitas de
   configuração (Claude Code, Claude Desktop, Cursor, VS Code, Gemini CLI,
   Codex) na tela do conector, já que o servidor é MCP HTTP padrão; opção de
   validade (30/90/365 dias). Esforço baixo.
7. **Formulário:** "Salvar e adicionar outro"; filtro por faixa de valor.
   Esforço baixo.
8. **Ajuda dentro do app**, pesquisável, com as regras do Nexo (transferência
   não é gasto, regra do fechamento, pendente, ajuste neutro, pontual, dados
   do banco até…, o que o assistente pode fazer). Esforço baixo-médio.
9. **Checklist de primeiros passos** para perfis novos (fase 6 do plano).

## O que não copiar

- Lançar recorrentes 24 meses à frente: o Nexo projeta sem gravar, e isso
  preserva a regra "nada cria dinheiro sozinho".
- Faturas só para cartões conectados: o Nexo calcula para qualquer cartão e
  ainda mostra a oficial do banco.
- Mês de referência editável por transação: resolve o mês financeiro, mas
  abre espaço para números que não batem com o extrato; se vier, só junto
  com o item 2 e com o lançamento continuando na data real.
