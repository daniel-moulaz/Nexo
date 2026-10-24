# Handoff completo do Nexo para Claude

Data de corte: **20/10/2026**, fuso **America/Sao_Paulo**.

Este documento foi solicitado pelo proprietário para continuar o trabalho diretamente nesta pasta, sem depender do histórico da conversa com Codex. Não é uma especificação para recomeçar o aplicativo. Preserve a implementação, os dados, o histórico e as decisões que já foram validadas.

## 1. Objetivo do usuário e forma de trabalhar

Daniel usa o Nexo de verdade no celular. Quer um painel financeiro pessoal que mostre **passado, presente e futuro**, rápido para lançar, claro para decidir e confiável para organizar compromissos. No computador quer um aplicativo produtivo, não um celular esticado.

Prioridades que motivaram o trabalho:

1. Visibilidade financeira na Home, gráficos e análises fáceis de encontrar.
2. Dívidas, cartões, recorrentes, parcelas, atrasos e previsão compreensíveis.
3. Sugestões bancárias confiáveis, revisáveis e diagnosticáveis.
4. Windows nativo offline, usando a mesma contabilidade.
5. Sincronização real celular ↔ PC, preservando trabalho offline.
6. Investimentos com experiência próxima à de um app de carteira.
7. Relatório periódico para levar ao assistente e, futuramente, entrada por mensagem.

O usuário já reclamou de rodadas que mudaram telas secundárias enquanto a Home parecia igual. Não apresentar uma lista de pequenas alterações como se fosse uma transformação da experiência. Priorizar melhoria visível e útil, poucos toques e nomenclatura comum. Ele prefere três recursos completos a dez incompletos.

Há autonomia forte para pesquisar, simplificar, consolidar telas, melhorar UX, implementar correções, refatorar com testes, adicionar dependências maduras, migrations seguras, documentação e commits. Não perguntar por cada escolha pequena ou média.

Pedir intervenção somente quando necessário por risco real de perda de dados, apagar banco, alterar identidade/assinatura, quebrar compatibilidade, credencial pessoal, serviço pago/cartão, envio de dados financeiros reais ou decisão arquitetural irreversível. Explicar concretamente a necessidade. Senhas, PIN, OTP, chave de banco, service role e chaves administrativas não devem ir para o chat/código/logs.

## 2. Estado atual confirmado

| Item | Estado no corte |
|---|---|
| Diretório real | `C:\Users\danie\projetos\Expensy` |
| Produto | Nexo |
| Branch atual | `codex/nexo-investments` |
| Versão | **1.6.5+26** em `pubspec.yaml` e confirmada no Android |
| Schema | **25**, em `lib/database/db_helper.dart` |
| Android | Instalado por atualização, sem desinstalar/limpar dados |
| Windows | Runner nativo x64, SQLite FFI, bundle Release gerado; homologação manual integral pendente |
| Sync | **Não ativo, não integrado ao app** |
| API de cotações | brapi opcional, token local seguro, cache; não é integração de corretora |
| Relatório 3/7 dias | Local, gerado no app e exportável em TXT |
| Bot Telegram/WhatsApp | Proposta, sem bot de produção |
| Validação mais recente | **279 testes aprovados**, analyze sem problemas, Release Android e Windows aprovados |
| Git | Commits publicados na branch do remoto `nexo`; muitas mudanças anteriores continuam locais |

Não afirmar que tudo foi integrado à main: o push verificado foi da branch `codex/nexo-investments`.

Última inspeção real após desbloqueio: Home abriu; Investir abriu com gráficos/cotações; formulário mostrou **“De qual conta saiu?”**, cancelado sem salvar; posição encerrada mostrou **“Retirar da carteira”**, não acionado. Nenhum lançamento, vínculo ou saldo real foi alterado durante essa inspeção. As operações de escrita foram testadas em bases sintéticas.

## 3. Git, autoria e diferenças entre pasta e GitHub

Remotos:

- `nexo`: `https://github.com/daniel-moulaz/Nexo.git` — repositório público do produto/portfólio.
- `origin`: `https://github.com/daniel-moulaz/Expensy.git` — preservado.
- `upstream`: `https://github.com/mina-android/Expensy.git` — origem do código.

A licença MIT, autoria e histórico do projeto original devem permanecer. Não apresentar Nexo como código inteiramente escrito do zero; não fabricar commits/datas para contribuições. Nenhum force push ou reescrita de autoria.

Histórico útil, do mais recente:

| Commit | Conteúdo |
|---|---|
| `c3a34b7` | Registro da conferência de investimentos no Android real |
| `46a5720` | Investimentos vinculados ao caixa, arquivamento de posição encerrada, schema 25, 1.6.5+26 |
| `dffbe3f` | Empréstimos: gravação atômica e correção de quitação antecipada por contagem dupla |
| `3c5448d` | 1.6.4+25: gráficos da carteira e histórico por ativo |
| `754e19d` | 1.6.3+24: dados brapi, logos e reorganização da navegação |
| `4f7cd7f` | 1.6.2+23: ganho/perda e custo por ativo |
| `d28a6f6` | 1.6.1+22: alertas de caixa e atalhos de recorrentes |
| `579a0ce` | Documentação da entrega inicial de investimentos |
| `e4acb18` | 1.6.0+21: carteira local e cotações opcionais |
| `1961d6b` | Estado e limites do protótipo de sync |
| `007e966` | Protocolo/journal SQLite isolado de sync e testes |

### Atenção máxima à árvore de trabalho

Existe um conjunto antigo de alterações válidas não commitadas: notificações Kotlin, formulários, faturas, backup, Windows, extração de `TransactionMetadata` para modelo e novos testes/ferramentas. O snapshot dos caminhos está em **`NEXO_HANDOFF_WORKTREE_2026_10_20.md`**.

Os builds instalados e a suíte de 279 testes usaram o **workspace integrado**, incluindo essas alterações. Portanto:

- Não substituir a pasta por clone limpo.
- Não executar reset, clean, checkout geral ou stash geral para “organizar”.
- Não apagar arquivos não rastreados: alguns são dependências do estado local.
- Não dar `git add .` e transformar tudo em um commit sem revisão.
- `lib/providers/app_provider.dart` teve commits seletivos de empréstimos/investimentos, mas conserva mudanças locais de restore.
- `lib/screens/add_transaction_screen.dart` teve commit seletivo do bloqueio de edição de movimento de investimento; outras mudanças/formatting permanecem locais.
- `lib/models/transaction_metadata.dart` está local; o serviço antigo reexporta o modelo. Evitar publicar um import sem sua dependência.
- Vários arquivos marcados como modificados podem ter diferenças de finais de linha/formatting. Comparar conteúdo, não só o status.
- `.vscode/` apareceu como não rastreado no momento deste handoff e não foi revisado; pode ser trabalho do usuário.

Primeiro classificar as diferenças por lote e validar sua coerência. Pode fazer commits seletivos de correções entendidas e testadas; não “resolver” as pendências descartando trabalho.

## 4. Regras financeiras invariáveis

| Evento | Efeito correto |
|---|---|
| Receita realizada | Aumenta saldo da conta |
| Despesa paga | Reduz saldo atual |
| Despesa pendente | Não reduz saldo atual; entra em compromissos/previsão |
| Transferência interna | Origem −, destino +, patrimônio líquido neutro, consumo zero |
| Reserva/objetivo | Movimento de patrimônio; não consumo |
| Compra no cartão | Consumo uma vez e dívida/fatura; não débito imediato no banco |
| Pagamento de fatura | Reduz banco e dívida; não novo consumo |
| Ajustes/reembolsos | Preservar classificação e semântica existentes, sem converter automaticamente em consumo |
| Aporte em investimento vinculado | Reduz caixa disponível e aumenta posição; não consumo |
| Resgate vinculado | Aumenta caixa; não nova receita operacional do valor total resgatado |
| Provento registrado e vinculado | Aumenta caixa e entra como receita |
| Cotação | Altera valor de referência do ativo, nunca saldo/quantidade/custo |
| Sugestão/importação | Revisão explícita; não alterar dinheiro silenciosamente |
| Retry/sync/conflito | Não duplicar, apagar ou inventar dinheiro |

Consumo, movimentação, saldo disponível, patrimônio e projeção são conceitos diferentes. Não usar a soma bruta das linhas `type=expense` como gasto; ler metadados e `FinanceRules`.

`accounts.balance` é materializado. Existem movimentos e ajustes históricos que impedem reconstruir tudo simplesmente somando transações. Isso é um bloqueio importante para sync: não sobrescrever/somar saldos remotos, não reaplicar importação e não recalcular câmbio antigo com cotação nova.

Antes de qualquer mudança contábil, rastrear todos os caminhos de escrita, reversão, exclusão, undo e restore. Gravar a operação inteira numa transação SQLite. Não corrigir inconsistência do usuário por adivinhação.

## 5. Mapa da implementação

### Inicialização, persistência e estado

- `lib/main.dart`: inicialização pt-BR, perfil, serviços, segurança e Provider; alvo de produção.
- `lib/database/db_helper.dart`: schema, migrations, persistência e backup/restore.
- `lib/database/database_platform.dart`: sqflite Android / SQLite FFI Windows.
- `lib/models/models.dart`: modelos centrais.
- `lib/models/transaction_metadata.dart`: extração local do modelo; verificar situação Git antes de publicar.
- `lib/services/transaction_metadata_service.dart`: persistência/reexportação dos metadados, revisão observável.
- `lib/providers/app_provider.dart`: estado e muitos limites transacionais financeiros. É grande; não refatorar tudo incidentalmente.
- `lib/services/finance_rules.dart`: classificação neutra.
- `lib/services/loan_ledger.dart`: operações de empréstimos atômicas, recém-introduzidas.

