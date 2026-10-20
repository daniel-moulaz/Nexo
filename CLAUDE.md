# Nexo — entrada para o próximo agente

Leia **`docs/NEXO_HANDOFF_CLAUDE_2026_10_20.md` integralmente antes de alterar código**. Ele reúne o contexto do produto, estado real, regras financeiras, pendências, decisões, ambiente e roteiro de continuidade.

Leia também `docs/NEXO_HANDOFF_WORKTREE_2026_10_20.md`: há mudanças locais legítimas e arquivos não rastreados. A versão instalada foi compilada com esse workspace integrado. Um checkout limpo do GitHub não é necessariamente igual ao que está no celular.

Atualização de 20/10/2026 (Claude, lote S1 de sync): leia também **`docs/NEXO_SYNC_DOMAIN_2026_10_20.md`** (fronteira de domínio, captura atômica, correções de dinheiro, evidências) e `docs/NEXO_INTEGRATIONS_PLAN_2026_10.md` (MCP/Pluggy/ChatGPT: plano, não funcionalidade). Toda gravação de dados do usuário deve usar `ledgerTransaction`/`DBHelper.operation`; `test/ledger_capture_test.dart` falha se um caminho escapar.

Estado de referência em 20/10/2026 (fim do dia):

- Pasta: `C:\Users\danie\projetos\Expensy`. Nome público: **Nexo**.
- Branch: `codex/nexo-investments`. Commitados: sync S1 (domínio) e S2 (motor + protocolo 2), fechamento semanal e as mudanças locais antigas, publicadas em lotes revisados.
- **A pasta não tem mais mudanças locais de conteúdo.** Arquivos marcados como modificados diferem só por final de linha (inclui `lib/l10n/*` regenerado pelo build). `.vscode/` é configuração do usuário: não versionar.
- Versão do código: **1.6.7+28**. Instalada Android: **1.6.7+28** em 20/10 (verificar com `adb` antes de atualizar). Schema SQLite: **25**.
- Identidade Android **`com.ma.expensy`**, banco **`expensy.db`**, pacote Dart **`expensy`** e certificado existente são invariantes.
- Remoto de publicação: **`nexo` → `daniel-moulaz/Nexo`**. `origin` ainda é Expensy; não trocar remotos nem fazer push no destino errado.
- Plano e andamento: `docs/NEXO_PLANO_SEQUENCIA_2026_10.md` (login por e-mail pronto, bloqueado no SMTP do Supabase; MCP e Pluggy implementados e testados, não publicados).
- **Não há sincronização de produção.** A sincronização automática funciona entre perfis Windows de teste com dados fictícios (validada pelo usuário em 20/10, ver `NEXO_SYNC_DOMAIN`); dados reais e celular continuam desligados. No projeto `nexo-sync` o usuário aplicou as migrations v2 e `202610200003_sync_lab_datasets.sql`; `202610200002_mcp_connectors.sql` ainda não foi aplicada. Não habilitar upload real por inferência.
- Última validação: **347 testes** Flutter, SQL do laboratório 37/37, MCP 18/18, Pluggy 13/13, análise limpa. Testes Kotlin/instrumentados não foram reexecutados nesta rodada. Isso não significa homologação manual completa de Windows ou sync.

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
