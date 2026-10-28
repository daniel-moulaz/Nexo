# Nexo como projeto independente (28/10/2026)

O Nexo começou em cima de uma base de código de terceiros, licenciada sob **MIT**.
O ponto de partida é o commit raiz do repositório (agosto de 2026); desde então são
só commits próprios, nenhum código novo da base foi incorporado, e a base passou a
outra licença depois disso sem efeito sobre o Nexo. A licença MIT exige manter o aviso
de copyright da base enquanto houver código derivado: esse aviso está em `LICENSE`,
abaixo do aviso do Nexo, e em nenhum outro lugar.

## O que foi feito na 1.12.10

| Vínculo | Onde | Decisão |
|---|---|---|
| Nome do pacote Dart e 405 imports | `pubspec.yaml`, `lib/`, `test/`, `tool/` | **Renomeado** para `nexo` |
| Classes com o nome antigo (`*App`, `*AppState`, `*Route`, `*SlideUpRoute`) | `lib/main.dart`, `lib/theme/app_theme.dart` e 26 usos | **Renomeadas** para `NexoApp`, `NexoAppState`, `NexoRoute`, `NexoSlideUpRoute` |
| Arquivo do banco local | `lib/database/database_platform.dart` | **Renomeado** para `nexo.db`, com migração na primeira abertura |
| Canais nativos do Android | Dart e `MainActivity.kt` | **Renomeados** para `nexo/quick_add`, `nexo/quick_add_stream`, `nexo/privacy` |
| Projeto CMake do Windows | `windows/CMakeLists.txt` | **Renomeado** para `nexo` (o executável já era `Nexo.exe`) |
| Sonda nativa do listener de notificações | `android/app/src/androidTest`, `tool/` | **Apagados** (o listener saiu na 1.12.9) |
| Remotos git da base e do fork anterior | `.git/config` | **Removidos**; `origin` é `daniel-moulaz/Nexo` |
| Textos e comentários com o nome antigo | README, docs, recursos Android | **Reescritos**; a pasta `docs/legacy` foi apagada |
| `applicationId`/`namespace` `com.ma.expensy` e pacote Kotlin | `android/app/build.gradle`, `android/app/src/main/kotlin/com/ma/expensy/` | **Mantidos por decisão do dono** (28/10): trocar faria o Android tratar o Nexo como outro app, sem os dados locais |
| Ids internos dos canais de notificação (`*_budget`, `*_daily_reminder`, `*_lended`, `*_loans`) | serviços de lembrete | **Mantidos**: chaves do registro de canais do Android no app instalado; trocar exigiria cancelar e reagendar todos os lembretes para um ganho invisível |

## Histórico do git (28/10/2026)

O histórico publicado foi reescrito para começar no Nexo: um commit raiz com a base
sob MIT e, em seguida, só os commits do dono, com as mensagens que citavam o nome antigo
corrigidas. O histórico completo anterior ficou guardado só no PC do dono, na branch
local `backup/historico-completo-2026-10-28` e no arquivo
`C:\Users\danie\projetos\nexo-historico-completo-2026-10-28.bundle`. Versões antigas
dos arquivos dentro dos commits do dono ainda trazem o nome antigo (por exemplo o
`pubspec.yaml` até a 1.12.10); isso só mudaria com um histórico de um commit só.

## A migração do banco

`DatabasePlatform.path` resolve `nexo.db`. Se ele não existe e o arquivo com o nome
antigo existe, o app abre o antigo, executa `PRAGMA wal_checkpoint(TRUNCATE)` (o
write-ahead log é dobrado no arquivo principal), fecha e renomeia o arquivo principal;
só então move os sidecars `-journal`, `-wal` e `-shm`, que depois do checkpoint não
carregam dados. Se o arquivo principal não puder ser renomeado, nada se move e o nome
antigo continua valendo; nunca se cria um banco vazio ao lado do cheio. Se os dois
existirem, `nexo.db` vence e o antigo fica intocado. Coberto por
`test/database_rename_test.dart`. O nome antigo permanece no código só como a constante
`legacyFileName`, que a migração precisa.

Cópias antigas em `%LOCALAPPDATA%\Nexo\backups\` continuam com o nome que tinham; são
arquivos de segurança, não são abertos pelo app.

## O que resta e por quê

1. `com.ma.expensy` como identidade Android e pacote Kotlin, por decisão do dono.
2. Ids internos dos canais de notificação, no estado do app instalado.
3. A constante `legacyFileName` da migração do banco e seu teste.
4. O aviso MIT da base em `LICENSE`, exigido pela licença.

Fora isso, nada no código, nas docs ou nos commits publicados aponta para a base: não
há infraestrutura compartilhada (o projeto Supabase, as Edge Functions e as migrations
têm nomes `nexo_*`), não há assets, fontes ou ícones herdados em uso (a marca é a do N
dourado, `docs/brand/`), e nenhum script de build cita o nome antigo.
