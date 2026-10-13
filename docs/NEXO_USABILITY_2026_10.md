# Nexo — visibilidade financeira e revisão periódica

Rodada iniciada em outubro de 2026, branch `feat/nexo-financial-visibility-ux`.
Base: `feat/nexo-windows-native`, com alterações locais preexistentes preservadas.
Esta rodada não declara encerrada a homologação funcional Windows anterior.

## Inspeção e problemas

O Nexo 1.5.2+18 instalado no celular autorizado foi inspecionado por navegação somente de leitura: Home, Recorrentes, detalhe de recorrente, Mais e Empréstimos. Nenhum pagamento, exclusão, instalação ou exportação foi feito no celular. O banco real não foi copiado. Não há capturas ou valores pessoais neste documento.

- Recorrentes destacava médias mensais/semanais em vez dos vencimentos efetivos.
- O filtro inicial escondia parcelamentos. O botão flutuante disputava espaço com ações da lista.
- O detalhe priorizava metadados antes do histórico, sem sequência clara de vencimentos futuros.
- Empréstimos estava escondido nas ferramentas avançadas. A quantidade de registros de pagamento podia ser confundida com parcelas quitadas, inclusive com valores parciais/zero.
- Home tem excesso de altura em resumos e explicações. Não foi redesenhada nesta rodada: o foco foi compromissos, navegação e revisão financeira.

## Alterações

1. Recorrentes: Em aberto, Próximos meses, Histórico e Encerradas; filtro Todas por padrão; vencimentos reais no mês e atrasados separados; adicionar no cabeçalho; acesso a Dívidas e Agenda.
2. Projeção somente de leitura com datas reais, ancoragem no fim de mês, exclusão de IDs já registrados, preservação de parcelas puladas e limite explícito para cronogramas antigos/inválidos.
3. Detalhe: informações secundárias recolhidas, próximos vencimentos (até 12 meses), histórico pelos valores realmente registrados, modo privado respeitado. Pagamento/recebimento exige revisão do valor, conta e efeito financeiro antes do método contábil existente.
4. Dívidas e compromissos reúne acessos a cartões, empréstimos, parcelamentos e pendências. Não soma grupos potencialmente sobrepostos em uma dívida fictícia única.
5. Empréstimos apresenta restante, valor efetivamente pago, total contratual, média contratual explicitamente identificada e histórico. Não trata contagem de pagamentos como parcelas quitadas e não oferece pagamento imediato por um único toque na lista.
6. Mais → Planejamento torna dívidas, empréstimos e a revisão financeira acessíveis.
7. Revisão financeira: últimos 3 ou 7 dias, comparação com intervalo anterior de igual duração, receitas, consumo, reembolsos, categorias, saldo atual, contratos, orçamentos, objetivos e previsão de 7 dias/fim do mês. Exportação TXT em UTF-8 pelo seletor nativo de destino.

## Revisão financeira e uso com assistente

Abra **Mais → Revisão financeira**, escolha 3 ou 7 dias e **Gerar revisão**. Abra as seções e use **Salvar relatório .txt**. O arquivo pode ser anexado a uma conversa com o pedido “faça o relatório”. A leitura dos dados e os cálculos acontecem no Nexo, sem IA externa, servidor ou envio automático.

Os nomes são opcionais e ficam omitidos por padrão; valores e datas continuam privados. O modo de ocultar valores bloqueia geração/visualização/exportação. O relatório é uma fotografia do momento da geração: gere novamente depois de alterar lançamentos. Uma falha ao ler pagamentos de fatura impede a geração em vez de assumir que não houve pagamentos.

Não há acesso direto deste chat ao banco do celular, rotina agendada, sincronização PC/celular nem bot conectado. Um relatório gerado no PC contém apenas os dados locais do PC. Não representa automaticamente o celular. Não se deve compartilhar o arquivo SQLite em uso via pasta de nuvem.

Limites explícitos: contratos de empréstimo e dinheiro emprestado entre pessoas não geram automaticamente eventos de previsão; bens e histórico completo dos contratos permanecem nas telas específicas. Orçamentos usam todo o seu período e separam realizado e pendente. Consumo não é saldo, e pagamento de fatura não conta novamente. As taxas disponíveis localmente são usadas nas conversões.

## Pesquisa de experiência

