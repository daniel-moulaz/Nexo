# Carteira de investimentos — 1.6.0+21

Implementação em 19/10/2026, branch `codex/nexo-investments`.

## Produto e limites contábeis

Carteira local de acompanhamento em BRL, acessível na Home, Mais > Planejamento e sidebar Windows. Cadastro de posição inicial ou compra; operações adicionais de compra, venda/resgate e provento recebido. Quantidade com seis casas, custo médio proporcional nas vendas, custo restante, valorização não realizada, resultado realizado e proventos separados. Compras do mês não incluem a posição inicial. Gráfico de distribuição por classe com filtro ao tocar, busca por nome/ticker/instituição, histórico por ativo e atualização manual do preço.

**Não é uma conta de investimento integrada ao caixa.** Operações não alteram contas, receitas, consumo, cartões ou o patrimônio consolidado legado. A interface explica essa separação para evitar somar duas vezes investimentos já representados em contas/bens. Proventos na carteira não criam uma segunda receita bancária. Renda fixa/cripto/FIIs/ETFs podem ser acompanhados manualmente; não há cálculo automático de juros, impostos, desdobramentos, inflação, CDI, TWR ou TIR. A diferença valor/custo não é apresentada como rentabilidade de um período. Não há recomendação de ativos.

Valores persistidos em centavos inteiros; quantidades/preços em milionésimos. Produtos intermediários usam BigInt para evitar overflow. Limites explícitos: quantidade de 1 milhão de unidades por posição, preço unitário de R$ 1 milhão, custo de R$ 1 trilhão. Vendas descobertas e exclusões que deixam vendas sem quantidade são bloqueadas. Repetição da mesma operação/ID é idempotente; alteração do payload com ID usado é rejeitada. Cadastro inicial e operação são transacionais. Excluir operação exige confirmação e recalcula a posição. Correção de operação é exclusão e novo registro; edição de nome/classe, exclusão do cadastro vazio e eventos corporativos permanecem para evolução posterior.

## Cotações e privacidade

Adaptador HTTPS para `https://brapi.dev/api/v2/stocks/quote?symbols=...`, contratado como recurso opcional, desligado por padrão. Suporte online desta rodada: ações brasileiras com ticker. FIIs e demais classes não são enviados a um endpoint de ações por suposição. Sem chave, a documentação permite PETR4, VALE3, ITUB4 e MGLU3 para teste. Cobertura adicional depende da chave/plano do usuário; nenhum plano pago foi contratado.

Ao ativar, consulta ao abrir a tela, no máximo uma rodada a cada 15 minutos, sequencial, até 20 códigos únicos por rodada. Botão de atualização respeita o mesmo intervalo. Não há serviço em background nem promessa de tempo real. Provedor recebe ticker e metadados de rede; nunca quantidade, instituição, posição, saldo ou histórico. Chave pessoal em flutter_secure_storage com namespace QA separado; não entra no banco, backup, URL ou Git. Autorização pelo header, redirects desabilitados, timeout de 15 segundos e resposta máxima de 128 KiB. Moeda divergente, preço inválido, ticker renomeado e data futura são rejeitados. Falha/offline preserva preço anterior; resposta mais antiga não substitui avaliação mais nova. Data/fonte visíveis e aviso de preço antigo no detalhe.

Consulta real em 19/10/2026 com PETR4 de demonstração retornou HTTP 200, BRL, preço e horário. Não envolveu carteira real. Testes HTTP usam respostas sintéticas; autenticação com chave pessoal ainda não exercitada.

## Persistência e backup

`expensy.db` schema **23 → 24**. Migração aditiva cria `investments` e `investment_operations`, além de índice por investimento. Nenhuma tabela anterior é renomeada ou apagada. IDs UUID estáveis e datas UTC nas operações. Backup JSON inclui ambas as tabelas; restauração valida vínculos, IDs, tipos e replay contábil antes de substituir dados. Backup 23 continua aceito e restaura carteira vazia. Backup 24 incompleto é rejeitado. Versões anteriores do app não devem receber backup 24.

