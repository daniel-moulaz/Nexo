<div align="center">

# Nexo

### Seu dinheiro, com clareza.

Controle financeiro pessoal para entender o passado, acompanhar o presente e organizar os próximos compromissos.

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D4)
![Local first](https://img.shields.io/badge/Dados-locais-00695C)
[![MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-blue)](LICENSE)

[Conheça o app](#um-painel-para-o-dia-a-dia) · [Telas](#telas) · [Executar](#executar-o-projeto) · [Documentação](#documentação)

</div>

## Um painel para o dia a dia

O Nexo reúne saldo, gastos, cartões, dívidas e previsão de caixa em uma experiência compartilhada entre Android e Windows. O foco é reduzir trabalho manual sem perder a precisão dos registros.

- **Home analítica:** saldo em contas, cartões em aberto, entradas e gastos do mês, comparação mensal e maior categoria.
- **Visão do futuro:** projeção de 7, 30 ou 90 dias, próximos vencimentos e alertas de compromissos atrasados.
- **Organização financeira:** contas, transferências, cartões e faturas, recorrentes, parcelamentos, empréstimos, orçamentos e objetivos.
- **Análises acessíveis:** despesas por categoria, filtros, detalhes dos lançamentos e fechamento mensal.
- **Menos digitação:** repetição de lançamentos e sugestões revisáveis a partir de notificações bancárias autorizadas no Android.
- **Seus arquivos:** importação com revisão, exportação CSV/XLSX e backup/restauração.
- **Proteção local:** PIN, ocultação de valores e recursos de segurança conforme a plataforma.

## Telas

As imagens abaixo foram geradas com **dados fictícios de teste**. Não representam finanças pessoais reais.

<p align="center">
  <img src="docs/images/nexo-home-mobile.png" width="320" alt="Home do Nexo com saldo, resumo mensal e atalhos usando dados fictícios" />
</p>

<p align="center">
  <img src="docs/images/nexo-home-desktop.png" width="1100" alt="Painel do Nexo com previsão de caixa e categorias usando dados fictícios" />
</p>

## Precisão antes de automação

- Despesas pendentes não reduzem o saldo atual.
- Transferências e reservas não viram consumo.
- Compras no cartão entram na fatura; pagar a fatura não cria uma segunda despesa de consumo.
- Sugestões de notificações exigem revisão antes de virar lançamentos.
- A previsão usa compromissos cadastrados. Não presume salário nem gastos futuros desconhecidos.

## Estado do projeto

| Área | Situação |
| --- | --- |
| Android | Em uso; versão de referência **1.5.4+20** |
| Windows | Aplicativo nativo com SQLite, navegação lateral e tabela de transações; homologação completa ainda em andamento |
| Funcionamento offline | Registros e consultas locais; cotações externas dependem de conexão |
| Sincronização celular ↔ PC | Planejada. Hoje cada instalação mantém sua própria base |
| Telegram/WhatsApp | Proposta documentada; sem bot em produção |

Não há uma publicação oficial do Nexo na Play Store neste repositório. A seção de código não inclui APKs, bancos pessoais, backups ou credenciais de assinatura. Não use o banco SQLite aberto em uma pasta compartilhada entre dispositivos como substituto de sincronização.

## Executar o projeto

Use Flutter e Dart compatíveis com `pubspec.yaml`. O ambiente utilizado na rodada 1.5.4 foi Flutter **3.47.5**. Confira a instalação com `flutter doctor -v`.

```sh
git clone https://github.com/daniel-moulaz/Nexo.git
cd Nexo
flutter pub get
flutter analyze
flutter test --concurrency=1
```

**Android:** instale Android SDK e o JDK compatível com o Gradle do projeto, conecte um dispositivo de teste e execute:

```sh
flutter run -d <id-do-dispositivo>
flutter build apk --release
```

**Windows:** é necessário Visual Studio com **Desktop development with C++** e Windows SDK. Ative o Modo de Desenvolvedor do Windows se o Flutter solicitar suporte a links simbólicos.

```sh
flutter run -d windows
flutter build windows --release
```

O bundle Windows fica em `build/windows/x64/runner/Release/`. Distribua a **pasta inteira**, incluindo DLLs e `data/`, e execute `Nexo.exe`.

Credenciais de assinatura ficam apenas na máquina de desenvolvimento. Sem configuração de assinatura própria, o projeto usa a assinatura de depuração como fallback; esse build não equivale a uma distribuição pública assinada. Para atualizar uma instalação existente sem perder compatibilidade, preserve seu certificado.

## Arquitetura e dados

- **Flutter/Dart:** interface e regras financeiras compartilhadas.
- **SQLite:** armazenamento local; `sqflite` no Android e `sqflite_common_ffi` no Windows.
- **Provider:** estado do aplicativo.
- **Kotlin:** integrações Android, incluindo análise conservadora de notificações autorizadas.
- **Testes:** regras contábeis, persistência, importação/exportação, segurança, navegação e layouts.

Os identificadores técnicos `com.ma.expensy`, `expensy.db` e o nome do pacote Dart `expensy` são preservados para compatibilidade. O nome apresentado ao usuário é **Nexo**.

## Documentação

- [Home, pesquisa de UX e validação da versão 1.5.4](docs/NEXO_HOME_2026_10.md)
- [Dívidas, recorrentes e revisão financeira](docs/NEXO_USABILITY_2026_10.md)
- [Painel, análises e automação](docs/NEXO_EVOLUTION_2026.md)
- [Arquitetura proposta para sincronização](docs/NEXO_SYNC_ARCHITECTURE.md)
- [Proposta de lançamento por conversa](docs/NEXO_CONVERSATIONAL_ENTRY.md)
- [Roadmap](docs/NEXO_ROADMAP.md)

Os documentos registram diferentes etapas do desenvolvimento; consulte a data e a versão de cada relatório. Builds, capturas privadas e bases temporárias não fazem parte do código publicado.

## Desenvolvimento e origem

O Nexo é desenvolvido por [Daniel Moulaz](https://github.com/daniel-moulaz) a partir do [Expensy, de Mina Android](https://github.com/mina-android/Expensy), sob licença MIT. A evolução inclui adaptação brasileira, revisão contábil, automação local, experiência desktop e novas formas de visualizar compromissos financeiros.

O histórico e a autoria do projeto original são preservados. Este repositório tem apresentação e evolução próprias; não é o repositório oficial do Expensy.

Contribuições devem manter testes relevantes, compatibilidade dos dados e migrações explícitas quando necessárias. Nunca inclua bancos pessoais, notificações reais, PINs, tokens, keystores ou arquivos de configuração locais em commits ou issues.

Licença [MIT](LICENSE), com os avisos de autoria originais preservados.
