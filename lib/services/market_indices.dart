import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Public Brazilian indices from the Central Bank, no key and no cost:
/// IPCA (12 months), Selic (yearly target) and PTAX (dollar). Read once a
/// day, cached in preferences, shown as context next to the portfolio.
/// A failed read never fails a screen: the last good value stays.
class IndexReading {
  const IndexReading(
      {required this.ipca12m,
      required this.selic,
      required this.ptax,
      required this.at});

  /// IPCA accumulated over the last 12 months, in percent (e.g. 4.32).
  final double? ipca12m;

  /// Selic target rate, percent a year.
  final double? selic;

  /// PTAX sale rate, BRL per USD.
  final double? ptax;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'ipca12m': ipca12m,
        'selic': selic,
        'ptax': ptax,
        'at': at.toIso8601String()
      };
  static IndexReading fromJson(Map<String, dynamic> j) => IndexReading(
      ipca12m: (j['ipca12m'] as num?)?.toDouble(),
      selic: (j['selic'] as num?)?.toDouble(),
      ptax: (j['ptax'] as num?)?.toDouble(),
      at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2000));
}

class MarketIndices {
  MarketIndices(
      {http.Client Function()? clientFactory, DateTime Function()? now})
      : _clientFactory = clientFactory ?? http.Client.new,
        _now = now ?? DateTime.now;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;
  static const _key = 'nexo_market_indices';
  static const _ttl = Duration(hours: 20);

  /// SGS series: 433 = IPCA monthly %, 432 = Selic target % a year.
  static Uri sgs(int series, DateTime from, DateTime to) => Uri.parse(
      'https://api.bcb.gov.br/dados/serie/bcdata.sgs.$series/dados?formato=json&dataInicial=${_br(from)}&dataFinal=${_br(to)}');

  /// PTAX for one day (sale rate); weekends and holidays come back empty.
  static Uri ptax(DateTime day) => Uri.parse(
      "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarDia(dataCotacao=@dataCotacao)?@dataCotacao='${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}-${day.year}'&\$format=json");

  static String _br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Cached reading when fresh; otherwise fetches and caches. Each index is
  /// independent: one failing leaves the others (and its own last value).
  Future<IndexReading?> read({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    IndexReading? cached;
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        cached = IndexReading.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        cached = null;
      }
    }
    final now = _now();
    if (!force && cached != null && now.difference(cached.at) < _ttl)
      return cached;
    final client = _clientFactory();
    try {
      final ipca = await _ipca12m(client, now) ?? cached?.ipca12m;
      final selic = await _selic(client, now) ?? cached?.selic;
      final ptaxValue = await _ptax(client, now) ?? cached?.ptax;
      if (ipca == null && selic == null && ptaxValue == null) return cached;
      final reading =
          IndexReading(ipca12m: ipca, selic: selic, ptax: ptaxValue, at: now);
      await prefs.setString(_key, jsonEncode(reading.toJson()));
      return reading;
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, dynamic>>?> _series(
      http.Client client, int id, DateTime from, DateTime to) async {
    try {
      final r = await client
          .get(sgs(id, from, to))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static double? _num(Object? v) =>
      v == null ? null : double.tryParse(v.toString().replaceAll(',', '.'));

  /// Compound of the last 12 monthly IPCA readings.
  Future<double?> _ipca12m(http.Client client, DateTime now) async {
    final rows = await _series(
        client, 433, DateTime(now.year - 1, now.month - 1, 1), now);
    if (rows == null || rows.isEmpty) return null;
    final values =
        rows.map((r) => _num(r['valor'])).whereType<double>().toList();
    if (values.isEmpty) return null;
    final last12 =
        values.length > 12 ? values.sublist(values.length - 12) : values;
    var factor = 1.0;
    for (final v in last12) {
      factor *= 1 + v / 100;
    }
    return double.parse(((factor - 1) * 100).toStringAsFixed(2));
  }

  Future<double?> _selic(http.Client client, DateTime now) async {
    final rows =
        await _series(client, 432, now.subtract(const Duration(days: 20)), now);
    if (rows == null || rows.isEmpty) return null;
    return _num(rows.last['valor']);
  }

  /// Walks back up to 7 days to find the last business day with a rate.
  Future<double?> _ptax(http.Client client, DateTime now) async {
    for (var back = 0; back < 7; back++) {
      final day = now.subtract(Duration(days: back));
      try {
        final r =
            await client.get(ptax(day)).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) continue;
        final values = (jsonDecode(r.body) as Map)['value'] as List?;
        if (values == null || values.isEmpty) continue;
        final sale = _num((values.last as Map)['cotacaoVenda']);
        if (sale != null) return sale;
      } catch (_) {
        return null; // offline: do not try six more times
      }
    }
    return null;
  }
}
