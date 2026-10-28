# Relatório da rodada de evolução (27 e 28/10/2026)

Resposta à missão "desvinculação do Expensy e evolução integral do Nexo". Cada
item diz o que **já existia**, o que foi **preservado**, **corrigido**, **redesenhado**,
**criado**, o que ficou só **recomendado** e o que está **pendente** e por quê. Nada
aqui é dado como feito sem teste ou instalação registrada.

## 1. Diagnóstico inicial

`docs/AUDITORIA_NEXO_2026_10.md`: números do código, o que sustenta o produto (fronteira
de escrita única, regras financeiras isoladas, sincronização com protocolo próprio, MCP
como pedido), o que pesa (`AppProvider` de 2.103 linhas, telas gigantes, 94 `catch (_)`
silenciosos, i18n pela metade, finais de linha mistos, sete serviços de notificação) e o
que falta no produto.

## 2. Desvinculação do Expensy

`docs/NEXO_DESVINCULACAO_EXPENSY_2026_10.md`. **Feito (1.12.10):** pacote Dart `nexo`
(405 imports), classes `Nexo*`, banco `nexo.db` com migração testada, canais nativos
`nexo/*`, CMake `nexo`, sonda nativa removida, LICENSE com o aviso do Nexo sobre o MIT
original, README e docs sem o nome antigo fora do histórico, remotos git só do Nexo.
**Mantidos por decisão do dono:** `applicationId` `com.ma.expensy` (o app instalado
continua o mesmo) e os ids internos dos canais de notificação. **Residual legítimo:** o
aviso MIT de Mina Android, exigido pela licença; o histórico git.

## 3. Referências e análise competitiva

`docs/PESQUISA_REFERENCIAS_2026_10.md` (28/10, com links) e
`docs/REFERENCIA_AUVP_FINANCAS_2026_10.md` (27/10, acesso real ao AUVP Finanças). Cada
referência separa verificado de hipótese e termina com a adaptação para o Nexo e sua
prioridade. Treze adaptações consolidadas.

## 4. Propostas de evolução

`docs/PLANO_EVOLUCAO_2026_11.md`: P0 (base), P1 (alto impacto), P2 (evolução), P3
(inovação), com problema, solução, referência, arquivos, complexidade, aceitação e estado.
Substitui o roadmap anterior.

## 5. Decisões de arquitetura nesta rodada

- Paleta de comandos como registro de entradas puro (`paletteEntries`) separado da
  interface (`CommandPaletteView`): testável sem UI e reaproveitável no Windows e no
  celular.
- Lançamento por texto como parser puro (`TextEntryParser`) que **não grava**: devolve
  campos e o formulário existente confirma. Mantém a regra "nada entra sozinho".
- Categoria aprendida como contagem local por descrição normalizada com limiar
  (`CategoryMemory`), sem modelo em nuvem; inspirada no Copilot, mas sem rede.
- Migração do nome do banco por renomeação atômica depois de checkpoint, com fallback
  para o nome antigo; nunca cria um segundo banco vazio.

## 6. Mudanças visuais

Já estavam feitas antes desta missão e seguem válidas: marca nova (N dourado), Hoje e
Extrato redesenhados, 14 telas secundárias no sistema plano, Mais em grupos com
divisórias, barra lateral do Windows com os nomes do celular, abertura com a marca
(`docs/DESIGN_2026_10.md`). Nesta rodada: a lupa do Hoje passou a abrir a paleta e o
rodapé de atalhos do Windows ganhou Ctrl+K.

## 7. Funcionalidades implementadas (1.12.11)

| Item | Onde | Teste |
|---|---|---|
| Buscar ou fazer (paleta; Ctrl+K; lupa) | `lib/widgets/command_palette.dart`, `main_shell.dart`, `finance_home_screen.dart` | `test/command_palette_test.dart` (5) |
| Lançar por texto | `lib/services/text_entry.dart`, `add_transaction_screen.dart` (`initialDate`, template com campos em branco) | `test/text_entry_test.dart` (11) |
| Categoria aprendida | `lib/services/category_memory.dart` (usada no lançamento por texto) | em `text_entry_test.dart` |
| Texto 1,5× nas nove telas principais | — | `test/scaled_text_tabs_test.dart` (9) |
| Banco `nexo.db` com migração | `lib/database/database_platform.dart` | `test/database_rename_test.dart` (3) |

Removidas na 1.12.9 (já antes da missão, aprovadas pelo dono): monitoramento de
notificações do Android, Revisão financeira, Previsão detalhada, Dívidas e compromissos,
cinco telas sem navegação.

## 8. Validação

- Suíte Flutter completa, análise limpa (número no CLAUDE.md, "Última validação").
- Builds Android (assinatura `54d668e0…`) e Windows da 1.12.10 e da 1.12.11.
- Instalação no celular: ver "Pendentes".
- Não reexecutados nesta rodada: SQL/MCP/Pluggy (Node), roteiro e2e contra o Supabase,
  testes Kotlin. A paleta e o lançamento por texto foram verificados por teste de widget,
  não por uso manual no aparelho.

## 9. Recomendado, não implementado

Tudo o que está como "proposto" no plano. Os primeiros da fila: P1-3 (categoria aprendida
na caixa Para revisar), P1-4 (gastos irregulares provisionados), P1-5 (até a próxima
renda), P0-4 (diagnóstico local), P0-2 (`.gitattributes`), P2-3 (PT-BR único; decisão do
dono).

## 10. Pendentes e por quê

- **Instalar a 1.12.11 no celular:** o aparelho saiu do USB durante a rodada; o APK está
  compilado e conferido. O CLAUDE.md diz o estado exato.
- **Pasta local `projetos\Expensy`:** só o dono renomeia, com as sessões fechadas.
- **Fork `daniel-moulaz/Expensy` no GitHub:** intocado; arquivar ou apagar é decisão do
  dono.
