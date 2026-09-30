# Automação local, lembretes e segurança — Nexo 1.4

Atualização 1.5: diagnóstico por motivo, padrões/confiança, fila com memória após ack, aviso genérico opcional, associações locais e revisão com data editável documentados em [NEXO_EVOLUTION_2026.md](NEXO_EVOLUTION_2026.md). O texto abaixo permanece como histórico da implementação 1.4.

Pesquisa e implementação em 26/09/2026. Base: commit a5b6091, schema 22; pull sem divergência, pub get e analyze aprovados, 66 testes da base aprovados. Nenhuma integração bancária remota.

## Referências e decisões

- [NotificationListenerService, Android](https://developer.android.com/reference/android/service/notification/NotificationListenerService): serviço nativo autorizado pelo usuário em acesso a notificações. Declarado com `BIND_NOTIFICATION_LISTENER_SERVICE`; sem Accessibility, scraping, overlay ou abertura do app financeiro. O Android concede acesso amplo: a tela do Nexo explica isso, e o serviço filtra a seleção antes de ler o texto.
- [Restrições do Android 15](https://developer.android.com/about/versions/15/behavior-changes-all): conteúdo sensível/OTP pode ser ocultado. Não tentamos contornar a restrição.
- Identificadores conferidos nas páginas oficiais: [Nubank, com.nu.production](https://play.google.com/store/apps/details?id=com.nu.production), [Mercado Pago, com.mercadopago.wallet](https://play.google.com/store/apps/details?id=com.mercadopago.wallet), [Inter, br.com.intermedium](https://play.google.com/store/apps/details?id=br.com.intermedium), [PicPay, com.picpay](https://play.google.com/store/apps/details?id=com.picpay). Esses nomes facilitam a apresentação; não são uma garantia de que todo formato de notificação desses bancos será reconhecido. Não houve acesso a conta bancária real.
- [local_auth, Flutter](https://pub.dev/packages/local_auth) e [configuração Android](https://pub.dev/packages/local_auth_android): autenticação no dispositivo, biometria com alternativa de PIN/padrão/senha do Android. `FlutterFragmentActivity` e tema AppCompat necessários. Versões resolvidas: local_auth 3.0.2, local_auth_android 2.2.0.
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage): versão compatível resolvida 10.3.4; RSA OAEP + AES-GCM, chave protegida pelo Android Keystore. `resetOnError: false` evita remover a proteção silenciosamente em uma falha.
- [OWASP Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html): verificador PBKDF2-HMAC-SHA256, 600.000 iterações, salt aleatório de 32 bytes, resultado de 256 bits. Derivação fora da isolate de UI. PIN de seis dígitos nunca persistido em texto puro; comparação sem saída antecipada por caractere; cinco falhas impõem espera persistente de um minuto. O bloqueio é uma proteção de acesso do app, não criptografia integral do SQLite nem defesa contra aparelho comprometido/root.
- [Activity.setRecentsScreenshotEnabled](https://developer.android.com/reference/android/app/Activity#setRecentsScreenshotEnabled(boolean)) e [FLAG_SECURE](https://developer.android.com/security/fraud-prevention/activities): opções separadas para recentes (Android 13+) e bloqueio de captura. Screenshots continuam permitidos por padrão.
- [Notificações Android](https://developer.android.com/develop/ui/views/notifications/build-notification): lembretes discretos, com conteúdo genérico. Alarmes novos são inexatos e não exigem nova concessão de alarme exato; economia de bateria pode atrasá-los.

## Sugestões

Desligado por padrão, nenhum app pré-selecionado. A lista combina apps com launcher e identificadores que emitiram notificações depois do opt-in; para fontes não permitidas, somente a identidade do pacote é observada, nunca seu texto. Essa descoberta é limitada a 100 fontes. O usuário escolhe explicitamente cada app.

O parser Kotlin roda localmente mesmo sem Flutter aberto. Reconhece padrões explícitos de compra aprovada/débito/crédito, Pix enviado/recebido, transferência realizada/recebida/enviada, pagamento realizado, estorno e reembolso. Exige um único valor brasileiro positivo; nega notificações recusadas, agendadas, promocionais, com OTP/senha, saldos/limites/faturas ou múltiplos valores. Texto desconhecido não vira sugestão.

Somente ID, pacote, centavos, descrição curta, tipo sugerido, meio e horário são retidos. O texto original não é armazenado nem registrado em log. Transporte nativo usa fila AES-GCM/Keystore, limitada a 250 itens e sete dias. O Dart lê e confirma a remoção da fila somente após inserir no SQLite. Falha na fila aparece na configuração, sem exibir conteúdo sensível.

Fingerprint SHA-256 combina pacote, chave Android, horário aproximado do evento, valor, descrição normalizada e tipo. Reenvio com a mesma identidade não recria a sugestão. Após sete dias, sugestões antigas viram tombstones: descrição e valor são removidos, preservando apenas dados suficientes para impedir replay. Tombstones resolvidos/expirados são eliminados após 90 dias para limitar crescimento do banco. Como a entrada nativa já rejeita notificações com mais de sete dias, essa retenção continua muito maior que a janela possível de reprocessamento. Uma compra distinta com chave/horário diferente exige revisão; semelhança financeira não prova duplicação. A revisão procura lançamentos manuais/importados com mesma conta, valor e tipo em até três dias e pede escolha explícita. Importações posteriores usam a mesma infraestrutura de candidatos existente. Nenhuma união ou descarte de dinheiro é automático.

Caixa em Mais > Sugestões de lançamentos. Registrar abre revisão, não salva. A conta é sempre escolhida pela pessoa, sem inferir cartão apenas pelo nome do banco. Regras locais de categoria/subcategoria são aplicadas e editáveis. Pix entre contas próprias pode ser classificado como transferência neutra. Para estorno/reembolso, o usuário revisa a conta e o tipo; pagamento de fatura é deliberadamente rejeitado pelo parser para evitar despesa duplicada.

Confirmação e lançamento (ou dois lados da transferência) ocorrem na mesma transação SQLite, condicionada a sugestão pendente e não expirada. Não há salvamento automático ou ação financeira em background. Notificações de bancos mudam de texto; suporte é conservador e não universal.

## Lembretes

Configurações > Notificações: contas 3/1/0 dias antes; receitas; recorrentes; fechamento; fatura não quitada; orçamento; previsão negativa em sete dias. Novos avisos às 9h, sem valores/estabelecimentos. Recorrentes respeitam o lembrete e horário do cadastro, incluindo aviso antecipado já configurado. Confirmar/pagar/cancelar altera a projeção e cancela o job correspondente. A central substitui os jobs antigos de recorrentes/cartões, sem cancelar indiscriminadamente outros canais.

IDs estáveis e lista persistida de jobs evitam reagendar a mesma notificação em cada abertura. Orçamento tem limite persistente de um alerta por orçamento/dia. Previsão vem do cálculo financeiro existente; não inventa recebimentos ou compras. Janela de agendamento de até 31 dias, recalculada em abertura/mudanças; compromissos vencidos podem gerar um aviso no próximo dia. Não há worker que altere finanças ou leia bancos. Se o app permanecer fechado além da janela, reabra-o para atualizar o planejamento. Permissões, restrições de bateria, horário/fuso e mudanças fora do Nexo afetam entrega; não é um serviço bancário de cobrança.

## Bloqueio e recuperação

Ativação exige autenticação do aparelho antes de cadastrar/confirmar o PIN. Biometria é oferecida primeiro com alternativa de credencial Android; PIN Nexo também desbloqueia. Inicialização sempre bloqueia quando ativo. Background usa cronômetro monotônico para 0/30/60/300 segundos; a interface é encoberta enquanto fora de primeiro plano. Atalhos continuam atrás do bloqueio.

Esquecimento: autenticar pelo dispositivo e trocar o PIN em Segurança. Falha de leitura segura: permanece bloqueado; após autenticação Android explícita, pode redefinir apenas a chave `nexo_security_v1` da proteção. A recuperação não usa `deleteAll()` e não remove outros segredos que venham a compartilhar o secure storage no futuro. Nunca oferece apagar o banco como recuperação. Sem PIN Nexo e sem autenticação válida no aparelho, não há backdoor. Perda/reinstalação do aparelho requer backup financeiro explícito e nova configuração de proteção.

Segredos ficam fora do backup financeiro; backup automático Android e transferência automática são excluídos. Preferências de acesso às notificações, PIN, autolock, privacidade e lembretes são próprias do aparelho e não são concedidas por restauração do banco. Schema **22 → 23** apenas adiciona `notification_suggestions`, com instalação limpa, upgrade, backup e restore oficiais no DBHelper. Não reprocessa saldos antigos. ApplicationId e assinatura preservados.

## Melhorias extras implementadas por autonomia

- **Bloquear agora**: ação explícita para emprestar o celular sem aguardar timeout; usa a mesma proteção local, inspirada nos controles de autenticação Android documentados acima.
- **Widgets protegidos pelo bloqueio**: com bloqueio Nexo ativo, payloads dos widgets ocultam valores mesmo se o modo de ocultar valores da Home estiver desativado. Evita que uma superfície externa contorne a intenção de privacidade. Fundamentação: controles de exposição visual Android; testes inspecionam o payload.

Resultados de testes, revisão em Android e builds são registrados no NEXO_AUDIT.md ao concluir a rodada. Capturas, filas de teste, PINs e logs locais não são versionados.
