import '../providers/app_provider.dart';
import '../screens/home_customize_sheet.dart' show kHomeSections;
import '../services/envelopes.dart';

/// One app setting the assistant may read and change. [shared] settings
/// live in the synced ledger (same on every device); the others belong to
/// the device that applies the request, which reports them to the server.
class AssistantSetting {
  const AssistantSetting(this.key, this.label, this.kind,
      {this.shared = false, this.values = const []});
  final String key, label;

  /// bool, number, time, enum, string, currency, shares, goal_ids, cards.
  final String kind;
  final bool shared;
  final List<String> values;
}

/// The registry of settings. The server keeps the same list
/// (`supabase/functions/nexo-mcp/settings.ts`); a test compares them.
final assistantSettings = <AssistantSetting>[
  const AssistantSetting(
      'referenceIncome',
      'Renda de referência dos tipos de gasto (0: renda fixa do ciclo)',
      'number',
      shared: true),
  const AssistantSetting('envelopeShares',
      '% da renda de referência por tipo de gasto; soma 100', 'shares',
      shared: true),
  const AssistantSetting(
      'weekStart', 'Primeiro dia da semana dos orçamentos semanais', 'enum',
      shared: true, values: ['monday', 'sunday']),
  const AssistantSetting('lockedGoalIds',
      'Objetivos cujo dinheiro fica fora do saldo livre do Hoje', 'goal_ids',
      shared: true),
  const AssistantSetting(
      'budgetAlertsEnabled', 'Aviso quando um orçamento estoura', 'bool'),
  const AssistantSetting(
      'dailyReminderEnabled', 'Lembrete diário para lançar gastos', 'bool'),
  const AssistantSetting(
      'dailyReminderTime', 'Hora do lembrete diário (HH:mm)', 'time'),
  const AssistantSetting('hideBalance', 'Esconder valores na tela', 'bool'),
  AssistantSetting('themeMode', 'Tema claro, escuro ou do sistema', 'enum',
      values: AppSettings.validThemeModes.toList()),
  AssistantSetting('themeSeed', 'Cor do tema', 'enum',
      values: AppSettings.validSeeds.toList()),
  AssistantSetting('appFont', 'Fonte do app', 'enum',
      values: AppSettings.validFonts.toList()),
  const AssistantSetting(
      'amoledSurfaces', 'Fundo preto puro no tema escuro', 'bool'),
  const AssistantSetting(
      'dynamicColorEnabled', 'Cores do papel de parede (Android)', 'bool'),
  const AssistantSetting('hapticsEnabled', 'Vibração ao tocar', 'bool'),
  AssistantSetting('homeCards', 'Cartões visíveis do Hoje, em ordem', 'cards',
      values: kHomeSections.keys.toList()),
  const AssistantSetting('userName', 'Nome mostrado no app', 'string'),
  const AssistantSetting(
      'currency', 'Moeda principal (ISO, ex.: BRL)', 'currency'),
];

AssistantSetting? assistantSetting(String key) =>
    assistantSettings.where((s) => s.key == key).firstOrNull;

/// Checks [value] for [key] and returns it in the form the app stores.
/// Throws [ArgumentError] with a message the person can read.
Object validateAssistantSetting(String key, Object? value,
    {Set<String> goalIds = const {}}) {
  final def = assistantSetting(key) ??
      (throw ArgumentError('Configuração desconhecida: $key.'));
  Never bad(String why) => throw ArgumentError('$key: $why');
  switch (def.kind) {
    case 'bool':
      if (value is! bool) bad('use verdadeiro ou falso.');
      return value;
    case 'number':
      if (value is! num || !value.isFinite || value < 0 || value > 1e9) {
        bad('use um valor de 0 a 1 bilhão.');
      }
      return (value * 100).round() / 100;
    case 'time':
      if (value is! String ||
          !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
        bad('use HH:mm.');
      }
      return value;
    case 'enum':
      if (value is! String || !def.values.contains(value)) {
        bad('use ${def.values.join(', ')}.');
      }
      return value;
    case 'string':
      if (value is! String || value.trim().length > 60) bad('até 60 letras.');
      return value.trim();
    case 'currency':
      if (value is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
        bad('use o código de 3 letras, como BRL.');
      }
      return value;
    case 'shares':
      if (value is! Map) bad('informe a % de cada tipo.');
      final shares = <String, int>{};
      for (final def in envelopeDefs) {
        final v = value[def.id];
        if (v is! num || v != v.roundToDouble() || v < 0 || v > 100) {
          bad('${def.id} deve ser um inteiro de 0 a 100.');
        }
        shares[def.id] = v.toInt();
      }
      if (value.keys.any((k) => envelopeById(k as String?) == null)) {
        bad('tipos válidos: ${envelopeDefs.map((e) => e.id).join(', ')}.');
      }
      final total = shares.values.fold<int>(0, (s, v) => s + v);
      if (total != 100) bad('as porcentagens somam $total%, devem somar 100%.');
      return shares;
    case 'goal_ids':
      if (value is! List || value.any((v) => v is! String)) {
        bad('informe a lista de ids dos objetivos.');
      }
      final unknown = value.where((v) => !goalIds.contains(v));
      if (unknown.isNotEmpty) bad('objetivo não encontrado: ${unknown.first}.');
      return List<String>.from(value);
    case 'cards':
      if (value is! List ||
          value.isEmpty ||
          value.any((v) => !def.values.contains(v))) {
        bad('use uma lista não vazia com ${def.values.join(', ')}.');
      }
      return List<String>.from(value);
  }
  bad('tipo de configuração desconhecido.');
}