Sem integração com protótipo de sincronização nesta rodada. Histórico local não significa sync ativo. API de cotações não faz login bancário nem importa carteira da B3.

## Pesquisa e decisões

- [AUVP](https://www.auvp.com.br/): referência conceitual de organização e gestão de carteira; não houve acesso à área fechada, reprodução do Diagrama do Cerrado ou cópia de interface proprietária.
- [Kinvo — metodologia](https://suporte.kinvo.com.br/articles/48c87376-9ec0-4f68-a67c-36f97dfb64fd): aportes mudam o capital e não podem ser confundidos com performance; decisão de não fabricar gráfico histórico/percentual sem séries suficientes.
- [Gorila — cálculos e cotizações](https://guia.gorila.com.br/hc/pt-br/sections/360009897352-C%C3%A1lculos-e-Cotiza%C3%A7%C3%B5es): separar resultado nominal de rentabilidade histórica e explicitar avaliação manual.
- [brapi — API](https://brapi.dev/docs), [autenticação](https://brapi.dev/docs/authentication): integração extensível, limites, token pessoal seguro e atualização opcional.

## Validação

Pré-voo: fetch, branch dedicada, alterações anteriores preservadas; pub get, analyze limpo e 221 testes aprovados. Tela Home e menu Mais do Android real inspecionados sem editar dados; capturas privadas apenas em build ignorado. Nenhuma base real foi copiada ou enviada a APIs.

19 testes novos de domínio/repositório/HTTP aprovados: custo médio, venda parcial/total, proventos, venda histórica inválida, replay, rollback por falha, migração 23→24, backup/restore antigo/novo/inválido, ausência de mudanças no caixa, restart, preço antigo, respostas inválidas, offline e status de erro do provedor.

6 testes de interface aprovados: 320×740, 412×915 escuro, 1280×720 e 1920×1080; fonte ampliada no celular; privacidade/filtro/detalhe; cadastro, venda e preço manual com persistência. Corrigido callback setState que retornava Future na recarga após salvar. Capturas sintéticas revisadas em build/investments-review. Testes não equivalem à homologação nativa completa.

Análise final limpa. Uma execução completa teve 245 aprovados e um overflow no seletor de classe em 320 px; corrigido com campo expansível e os seis testes de UI passaram novamente. Execução completa final: **246 testes aprovados**, com `flutter test --no-pub --concurrency=1`.

Windows Release compilado e empacotado em `build/distribution/Nexo-1.6.0+21-windows-x64.zip`; SHA-256 `8E3A564F742960609B7B26AF2A6965C4650DDA771F33A49741FF61E7F980A121`. Distribuir toda a pasta extraída. Não houve homologação nativa/manual desta carteira no EXE; os fluxos foram exercitados por testes de widgets e SQLite FFI.

Android Release **não concluído**: `:app:mergeReleaseNativeLibs` falhou com “Espaço insuficiente no disco” ao extrair as bibliotecas Flutter. Retry automático interrompido e intermediários regeneráveis limpos para devolver espaço. Não houve mudança de assinatura, applicationId ou instalação no celular. O aparelho permanece na versão anterior. Necessário liberar espaço adicional antes de reconstruir; não instalar build parcial.

Limpeza autorizada pelo usuário: caches de download npm, arquivos temporários de compilação Flutter encerrada, cache de páginas Chrome/Edge (sem cookies, histórico ou senhas), ZIPs Gradle já extraídos e cache de transforms após falha. Dados pessoais, backups, instaladores Nexo e versões de código preservados.

O commit desta rodada inclui a validação de backup já pendente em DBHelper porque ela é pré-requisito para rejeitar restaurações incompletas no schema 24. Demais mudanças anteriores de notificações/Windows/sync permanecem fora do commit; nos testes legados foram selecionados apenas os ajustes que consultam schemaVersion.

## Próximos passos

Vinculação explícita e transacional ao caixa, conciliação de posições antigas para evitar dupla contagem, edição de cadastro, eventos corporativos, cotações específicas de FIIs/ETFs, séries históricas e performance ponderada por fluxos, exportação tabular da carteira. Priorizar corretude antes de automatizar movimentações.
