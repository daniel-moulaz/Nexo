# Homologação Windows — Nexo 1.5.1+17

30/09/2026 · branch `feat/nexo-windows-native` · schema **23 antes/depois**.

**Status: homologação parcial; Windows ainda não aprovado para distribuição final.** Há evidência funcional nativa de contabilidade, arquivos, persistência e secure storage. Isso não substitui a conclusão do roteiro manual pelos controles do bundle.

## Continuidade e isolamento

- Mantidos os resultados já aprovados: pub get, analyze limpo, 142 testes, ZIP original conferido/extraído, primeira abertura e onboarding observados.
- Commits de base: `247a5f9` (runner/persistência/plataformas) e `5efa5df` (interface/tabela/atalhos).
- Git status, diff, staging e oito commits revisados antes de retomar. Staging inicialmente vazio.
- Alterações preexistentes de `android/local.properties` e `GeneratedPluginRegistrant.java` preservadas, fora dos commits. Outros arquivos apareciam modificados apenas por terminadores de linha; não foram descartados.
- Instância normal do usuário preservada. Nenhum dado pessoal lido/importado para a base de testes.
- ZIP original: `build/distribution/Nexo-1.5.1+17-windows-x64.zip`, SHA-256 `16C99EE04DA20672EA7D624548F575752AE438C56CFEC8D5549EBE55BC3F98DD`.
- Extração original limpa: `build/review/homologation-20260930-184435/bundle`. Executado com `--test-profile` e TEMP/TMP próprios.
- Banco normal permanece `%LOCALAPPDATA%/Nexo/expensy.db`. QA usa `%TEMP%/NexoWindowsQA/expensy.db`, prefixo de preferências e chave de segurança separados.

## Bugs encontrados e corrigidos

### Restore de backup incompleto podia apagar o acervo

Reprodução: JSON com apenas `{"version":23}` passava pelo reconhecimento superficial de backup e substituía as tabelas por listas vazias. A regressão foi reproduzida antes da correção.

Agora DBHelper valida versão, tabelas obrigatórias, formato das linhas e IDs duplicados **antes** de substituir dados. AppProvider interpreta configurações antes de importar SQLite. Rejeição preserva integralmente o banco. Backups da versão 22 sem a tabela de sugestões continuam aceitos e restauram no schema 23.

Testes cobrem arquivo incompleto, somente configurações, versão futura, configuração de tipo inválido, IDs duplicados e restore legado. A correção é compartilhada com Android.

### Atalhos não recebiam foco ao abrir uma edição

A tabela abria o formulário, mas Esc não cancelava sem um primeiro clique num campo. Adicionado foco inicial no contêiner do formulário. Regressão cobre abrir edição e cancelar, repetir sem autosalvar, navegação Tab e Ctrl+Enter com valor inválido. **Nenhum Esc foi enviado por Computer Use nesta retomada.**

### Receita marcada como gasto na exportação

A abertura do CSV real revelou “Conta como gasto? = Sim” na linha de salário. Os totais do resumo estavam corretos; o erro era a classificação da coluna para análise externa. Corrigida a condição compartilhada por CSV e XLSX: somente despesas não neutras recebem Sim. A regressão foi reproduzida antes da correção e cobre receita, despesa, pendente e transferência, sem alterar saldos. Os arquivos do ensaio anterior preservam a evidência do defeito; o teste de exportação final verifica os arquivos regenerados.

## Ensaio nativo Release com plugins reais

`tool/windows_native_check.dart` compila um entrypoint de teste usando os mesmos serviços financeiros e os plugins nativos registrados no runner. Não usa mock de SQLite nem de secure storage. É complementar ao ensaio do bundle; não é apresentado como automação manual dos formulários.

Executado em dois processos independentes, com banco sintético novo e rede Dart bloqueada por HttpOverrides somente nesses processos. Ambos concluíram com código 0. A segunda execução só começou após a primeira terminar.

Evidências locais não versionadas:
`build/review/native-probe-20260930-190639/temp/NexoWindowsQA/native-create.json` e `native-restart.json`.

