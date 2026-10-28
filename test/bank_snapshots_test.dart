import 'package:nexo/services/balance_check.dart';
import 'package:nexo/services/bank_snapshots.dart';
import 'package:nexo/services/pluggy_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

class _Remote implements PluggyRemote {
  int reads = 0;
  _Remote(this.rows);
  List<BankAccountSnapshot> rows;
  final links = <String, String?>{};
  @override
  Future<List<BankAccountSnapshot>> accounts() async {
    reads++;
    return rows;
  }

  @override
  Future<void> link(String accountId, String? nexoAccountId) async {
    links[accountId] = nexoAccountId;
    rows = [
      for (final r in rows)
        r.accountId == accountId
            ? BankAccountSnapshot(
                accountId: r.accountId,
                bank: r.bank,
                type: r.type,
                name: r.name,
                currency: r.currency,
                balanceCents: r.balanceCents,
                bankUpdatedAt: r.bankUpdatedAt,
                nexoAccountId: nexoAccountId)
            : r
    ];
  }

  @override
  Future<List<PluggyItem>> refresh({bool force = false}) async => const [];
  @override
  Future<List<PluggyItem>> items() async => const [];
  @override
  Future<void> addItem(String itemId, String label) async {}
  @override
  Future<void> removeItem(String itemId) async {}
  @override
  Future<List<Map<String, dynamic>>> suggestions(int sinceMs) async => const [];
  @override
  Future<void> decide(List<Map<String, Object?>> decisions) async {}
}

void main() {
  final card = BankAccountSnapshot(
      accountId: 'p-nu',
      bank: 'Nubank',
      type: 'CREDIT',
      name: 'Cartão',
      currency: 'BRL',
      balanceCents: 21359,
      creditLimitCents: 65000,
      availableCents: 1549,
      nexoAccountId: 'nu');

  test('the bank says how much of the limit is used (session: 97%)', () {
    expect(BankSnapshots.limitUsed(card), closeTo(.976, .001));
    expect(BankSnapshots.linkedTo([card], 'nu'), same(card));
    expect(BankSnapshots.linkedTo([card], 'other'), isNull);
    final noLimit = BankAccountSnapshot(
        accountId: 'b', bank: 'B', type: 'BANK', name: 'n', currency: 'BRL');
    expect(BankSnapshots.limitUsed(noLimit), isNull);
  });

  test('read once and shared; empty without Open Finance', () async {
    PluggyInbox.instance = null;
    expect(await BankSnapshots.load(force: true), isEmpty);
    final remote = _Remote([card]);
    PluggyInbox.instance = PluggyInbox(remote);
    expect(await BankSnapshots.load(force: true), [card]);
    await BankSnapshots.load();
    await BankSnapshots.load();
    expect(remote.reads, 1);
    PluggyInbox.instance = null;
  });
}
