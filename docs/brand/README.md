# Marca do Nexo

`nexo-mark.svg` é a fonte: o **Engate**, dois ganchos que se prendem e formam o N, em
#5EEAD4 e #F8FAFC sobre #0E1420. Escolhido em 06/11/2026 entre oito propostas, que
continuam em `opcoes/` com a página de comparação. No fundo claro as cores são #0F766E e
#0F172A.

Os PNGs em `assets/brand/` (ícone completo, primeiro plano adaptativo dentro da zona segura de 66
em 108, monocromático para ícones temáticos do Android 13+ e abertura) saem de `opcoes/gerar.py`.
A abertura usa o ícone com fundo, porque um dos traços é branco e a janela pode ser clara.
`ic_notification.png` é a marca em branco: o Android só usa o desenho.

As camadas do Android vêm de `dart run flutter_launcher_icons` (configuração no `pubspec.yaml`, com
`adaptive_icon_foreground_inset: 0` porque o primeiro plano já traz a margem). O `app_icon.ico` do
Windows é o de `opcoes/engate/`, com sete tamanhos: depois de rodar a ferramenta, copie-o de volta
para `windows/runner/resources/`, porque ela grava um só.