| Etapa | Esperado | Encontrado |
|---|---|---|
| Banco inicial | R$ 1.000 | R$ 1.000 |
| Receita 1.500, despesa paga 100, pendente 80 | Banco 2.400; receitas 1.500; consumo 100; pendentes 80 | Exatamente esses valores |
| Transferir 200 à reserva | Banco 2.200; reserva 200; total 2.400; consumo 100 | Exatamente esses valores |
| Compra no cartão 120 | Banco 2.200; dívida 120; consumo 220 | Exatamente esses valores |
| Pagamento integral da fatura | Banco 2.080; dívida zero; patrimônio 2.280; consumo continua 220 | Exatamente esses valores |
| Orçamento Alimentação 350 | Usado 100; restante 250; 28,57% | Exatamente esses valores; UI arredonda para 29% |
| Recorrente mensal 30 | Um pagamento; próxima ocorrência futura; banco 2.050 | Uma ocorrência mesmo com duas solicitações simultâneas |
| Após todos os eventos | Banco 2.050 + reserva 200 = 2.250; consumo 250 | Nove linhas no ledger; nenhuma duplicação |
| Backup, editar mercado 100→777, restaurar | Mercado volta a 100; banco 2.050 | Exatamente esses valores |
| Encerrar e abrir outro processo | Mesmas nove linhas, saldos e configurações | Preservados |

A compra no cartão é consumo uma vez; pagamento da fatura e os dois lados da transferência são movimentos neutros. Os R$ 80 pendentes não reduziram saldo atual.

## Matriz funcional e limites

| Fluxo | Evidência obtida | Pendência manual |
|---|---|---|
| Primeira abertura/onboarding | ZIP original extraído e aberto; telas observadas | Concluir todo onboarding digitado, sem perda de foco da ferramenta |
| Home | Release normal abriu base sintética; captura nativa e árvore acessível conferidas | Inspeção em todos os tamanhos da janela |
| Home: números/gráficos | Saldo 2.250; receita 1.500; gasto 250; previsão 2.170; maior categoria Compras 120/48%; Alimentação 100/40%; Contas 30/12%; orçamento restante 250 | Comparação visual com outro mês preenchido |
| Análises | Cálculos contábeis e filtros por código; widgets abrem filtros e drill-down da categoria em seis tamanhos | Todos os filtros e cliques no executável |
| Transações | Widgets: busca, filtro preservado entre abas, ordenação, páginas de 20/4 linhas, abrir edição e repetir sem autosalvar | Salvar/editar/repetir integralmente por teclado no bundle |
| Importação | CSV, TXT e OFX: preview sem gravar; confirmação explícita; duplicata ignorada; saldo não alterado silenciosamente | Diálogo nativo de escolher arquivo e confirmação no bundle |
| Erros de importação | Cancelamento do picker, arquivo inexistente e CSV inválido: mensagem e ledger intacto | Caminho com ACL negada pelo Windows |
| Exportação | CSV e XLSX gravados e reabertos; IDs, colunas, valores, datas, moeda e acentos em testes e arquivo real | Diálogo nativo de salvar e abrir no Excel |
| Backup/restore | Arquivo real, alteração, restauração, restart sem duplicação; inválidos rejeitados | Escolha/confirmação de arquivo pelos botões |
| PIN/secure storage | Plugin Windows real: ativar, fechar processo, carregar bloqueado, erro/acerto, cooldown e desativação persistidos | Botões ativar/bloquear agora/remover e reabertura da UI protegida |
| Restart | Processo do ensaio terminou; segundo processo recuperou DB, preferências e PIN | Fechar/reabrir interface e janela por botões; não houve reboot do computador |
| Múltiplas instâncias | Segunda execução abriu somente janela intitulada Nexo e terminou; código do mutex retorna antes de criar FlutterWindow; não houve segundo acesso ao SQLite observado | Mensagem e foco da instância existente não capturados de forma confiável |
| Responsividade | Home/Análises/Fechamento/shell/tabela: 1280×720, 1366×768, 1920×1080, 2560×1440; resize dinâmico desde 960×640 por widget tests; captura nativa inicial 1280 | Maximizar/minimizar/restaurar e DPI no Windows real |
| Offline | Dois processos nativos com HttpClient bloqueado; CRUD, consulta, edição, restore e export funcionaram | Rede Windows realmente indisponível; não foi desconectado o ambiente |
| Teclado | Ctrl+F, Ctrl+N, Tab, Ctrl+Enter validando entrada e Esc por widgets | Salvamento válido via Ctrl+Enter no bundle; Esc fica manual opcional |
| Valores brasileiros | 32,90/32.90→32,90; 1.234,56/1234,56→1.234,56; ambiguidade inválida rejeitada; data/hora local e pt-BR | Teclado numérico físico |

