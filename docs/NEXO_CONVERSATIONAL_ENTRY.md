# Entrada por mensagem — proposta, ainda não conectada

Exemplo desejado: “barbearia, 80 reais, cartão Nubank”. Resultado proposto: despesa de R$ 80,00, data/hora local identificada, cartão existente sugerido e categoria sugerida. Revisão curta: Registrar / Corrigir / Cancelar. Nenhuma mensagem de exemplo desta conversa foi registrada no banco.

## Ordem recomendada

1. Entrada de texto dentro do Nexo, inteiramente local, gerando um rascunho para o formulário existente. Reutilizar regras editáveis de categoria e `parseMoney`; não criar categorias, contas ou parcelamentos por suposição.
2. Integração pessoal Telegram, opt-in, com identidade vinculada e fila persistente. É a primeira candidata técnica; não há bot criado, token configurado ou tráfego financeiro nesta rodada.
3. WhatsApp somente pela API oficial, após validar requisitos comerciais, credenciais, hospedagem e custos. Não automatizar WhatsApp Web nem usar sessão pessoal como servidor improvisado.
4. Conector autorizado para assistente no PC, com leitura de snapshot e operações estruturadas limitadas. Este chat atualmente não possui esse conector. Não permitir acesso irrestrito ao SQLite em uso.

## Regras necessárias antes de implementar conexão externa

- Vinculação autenticada ao usuário e ao dispositivo; aceitar apenas conversa privada e remetente vinculado. Token em armazenamento seguro/servidor, nunca embutido no APK, repositório ou logs.
- Transportador não altera saldo: entrega comando identificado à caixa de revisão do Nexo.
- ID estável do comando e constraint de unicidade; confirmação e lançamento na mesma transação SQLite; retry devolve o mesmo resultado. Mensagem repetida de transporte não duplica dinheiro. Compras semelhantes de origens diferentes geram alerta, não exclusão automática.
- Data do evento recebida do canal, convertida para timezone local. “Ontem”, data explícita, conta ambígua, valores múltiplos, parcelas, reembolso e transferência exigem interpretação específica ou correção. Nunca assumir que “80 em 3x” significa valor total ou valor da parcela.
- Estado visível: recebido, aguardando revisão, registrado ou falhou. A resposta “registrado” só pode ocorrer após commit no dispositivo, nunca ao receber webhook. Edição de mensagem já confirmada não altera lançamento silenciosamente.
- Se PC e celular ainda não sincronizam, escolher explicitamente o destino. Não gravar a mesma mensagem nos dois bancos independentes.
- Logs genéricos, retenção mínima, apagar rascunhos sensíveis conforme política. Mensagens financeiras passam pelo provedor escolhido; precisa de consentimento explícito antes de conectar dados reais.

## Disponibilidade e decisões externas

A [API oficial Telegram](https://core.telegram.org/bots/api#getting-updates), consultada em 13/10/2026, oferece polling ou webhook e limita a retenção de updates não recebidos a 24 horas. Portanto “PC desligado por vários dias e recebe tudo depois” não é garantido por um bot que só roda no PC. Precisaria de receptor continuamente disponível e armazenamento durável, com política de privacidade e custos definidos. `update_id` permite deduplicação de transporte; o offset só deve avançar após persistência segura.

Documentação WhatsApp tentada: [Meta — overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/overview). A consulta direta retornou HTTP 429 nesta rodada. Requisitos e preços não foram considerados confirmados; devem ser revistos antes de escolher essa alternativa.

Para ativar um bot serão necessários: escolha do canal e do dispositivo de destino, criação/vinculação do bot na conta do usuário, token guardado fora da conversa/repositório e decisão sobre onde manter o receptor. Qualquer serviço pago ou envio de dados reais exige autorização. A implementação local de usabilidade/relatório não depende dessas decisões.

## Testes de aceitação futuros

Valor brasileiro e internacional, múltiplos valores, data relativa/timezone, conta inexistente/ambígua, categoria editável, parcelas, crédito versus débito, estorno, transferência, confirmação repetida, timeout depois do commit, mensagens editadas, remetente não autorizado, app offline, reabertura, PIN, restore e mensagem já registrada por notificação/importação.
