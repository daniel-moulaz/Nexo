# Nexo — entrada para o próximo agente

Leia **`docs/NEXO_HANDOFF_CLAUDE_2026_10_20.md` integralmente antes de alterar código**. Ele reúne o contexto do produto, estado real, regras financeiras, pendências, decisões, ambiente e roteiro de continuidade.

Leia também `docs/NEXO_HANDOFF_WORKTREE_2026_10_20.md`: há mudanças locais legítimas e arquivos não rastreados. A versão instalada foi compilada com esse workspace integrado. Um checkout limpo do GitHub não é necessariamente igual ao que está no celular.

Estado de referência em 20/10/2026:

- Pasta: `C:\Users\danie\projetos\Expensy`. Nome público: **Nexo**.
- Branch: `codex/nexo-investments`. Último commit funcional: `46a5720`; documentação da conferência Android: `c3a34b7`.
- Versão instalada Android: **1.6.5+26**. Schema SQLite: **25**.
- Identidade Android **`com.ma.expensy`**, banco **`expensy.db`**, pacote Dart **`expensy`** e certificado existente são invariantes.
- Remoto de publicação: **`nexo` → `daniel-moulaz/Nexo`**. `origin` ainda é Expensy; não trocar remotos nem fazer push no destino errado.
- **Não há sincronização de produção.** Há laboratório local, transporte experimental e laboratório Supabase sintético. Não habilitar upload real por inferência.
- Última validação do workspace: **279 testes**, análise limpa, builds Release Android e Windows. Isso não significa homologação manual completa de Windows ou sync.

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
