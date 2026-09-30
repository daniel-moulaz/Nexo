# Nexo 1.5.0+16 — painel e automação

Rodada iniciada em 29/09/2026, continuada em 30/09/2026. Branch `feat/nexo-dashboard-automation-desktop`, base `3215817`. Main intacta. Antes de implementar: status, branch, fetch origin, histórico e docs revisados; `pub get`, analyze sem problemas e **92 testes** da base aprovados. Alterações locais preexistentes em `android/local.properties` e registrador Java gerado preservadas fora dos commits.

## Auditoria e escolhas de produto

1. Home antiga chamava de “ritmo seguro” uma divisão de caixa menos pendências do mês e dívida total de cartões, sem toda a previsão de recorrências/vencimentos. Era um nome de confiança excessiva. Extraordinárias pendentes também podiam diminuir o custo normal realizado. Agora a Home usa a previsão compartilhada da Agenda e separa consumo realizado de caixa previsto.
2. Estatísticas somava valores brutos de moedas diferentes e tinha cache dependente da lista de transações, sem refletir toda mudança de metadados. Havia três entradas concorrentes de relatórios em Mais. A navegação agora concentra Análises com cálculo compartilhado, conversão de moeda do app, filtros e detalhamento. Telas antigas permanecem no código para compatibilidade de referências, mas não são as entradas do menu.
3. Parser devolvia apenas null, sem motivo; usava `distinct()` nos valores, aceitando dois valores iguais como um só; não tratava título repetido no texto expandido; tinha poucas ordens de frase. Não havia confirmação pública de que os textos dos bancos fossem estáveis.
4. Fila nativa deduplicava só enquanto o item permanecia nela. SQLite já tinha tombstones, confirmação atômica e possível duplicata financeira. Adicionado histórico nativo limitado de fingerprints reconhecidos após ack para evitar reavisar imediatamente o mesmo evento. A deduplicação por semelhança continua exigindo decisão humana.
5. Sugestões estavam em Mais, sem aviso de chegada; revisão exigia selecionar conta sempre. Agora existe entrada direta na Home, aviso opcional e escolha de conta lembrada explicitamente.
6. Privacidade da caixa ocultava valor, mas mostrava descrição. Agora oculta ambos. O aviso externo é sempre genérico, inclusive com app fechado.
7. O app forçava `accessibleNavigation: false`. Isso foi removido para respeitar a preferência do sistema.
8. O teste completo de revisão em 360 px revelou overflow no seletor de tipo por causa do texto de transferência. Campo expandido e texto limitado corrigem o layout; o teste também verifica pré-preenchimento, confirmação explícita, saldo, metadados e resolução da sugestão.

## Pesquisa atualizada de UX

Pesquisa documental em fontes oficiais; não houve login, acesso a contas bancárias ou avaliação presencial de todos os fluxos concorrentes. O benchmark de 26/09 continua em [NEXO_BENCHMARK_2026.md](NEXO_BENCHMARK_2026.md). Nenhum código, asset ou texto de interface foi copiado.

