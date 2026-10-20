# Sincronização — fronteira de domínio e captura atômica (20/10/2026)

Branch `codex/nexo-investments`. Versão **1.6.6+27**, schema SQLite **25** (sem migration). Lote executado por Claude a partir do handoff de 20/10.

**O Nexo continua sem sincronizar.** Nenhum dado real foi lido, enviado ou copiado. Este lote resolve os bloqueios locais de domínio que impediam ligar o laboratório ao app; ainda faltam motor de envio/recebimento, autenticação, conflitos com interface, bootstrap e homologação entre aparelhos.

## O que mudou

### 1. Laboratório publicado e transporte endurecido (`7be004c`)

Os arquivos que estavam só locais foram versionados: `lib/sync/supabase_sync_transport.dart`, `supabase/migrations/202610160001_sync_lab.sql`, `supabase/tests/sync_lab_smoke.sql`, `tool/validate_sync_sql.mjs`.

O transporte agora classifica o corpo de erro do PostgREST por uma lista fechada de códigos do laboratório:

- `device_unavailable` → `SyncDeviceRevoked` (antes era confundido com sessão expirada, o que levaria a pedir login em loop para um aparelho revogado);
- códigos conhecidos (`operation_id_reused`, `dataset_unavailable`…) → `SyncProtocolException(código)`;
- texto desconhecido do servidor não é repassado — só o status HTTP (evita vazar conteúdo em logs/tela);
- corpo de erro limitado a 16 KiB antes de ser lido.

`test/supabase_sync_transport_test.dart` (14 testes, `MockClient`, sem rede): sessão ausente/anon/service_role não gera requisição; payload, hash e cabeçalhos exatos; 401/403/JWT expirado; 429/5xx/timeout/erro de rede com fechamento do cliente; redirecionamento recusado (token não sai do host); resposta gigante ou não JSON; recibo adulterado ou de outra operação; conflito incompleto; lacuna de cursor; limite de página.

### 2. Toda gravação financeira é uma operação de domínio nomeada (`f09258b`)

`ledgerTransaction(db, 'tipo', corpo)` substitui `db.transaction` em todos os caminhos que gravam dados do usuário: `AppProvider`, helpers do `DBHelper`, `LoanLedger`, novo `LendedLedger`, `InvestmentRepository`, metadados, regras de importação, faturas, normalização de inicialização, importação GreenStash e restore.

**Sem captura instalada — o caso de todo banco real hoje — é exatamente uma transação SQLite comum**: nenhuma tabela, gatilho ou linha extra.

Com captura instalada (`LedgerCapture.install`, hoje só em testes sintéticos; no futuro, na ativação do sync), gatilhos SQLite registram cada linha alterada e cada variação de saldo **no mesmo commit**, atribuídas à operação em curso. Por serem gatilhos, cascatas (`delete_transaction_metadata`), `INSERT OR REPLACE` e SQL bruto também são vistos — não depende de cada chamada lembrar de registrar.

| Propriedade | Como é garantida |
|---|---|
| Despesas independentes na mesma conta não conflitam | Saldo viaja como **delta inteiro em milionésimos** da moeda da conta, nunca como total; a entidade conta não inclui `balance` |
| Conta excluída/alterada em outro aparelho não gera órfão | Cada delta fixa a revisão da conta em que se baseou; divergência → `LedgerConflict('account_changed')` |
| Edição simultânea do mesmo registro | Revisão base por entidade; divergência → `concurrent_edit`, nada aplicado (rollback integral) |
| Reentrega não duplica dinheiro | `sync_applied` por ID de operação; reaplicar é no-op |
| Câmbio antigo não é recalculado | O delta registrado é o efeito exato que ocorreu localmente |
| Cotação, ouro e normalização não viram dinheiro | Escopo `derived`: capturado e descartado; cada aparelho recalcula |
| Restore não vira lote de recriações | Escopo `restore`: nada vai ao journal e uma **barreira persistente** bloqueia aplicar operações remotas até novo bootstrap |
| Escrita esquecida fora de operação | Contada em `unattributedChanges`; o motor deverá recusar envio enquanto > 0 |
| Toda tabela tem decisão de sync | Teste falha se surgir tabela fora de `ledgerTables`/`ledgerLocalTables` |

Tabelas sincronizáveis: contas, categorias, lançamentos, metadados, pagamentos de fatura, recorrentes e histórico, desejos, pessoas e registros de dinheiro emprestado, bens, orçamentos, objetivos e contribuições, empréstimos e parcelas, investimentos e operações, regras de importação. Locais: caixa de sugestões de notificação (é do aparelho), snapshots diários de patrimônio (derivados) e a tabela legada `asset_items`.

### 3. Correções de dinheiro encontradas ao rotear cada caminho

| Problema | Correção |
|---|---|
| Dinheiro emprestado gravava o saldo a partir da **cópia em memória** (`saldo_em_cache + delta`), apagando qualquer mudança feita no banco desde a última leitura; entidade e saldo em commits separados | `LendedLedger`: registro e saldo no mesmo commit, `balance = balance + ?`, estado lido do banco |
| Tocar duas vezes em "Quitar" devolvia o valor duas vezes | Quitação lê o estado gravado; segunda vez não move nada |
| Excluir um registro **em aberto** deixava o débito na conta sem explicação | Excluir em aberto estorna (como lançamento e empréstimo); desfazer reaplica; quitado é neutro |
| Edição de conta gravava o saldo da tela; com cartão, uma tela desatualizada criaria um "Ajuste do saldo do cartão" falso | Aplica só a **diferença digitada** em relação ao valor que a tela abriu |
| Excluir objetivo com dinheiro guardado das contas fazia o valor sumir; desfazer perdia as contribuições | Exclusão recusada com orientação ("Retire o valor guardado…"); desfazer restaura histórico |
| Desfazer exclusão de recorrente separava regra e histórico e deixava lembrete antigo | Regra + histórico juntos; lembrete cancelado/reagendado |
| Helpers sem chamador gravavam lançamentos/empréstimos sem mexer no saldo | Removidos |