- [Wallet — planned payments](https://budgetbakers.com/en/products/wallet/features/planned-payments/): dar contexto futuro aos vencimentos. Adaptação: sequência de ocorrências e ligação com a Agenda.
- [Monarch — recurring expenses and bills](https://help.monarch.com/hc/en-us/articles/4890751141908-Tracking-Recurring-Expenses-and-Bills): separar estado e período de compromissos. Adaptação: em aberto, próximos meses, histórico e encerradas.
- [Organizze — pagamentos recorrentes](https://www.organizze.com.br/blog/gestao-financeira/pagamentos-recorrentes): evidenciar vencimentos e atraso. Adaptação: atraso separado do restante do mês.
- [Minhas Finanças — ajuda](https://minhasfinancas.app.br/ajuda): referência conceitual de organização dos módulos e distinção entre recorrências, parcelas e empréstimos.

Nenhum código, asset ou desenho proprietário foi copiado.

## Dados e validação

Schema permanece **23**, banco `expensy.db`, identidade Android e assinatura preservadas. Nenhuma nova dependência. Não há migração nem rotina de escrita financeira nova para relatórios/projeções.

Pré-voo: dependências resolvidas, análise limpa, 156 testes aprovados antes das alterações. Novos testes cobrem projeção, fim de mês, duplicidade, histórico, confirmação cancelada, privacidade, layout compacto/desktop, períodos do relatório, neutralidade contábil e fatura já paga. Resultados finais e builds são registrados após execução, abaixo.

Capturas de revisão usam apenas dados sintéticos e ficam em `build/review`, fora do versionamento. Não equivalem a homologação manual de todos os fluxos Windows nem a instalação desta versão no celular pessoal.

### Resultado automático final

- `dart format`: aplicado aos arquivos desta rodada.
- `flutter analyze --no-pub`: nenhuma ocorrência.
- `flutter test --concurrency=1 --no-pub`: **184 testes aprovados**, incluindo os 28 novos testes de projeção, revisão e telas.
- Layouts novos exercitados em 360, 412 (escala de texto 1,5) e 1280 pixels por widget tests. Capturas sintéticas de Recorrentes, detalhe, Dívidas e Empréstimos revisadas. Não houve homologação visual nativa em todas as escalas/DPI.
- Android Release **1.5.3+19** compilado. `applicationId` conferido: `com.ma.expensy`; certificado SHA-256 `54d668e0f56caf801de429377a7a3066dbe0ed74779f04bac1ba1d2a5b112096`, o mesmo certificado Android Debug já utilizado pelo projeto. Nenhuma chave foi criada/substituída. Não é assinatura pública de produção nova.
- Versão no pubspec avançada de 1.5.2+18 (alteração local anterior) para 1.5.3+19. Identificadores técnicos e schema mantidos.
- Os builds refletem o estado local integrado, incluindo correções anteriores preservadas. O commit de usabilidade não incorpora indiscriminadamente os demais arquivos pendentes.
- Windows Release **1.5.3+19** compilado. Bundle completo em `build/distribution/Nexo-1.5.3+19-windows-x64.zip`; extrair todos os arquivos e executar `Nexo.exe`. Não distribuir apenas o EXE.
- Ensaio de inicialização Windows com `--test-profile` e TEMP/TMP exclusivos: processo permaneceu ativo e criou `NexoWindowsQA/expensy.db` na pasta temporária. Como a abertura foi oculta, não houve handle de janela acessível para fechamento normal; o processo QA identificado foi encerrado explicitamente. Isso NÃO comprova navegação, fechamento normal ou restart pela interface. Não declara Windows homologado.
- APK Release em `build/distribution/Nexo-1.5.3+19-android.apk`, SHA-256 `2673A43174999C02830BD24DB821D50D0AF1340C748E9C00F180C205F5EC7674`.
- ZIP Windows SHA-256 `D45A6AD380AA309D7A88785852C9FA545BE7F191837BF8165EC322599ECA185F`.
- A atualização não foi instalada no celular pessoal. Diálogo nativo de salvar TXT, revisão visual desta versão instalada e as pendências anteriores da homologação Windows permanecem para validação manual.
- Android Debug também compilado em `build/app/outputs/flutter-apk/app-debug.apk`. A primeira tentativa falhou por heap Java limitado a 1 GB; a repetição passou com 2560 MB, apenas em variável do processo, sem alteração permanente do Gradle.
- Avisos preexistentes de manutenção do AGP/Kotlin e traduções de outros idiomas foram preservados; não foram atualizadas dependências nesta rodada.