| Referência | Evidência e adaptação ao Nexo |
|---|---|
| [Minhas Finanças](https://minhasfinancas.app.br/) e [desktop](https://minhasfinancas.app.br/desktop) | Mais espaço para análise e importação no PC; sidebar e colunas próprias, mantendo um modelo financeiro compartilhado |
| [YNAB Spending Breakdown](https://support.ynab.com/en_us/spending-breakdown-H1H7YxmD0) e [metas](https://support.ynab.com/how-to-use-targets-rk5kkI9ks) | Categoria acessível e progresso visível; donut com lista de valor/percentual e restante por orçamento |
| [Monarch Reports](https://help.monarch.com/hc/en-us/articles/21846787088916-Reports) | Filtros e aprofundamento contextual; tocar gráfico abre somente os registros daquele recorte |
| [Copilot Dashboard](https://help.copilot.money/en/articles/6045480-dashboard-tab-overview) e [FAQ](https://help.copilot.money/en/articles/10238054-dashboard-faq) | Revisão de lançamentos e recorrentes no cotidiano; Nexo mostra sugestões diretamente e distingue previsto de realizado, sem presumir contratos fixos |
| [Wallet](https://budgetbakers.com/en/products/wallet/download/) | Superfície ampla para relatórios; tabela no detalhe desktop. Sync permanece uma engenharia separada da adaptação visual |
| Organizze, Mobills, Money Manager | Evidências do benchmark anterior mantidas; não há nova alegação sobre versões/planos nesta rodada |

Home: saldo e dois totais primeiro; maior categoria e comparação explícita; ações comuns e três acessos curtos; previsão, categorias e até três orçamentos. Secundários ficam em Análises, Agenda e navegação de contas. Não foi criado score nem recomendação de gasto inventada. “Quanto fica disponível?” é previsão informada, não autorização de gasto.

## Home, gráficos e fechamento

- Resumo com receitas realizadas, despesas realizadas, maior categoria e comparação até o mesmo dia do mês anterior. Base zero não produz percentual infinito. Meses curtos limitam o dia ao último disponível.
- Previsões em sete dias e fim do mês com `CashForecast`, pagamento parcial de fatura, recorrentes, receitas e atrasados. Falha de consulta não mostra falsa previsão zerada. Saídas previstas aparecem separadas do saldo em contas.
- Donut de consumo por categoria na Home (top 3 na legenda) e Análises (lista completa); tocar cada setor/linha abre lançamentos. Grupos usam ID, não nome potencialmente repetido.
- Barras receitas × despesas em seis meses, lista com valores exatos acessível sem toque no gráfico e média dos cinco meses anteriores. Meses sem registros contam como zero e isso é informado. Mês corrente é parcial.
- Filtros combinados: mês/período, conta ou cartão, categoria, subcategoria e tipo. Cancelar não aplica alterações. Filtro ativo é visível e pode ser limpo.
- Normal × extraordinário e origem recorrente × demais despesas; não chama todo recorrente de custo fixo, nem toda despesa sem origem de variável comprovada. Reembolso identificado fica separado de receita ordinária; sem vínculo histórico não reduz categoria por adivinhação.
- Orçado × realizado com limites mensais atuais e pendências. Não inventa histórico dos limites antigos. Patrimônio existente tem acesso direto.
- Fechamento mensal é uma visão recalculada, com receitas, despesas, reembolsos, resultado, maior categoria, comparação e orçamento. Mês corrente é marcado parcial. Não congela dados, não cria lançamentos e não oferece saldo histórico reconstruído a partir de saldos atuais.

Transferências registradas somam somente a ponta de saída, sem duplicar lados. Reservas, ajustes neutros e pagamento de fatura não entram no consumo. Compra no cartão conta na data da compra/parcela, não novamente no pagamento. Importados preservam `affects_balance`; relatórios não recalculam saldos.

## Notificações: fontes, arquitetura e limites

| Bancos pesquisados | O que as fontes sustentam |
|---|---|
| Nubank, Mercado Pago, Inter, PicPay | Identidades do benchmark anterior; [Mercado Pago](https://www.mercadopago.com.br/blog/configurar-notificacoes-alertas-conta-mercado-pago) documenta seleção de alertas; [Inter](https://ajuda.inter.co/conta-digital-pessoa-fisica-e-mei/como-faco-para-definir-a-forma-em-que-vou-receber-notificacoes) documenta preferências. [Inter segurança](https://ajuda.inter.co/cartao/o-inter-envia-mensagem-no-whatsapp-sobre-tentativa-de-compra-no-cartao) mostra por que pedido de reconhecimento não é compra confirmada. [PicPay](https://meajuda.picpay.com/hc/pt-br/articles/360044238472-Por-que-n%C3%A3o-estou-recebendo-notifica%C3%A7%C3%B5es-sobre-as-promo%C3%A7%C3%B5es) também tem promoções; receber push não prova evento financeiro |
| Itaú, Bradesco, Banco do Brasil | [Itaú SMS](https://www.itau.com.br/cartoes/servicos/aviso-sms), [Bradesco push](https://banco.bradesco/html/principal/cartoes/servicoseseguros/notificacao-de-compras-pelo-app/), [BB SMS/Push](https://www.bb.com.br/site/pra-voce/solucoes-digitais/sms/). Canais, limites e preferências variam; não tratar SMS como push do banco nem pedir acesso a SMS |
| C6, Caixa, Santander | [C6 segurança](https://cdn.c6bank.com.br/c6-site-docs/cartilha-de-seguranca.pdf), [Caixa notificações](https://www.caixa.gov.br/atendimento/canais-digitais/banking-caixa/primeiro-acesso/servico-de-sms/Paginas/default.aspx), [Santander Way](https://www.santander.com.br/baixeway). Nenhuma dessas fontes é contrato estável de formato textual de push |

`NotificationPattern` contém ID, regex de evento, tipo e confiança; `ParserResult` contém sugestão ou motivo genérico. Alta confiança exige evento explícito, média cobre pagamento/transferência cujo destino precisa de revisão. Baixa/ambígua não entra. Exemplos de teste são **sintéticos**, não capturas de bancos nem alegação de suporte universal.

Agora aceita ordens explícitas como “compra de [valor] aprovada” e “você recebeu/enviou um Pix”. Rejeita negativas, solicitações de reconhecimento, múltiplos valores mesmo iguais, moeda estrangeira identificada, valores negativos, OTP/senha, saldo/limite/fatura, conteúdo excessivo e valores fora dos limites. Só remove duplicação estrutural quando o corpo começa com o título inteiro; não elimina valores repetidos arbitrariamente.

Não armazena texto bruto. Descrição é um estabelecimento curto e conservador após “em” ou um rótulo genérico; destinatário Pix e números de cartão não são retidos. Configurações > Automação > Diagnóstico mostra somente estado, lista já autorizada, horário, resultado e confiança do último padrão. Eventos de apps não autorizados têm motivo, mas conteúdo não é lido. Há orientação de configurações restritas em sideload e aviso se o Android bloqueou notificações do Nexo.

Aviso “Nexo detectou uma movimentação”, opcional/desligado por padrão, sem valor/estabelecimento. Um aviso agrupado abre revisão atrás da proteção Nexo, em cold/warm start. Ignorar está na caixa com desfazer; não há ação financeira pelo push. Não se implementou “Ignorar” externo que precisasse resolver SQLite sem Flutter: um toque em Revisar dá acesso ao fluxo completo.

Fila continua AES-GCM/Keystore, sete dias e 250 itens, com backpressure; SQLite conserva tombstones por 90 dias. Após ack, mapa nativo de até 2000 fingerprints por sete dias evita reavisos. Mudança de chave Android, horário ou descrição pode gerar sugestão distinta; revisão financeira por conta/valor/data continua obrigatória quando houver candidato. Mudanças de parsing podem alterar descrições/fingerprints legados; não existe promessa de deduplicação perfeita entre versões ou fontes.

“Lembrar esta escolha” guarda associação app + meio + tipo → account_id nas preferências do aparelho. Revalida existência, BRL e compatibilidade cartão/banco; nunca confirma. Pode esquecer todas em Automação. Regras de categoria existentes ficam acessíveis ali, com exemplos editáveis IFOOD, UBER, NETFLIX e POSTO; nenhum exemplo é ativado sem escolher categoria/salvar. Data, valor, descrição, tipo e categoria permanecem editáveis. A gravação da associação é separada: sua falha não transforma lançamento já salvo em tentativa financeira repetida.

## Extras, schema e compatibilidade

- Novo lançamento sugere a conta do registro manual realizado mais recente do mesmo tipo; ignora importações, neutros e pendências, mantendo seleção visível.
- CSV/XLSX preservam todas as colunas anteriores e acrescentam transaction_id, data_hora ISO, account_id, tipo_conta, cartão, ciclo_fatura, destination_account_id quando par conhecido e origem técnica. IDs são texto; proteção contra fórmulas permanece. `updated_at` não existe e não é inventado.
- Schema **23 → 23**. Nenhuma migração financeira, nenhuma alteração de saldo legado. Preferências locais novas não fazem parte do backup financeiro; diagnóstico contém somente códigos/horário. ApplicationId `com.ma.expensy`, `expensy.db`, assinatura e splash preservados.
- Windows: apresentação responsiva implementada; toolchain C++ ausente e adaptadores nativos ainda precisam portabilidade. Ver [NEXO_DESKTOP.md](NEXO_DESKTOP.md).
- Sync: somente design técnico, matriz de aceitação e plano de migração; ver [NEXO_SYNC_ARCHITECTURE.md](NEXO_SYNC_ARCHITECTURE.md). Nenhum teste de sync foi falsamente contabilizado como aprovado.

## Ainda planejado

Motor offline de sync e backend exigem prova com dois bancos sintéticos, conflitos/restore e consentimento antes de dados reais. Distribuição Windows depende de toolchain e validação dos adaptadores. Fechamento imutável, histórico de limites, próximo mês comprometido em fechamento histórico, multicategoria, favoritos/modelos, conciliação com vínculo persistente e reclassificação de estornos exigem dados/modelagem adicionais. Não foram acrescentados controles sem implementação funcional.

## Validação e builds

- `dart format`: arquivos alterados formatados; `flutter analyze`: **sem problemas**.
- `flutter test --concurrency=1 --dart-define=CAPTURE_REVIEW=true`: **118 testes aprovados** (base: 92). Inclui neutralidade de transferências/reservas/faturas, pendências, reembolsos, filtros, comparação de períodos, retenção, revisão de sugestão e exportação.
- Teste Android do próprio app: `:app:testDebugUnitTest --tests com.ma.expensy.FinancialNotificationParserTest`: **7 testes aprovados**, sem falhas/erros. Não depende dos testes internos dos plugins.
- Layouts exercitados: **360×800, 412×915, 1280×720 e 1920×1080**, incluindo modo escuro e fonte ampliada. Capturas inspecionadas da Home e Análises usam exclusivamente dados sintéticos em `build/review/` e não são versionadas.
- **Homologação Android real pendente**: nenhum aparelho físico conectado. O AVD Pixel 7 não iniciou em três tentativas por limite de memória comprometida do Windows (requeria 4096 MB livres). Não foi instalado APK nesta rodada. Permissões/restrição de sideload, entrega de push em background, cold/warm start protegido, biometria física e splash precisam de teste em aparelho; testes unitários/de layout não substituem isso.
- **Windows**: alvo nativo não habilitado; sem build Windows por ausência de toolchain C++ e portabilidade dos adaptadores ainda pendente.
- **Sync**: design somente; matriz contábil de sincronização documentada, mas ainda não executada.
- O build mantém avisos de futura descontinuação das versões atuais de Gradle/AGP/Kotlin. Atualização do toolchain fica em lote próprio; não foi alterada a configuração de assinatura para contornar o build.

Builds finais concluídos em 30/09/2026:

| Artefato | Resultado | Bytes | SHA-256 |
|---|---|---:|---|
| `build/app/outputs/flutter-apk/app-debug.apk` | `flutter build apk --debug` aprovado | 181278265 | `8C87B6149B840AA2046CAF31E2539B796B7624CB63E0763C86DA4A4B1CF30A4C` |
| `build/app/outputs/flutter-apk/app-release.apk` | `flutter build apk --release` aprovado | 70622954 | `DDF79DD5860A2B036FF6EAD114382AF5F29282DC97B09186331A37E62A6F4E88` |

`aapt dump badging` confirmou em ambos: applicationId `com.ma.expensy`, versão `1.5.0`, versionCode `16`, nome Nexo. Configuração de assinatura, manifesto e schema não tiveram diff em relação à base. APKs são artefatos locais ignorados pelo Git; não foram instalados, publicados ou enviados.

## Git

- `6566fdb` — painel analítico, Análises, automação diagnosticável, responsividade e testes.
- `5131618` — correção da revisão em celular compacto e teste completo de confirmação.
- Documentação desta rodada em commit separado. Sem push, merge ou alteração direta da main; arquivos locais gerados preexistentes permanecem fora dos commits.
