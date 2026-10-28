# Auditoria do Nexo (28/10/2026, código da 1.12.10)

Leitura crítica do produto e do código, feita depois de dois dias de trabalho no
repositório inteiro (redesenho visual, remoção de sobreposições, desvinculação do
Expensy). Separa fatos medidos de opinião; cada ponto fraco aponta para o item do
plano em `docs/PLANO_EVOLUCAO_2026_11.md`.

## Números

| Área | Arquivos | Linhas |
|---|---|---|
| `lib/screens` | 38 | 22.186 |
| `lib/services` | 51 | 5.734 |
| `lib/sync` | 14 | 4.364 |
| `lib/widgets` | 11 | 3.189 |
| `lib/providers` (um arquivo) | 1 | 2.103 |
| `lib/database` | 2 | 1.640 |
| `lib/models` | 2 | 1.268 |
| `test` | 63 | 12.367 |
| `supabase/functions` (Deno) | 12 | 3.004 |
| `supabase/migrations` | 12 | 1.787 |

Outros: 30 tabelas SQLite (schema 26); 44 dependências no `pubspec.yaml`; 434 testes
Flutter, mais 48 de SQL, 37 do MCP e 22 do Pluggy (Node). Maiores arquivos:
`app_provider.dart` (2.103 linhas), `finance_home_screen.dart` (1.949), `db_helper.dart`
(1.567), `investments_screen.dart` (1.433), `recurring_screen.dart` (1.287).

## Arquitetura: o que está certo

- **Fronteira de escrita única.** Toda gravação passa por `ledgerTransaction` /
  `DBHelper.operation`, e `test/ledger_capture_test.dart` falha se um caminho escapar. É a
  base da sincronização e do "nada cria dinheiro sozinho".
- **Regras financeiras isoladas** (`finance_rules.dart`, `card_commitment.dart`,
  `spendable.dart`, `cash_forecast.dart`, `envelopes.dart`): calculáveis sem UI e cobertas
  por teste. Transferência, reserva e aporte não são consumo; pendente não debita; fatura
  paga não duplica.
- **Sincronização com protocolo próprio** (diário de operações, cursor, conflitos
  revisáveis, barreira de restauração) e servidor de referência em SQLite para testes.
- **Integrações como "pedido que o app executa"**: o MCP não escreve no banco; manda
  comandos que passam pelas mesmas regras (`AssistantCommands`), com paridade testada.
- **Sistema visual próprio** (`nexo_ui.dart`): cartão plano, pills, seletor de mês, chip
  row, progresso, donut, calendário de gastos. Galerias renderizam cada tela em claro/escuro,
  no celular e a 1280 px.

## Arquitetura: o que pesa

1. **`AppProvider` é um deus-objeto** (2.103 linhas): estado, carregamento, regras de
   negócio, notificações, widgets Android e formatação no mesmo `ChangeNotifier`. Todo
   `notifyListeners()` redesenha tudo que escuta. Plano: P2-1 (fatiar por domínio
   mantendo a API; nenhuma mudança de comportamento).
2. **Telas gigantes com lógica dentro** (`finance_home_screen.dart`, `investments_screen.dart`,
   `recurring_screen.dart`): cálculo, estado local e layout no mesmo `build`. O Hoje já
   delega a serviços; os outros não. Plano: P2-2.
3. **94 `catch (_)` silenciosos** em `lib/`. Muitos são defensivos legítimos (plugin
   ausente no Windows), mas vários engolem falhas de I/O e rede sem registro. Plano: P1-6
   (registro local de falhas com contagem, visível em Ajuda › Diagnóstico).
4. **Internacionalização pela metade**: 351 usos de `l10n` contra 358 `Text('…')` fixos em
   português nas telas. O app é PT-BR na prática e carrega 12 idiomas gerados que ninguém
   usa. Decisão do dono: ou consolidar em PT-BR (remover `l10n`, ganhar simplicidade) ou
   completar a tradução. Recomendo consolidar. Plano: P2-3.
5. **Finais de linha mistos** (CRLF e LF no mesmo arquivo) em dezenas de arquivos; o
   `git status` vive sujo com `lib/l10n/*`. Plano: P0-2 (`.gitattributes` com `text=auto`
   e uma normalização única em commit próprio).
6. **Sete serviços de notificação** (`notification_service`, `budget_notification_service`,
   `daily_reminder_service`, `lended_notification_service`, `loan_reminder_service`,
   `credit_reminder_service`, `financial_reminders`) com inicialização e canal cada um.
   `financial_reminders.dart` já é o planejador central; os outros são sobras. Plano: P2-4.
7. **Dois modelos de "sugestão"** (regras de importação, contas lembradas) e nenhum
   aprendizado de categoria pelo histórico. Plano: P1-3.
8. **Testes fortes nas regras, fracos na interface sob estresse**: só Recorrentes, detalhe
   e empréstimos são verificados com texto 1,5×; o overflow da 1.12.7 escapou por isso.
   Plano: P0-1 (as cinco abas e as telas de Mais com texto grande em teste).

## Produto: o que funciona e o que falta

**Funciona e é diferencial:** local-first com sincronização real; Open Finance de quatro
bancos; conferência de saldo com ajuste neutro; fatura oficial ao lado da do Nexo;
envelopes por % da renda; "quanto posso gastar" por dia; conector para o Claude; Windows
nativo com atalhos; biometria automática.

**Falta (pela auditoria, não só pela pesquisa):**
- Um lugar para **achar qualquer coisa** (tela, ação, lançamento) sem navegar: P1-1.
- **Lançar em uma linha**: hoje são seis toques para uma despesa comum: P1-2.
- **Renda em dia variável**: o app assume o mês civil; quem recebe no dia 7 ou 12 quer
  ver "até a próxima renda": P1-5.
- **Provisão de gastos irregulares** (IPVA, seguro, matrícula): P1-4.
- **Patrimônio ao longo do tempo** e proventos: P2-6.
- **Agenda em mês**: P2-5.
- Estados vazios ainda genéricos em Contas, Categorias e Desejos (texto só): P2-7.
- Onboarding (1.151 linhas) antigo, anterior ao Hoje atual e aos envelopes: P2-8.

## Segurança e privacidade

- PIN com PBKDF/salt (`PinVerifier`), biometria, tela borrada ao sair, bloqueio de
  captura; segredos fora do repositório; servidor sem criptografia de ponta a ponta
  (documentado). Nada crítico encontrado. Melhoria: o relatório de erros local (P1-6) não
  pode registrar valores nem descrições.

## Acessibilidade e desempenho

- 72 usos de `Semantics`/`tooltip`/`semanticLabel` em 38 telas: os ícones de ação têm
  tooltip, mas pills e números grandes não têm rótulo semântico. Plano: P1-7.
- Texto 1,5× quebra o layout em alguns cartões (corrigido no Recorrentes; os outros não
  são verificados). Plano: P0-1.
- Abertura: o banco é lido e todos os recorrentes projetados antes do primeiro frame no
  Hoje; aceitável com centenas de lançamentos, mas o provider recarrega listas inteiras a
  cada gravação. Plano: P2-1.

## O que esta auditoria recomenda remover ou consolidar

- Os 12 idiomas gerados (ver 4).
- Os serviços de notificação sobressalentes (ver 6).
- `onboarding_screen.dart` reescrito em cima do Hoje atual (P2-8), não mantido ao lado.