### Produto e análises

- `lib/screens/main_shell.dart`: navegação e atalhos.
- Home e telas analíticas em `lib/screens/`; localizar nomes atuais com `rg --files`.
- `lib/services/financial_analysis.dart`, `cash_forecast.dart`, `cash_timeline.dart`, `recurring_projection.dart`: análises/projeção de leitura.
- `lib/services/card_commitment.dart`, `current_invoice_summary.dart`, `card_invoice_service.dart`, `billing_cycle.dart`: compromissos e ciclos de cartão.
- `lib/services/financial_checkup.dart`: relatório de revisão financeira.
- `lib/services/entry_defaults.dart`, `quick_add_service.dart`: facilidades de lançamento.
- `lib/services/finance_export_service.dart`, `ofx_parser.dart`, `file_output.dart`, `import_rules_service.dart`: arquivos e revisão de importação.
- `lib/utils/finance_input.dart`: interpretação de valores; reutilizar para pt-BR.

### Segurança e Android

- `lib/services/nexo_security.dart`, `lib/widgets/security_gate.dart`: PIN/biometria/bloqueio.
- `lib/services/platform_capabilities.dart`: limites por plataforma.
- `lib/services/desktop_profile.dart`: perfil QA isolado.
- `lib/services/notification_inbox.dart`, regras/telas de automação.
- `android/app/src/main/kotlin/com/ma/expensy/FinancialNotificationListener.kt`, `FinancialNotificationParser.kt`, `MainActivity.kt`: captura, parsing, canais e integrações Android.

### Investimentos

- `lib/investments/investment_models.dart`: quantidade inteira com escala de seis casas, valores em centavos, custo médio e validação.
- `investment_repository.dart`: operações, cash vinculado, arquivamento, validação de backup e revisão observável.
- `investment_quotes.dart`: brapi, limites, serialização, metadados/cache.
- `investment_history.dart`: histórico ajustado, validação e cache.
- `lib/screens/investments_screen.dart`: carteira, detalhes, formulários, vínculo de operação antiga.
- `lib/widgets/portfolio_charts.dart`, `investment_price_chart.dart`, `investment_market_info.dart`: gráficos/mercado.

### Sync experimental

- `lib/sync/sync_protocol.dart`, `sync_store.dart`: protocolo e journal isolados.
- `test/support/sqlite_sync_server.dart`: servidor de referência exclusivamente para testes.
- `test/sync_protocol_test.dart`: testes sintéticos do protocolo, não integração das gravações reais do Provider.
- `lib/sync/supabase_sync_transport.dart`: transporte HTTP experimental, ainda local/não rastreado no corte.
- `supabase/migrations/202610160001_sync_lab.sql`, `supabase/tests/sync_lab_smoke.sql`, `tool/validate_sync_sql.mjs`: laboratório PostgreSQL e validação.

## 6. Experiência atual e decisões de UX

Navegação mobile com cinco destinos: **Início, Extrato, Contas, Investir, Mais**, rótulos sempre visíveis. IDs internos preservados: Home 0, Extrato 8, Contas 3, Investir 11, Mais 5; verificar `main_shell.dart` antes de alterar para não quebrar atalhos.

Home passou a priorizar saldo das contas, cartões em aberto, após cartões, alerta de falta de caixa, previsão de fim de mês, entradas/gastos, maior categoria e atalhos. Não esconder tudo em relatórios; também não empilhar dezenas de cards.

Recorrentes/dívidas passaram a evidenciar passado, atraso, próximos vencimentos e histórico. Projeções não devem gravar ocorrências nem marcar pagamentos. Confirmar pagamento exige revisar valor/conta. Não somar grupos sobrepostos de dívida num total enganoso.

Mais foi consolidado: ferramentas ocasionais recolhidas, planejamento/organização separados; “Ativos” virou “Bens e patrimônio” e “Exportar relatório” explicita saída de arquivo. Preservar acesso às ferramentas úteis, sem recuperar redundâncias.

Acessibilidade: texto ampliado, contraste, alvos de toque, modo escuro, privacidade também nos gráficos. Desktop: sidebar, tabelas, filtros, teclado, largura horizontal aproveitada; janelas/dialogs com scroll.

Referências já pesquisadas: Minhas Finanças/Nimtech, Organizze, Wallet, YNAB, Monarch, Copilot, Quicken/Simplifi; para investimentos Gorila, Investidor10, Rico e material público AUVP. A área privada AUVP **não foi inspecionada**. Usar conceitos, nunca copiar código/assets/textos/layout pixel-perfect. Links e decisões estão nos documentos de pesquisa; revalidar documentação externa quando for implementar API/serviço.

## 7. Último pedido resolvido: investimentos e disponibilidade

O usuário relatou:

1. Depois de encerrar a posição, o ativo continuava com zero na carteira.
2. Investir dinheiro não reduzia o saldo da conta/Home.

