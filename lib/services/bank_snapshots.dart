import 'balance_check.dart';
import 'pluggy_inbox.dart';
import 'diagnostics.dart';

/// The Open Finance account snapshots (balance, card limit), read from the
/// server at most every few minutes and shared by the screens. Empty when
/// Open Finance is not connected or the server is older: nothing breaks.
class BankSnapshots {
  static List<BankAccountSnapshot>? _cache;
  static DateTime? _at;
  static Future<List<BankAccountSnapshot>>? _loading;

  static Future<List<BankAccountSnapshot>> load({bool force = false}) {
    final at = _at;
    if (!force &&
        _cache != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 10)) {
      return Future.value(_cache);
    }
    return _loading ??= _read().whenComplete(() => _loading = null);
  }

  static Future<List<BankAccountSnapshot>> _read() async {
    final remote = PluggyInbox.instance?.remote;
    if (remote == null) return const [];
    try {
      _cache = await remote.accounts();
      _at = DateTime.now();
    } catch (e) {
      Diagnostics.note('open finance: contas', e);
      // Keep what we had; an extra never fails a screen.
    }
    return _cache ?? const [];
  }

  /// The bank card linked to [nexoAccountId], if any.
  static BankAccountSnapshot? linkedTo(
          List<BankAccountSnapshot> list, String nexoAccountId) =>
      list.where((s) => s.nexoAccountId == nexoAccountId).firstOrNull;

  /// Share of the card limit in use (0..1+), from the bank.
  static double? limitUsed(BankAccountSnapshot s) {
    final limit = s.creditLimitCents, available = s.availableCents;
    if (!s.isCard || limit == null || available == null || limit <= 0) {
      return null;
    }
    return (limit - available) / limit;
  }
}