Mudança perceptível para o usuário: **excluir um registro em aberto de dinheiro emprestado vinculado a uma conta agora devolve o valor à conta** (e o desfazer volta a debitar). Antes o débito permanecia.

### 4. Correção da suíte em checkout limpo (`d56fd91`)

O branch publicado tinha **27 testes falhando num checkout limpo** desde que `validateBackup` passou a rejeitar backups incompletos: o ajuste do `setUp` existia só na pasta local. Publicado apenas esse ajuste.

Também publicada em commit próprio a extração já integrada de `TransactionMetadata` para `lib/models/` (`6695d91`, movimento idêntico).

## Evidências

| Verificação | Resultado |
|---|---|
| Pasta integrada (inclui mudanças locais anteriores) | `flutter analyze` sem problemas; **309/309 testes** |
| Worktree limpa no commit `d56fd91` (sem arquivos locais) | analyze limpo; **298/298 testes** |
| Mesmo checkout limpo antes deste lote (`8fff22a`) | 27 falhas — corrigidas |
| Laboratório PostgreSQL/WASM | **22/22** (`node tool/validate_sync_sql.mjs`) |
| Novos testes | 14 transporte, 9 captura/replay/convergência, 7 dinheiro emprestado |

O teste central (`test/ledger_capture_test.dart`) executa no "celular" sintético praticamente todos os caminhos de escrita (contas, categorias, lançamentos pagos/pendentes/parcelados, edição, exclusão+desfazer, transferência, fatura, recorrente pago/pulado/excluído+desfazer, objetivo, dinheiro emprestado, pessoa, empréstimo, bens, orçamento, desejos, regras, metadados, investimento com caixa, cotação brapi e manual), verifica **zero escritas não atribuídas** e aplica o journal numa cópia do checkpoint no "PC": **as 19 tabelas ficam idênticas**, saldos ao milionésimo.

Builds Release com `--target lib/main.dart` na pasta integrada, versão 1.6.6+27:

- Android: `build/app/outputs/flutter-apk/app-release.apk` (75,2 MB), SHA-256 `40e82f6d2dafeb5b12cf041d257531518c5ed8fafc9e3997fb6b05d1ca144082`, certificado `54d668e0…2096` (o mesmo já instalado). **Não instalado** no aparelho.
- Windows: `build/windows/x64/runner/Release/` (pasta inteira é o bundle). Não empacotado nem homologado manualmente.

Compilar não prova o comportamento no aparelho: a validação é a suíte acima; a conferência manual do dinheiro emprestado e da exclusão de objetivo no Android fica pendente da instalação.

## Limites e o que ainda não é verdade

- Não há motor que envie o journal ao servidor ou baixe operações remotas. `SyncStore` (laboratório) ainda trabalha com sua própria projeção; o próximo lote liga o journal real ao protocolo.
- O protocolo do servidor (v1) conhece só `edits`. Para aceitar deltas de saldo e a revisão exigida da conta, precisa de **v2** (`effects` + `requires`) no SQL e no servidor de referência.
- Conflito é detectado e preservado, mas não há tela de resolução nem rebase da operação local.
- Bootstrap: o checkpoint dos testes é uma cópia de arquivo fechado, válida só em teste. Produção precisa de bootstrap por upload/download do acervo escolhido, nunca cópia de SQLite entre aparelhos.
- Valores continuam `REAL` no SQLite; o journal é inteiro (milionésimos). Migrar o armazenamento local para centavos inteiros é decisão separada, com migration sobre dados reais.
- Aplicar uma entidade remota substitui a linha inteira. Para `investments`, isso pode trazer uma cotação mais antiga do outro aparelho até a próxima atualização — cotação nunca altera dinheiro.
- Futuras migrations de schema em banco com captura instalada precisarão de escopo próprio (hoje gerariam escritas não atribuídas, o que bloquearia o envio — falha segura).
- Renomear uma conta em um aparelho enquanto o outro lança nela gera conflito (conservador). Moeda/tipo alterados precisam desse bloqueio; renomear poderia ser relaxado depois.

## Próximo lote de sync (local e sintético)

1. Protocolo v2: operação = edits + `effects` (deltas) + `requires` (revisões lidas); servidor de referência SQLite e SQL do laboratório (PGlite) validando ambos atomicamente.
2. Motor `LedgerSync`: envia `sync_journal` em ordem, recibos idempotentes, pull paginado aplicando via `LedgerCapture.apply`, cursor no mesmo commit, pausa em `unattributedChanges > 0` ou barreira de restore, `SyncDeviceRevoked`/`SyncAuthenticationRequired` como estados, não exceções soltas.
3. Conflitos persistidos com base/local/remoto; rebase explícito gera nova operação; operação local rejeitada é revertida localmente de forma compensatória e revisável.
4. Bootstrap: aparelho de origem escolhido, upload do acervo como checkpoint (revisão 1), segundo aparelho baixa em base vazia/separada.
5. Dois perfis sintéticos via servidor de referência: offline simultâneo, resposta perdida, reinício no meio, restore+sync.

Depende do usuário depois disso: aplicar a migration v2 no projeto `nexo-sync`, configurar login (e-mail/OTP), testar com dois usuários sintéticos por HTTP e, só então, decidir conscientemente o primeiro envio do acervo real.