Entregue em **1.6.5+26**, detalhes em `NEXO_INVESTMENT_CASH_2026_10.md`:

- Posição zerada oferece **Retirar da carteira**, preservando operações e resultados. Lista pode mostrar posições retiradas; é arquivamento reversível, não exclusão financeira.
- Compra/aporte e venda/resgate exigem escolher conta ou explicitamente **Não movimentar conta (já registrado)**.
- Conta elegível: saldo em BRL, sem cartão/ouro. Não foi criada uma conta obrigatória nova. Pode usar uma conta de banco/caixa de corretora cadastrada, escolhida pelo usuário.
- Posição inicial antiga não debita automaticamente.
- Histórico permite vincular operação antiga a conta após confirmação de que o efeito ainda não está refletido no saldo.
- Exemplo testado: R$ 1.000 no banco + aporte de R$ 100 → R$ 900 disponíveis + R$ 100 investidos, consumo zero.
- Movimento do extrato usa ID `investment:<operation_id>` e metadados de neutralidade. Extrato impede edição isolada e direciona a Investir.
- Exclusão de operação vinculada estorna conta e operação atomicamente; valida se o restante da posição continua coerente.
- Conta com vínculo não pode ser excluída nem transformada em cartão/ouro/moeda estrangeira.
- Atualização de preço não movimenta dinheiro.
- Operações antigas reais **não foram vinculadas pelo agente**. Não vincular automaticamente nem deduzir a origem por nome.

Migration 24 → 25:

- `investments.archived INTEGER NOT NULL DEFAULT 0`;
- `investment_operations.cash_account_id TEXT`, nulo para antigos;
- banco mantém nome/identidade;
- backup inclui vínculos e valida correspondência antes da restauração; não reaplica débito.

Limites a preservar/avaliar:

- Não há corretora conectada, execução de ordens nem apuração tributária.
- O patrimônio legado de “Bens e patrimônio” não foi automaticamente consolidado com toda a carteira: evitar dupla contagem de investimentos já cadastrados como bens/contas.
- Arquivar não apaga resultado histórico. Compras reais não podem sumir do saldo pelo simples ato de ocultar.
- Se houver erro em atualização visual depois do commit, distinguir “salvo, falha ao atualizar tela” de “não salvo”; revisar antes de criar novos caminhos de retry.

Também corrigido `payLoanInstallment`: o código recarregava pagamentos e depois adicionava o pagamento mais uma vez para decidir quitação. `LoanLedger` passou a fazer principal/pagamentos/estornos atomicamente. Testes de pagamento parcial, quitação, reversão, retry e rollback foram adicionados.

## 8. brapi: o que existe e o que não prometer

Token é configurado no app e guardado no armazenamento seguro. Não extrair nem publicar. Autorização via cabeçalho; impedir vazamento por redirecionamento. Consultar somente com a opção ligada.

Implementado:

- Cotação de ações/FIIs/ETFs brasileiros conforme cobertura/plano.
- Variação do pregão separada do ganho/perda pessoal sobre custo remanescente.
- Logo SVG HTTPS do domínio permitido `icons.brapi.dev`, sem token na imagem; fallback para inicial do ticker.
- Campos opcionais de mercado: abertura, fechamento anterior, máximas/mínimas, volume, valor de mercado etc. Ausência não vira zero.
- Cache público local com timestamp, sem incluir posição/quantidade/operações/token.
- Até 20 tickers por rodada de preço, deduplicados/seriais; intervalo mínimo atual de 15 minutos no cliente.
- Gráficos da carteira: distribuição, resultado das posições abertas e proventos registrados dos seis meses.
- Histórico `/api/v2/stocks/historical`, um símbolo, `range=3mo`, `interval=1d`; UI um/três meses.
- Usa `adjustedClose`, sem misturar bruto/ajustado. Não é TWR nem rentabilidade pessoal.
- Cache do histórico após 12h, tentativas limitadas a 30min; fila compartilhada com cotações.

Renda fixa/cripto continuam manuais. Dividendos públicos, desdobramento e eventos corporativos não podem alterar saldo/quantidade automaticamente. Logos têm cache em memória, não promessa de persistência offline após reinício.

Limites do plano gratuito documentados em 19/10/2026 são referência histórica, não contrato eterno; reconsultar `https://brapi.dev/docs` e `https://brapi.dev/pricing` antes de expandir. Não “aproveitar tudo” disparando todos os endpoints ou consumindo a cota sem decisão de produto.

## 9. Sincronização: prioridade pendente e progresso real

**O pedido de sincronização foi iniciado, depois interrompido pela prioridade do caixa de investimentos. Continua pendente.**

O usuário criou um projeto Supabase `nexo-sync` na própria conta. Foi localizado no painel existente, plano Free/região São Paulo observados na sessão. Não recriar projeto, contratar plano, solicitar cartão ou acessar chaves administrativas. Identificar o projeto existente no painel e usar somente URL/chave publicável na configuração de cliente quando necessário. Credenciais não integram este handoff.

