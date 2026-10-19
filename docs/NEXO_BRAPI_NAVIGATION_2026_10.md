# Nexo 1.6.3+24 — mercado e navegação

## Pesquisa e decisões

Consultadas em 19/10/2026 as fontes oficiais:

- [Cotação brapi v2](https://brapi.dev/docs/acoes/cotacao): preço, variação do pregão, abertura, fechamento anterior, extremos, volume, valor de mercado e `logourl`. A documentação cobre ações, FIIs e ETFs nesse endpoint.
- [Planos](https://brapi.dev/pricing): gratuito com uma requisição simultânea e um ativo por chamada; atualização de dados a cada 30 minutos. A disponibilidade efetiva depende do ticker, chave e plano; não presumir acesso irrestrito.
- [Histórico](https://brapi.dev/docs/acoes/historico): endpoint separado, janelas por plano e distinção entre preços ajustados e originais.
- [Dividendos](https://brapi.dev/docs/acoes/dividendos): eventos públicos não comprovam recebimento na carteira; FIIs usam endpoint separado.
- [Perfil da empresa](https://brapi.dev/docs/acoes/perfil): dados complementares separados da cotação.
- [YNAB — reorganização do app](https://www.ynab.com/whats-new/the-great-ynab-remodel): Home para decisões rápidas e espaço comum para consultar movimentações.
- [Material — navegação](https://m2.material.io/design/navigation/): poucos destinos principais e hierarquia previsível.

Adaptação conceitual, sem copiar assets ou telas dos concorrentes. Logos vêm do campo público do provedor; não são novos assets proprietários do Nexo.

## Implementado

- Aproveitamento dos campos opcionais da mesma consulta de cotação, sem chamadas extras de dados para cada indicador.
- Logo SVG do domínio `icons.brapi.dev`, HTTPS, sem chave de API no pedido de imagem. Falha, ausência, modo offline ou consulta desativada usam inicial do ticker. Imagens têm cache em memória; não há garantia de persistência do logo após reiniciar offline.
- Variação percentual do pregão separada do ganho/perda da posição, com data e hora local da fonte.
- Detalhe recolhível de mercado com variação por unidade, abertura, fechamento anterior, máxima/mínima do pregão e de 52 semanas, valor de mercado e volume em unidades.
- Ausência ou formato inválido não viram zero. Campo opcional inválido não impede atualização do preço principal.
- Cache local reconstruível de dados públicos, sem operações/quantidades/chave. Preserva snapshot mais recente, continua legível offline e não altera schema 24 nem backup financeiro.
- Consulta também para FIIs e ETFs brasileiros, conforme cobertura do provedor. Renda fixa e cripto continuam manuais.
- Barra mobile com cinco destinos: Início, Extrato, Contas, Investir e Mais; rótulos sempre visíveis. IDs internos preservados para atalhos antigos e desktop.
- Extrato usa a consulta unificada de receitas/despesas/transferências e filtros já existente. Não abre teclado automaticamente ao entrar pela aba; busca direta e Ctrl+F preservados.
- Mais reorganizado em Planejar e acompanhar, Organizar e proteger, Outros controles. Recorrentes e orçamentos permanecem acessíveis; ferramentas ocasionais ficam recolhidas. Termos ambíguos: Ativos vira Bens e patrimônio; relatório de arquivo vira Exportar relatório.

## Limites deliberados

Não consultar todos os endpoints indiscriminadamente: isso gastaria cota e criaria mais telas sem melhorar a rotina. Histórico de preços, dividendos, múltiplos, balanços, perfil empresarial, macro e cripto foram pesquisados, mas não integrados nesta entrega. Um próximo gráfico histórico deve identificar ajustes e nunca ser chamado de rentabilidade pessoal. Proventos e eventos corporativos jamais serão aplicados automaticamente sobre quantidade ou saldo.

Os preços não são tempo real, não representam ordem de compra/venda e não comprovam posição na corretora. O app continua local-first; desativar consultas impede novos pedidos de logos na tela. Dados antigos têm timestamp explícito. Chave existente permanece no armazenamento seguro.

## Validação

Consulta pública de demonstração PETR4 confirmou resposta v2 e logo SVG com HTTP 200, sem chave nem carteira real.

Análise estática limpa. Suíte completa: **257 testes aprovados**. Após os ajustes finais de ativação da aba e seleção da navegação, repetidos **11 testes de interface**, todos aprovados. Testes novos cobrem campos opcionais, URLs de logo rejeitadas, cache offline e monotonicidade da data, cobertura por classe, navegação em 320/412 px, ausência de teclado automático e privacidade dos dados de mercado.

As operações financeiras, migrations e regras contábeis não foram alteradas. Os demais arquivos pendentes no workspace foram preservados e não fazem parte desta entrega.

Android Release final compilado (74,8 MB), identidade `com.ma.expensy`, versão `1.6.3+24`, certificado anterior confirmado. Instalado por atualização (`install -r`, Success), preservando dados. Artefato: `build/distribution/Nexo-1.6.3+24-android.apk`; SHA-256 `CA0C0DEF8C869B54C102F683726EC957CDC0727865003FB57E3471166CA655D2`.

Windows Release final compilado e pacote completo validado pelo empacotador: `build/distribution/Nexo-1.6.3+24-windows-x64.zip`; SHA-256 `789D63637233BF3232527E1AFAE8DF509B026AAEB5E05B4797796BCA296F6556`. Esta rodada não constitui nova homologação manual completa do executável Windows.

No Android real, conferidos Home com cinco abas rotuladas, abertura direta de Investir, atualização de dois tickers, logos SVG e variação do pregão separados do resultado pessoal, além do detalhe do ativo. Nenhuma operação financeira criada/editada para a inspeção. Capturas privadas permanecem fora do Git.

Também conferidos o menu Mais reorganizado e a expansão dos dados de mercado. A inspeção identificou botão de adicionar excessivamente largo e valor de mercado quebrando em várias linhas; corrigidos com FAB compacto no mobile e valor de mercado abreviado, rotulado como aproximado. Análise e os 11 testes de interface passaram novamente; APK final reinstalado e botão compacto conferido no aparelho.
