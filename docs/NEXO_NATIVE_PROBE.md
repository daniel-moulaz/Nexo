> **Obsoleto desde a 1.12.9.** O listener de notificações saiu do app (ver
> `docs/REVISAO_SOBREPOSICOES_2026_10.md`), e com ele o `NotificationProbe.kt`
> e o `tool/native_probe.init.gradle` descritos abaixo. O texto fica como
> registro do método.

# Validação nativa isolada de notificações

Este ensaio usa o listener, parser e fila criptografada reais em um Android descartável. Não abre a interface Flutter nem valida a confirmação SQLite/Dart. O APK gerado sem assets Flutter é exclusivo de teste, não uma atualização distribuível.

O script de inicialização Gradle aplica o sufixo `.nativeqa` apenas nesta execução. A identificação e assinatura de produção permanecem intactas. O teste recusa execução se o aplicativo alvo não for `com.ma.expensy.nativeqa`; ele limpa exclusivamente as preferências desse aplicativo de ensaio.

## Compilar

Usar Java 17 e, na pasta `android`, executar:

```text
gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest -x :app:compileFlutterBuildDebug --max-workers=2 -I ../tool/native_probe.init.gradle
```

Os APKs ficam em `build/app/outputs/apk/debug/app-debug.apk` e `build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk`. Instalar ambos somente em um emulador descartável. Sempre conferir que `output-metadata.json` informa `com.ma.expensy.nativeqa` e `com.ma.expensy.nativeqa.test`.

## Executar

Substituir SERIAL pelo emulador correto. A primeira fase autoriza o listener apenas nesse dispositivo de ensaio e publica mensagens sintéticas pelo Android Shell.

```text
adb -s SERIAL shell am instrument -w com.ma.expensy.nativeqa.test/com.ma.expensy.NotificationProbe
adb -s SERIAL shell am force-stop com.ma.expensy.nativeqa
adb -s SERIAL shell am instrument -w -e phase resume com.ma.expensy.nativeqa.test/com.ma.expensy.NotificationProbe
adb -s SERIAL shell am instrument -w -e phase queue com.ma.expensy.nativeqa.test/com.ma.expensy.NotificationProbe
```

Resultados esperados: `PASS (10)`, `PASS (4)` e `PASS (6)`. Usar a ordem acima; a segunda fase depende da fila persistida pela primeira. Começar cada sequência em um emulador novo, sem notificações de uma sequência anterior.

Cobertura: conexão, captura pelo sistema, parsing, criptografia, replay, ack, recusa, seleção de origem, recuperação de notificações ativas, reinício do processo, limpeza de itens vencidos na entrada, limite de 250 itens, ack parcial e preservação da fila diante de falha de decriptação.

## Núcleo financeiro

Na raiz do projeto:

```text
dart tool/financial_core_check.dart
```

São 15 verificações do código real de cálculos e serialização, independentes de Flutter e de banco de dados. Não substituem a suíte `flutter test`.
