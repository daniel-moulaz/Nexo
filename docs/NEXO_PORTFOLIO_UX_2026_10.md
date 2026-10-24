# Carteira por ativo — 1.6.2+23

## Objetivo

Dar visibilidade ao ganho ou perda de cada posição, antes dos gráficos agregados. Revisão solicitada pelo usuário após ativar cotações. Sem copiar interface, textos ou assets de terceiros.

## Referências

- [Gorila para investidores](https://gorila.com.br/para-investidores/): resultado sempre visível e visão consolidada.
- [Investidor10 — recursos da plataforma](https://investidor10.com.br/conteudo/investidor10-o-que-e-a-plataforma-como-funciona-e-quais-recursos-oferece-aos-investidores-120727/): preço médio, variação e alocação como informações complementares.
- [Gorila — cálculos e cotizações](https://guia.gorila.com.br/hc/pt-br/sections/360009897352-C%C3%A1lculos-e-Cotiza%C3%A7%C3%B5es): distinguir resultado nominal de rentabilidade histórica.

Foram consultadas páginas públicas; não houve acesso a carteiras privadas dessas plataformas.

## Mudanças

- Ativos passam a aparecer antes da distribuição por classe e dos resultados de vendas/proventos.
- Cada cartão mostra código, nome, quantidade, ganho/perda em reais e percentual, valor atual, custo restante, preço médio, último preço e fonte/data.
- Verde para ganho, vermelho para perda, neutro para zero. Sinal, ícone e texto preservam compreensão sem depender de cor. Paleta adaptada a claro/escuro.
- Detalhe do ativo e resumo da carteira usam a mesma apresentação de variação.
- Resumo inicial compacto: compras do mês foram movidas para Resultados registrados.
- Privacidade oculta valores, percentuais e direção do resultado.

## Semântica financeira

Variação = valor avaliado − custo restante. Percentual = variação / custo restante × 100. O percentual consolidado usa totais, não média dos percentuais individuais. Se custo for zero, mostrar “Sem base percentual”. Posição encerrada mostra resultado das vendas, sem tratar valorização zero como seu retorno histórico.

Não é variação diária, rentabilidade ponderada por fluxos, nem retorno incluindo dividendos. Vendas e proventos continuam separados. Preço médio exibido em centavos, calculado sobre quantidade atual; último preço preserva até seis casas quando necessário. Nenhuma mudança na persistência ou regras de replay. Schema 24 preservado.

## Validação

Análise estática limpa e **250 testes aprovados** na suíte completa. Os oito testes de interface da carteira também passaram com fonte real e geração de capturas sintéticas. Cobrem ganho, perda, zero, custo zero, privacidade e ordem visual; tamanhos de 320/412/1280/1920 px; detalhe, compra, venda e preço manual. Capturas de celular escuro e desktop claro revisadas. Nenhuma cotação ou posição real foi usada em fixtures ou documentação.

Android Release compilado e instalado com `adb install -r` (Success). Versão 1.6.2+23 confirmada pelo package manager. Identidade `com.ma.expensy`, assinatura anterior e dados preservados; sem uninstall/clear-data. APK: `build/distribution/Nexo-1.6.2+23-android.apk`, SHA-256 `9C8423C69E6BF9FB55F262FA009B4237D0C5A266813B597916EC5EA13E8F575E`.

Abertura após instalação exibiu a proteção local normal; após desbloqueio pelo usuário, a carteira e o detalhe de ativo foram conferidos no Android real. Ganho verde e perda vermelha, valores e percentuais por posição, preço médio, último preço e fonte/data apareceram corretamente, sem corte de texto nos cartões observados. Nenhuma operação financeira foi alterada durante essa conferência. Não houve tentativa de contornar a proteção; capturas privadas permanecem fora do versionamento.

Windows Release compilado e bundle completo empacotado: `build/distribution/Nexo-1.6.2+23-windows-x64.zip`, SHA-256 `6DE3FCD9BD14B564D9523FA5EE2E97E0F617A2870BF938CE505390EFAE217EF0`. A validação desktop desta mudança cobre build e testes de interface responsiva; não representa nova homologação funcional completa do executável Windows.
