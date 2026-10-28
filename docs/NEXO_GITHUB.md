# Repositório e histórico do Nexo

## Organização

- Repositório próprio: `daniel-moulaz/Nexo`, público e independente.
- Branch de apresentação: `main` no novo repositório.
- Base de código inicial sob licença MIT; o crédito exigido está em `LICENSE`. Histórico reescrito em 28/10/2026 para começar no Nexo (`docs/NEXO_PROJETO_INDEPENDENTE_2026_10.md`).

A publicação inicial reúne o histórico já commitado da versão 1.5.4 e sua apresentação. Não usa squash, datas artificiais, force push nem reescrita da autoria. Mudanças locais que ainda aguardam revisão permanecem fora da publicação; os relatórios de builds de 13/10 descrevem o workspace daquela rodada, como indicado nos próprios documentos.

## Validação da publicação — 15/10/2026

Uma cópia limpa foi extraída do commit `3be8b59` com `git archive`, sem os arquivos locais pendentes. Dependências resolvidas, `flutter analyze --no-pub` sem ocorrências e **185 testes aprovados** com `flutter test --no-pub --concurrency=1`. O ambiente Windows sem Modo de Desenvolvedor usou o script existente `tool/prepare_windows_plugins.ps1` para preparar os links dos plugins. Links locais e imagens do README foram conferidos. As alterações posteriores a esse teste são apenas documentação.

Esse resultado descreve o código publicado. A suíte de 196 testes da rodada de 13/10 incluía testes de alterações locais ainda pendentes e não deve ser confundida com esta cópia limpa.

## Contribuições no perfil

O GitHub reconheceu a autoria de commits anteriores como `daniel-moulaz`. Commits precisam usar um e-mail associado à conta e estar na branch padrão de um repositório independente para serem elegíveis ao gráfico. O processamento não é imediato e as contribuições seguem as datas reais dos commits.

Referência: [solucionar contribuições ausentes](https://docs.github.com/en/account-and-profile/how-tos/contribution-settings/troubleshooting-missing-contributions).

## Próximas alterações

Trabalhar em branches de funcionalidade, testar e integrar na `main` por pull request. Usar mensagens que descrevam mudanças reais, como `fix(backup): reject incomplete restores` ou `feat(home): add cash timeline`. Preservar a sequência de commits revisados quando ela for útil para entender a evolução.

Desde 28/10/2026 o único remoto é `origin`, apontando para este repositório.

## Arquivos publicados

README em português, duas capturas sintéticas da Home, código commitado, testes e documentação. `android/local.properties` deixou de ser rastreado na versão atual, mas continua no computador para compilar. Histórico anterior público não foi reescrito.

Banco pessoal, backups, exportações, logs, APKs, keystores e credenciais não devem entrar em novos commits. O `.gitignore` protege esses padrões. A licença original permanece intacta.

## Atualização — 24/10/2026

- O trabalho de 20 a 23/10 (1.6.8 a 1.12.2) foi integrado ao `main` pelo [pull request #1](https://github.com/daniel-moulaz/Nexo/pull/1), sem conflitos.
- A pedido do dono, antes do merge as mensagens dos 93 commits do ramo `codex/nexo-investments` foram reescritas para remover a linha de coautoria automática ("Co-Authored-By"); conteúdo, autor e datas foram conferidos commit a commit e ficaram iguais. Foi o único envio forçado, feito com `--force-with-lease`, só nesse ramo; o `main` não foi reescrito. As referências a commits nos documentos foram atualizadas.
- Daqui em diante: trabalhar em ramo, abrir pull request para o `main`, sem linhas de coautoria automática.
