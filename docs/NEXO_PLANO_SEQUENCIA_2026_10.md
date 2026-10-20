# Plano de sequência — sync, Claude e Pluggy (20/10/2026)

Cada etapa só começa quando a anterior passou no seu critério de saída. "Claude faz" = trabalho local, testado com dados fictícios. "Você faz" = ações que exigem sua conta, credencial ou decisão. Tudo dentro de planos gratuitos; nada é cobrado.

| # | Etapa | Claude faz | Você faz | Critério de saída |
|---|---|---|---|---|
| 1 | **Login** | Login por e-mail com código no app (Android e Windows), sessão no armazenamento seguro, sair/revogar; testes HTTP com dois usuários fictícios isolados | Passar URL e chave publicável; ativar e-mail com código no Supabase (eu indico onde); digitar os códigos recebidos em `danielmoulaz7@gmail.com` | Usuário A não lê nem grava nada do B pela internet |
| 2 | **Sync em teste** | Tela "Sincronizar dispositivos" (status, pendentes, conflitos, última sincronização); celular de teste ↔ Windows `--test-profile` com dados fictícios no Supabase real | Rodar o Windows de teste e conferir a tela no celular | Lançar, editar, apagar e ficar offline nos dois lados sem duplicar nem perder dinheiro |
| 3 | **Ativação real** | Tela de consentimento mostrando o que será enviado; backup obrigatório antes; celular como origem, PC entra vazio | **Decidir e confirmar** o primeiro envio | Celular e PC iguais; backup recuperável guardado |
| 4 | **Claude consulta** | Servidor MCP (Edge Function) com login, só leitura: resumo, contas, lançamentos, gastos por categoria, contas a vencer, investimentos. Primeiro com dados fictícios | Adicionar o conector no Claude Pro (Customize → Connectors) | Perguntas como "quanto gastei com delivery este mês?" batem com o app |
| 5 | **Claude cadastra** | Pedidos idempotentes ("adiciona R$ 32,90 do iFood") que o app valida pelas regras reais; status "pendente → lançado"; confirmação para editar/excluir; auditoria | Testar frases reais | Nada é dito "lançado" antes do app gravar; repetir o pedido não duplica |
| 6 | **Pluggy Sandbox** | Função no servidor com webhook, normalização, ID do Pluggy como chave anti-duplicata, entrada na caixa de revisão | Criar conta no painel Pluggy; cadastrar credenciais de **teste** como segredo do Supabase | Bancos fictícios chegam como sugestões, sem criar dinheiro sozinhos |
| 7 | **Meu Pluggy real** | Vincular `itemId`s, conciliar com notificações e lançamentos manuais, avisar expiração (1 ano) e falhas | Conectar seus bancos no Meu Pluggy (até 5); trocar para credenciais reais | Movimentações reais revisáveis, duplicatas sinalizadas |
| 8 | **ChatGPT** | Reaproveitar o mesmo servidor MCP | Confirmar se seu plano permite ferramentas de escrita | Consulta funcionando; cadastro só se a plataforma permitir |

## Pode andar em paralelo

- Etapa 4 com dados fictícios pode ser preparada durante as etapas 1–3; só passa a ler seus dados depois da 3.
- Etapa 6 (Sandbox) não depende do sync e pode ser feita a qualquer momento.

## Pontos de atenção

- **O Supabase Free pausa projetos após ~1 semana sem uso.** Com sync ativo isso não deve acontecer; se pausar, o app continua funcionando offline e você reativa no painel.
- O e-mail padrão do Supabase entrega códigos só para membros do projeto e com limite baixo por hora — suficiente para você, não para outros usuários.
- Pluggy pessoal: atualização automática a cada 24h, sem atualização manual; consentimento vence em 1 ano e precisa de reconexão.
- Segredos (senha do banco, `service_role`, `sb_secret_…`, `clientSecret` do Pluggy) nunca vão para o chat, o código ou o app: você os cadastra direto no painel.
- Cada etapa termina com testes, documentação e commits; nenhuma etapa envia seus dados sem a decisão da etapa 3.

## Andamento (20/10/2026, fim do dia)

| # | Situação |
|---|---|
| 1 Login | Código pronto e testado (8 + 2 testes); tela Mais → Sincronizar dispositivos; teste do servidor com dados fictícios. **Bloqueado no envio de e-mail**: o Supabase gratuito só permite editar o e-mail com SMTP próprio e limita a ~2 envios/hora. Contorno implementado: colar o link do e-mail sem abrir. Próximo passo do usuário: configurar SMTP (Resend recomendado) ou aguardar o limite e testar no Windows `--test-profile` |
| 2–3 Sync | Etapa 2 **validada no Windows com dois perfis de teste**: sincronização automática (conta e despesa foram de um perfil ao outro sozinhas, saldos idênticos). Tela de status/conflitos pronta. Falta: conflito/offline pela interface, celular, e a etapa 3 (dados reais, decisão do usuário) |
| 4 Claude consulta | Servidor MCP pronto e testado (paridade exata com o app), não publicado; depende das etapas 1–3 |
| 6 Pluggy Sandbox | Cliente e normalizador prontos e testados; faltam credenciais do usuário, tabela de sugestões, webhook e integração na caixa de revisão |
| Extra | Exclusão de conta nunca apaga histórico em cascata; fixture de paridade determinístico |

Builds de teste com servidor: `flutter build windows --release --target lib/main.dart --dart-define-from-file=tool/nexo_sync.local.json` (arquivo local, ignorado pelo Git). Sem esse arquivo o app mostra "sem servidor configurado".
