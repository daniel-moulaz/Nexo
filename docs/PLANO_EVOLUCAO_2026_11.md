# Plano de evolução do Nexo (28/10/2026)

Sai da auditoria (`docs/AUDITORIA_NEXO_2026_10.md`), da pesquisa de referências
(`docs/PESQUISA_REFERENCIAS_2026_10.md`) e das referências da AUVP
(`docs/REFERENCIA_AUVP_FINANCAS_2026_10.md`). Substitui `docs/ROADMAP_2026_11.md` como
lista de trabalho; o roadmap antigo fica como registro das ideias.

Legenda: **Estado** = feito / em andamento / proposto. Cada item tem critério de
aceitação verificável; nada aqui é dado como feito sem teste.

## Identidade do produto (o que guia as escolhas)

O Nexo é o lugar onde a pessoa **vê o dinheiro de verdade** (contas, cartões, Open
Finance, investimentos) **com as regras certas** (transferência não é gasto, pendente não
debita, fatura não duplica) e **decide rápido** (quanto posso gastar, o que sai até a
próxima renda). Local-first; o servidor sincroniza, não manda. Assistente que pede, não
escreve. Tudo que entra tem que servir a esse eixo; o resto é ruído.

## P0 — Base

| # | Item | Problema | Solução | Arquivos | Complex. | Aceitação | Estado |
|---|---|---|---|---|---|---|---|
| P0-1 | Texto grande em toda tela | Só 3 telas são verificadas a 1,5×; o overflow da 1.12.7 passou | Teste que abre as 5 abas e as telas de Mais a 412 px com 1,5× e falha em overflow | `test/scaled_text_tabs_test.dart` | baixa | teste no CI, passa | **feito (1.12.11)** |
| P0-2 | Finais de linha | CRLF e LF misturados; `git status` sujo | `.gitattributes` `* text=auto`, normalização num commit só | raiz | baixa | `git status` limpo após build | proposto (decisão do dono: commit grande) |
| P0-3 | Desvinculação do Expensy | pacote, banco, canais, docs | ver `docs/NEXO_DESVINCULACAO_EXPENSY_2026_10.md` | vários | média | testes passam; só `com.ma.expensy` resta | **feito (1.12.10)** |
| P0-4 | Erros silenciosos | 94 `catch (_)` sem registro | `Diagnostics.note(area, error)` local, contagem por área, sem valores; visível em Ajuda | `lib/services/diagnostics.dart` + pontos de captura | média | falhas de rede/IO aparecem na tela de diagnóstico | proposto |

## P1 — Alto impacto

| # | Item | Referência | Solução | Arquivos | Complex. | Aceitação | Estado |
|---|---|---|---|---|---|---|---|
| P1-1 | **Busca global / paleta** | Linear, Raycast, Superhuman | Ctrl+K no Windows e a lupa do Hoje abrem uma paleta com telas, ações, contas/cartões e lançamentos; Enter executa; atalho ao lado | `lib/widgets/command_palette.dart`, `main_shell.dart`, `finance_home_screen.dart` | média | teste abre, digita "agenda", abre a Agenda; "mercado" lista o lançamento | **feito (1.12.11)** |
| P1-2 | **Lançar por texto** | Fantastical, Todoist | "mercado 45,90 ontem no roxo" abre o formulário preenchido (valor, data, conta, categoria); confirma com Salvar | `lib/services/text_entry.dart`, `add_transaction_screen.dart` (`template` + `initialDate`), paleta | média | 11 casos de parser; widget test do preenchimento | **feito (1.12.11)** |
| P1-3 | **Categoria aprendida** | Copilot | histórico de confirmações por descrição normalizada; sugere só com ≥2 e ≥60 %; alternativas no topo | `lib/services/category_memory.dart`; usar em Para revisar e no formulário | média | testes de limiar; a caixa de revisão pré-seleciona a categoria aprendida | parcial (serviço + texto; Para revisar: proposto) |
| P1-4 | **Gastos irregulares provisionados** | YNAB "For Later" | recorrente anual/semestral gera "reservado por mês" no envelope; o Hoje desconta do "posso gastar" | `recurring_projection.dart`, `spendable.dart`, Orçamento | média | IPVA anual de 1.200 reduz o "posso gastar" em 100/mês | proposto |
| P1-5 | **Até a próxima renda** | Nubank, PocketGuard | horizonte = data da próxima renda recorrente (ou confirmada); Hoje mostra "sai até lá" e "posso gastar por dia até lá"; entrada grande sem recorrente pergunta "é a renda do mês?" | `spendable.dart`, `finance_home_screen.dart`, caixa Para revisar | média | com renda dia 7, o cálculo usa 7/11 em vez de 31/10 | proposto |
| P1-6 | Diagnóstico local | — | ver P0-4 | | | | proposto |
| P1-7 | Semântica | WCAG | rótulos nos pills e números grandes; ordem de foco; contraste dos tons | `nexo_ui.dart`, Hoje | baixa | leitor de tela lê "Saldo em contas, 17 mil…" | proposto |
| P1-8 | Última leitura do banco | Organizze | "lido às 06:12 · próxima leitura amanhã" na caixa Para revisar e em Contas | `pluggy_inbox.dart`, telas | baixa | texto aparece com a hora real do item | proposto |
| P1-9 | Recorrentes sugeridas do banco | Monarch | `subscription_detector` sobre as sugestões do Open Finance aceitas; botão "virar recorrente" | `subscription_detector.dart`, Para revisar | média | três cobranças mensais iguais geram a sugestão | proposto |

