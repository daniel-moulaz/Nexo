# Nexo — entrada para o próximo agente

Leia **`docs/NEXO_HANDOFF_CLAUDE_2026_10_20.md` integralmente antes de alterar código**. Ele reúne o contexto do produto, estado real, regras financeiras, pendências, decisões, ambiente e roteiro de continuidade.

Leia também `docs/NEXO_HANDOFF_WORKTREE_2026_10_20.md`: há mudanças locais legítimas e arquivos não rastreados. A versão instalada foi compilada com esse workspace integrado. Um checkout limpo do GitHub não é necessariamente igual ao que está no celular.

Atualização de 20/10/2026 (Claude, lote S1 de sync): leia também **`docs/NEXO_SYNC_DOMAIN_2026_10_20.md`** (fronteira de domínio, captura atômica, correções de dinheiro, evidências) e `docs/NEXO_INTEGRATIONS_PLAN_2026_10.md` (MCP/Pluggy/ChatGPT: plano, não funcionalidade). Toda gravação de dados do usuário deve usar `ledgerTransaction`/`DBHelper.operation`; `test/ledger_capture_test.dart` falha se um caminho escapar.

Estado de referência em 20/10/2026 (fim do dia):

- Pasta: `C:\Users\danie\projetos\Expensy`. Nome público: **Nexo**.
- Branch: `codex/nexo-investments`. Commitados: sync S1 (domínio) e S2 (motor + protocolo 2), fechamento semanal e as mudanças locais antigas, publicadas em lotes revisados.
- **A pasta não tem mais mudanças locais de conteúdo.** Arquivos marcados como modificados diferem só por final de linha (inclui `lib/l10n/*` regenerado pelo build). `.vscode/` é configuração do usuário: não versionar.
- Versão do código: **1.11.0+36** (fatura com a regra do fechamento do banco, caixa "Para revisar" com conciliação automática, quanto posso gastar, orçamento proporcional, alertas de cobrança; ver `CHANGELOG.md` e `docs/PLAN.md`). Antes: 1.10.0 (planejamento, CDI, resumo da semana, formulário rápido, Claude com todas as ações do app). Instalada Windows: **1.10.0+35** em 21/10 (roda de `build/windows/x64/runner/Release/Nexo.exe`: fechar o app antes de compilar). Android: **1.10.0+35** instalada em 21/10 por `adb install -r` (assinatura `54d668e0…`, dados preservados, `firstInstallTime` 26/09; verificar com `adb` antes de atualizar). Schema SQLite: **25**.
- Identidade Android **`com.ma.expensy`**, banco **`expensy.db`**, pacote Dart **`expensy`** e certificado existente são invariantes.
- Remoto de publicação: **`nexo` → `daniel-moulaz/Nexo`**. `origin` ainda é Expensy; não trocar remotos nem fazer push no destino errado.
- Plano e andamento: `docs/NEXO_PLANO_SEQUENCIA_2026_10.md` (login por senha; Pluggy e Claude/MCP **publicados e em uso** desde 21/10: Edge Functions `pluggy-sync` e `nexo-mcp` com verify JWT desligado e autenticação própria; 4 conexões Meu Pluggy: Nubank, Inter, BTG, Mercado Pago; Claude faz o mesmo que a pessoa no app — lançamentos, transferências, recorrentes, orçamentos, categorias, objetivos, fatura, contas e **ajuste de saldo neutro** (`account.adjust`), investimentos, empréstimos, dinheiro emprestado, bens e desejos — sempre como pedido que o app executa por `AssistantCommands`/`AssistantMoreCommands` com as próprias regras; 38 tipos conferidos entre servidor, SQL e app; o app 1.9.0 recusa os tipos novos como "Pedido desconhecido").
- **Sincronização real ATIVA desde 20/10/2026**: o usuário ativou no celular (consentimento, backup salvo, cópia interna, ensaio local e conferência com o servidor). Um único acervo real por conta; perfis Windows de teste só veem acervos sintéticos. O PC entra pelo botão "Entrar no acervo do celular" (cópia do banco antigo do PC em `%LOCALAPPDATA%/Nexo/backups`). Migrations aplicadas no `nexo-sync`: todas até `202610210005_mcp_all_actions.sql` (21/10; `nexo-mcp` republicado com `more_actions.ts` e `all_actions.ts`). **Pendente:** `202610210006_mcp_capabilities.sql` e redeploy do `nexo-mcp` com `invoices.ts` e as mudanças desde `3b3b72c` (o app 1.11 funciona sem eles; o relato de capacidades falha em silêncio). Segredos de função: `PLUGGY_CLIENT_ID`, `PLUGGY_CLIENT_SECRET`, `NEXO_PLUGGY_OWNER`. Dados no servidor **não** têm criptografia de ponta a ponta.
- Última validação: **415 testes** Flutter, SQL 46/46, MCP 35/35, Pluggy 17/17, roteiro `tool/sync_e2e.dart` contra o Supabase real 11/11, análise limpa. Testes Kotlin/instrumentados não foram reexecutados nesta rodada. Isso não significa homologação manual completa de Windows ou sync.

Regras permanentes:

1. Local-first e correção financeira acima da quantidade de recursos.
2. Não limpar/resetar/stashar indiscriminadamente a árvore de trabalho. Não usar `git add .`. Revisar e preservar mudanças anteriores.
3. Não alterar main diretamente, assinatura, applicationId ou banco sem migration compatível.
4. Não testar escritas na base pessoal. Fixtures, banco temporário e perfil Windows `--test-profile`.
5. Transferência/reserva/aporte não são consumo; pendente não debita caixa; pagar fatura não duplica gasto.
6. Nenhuma notificação, cotação, importação, comando de bot ou conflito técnico pode criar/apagar dinheiro silenciosamente.
7. Não versionar credenciais, banco, backups, exports, logs, builds ou screenshots reais.
8. Autonomia para decisões reversíveis, UX, correções e testes. Parar para risco real de perda, credencial pessoal, cobrança, envio de dados reais ou decisão irreversível.
9. Antes de implementar: status/branch/histórico/docs, dependências, analyze e testes sequenciais. Ao entregar: format, analyze, testes adequados, builds Android/Windows quando afetados, documentação e commits seletivos.
10. **Nunca testar Esc por Computer Use**: já interrompeu a ferramenta. Usar widgets ou validação manual. Não derrubar a rede do ambiente de automação para testar offline.

O handoff distingue fatos confirmados, mudanças somente locais e propostas. Documentos antigos podem citar versões/schema superados; não use seu título como estado atual.