Os documentos `NEXO_SYNC_IMPLEMENTATION.md` e `NEXO_SYNC_ARCHITECTURE.md` ainda dizem em trechos antigos “projeto não criado”, schema 23 e ausência de transporte: isso descreve a etapa de 16/10, **não todo o estado de 20/10**.

### O que foi realmente feito

1. Protocolo/journal SQLite isolados, com IDs, dataset/epoch/device, hash, revisões base, outbox, recibos idempotentes, pull incremental, tombstones, conflitos preservados e barreira de restore.
2. Tabelas `sync_lab_*` somente em laboratório inicializado explicitamente. Não inicializadas no banco normal pelo app.
3. Transporte `SupabaseSyncTransport` local, aceita URL HTTPS, chave `sb_publishable_...` e fornecedor de sessão de usuário. Rejeita papel JWT administrativo como guarda contra configuração acidental; **não valida assinatura JWT localmente**. Servidor é responsável pela autenticação.
4. SQL `nexo_sync_lab_private` e RPCs `nexo_sync_lab_*` já encontrados no projeto remoto.
5. **22 testes SQL locais aprovados** com PostgreSQL/WASM PGlite. Log local `build/sync-sql-validation.log`.
6. Smoke remoto sintético executado no SQL Editor com papéis/claims simulados e rollback. Resultado observado: `synthetic_smoke_passed`, nenhum dataset/entidade/request persistido, RLS habilitado. Não confundir com autenticação HTTP de dois usuários reais.
7. Correção das operações de empréstimo para reduzir uma das fragilidades de domínio, commit `dffbe3f`.

### O que NÃO foi feito

- Não há login implementado no produto, SDK Auth integrado, refresh de sessão persistido ou pareamento.
- Não houve teste HTTP ponta a ponta autenticado Android ↔ Windows.
- Não há integração da outbox com todas as gravações reais.
- Não há UI de conflitos/resolução/rebase.
- Não há bootstrap de acervo legado nem política completa de restore integrado ao sync.
- Não há E2EE, recuperação de chaves, retenção/compactação final.
- Nenhum dado financeiro real enviado. Nenhum consentimento específico de primeiro upload concluído.
- Houve pergunta sobre e-mail para login de teste; **não houve resposta utilizável para essa etapa**. Não adivinhar e-mail ou disparar código.

### Próximo lote recomendado de sync, em ordem

1. Revisar o laboratório e separar/publicar corretamente os arquivos locais, com testes próprios do transporte HTTP: 401/403, expiração, timeout, retry, limites, resposta inválida, paginação, redirects, revogação.
2. Desenhar fronteira de domínio compartilhada. Integrar operação e outbox no mesmo commit SQLite. Cobrir também aportes/resgates/proventos de investimentos introduzidos no schema 25.
3. Resolver saldos materializados por checkpoint reconciliado + deltas idempotentes, sem “última escrita vence” em dinheiro. Despesas independentes na mesma conta não podem simplesmente sobrescrever uma à outra.
4. Auditar transferências, faturas, reservas, recorrentes, parcelas, empréstimos, dinheiro emprestado, exclusão de conta, alterações diretas de metadados e valores derivados. `LoanLedger` não corrige automaticamente os outros módulos.
5. Integrar restore com barreira persistente, nova época/acervo quando necessário e recuperação explícita. Nunca restaurar device_id, token ou cursor como se pertencessem ao novo dispositivo.
6. Implementar resolução de conflito com base/local/remoto e histórico; preservar alternativas; não limpar fila para esconder erro.
7. Autenticação oficial segura, armazenamento local de sessão, logout/revogação e RLS testados com usuários distintos por HTTP.
8. Bootstrap escolhe explicitamente o dispositivo de origem. Segundo dispositivo com dados não é mesclado por nomes/valores; apresentar plano e revisão.
9. Homologar dois dispositivos/perfis sintéticos offline, edição simultânea, resposta perdida após commit, rede interrompida, restart, restore+sync, tombstones e diferentes versões de schema.
10. Só depois apresentar ao usuário ativação real, dados incluídos, destino, backup recuperável e conflitos. Consentimento explícito antes de enviar acervo pessoal.

### Contabilidade de aceitação obrigatória

- Mesma transação e retry não duplicam.
- Transferência aplica/reverte as duas pontas juntas.
- Reserva permanece neutra.
- Fatura não duplica consumo.
- Parcelamento e ocorrência recorrente têm identidade estável e não repetem.
- Exclusão versus edição produz revisão segura.
- Dispositivos offline com mudanças simultâneas preservam tudo até resolução.
- Investimento + cash vinculado entram como unidade financeira; cotação/cache não viram dinheiro.
- Restore antigo não ressuscita exclusões nem reenvia operações já aplicadas.
- Falha parcial não avança cursor nem altera só metade do agregado.

