# Snapshot da pasta no handoff — 20/10/2026

Este inventário registra somente caminhos e estatísticas, sem dados financeiros ou credenciais. Reexecute git status antes de trabalhar: o usuário pode continuar editando a pasta.

Branch: `codex/nexo-investments`. HEAD anterior ao commit do handoff: `c3a34b730ac03a091dcebfbc5011f7575ef9e5d5`.

O staging estava vazio. Os três arquivos novos deste handoff foram excluídos da listagem abaixo. As demais mudanças são preexistentes e devem ser entendidas e preservadas.

## Status recebido

```text
 M android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
 M android/app/src/main/kotlin/com/ma/expensy/FinancialNotificationListener.kt
 M android/app/src/main/kotlin/com/ma/expensy/FinancialNotificationParser.kt
 M android/app/src/main/kotlin/com/ma/expensy/MainActivity.kt
 M android/app/src/test/kotlin/com/ma/expensy/FinancialNotificationParserTest.kt
 M docs/NEXO_DESKTOP.md
 M docs/NEXO_EVOLUTION_2026.md
 M docs/NEXO_SYNC_ARCHITECTURE.md
 M lib/models/models.dart
 M lib/providers/app_provider.dart
 M lib/screens/add_transaction_screen.dart
 M lib/screens/assets_screen.dart
 M lib/screens/automation_settings_screen.dart
 M lib/screens/card_invoice_screen.dart
 M lib/screens/categories_screen.dart
 M lib/screens/incomes_screen.dart
 M lib/screens/insights_screen.dart
 M lib/screens/lended_person_screen.dart
 M lib/screens/lended_screen.dart
 M lib/screens/loan_detail_screen.dart
 M lib/screens/net_worth_screen.dart
 M lib/screens/notification_inbox_screen.dart
 M lib/screens/onboarding_screen.dart
 M lib/screens/savings_goal_detail_screen.dart
 M lib/screens/transfer_screen.dart
 M lib/screens/wishlist_screen.dart
 M lib/screens/yearly_analysis_screen.dart
 M lib/services/finance_bootstrap_service.dart
 M lib/services/finance_export_service.dart
 M lib/services/finance_rules.dart
 M lib/services/notification_inbox.dart
 M lib/services/transaction_metadata_service.dart
 M lib/widgets/analysis_widgets.dart
 M lib/widgets/savings_goal_sheet.dart
 M lib/widgets/shared_widgets.dart
 M test/analysis_screens_test.dart
 M test/ledger_test.dart
 M test/notification_retention_test.dart
 M test/product_screens_test.dart
 M test/widget_test.dart
 M test/windows_platform_test.dart
?? .vscode/
?? android/app/src/androidTest/
?? docs/NEXO_CARD_SUGGESTIONS_2026_10.md
?? docs/NEXO_NATIVE_PROBE.md
?? docs/NEXO_WINDOWS_VALIDATION.md
?? lib/models/transaction_metadata.dart
?? lib/sync/supabase_sync_transport.dart
?? supabase/
?? test/card_invoice_screen_test.dart
?? test/windows_import_test.dart
?? tool/android_notification_check.dart
?? tool/financial_core_check.dart
?? tool/native_probe.init.gradle
?? tool/validate_sync_sql.mjs
?? tool/windows_native_check.dart
```

## Estatísticas do diff rastreado

Arquivos não rastreados não entram neste resumo; modificações por final de linha podem aparecer no status sem diff de conteúdo equivalente.

```text
 .../flutter/plugins/GeneratedPluginRegistrant.java |  10 +
 .../ma/expensy/FinancialNotificationListener.kt    |  40 +-
 .../com/ma/expensy/FinancialNotificationParser.kt  |   4 +-
 .../src/main/kotlin/com/ma/expensy/MainActivity.kt |  16 +-
 .../ma/expensy/FinancialNotificationParserTest.kt  |  11 +
 docs/NEXO_DESKTOP.md                               |  82 ++-
 docs/NEXO_EVOLUTION_2026.md                        |   5 +
 docs/NEXO_SYNC_ARCHITECTURE.md                     |   5 +
 lib/providers/app_provider.dart                    |  17 +-
 lib/screens/add_transaction_screen.dart            | 803 +++++++++++----------
 lib/screens/automation_settings_screen.dart        |  21 +
 lib/screens/card_invoice_screen.dart               |  80 +-
 lib/screens/notification_inbox_screen.dart         |  46 +-
 lib/services/finance_export_service.dart           |   2 +-
 lib/services/finance_rules.dart                    |   2 +-
 lib/services/notification_inbox.dart               |  46 +-
 lib/services/transaction_metadata_service.dart     |  72 +-
 lib/widgets/analysis_widgets.dart                  |   8 +-
 test/analysis_screens_test.dart                    | 112 ++-
 test/ledger_test.dart                              |   6 +-
 test/notification_retention_test.dart              |  60 +-
 test/product_screens_test.dart                     |  52 +-
 test/windows_platform_test.dart                    |  87 +++
 23 files changed, 1034 insertions(+), 553 deletions(-)
```

## Classificação inicial para revisão

- Android/automação: listener, parser, MainActivity, registrador de plugins, testes Kotlin, androidTest, inbox e diagnóstico. Ler docs/NEXO_CARD_SUGGESTIONS_2026_10.md e docs/NEXO_NATIVE_PROBE.md.
- Modelo de metadados: extração para lib/models/transaction_metadata.dart com reexportação pelo serviço; revisar os consumidores junto. Não publicar só parte da dependência.
- Formulários/cartões/backup: AppProvider, AddTransactionScreen, fatura, import/export e respectivos testes. Os commits do lote 1.6.5 já foram feitos seletivamente; o que resta não deve ser descartado como se fosse sobra sem valor.
- Windows: documentação de homologação, novos testes e ferramentas de ensaio; a documentação distingue o que foi automatizado do que falta manualmente.
- Sync: transporte Supabase, SQL de laboratório e validação PostgreSQL/WASM. Ainda não integrados nem prontos para dados reais.
- .vscode/: apareceu no corte e não foi inspecionado; preservar e verificar intenção do usuário antes de versionar.

## Antes de qualquer commit de recuperação

1. Comparar diff e arquivos novos; conferir se há alteração semântica ou somente formato/finais de linha.
2. Agrupar por funcionalidade e dependências, sem misturar dados privados, credenciais ou artefatos de build.
3. Testar o estado integrado. Se publicar um subconjunto, verificar também que esse subconjunto funciona sem depender de arquivos deixados fora.
4. Revisar git diff --cached e nomes de arquivos. Nunca git add . ou limpeza geral para resolver as pendências.

Não foi feito reset, limpeza, stash, migração, alteração de código financeiro ou novo build para produzir este handoff.
