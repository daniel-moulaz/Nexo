import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/services/reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The October 2026 session (fictitious names), section 7 of the plan.
void main() {
  final day = DateTime(2026, 10, 20, 12);
  PendingMovement mv(String id, int cents, String description, String kind,
          {DateTime? at}) =>
      PendingMovement(
          id: id,
          amountCents: cents,
          description: description,
          kind: kind,
          occurredAt: at ?? day);
  AppTransaction tx(String id, double amount, String description,
          {String type = 'expense', String category = 'food', DateTime? at}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: description,
          accountId: 'mp',
          categoryId: category,
          date: at ?? day);

  test('names without card prefixes, numbers and movement words', () {
    expect(normalizeMerchant('Ifd*Wesley Lanches 123'), 'wesley lanches');
    expect(normalizeMerchant('Mp *Buser'), 'buser');
    expect(normalizeMerchant('Pix enviado - Fulana de Tal'), 'fulana tal');
    expect(
        normalizeMerchant('Pagamento com Pix PHSS 12.345.678/0001-90'), 'phss');
    expect(textSimilarity('Pix recebido IFOODCOM AGENCIA', 'Trabalho Ifood'),
        greaterThanOrEqualTo(.6));
  });

  test('the session: only what really needs the person is left', () {
    final pending = [
      mv('lanche', 800, 'Pagamento com Pix Fulana Aparecida', 'expense'),
      mv('buser', 3990, 'Mp *Buser', 'expense'),
      mv('wesley', 3085, 'Ifd*Wesley', 'expense'),
      mv('forgot', 1000, 'Pix enviado Beltrano', 'expense'),
      // PHSS chain on the same day.
      mv('phss-mp', 2500, 'Pagamento PHSS', 'expense'),
      mv('phss-back', 2500, 'Estorno PHSS', 'income'),
      mv('self-out', 2500, 'Pix enviado Dono da Conta', 'expense'),
      mv('self-in', 2500, 'Pix recebido Dono da Conta', 'income'),
      mv('phss-inter', 2500, 'Pagamento PHSS', 'expense'),
      // Reserve moves and a tiny yield.
      mv('r1', 500, 'Reserva por gasto MT', 'transfer'),
      mv('r2', 500, 'Reserva por gasto MT', 'transfer'),
      mv('r3', 500, 'Reserva por gasto MT', 'transfer'),
      mv('r4', 21612, 'Dinheiro retirado MT', 'income'),
      mv('yield', 3, 'Rendimento', 'income'),
      mv('ifood', 10000, 'Pix recebido IFOODCOM AGENCIA', 'income'),
    ];
    final transactions = [
      tx('m-lanche', 8, 'lanche ufop'),
      tx('m-bus', 49.90, 'Passagem JM-BH', category: 'travel'),
      tx('m-acai', 30, 'Açaí'),
      tx('m-bets', 25, 'apostas', category: 'bets'),
      tx('m-job', 100, 'Trabalho Ifood', type: 'income', category: 'extra'),
      // Old Buser purchases teach the category.
      tx('old-bus', 39.90, 'Mp *Buser',
          category: 'travel', at: DateTime(2026, 9, 5)),
    ];
    final metadata = <String, TransactionMetadata>{};
    final result = {
      for (final m in reconcile(
          pending: pending,
          transactions: transactions,
          metadata: metadata,
          linkedIds: {'old-bus'},
          ownerNames: ['Dono da Conta'],
          learnedCategory: categoryFromHistory(transactions, metadata)))
        m.movement.id: m
    };
    Resolution r(String id) => result[id]!.resolution;

    expect(r('lanche'), Resolution.linked);
    expect(result['lanche']!.transaction!.id, 'm-lanche');
    expect(r('buser'), Resolution.maybe);
    expect(result['buser']!.transaction!.id, 'm-bus');
    expect(r('wesley'), Resolution.maybe);
    expect(result['wesley']!.transaction!.id, 'm-acai');
    expect(r('forgot'), Resolution.newEntry);

    expect(r('phss-mp'), Resolution.reversal);
    expect(r('phss-back'), Resolution.reversal);
    expect(r('self-out'), Resolution.ownTransfer);
    expect(r('self-in'), Resolution.ownTransfer);
    expect(result['self-out']!.pair!.id, 'self-in');
    // One spending left, linked to the manual "apostas".
    expect(r('phss-inter'), Resolution.linked);
    expect(result['phss-inter']!.transaction!.id, 'm-bets');

    for (final id in ['r1', 'r2', 'r3', 'r4']) {
      expect(r(id), Resolution.reserve, reason: id);
    }
    expect(r('yield'), Resolution.smallYield);
    expect(r('ifood'), Resolution.linked);
    expect(result['ifood']!.transaction!.id, 'm-job');

    final needsPerson = result.values
        .where((m) => !m.automatic)
        .map((m) => m.movement.id)
        .toSet();
    expect(needsPerson, {'buser', 'wesley', 'forgot', 'self-out', 'self-in'});
  });

  test('never links twice, never to a transfer leg; dismissed pairs stay apart',
      () {
    final pending = [
      mv('a', 800, 'Pix Fulana', 'expense'),
      mv('b', 800, 'Pix Ciclana', 'expense'),
    ];
    final transactions = [
      tx('lanche', 8, 'lanche'),
      tx('leg', 8, 'Transferência enviada'),
    ];
    final metadata = {
      'leg': const TransactionMetadata(
          transactionId: 'leg', excludeFromSpending: true, source: 'transfer:x')
    };
    final result = reconcile(
        pending: pending, transactions: transactions, metadata: metadata);
    // Two R$ 8 movements and one R$ 8 entry: not unique, so ask.
    expect(result.where((m) => m.resolution == Resolution.linked), isEmpty);
    expect(result.every((m) => m.transaction?.id != 'leg'), isTrue);

    final again = reconcile(
        pending: [pending.first],
        transactions: transactions,
        metadata: metadata,
        linkedIds: {'lanche'});
    expect(again.single.resolution, Resolution.newEntry);

    final dismissed = reconcile(
        pending: [mv('w', 3085, 'Ifd*Wesley', 'expense')],
        transactions: [tx('acai', 30, 'Açaí')],
        metadata: const {},
        dismissedPairs: {'w|acai'});
    expect(dismissed.single.resolution, Resolution.newEntry);
  });

  test('a received Pix from the same name is not a reversal', () {
    final result = reconcile(pending: [
      mv('out', 5000, 'Pix enviado Fulano', 'expense'),
      mv('in', 5000, 'Pix recebido Fulano', 'income'),
    ], transactions: const [], metadata: const {});
    expect(result.map((m) => m.resolution).toSet(), {Resolution.ownTransfer});
  });

  group('real cases', () {
    final day = DateTime(2026, 11, 5, 12);
    PendingMovement move(String id, int cents, String text,
            {String kind = 'expense', String medium = 'bank'}) =>
        PendingMovement(
            id: id,
            amountCents: cents,
            description: text,
            kind: kind,
            medium: medium,
            occurredAt: day);
    AppTransaction entry(String id, double amount, String text,
            {String account = 'bank'}) =>
        AppTransaction(
            id: id,
            type: 'expense',
            amount: amount,
            description: text,
            accountId: account,
            categoryId: 'c',
            date: day,
            currency: 'BRL');

    test('a Pix to oneself is neither spending nor income, one side or two',
        () {
      final r = reconcile(pending: [
        move('out', 5000, 'Pix enviado Pessoa Exemplo'),
        move('in', 7000, 'Pix recebido Pessoa Exemplo', kind: 'income'),
        move('other', 5000, 'Pix enviado Outra Pessoa'),
      ], transactions: const [], metadata: const {}, ownerNames: [
        'Pessoa Exemplo'
      ]);
      expect(r[0].resolution, Resolution.ownName);
      expect(r[1].resolution, Resolution.ownName);
      expect(r[0].automatic, isTrue);
      expect(r[2].resolution, Resolution.newEntry);
    });

    test('the piggy bank moves stay out by themselves', () {
      final r = reconcile(pending: [
        move('a', 1000, 'Dinheiro retirado Emergências', kind: 'income'),
        move('b', 1000, 'Reserva por gasto'),
      ], transactions: const [], metadata: const {});
      expect(r.every((m) => m.resolution == Resolution.reserve), isTrue);
    });

    test('an entry made by hand links to the movement', () {
      final r = reconcile(
          pending: [move('a', 3300, 'Lanche', medium: 'credit')],
          transactions: [entry('t', 33, 'Lanche', account: 'card')],
          metadata: const {},
          creditAccounts: const {'card'});
      expect(r.single.resolution, Resolution.linked);
      expect(r.single.wrongAccount, isFalse);
    });

    test('a Pix against a card entry is pointed out, never linked by itself',
        () {
      final r = reconcile(
          pending: [move('a', 2530, 'iFood')],
          transactions: [entry('t', 25.30, 'iFood', account: 'card')],
          metadata: const {},
          creditAccounts: const {'card'});
      expect(r.single.resolution, Resolution.maybe);
      expect(r.single.wrongAccount, isTrue);
      expect(r.single.automatic, isFalse);
    });

    test('"they are different" holds for a wrong account too', () {
      final r = reconcile(
          pending: [move('a', 2530, 'iFood')],
          transactions: [entry('t', 25.30, 'iFood', account: 'card')],
          metadata: const {},
          dismissedPairs: const {'a|t'},
          creditAccounts: const {'card'});
      expect(r.single.wrongAccount, isFalse);
    });
  });
}
