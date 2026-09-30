# Sincronização Nexo — design técnico, não implementado

Revisão: 30/09/2026. Base local: SQLite `expensy.db`, schema 23. Não há servidor, cliente de sync, conta externa, transmissão, credencial ou custo contratado nesta rodada. Não chamar sincronização de pronta com base nos testes locais existentes.

## Decisão proposta

SQLite continua sendo a fonte de trabalho de cada dispositivo, com gravação e leitura offline. Propõe-se um protocolo de operações de domínio sobre PostgreSQL, com Supabase como candidato de autenticação e hospedagem. O transporte não será cópia de arquivos SQLite nem espelhamento cego de tabelas/saldos. Nenhum backend foi escolhido de forma irreversível.

| Alternativa | Adequação e custo operacional | Decisão |
|---|---|---|
| Supabase + protocolo próprio | Postgres, transações, Auth e RLS; exige implementar outbox, conflitos e monitoramento. Avaliar limites gratuitos/armazenamento/egress antes de provisionar; não assumir gratuidade permanente | Candidato preferido para protótipo sintético |
| API própria + PostgreSQL | Controle de protocolo; responsabilidade própria por identidade, atualizações, backups, disponibilidade e segurança | Viável, maior manutenção |
| PowerSync | Motor de sync e SQLite; avaliar SDK, licença, plataformas e estratégia de upload/conflitos com as invariantes Nexo | Investigar em prova isolada, não trocar o banco agora |
| Firebase/Firestore | Modelo documental diferente; a documentação Flutter ressalva Windows para desenvolvimento local, não produção | Não priorizar para Android + Windows |

