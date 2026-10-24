import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/desktop_profile.dart';
import 'investment_models.dart';

/// Daily CDI rates (Banco Central, SGS series 12), in percent per business
/// day. Public data: the request carries only a date range.
class CdiSeries {
  CdiSeries(Map<DateTime, double> rates, {DateTime? from})
      : rates = Map.fromEntries(
            rates.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
        from = from ?? (rates.isEmpty ? null : rates.keys.reduce(_min));
  final Map<DateTime, double> rates;

  /// Start of the period asked for: a weekend start has no rate of its own.
  final DateTime? from;
  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  DateTime? get last => rates.isEmpty ? null : rates.keys.last;

  /// Growth of 1 invested on [from] until [to]: the rate of each business
  /// day d with from <= d < to, as a CDB applied on d earns d's rate.
  double factor(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    var f = 1.0;
    for (final e in rates.entries) {
      if (e.key.isBefore(a)) continue;
      if (!e.key.isBefore(b)) break;
      f *= 1 + e.value / 100;
    }
    return f;
  }

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);
  Map<String, Object?> toJson() => {
        'from': from == null ? null : _day(from!),
        'rates': {for (final e in rates.entries) _day(e.key): e.value},
      };
  factory CdiSeries.fromJson(Map<String, dynamic> j) => CdiSeries({
        for (final e in (j['rates'] as Map<String, dynamic>).entries)
          DateTime.parse(e.key): (e.value as num).toDouble()
      }, from: j['from'] == null ? null : DateTime.parse(j['from'] as String));
}

class CdiComparison {
  const CdiComparison(
      {required this.portfolio,
      required this.cdi,
      required this.since,
      required this.coveredUntil});

  /// Market value now, in cents.
  final int portfolio;

  /// What the same contributions and withdrawals would be worth at 100% of
  /// the CDI, in cents.
  final int cdi;
  final DateTime since, coveredUntil;
  int get difference => portfolio - cdi;
}

/// Compares the portfolio with putting each contribution (and taking each
/// sale or income) on the same day at 100% of the CDI. Archived assets and
/// assets in other currencies stay out. Null when there is nothing to
/// compare or the series does not cover the first operation.
CdiComparison? compareWithCdi(
    Iterable<InvestmentPosition> positions, CdiSeries series, DateTime now) {
  final first = series.from;
  final last = series.last;
  if (first == null || last == null) return null;
  var portfolio = 0;
  var cdi = 0.0;
  DateTime? since;
  for (final p in positions) {
    if (p.investment.archived || p.operations.isEmpty) continue;
    portfolio += p.value;
    for (final op in p.operations) {
      final local = op.date.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day.isBefore(first)) return null;
      final f = series.factor(day, now);
      cdi += switch (op.kind) {
        'buy' || 'opening' => op.cents * f,
        _ => -op.cents * f, // sell, income: money that left the portfolio
      };
      if (since == null || day.isBefore(since)) since = day;
    }
  }
  if (since == null) return null;
  return CdiComparison(
      portfolio: portfolio, cdi: cdi.round(), since: since, coveredUntil: last);
}

class CdiSource {
  CdiSource({http.Client Function()? clientFactory})
      : clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() clientFactory;

  /// Tests replace the network source.
  static CdiSource Function() instance = CdiSource.new;

  static String get _key =>
      DesktopProfile.isTest ? 'cdi_series_qa_v1' : 'cdi_series_v1';

  static Future<CdiSeries?> cached() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return null;
      return CdiSeries.fromJson(
          (jsonDecode(raw) as Map)['series'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Cached series extended to today, at most every 12 hours. Network
  /// errors keep the cached series.
  Future<CdiSeries?> load(DateTime since, {DateTime? now}) async {
    now ??= DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final old = await cached();
    final checked =
        DateTime.tryParse(_decode(prefs.getString(_key))?['checked'] ?? '');
    since = DateTime(since.year, since.month, since.day);
    final covers = old?.from != null && !old!.from!.isAfter(since);
    if (covers &&
        checked != null &&
        now.difference(checked) < const Duration(hours: 12)) {
      return old;
    }
    try {
      final rates = <DateTime, double>{...?(covers ? old.rates : null)};
      var from = covers && old.last != null
          ? old.last!.add(const Duration(days: 1))
          : since;
      while (!from.isAfter(now)) {
        // The API refuses daily ranges of ten years or more.
        var to = DateTime(from.year + 5, from.month, from.day)
            .subtract(const Duration(days: 1));
        if (to.isAfter(now)) to = now;
        rates.addAll(await _fetch(from, to));
        from = to.add(const Duration(days: 1));
      }
      final series = CdiSeries(rates, from: covers ? old.from : since);
      await prefs.setString(
          _key,
          jsonEncode(
              {'checked': now.toIso8601String(), 'series': series.toJson()}));
      return series;
    } catch (_) {
      return old;
    }
  }

  static Map<String, dynamic>? _decode(String? raw) {
    try {
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<Map<DateTime, double>> _fetch(DateTime from, DateTime to) async {
    final client = clientFactory();
    try {
      final response = await client
          .get(Uri.https('api.bcb.gov.br', '/dados/serie/bcdata.sgs.12/dados', {
            'formato': 'json',
            'dataInicial': _br(from),
            'dataFinal': _br(to)
          }))
          .timeout(const Duration(seconds: 20));
      // No business day in the range (e.g. a weekend) answers 404.
      if (response.statusCode == 404) return {};
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 512 * 1024) {
        throw const FormatException('CDI indisponível');
      }
      final out = <DateTime, double>{};
      for (final row in jsonDecode(utf8.decode(response.bodyBytes)) as List) {
        final p = (row['data'] as String).split('/');
        final v = double.parse(row['valor'] as String);
        // A daily CDI above 1% would be over 1,000% a year: not a rate.
        if (p.length != 3 || !v.isFinite || v < 0 || v > 1) {
          throw const FormatException('CDI inválido');
        }
        out[DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]))] = v;
      }
      return out;
    } finally {
      client.close();
    }
  }
}