TLS/RLS não são E2EE. PIN não é senha do servidor nem chave criptográfica. Não inventar criptografia. OTP de e-mail é candidato de UX, mas limites/SMTP do provedor precisam ser verificados; o serviço padrão não deve ser tratado como entrega pública garantida.

## 10. Windows: produto nativo e pendências de homologação

**Windows não é web.** Executa `Nexo.exe` com banco local em `%LOCALAPPDATA%\Nexo\expensy.db`.

Não copiar um banco SQLite aberto entre PC/celular, OneDrive, Drive ou pasta compartilhada como “sync”. Os dois dispositivos atualmente têm bases independentes.

Implementado:

- SQLite FFI com schema e regras comuns.
- Sidebar a partir de 900px, páginas sob demanda, tabela de transações paginada, filtros/busca, ações de editar/repetir.
- Ctrl+N, Ctrl+F, Ctrl+Enter, Tab e cancelamento por Esc no código; verificar limites de foco/bloqueio.
- PIN/secure storage Windows, perfil de teste e mutex por perfil/sessão.
- Janela inicial 1280×720, mínimo 960×640 conforme DPI; tamanho/posição não persistidos.
- CSV/TXT tabular/OFX com revisão; XLSX para exportação, não prometer importação XLSX.
- Salvamento por diálogo nativo; escrita temporária/substituição segura via `FileOutput`.
- Android-only desabilitado por `PlatformCapabilities`; sem listener bancário fictício Windows.

PIN protege acesso pela interface, **não criptografa SQLite/backups**. Windows Hello não foi ativado. Filtros persistem na sessão, não necessariamente após restart. Paginação é na UI, não SQL; parsing pesado ainda merece estudo de desempenho.

Ensaio seguro: `Nexo.exe --test-profile`; usa `%TEMP%\NexoWindowsQA\expensy.db`, prefixos e chaves QA separados. Para base nova, TEMP/TMP exclusivos somente no processo lançado. Não modificar ambiente global nem abrir base real para testes.

`tool/windows_native_check.dart` é entrypoint de teste: pode gerar bundle temporário isolado, **nunca distribuir esse alvo**. Depois reconstruir explicitamente `--target lib/main.dart`.

Pendências reais de `NEXO_WINDOWS_VALIDATION.md`: formulários e salvamento por teclado no executável, diálogos nativos de import/export/restore, controles de PIN, foco/múltiplas instâncias, maximizar/minimizar/restaurar, DPI, instalação limpa e desempenho com base grande. Há testes/widgets/ensaios nativos, mas não uma homologação manual integral.

**Nunca apertar Esc por Computer Use**: foi interpretado como encerramento da interação. Testar por código ou deixar manual. Não desligar a conectividade da automação inteira para validar offline.

## 11. Notificações: manter conservador e diagnosticável

Android captura somente apps autorizados, faz parsing conservador e gera sugestão para revisão. Nada deve virar transação automaticamente. Não persistir texto bruto, OTP, senha ou conteúdo sensível.

Mudanças locais documentadas incluem reconexão do listener, alternativas de texto, variantes de compra/Pix, inbox atualizada, confirmação da fila nativa somente depois da persistência local, proteção contra múltiplos toques e falhas de parsing.

Manter deduplicação por identidade, expiração de sugestões, tombstones e fila protegida. Notificação vs manual vs CSV não podem ser mesclados/deletados automaticamente: alertar “possível duplicata”, usuário decide.

Diagnóstico deve mostrar permissão/ativação/app, tempo e motivo genérico. Autorizações Android e restrições de APK sideload precisam de instruções claras. Não presumir todos os formatos bancários a partir de fixtures.

`NEXO_CARD_SUGGESTIONS_2026_10.md` registra ensaio Android sintético com package isolado, sugestão sem efeito no saldo antes da confirmação e persistência após registrar. Isso não prova todas as notificações reais de Nubank, Mercado Pago etc. Não ler OTPs nem copiar notificações reais para repo/testes.

Associações locais conta/cartão e categorias são sugestões editáveis, não confirmação automática.

## 12. Relatórios e entrada por mensagem

Pedido do usuário: dizer “faça o relatório” e receber revisão de três ou sete dias, idealmente usando PC/sync.

Já existe **Mais → Revisão financeira → 3 ou 7 dias → Gerar revisão → Salvar relatório TXT**. Cálculo local, comparação com período equivalente, receitas/consumo/reembolsos/categorias, contas/compromissos/orçamentos/objetivos/previsão. Nomes omitidos por padrão, mas valores/datas continuam privados. Ocultar valores bloqueia geração/exportação.

Relatório é snapshot: gerar novamente após mudar dados. No PC representa somente o banco local do PC enquanto não houver sync. Não existe rotina agendada nem acesso automático de um chat ao banco.