Fontes: [Supabase Flutter](https://supabase.com/docs/guides/getting-started/quickstarts/flutter), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [segurança de dados](https://supabase.com/docs/guides/database/secure-data), [PowerSync Flutter 2.0](https://releases.powersync.com/announcements/powersync-dart-flutter-sdk-v2-0), [Firebase Flutter](https://firebase.google.com/docs/flutter/setup). Avaliação documental; preços não foram cotados nem serviços contratados.

## Modelo e identidade

Manter IDs existentes. Novos objetos e operações usam UUID aleatório; IDs de ocorrência têm identidade determinística por regra, revisão do cronograma e ocorrência local, sem depender do relógio do servidor. Um `dataset_id` separa acervos; `user_id` vem da identidade autenticada. `device_id` aleatório por instalação não contém nome/serial do aparelho e não volta de backup.

Migração futura aditiva, ainda não aplicada:

- `sync_entities(dataset_id, entity_type, entity_id, revision, updated_at, deleted_at, device_id)`; metadados para entidades legadas sem renomear tabelas ou IDs.
- `sync_outbox(operation_id, aggregate_id, base_revision, payload_version, payload, content_hash, attempts, next_retry_at, status)`: mesmo commit SQLite da edição financeira.
- `sync_applied(operation_id, content_hash, server_revision)`: recibos idempotentes duráveis.
- `sync_cursor(dataset_id, epoch, last_server_revision)` e `sync_devices` para confirmação de leitura.
- `sync_conflicts(conflict_id, aggregate_id, base, local, remote, resolution, created_at)` e histórico de revisões. Conteúdo financeiro exige as mesmas proteções do banco.
- `sync_tombstones(entity_type, entity_id, deleted_at, revision)`; exclusão lógica e dependências preservadas.

Datas `updated_at`/`deleted_at` ajudam auditoria, mas **não ordenam** sync e não resolvem conflitos. Relógios podem divergir. Um contador de revisão do acervo, serializado por trava transacional no servidor, produz cursor de commit sem perder transações que confirmem fora da ordem. Não usar apenas `updated_at > cursor`, nem uma sequence com lacunas de commits ainda não confirmados.

## Unidade de sincronização financeira

Uma operação representa o agregado inteiro: lançamento + metadados; transferência com as duas pontas; pagamento de fatura com conta de origem + registro de pagamento; aporte com lançamento e contribuição; criação de série de parcelas; ocorrência recorrente com histórico e avanço do cronograma. Dependências são verificadas antes de aplicar. Lotes parciais ficam em staging e não entram nos totais.

`accounts.balance` atual é um valor materializado: **não somar nem substituir saldos remotos**. Antes do primeiro sync é necessário bootstrap consistente do histórico legado e saldos atuais. A proposta é preservar um checkpoint de saldo reconciliado e registrar deltas de operações posteriores, com `affects_balance`, moeda e estado pago/pendente. Não inferir efeito de importações antigas. Se o checkpoint e o histórico não explicarem o saldo, pedir revisão explícita; não gerar ajuste invisível. Cache de saldo é recalculado somente por operações aceitas exatamente uma vez.

O primeiro acervo parte de UM dispositivo escolhido. O segundo baixa o mesmo acervo; se já tiver dados, não mesclar por semelhança. Apresentar escolha de acervo ou conciliação manual. Backups continuam possíveis; importar backup não autoriza uploads.

## Fluxo incremental e falhas

1. Comitar edição local + outbox atomicamente; UI confirma o registro local imediatamente.
2. Quando houver conectividade e consentimento, enviar operação com `operation_id` estável, hash, revisão base e versão do protocolo.
3. Servidor valida autenticação, acervo, dispositivo, invariantes e revisão base dentro de uma transação. Repetição de ID/hash devolve o recibo anterior; mesmo ID com payload diferente é erro, nunca nova operação.
4. CAS de revisão aceita a operação ou abre conflito. Persistir histórico, agregado, recibo e revisão do acervo juntos.
5. Baixar páginas após cursor, incluindo tombstones. Aplicar página/agregado e cursor no mesmo commit SQLite. Repetição não reaplica saldo; falha não avança cursor.
6. Só confirmar outbox após guardar recibo. Timeout depois do commit remoto resulta em retry do MESMO ID. Backoff exponencial com jitter, teto e botão de tentar novamente; autenticação expirada pausa rede sem bloquear trabalho local.

Realtime pode avisar que há novidades; não substitui o pull incremental. Tela futura: última sincronização, itens pendentes, conflitos e erro acionável. Sem falsa indicação de atualizado enquanto existir outbox/conflito.

## Conflitos

Edição simultânea de valor, moeda, conta, tipo, data, categoria, parcela, recorrência, status, exclusão ou metadados financeiros exige revisão. Não usar last-write-wins. Conservar base/local/remoto e exibir diferenças e impacto em saldos. Enquanto pendente, cada aparelho mantém a versão local visível com aviso; não aplica metade de uma transferência. Somente conteúdo idêntico pode ser reconhecido como equivalente automaticamente.

Excluir versus editar é conflito. Exclusão de conta com dependências é bloqueada até resolução. A escolha do usuário gera nova operação baseada na revisão remota atual; se outro dispositivo editar novamente, CAS retorna novo conflito. A auditoria preserva alternativas descartadas. Desfazer gera operação compensatória revisável, não apaga o histórico técnico.

## Tombstones, dispositivos antigos e restauração

Não eliminar tombstones por simples TTL enquanto dispositivos ativos puderem reenviar operações antigas. Dispositivo inativo pode ser revogado; para voltar, baixa checkpoint completo em nova época e passa por revisão da outbox. Exclusão confirmada não ressuscita por backup velho.

Restore exige barreira: pausar sync, criar cópia local recuperável, validar dataset/época, não restaurar identidade do dispositivo/tokens/cursor. Uma cópia antiga abre como acervo separado ou passa por reconciliação explícita. Nunca enviar o backup como lote de recriações. Testar crash em cada transição. Revogação de dispositivo corta acesso remoto; não finge apagar cópias locais de aparelho offline.

## Privacidade, criptografia e autenticação

TLS com validação de certificado padrão; autenticação por sessão, isolamento por usuário e acervo. Em Supabase, RLS em toda tabela exposta com `auth.uid()` e participação no acervo, `USING` e `WITH CHECK`; revogar grants anônimos desnecessários, testar funções/views e impedir que o cliente altere proprietário. Chave publicável não substitui RLS. Nunca embarcar `service_role`, credenciais administrativas ou strings de conexão no APK/EXE. Logs sem payload, descrição, valor, OTP ou token.

Proposta de UX: continuar sem conta para uso local; opt-in explícito “Sincronizar dispositivos”. E-mail com código temporário reduz dependência de deep links entre Android/Windows; magic link também é possível, mas exige validar redirects/PKCE. Google é alternativa posterior com configuração própria. PIN Nexo permanece exclusivamente local. Tokens em armazenamento seguro de cada SO; sessão remota expirada não bloqueia SQLite. Fonte: [autenticação sem senha por e-mail](https://supabase.com/docs/guides/auth/auth-email-passwordless).

E2EE é desejável, mas ainda não implementada: avaliar biblioteca/protocolo auditado, criptografia autenticada padrão (AES-GCM ou XChaCha20-Poly1305), chave de acervo aleatória, envelope por dispositivo, pareamento autenticado, rotação/revogação e recuperação explícita. Não usar PIN de seis dígitos como chave de acervo. TLS/RLS não são E2EE. Criptografar payloads impede validação financeira completa pelo servidor: clientes precisam validar o agregado e o servidor só consegue validar envelope/revisão/autorização. Resolver esse tradeoff e a recuperação antes de enviar dados reais; sem algoritmo caseiro ou promessa de recuperação impossível.

## Critérios obrigatórios antes de habilitar

Matriz ainda **não executada**, pois não existe motor de sync:

| Cenário | Evidência exigida |
|---|---|
| Mesma transação, retry e resposta perdida | Um registro e um efeito; ID/hash reutilizado |
| Transferência e reserva | Par atômico; patrimônio neutro; consumo zero |
| Fatura | Compra única; pagamento só afeta caixa/dívida |
| Parcelamento e recorrente | Identidade única de série/ocorrência mesmo em dois aparelhos |
| Exclusão sincronizada e excluir × editar | Tombstone preservado; conflito explícito |
| Edições simultâneas e relógio errado | Nenhuma escolha financeira por horário |
| Pull/push interrompido | Cursor e recibos coerentes; reinício idempotente |
| Ambos offline por semanas | Uso local normal; convergência após revisão |
| Restore + sync e dispositivo revogado | Não ressuscitar excluídos nem duplicar saldo |
| Migração do acervo legado/importado | Checkpoint preserva saldo e `affects_balance` |
| Autorização | Usuário A não lê/escreve B, inclusive via RPC/view |
| Criptografia e recuperação | Vetores da biblioteca, rotação, perda de chave e revogação |

Próximo lote pode implementar um servidor de teste local e dois SQLite sintéticos antes de qualquer credencial externa. Para backend real será necessário: autorização de serviço/plano/região, projeto sob controle do usuário, configuração de Auth e e-mail, política de recuperação/criptografia e consentimento separado para subir o acervo. Nenhuma senha bancária será necessária.
