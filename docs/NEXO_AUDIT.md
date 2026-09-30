# Nexo — auditorias 1.2.0 e 1.3.0

Auditoria da rodada 1.5, com Home/Análises e automação: [NEXO_EVOLUTION_2026.md](NEXO_EVOLUTION_2026.md). Schema permanece 23; main e dados existentes preservados.

A seção final registra a rodada de produto 1.3.0. Os resultados e hashes de 1.2.0 abaixo são históricos.

## Base 1.2.0

Base integrada: `0219769814a40fa02148359291eff5dcde391731`, exclusivamente em `feat/finance-app-base`.
Identificador Android preservado: `com.ma.expensy`. Banco preservado: `expensy.db`.

## Correções principais

- Compilação: imports do seletor de moeda, parâmetro inválido e avisos de código sem uso.
- Lançamentos: gravação atômica de transação, metadados e saldo; pendentes não movimentam saldo até a efetivação; edição e exclusão revertem somente o efeito efetivamente aplicado.
- Recorrentes: formulário com validação explícita; ocorrência identificada por recorrente/data; conclusão e histórico na mesma transação; proteção contra toque duplo/tela desatualizada; pular não cria lançamento; preservação do tipo e do dia original após meses curtos.
- Transferências: contas bancárias disponíveis; duas pontas atômicas e neutras nos relatórios; exclusão de uma ponta remove o par; desfazer restaura ambas.
- Cartões: fechamento inclui todo o dia; vencimento no mesmo mês quando posterior ao fechamento; datas limitadas ao último dia válido; navegação por faturas; pagamento total/parcial atômico, sem novo gasto; saldo inicial aparece como ajuste neutro pagável; créditos recebidos no cartão reduzem a fatura.
- Parcelas: informar o valor **por parcela** e a parcela atual. `3 de 12` cria as dez parcelas restantes, sem inventar as anteriores. Parcelas bancárias futuras ficam previstas; no cartão comprometem o limite. Editar/excluir atua na parcela selecionada, conforme aviso do formulário.
- Orçamento: tela simplificada; período mensal/semanal; gastos neutros excluídos; limite superior do período corrigido; percentual corrigido (antes multiplicava por 140); aviso visual a partir de 75%; prévia aceita vírgula.
- Objetivos: contas bancárias disponíveis, aportes/retiradas atômicos, bloqueio de retirada acima do saldo, prazo e recomendação mensal.
- Importação: CSV/TXT e OFX SGML/XML; prévia, conta de destino, correção manual da classificação, deduplicação por conta, preservação do saldo por padrão e preservação desse comportamento ao editar/excluir histórico importado.
- Excel: Resumo, Transações, Contas, Cartões, Orçamentos e Objetivos; valores numéricos e metadados financeiros.
- Interface: Nexo, PT-BR, valores e datas brasileiros, ações rápidas na home, agenda, menus agrupados, dropdowns responsivos e barra inferior com espaço reservado. Removidas quatro telas antigas sem referências que duplicavam os fluxos atuais.

## Banco e compatibilidade

`DBHelper` passou da versão 20 para 21 e assumiu `transaction_metadata` e `card_invoice_payments`. A migração aceita a tabela de metadados parcial criada por versões anteriores. Um gatilho remove metadados ao excluir transações.

Backup/restauração agora incluem essas tabelas e `net_worth_snapshots`. `affects_balance` registra se um histórico importado participa do saldo. IDs, nomes de tabelas e identificadores internos anteriores foram preservados. A restauração continua transacional.

As regras novas não tentam reconstruir automaticamente saldos históricos: versões anteriores não registravam com segurança se uma importação havia afetado o saldo. O saldo atual pode ser conferido e ajustado na edição da conta. Transferências antigas sem identificação de par não são vinculadas por adivinhação.

## Validação

Resultado final em 26/09/2026, código `3c69343`: dependências resolvidas, análise sem problemas, **29 testes aprovados**, APK debug e APK release gerados com sucesso. A versão final debug foi reinstalada e aberta no emulador, mantendo os dados existentes.

