# Open Finance — proposta futura

> **Atualização 24/10/2026:** o Open Finance foi implementado pelo **Meu Pluggy** (gratuito para uso pessoal, só leitura): sugestões em "Para revisar", saldo do banco × Nexo, limite real e fatura oficial do cartão. Ver [APIS_EXPLORACAO.md](APIS_EXPLORACAO.md) e [PLAN.md](PLAN.md). O texto abaixo é a proposta original.

Não implementado nesta rodada. O Nexo funciona localmente e não pede senha bancária.

O [Banco Central](https://www.bcb.gov.br/meubc/faqs/s/open-finance) informa que compartilhamento exige consentimento e identifica instituições participantes. Acesso real requer avaliar parceiro participante, contrato, custos, segurança e requisitos regulatórios; não basta chamar uma API pública do celular.

Arquitetura possível: Nexo → backend próprio autenticado → parceiro habilitado → instituição, com autorização no ambiente do banco. Tokens e segredos ficam no backend, nunca no APK. Importação entra primeiro em uma caixa de revisão, com IDs externos estáveis, conciliação explícita, histórico de consentimentos, revogação, expiração e exclusão. O banco local continua utilizável sem conexão.

Antes de iniciar: revisão jurídica/técnica atualizada, contrato e custo aprovados, minimização de dados, criptografia, testes de revogação e incidentes. Proibidos scraping, captura de senha e automação de login. Nenhum dado foi enviado para esse propósito.
