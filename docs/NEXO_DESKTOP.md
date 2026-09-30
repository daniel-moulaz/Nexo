# Nexo no PC — preparação responsiva

30/09/2026. Implementada a camada de apresentação compartilhada; **não é uma distribuição Windows pronta**.

- Menos de 900 px: navegação inferior existente.
- A partir de 900 px: barra lateral com Resumo, Transações, Contas/cartões, Recorrentes, Orçamentos/objetivos, Análises, Agenda, Importar, Configurações e Mais.
- Painéis Home/Análises passam a duas colunas a partir de 1000 px úteis, com largura máxima de 1440 px.
- Detalhe dos gráficos usa tabela a partir de 900 px; abaixo disso usa lista. Mesmos objetos e regras contábeis.
- Seções são inicializadas quando abertas e preservadas durante troca de abas; filtros não somem a cada navegação.
- Respeita escala de texto e preferência de navegação acessível do sistema. Gráficos têm equivalentes textuais e valores ocultos no modo privado.

## Ambiente e limite de entrega

`flutter doctor -v`: Flutter 3.47.5, Dart 3.13.4, Windows 11. **Visual Studio com Desktop development with C++ ausente**. Nenhum alvo `windows/` foi gerado, nenhuma dependência de runtime desktop foi adicionada e nenhum EXE foi produzido. Um runner sem validar SQLite, notificações e segurança daria uma impressão enganosa de suporte. Não instalar ferramentas de vários GB como efeito colateral desta rodada.

Próximo lote nativo: instalar toolchain C++/Windows SDK, gerar runner apenas Windows em branch isolada, promover/configurar `sqflite_common_ffi` em produção com armazenamento no diretório de suporte do usuário e nome `expensy.db`; testar instalação, backup, restore e migrações em caminho temporário. Não abrir diretamente o banco Android por compartilhamento de arquivos. O plugin sqflite Android permanece intacto.

Revisar explicitamente todos os adaptadores Android antes do primeiro start Windows: inicialização/cancelamento de `flutter_local_notifications`, home widgets, MethodChannel/EventChannel de atalhos, descoberta de apps e acesso a notificações. Automação por notificações bancárias permanece recurso Android; a caixa sincronizada depende do futuro desenho de privacidade, não de um listener Windows fictício. Validar armazenamento seguro, Windows Hello/PIN local e proteção de tela sem presumir equivalência de APIs Android. Os serviços antigos ainda têm inicialização Android; a UI responsiva não resolve isso sozinha.

Build de aceitação futuro: `flutter build windows` e execução do bundle Release completo, não só o EXE. Exercitar abrir/fechar, redimensionar, teclado, arquivos, valores com vírgula, moeda, edição, erros de disco, reinício offline e backup/restore. A assinatura Android não é alterada nem reutilizada como identidade de distribuição Windows.

## Pesquisa de experiência

[Minhas Finanças desktop](https://minhasfinancas.app.br/desktop) apresenta mais espaço de análise/importação; [Monarch Reports](https://help.monarch.com/hc/en-us/articles/21846787088916-Reports) documenta filtros e aprofundamento. Adaptação Nexo: navegação lateral, painéis lado a lado e tabela para o conjunto exato de lançamentos do gráfico. Sem cópia de assets, código ou composição pixel-perfect. Busca desktop geral ainda usa a tela compartilhada; atalhos de teclado e edição em lote ficam para o lote nativo, após teste de conflitos e desfazer.

As renderizações sintéticas 360×800, 412×915, 1280×720 e 1920×1080 são verificadas em `test/analysis_screens_test.dart`. Teste de layout não substitui homologação do binário Windows. Resultados reais desta rodada constam em `NEXO_EVOLUTION_2026.md`.