Artefatos locais:

- `build/app/outputs/flutter-apk/app-debug.apk` — SHA-256 `812a8a69bee0394b414ef0df07541bdae5a3e138c790e8e40013a245e909e15b`.
- `build/app/outputs/flutter-apk/app-release.apk` — SHA-256 `3b4158b1d01f51a14d846a53fd31dabe7358271f5ce7bd8ae498265080f3cbb4`.

O Gradle emitiu avisos de descontinuação futura das versões de Gradle/AGP/Kotlin; não houve erro de compilação. A tradução PT-BR não tem mensagens pendentes no gerador; outros idiomas herdados ainda têm traduções faltantes.

- `flutter pub get`, `flutter analyze`, `flutter test`.
- Testes SQLite reais: instalação nova, migração v20, backup/restauração, pendente/efetivação/edição/exclusão, transferência e desfazer, fatura parcial, limite de pagamento, parcelas, recorrência, orçamento, objetivos e saldo inicial do cartão.
- Testes de dinheiro, ciclo, meses curtos e OFX.
- Teste de ida e volta de Excel, verificando abas, metadados e células numéricas.
- Dez telas renderizadas em 360 × 800; abertura e salvamento de recorrente com `1.234,56`; formulário de orçamento com vírgula. Capturas locais em `build/review/`, não versionadas.
- APK debug instalado e aberto no emulador Android existente.
- Builds obrigatórios: `flutter build apk --debug` e `flutter build apk --release`.

## Limites de validação e decisões

- Sem parser PDF, sincronização, analytics ou serviços pagos novos. SQLite FFI é dependência apenas de teste.
- OFX cobre lançamentos bancários; não cobre investimentos OFX ou todos os dialetos particulares de instituições. A prévia permite revisar a interpretação.
- Créditos/estornos são representados por entradas na conta/cartão; não há vínculo automático com a compra original ou reclassificação retroativa da categoria original.
- Contas com vínculos não podem ser excluídas pela tela antes de realocar os dados; podem ser excluídas do saldo total. Isso evita apagar histórico e deixar transferências pela metade.
- A configuração existente assina release com a chave debug quando não há `android/key.properties`. Esta máquina não tem esse arquivo. Atualizar uma instalação assinada com outra chave exige a chave original; não se deve desinstalar para contornar isso, pois os dados locais seriam removidos.
- Validação visual cobre os fluxos principais; não constitui homologação em todos os aparelhos, tamanhos de fonte ou dialetos de extrato. Os saldos pessoais preexistentes não foram recalculados.

