import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/desktop_profile.dart';
import 'investment_quotes.dart';

class PricePoint {
  final DateTime date;
  final double price;
  const PricePoint(this.date, this.price);
}

class PriceHistory {
  final List<PricePoint> points;
  final DateTime fetchedAt;
  const PriceHistory(this.points, this.fetchedAt);
  factory PriceHistory.parse(List rows, DateTime fetchedAt) {
    if (rows.length > 150) throw const FormatException();
    final byDate = <int, PricePoint>{};
    for (final row in rows) {
      if (row is! Map) throw const FormatException();
      final seconds = row['date'];
      final price = row['adjustedClose'];
      // Never splice raw closes into an adjusted series.
      if (price == null) continue;
      if (seconds is! num ||
          !seconds.isFinite ||
          seconds != seconds.round() ||
          seconds < 0 ||
          seconds > fetchedAt.millisecondsSinceEpoch / 1000 + 86400 ||
          price is! num ||
          !price.isFinite ||
          price <= 0 ||
          price > 1000000) {
        throw const FormatException();
      }
      final date = DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000,
          isUtc: true);
      final key = seconds.toInt();
      if (byDate.containsKey(key) && byDate[key]!.price != price.toDouble()) {
        throw const FormatException();
      }
      byDate[key] = PricePoint(date, price.toDouble());
    }
    final sorted = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return PriceHistory(List.unmodifiable(sorted), fetchedAt);
  }
  List<PricePoint> window(int days) {
    if (points.isEmpty) return [];
    final from = points.last.date.subtract(Duration(days: days));
    return points.where((p) => !p.date.isBefore(from)).toList();
  }
}

class InvestmentHistory {
  final http.Client Function() clientFactory;
  final Duration timeout;
  InvestmentHistory(
      {http.Client Function()? clientFactory,
      this.timeout = const Duration(seconds: 15)})
      : clientFactory = clientFactory ?? http.Client.new;
  static String get _prefix =>
      DesktopProfile.isTest ? 'history_qa${DesktopProfile.qaSuffix}_' : 'history_';
  static Future<PriceHistory?> cached(String ticker) async {
    try {
      final text =
          (await SharedPreferences.getInstance()).getString('$_prefix$ticker');
      if (text == null || text.length > 40000) return null;
      final json = jsonDecode(text) as Map;
      return PriceHistory.parse(
          json['points'] as List, DateTime.parse(json['at'] as String));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String ticker, PriceHistory data) async {
    await (await SharedPreferences.getInstance()).setString(
        '$_prefix$ticker',
        jsonEncode({
          'at': data.fetchedAt.toUtc().toIso8601String(),
          'points': data.points
              .map((p) => {
                    'date': p.date.millisecondsSinceEpoch ~/ 1000,
                    'adjustedClose': p.price
                  })
              .toList(),
        }));
  }

  static Future<bool> claim(String ticker) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_prefix}attempt_$ticker';
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (prefs.getInt(key) ?? 0) <
        const Duration(minutes: 30).inMilliseconds) return false;
    await prefs.setInt(key, now);
    return true;
  }

  Future<PriceHistory> fetch(String ticker, {String? token}) =>
      InvestmentApiQueue.run(() async {
        if (!RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(ticker))
          throw const QuoteFailure('Código inválido.');
        final client = clientFactory();
        try {
          return await (() async {
            final request = http.Request(
                'GET',
                Uri.https('brapi.dev', '/api/v2/stocks/historical', {
                  'symbols': ticker,
                  'range': '3mo',
                  'interval': '1d',
                  'sortOrder': 'asc'
                }))
              ..followRedirects = false;
            if (token != null && token.isNotEmpty)
              request.headers['Authorization'] = 'Bearer $token';
            final response = await client.send(request);
            if (response.statusCode != 200)
              throw QuoteFailure(switch (response.statusCode) {
                400 ||
                401 ||
                403 =>
                  'Histórico indisponível para este ativo ou plano brapi.',
                429 => 'Limite da brapi atingido. Tente mais tarde.',
                _ =>
                  'Histórico indisponível. Os dados salvos foram preservados.',
              });
            final bytes = <int>[];
            await for (final chunk in response.stream) {
              if (bytes.length + chunk.length > 512 * 1024)
                throw const FormatException();
              bytes.addAll(chunk);
            }
            final json = jsonDecode(utf8.decode(bytes)) as Map;
            final rows = json['results'] as List;
            if (rows.length != 1) throw const FormatException();
            final row = rows.single as Map;
            if (row['symbol'] != ticker ||
                row['requestedSymbol'] != ticker ||
                row['changed'] != false) {
              throw const QuoteFailure(
                  'Código divergente no histórico. Revise o ativo.');
            }
            final data = row['data'] as Map;
            if (data['usedInterval'] != '1d') throw const FormatException();
            final history = PriceHistory.parse(
                data['historicalDataPrice'] as List, DateTime.now().toUtc());
            if (history.points.length < 2)
              throw const QuoteFailure(
                  'Ainda não há dois fechamentos ajustados disponíveis para este gráfico.');
            return history;
          })()
              .timeout(timeout);
        } on QuoteFailure {
          rethrow;
        } catch (_) {
          throw const QuoteFailure(
              'Não foi possível obter um histórico válido. Os dados salvos foram preservados.');
        } finally {
          client.close();
        }
      });
}
