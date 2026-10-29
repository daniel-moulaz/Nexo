/// The rules of the Nexo in plain words, searchable in the whole text (not
/// only in the titles). Kept as data so the app and the assistant can use
/// the same answers.
class HelpTopic {
  const HelpTopic(this.group, this.question, this.answer);
  final String group, question, answer;
}

const helpTopics = [
  // ── Como o Nexo conta o dinheiro ────────────────────────────────────
  HelpTopic(
      'Como o Nexo conta',
      'Transferência entre minhas contas conta como gasto?',
      'Não. Mover dinheiro entre suas contas, reservar para um objetivo ou aportar num investimento não é consumo nem receita: o dinheiro só mudou de lugar. Essas movimentações aparecem no extrato como "Transferência" e ficam fora de gastos, receitas, orçamentos e comparações.'),
  HelpTopic('Como o Nexo conta', 'Pagar a fatura do cartão conta duas vezes?',
      'Não. A compra no cartão já contou como gasto no dia da compra. O pagamento da fatura é uma transferência da conta para o cartão: abate a dívida e não cria um segundo gasto.'),
  HelpTopic('Como o Nexo conta', 'Uma despesa pendente mexe no saldo?',
      'Não. Pendente é o que você ainda vai pagar. Ela aparece na agenda e na previsão, mas o saldo das contas só muda quando você marca como paga.'),
  HelpTopic('Como o Nexo conta', 'O que é o ajuste de saldo neutro?',
      'Quando o saldo do Nexo não bate com o do banco, "Conferir com o banco" oferece um ajuste neutro: muda o saldo da conta sem criar receita nem despesa, como editar o saldo. Assim as médias e as comparações não se distorcem.'),
  HelpTopic('Como o Nexo conta', 'O que é um gasto pontual?',
      'Um gasto marcado como "Pontual" (por exemplo, um Pix para a família ou uma compra grande que não se repete) continua no saldo, no total do mês e no "quanto posso gastar", mas fica fora do ritmo do mês, da comparação com o mês anterior, das sugestões de orçamento e da média que diz quantos meses a reserva cobre.'),
  HelpTopic(
      'Como o Nexo conta',
      'Qual fatura recebe uma compra feita no dia do fechamento?',
      'A seguinte. No Nexo, como no banco, o dia do fechamento é o "melhor dia de compra": tudo que é comprado nesse dia entra na próxima fatura. Compras até o dia anterior fecham na fatura atual.'),
  HelpTopic('Como o Nexo conta', 'Renda fixa e renda extra: qual a diferença?',
      'Renda fixa é o que vem de uma receita recorrente cadastrada (salário, bolsa). Renda extra é tudo o mais que entrou (trabalho avulso, venda, presente). "Quanto posso gastar" usa só a renda fixa, para não planejar em cima do que pode não repetir.'),
  // ── Hoje e orçamento ────────────────────────────────────────────────
  HelpTopic('Hoje e orçamento', 'Como o "quanto posso gastar" é calculado?',
      'Renda fixa do mês, menos as contas fixas (recorrentes de despesa), menos o que está pendente, menos o que os objetivos pedem no mês, menos o gasto variável já feito. O que sobra é dividido pelos dias que faltam. "Como chego nisso" mostra cada parcela.'),
  HelpTopic('Hoje e orçamento', 'O que é o ritmo do mês?',
      'A linha dos gastos variáveis acumulados dia a dia, comparada com o ritmo ideal (gastar por igual até o fim do mês) e com o mês anterior. Só gastos variáveis: contas fixas, transferências e pontuais ficam fora.'),
  HelpTopic('Hoje e orçamento', 'O que são os tipos de gasto (envelopes)?',
      'Os seis grupos do método AUVP: Custos fixos, Conforto, Metas, Prazeres, Conhecimento e Liberdade financeira, cada um com uma parte da renda de referência (por padrão 30, 15, 15, 10, 5 e 25%). Cada categoria de despesa pertence a um tipo; aportes contam em Liberdade financeira e depósitos em objetivos contam em Metas, onde chegar a 100% é a meta, não um alerta. É planejamento: nada muda nos lançamentos.'),
  HelpTopic(
      'Hoje e orçamento',
      'Orçamento criado no meio do mês conta desde quando?',
      'Desde o dia em que foi criado, com o limite proporcional aos dias que faltavam. Nos meses seguintes o limite é inteiro.'),
  HelpTopic(
      'Hoje e orçamento',
      'Por que a comparação com o mês anterior diz "sem base"?',
      'Quando o período anterior tem menos de três lançamentos (por exemplo, no primeiro mês de uso), uma porcentagem não diria nada. A comparação volta quando houver base, e deixa os gastos pontuais de fora.'),
  // ── Banco e Open Finance ────────────────────────────────────────────
  HelpTopic(
      'Banco (Open Finance)',
      'O que chega do banco e o que o Nexo faz com isso?',
      'Movimentações, saldos, limites e faturas das contas conectadas no Meu Pluggy. Movimentações viram sugestões em "Para revisar": nada vira lançamento sozinho. A conciliação automática vincula ao que você já lançou, separa estornos, reservas e Pix entre contas próprias, e deixa o resto para você confirmar ou ignorar.'),
  HelpTopic(
      'Banco (Open Finance)',
      'Até quando os dados do banco estão atualizados?',
      'O Open Finance atualiza uma vez por dia. "Dados do banco até…" mostra a última movimentação recebida de cada banco. Se o dia ainda não chegou, um dia sem gastos no Nexo não significa que você não gastou.'),
  HelpTopic(
      'Banco (Open Finance)',
      'Com que frequência o Nexo busca os dados do banco?',
      'Ao abrir o app ou voltar para ele (no máximo a cada 15 minutos) e quando você puxa para atualizar em "Para revisar". A leitura não gasta chamadas do Open Finance; o banco é quem atualiza uma vez por dia.'),
  HelpTopic(
      'Banco (Open Finance)',
      'O que é "Conferir com o banco" e a conta principal com vários bancos?',
      'Vincule cada conta do banco a uma conta do Nexo. Várias contas do banco podem apontar para a mesma conta do Nexo: os saldos são somados e comparados de uma vez. Cartões são um para um. A diferença pode ser corrigida com um ajuste neutro.'),
  HelpTopic(
      'Banco (Open Finance)',
      'A fatura do banco é diferente da do Nexo. Qual vale?',
      'A do banco é a referência final. O Nexo mostra a fatura oficial ao lado da sua, com a diferença, para você achar compras que faltam ou foram lançadas duas vezes. Nada é lançado ou pago a partir dela.'),
  HelpTopic('Banco (Open Finance)', 'O que é "cobrança para conferir"?',
      'Um aviso para descrições que parecem tarifa, seguro, anuidade, proteção, capitalização ou serviço do banco. O aviso olha só a descrição: se você contratou, toque em "Reconheço"; se não, peça o detalhamento ao banco. O Nexo não contesta nem cancela nada.'),
  // ── Assistente ──────────────────────────────────────────────────────
  HelpTopic('Assistente', 'O que o assistente (Claude) pode fazer no Nexo?',
      'O mesmo que você no app: consultar, lançar, corrigir, apagar, transferir, pagar fatura, mexer em recorrentes, orçamentos e tipos de gasto, categorias, objetivos, investimentos, empréstimos, dinheiro emprestado, bens, desejos, regras de categoria e configurações. Cada pedido vira uma solicitação que o app grava com as próprias regras, uma de cada vez; o assistente só diz "feito" depois que o Nexo confirma. Tudo aparece em Sincronizar dispositivos → Feito pelo Claude, com Desfazer.'),
  HelpTopic('Assistente', 'Como desfazer algo que o Claude fez?',
      'Peça a ele ("desfaz o último lançamento") ou abra Sincronizar dispositivos → Feito pelo Claude e toque em Desfazer. Os dados e os saldos voltam ao que eram antes do pedido. Se você mudou algo depois, o Nexo não desfaz nada e avisa, para não apagar a sua mudança.'),
  HelpTopic(
      'Assistente',
      'Como conectar outro assistente (Claude Code, Cursor, VS Code)?',
      'Em Sincronizar dispositivos → Claude → Conectar, o endereço gerado funciona em qualquer cliente MCP. O diálogo mostra a receita de cada um. O endereço é a chave: para trocar, desconecte e gere outro.'),
  HelpTopic('Assistente', 'Como foi meu dia / minha semana?',
      'Pergunte ao assistente: ele resume entradas, saídas, compras no cartão, orçamentos estourados e próximos vencimentos, e avisa se os dados do banco de hoje ainda não chegaram. No app, o dia anterior aparece no Hoje e a semana em "Sua semana".'),
  // ── Dados e segurança ───────────────────────────────────────────────
  HelpTopic('Dados e segurança', 'Onde ficam meus dados?',
      'No aparelho, num banco local. Com a sincronização ligada, uma cópia fica no seu projeto Supabase, protegida por login e acesso por dono, sem criptografia de ponta a ponta (o assistente precisa ler). Backups e exportações são arquivos seus.'),
  HelpTopic(
      'Dados e segurança',
      'O Nexo movimenta dinheiro, faz Pix ou paga contas?',
      'Não. Nenhuma função movimenta dinheiro de verdade. O Open Finance é só leitura. Lançar, transferir ou pagar fatura no Nexo muda só os seus registros.'),
  HelpTopic('Dados e segurança', 'Como atualizar o app?',
      'A versão instalada aparece em Configurações. No celular, a atualização é feita pelo cabo USB com o mesmo certificado, sem perder dados; no PC, substituindo a pasta do programa.'),
];

/// Topics whose question or answer contains every word of [query].
List<HelpTopic> searchHelp(String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return helpTopics;
  return [
    for (final t in helpTopics)
      if (words.every((w) =>
          t.question.toLowerCase().contains(w) ||
          t.answer.toLowerCase().contains(w)))
        t
  ];
}
