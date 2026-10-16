# Sincronização — início da implementação

Data: 16/10/2026. Branch: `codex/nexo-sync-foundation`.

## Situação real

O Nexo instalado ainda **não sincroniza celular e Windows**. Este lote implementa um protocolo e um journal SQLite isolados, exercitados com dois dispositivos fictícios e um terceiro SQLite como servidor de referência. Não há Supabase provisionado, autenticação, cliente HTTP, migração no banco do app ou opção de sincronização na interface.

Nenhum dado financeiro real foi lido para os testes ou transmitido. Nenhuma conta externa, serviço pago ou credencial foi criada. `expensy.db` e o schema de produção **23** permanecem inalterados; Android conserva identidade e assinatura.

## Código disponível

- `lib/sync/sync_protocol.dart`: operação imutável, IDs estáveis, identidade de acervo/época/dispositivo, revisão base, serialização determinística, SHA-256, recibo e contrato de transporte.
- `lib/sync/sync_store.dart`: projeção local e outbox no mesmo commit SQLite; retry persistido; recibos idempotentes; pull incremental; tombstones; conflitos que preservam base, alternativa local e remota; barreira persistente de restore.
- `test/support/sqlite_sync_server.dart`: **servidor de referência apenas para testes**, sem rede nem segurança de produção. Compara revisões e comita contador, agregado, histórico e recibo juntos.
- `test/sync_protocol_test.dart`: cenários sintéticos e falhas provocadas em SQLite real via FFI. Os exemplos financeiros usam os modelos e a classificação neutra do Nexo, mas **não passam pelos métodos de gravação de `AppProvider`**. Não são homologação da futura integração financeira.

SHA-256 detecta troca de conteúdo/ID e não fornece autenticação ou criptografia. Datas de dispositivo são apenas auditoria. Nem relógio mais recente nem último envio escolhem um vencedor financeiro.

## Persistência do experimento

Tabelas `sync_lab_binding`, `sync_lab_entities`, `sync_lab_outbox`, `sync_lab_applied` e `sync_lab_conflicts`, versão interna 1. São criadas somente quando o laboratório inicializa explicitamente um banco fornecido pelo chamador. O app não importa/inicializa este módulo. O laboratório não acessa `DBHelper`, diretórios normais do usuário, backups existentes ou banco Android.

`sync_lab_entities` conserva a revisão de entidades excluídas e a data de tombstone. A fila conserva o conteúdo base e a operação; um conflito mantém as três alternativas sem substituição automática. Recibos aceitos não avançam sozinhos o cursor de pull: ainda é necessário observar os commits intermediários. Limites por operação: 10 mil alterações e 1 MiB; 100 operações/página/passagem. Identificadores e conteúdo não aparecem nas mensagens de erro do protocolo.

As tabelas são específicas do experimento, **não uma proposta de copiar tabelas/saldos cegamente para produção**. O JSON local contém dados fictícios em texto claro; não há E2EE. Retenção/compactação e recuperação de chaves ainda precisam de implementação e testes.

## Resultados contábeis sintéticos

| Cenário | Resultado esperado e verificado no protótipo |
|---|---|
| Saldo 1.000 + receita 1.500 − despesa paga 100; pendência 80 | Saldo 2.400, consumo realizado 100, pendência preservada 80 |
| Transferir 200 a partir de saldo 1.000 | Origem 800, destino 200, total 1.000 e consumo zero |
| Reservar 200 | Conta 800, objetivo 200, consumo zero |
| Compra no cartão 120 | Banco 1.000, cartão −120, consumo 120 |
| Pagar essa fatura | Banco 880, cartão zero, consumo continua 120 |
| Três parcelas de 100 e reenvios | Uma série, dívida 300, três registros |
| Mesma ocorrência recorrente paga nos dois dispositivos | Um efeito de 80 no servidor; segunda operação fica em conflito |
| Resposta perdida depois do commit remoto | Retry do mesmo ID retorna recibo anterior, sem novo débito |
| Falha ao aplicar uma transferência | Nenhuma ponta aplicada; cursor não avança |
| Falha ao escrever histórico remoto | Contador e todas as entidades voltam juntos |
| Exclusão e backup/operação antiga | Tombstone impede recriação por revisão zero |
| Restore no journal e reinício | Barreira persiste e nenhuma requisição é enviada |

Também testados: edição simultânea com relógio incorreto; editar versus excluir; mudanças em entidades independentes; conteúdo diferente com mesmo ID; hash inválido; acervo/época incorretos; lacuna no cursor; paginação; persistência da fila; trabalho offline; barreira contra workers simultâneos na mesma instância.

