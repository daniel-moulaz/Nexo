# Nexo — revisão de RLS e segredos (23/10/2026)

Decisão do dono: **sem criptografia de ponta a ponta por enquanto** (o
assistente precisa ler os dados no servidor). Em troca, revisar acesso e
segredos. Resultado da revisão das migrations até `202610230001` e do código.

## Banco (Supabase `nexo-sync`)

- **Todas as 12 tabelas** ficam em esquemas privados (`nexo_sync_lab_private`,
  `nexo_mcp_private`, `nexo_pluggy_private`), com `revoke all on schema …
  from public, anon, authenticated`, **RLS ligada e nenhuma política** (nega
  tudo por padrão) e **nenhum `grant` direto em tabela**.
- O acesso é só por funções `security definer`, **todas com
  `set search_path = ''`**.
- **22 funções** liberadas a `authenticated`: todas conferem `auth.uid()` e
  só tocam linhas do próprio dono (verificado por varredura e pelos testes
  `tool/validate_sync_sql.mjs`, que cobrem anônimo bloqueado e isolamento
  entre donos).
- Funções de serviço (`nexo_pluggy_store*`, `nexo_mcp_enqueue`,
  `nexo_mcp_ledger`, `nexo_mcp_bank_status`…) só para `service_role`.
- Nenhuma função liberada a `anon` ou `public`.

## App

- O build leva só `NEXO_SUPABASE_URL` e a chave **publicável**
  (`sb_publishable_…`), feita para ficar no app. O transporte recusa chaves
  de serviço (`test/supabase_sync_transport_test.dart`).
- `tool/nexo_sync.local.json` está no `.gitignore`.
- Varredura do repositório: nenhum `sb_secret_`, JWT, `clientSecret` ou token
  `nexo_mcp_` real versionado.

## Edge Functions

- `pluggy-sync`: valida a sessão no Supabase Auth e só o dono configurado
  (`NEXO_PLUGGY_OWNER`) usa as credenciais da Pluggy; segredos só em
  secrets; respostas e logs sem credenciais.
- `nexo-mcp`: "Verify JWT" desligado de propósito; autentica pelo token do
  conector (só o hash fica no banco), escopo leitura/escrita, revogável no
  app, auditoria por chamada sem conteúdo financeiro.
- Chave de serviço lida de `SUPABASE_SERVICE_ROLE_KEY`/`SUPABASE_SECRET_KEYS`
  só dentro das funções.

## Checklist de rotação (quando suspeitar de vazamento, ou 1×/ano)

1. **Token do conector do Claude** (já vazou uma vez num print): no app,
   Sincronizar dispositivos → Claude → Desconectar; criar outro; atualizar a
   URL no Claude.
2. **Pluggy `clientSecret`**: gerar novo no dashboard da Pluggy; atualizar o
   secret `PLUGGY_CLIENT_SECRET` da função `pluggy-sync`.
3. **Chave de serviço do Supabase**: gerar nova `sb_secret_` no painel;
   apagar a antiga; as funções leem a nova automaticamente.
4. **Senha da conta Nexo (Supabase Auth)**: trocar no app; as sessões antigas
   expiram.
5. **Autorização dos bancos no Meu Pluggy**: dura 1 ano; renovar em
   meu.pluggy.ai (não renova sozinha).

## Pendências conhecidas

- Dados no servidor **sem** criptografia de ponta a ponta (decisão
  consciente; revisar se o assistente passar a rodar no aparelho).
- Supabase Vault não é usado: não há segredo guardado no banco (todos são
  secrets das funções). Se um dia houver, usar Vault, não `pgsodium`.
- Webhook da Pluggy (quando existir) precisa de cabeçalho secreto e conferir
  o IP de origem `52.67.145.81`.
