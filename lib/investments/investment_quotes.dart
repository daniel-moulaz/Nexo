import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/desktop_profile.dart';

class QuoteFailure implements Exception {
  final String message;
  const QuoteFailure(this.message);
  @override
  String toString() => message;
}

/// The free plan accepts one concurrent request, including historical data.
class InvestmentApiQueue {
  static Future<void> _tail = Future<void>.value();
  static Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}

class InvestmentQuote {
  final int priceMicros;
  final DateTime date;
  final MarketSnapshot? market;
  const InvestmentQuote(this.priceMicros, this.date, {this.market});
}

/// Public market data only. Missing optional fields never invalidate a price.
class MarketSnapshot {
  final DateTime date;
  final Map<String, Object> fields;
  const MarketSnapshot(this.date, this.fields);
  static const numeric = [
    'regularMarketChange',
    'regularMarketChangePercent',
    'regularMarketOpen',
    'regularMarketPreviousClose',
    'regularMarketDayLow',
    'regularMarketDayHigh',
    'fiftyTwoWeekLow',
    'fiftyTwoWeekHigh',
    'regularMarketVolume',
    'marketCap',
  ];
  factory MarketSnapshot.parse(Map data, DateTime date) {
    final fields = <String, Object>{};
    for (final key in numeric) {
      final v = data[key];
      if (v is num &&
          v.isFinite &&
          v.abs() <= 1e16 &&
          (key.contains('Change') || v >= 0)) fields[key] = v;
    }
    final logo = data['logourl'];
    if (logo is String && logo.length < 512) {
      final uri = Uri.tryParse(logo);
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host == 'icons.brapi.dev' &&
          uri.userInfo.isEmpty &&
          uri.port == 443 &&
          uri.query.isEmpty &&
          uri.fragment.isEmpty &&
          RegExp(r'^/icons/[A-Za-z0-9_-]+\.svg$').hasMatch(uri.path)) {
        fields['logourl'] = logo;
      }
    }
    return MarketSnapshot(date, fields);
  }
  num? value(String key) => fields[key] is num ? fields[key] as num : null;
  String? get logo => fields['logourl'] as String?;
}

/// Rebuildable public cache, separate from financial backups and SQLite schema.
class MarketCache {
  static String get _prefix => DesktopProfile.isTest ? 'market_qa_' : 'market_';
  static Future<MarketSnapshot?> read(String ticker) async {
    try {
      final raw =
          (await SharedPreferences.getInstance()).getString('$_prefix$ticker');
      if (raw == null || raw.length > 8192) return null;
      final json = jsonDecode(raw) as Map;
      return MarketSnapshot.parse(
          json['fields'] as Map, DateTime.parse(json['date'] as String));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String ticker, MarketSnapshot snapshot) async {
    final old = await read(ticker);
    if (old != null && old.date.isAfter(snapshot.date)) return;
    await (await SharedPreferences.getInstance()).setString(
        '$_prefix$ticker',
        jsonEncode({
          'date': snapshot.date.toUtc().toIso8601String(),
          'fields': snapshot.fields
        }));
  }
}

/// Only sends a ticker. Never sends balances, quantities, operations or names.
class InvestmentQuotes {
  final http.Client Function() clientFactory;
  final Duration timeout;
  InvestmentQuotes(
      {http.Client Function()? clientFactory,
      this.timeout = const Duration(seconds: 15)})
      : clientFactory = clientFactory ?? http.Client.new;
  Future<InvestmentQuote> fetch(String ticker, {String? token}) =>
      InvestmentApiQueue.run(() => _fetch(ticker, token: token));
  Future<InvestmentQuote> _fetch(String ticker, {String? token}) async {
    if (!RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(ticker)) {
      throw const QuoteFailure('Código do ativo inválido.');
    }
    final client = clientFactory();
    try {
      return await (() async {
        final request = http.Request('GET',
            Uri.https('brapi.dev', '/api/v2/stocks/quote', {'symbols': ticker}))
          ..followRedirects = false;
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw QuoteFailure(switch (response.statusCode) {
            401 ||
            403 =>
              'Este ativo exige uma chave válida e cobertura no seu plano brapi.',
            429 => 'Limite da brapi atingido. Aguarde antes de atualizar.',
            _ => 'Cotação indisponível. O último valor foi preservado.'
          });
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 128 * 1024) {
            throw const QuoteFailure('Resposta de cotação inválida.');
          }
          bytes.addAll(chunk);
        }
        final json = jsonDecode(utf8.decode(bytes)) as Map;
        final results = json['results'] as List;
        if (results.length != 1) throw const FormatException();
        final row = results.single as Map;
        if (row['symbol'] != ticker ||
            row['requestedSymbol'] != ticker ||
            row['changed'] != false) {
          throw const QuoteFailure(
              'Código do ativo alterado ou divergente. Revise antes de atualizar.');
        }
        final data = row['data'] as Map;
        final price = data['regularMarketPrice'] as num;
        final date = DateTime.parse(data['regularMarketTime'] as String);
        if (data['currency'] != 'BRL' ||
            !price.isFinite ||
            price <= 0 ||
            price > 1000000 ||
            date.isAfter(
                DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
          throw const FormatException();
        }
        return InvestmentQuote((price * 1000000).round(), date,
            market: MarketSnapshot.parse(data, date));
      })()
          .timeout(timeout);
    } on QuoteFailure {
      rethrow;
    } catch (_) {
      throw const QuoteFailure(
          'Não foi possível obter uma cotação válida. Seu último valor foi preservado.');
    } finally {
      client.close();
    }
  }
}

class InvestmentQuoteSettings {
  static String get _key =>
      DesktopProfile.isTest ? 'nexo_quotes_qa' : 'nexo_quotes';
  static const storage = FlutterSecureStorage();
  static Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool('${_key}_enabled') ??
      false;
  static Future<String?> token() => storage.read(key: '${_key}_token');
  static Future<void> configure(
      {required bool enabled, required String token}) async {
    if (token.trim().isEmpty) {
      await storage.delete(key: '${_key}_token');
    } else {
      await storage.write(key: '${_key}_token', value: token.trim());
    }
    await (await SharedPreferences.getInstance())
        .setBool('${_key}_enabled', enabled);
  }

  static Future<bool> claimRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt('${_key}_last_attempt') ?? 0;
    if (now - last < const Duration(minutes: 15).inMilliseconds) return false;
    await prefs.setInt('${_key}_last_attempt', now);
    return true;
  }
}
