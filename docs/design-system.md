# Sistema de design do Nexo

Uma identidade, igual no celular e no Windows. Tudo sai de `lib/theme/nexo_tokens.dart` e de `lib/widgets/nexo_brand.dart`: trocar a marca é trocar esses dois arquivos e o SVG, sem refazer telas. `test/design_tokens_test.dart` faz o build falhar se as regras abaixo forem quebradas.

## A ideia

A logo é o Engate: dois ganchos que se prendem sobre tinta azul-escura. O app leva isso para dentro de três formas:

- **Painel de tinta (`NexoInkPanel`):** escuro nos dois temas, com o Engate em marca-d'água. É a assinatura visual. Uma por tela, para o número que importa ali.
- **Traço arredondado:** barras de progresso e botões usam a mesma ponta redonda da logo.
- **Camadas, não contornos:** a profundidade vem do degrau entre superfícies. No tema claro, um fio fino ainda separa branco de papel.

## Cor

### Marca

| Token | Valor | Uso |
| --- | --- | --- |
| `NexoBrand.ink` | `#0E1420` | Fundo do tema escuro e do painel |
| `NexoBrand.inkRaised`, `inkHigh` | `#16202F`, `#1F2B3D` | Degraus sobre a tinta |
| `NexoBrand.teal` | `#5EEAD4` | Cor primária no escuro |
| `NexoBrand.tealDeep` | `#0F766E` | Cor primária no claro |
| `NexoBrand.paper` | `#F8FAFC` | Segundo gancho da marca |

A cor da marca marca **o que está ativo ou é a ação principal**. Ela nunca diz nada sobre dinheiro.

### Semântica

| Token | Escuro | Claro | Significa |
| --- | --- | --- | --- |
| `NexoTones.income` | `#B4E86B` | `#3F6212` | Ganho, entrada |
| `NexoTones.expense` | `#FB8FA0` | `#BE123C` | Gasto, saída, estouro |
| `NexoTones.warning` | `#FBBF24` | `#92400E` | Perto do limite, pendente |
| `NexoTones.info` | `#7DD3FC` | `#0369A1` | Informação |

O ganho é um verde-lima de propósito: o verde esmeralda de antes ficava a poucos graus do teal da marca. Um teste exige mais de 60 graus de distância entre os dois. Valores nunca dependem só da cor: sempre há sinal ou palavra junto.

Dentro do painel de tinta, use os tons `*OnInk`, que valem nos dois temas.

### Categorias e gráficos

- Categorias guardam a própria cor. `NexoTones.category` ajusta a luminosidade para cada tema, porque muitas eram escuras e sumiam no fundo escuro.
- Séries sem cor própria usam `NexoChart.series`, separadas para daltonismo e longe de ganho e gasto.

## Tipografia

Inter, incluída no app, nos dois aparelhos. As regras estão em `docs/TIPOGRAFIA.md`: mínimo 12, pesos até 700, nada de `letterSpacing` fora do tema, e `NexoTones.figures` só em valores em coluna.

## Espaço, forma e movimento

- **Espaçamento (`NexoSpace`):** 4, 8, 12, 16, 24, 32.
- **Raios (`NexoRadius`):** chip 12, campo 14, cartão 20, painel 24, folha 28.
- **Movimento (`NexoMotion`):** 140 ms ou 240 ms, com `easeOutCubic`. `NexoMotion.of(context)` zera a duração quando o sistema pede menos movimento.

## Componentes

| Componente | Quando usar |
| --- | --- |
| `NexoMark` | Cabeçalho do Hoje, barra lateral e telas vazias |
| `NexoInkPanel`, `NexoInkStat` | O número principal da tela |
| `NexoCard` | Todo o resto. Sem sombra, sem contorno no escuro |
| `NexoProgress` | Barras: teal dentro da meta, âmbar a partir de 80%, vermelho no limite |
| `CategoryDot` | Ícone e cor da categoria, com ícone escolhido pelo nome em português |
| `EmptyState` | Tela vazia, com ícone e marca |

Dentro do painel, os filhos recebem o tema escuro sozinhos. Só o que é calculado fora dele, como um `NexoTones.income(context)` da tela, precisa do tom `*OnInk`.

## Regras

1. Sem cor escrita na tela. O teste trava a contagem: ela só pode cair.
2. Um painel de tinta por tela.
3. Texto normal com contraste de 4,5:1, em todas as superfícies e nos dois temas.
4. Sobre um preenchimento qualquer, use `NexoTones.on(cor)`, nunca branco fixo.
