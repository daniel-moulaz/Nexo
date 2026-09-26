# Nexo 1.2.0 — revisão financeira

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