## Limites que impedem ativar no app agora

1. **Saldo materializado:** duas despesas independentes na mesma conta atualmente conflitam no laboratório. Isso é deliberadamente conservador. Produção precisa de checkpoint de saldo e deltas validados por operação, sem sobrescrever `accounts.balance` nem recalcular câmbio histórico com cotação nova.
2. **Integração de domínio:** cada gravação real deve capturar uma operação e sua outbox no mesmo commit das tabelas financeiras. Transação + metadados, duas pontas da transferência, fatura, parcelas, ocorrência e reserva precisam chegar juntas. Há caminhos de empréstimos e exclusões com múltiplas gravações que exigem revisão antes de conectar o journal.
3. **Conflitos:** o protótipo para e preserva alternativas, mas não tem resolução/rebase nem tela. Não habilitar no usuário sem revisão explícita e histórico da resolução; não limpar uma fila para fazê-la parecer atualizada.
4. **Bootstrap:** escolher o dispositivo de origem; validar checkpoint/IDs e decidir explicitamente sobre dados existentes no outro aparelho. Nunca mesclar por nome/valor nem usar uma cópia SQLite aberta entre máquinas.
5. **Restore real:** a barreira testada pertence ao journal. Ainda é necessário integrá-la ao backup/restore do Nexo, com cópia recuperável, nova época/acervo e proteção contra cópia de device_id e tokens.
6. **Backend:** implementar transporte autenticado e servidor PostgreSQL; testar RLS/grants/RPCs com dois usuários diferentes, perda de sessão, dispositivo revogado e isolamento. O servidor SQLite dos testes não substitui essas validações.
7. **Privacidade:** definir criptografia adicional, pareamento e recuperação antes do uso real. TLS/RLS não equivalem a E2EE. PIN local não será senha de servidor nem chave de criptografia.
8. **Aparelhos:** testar Android ↔ Windows de verdade, incluindo rede interrompida, restart, arquivos/restauração e edição offline simultânea. Nenhum teste atual autoriza chamar sincronização de pronta.

### Pontos concretos para a integração financeira

Auditoria estática do workspace atual, sem alterar essas rotas neste lote:

| Gravação atual | Exigência antes de sincronizar |
|---|---|
| `AppProvider.addTransaction`, `updateTransaction`, `deleteTransaction` | Já agrupam lançamento, metadados e saldo em transação SQLite; capturar outbox no mesmo commit, incluindo estorno e origem importada |
| `addTransfer` | Preservar duas pontas, contas, neutralidade e eventual `card_invoice_payments` como um único agregado |
| `_completeRecurring` | Preservar identidade determinística da ocorrência, histórico e avanço da regra; rever revisão de cronograma e equivalência entre dois dispositivos |
| `_moveGoal` | Capturar contribuição/retirada, conta e objetivo juntos, mantendo conversão histórica e reserva neutra |
| Empréstimos e dinheiro emprestado | Há métodos que persistem entidade e saldo em chamadas separadas; tornar a unidade financeira atômica antes de anexar a outbox |
| `payLoanInstallment` | O código recarrega os pagamentos e depois calcula `loanTotalPaid(l) + payAmount`; verificar e corrigir a possível contagem dupla na quitação com teste específico antes da integração |
| `DBHelper.deleteAccount` | Exclusão de conta e seus lançamentos exige revisar dependências de transferência, cartão, recorrente e objetivos; não propagar cascata silenciosa |
| `TransactionMetadataService.save`, `CardInvoiceService.recordPayment` | Rotas de gravação direta precisam participar da mesma fronteira de domínio ou deixar de ser públicas para mutações financeiras |
| `_refreshGoldBalances`, `_recordNetWorthSnapshot` | São valores derivados; não gerar operações concorrentes como se fossem decisões financeiras do usuário |
| `exportAll` / `importAll` | Snapshot consistente, validação e barreira de restore; nunca restaurar cursor/token/device_id junto com dados financeiros |

Esses achados explicam por que conectar simplesmente o SQLite ao Supabase agora seria insuficiente. Os 25 testes do protocolo não corrigem nem homologam esses caminhos de produção.

## Próximo passo externo: Supabase sob controle do usuário

O usuário informou que ainda não tem conta/projeto. A configuração mínima proposta é:

1. Criar a própria conta em [Supabase Dashboard](https://supabase.com/dashboard); login e senhas ficam com o usuário.
2. Criar organização no plano **Free** e projeto exclusivo `nexo-sync`. Não adicionar cartão ou escolher plano pago. Região de São Paulo, caso disponível na criação. Guardar a senha gerada do banco em gerenciador próprio.
3. Compartilhar somente a URL do projeto e, quando necessário para configurar o cliente, a **publishable key** (`sb_publishable_...`). Não enviar senha do banco, token administrativo, `sb_secret_...` ou `service_role`.
4. Não importar extratos, backups ou dados reais no painel. O primeiro teste remoto usará apenas dados fictícios, após implementar e validar as regras de acesso.

A escolha é reversível nesta etapa: o contrato Dart não depende de Supabase. Provisionar o projeto não ativa uploads. O consentimento para transferir o acervo real será separado e mostrará quais dados/dispositivos participam.

### Custos e autenticação pesquisados

Consulta em 16/10/2026: Free custa US$ 0/mês, inclui 500 MB de banco e 5 GB de egress, até dois projetos ativos; pausa após uma semana de inatividade e não inclui backup automático. O uso local continuará funcionando quando o servidor estiver indisponível. [Preços oficiais](https://supabase.com/pricing)

Para o piloto, e-mail com código evita depender de abertura de links entre Android e Windows. O SMTP padrão, porém, aceita apenas e-mails da equipe do projeto, limita atualmente a duas mensagens por hora e não tem garantia de entrega. Portanto, não tratar o e-mail padrão como login pronto para distribuição pública; configurar SMTP próprio ou outro provedor de identidade antes disso. Nenhum serviço de e-mail foi contratado. [SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [OTP por e-mail](https://supabase.com/docs/guides/auth/auth-email-passwordless)

A chave publicável identifica o aplicativo, não o usuário. A sessão autenticada e as políticas RLS precisam restringir cada acervo; chaves secretas administrativas contornam RLS e não entram no cliente. [Chaves de API](https://supabase.com/docs/guides/getting-started/api-keys), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)

## Verificação deste lote

- Pré-voo: dependências resolvidas, análise limpa e **196 testes existentes aprovados**.
- Suíte nova isolada: **25 testes aprovados**; análise limpa e suíte completa do workspace com **221 testes aprovados**.
- Alterações anteriores: 54 entradas locais preservadas, staging inicialmente vazio. Foram encontradas mudanças legítimas de notificações, formulários e backup; não apagadas nem incluídas automaticamente no commit deste lote.
- Não houve alteração de versão do app: permanece 1.5.4+20 porque nenhuma sincronização foi exposta no produto.

Comandos reproduzíveis:

```powershell
dart format lib/sync test/sync_protocol_test.dart test/support/sqlite_sync_server.dart
flutter analyze
flutter test --concurrency=1
flutter test test/sync_protocol_test.dart --concurrency=1
```

Validação final em 16/10/2026:

- `dart format` aplicado somente aos quatro arquivos Dart novos; `flutter analyze` sem problemas.
- `flutter test --concurrency=1`: **221 aprovados**, incluindo os 25 novos. Este resultado inclui as alterações preexistentes do workspace.
- Commit de código `007e966`, verificado também em worktree temporária limpa: análise sem problemas e **25/25 testes novos aprovados**, sem depender dos arquivos locais antigos. Nessa cópia, `pub get` resolveu dependências, mas terminou com aviso/erro de criação de symlinks por ausência de Modo de Desenvolvedor do Windows. A análise e os testes usaram `--no-pub` com as dependências resolvidas; nenhuma configuração de segurança do Windows foi alterada.
- `flutter build windows --release --no-pub`: passou; saída `build/windows/x64/runner/Release/`. A pasta inteira é o bundle, não só `Nexo.exe`.
- `flutter build apk --release --no-pub`: passou; `build/app/outputs/flutter-apk/app-release.apk`, aproximadamente 73 MB.
- Builds feitos no workspace principal com as alterações locais anteriores preservadas; não distribuídos nem instalados neste lote. O módulo experimental não é importado pelo app.
- Avisos Android preexistentes de versões futuras mínimas de Gradle/AGP/Kotlin e traduções incompletas não impediram compilação. Não houve upgrade incidental de dependências.
- O schema de produção segue **23**, versão do produto **1.5.4+20**. Arquivos temporários, bancos, binários e credenciais não entram nos commits.

Nenhum resultado acima equivale a homologação Android ↔ Windows com servidor remoto.