A tabela separa abertura do formulário e gravação financeira: o teste de Ctrl+Enter confirma validação do formulário, não deve ser descrito como homologação manual de um salvamento válido.

## Exportações e arquivos

O CSV real contém 23 colunas, incluindo transaction_id, data_hora, account_id, tipo_conta, cartao, ciclo_fatura e destination_account_id. Usa data brasileira, valor numérico decimal com ponto e coluna BRL; a UI usa R$ com vírgula. Acentos de “Salário”, “Cartão” e “Transferência” foram preservados. Movimentos neutros têm “Conta como gasto? = Não”. XLSX foi reaberto pelo decodificador, com as nove linhas e cabeçalho.

Teste de arquivo bloqueado preservou conteúdo anterior; ausência de diretório/arquivo resulta em erro controlado. Não houve alteração de ACL, disco do usuário ou dados pessoais.

## Layout e limitações do Computer Use

A Home já usa duas colunas e limite de 1440 px. A captura sintética de shell 1920×1080 foi revisada: conteúdo centralizado, margens equilibradas e gráficos lado a lado. Não houve evidência suficiente para justificar novo redesenho ou alargamento nesta rodada. A Home nativa inicial também foi observada com os valores do ensaio.

A ferramenta alternou entre a árvore acessível do Nexo e capturas de outro aplicativo; também houve controles fora do cache e perda de foco ao digitar. Ativação explícita recuperou uma captura correta, mas o problema voltou. A interação insegura não foi repetida. Não foram usados Esc, comandos de sistema via UI, desligamento de rede nem alterações de segurança para contornar a ferramenta. Capturas privadas não foram salvas/versionadas.

## Validação automática e builds

Resultados finais e hashes serão registrados ao concluir os comandos desta rodada. Logs ficam apenas em `build/review`.

- Baseline recebido: 142 testes.
- Após regressões de backup/importação: 148 testes aprovados.
- Regressão adicional de foco/tabela: passou isoladamente.
- Suite final, analyze e builds: em verificação.

## Reproduzir o ensaio nativo

1. Compilar `flutter build windows --release --target tool/windows_native_check.dart`.
2. Copiar **toda** a pasta Release para pasta temporária nova.
3. Definir TEMP e TMP somente no processo de lançamento, apontando para uma pasta de teste nova. Executar o EXE copiado com `--test-profile` e aguardar saída.
4. Executar o mesmo EXE com `--test-profile --qa-resume`; conferir relatórios e código de saída 0.
5. O PIN fixo do ensaio é uma fixture sintética, não uma credencial do usuário. A fase restart remove a proteção exclusivamente da chave QA.
6. **Reconstruir `--target lib/main.dart` antes de empacotar/distribuir.** O executável do ensaio não é o aplicativo distribuível.

## Pendências para aprovação final

Concluir os itens manuais da matriz com controle exclusivo e confiável da janela. Validar especialmente diálogos nativos de import/export/restore, PIN pelos controles, gravação dos formulários, múltiplas instâncias e resize/maximização. Homologar bundle em Windows x64 limpo, escala DPI e desempenho com base grande.

PIN não criptografa a base. Windows Hello/recuperação de PIN, persistência de janela e filtros após reinício permanecem fora desta versão. Paginação é de widgets, não SQL; parsing de importação ainda usa a isolate de UI. Não foi feita sincronização, upload, backend, assinatura pública ou mudança de schema.

Depois da aprovação Windows local, retomar [NEXO_SYNC_ARCHITECTURE.md](NEXO_SYNC_ARCHITECTURE.md): conflitos, tombstones, retry/idempotência e restore+sync precisam de engine e testes próprios antes de qualquer envio real.
