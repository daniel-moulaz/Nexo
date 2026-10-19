# Revisão local de usabilidade — 19/10/2026

## Escopo e privacidade

Revisão autorizada da versão Android 1.6.0+21 no aparelho conectado, com navegação somente de leitura. Nenhum lançamento real foi criado, pago, excluído ou reclassificado. Capturas privadas ficam apenas na pasta ignorada de build; este documento não contém nomes, valores nem exportações da base pessoal.

## Problemas observados e ajustes 1.6.1+22

- Home: comparação visual ocupava espaço mesmo sem gastos no período anterior. Agora as barras só aparecem quando existe base de comparação; a mensagem continua explicando a ausência de histórico.
- Home: falta de caixa intermediária ficava escondida abaixo do gráfico de previsão. Um aviso junto ao saldo mostra a primeira data projetada abaixo de zero no horizonte selecionado, com acesso à Agenda. Modo privado oculta esse aviso. Alertas de atraso continuam prioritários.
- Home: atalhos explícitos para Análises, Agenda, revisão de 3 ou 7 dias e Investimentos. A análise recebe o mês selecionado. Não são novos cálculos nem um serviço externo de relatórios.
- Recorrentes: os filtros de tipo ocupavam várias linhas antes dos compromissos. Substituídos por um menu com opção selecionada visível. As visões Em aberto, Próximos meses, Histórico e Encerradas continuam disponíveis.
- Barra inferior: rótulo curto “Rotina” evita a quebra observada no nome de Recorrentes. A tela mantém seu título descritivo e inclui receitas, despesas fixas e parcelamentos.
- Despesas: o cabeçalho identifica o mês completo e explica a diferença para o consumo até hoje da Home. Lançamentos com dia futuro recebem indicação “Data futura”, preservando seu status real.

## Referências consultadas

- [Copilot — Dashboard Tab Overview](https://help.copilot.money/en/articles/6045480-dashboard-tab-overview): revisão, orçamentos e próximos compromissos acessíveis no painel. Adaptado como acesso direto às telas já existentes e prioridade para alertas acionáveis.
- [YNAB — Features](https://www.ynab.com/features): planejamento, metas e leitura de evolução financeira. A separação entre hoje e o período completo ajuda a interpretar o histórico sem misturá-lo ao futuro.

Sem cópia de assets, textos ou layout proprietário. A personalização orienta a hierarquia da interface; não incorpora dados pessoais no código.

## Compatibilidade

Schema permanece 24. Sem mudanças de banco, regras contábeis, assinatura, applicationId ou sincronização. Investimentos continuam sendo acompanhamento local separado das contas, como documentado em NEXO_INVESTMENTS.md.

## Validação

Análise estática limpa e suíte completa com **248 testes aprovados**, incluindo aviso de falta de caixa antes do resumo mensal, privacidade, acesso à análise, ausência de barras sem histórico e filtro de recorrentes. Primeiro conjunto de 59 testes de Home, recorrentes e visibilidade também aprovado. Testes usam dados sintéticos e bases temporárias; cobrem telas compactas e desktop com texto ampliado.

Inspeção real da versão anterior: Home, carteira, dívidas, recorrentes, despesas, previsão, categorias, Análises e diálogo de filtros. Nenhum formulário de lançamento foi salvo.

Android Release 1.6.1+22 gerado e instalado com `adb install -r`: Success. Package manager confirmou versionName 1.6.1/versionCode 22. ApplicationId `com.ma.expensy` e certificado SHA-256 `54d668e0f56caf801de429377a7a3066dbe0ed74779f04bac1ba1d2a5b112096` preservados. APK em `build/distribution/Nexo-1.6.1+22-android.apk`, SHA-256 `DC7CF8FC05269E2F2821EC278E423EC5686BE7B0891B68D424CCAE6D724B415F`.

Após instalação, o app abriu na proteção local existente. O usuário desbloqueou normalmente; a nova Home foi observada com o aviso antecipado de caixa, ausência das barras sem histórico e os mesmos totais visíveis da revisão anterior. Não houve tentativa de contornar a segurança.

No Android atualizado, toque no aviso abriu Agenda com horizonte de 30 dias. Recorrentes e menu de tipos foram abertos: seleção atual e três opções legíveis; rótulo Rotina sem quebra; valores e compromissos preservados. Nenhum pagamento foi registrado.

Windows Release compilado. Bundle completo: `build/distribution/Nexo-1.6.1+22-windows-x64.zip`, SHA-256 `B035BF6357BEE2FE930BEEA02ECED1A47A18FA83C1091A39CA7357A0CEEF6B94`. Empacotamento verificou DLLs/assets e ausência de banco, credenciais e logs. Extrair a pasta inteira; não distribuir apenas Nexo.exe. Esta rodada não incluiu homologação manual nativa do Windows.
