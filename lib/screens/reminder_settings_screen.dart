import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/financial_reminders.dart';
import '../services/notification_service.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});
  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  Map<String, dynamic>? prefs;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await FinancialReminders.instance.preferences();
    if (mounted) setState(() => prefs = p);
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await FinancialReminders.instance
          .save(prefs!, context.read<AppProvider>());
      error = FinancialReminders.instance.lastError;
    } catch (_) {
      error = 'Não foi possível salvar os lembretes.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('Notificações')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Lembretes discretos, sem valores ou estabelecimentos na notificação. São atualizados quando você abre o Nexo ou altera seus dados. O Android pode atrasar a entrega para economizar bateria.'),
          TextButton.icon(
              onPressed: () async {
                final ok = await NotificationService().requestPermissions();
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Notificações autorizadas.'
                          : 'Notificações não autorizadas no Android.')));
              },
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Autorizar notificações')),
          if (prefs == null)
            const LinearProgressIndicator()
          else ...[
            for (final e in const {
              'bills': 'Contas a vencer',
              'income': 'Receitas previstas',
              'recurring': 'Recorrentes',
              'closing': 'Fechamento de cartão',
              'invoice': 'Vencimento de fatura',
              'forecast': 'Saldo previsto negativo em 7 dias'
            }.entries)
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: prefs![e.key] == true,
                  onChanged: busy
                      ? null
                      : (v) {
                          prefs![e.key] = v;
                          save();
                        }),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Orçamento'),
                value: app.settings.budgetAlertsEnabled,
                onChanged: busy
                    ? null
                    : (v) => app.updateSetting('budgetAlertsEnabled', v)),
            const Text('Contas e faturas • avisar às 9h'),
            Wrap(spacing: 8, children: [
              for (final days in [3, 1, 0])
                FilterChip(
                    label: Text(days == 0
                        ? 'No dia'
                        : '$days dia${days == 1 ? '' : 's'} antes'),
                    selected: (prefs!['days'] as List).contains(days),
                    onSelected: busy
                        ? null
                        : (v) {
                            final list = List<int>.from(prefs!['days']);
                            v ? list.add(days) : list.remove(days);
                            prefs!['days'] = list;
                            save();
                          })
            ]),
            const SizedBox(height: 12),
            const Text(
                'Recorrentes: ative também o lembrete no cadastro de cada recorrente. O horário escolhido lá é preservado. Só a próxima ocorrência é lembrada. Pagar ou receber cancela o aviso correspondente. Faturas quitadas não geram lembrete de dívida.'),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
          ],
        ]));
  }
}
