# Opções de marca

Propostas para substituir o N dourado, ainda sem escolha. Nada aqui entra no app: `assets/brand/` e os ícones do Android e do Windows continuam com a logo atual.

Abra `comparacao.html` para ver tudo lado a lado. Cada pasta traz uma opção:

| Arquivo | O que é |
| --- | --- |
| `simbolo-escuro.svg`, `simbolo-claro.svg` | Só o símbolo, sem fundo |
| `nome-escuro.svg`, `nome-claro.svg` | Símbolo e nome, com as letras em curvas (Inter) |
| `icone.svg`, `icone-*.png` | Ícone com fundo, em 16, 32, 48, 192 e 512 px |
| `android-frente.svg`, `android-mono.svg` | Camadas adaptativas de 108, com a marca dentro do círculo seguro de 66 |
| `app_icon.ico` | Ícone do Windows, de 16 a 256 px |

`gerar.py` refaz os arquivos e mede contraste e zona segura; `pagina.py` refaz a comparação.

## Decisões

- Direções variadas: monograma (Engate, Constelação, Fluxo, Blocos, Ponte), abstrato (Interseção, Núcleo) e geométrico (Encontro).
- Já existe uma fintech de cripto chamada Nexo, com identidade azul. As opções evitam N facetado em azul.
- Também evitam roxo (Nubank), laranja chapado (Inter), N em caixa (apps de notas), N de fita dobrada (serviços de vídeo), cifrão, moeda e barras.
- Sem busca de marcas registradas: a originalidade é uma avaliação visual.
- Preferida: Engate. Em 16 px, Ponte e Fluxo ficam mais nítidas.

## Aplicar a escolhida

1. Substituir `docs/brand/nexo-mark.svg` e atualizar `docs/brand/README.md`.
2. Gerar `assets/brand/icon.png`, `foreground.png`, `monochrome.png` e `splash.png`.
3. Trocar `adaptive_icon_background` em `pubspec.yaml` e `ic_launcher_background` em `values*/colors.xml`.
4. Refazer `drawable-*/splash_mark.png` e `ic_notification.png`.
5. Rodar `dart run flutter_launcher_icons`, que refaz as camadas do Android e `windows/runner/resources/app_icon.ico`.
6. Atualizar as imagens do README com `flutter test tool/readme_screens.dart`.