## P2 — Evolução

| # | Item | Referência | Solução | Complex. | Estado |
|---|---|---|---|---|---|
| P2-1 | Fatiar `AppProvider` | auditoria | `LedgerState`, `PlanningState`, `IntegrationsState` por trás da mesma API; sem mudança de comportamento | alta | proposto |
| P2-2 | Telas gigantes | auditoria | mover cálculo de `investments_screen` e `recurring_screen` para serviços testáveis | média | proposto |
| P2-3 | PT-BR único | auditoria | remover os 12 idiomas gerados ou completar a tradução; decisão do dono | média | proposto |
| P2-4 | Um serviço de lembretes | auditoria | `financial_reminders` absorve diário, orçamento, cartão, empréstimo e emprestado | média | proposto |
| P2-5 | Agenda em mês + replanejar | Fantastical, Structured | grade mensal com totais por dia; vencido: pular, pagar hoje, mover | média | proposto |
| P2-6 | Patrimônio ao longo do tempo; proventos | Kinvo, Status Invest | série mensal (contas + investimentos) e proventos por mês no Investir | média | proposto |
| P2-7 | Estados vazios com ação | auditoria | cada lista vazia ensina e tem o botão certo | baixa | proposto |
| P2-8 | Onboarding novo | auditoria | três passos: contas, renda e envelopes; restaurar backup ou entrar no acervo | média | proposto |
| P2-9 | Objetivos travados; contas ligadas a objetivo | Monzo | objetivo "trancado" sai do saldo livre; recorrente debita de um objetivo | média | proposto |
| P2-10 | Sankey do mês; corte por comerciante | Monarch, Revolut | em Análises | média | proposto |
| P2-11 | Movimento com propósito | M3 Expressive | transição de mês, número que conta | baixa | proposto |

## P3 — Inovação

| # | Item | Referência | Observação |
|---|---|---|---|
| P3-1 | Cupom por câmera (OCR local) | Organizze | ML Kit no Android; Windows fica sem |
| P3-2 | Extrato da B3 (Excel) | Status Invest | parser + conciliação com `investment_operations` |
| P3-3 | Tesouro Direto, PTAX, IPCA | roadmap | APIs públicas, sem custo |
| P3-4 | Widgets configuráveis no Hoje | Monzo, Revolut | ordem e visibilidade dos cartões por pessoa |
| P3-5 | Exportar .ics da Agenda | roadmap | compromissos no calendário do sistema |

## Para remover ou consolidar (além do que saiu na 1.12.9)

- 12 idiomas gerados (P2-3). Serviços de notificação sobressalentes (P2-4).
- `docs/ROADMAP_2026_11.md` passa a histórico; este plano é a lista viva.
