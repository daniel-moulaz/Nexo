# Nexo 1.5.2+18 — cartão e sugestões

Revisão concluída em 04/10/2026. Projeto: C:\Users\danie\projetos\Expensy.

## Alterações

- Home separa saldo em contas, dívida em aberto nos cartões e disponível após cartões. Cada cartão mostra a dívida total e o restante da fatura atual.
- Disponível = saldo das contas incluídas menos a dívida restante dos cartões incluídos. Pagamentos já refletidos nos saldos não são subtraídos outra vez. Créditos positivos de cartão não viram dinheiro bancário. O total inclui parcelas futuras já cadastradas; outros compromissos permanecem na previsão.
- Fatura respeita ocultação de valores e apresenta carregamento, erro e nova tentativa. Mudar de período invalida a fatura anterior antes de permitir pagamento.
- Sugestões: recuperação/reconexão do listener Android, leitura alternativa de textos, mais variantes de compra/Pix, atualização automática da inbox, tolerância a registros malformados e sincronização concorrente segura.
- O recebimento só é confirmado à fila nativa após persistência local. Falhas de sincronização não escondem sugestões já salvas. Diagnóstico e estados vazios orientam a configuração.
- Revisão bloqueia múltiplos toques. Nada vira lançamento sem confirmação explícita. Deduplicação, expiração de 7 dias, tombstones de 90 dias e fila criptografada foram preservados.
- Indicadores monetários adaptam as colunas ao texto ampliado. Corrigidas também fixtures de teste que falhavam no começo do mês e mocks do canal de eventos.

## Compatibilidade

Mantidos applicationId com.ma.expensy, namespace, configuração de assinatura, dependências, esquema SQLite e migrações. Versão incrementada de 1.5.1+17 para 1.5.2+18. Nenhum banco pessoal foi aberto ou alterado. Modificações locais anteriores foram preservadas.

TransactionMetadata foi extraído para um modelo com reexportação: conteúdo e serialização da classe permanecem idênticos.

## Validação

- Análise Flutter: nenhum problema.
- Suíte Flutter completa: 156 testes aprovados, incluindo cálculos de cartão/fatura, migrações, retenção, sincronização, confirmação e telas.
- Parser Android: 8 testes JUnit aprovados.
- Serviços financeiros reais em Dart: 15 verificações aprovadas.
- Android nativo: 20 verificações aprovadas de captura, filtros, parsing, criptografia, replay, ack, reconexão, reinício, expiração, limite da fila e proteção em falha de decriptação.
- Ensaio Android + Flutter + SQLite + interface: notificação sintética de R$ 32,90 capturada pelo sistema; sugestão pendente com saldo R$ 100 e zero lançamentos; após tocar em Confirmar e registrar, exatamente um lançamento e saldo R$ 67,10; reinício mantém o resultado sem duplicar.
- Ensaio executado em emulador descartável com pacote isolado com.ma.expensy.nativeqa. Nenhum dado real foi usado. O alvo de teste não integra o APK de produção.
- Revisão visual da Home em 360, 412 e 1280 pixels, incluindo texto ampliado, e da revisão de sugestão no Android.

## Limitações restantes

Não houve aparelho físico conectado nem amostras reais anonimizadas dos bancos do usuário. Variantes sintéticas foram testadas; textos específicos de cada banco e restrições de bateria do aparelho ainda precisam de validação real. A revisão e os testes abrangem diversas telas, mas não equivalem à homologação manual de cada combinação do app.

A detecção exige acesso às notificações concedido no Android e o banco selecionado nas configurações do Nexo. Nenhuma política de segurança do Windows foi desativada.

## APK entregue

Nexo-1.5.2+18.apk compilado em release com alvo lib/main.dart. Identidade com.ma.expensy e certificado da versão anterior conferidos. Instalação sobre o APK anterior aceita pelo Android no emulador, sem desinstalação. Inicialização da versão final verificada. Certificado existente: Android Debug, preservado conforme configuração atual do projeto; nenhum keystore foi substituído.

SHA-256 do certificado: 54d668e0f56caf801de429377a7a3066dbe0ed74779f04bac1ba1d2a5b112096.

O APK está na pasta outputs desta tarefa, acompanhado de checksum, comprovação da assinatura, logs dos testes e capturas. Não foi instalado em aparelho pessoal.
