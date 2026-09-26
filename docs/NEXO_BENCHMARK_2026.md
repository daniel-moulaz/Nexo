# Benchmark de produto — Nexo

Pesquisa em 26/09/2026, antes da implementação. Base: Nexo 1.2.0, schema 21; análise limpa e 29 testes aprovados. Pesquisa documental, não teste presencial dos concorrentes. Disponibilidade varia por plataforma/plano. Ausência de confirmação não significa ausência do recurso. Nenhum código, texto de interface ou asset foi copiado.

## Matriz de referências verificadas

| Produto / fonte oficial | Recursos documentados relevantes | Aprendizado para o Nexo |
|---|---|---|
| [Minhas Finanças / Nimtech](https://play.google.com/store/apps/details?hl=pt&id=cicero.minhasfinancas) | Contas, cartões, pagamento parcial, parcelas, recorrentes, categorias/subcategorias/tags/multicategorias, agenda, busca, OFX/CSV, Excel, comparações, biometria | Principal referência: organizar o cotidiano brasileiro e manter informação acessível |
| [Minhas Finanças — site](https://minhasfinancas.app.br/) | Mia, automações, desktop, Open Finance e personalização | Automação deve poupar trabalho; Nexo permanece local e sem IA externa |
| [Organizze](https://www.organizze.com.br/) | Contas/cartões, alertas, conexão bancária e consulta por assistentes | Visão consolidada e lembretes; integração externa não é requisito para clareza |
| [Mobills](https://www.mobills.com.br/blog/mobills/como-utilizar-o-mobills/) | Objetivos, orçamento por categorias/subcategorias, alertas | Restante do orçamento deve ser compreensível sem contabilidade |
| [Nubank](https://blog.nubank.com.br/como-funcionam-as-caixinhas-do-nubank/) | Dinheiro separado por objetivos | Reserva é patrimônio, não consumo |
| [Inter](https://ajuda.inter.co/investimentos/como-criar-um-porquinho-por-objetivos) | Objetivos associados a investimentos | Nome e finalidade ajudam mais que jargão de investimento |
| [Itaú](https://www.itau.com.br/controle-de-gastos) | Controle de gastos, notificações, busca no extrato, compras recentes | Poucos passos entre resumo e detalhe |
| [Banco do Brasil](https://blog.bb.com.br/bb-me-resolve-solucoes-digitais-para-facilitar-a-rotina/) | Agenda, entradas/saídas, categorias, extrato multibanco | Uma lista cronológica responde o que vem pela frente |
| [Bradesco](https://banco.bradesco/aplicativo-bradesco/) / [BIA](https://banco.bradesco/bia/) | Acesso a serviços e assistência contextual | Ações fáceis de encontrar; não reproduzir operações bancárias |
| [PicPay](https://meajuda.picpay.com/hc/pt-br/articles/45086956651027-Como-crio-meus-Cofrinhos-Comuns) | Cofrinhos com objetivo e nome | Objetivos devem explicar quanto falta |
| [Mercado Pago](https://www.mercadopago.com.br/blog/reservas-do-mercado-pago) | Reservas por finalidade | Separar compromissos de dinheiro disponível |
| [C6](https://www.c6bank.com.br/blog/c6-assistant) | Consulta de gastos por linguagem natural e assistência | Consultas rápidas são úteis; execução financeira externa não cabe aqui |
| [Wallet](https://budgetbakers.com/en/products/wallet/features/planned-payments/) / [ajuda](https://support.budgetbakers.com/hc/en-us/sections/6961343873426-Features) | Pagamentos planejados, saldo esperado, regras | Explicar horizonte e premissas da previsão |
| [YNAB](https://www.ynab.com/features) | Metas, planejamento, progresso, dívidas | Dar propósito ao dinheiro e mostrar progresso |
| [Monarch](https://www.monarch.com/) / [regras](https://help.monarch.com/hc/en-us/articles/360048393372-Creating-Transaction-Rules) | Busca unificada, recorrentes, objetivos, regras de transação | Regras editáveis e critérios explícitos |
| [Copilot](https://help.copilot.money/en/articles/11157550-quick-start-guide) / [FAQ](https://www.copilot.money/faq) | Fluxo de caixa, orçamento opcional, recorrentes, investimentos, IA | Mostrar somente o necessário e revisar sugestões |
| [Spendee](https://help.spendee.com/article/114-what-is-spendee) | Carteiras e identificação de gastos por viagem | Organização transversal pode vir depois por tags |
| [Money Manager / Realbyte](https://www.realbyteapps.com/) | Registro e acompanhamento de receitas/despesas | Rapidez de registro e visão legível |
| [Rocket Money](https://www.rocketmoney.com/faq) | Assinaturas, próximos pagamentos, orçamento e patrimônio | Compromissos recorrentes precisam ficar visíveis |

## Cobertura funcional e prioridade

| Ideia | Prioridade | Decisão desta rodada |
|---|---|---|
| Saldo atual versus previsto; horizontes 7/15/30 dias e fim do mês | P0 | Implementar cálculo local explicado, sem alterar saldo |
| Agenda com pendências, recorrências, parcelas e faturas | P0 | Melhorar períodos e acesso às ações existentes |
| Importação com prévia e proteção de saldo | P0 | Preservar; regras locais configuráveis e revisão de possíveis duplicatas |
| Busca por período, conta, categoria, status, valor e origem | P1 | Implementar filtros em formulário vertical |
| CSV universal e XLSX | P1 | Acrescentar CSV com metadados e proteção de fórmulas |
| Privacidade em busca/widget e valores grandes | P0 | Revisar e corrigir exposições encontradas |
| Dashboard personalizável, mostrar/ocultar/reordenar | P1 | Próxima versão; não alongar Home nesta rodada |
| Tags e filtros transversais | P1 | Próxima versão com schema e exportação completos |
| Split/multicategoria | P1 | Próxima versão; pai único no saldo e filhos somente analíticos |
| Conciliação automática | NÃO IMPLEMENTAR AGORA | Sem união automática duvidosa; revisão explícita de candidatos |
| Assinaturas mensal/anual e detecção | P1 | Próxima versão; recorrentes já disponíveis, não inferir contratos automaticamente |
| Orçamentos por renda, tags e períodos arbitrários | P2 | Preservar mensal/semanal; evitar formulário excessivo |
| Objetivos vinculados a contas | P1 | Próxima versão; prevenir dupla contagem de aportes |
| Comparações e fechamento mensal | P1 | Próxima versão; relatórios atuais preservados |
| Score financeiro | NÃO IMPLEMENTAR AGORA | Evitar precisão inventada; preferir indicadores explicados |
| Modelos/favoritos, atalhos e texto livre local | P1 | Próxima versão, após medir custo do lançamento |
| Notificações por evento e widgets adicionais | P2 | Preservar existentes e revisar privacidade; sem spam |
| CSV configurável por banco e conciliação persistente | P1 | Próxima versão; manter CSV/TXT/OFX e prévia |
| Backup e restauração de novas tabelas | P0 | Obrigatório nesta rodada |
| Open Finance, sincronização, IA externa | NÃO IMPLEMENTAR AGORA | Dependências externas, custos e privacidade; documentos próprios |
| Scraping, senha bancária no app, PDF heurístico | NÃO IMPLEMENTAR AGORA | Risco e baixa confiabilidade |

## Dores e implicações

A [ajuda oficial do Wallet](https://support.budgetbakers.com/hc/en-us/articles/7149523920786-Setup-Planned-Payments) reconhece possíveis duplicações de planejados em uso offline em múltiplos dispositivos. Um [relato comunitário sobre sincronização e planejados](https://www.reddit.com/r/BudgetBakers/comments/1r5efdh/automated_bank_sync_vs_and_planned_payments/) ilustra a dúvida entre previsão e lançamento importado. São sinais qualitativos, não uma medida de frequência.

Avaliações na página oficial do Minhas Finanças pedem menor atrito em lançamento, visualização consolidada de cartões e tratamento de recebimentos parciais. A página é dinâmica: não extrapolamos esses relatos a todos os usuários. A resposta do Nexo é preservar dados, não duplicar dinheiro, explicar previsão e reduzir o caminho até o lançamento.

## Escopo aprovado por decisão de produto

Três frentes grandes: previsão/agenda, regras de importação, busca avançada. Melhorias menores: CSV, modo privado na busca, filtros que cabem na tela, datas inclusivas, indicação de vencidos, explicação de previsão, revisão de candidatos duplicados e validação de regras. Resultado e limites serão registrados na auditoria ao concluir os testes.
