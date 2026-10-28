# Revisão de sobreposições (27/10/2026)

Pedido do dono: "implementamos coisas que meio que inutilizam outras; o
monitoramento de notificações sendo que o Open Finance já funciona". Esta
revisão lista o que ficou redundante depois do Open Finance (Pluggy, 4 bancos,
leitura uma vez por dia) e do conector MCP (Claude lê e lança direto), com uma
recomendação por item. O dono aprovou tudo em 27/10 e a remoção saiu na
**1.12.9** (itens 1 a 5). O item 6 fica como está.

## Resumo

| Função | Sobreposta por | Recomendação |
|---|---|---|
| Monitoramento de notificações (Automação) | Open Finance na mesma caixa "Para revisar" | **Remover** |
| Revisão financeira (arquivo de 3 ou 7 dias) | Conector MCP; "Mês em revisão" | **Remover** |
| Previsão detalhada | Hoje, Agenda, Orçamento, Recorrentes | **Remover** |
| Telas sem caminho de navegação (5) | Análises, Mês em revisão | **Apagar o código** |
| Dívidas e compromissos | Agenda + Recorrentes + Empréstimos | Avaliar: é o único lugar que soma tudo |
| Importar extrato | Open Finance | Manter (histórico, outros bancos, OFX) |
| Lista de desejos, Bens, Emprestado, Empréstimos | — | Manter: sem sobreposição real |

## 1. Monitoramento de notificações — remover

O que é: serviço Android que lê notificações dos apps de banco
(`FinancialNotificationListener.kt`, `FinancialNotificationParser.kt`), o
parser, a tela **Configurações › Automação** (ligar, acesso no Android, apps
permitidos, diagnóstico, "avisar quando houver compra para revisar") e a
permissão de acesso a notificações.

Por que ficou redundante: o `pluggy-sync` traz os lançamentos de Nubank,
Inter, BTG e Mercado Pago para a **mesma** caixa "Para revisar"
(`notification_suggestions` com `app_id = 'pluggy'`). Cada lançamento continua
passando pela revisão da pessoa; nada entra sozinho.

O que muda ao remover: o aviso de compra deixa de ser instantâneo (o banco
atualiza o Open Finance uma vez por dia). Em troca, saem uma permissão
sensível, um serviço em segundo plano, uma seção inteira das configurações e
cerca de 900 linhas entre Kotlin e Dart, com o teste Kotlin do parser.

Fica: a caixa "Para revisar" (só Open Finance), as **regras de categoria**
(servem à importação e ao Pluggy; passam a abrir por Importar) e "Esquecer
contas sugeridas".

## 2. Revisão financeira — remover

O que é: gera um arquivo com o resumo de 3 ou 7 dias para a pessoa colar numa
conversa e pedir uma análise (`financial_checkup_screen.dart`,
`financial_checkup.dart`). O **Fechamento semanal** (notificação de domingo)
abre essa tela.

Por que ficou redundante: o conector MCP deixa o Claude ler os mesmos dados
direto, com as regras do app, sem arquivo. "Mês em revisão" cobre a leitura
humana do período.

O que muda: o fechamento semanal passa a abrir "Mês em revisão" (ou o resumo
da semana do Hoje). Some o atalho "Revisão de 3 ou 7 dias" do Hoje e o item
em Mais.

## 3. Previsão detalhada — remover

O que é: `financial_planning_screen.dart` com "Fluxo dos próximos 30 dias",
"Inteligência do mês", "Possíveis recorrências detectadas", "Orçamentos em
atenção" e "Agenda financeira".

Por que ficou redundante: cada bloco já existe em outro lugar. Previsão e
avisos no Hoje; saldo previsto por data na Agenda; orçamentos em atenção no
Orçamento; recorrências detectadas viram aviso no Hoje (assinaturas).

O que muda: some o item "Previsão detalhada" em Mais. Nenhum dado é perdido;
é só uma tela de leitura.

## 4. Telas sem nenhum caminho de navegação — apagar

Não há botão, aba ou rota que chegue a elas; só `screens_test.dart` as abre:

- `statistics_screen.dart` (Estatísticas) e `yearly_analysis_screen.dart`
  (Análise anual): substituídas por Análises e Mês em revisão.
- `insights_screen.dart`: substituída pelos avisos do Hoje.
- `expenses_v2_screen.dart` e `incomes_screen.dart`: listas antigas,
  substituídas pelo Extrato.
- `currency_converter_screen.dart`: conversor de moedas (o app é BRL).

Apagar o código e os trechos do teste. Zero efeito para quem usa.

## 5. Dívidas e compromissos — avaliar

Soma cartões, empréstimos, parcelas e despesas pendentes em uma tela, com
"quando vence e como fica meu saldo". A Agenda mostra os mesmos vencimentos
em ordem de data, e Recorrentes/Empréstimos mostram cada parte. Se o dono
não abre essa tela, pode sair; se usa o total "o que falta pagar", vale
manter ou virar um cabeçalho da Agenda.

## 6. O que fica como está

- **Importar extrato**: histórico anterior ao Open Finance, bancos fora das 4
  conexões e OFX. Continua em Organizar e proteger.
- **Conferir com o banco**: depende do Open Finance; é o par dele.
- **Lista de desejos, Bens e patrimônio, Dinheiro emprestado, Empréstimos**:
  nichos sem outra tela que faça o mesmo. Bens alimenta o patrimônio.
- **Widgets Android** (orçamento, contas, novo lançamento, lançamento rápido).
- **Lembretes** (diário, orçamento, cartão, empréstimo, emprestado): cada um
  avisa de uma coisa diferente.

## Feito

- 1.12.8: item morto "Orçamentos e objetivos" em Mais removido; subtítulo de
  "Sincronizar dispositivos" corrigido (dizia "ainda inativa").
- 1.12.9: itens 1 a 5 removidos. O canal nativo `com.ma.expensy/automation`
  continua só para as opções de privacidade (recentes e captura de tela).
  A tabela `notification_suggestions` não muda: linhas antigas do listener
  viram lápides como antes.
