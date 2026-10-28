# Investimentos e saldo disponível — 1.6.5+26

## Comportamento

- Compras/aportes podem debitar uma conta de saldo em BRL. Vendas/resgates podem creditar essa conta. Ambos ficam fora do consumo e das receitas operacionais; proventos vinculados entram como receita.
- Exemplo: R$ 1.000 disponíveis, aporte de R$ 100 → R$ 900 na conta e R$ 100 na posição. Cotação posterior altera apenas o valor do investimento.
- O formulário exige escolher a conta ou selecionar explicitamente “Não movimentar conta (já registrado)”. Não escolhe a origem do dinheiro sozinho.
- Operações antigas continuam sem movimentação automática. No histórico do ativo, tocar numa operação sem conta permite vinculá-la, após confirmar que o movimento ainda não está refletido no saldo. Se o saldo já foi ajustado ou existe lançamento manual, não vincular novamente.
- Posição zerada oferece “Retirar da carteira”. Histórico e resultados permanecem preservados. “Mostrar posições retiradas” permite consultar e reexibir. Posição com quantidade positiva não pode ser retirada.
- Excluir uma operação vinculada estorna sua movimentação na mesma transação SQLite, desde que o restante do histórico continue válido. O extrato direciona a edição para Investir, impedindo alterar somente um lado.
- Conta vinculada não pode ser excluída nem convertida em cartão, ouro ou moeda estrangeira.

## Persistência e compatibilidade

Schema 24 → 25, mantendo `nexo.db` e a identidade Android:

- `investments.archived INTEGER NOT NULL DEFAULT 0`;
- `investment_operations.cash_account_id TEXT`, nulo para todo registro preexistente;
- movimento associado identificado por `investment:<operation_id>` em `transactions` e `transaction_metadata`.

Operação, movimento e saldo são gravados atomicamente. Repetir a mesma operação não repete o débito. Backup inclui os vínculos; restauração valida a correspondência antes de substituir dados e não reaplica movimentos. Não há reconciliação silenciosa de posições antigas.

## Limites

Não é conexão bancária/corretora e não executa ordens. É contabilização local das operações informadas. A conta pode representar banco ou caixa da corretora; a escolha é explícita. Cotações não alteram caixa. Esta mudança não ativa sincronização remota nem envia dados reais.

## Validação

Testes sintéticos cobrem aporte, resgate, provento, repetição idempotente, estorno, venda inválida, conta ausente, vinculação antiga, arquivamento, backup/restore repetido, backup inconsistente, migração 24→25 e proteção de edição da conta/extrato.

Validação concluída em 20/10/2026:

- `dart format` aplicado aos arquivos do lote; `flutter analyze --no-pub` sem problemas.
- `flutter test --concurrency=1 --no-pub`: **279 testes aprovados**, incluindo 9 testes de integração entre investimento e caixa.
- Builds Release Android e Windows aprovados. Builds e suíte executados no workspace com alterações anteriores preservadas; os commits incluem somente os respectivos lotes revisados.
- Android instalado por atualização (`install -r`), sucesso; aparelho confirmou `com.ma.expensy`, versão `1.6.5`, código `26`. Assinatura anterior preservada. Abertura observada até a proteção PIN/biometria; conferência visual autenticada desta versão ainda depende do desbloqueio do usuário. Nenhuma operação financeira real criada ou vinculada durante a validação.
- APK: `build/distribution/Nexo-1.6.5+26-android.apk`, SHA-256 `58958EF263A9E826E86ACF6BDC1A08F09A9A8FD1E16B32ECA8A712A62EA69C35`.
- Windows: `build/distribution/Nexo-1.6.5+26-windows-x64.zip`, SHA-256 `49E898A31F72416383D21FDA9BD7482CD9CA1B54F8AF8C10D3FB6B0F13C8C950`. Distribuir/extrair a pasta completa, incluindo DLLs e assets. Não houve nova homologação manual do executável Windows neste lote.
- Teste da interface cobre cadastro, venda e cotação; SQLite FFI exige aguardar as consultas encadeadas fora do relógio simulado do teste. Ajustado o helper de espera, sem remover as verificações de persistência.

Conferência após desbloqueio pelo usuário, em 20/10/2026:

- Home e aba Investir abertas no Android real; carteira, gráficos e consulta de cotações renderizados.
- Formulário de compra aberto: seleção “De qual conta saiu?” e orientação sobre saldo disponíveis; cancelado vazio, sem salvar.
- Detalhes de posição encerrada abertos: quantidade zero e botão “Retirar da carteira” visíveis. Botão não acionado nesta inspeção para preservar a lista do usuário.
- Nenhuma operação, vínculo ou alteração de saldo real realizada. As escritas financeiras e o arquivamento continuam validados pelos testes sintéticos descritos acima; capturas privadas não são versionadas.