Pedido futuro de mensagem: “barbearia / 80 reais / cartão Nubank”, reconhecer contexto e pré-preencher. Documento `NEXO_CONVERSATIONAL_ENTRY.md`:

1. Primeiro rascunho local no app, com revisão.
2. Telegram pessoal opt-in é candidato; não há bot/token/receptor criado.
3. WhatsApp somente API oficial, custos/requisitos revisados; não automatizar WhatsApp Web.
4. Identidade autenticada, ID idempotente, fila durável, confirmação após commit, status explícito.
5. Mensagem ambígua/parcelas/conta inexistente exigem correção, não suposição.
6. Externos precisam de consentimento e infraestrutura; PC desligado não é receptor confiável.

Não criar esses recursos antes de acertar a sincronização/base de dados, nem dizer que já estão conectados.

## 13. Ambiente, comandos e distribuição

PowerShell no Windows. Paths conhecidos nesta máquina:

```powershell
$flutter = 'C:\Users\danie\develop\Flutter\flutter\bin\flutter.bat'
$dart = 'C:\Users\danie\develop\Flutter\flutter\bin\dart.bat'
$adb = 'C:\Users\danie\AppData\Local\Android\Sdk\platform-tools\adb.exe'
```

Pré-voo:

```powershell
Set-Location 'C:\Users\danie\projetos\Expensy'
git status --short
git branch --show-current
git diff --stat
git diff --cached --name-only
git log --oneline -12
git remote -v
git fetch nexo
& $flutter doctor -v
& $flutter pub get
& $flutter analyze
& $flutter test --concurrency=1
```

`fetch` não é permissão para pull/rebase/merge por cima de mudanças locais. Não mudar de branch às cegas.

Ambiente documentado em rodadas anteriores: Flutter 3.47.5/Dart 3.13.4, VS Build Tools 2022 com Desktop C++, ATL e SDK Windows. Confirmar versões locais pelo doctor; não atualizar toolchain incidentalmente.

Se falta suporte a symlink, existe `tool/prepare_windows_plugins.ps1` (junctions locais). Não alterar segurança/Developer Mode global sem necessidade. Android SDK possui build-tools 36.0.0 utilizados na última verificação.

Validação da entrega:

```powershell
# Formatar apenas os arquivos do lote, sem gerar churn nos pendentes.
& $dart format <arquivos-alterados>
& $flutter analyze
& $flutter test --concurrency=1
& $flutter build apk --release --target lib/main.dart
& $flutter build windows --release --target lib/main.dart
./tool/package_windows.ps1
```

Executar Flutter/tests/builds sequencialmente para evitar disputa de arquivos/cache. Logs em `build/`, fora do Git. `--no-pub` é aceitável após dependências resolvidas, como nas validações recentes.

Debug APK também faz parte da matriz ampla solicitada pelo usuário; o lote 1.6.5 validou **Release**. Não declarar novo Debug testado sem rodar. Para Android nativo, rodar testes específicos do app, não assumir falhas de plugins terceiros como falhas do produto.

Houve falta de disco no passado. Verificar espaço antes de builds; pode limpar cache/build regenerável identificado, não arquivos pessoais indiscriminadamente. Em PowerShell, resolver/verificar caminho antes de remover recursivamente; não misturar shell para deletar.

Instalação:

- Revalidar dispositivo com `adb devices`; não assumir serial antigo.
- Verificar package/versão e SHA-256 do certificado antes de atualizar.
- Usar `adb install -r <apk>`; nunca uninstall/clear para “resolver” migration.
- Certificado existente SHA-256: `54d668e0f56caf801de429377a7a3066dbe0ed74779f04bac1ba1d2a5b112096`.
- Certificado é o Android Debug já utilizado; preservado, não uma nova assinatura pública de produção. Não trocar por keystore diferente.
- Após instalar, pedir desbloqueio normal ao usuário se necessário. Nunca pedir PIN/senha no chat nem tentar contornar bloqueio.
- O usuário autorizou inspeção local das telas para melhorar o produto; isso não autoriza publicar dados nem inventar operações reais de teste.

Artefatos finais atuais:

- `build/distribution/Nexo-1.6.5+26-android.apk`
  - SHA-256 `58958EF263A9E826E86ACF6BDC1A08F09A9A8FD1E16B32ECA8A712A62EA69C35`.
- `build/distribution/Nexo-1.6.5+26-windows-x64.zip`
  - SHA-256 `49E898A31F72416383D21FDA9BD7482CD9CA1B54F8AF8C10D3FB6B0F13C8C950`.
- Windows completo: `build/windows/x64/runner/Release/`; não entregar só EXE.
- Sem certificado Windows/MSIX público comprado/configurado.

Não versionar APK/ZIP/build, banco real ou sintético, exportações/backups, logs, dumps, screenshots privadas, `local.properties`, `key.properties`, keystore, token ou PIN. Capturas sintéticas podem ser selecionadas conscientemente para documentação.

## 14. Testes existentes e limites das evidências

