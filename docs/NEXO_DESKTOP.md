# Nexo Windows nativo — 1.5.1+17

> **Atualização 24/10/2026:** o Windows está em uso diário na mesma versão do Android (1.12.2), sincronizado com o celular. A homologação manual completa continua pendente.

30/09/2026 · branch `feat/nexo-windows-native`, baseada em `d0ed659`.

O runner Windows x64 funciona com SQLite local e plugins nativos. A contabilidade, o restore e o PIN foram exercitados em processos Release isolados. **A homologação manual completa ainda está pendente**, principalmente formulários, seletores de arquivos e janela. Evidências e limites: [NEXO_WINDOWS_VALIDATION.md](NEXO_WINDOWS_VALIDATION.md).

## Executar e distribuir

Extrair `build/distribution/Nexo-1.5.1+17-windows-x64.zip` e abrir `Nexo.exe`. Distribuir **toda a pasta**, incluindo DLLs e `data/`, nunca somente o EXE. `tool/package_windows.ps1` valida componentes, rejeita bancos/credenciais/logs e gera o ZIP e seu SHA-256. O bundle inclui runtime C++ local. Instalação limpa de Windows x64 ainda precisa ser homologada.

Ensaio isolado: `Nexo.exe --test-profile`. A janela e o banner mostram TESTE LOCAL. O banco fica em `%TEMP%/NexoWindowsQA/expensy.db`; preferências usam prefixo separado e PIN usa chave própria. Para outra base sintética, definir TEMP/TMP somente no processo que inicia o app. Nunca apontar para dados reais. O perfil de QA não copia a base normal. Um mutex por perfil/sessão Windows impede que a segunda interface inicialize o banco.

Não há assinatura Windows nem certificado adquirido. MSIX fica para depois da homologação funcional e definição da identidade de assinatura. Nenhuma política de segurança foi desativada.

## Persistência e segurança

- `DatabasePlatform` configura SQLite FFI no Windows e mantém sqflite no Android.
- Banco normal: **`%LOCALAPPDATA%/Nexo/expensy.db`**. Não fica ao lado do EXE nem em arquivo compartilhado entre dispositivos.
- Schema **23 → 23**. Upgrade 22→23 e restore de backup antigo têm testes com SQLite real.
- DBHelper, AppProvider, FinanceRules e metadados são compartilhados: pendentes não debitam saldo; transferências/reservas e pagamentos de fatura não contam como novo consumo.
- CSV/XLSX e backup JSON usam seletor nativo. No Windows, o picker retorna o caminho; `FileOutput` grava em temporário irmão e substitui o destino somente após concluir. Falha preserva o arquivo anterior.
- Restore valida estrutura, versão e IDs duplicados antes de substituir tabelas. Configurações são interpretadas antes da substituição. A importação SQLite é transacional.
- PIN usa PBKDF2 e `flutter_secure_storage` Windows. A gravação/leitura entre processos, PIN errado/correto, cooldown e desativação passaram no ensaio nativo. O fluxo completo por botões ainda está pendente.
- PIN protege a interface, **não criptografa SQLite ou backups**. Windows Hello, recuperação de PIN e bloqueio de captura Windows não estão habilitados.
- Falha de inicialização mostra orientação de pasta/permissão e permite tentar novamente, sem apagar/recriar banco.

## Recursos por plataforma

`PlatformCapabilities` concentra os recursos Android-only: listener bancário, apps autorizados, permissão de notificações, sugestões bancárias, widgets, intents, haptics, notificações agendadas e proteção de screenshots. No Windows essas APIs não são chamadas; as telas indicam “Disponível no Android”. Agenda e compromissos visuais continuam disponíveis. Não existe listener Windows fictício.

A fonte Windows é Segoe UI local. O registro financeiro não depende de rede; cotações opcionais continuam separadas. Nenhum backend ou sincronização foi ativado.

## Experiência desktop

- Sidebar a partir de 900 px: Resumo, Transações, Contas e cartões, Recorrentes, Orçamentos e objetivos, Análises, Agenda, Importar, Configurações e Mais.
- Páginas iniciadas sob demanda; busca/filtros preservados durante a sessão, não após restart.
- Home em duas colunas, largura máxima de 1440 px, resumo/previsão, donut, receitas × despesas de seis meses e orçamentos. Revisão sintética em 1920 px mostrou uso equilibrado do espaço; não houve redesenho nesta homologação.
- Tabela com 20 linhas por página, ordenação, busca, filtros, tooltips, scroll horizontal e menu de ações. Repetir abre formulário pré-preenchido sem salvar automaticamente. Transferências e parcelamentos não oferecem repetição simplificada.
- Importação CSV, TXT tabular e OFX com preview/revisão/deduplicação; limite de 10 MB/10 mil linhas. XLSX somente para exportação. Sem drag and drop ou exclusão em massa.
- Janela inicial 1280×720, mínimo 960×640 com escala DPI. Tamanho e posição não são persistidos.

| Atalho | Efeito |
|---|---|
| Ctrl+N | Novo lançamento com shell ativo e desbloqueado |
| Ctrl+F | Transações e foco na busca |
| Ctrl+Enter | Salvar formulário com validação |
| Esc | Cancelar formulário sem salvar; testado somente por widget test |
| Tab / Shift+Tab | Navegar controles |
| Enter | Confirmar diálogo de PIN |

Atalhos globais respeitam bloqueio e outras rotas. O formulário recebe foco inicial também ao editar.

## Compilar

Ambiente: Flutter 3.47.5/Dart 3.13.4, Visual Studio Build Tools 2022 17.14.41, Desktop C++, ATL e SDK 10.0.26100.0. ATL é necessário para a versão instalada de secure storage.

```powershell
flutter pub get
# Somente se symlinks não estiverem disponíveis:
./tool/prepare_windows_plugins.ps1
flutter analyze
flutter test --concurrency=1
flutter build windows --release --target lib/main.dart
./tool/package_windows.ps1
flutter build apk --release
```

O script de plugins usa junctions em `windows/flutter/ephemeral`, sem alterar SDK/Developer Mode. Android conserva `com.ma.expensy`, assinatura e banco.

O ensaio nativo `tool/windows_native_check.dart` é um **entrypoint exclusivo de teste**. Nunca distribuí-lo: após usá-lo, reconstruir explicitamente `--target lib/main.dart` antes de empacotar. Instruções e limites na validação.

## Referências e próximos passos

[Flutter Windows](https://docs.flutter.dev/platform-integration/windows/building), [Microsoft MSIX](https://learn.microsoft.com/en-us/windows/msix/package/sign-msix-package-guide), [SQLite FFI](https://pub.dev/packages/sqflite_common_ffi), [secure storage Windows](https://pub.dev/packages/flutter_secure_storage_windows/versions/4.1.0).

Concluir a matriz manual, depois validar instalação limpa, desempenho com bases grandes, acessibilidade e eventual MSIX assinado. Sync permanece separado em [NEXO_SYNC_ARCHITECTURE.md](NEXO_SYNC_ARCHITECTURE.md); não compartilhar banco aberto nem subir dados reais.
