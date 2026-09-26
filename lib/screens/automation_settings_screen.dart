import 'package:flutter/material.dart';
import '../services/notification_inbox.dart';
import 'notification_inbox_screen.dart';

class AutomationSettingsScreen extends StatefulWidget {
  const AutomationSettingsScreen({super.key});
  @override
  State<AutomationSettingsScreen> createState() =>
      _AutomationSettingsScreenState();
}

class _AutomationSettingsScreenState extends State<AutomationSettingsScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> status = {};
  List<Map<String, dynamic>> apps = [];
  Set<String> selected = {};
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    try {
      final s = Map<String, dynamic>.from(
          await NotificationInbox.channel.invokeMethod('status'));
      final list =
          (await NotificationInbox.channel.invokeListMethod('apps') ?? [])
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
      list.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
      if (mounted)
        setState(() {
          status = s;
          selected = (s['apps'] as List).cast<String>().toSet();
          apps = list;
          busy = false;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error =
              'Este recurso precisa do Android. Não foi possível consultar o acesso.';
        });
    }
  }

  Future<void> save(bool enabled) async {
    setState(() => busy = true);
    try {
      await NotificationInbox.channel.invokeMethod(
          'configure', {'enabled': enabled, 'apps': selected.toList()});
      await load();
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error = 'Não foi possível salvar. Tente novamente.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Automação')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'O Nexo pode analisar notificações dos aplicativos escolhidos para sugerir lançamentos. O processamento é feito localmente.'),
        const SizedBox(height: 8),
        const Text(
            'O Android concede acesso amplo às notificações. O Nexo filtra pelos apps abaixo antes de ler o conteúdo. Não solicita senha bancária, não abre o banco e nunca salva um lançamento sozinho.'),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Detectar notificações financeiras'),
            value: status['enabled'] == true,
            onChanged: busy ? null : save),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Acesso no Android'),
            subtitle: Text(
                status['access'] == true ? 'Autorizado' : 'Não autorizado'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => NotificationInbox.channel.invokeMethod('settings')),
        if (status['enabled'] == true && status['access'] != true)
          const Text(
              'A detecção está pausada. Autorize o acesso no Android para receber sugestões.'),
        if (status['error'] == true)
          const Text(
              'Uma sugestão não pôde ser armazenada com segurança. Abra novamente o Nexo e confira a proteção do aparelho.'),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sugestões de lançamentos'),
            trailing: const Icon(Icons.inbox_outlined),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationInboxScreen()))),
        const Divider(),
        const Text(
            'Apps permitidos • selecione apenas bancos e carteiras de sua confiança'),
        const Text(
            'A lista usa os nomes e identificadores instalados no aparelho. Nenhum app vem selecionado.'),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        for (final app in apps)
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(app['name']),
              subtitle: Text(app['id']),
              value: selected.contains(app['id']),
              onChanged: busy
                  ? null
                  : (v) {
                      if (v == true) {
                        selected.add(app['id']);
                      } else {
                        selected.remove(app['id']);
                      }
                      save(status['enabled'] == true);
                    }),
      ]));
}