Principais arquivos:

- `test/ledger_test.dart`, `finance_rules_test.dart`, `product_rules_test.dart`: contabilidade.
- `financial_analysis_test.dart`, `cash_timeline_test.dart`, `recurring_projection_test.dart`, `financial_checkup_test.dart`: leitura/projeções.
- `card_commitment_test.dart`, `card_invoice_screen_test.dart`: cartões.
- `investment_cash_test.dart`: 9 casos de caixa/posição/backup/migration/guardas.
- `investments_test.dart`, `investment_market_test.dart`, `investment_charts_test.dart`, `investments_screen_test.dart`: carteira/API/cache/UI.
- `loan_ledger_test.dart`: atomicidade e quitação.
- `sync_protocol_test.dart`: 25 casos do laboratório no lote original; não representam app sincronizando.
- `windows_platform_test.dart`, `windows_import_test.dart`: persistência/arquivos/plataforma.
- `analysis_screens_test.dart`, `product_screens_test.dart`, `mobile_navigation_test.dart`: interface/responsividade/atalhos.
- Android tests e `tool/*check*`: ensaios específicos, alguns ainda não rastreados.

Última suíte: 279/279, aproximadamente dois minutos nesta máquina. Arquivos de log `build/cash-full-tests.log`, `build/cash-analyze-final.log`, `build/cash-android-build.log`, `build/cash-windows-build.log`.

O teste de interface SQLite FFI precisou aguardar consultas reais encadeadas entre frames; o helper `settle` de `investments_screen_test.dart` foi ajustado. Não enfraquecer asserts de persistência para fazer teste passar.

Não confundir:

- widget com base sintética ≠ fluxo manual no aparelho;
- SQL Editor com role/claims simulados ≠ autenticação HTTP;
- build Windows ≠ homologação Windows;
- cache offline ≠ teste de rede física desligada;
- commit limpo ≠ todas as mudanças locais incluídas no APK.

## 15. Ordem de leitura dos documentos

1. Este handoff e snapshot da árvore de trabalho.
2. `NEXO_INVESTMENT_CASH_2026_10.md`: entrega atual.
3. `NEXO_INVESTMENTS.md`, `NEXO_PORTFOLIO_UX_2026_10.md`, `NEXO_BRAPI_NAVIGATION_2026_10.md`, `NEXO_INVESTMENT_CHARTS_2026_10.md`: evolução da carteira.
4. `NEXO_SYNC_ARCHITECTURE.md`, `NEXO_SYNC_IMPLEMENTATION.md`, SQL e transporte locais: maior pendência.
5. `NEXO_DESKTOP.md`, `NEXO_WINDOWS_VALIDATION.md`, `NEXO_NATIVE_PROBE.md`: Windows e evidência.
6. `NEXO_HOME_2026_10.md`, `NEXO_USABILITY_2026_10.md`, `NEXO_UX_REVIEW_2026_10.md`: produto.
7. `NEXO_CARD_SUGGESTIONS_2026_10.md`, `NEXO_AUTOMATION_SECURITY.md`, `NEXO_AUDIT.md`: sugestões/segurança.
8. `NEXO_CONVERSATIONAL_ENTRY.md`, `NEXO_AI_FUTURE.md`, `NEXO_OPEN_FINANCE_FUTURE.md`: propostas, não funções prontas.
9. `NEXO_BENCHMARK_2026.md`, `NEXO_EVOLUTION_2026.md`, `NEXO_ROADMAP.md`, `NEXO_GITHUB.md`: pesquisa/histórico.

README ainda aponta 1.5.4 em trechos. Docs antigos citam schema 23/24, 142/156/196/221/265 testes e builds anteriores. Isso não invalida a evidência histórica; só não deve substituir o estado atual. Atualizar com data e escopo, sem transformar testes antigos em alegações novas.

## 16. O que fazer ao assumir

1. Ler e confrontar este handoff com o código/status real; a pasta pode ter mudado desde o corte.
2. Não reimplementar o que já existe. Explicar brevemente ao usuário o estado entendido e o próximo lote.
3. Preservar/classificar alterações locais; validar baseline.
4. Se o usuário não trouxer prioridade nova, retomar **sync seguro**, começando pelos bloqueios de domínio e testes, não pelo upload da base pessoal.
5. Fazer lotes delimitados e completos, com testes e evidência. Pequenas correções necessárias de UX/contabilidade são autorizadas.
6. Atualizar documentação e status de limitações. Revisar staging e segredos antes de cada commit; push no remoto certo. Main por integração revisada, sem alteração destrutiva.
7. Entregar: o que mudou, efeito para o usuário, schema/migration, testes, builds, instalação, commits, estado Git e pendências reais.

Não prolongar indefinidamente uma entrega concluída com melhorias não relacionadas. Também não declarar pronto por só compilar. A prioridade permanente é proteger o dinheiro e reduzir o trabalho do usuário.
