# Tipografia do Nexo

Regras do texto no app. `test/typography_test.dart` faz o build falhar quando elas são quebradas e `test/real_font_layout_test.dart` mede as telas com a fonte real.

## Regras

| Regra | Valor | Por quê |
| --- | --- | --- |
| Fonte no Windows | Inter 4.1, em `assets/fonts/Inter` (arquivos sem alteração, SIL OFL) | Funciona offline, tem peso médio de verdade e não depende da versão do Windows |
| Fonte no Android | A do sistema, salvo escolha em Configurações | Inter escolhida ali vem do app, sem rede; as outras opções ainda são baixadas |
| Tamanho mínimo | 12 | Mínimo do Windows para texto regular |
| Pesos | 400 ler, 500 rótulos, 600 títulos e valores, 700 só em valores de 24 ou mais | Só esses quatro arquivos existem no app |
| Acima de 700 | Proibido | Com a Inter o motor borra um negrito falso por cima do Bold |
| Espaçamento entre letras | 0, sempre pelo tema | Os valores do Material foram calibrados para a Roboto |
| Algarismos tabulares | Só em valores em coluna, com `NexoTones.figures`; nunca no tema | Na Inter o `tnum` também alarga o hífen em 41% e muda, ao todo, 50 sinais: em texto, "Sexta-feira" vira "Sexta - feira" e "Bem-vindo" vira "Bem - vindo" |
| Caixa alta | Não usar | O Windows pede caixa de sentença em toda a interface |

## Rampa

Segue a [rampa de tipos do Windows](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography) com os nomes do Material:

| Estilo | Tamanho/linha | Peso |
| --- | --- | --- |
| `bodySmall` | 12/16 | 400 |
| `labelSmall`, `labelMedium` | 12/16 | 500 |
| `bodyMedium` | 14/20 | 400 |
| `labelLarge` | 14/20 | 500 |
| `titleSmall` | 14/20 | 600 |
| `bodyLarge` | 16/24 | 400 |
| `titleMedium` | 16/24 | 600 |
| `titleLarge` | 20/28 | 600 |
| `headlineSmall` | 24/32 | 600 |
| `headlineMedium` | 28/36 | 600 |
| `headlineLarge` | 32/40 | 700 |

## O que causava o texto esquisito no Windows

Medido em capturas do motor nativo, em 06/11/2026:

- `w800` e `w900` caíam na Segoe UI Black, família bem mais larga e pesada. Eram 157 usos, inclusive em texto de 12 px.
- O Windows não tem peso 500 na Segoe UI: ele já sai como semibold, então "médio" e "semibold" eram iguais.
- O espaçamento de 0,15 a 0,5 do Material alargava o texto normal ao lado da Black apertada. Só havia um `letterSpacing` negativo no app.
- Havia 51 tamanhos literais abaixo de 12, até 9 px.
- A escala do Windows **não** era problema: o manifesto declara PerMonitorV2 e o app desenha certo em 96, 120 e 144 DPI.

A maior parte do ganho veio dos pesos e tamanhos; a troca para a Inter acrescentou o peso médio real e a independência do sistema.

## Conferir no motor real

`flutter test` não usa o renderizador de texto do Windows. Para julgar tipografia:

```
flutter build windows --release --target tool/windows_shots.dart
build\windows\x64\runner\Release\Nexo.exe --test-profile=shots --tab=0
```

`--tab=11` abre o Investir e `--specimen --fonts=<pasta>` compara fontes lado a lado. Os dados são fictícios (`tool/demo_data.dart`) e não há rede nem servidor. Esse build substitui a pasta `Release`: refaça com `lib/main.dart` antes de empacotar.

Para as escalas reais, `tool/windows_capture.ps1` muda a escala do segundo monitor por alguns segundos, captura a janela e devolve a escala original. Ele recusa a imagem se a janela abrir em outro monitor.
