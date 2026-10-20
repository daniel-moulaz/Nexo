# Integrações: Claude (MCP), Pluggy, ChatGPT e fechamento semanal — plano (20/10/2026)

Documento de decisão, **não de funcionalidade pronta**. Nada aqui está implementado além da fronteira de domínio descrita em [NEXO_SYNC_DOMAIN_2026_10_20.md](NEXO_SYNC_DOMAIN_2026_10_20.md).

## Fatos verificados em 20/10/2026

| Plataforma | Fato relevante | Fonte |
|---|---|---|
| Claude Pro | Conectores personalizados MCP remotos disponíveis para Free (1 conector), Pro, Max, Team, Enterprise. Autenticação OAuth, "sem login" ou cabeçalhos fixos. **O servidor precisa ser acessível pela internet pública a partir da nuvem da Anthropic**; localhost/VPN não funcionam | [Claude Help Center](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp) |
| Meu Pluggy | Uso pessoal gratuito, **até 5 conexões**, sem uso comercial. `clientId`+`clientSecret` → API key (`POST /auth`, cabeçalho `X-API-KEY`). **Atualização automática a cada 24h; atualização manual não é possível.** Webhooks existem. `GET /v2/items` indisponível: guardar `itemId`. Consentimento dura **1 ano**; depois, `USER_AUTHORIZATION_EXPIRED` e reconexão manual (o `itemId` pode mudar). Sandbox para testes; Meu Pluggy sempre devolve dados reais. A página não confirma cartões/investimentos para essa modalidade | [Pluggy — Meu Pluggy](https://docs.pluggy.ai/pt/docs/guides/meu-pluggy-personal-use) |
| ChatGPT | Conectores MCP exigem "Developer Mode" e servidor público HTTPS. Escrita para planos individuais (Plus) é descrita de forma **contraditória** pelas fontes disponíveis | [Speakeasy](https://www.speakeasy.com/docs/mcp/build/integrate/clients/using-chatgpt-developer-mode-with-gram), [Peliqan](https://peliqan.io/blog/chatgpt-mcp/) — revalidar na central da OpenAI antes de implementar |

## Consequência arquitetural

Claude e ChatGPT conversam com um servidor na nuvem, nunca com o celular. Pluggy exige um segredo que **não pode** ficar no APK/EXE. Logo, as três integrações dependem do mesmo pré-requisito: **um backend com cópia autorizada dos dados**, ou seja, a sincronização. Por isso a ordem é sync → integrações, e por isso o lote atual tornou cada gravação uma operação atômica e reproduzível.

Decisão-chave para não criar "um segundo sistema financeiro": **as regras contábeis continuam somente no código Dart do app.** O servidor guarda operações e uma projeção de leitura; não reimplementa saldo, fatura, transferência ou parcelamento.

## Nexo MCP (Claude primeiro)

- Hospedagem candidata: Supabase Edge Functions (já existe o projeto `nexo-sync`, plano Free). Transporte MCP remoto com OAuth; avaliar no momento da implementação se o Supabase Auth pode atuar como servidor OAuth para o conector ou se é necessário um fluxo próprio mínimo.
- **Leitura** (`resumo`, `contas`, `lançamentos`, `gastos por categoria`, `orçamentos`, `contas a vencer`, `recorrentes`, `investimentos`): consultas à projeção sincronizada, com números calculados deterministicamente pelas mesmas regras exportadas pelo app (o relatório 3/7 dias já existe localmente).
- **Escrita** ("adiciona R$ 32,90 do iFood hoje"): o MCP cria uma **intenção** idempotente (ID estável, conta/categoria resolvidas ou pergunta de esclarecimento). Um aparelho do usuário a recebe pelo sync, valida pelas regras reais (`AppProvider.addTransaction`) e grava; a operação resultante volta ao servidor. A ferramenta responde "registrado como pendente" e oferece `consultar_status`; só diz "lançado" após o recibo. É mais lento quando nenhum aparelho está online, mas é honesto e evita duplicar a lógica financeira. Alternativa futura: o app Windows como "processador" quando ligado.
- Segurança: escopos leitura/escrita separados, revogação, auditoria por operação, confirmação para exclusões, minimização (nunca mandar o acervo inteiro ao modelo).

## Pluggy (Open Finance pessoal)

- Edge Function guarda `clientSecret` como segredo do Supabase (o usuário o cadastra; não passa pelo chat nem pelo código), recebe webhooks e lê contas/lançamentos.
- Importados entram na **mesma caixa de revisão** das notificações bancárias, chaveados pelo ID do lançamento Pluggy (idempotência), com origem, status pendente/postado e atualização quando o banco corrige. Nunca criam ou apagam dinheiro sozinhos; possível duplicata com lançamento manual/notificação é sinalizada, não mesclada.
- Camada de provedor desacoplada (`FinancialDataProvider`) para trocar Pluggy por outro agregador.
- Exige antes: sync ativo, consentimento explícito de envio de dados reais, credenciais criadas pelo usuário.

## ChatGPT

Mesmo servidor MCP. Antes de implementar, testar em conta própria se o plano atual permite ferramentas de escrita. Se não permitir, leitura via MCP e escrita só pelo Claude/app. A rota ChatGPT → Google Sheets → n8n → API fica como último recurso: adiciona dependências e superfícies de vazamento sem ganho real.

## Fechamento semanal (domingo 22h)

Pode ser feito **antes** do backend: lembrete local agendado no Android para domingo 22h abrindo a Revisão financeira de 7 dias (que já existe), com comparação à semana anterior, contas a vencer e variações. Lógica determinística, sem IA, sem rede. Candidato a lote curto de produto.

## Ordem proposta

1. Sync S2 (local/sintético): protocolo v2, motor, conflitos, bootstrap — ver documento de domínio.
2. Sync S3 (precisa do usuário): migration v2 no `nexo-sync`, login, testes HTTP com dois usuários sintéticos.
3. Ativação consciente do sync com dados reais (decisão do usuário).
4. Nexo MCP somente leitura → escrita por intenções.
5. Pluggy em Sandbox → Meu Pluggy real.
6. ChatGPT conforme capacidade confirmada.

Em paralelo, sem dependência: fechamento semanal local.
