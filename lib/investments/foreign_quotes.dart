import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sync/supabase_auth.dart';
import '../sync/sync_config.dart';
import 'investment_history.dart';
import 'investment_quotes.dart';

/// Quotes outside the B3 (US stocks and ETFs), read by the Nexo server so the
/// data provider key never reaches the device. Only tickers are sent.
abstract interface class ForeignQuoteSource {
  /// One quote per ticker it found; a ticker it did not find is left out.
  Future<Map<String, InvestmentQuote>> fetch(Set<String> tickers);
}

/// Daily closes kept by the Nexo server (US stocks have no free history).
abstract interface class ForeignHistorySource {
  Future<PriceHistory> history(String ticker);
}

class SupabaseForeignQuotes
    implements ForeignQuoteSource, ForeignHistorySource {
  SupabaseForeignQuotes(this.config, this.auth,
      {http.Client Function()? clientFactory,
      this.timeout = const Duration(seconds: 20)})
      : _clientFactory = clientFactory ?? http.Client.new;
  final SyncConfig config;
  final SupabaseAuth auth;
  final Duration timeout;
  final http.Client Function() _clientFactory;

  static ForeignQuoteSource? instance;

  static final _ticker = RegExp(r'^[A-Z0-9][A-Z0-9.\-]{0,11}$');

  Future<Object?> _post(Map<String, Object?> body) async {
    final token = await auth.accessToken();
    if (token == null) {
      throw const QuoteFailure(
          'Cotação dos EUA: entre na sua conta em Sincronizar dispositivos.');
    }
    final client = _clientFactory();
    try {
      final response = await client
          .post(config.projectUrl.resolve('/functions/v1/market-quotes'),
              headers: {
                'apikey': config.publishableKey,
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body))
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw QuoteFailure(switch (response.statusCode) {
          404 => 'Cotação dos EUA ainda não publicada no servidor.',
          503 when body.containsKey('history') =>
            'Histórico dos EUA ainda não publicado no servidor.',
          503 => 'Cotação dos EUA sem chave configurada no servidor.',
          429 =>
            'Limite de cotações dos EUA atingido. Tente em alguns minutos.',
          401 || 403 => 'Cotação dos EUA: entre de novo na sua conta.',
          _ => 'Cotação dos EUA indisponível. O último valor foi preservado.'
        });
      }
      if (response.bodyBytes.length > 64 * 1024) {
        throw const FormatException();
      }
      return jsonDecode(response.body);
    } on QuoteFailure {
      rethrow;
    } catch (_) {
      throw const QuoteFailure(
          'Não foi possível obter a cotação dos EUA. O último valor foi preservado.');
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, InvestmentQuote>> fetch(Set<String> tickers) async {
    final asked = tickers.where(_ticker.hasMatch).take(20).toList();
    if (asked.isEmpty) return {};
    final body = await _post({'symbols': asked});
    try {
      return parse(body, asked.toSet(), DateTime.now());
    } catch (_) {
      throw const QuoteFailure(
          'Não foi possível obter a cotação dos EUA. O último valor foi preservado.');
    }
  }

  @override
  Future<PriceHistory> history(String ticker) async {
    if (!_ticker.hasMatch(ticker)) throw const QuoteFailure('Código inválido.');
    final body = await _post({'history': ticker});
    try {
      return parseHistory(body, ticker, DateTime.now());
    } catch (_) {
      throw const QuoteFailure('Histórico dos EUA em formato inesperado.');
    }
  }

  /// The server's closes ({day, close_micros}) for [ticker], oldest first.
  static PriceHistory parseHistory(Object? body, String ticker, DateTime now) {
    if (body is! Map || body['symbol'] != ticker) throw const FormatException();
    final rows = body['points'];
    if (rows is! List || rows.length > 400) throw const FormatException();
    final points = <PricePoint>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final day = DateTime.tryParse('${row['day']}');
      final c = row['close_micros'];
      if (day == null || c is! num || c <= 0 || c > 1000000000000) continue;
      // Noon UTC of the market day: the same date in Brazil and New York.
      final at = DateTime.utc(day.year, day.month, day.day, 12);
      if (at.isAfter(now.toUtc().add(const Duration(days: 1)))) continue;
      points.add(PricePoint(at, c / 1000000));
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return PriceHistory(List.unmodifiable(points), now);
  }

  /// Keeps only a positive dollar price for a ticker that was asked for,
  /// dated no later than a few minutes from now.
  static Map<String, InvestmentQuote> parse(
      Object? body, Set<String> asked, DateTime now) {
    final out = <String, InvestmentQuote>{};
    final rows = body is Map ? body['quotes'] : null;
    if (rows is! List) throw const FormatException();
    for (final row in rows) {
      if (row is! Map) continue;
      final symbol = row['symbol'], price = row['price'], time = row['time'];
      if (symbol is! String ||
          !asked.contains(symbol) ||
          row['currency'] != 'USD' ||
          price is! num ||
          !price.isFinite ||
          price <= 0 ||
          price > 1000000 ||
          time is! String) {
        continue;
      }
      final at = DateTime.tryParse(time);
      if (at == null ||
          at.isAfter(now.toUtc().add(const Duration(minutes: 5)))) {
        continue;
      }
      out[symbol] = InvestmentQuote((price * 1000000).round(), at);
    }
    return out;
  }
}