Referência conceitual de UX: [Minhas Finanças](https://minhasfinancas.app.br/). Nenhum código ou asset da referência foi incorporado.

## Rodada de produto 1.3.0+14 — 26/09/2026

Base preservada: `09295f2`, após `3c69343`. Branch exclusiva `feat/finance-app-base`. Benchmark antes de implementar, com 18 produtos e fontes oficiais em [NEXO_BENCHMARK_2026.md](NEXO_BENCHMARK_2026.md). Decisões em [NEXO_ROADMAP.md](NEXO_ROADMAP.md); propostas externas em [Open Finance](NEXO_OPEN_FINANCE_FUTURE.md) e [IA](NEXO_AI_FUTURE.md).

### Entrega e motivos

- Previsão local com saldo atual separado do saldo estimado; Hoje/7/15/30 dias/fim do mês. Soma pendências com efeito no saldo, receitas previstas, ocorrências futuras e faturas por ciclo, abatendo pagamentos registrados. Recorrência no cartão entra no caixa no vencimento da fatura. Inclui atrasados, informa cartões sem datas e não modifica saldos. `cash_forecast.dart` é compartilhado com Planejamento, substituindo o cálculo anterior que ignorava faturas e receitas pendentes.
- Agenda permite abrir o lançamento/fatura correspondente e pagar, receber ou pular a próxima ocorrência com confirmação. Datas de fechamento são informativas. Ocorrências posteriores exigem resolver a anterior. A confirmação continua atômica no provider, com proteção contra tela desatualizada.
- Regras locais de importação: descrição contém, tipo, categoria e subcategoria; criação/edição/exclusão; texto mais específico ganha prioridade; categoria removida não é aplicada. Regras afetam a prévia de novos arquivos, não o histórico.
- Revisão de possíveis duplicatas: mesma conta, tipo, valor e até três dias de diferença, mesmo com descrição diferente. O usuário escolhe ignorar a linha ou manter registros distintos. Não há união, quitação ou alteração automática de saldo. CSV não descarta silenciosamente duas linhas iguais; OFX mantém deduplicação por FITID dentro do arquivo. Linhas já importadas são desmarcadas para permitir retomar após falha.
- Busca por texto/subcategoria e filtros combinados de conta/cartão, categoria, período inclusivo, situação, valores, classe, origem e parcelas. Receitas/despesas excluem movimentos neutros, que têm filtro próprio. Opções quebram linha; formulário de filtros é rolável; cancelar preserva os filtros anteriores.
- CSV UTF-8 com BOM, vírgula como delimitador, decimal com ponto e campos entre aspas, com os metadados do Excel. Textos que poderiam virar fórmulas recebem proteção. Excel preserva descrições numéricas como `00123`. CSV/Excel são relatórios; restauração completa usa Backup.
- Modo privado na busca e widgets: saldos, valores e progresso não ficam expostos no payload do widget; atualizar privacidade/lançamentos atualiza widgets. Removido log de exceções com possível conteúdo dos widgets. Nada de analytics, API paga, credenciais ou envio financeiro adicionado.

### Migração e compatibilidade

Schema **21 → 22**, somente `import_rules`, criada oficialmente no DBHelper em instalação limpa e upgrade. Backup/restauração incluem a tabela. Migração não toca lançamentos nem saldos antigos. Testes preservam a compatibilidade da migração anterior v20. ApplicationId, nome do banco e configuração de assinatura permanecem iguais.

### Limites desta rodada

- Previsão depende dos dados cadastrados e dos pagamentos de fatura registrados; histórico importado sem pagamentos correspondentes pode exigir conferência de faturas. Não presume que dívida antiga foi quitada. Não estima compras futuras desconhecidas; câmbio usa as cotações disponíveis no app. Contas excluídas do total não compõem caixa; cartão sem vencimento gera aviso. Expansão defensiva limita recorrências muito antigas a 3.660 ocorrências por regra e avisa quando atingida.
- Não existe conciliação persistente com vínculo entre extrato e lançamento. Ignorar uma linha não liquida uma pendência. FITID não é armazenado globalmente. Templates CSV configuráveis, tags, multicategoria, Home reordenável, metas vinculadas e agenda de prazos de objetivos ficaram no roadmap.
- Capturas de widget tests usam fonte Arial e podem mostrar quadrados para ícones; isso é limitação da captura de teste, não asset incorporado ao app. Não equivalem a homologação em todos os aparelhos ou arquivos bancários.
- Mantidos os avisos de atualização futura de Gradle/AGP/Kotlin e a assinatura release existente, com fallback debug nesta máquina. Nenhuma chave foi trocada.

### Evidências finais

Código: `18d9d8d`; pesquisa: `ba290cb`. Resultados finais em 26/09/2026:

| Verificação | Resultado |
|---|---|
| `flutter pub get` | Sucesso; nenhuma dependência de produção adicionada |
| `flutter analyze` | Nenhum problema encontrado |
| `flutter test --concurrency=1 --dart-define=CAPTURE_REVIEW=true` | **56 testes aprovados** |
| `flutter build apk --debug` | Sucesso; 179.286.730 bytes |
| `flutter build apk --release` | Sucesso; 69.790.176 bytes |
| Instalação `adb install -r` | Sucesso no emulador; versão 1.3.0 / código 14; dados preservados |

São 27 testes adicionais sobre a base de 29: previsão, fatura parcial/estorno/fechamento, recorrente sem mutação e sem duplicação, regras, candidatos de conciliação, filtros, CSV e proteção contra fórmulas, migração v21/backup/restore, privacidade do payload de widgets e 15 cenários de interface. Novas telas e Planejamento foram renderizados em 360×800 e 412×915 com estados vazios, 40 registros, valores grandes, nomes longos, fonte 1,5×, claro/escuro. Capturas revisadas localmente; Home atualizada conferida também no emulador. Arquivos de captura não versionados.

O Windows ficou sem memória/recursos para threads em uma execução paralela e no primeiro build debug. Reexecutamos testes em sequência; ambos os APKs concluíram com `GRADLE_OPTS` temporário: heap 1536m, metaspace 512m, um worker, sem paralelismo/daemon persistente. A configuração permanente do projeto não foi alterada. Nenhuma falha de compilação ficou pendente.

SHA-256 dos artefatos locais em `build/app/outputs/flutter-apk/`:

- `app-debug.apk`: `4e29f11e4ab1ad29f6a6f3e895be32b10c1b25597d5974fe3485444fb738c7a7`.
- `app-release.apk`: `3982562097caef8debfe08a4dfa8efd613ed5a5e8b056cf75a1f0826202a63f5`.

`android/local.properties`, registrador gerado, logs, build e capturas ficaram fora dos commits. A main não foi alterada.

### Revisão de “pular ocorrência” — 1.3.0

- Assinaturas/recorrentes comuns: pular consome uma ocorrência e avança a próxima data, sem lançamento nem alteração de saldo. `paidPayments` conta pagamentos; `skippedPayments` conta pulos; o progresso e `remainingPayments` consideram ambas as ocorrências concluídas. O detalhe mostra os dois contadores separadamente.
- Parcelamentos: “Pular” foi removido da lista, detalhe e agenda. O provider também rejeita a operação, inclusive quando chamado diretamente, antes de qualquer gravação. Progresso e parcelas restantes consideram somente pagamentos.
- Compatibilidade sem migração: schema permanece **22**. A coluna legada `paid_payments` continua armazenando ocorrências consumidas. O modelo desconta as entradas `skipped` de `recurring_history` ao ler; edição e backup/restauração preservam essa codificação. Não houve recálculo automático de saldos nem reescrita de dados antigos.
- Parcelas puladas anteriormente permanecem devidas e entram na previsão/agenda. A ação de pagamento regulariza primeiro a parcela pulada mais antiga, usando sua data, valor e ID históricos; muda sua ação no histórico para `paid`, gera somente um lançamento e não avança novamente `nextDate` nem o contador persistido. `installmentCurrent` usa a posição no cronograma, não o número de pagamentos realizados. Toques repetidos com estado antigo não quitam a próxima parcela.
- O histórico antigo não registra a conta de cada ocorrência: a regularização usa a conta atualmente cadastrada no recorrente, visível no detalhe. Não é possível inferir pulos cujo histórico tenha sido removido externamente. A versão anterior permanece documentada acima; os hashes daquele APK não identificam este novo build.

Testes adicionados cobrem pagamento e pulo de recorrente comum, pagamento e rejeição de pulo em parcelamento, progresso/restante, fim do cronograma, concorrência, recuperação de pulos legados, numeração das parcelas, backup/restauração, previsão e a presença/ausência da ação nas três telas.

Validação desta correção: `flutter analyze` sem problemas; `flutter test --concurrency=1 --dart-define=CAPTURE_REVIEW=true` com **66 testes aprovados**; `flutter build apk --release` concluído (69.888.480 bytes). Permanecem somente os avisos preexistentes de atualização futura de Gradle/AGP/Kotlin. SHA-256 do novo `app-release.apk`: `c79ee6f0b522bcfd7dbf06cf66fec0b2ff35596953280e87ed167c9b6dd70b4f`.
