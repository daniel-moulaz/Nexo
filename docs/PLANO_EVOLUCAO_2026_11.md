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
| P0-3 | Projeto independente | pacote, banco, canais, docs, histórico | ver `docs/NEXO_PROJETO_INDEPENDENTE_2026_10.md` | vários | média | testes passam; só `com.ma.expensy` resta | **feito (1.12.10)** |
| P0-4 | Erros silenciosos | 94 `catch (_)` sem registro | `Diagnostics.note(area, error)` local, contagem por área, sem valores; visível em Ajuda | `lib/services/diagnostics.dart` + 11 pontos em sync, login e Open Finance | média | falhas aparecem em Ajuda › Diagnóstico; `test/diagnostics_test.dart` | **feito (1.12.13)** |

## P1 — Alto impacto

| # | Item | Referência | Solução | Arquivos | Complex. | Aceitação | Estado |
|---|---|---|---|---|---|---|---|
| P1-1 | **Busca global / paleta** | Linear, Raycast, Superhuman | Ctrl+K no Windows e a lupa do Hoje abrem uma paleta com telas, ações, contas/cartões e lançamentos; Enter executa; atalho ao lado | `lib/widgets/command_palette.dart`, `main_shell.dart`, `finance_home_screen.dart` | média | teste abre, digita "agenda", abre a Agenda; "mercado" lista o lançamento | **feito (1.12.11)** |
| P1-2 | **Lançar por texto** | Fantastical, Todoist | "mercado 45,90 ontem no roxo" abre o formulário preenchido (valor, data, conta, categoria); confirma com Salvar | `lib/services/text_entry.dart`, `add_transaction_screen.dart` (`template` + `initialDate`), paleta | média | 11 casos de parser; widget test do preenchimento | **feito (1.12.11)** |
| P1-3 | **Categoria aprendida** | Copilot | histórico de confirmações por descrição normalizada; sugere só com ≥2 e ≥60 %; alternativas no topo | `lib/services/category_memory.dart`; usar em Para revisar e no formulário | média | testes de limiar; a caixa de revisão pré-seleciona a categoria aprendida | **feito (1.12.13)**: formulário e Para revisar |
| P1-4 | **Gastos irregulares provisionados** | YNAB "For Later" | recorrente anual/semestral entra no "posso gastar" como a parte de cada mês, até o mês do vencimento | `spendable.dart`, Hoje | média | IPVA anual de 1.200 reduz em 100/mês (`spendable_test.dart`) | **feito (1.12.13)** |
| P1-5 | **Até a próxima renda** | Nubank, PocketGuard | horizonte = próxima ocorrência da maior renda recorrente; Hoje mostra "sai até lá"; entrada grande sem recorrente pergunta "é a renda do mês?" | `spendable.dart`, `finance_home_screen.dart` | média | salário dia 5: ciclo 5/10→5/11 (`spendable_test.dart`) | **feito (1.12.13)** |
| P1-6 | Diagnóstico local | — | ver P0-4 | | | | **feito (1.12.13)** |
| P1-7 | Semântica | WCAG | rótulos nos pills, nos números do Hoje e na grade do mês | `nexo_ui.dart`, Hoje, `nexo_month_grid.dart` | baixa | leitor de tela lê "Saldo em contas: R$ …" | **feito (1.12.13)**; contraste dos tons: proposto |
| P1-8 | Última leitura do banco | Organizze | "Banco lido em dd/MM às HH:mm" na caixa Para revisar | `notification_inbox_screen.dart` | baixa | texto com a hora real do item | **feito (1.12.13)** |
| P1-9 | Recorrentes sugeridas do banco | Monarch | na revisão de uma cobrança que se repete, "Parece recorrente: criar" abre o cadastro preenchido | Para revisar, `recurring_screen.dart` | média | cobranças mensais iguais mostram o chip | **feito (1.12.13)** |

## P2 — Evolução

| # | Item | Referência | Solução | Complex. | Estado |
|---|---|---|---|---|---|
| P2-1 | Fatiar `AppProvider` | auditoria | `LedgerState`, `PlanningState`, `IntegrationsState` por trás da mesma API; sem mudança de comportamento | alta | proposto |
| P2-2 | Telas gigantes | auditoria | mover cálculo de `investments_screen` e `recurring_screen` para serviços testáveis | média | proposto |
| P2-3 | PT-BR único | auditoria | 11 idiomas removidos; `app_pt.arb` é o único; seletor de idioma fora | média | **feito (1.12.13)** |
| P2-4 | Um serviço de lembretes | auditoria | `financial_reminders` absorve diário, orçamento, cartão, empréstimo e emprestado | média | proposto |
| P2-5 | Agenda em mês + replanejar | Fantastical, Structured | grade mensal com totais por dia e filtro por dia; .ics | média | **feito (1.12.13)**; "mover vencido" continua proposto |
| P2-6 | Patrimônio ao longo do tempo; proventos | Kinvo, Status Invest | série de 6 meses (contas + aportes ao custo) e proventos, no Investir | média | **feito (1.12.13)** |
| P2-7 | Estados vazios com ação | auditoria | contas, cartões, orçamento, bens, desejos e emprestado com botão | baixa | **feito (1.12.13)** |
| P2-8 | Onboarding novo | auditoria | passo de idioma removido (quatro passos); reescrita completa continua proposta | média | parcial |
| P2-9 | Objetivos travados; contas ligadas a objetivo | Monzo | cadeado no objetivo tira o valor do saldo em contas do Hoje; "conta debita de objetivo" continua proposto | média | parcial (1.12.13) |
| P2-10 | Sankey do mês; corte por comerciante | Monarch, Revolut | "De onde veio, para onde foi" e "Por estabelecimento" em Análises | média | **feito (1.12.13)** |
| P2-11 | Movimento com propósito | M3 Expressive | transição de mês, número que conta | baixa | proposto |

## P3 — Inovação

| # | Item | Referência | Observação |
|---|---|---|---|
| P3-1 | Cupom por câmera (OCR local) | Organizze | parser do cupom pronto e testado (`receipt_parser.dart`); câmera e ML Kit ainda não ligados |
| P3-2 | Extrato da B3 (Excel) | Status Invest | **feito (1.12.13)**: `b3_import.dart`, botão no Investir, sem duplicar |
| P3-3 | PTAX, IPCA, Selic | roadmap | **feito (1.12.13)**: `market_indices.dart`, cartão no Investir; Tesouro Direto continua proposto |
| P3-4 | Cartões configuráveis no Hoje | Monzo, Revolut | **feito (1.12.13)**: "Personalizar o Hoje" na paleta |
| P3-5 | Exportar .ics da Agenda | roadmap | **feito (1.12.13)**: botão na Agenda |

## Para remover ou consolidar (além do que saiu na 1.12.9)

- 12 idiomas gerados (P2-3). Serviços de notificação sobressalentes (P2-4).
- `docs/ROADMAP_2026_11.md` passa a histórico; este plano é a lista viva.
