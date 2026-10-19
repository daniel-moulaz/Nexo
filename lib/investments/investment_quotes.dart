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

class InvestmentQuote {
  final int priceMicros;
  final DateTime date;
  const InvestmentQuote(this.priceMicros, this.date);
}

/// Only sends a ticker. Never sends balances, quantities, operations or names.
class InvestmentQuotes {
  final http.Client Function() clientFactory;
  final Duration timeout;
  InvestmentQuotes(
      {http.Client Function()? clientFactory,
      this.timeout = const Duration(seconds: 15)})
      : clientFactory = clientFactory ?? http.Client.new;
  Future<InvestmentQuote> fetch(String ticker, {String? token}) async {
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
        return InvestmentQuote((price * 1000000).round(), date);
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
