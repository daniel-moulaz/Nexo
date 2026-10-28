# Desvinculação do Expensy (28/10/2026)

O Nexo nasceu como fork do [Expensy](https://github.com/mina-android/Expensy),
de Mina Android. O ponto de bifurcação é o commit `bca2ba3` (v1.1.0, 10/08/2026),
quando o Expensy estava sob licença **MIT**; o Expensy passou a GPLv3 em 02/10/2026
(v1.2.0), e **nenhum commit do Expensy foi incorporado depois do fork** (212 commits
próprios desde então, zero merges do upstream). O código herdado continua MIT, e a
licença exige manter o aviso de copyright original: ele está em `LICENSE`, abaixo
do aviso do Nexo, e no README ("Desenvolvimento e origem").

## O que ligava os dois projetos

Levantamento com `grep -ri expensy` no repositório (148 arquivos, 590 linhas):

| Vínculo | Onde | Decisão |
|---|---|---|
| Nome do pacote Dart `expensy` e 405 imports `package:expensy/` | `pubspec.yaml`, `lib/`, `test/`, `tool/` | **Renomeado** para `nexo` |
| Classes `ExpensyApp`, `ExpensyAppState`, `ExpensyRoute`, `ExpensySlideUpRoute` | `lib/main.dart`, `lib/theme/app_theme.dart` e 26 usos | **Renomeadas** para `Nexo*` |
| Arquivo do banco `expensy.db` | `lib/database/database_platform.dart` | **Renomeado** para `nexo.db`, com migração na primeira abertura |
| Canais nativos `com.ma.expensy/quick_add`, `…/quick_add_stream`, `…/automation` | Dart e `MainActivity.kt` | **Renomeados** para `nexo/quick_add`, `nexo/quick_add_stream`, `nexo/privacy` |
| Projeto CMake `expensy` | `windows/CMakeLists.txt` | **Renomeado** para `nexo` (o executável já era `Nexo.exe`) |
| Sonda nativa do listener de notificações (`NotificationProbe.kt`, `tool/native_probe.init.gradle`) | `android/app/src/androidTest`, `tool/` | **Apagados** (o listener saiu na 1.12.9); `docs/NEXO_NATIVE_PROBE.md` marcado como obsoleto |
| Remotos git `origin` → daniel-moulaz/Expensy e `upstream` → mina-android/Expensy | `.git/config` | **Removidos**; `origin` passou a ser daniel-moulaz/Nexo e `main` local acompanha `origin/main` |
| Texto "Expensy" em `HOMESCREEN_WIDGET.md`, comentário em `widget_background.xml`, parágrafo do README | docs e recursos | **Reescritos** |
| `applicationId`/`namespace` `com.ma.expensy` e pacote Kotlin `com.ma.expensy` | `android/app/build.gradle`, `android/app/src/main/kotlin/com/ma/expensy/` | **Mantidos por decisão do dono** (28/10): trocar faria o Android tratar o Nexo como outro app, sem os dados locais |
| Ids de canal de notificação `expensy_budget`, `expensy_daily_reminder`, `expensy_lended`, `expensy_loans` | serviços de lembrete | **Mantidos**: são chaves internas do registro de canais do Android no app instalado; trocar exigiria cancelar e reagendar todos os lembretes pendentes para um ganho invisível |
| Menções históricas em `CHANGELOG.md` e em `docs/` (incluindo `docs/legacy/EXPENSY_AUDIT.md`) | histórico | **Mantidas**: registro do que foi feito e quando |
| Pasta local `C:\Users\danie\projetos\Expensy` | ambiente do dono | **A cargo do dono**: renomear com as sessões fechadas |
| Fork `daniel-moulaz/Expensy` no GitHub | conta do dono | **Intocado**; pode ser arquivado ou apagado pelo dono |

## A migração do banco

`DatabasePlatform.path` passa a resolver `nexo.db`. Se ele não existe e `expensy.db`
existe, o app abre o arquivo antigo, executa `PRAGMA wal_checkpoint(TRUNCATE)` (o
write-ahead log é dobrado no arquivo principal), fecha e renomeia o arquivo principal;
só então move os sidecars `-journal`, `-wal` e `-shm`, que depois do checkpoint não
carregam dados. Se o arquivo principal não puder ser renomeado, nada se move e o nome
antigo continua valendo; nunca se cria um banco vazio ao lado do cheio. Se os dois
existirem, `nexo.db` vence e `expensy.db` fica intocado. Coberto por
`test/database_rename_test.dart` (instalação nova, renomeação com linhas e sidecars,
os dois arquivos presentes).

Cópias antigas em `%LOCALAPPDATA%\Nexo\backups\` continuam com o nome que tinham; são
arquivos de segurança, não são abertos pelo app.

## Dependências residuais

1. `com.ma.expensy` como identidade Android e pacote Kotlin, por decisão do dono.
2. Ids internos dos canais de notificação (`expensy_*`), no estado do app instalado.
3. O aviso MIT de Mina Android em `LICENSE` e a frase de origem no README, exigidos
   pela licença do código herdado.
4. Histórico git e documentos antigos, que contam a origem.

Fora isso, o Nexo compila, testa e roda sem nada que aponte para o Expensy: não há
infraestrutura compartilhada (o projeto Supabase, as Edge Functions e as migrations
têm nomes `nexo_*`), não há assets, fontes ou ícones herdados em uso (a marca é a
do N dourado, `docs/brand/`), e nenhum script de build cita o nome antigo.
