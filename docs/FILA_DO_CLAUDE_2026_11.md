# Fila do Claude com o app fechado (1.17.0, 13/11/2026)

## O problema

Os pedidos do Claude ficavam "pendente: aguardando o app abrir" por minutos ou horas. O Nexo é local-first: o servidor guarda o pedido, mas quem grava é o app, com as regras do app (saldo, fatura, consumo). Até a 1.16.0 só gravava o app aberto no celular ou o PC na bandeja.

## O que foi decidido

Três caminhos, do mais rápido para o mais garantido:

| Caminho | Quando grava | Custo | Precisa de |
|---|---|---|---|
| Aviso do servidor (FCM, mensagem silenciosa de alta prioridade) | Em segundos, com o app fechado | Grátis (Firebase Cloud Messaging não cobra) | Projeto Firebase do dono e o segredo `FCM_SERVICE_ACCOUNT` |
| Checagem periódica (WorkManager) | A cada 15 min no máximo, com o app fechado | Uma passada de ~8 s por checagem | Nada: vem ligada |
| PC na bandeja | Em até 20 s | Processo aberto no PC | "Iniciar com o Windows", ligado sozinho uma vez na 1.17.0 |

Não usei serviço em primeiro plano: ele exige notificação fixa e gasta bateria o dia todo para ganhar o mesmo que o aviso do servidor.

### Como funciona no Android

- Um único worker (`NexoBackground.kt`) é disparado de três jeitos: pelo agendamento de 15 minutos, pelo aviso do servidor e pelo app.
- Só uma parte do app mexe no banco por vez. Com o app vivo, aberto ou atrás de outros, o worker pede a ele uma passada de sincronização. Sem o app, sobe um motor do Flutter sem tela (`nexoBackgroundQueue`), sincroniza, aplica os pedidos e envia o resultado. Um app que abre nesse meio-tempo espera o motor terminar, em até 90 s, antes de abrir o banco.
- Os pedidos já aplicados são relidos do disco a cada passada (`prefs.reload()`). Por isso, um pedido gravado sem tela e não confirmado ao servidor nunca é gravado de novo.
- A notificação "Feito pelo Claude" não traz valores e pode ser desligada.

### Sem duplicar e na ordem

O servidor entrega um pedido por vez por acervo, do mais antigo para o mais novo (`nexo_mcp_claim`, com trava). Celular e PC não pegam o mesmo pedido.

Na 1.17.0, um aparelho também não pega um pedido que não sabe gravar:

- **Versão mínima:** um pedido em dólar exige a 1.16.0 (`min_build` 58).
- **Tipo de pedido:** um tipo que o aparelho nunca informou fica para outro aparelho.

Se o mais antigo da fila não serve para aquele aparelho, ele espera em vez de pular. A ordem é mantida, e um app velho não grava errado.

## Medido no aparelho

POCO X7 Pro (Xiaomi, HyperOS, Android 15), build de teste `com.ma.expensy.teste`, acervo fictício, economia de bateria no padrão (sem liberação).

| Teste | Resultado |
|---|---|
| Pedido do Claude com o app fechado, sem aviso do servidor | Pedido às 14:18:31; gravado às 14:27:43, **9 min 12 s**, pela checagem periódica |
| Duração da passada sem tela | **~8 s**, do processo subir ao pedido gravado |
| Arrastar o app para fora dos recentes | O processo morre, o agendamento **continua** (`stopped=false`) e a checagem seguinte rodou |
| Agendamento após a passada | A próxima checagem entrou para 15 min depois |
| Aviso instantâneo (FCM) | **Não medido**: precisa do projeto Firebase do dono. O código está pronto e testado com o envio simulado |

Limites conhecidos:

- **Pior caso sem aviso:** 15 minutos. A economia de bateria pode adiar a checagem. Com o celular parado e com tela apagada por muito tempo (Doze), o Android junta as checagens em janelas que podem passar de 15 minutos. Abrir o app grava na hora.
- **Xiaomi:** "Início automático" desligado e bateria "Restrita" podem segurar a checagem e o aviso. A tela Fila do Claude mostra o estado da bateria e tem botões para as duas telas do sistema.
- **"Forçar parada":** nas configurações do Android, isso cancela tudo até o app ser aberto de novo. Isso é do Android, não do Nexo.

## Para ligar o aviso instantâneo (opcional, grátis)

1. Em console.firebase.google.com, crie um projeto (plano Spark, sem cartão) e adicione um app Android com o pacote `com.ma.expensy`.
2. Copie `appId`, `apiKey`, `projectId` e `senderId` (número do projeto) para `android/firebase.local.properties`. O arquivo fica fora do Git:
   ```
   appId=1:000000000000:android:0000000000000000
   apiKey=AIza...
   projectId=nome-do-projeto
   senderId=000000000000
   ```
3. Em Configurações do projeto › Contas de serviço, gere uma chave privada (JSON) e guarde-a como segredo da função:
   `npx -y supabase@2.122.0 secrets set FCM_SERVICE_ACCOUNT="$(Get-Content chave.json -Raw)" --project-ref aruzkellbwqrsfidhaum`.
   Depois apague o arquivo JSON do computador.
4. Recompile o APK, instale e abra o app uma vez. Ele registra o aparelho, e a tela Fila do Claude passa a dizer "acorda com o aviso do servidor".

Sem esses passos, tudo funciona com a checagem de 15 minutos.

## Onde ver

- **App:** Mais › Sincronizar dispositivos › Claude (IA) › Fila do Claude. Mostra os pedidos esperando, a última conferência de cada aparelho, os ajustes de bateria e um botão "Conferir agora".
- **Conector:** `get_request_status` mostra `last_queue_check` e `wakes_on_request` por aparelho, e diz quando um pedido espera uma versão mais nova.
