# Marca do Nexo

`nexo-mark.svg` é a fonte: um N dourado (#F2C14E) de traço único sobre fundo
quase preto (#0B1118), cantos de 112/512. Escolhida em 27/10/2026 entre três
propostas.

Os PNGs em `assets/brand/` (ícone completo, primeiro plano adaptativo com a
marca ocupando ~46% da tela, dentro da zona segura de 66%, monocromático para
ícones temáticos do Android 13+, e a marca sozinha para o splash) foram
rasterizados a partir desse SVG. Os ícones do Android e o `.ico` do Windows
são gerados por `dart run flutter_launcher_icons` (configuração no
`pubspec.yaml`, com `adaptive_icon_foreground_inset: 0` porque o primeiro
plano já traz a margem). `ic_launcher_round.xml` é cópia de `ic_launcher.xml`;
as camadas antigas em `mipmap-*` e `drawable/` foram removidas.
