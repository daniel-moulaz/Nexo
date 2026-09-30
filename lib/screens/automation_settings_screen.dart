import 'package:flutter/material.dart';
import '../services/notification_inbox.dart';
import 'notification_inbox_screen.dart';
import '../services/notification_service.dart';
import '../services/notification_preferences.dart';
import 'import_rules_screen.dart';

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
  static const reasons = {
    'none': 'Nenhuma notificação observada ainda',
    'created': 'Sugestão criada para revisão',
    'duplicate': 'Evento duplicado',
    'unrecognized': 'Formato não reconhecido',
    'multiple_amounts': 'Múltiplos valores; revisão ambígua',
    'not_financial': 'Evento não confirmado ou não financeiro',
    'sensitive': 'Conteúdo sensível descartado',
    'balance_or_invoice': 'Saldo, limite ou fatura; não é consumo confirmado',
    'app_not_allowed': 'App não autorizado; conteúdo não lido',
    'group_summary': 'Resumo agrupado ignorado',
    'old': 'Notificação antiga ou horário inválido',
    'queue_error': 'Não foi possível guardar a sugestão com segurança',
  };

  Future<void> notifyReview(bool enabled) async {
    setState(() => busy = true);
    try {
      if (enabled) await NotificationService().requestPermissions();
      await NotificationInbox.channel
          .invokeMethod('notifyReview', {'enabled': enabled});
      await load();
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error = 'Não foi possível configurar o aviso. Tente novamente.';
        });
    }
  }

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
        if (status['enabled'] == true && status['access'] != true) ...[
          const Text(
              'A detecção está pausada. Autorize o acesso no Android para receber sugestões.'),
          const SizedBox(height: 8),
          const Text(
              'Se aparecer “configurações restritas”, abra Configurações > Apps > Nexo > menu ⋮ > Permitir configurações restritas. Depois volte ao acesso às notificações e ative o Nexo.'),
        ],
        if (status['error'] == true)
          const Text(
              'Uma sugestão não pôde ser armazenada com segurança. Abra novamente o Nexo e confira a proteção do aparelho.'),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Avisar quando houver compra para revisar'),
            subtitle: const Text(
                'Aviso discreto, sempre sem valor ou estabelecimento. Nunca registra sozinho.'),
            value: status['notifyReview'] == true,
            onChanged: busy ? null : notifyReview),
        if (status['notifyReview'] == true &&
            status['notificationsAllowed'] != true)
          const Text(
              'O Android bloqueou os avisos do Nexo. As sugestões continuam disponíveis na caixa de revisão.'),
        Card(
            child: ExpansionTile(
                title: const Text('Diagnóstico'),
                subtitle:
                    Text(reasons[status['lastResult']] ?? reasons['none']!),
                children: [
              ListTile(
                  title: const Text('Automação'),
                  subtitle:
                      Text(status['enabled'] == true ? 'Ativa' : 'Desativada')),
              ListTile(
                  title: const Text('Apps permitidos'),
                  subtitle: Text(selected.isEmpty
                      ? 'Nenhum; selecione abaixo'
                      : selected
                          .map((id) =>
                              apps
                                  .where((a) => a['id'] == id)
                                  .firstOrNull?['name'] ??
                              NotificationInbox.knownApps[id] ??
                              id)
                          .join(', '))),
              ListTile(
                  title: const Text('Último evento observado'),
                  subtitle: Text((status['lastAnalyzed'] as num? ?? 0) == 0
                      ? 'Ainda não observado'
                      : 'Há ${DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch((status['lastAnalyzed'] as num).toInt())).inMinutes.clamp(0, 999999)} min')),
              ListTile(
                  title: const Text('Resultado'),
                  subtitle:
                      Text(reasons[status['lastResult']] ?? reasons['none']!)),
              if (status['confidence'] == 'high' ||
                  status['confidence'] == 'medium')
                ListTile(
                    title: const Text('Confiança do padrão'),
                    subtitle: Text(status['confidence'] == 'high'
                        ? 'Alta • evento explícito'
                        : 'Média • confirme a natureza da operação')),
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Somente horário e motivo genérico são guardados no diagnóstico. Nenhum texto, valor, senha ou código é armazenado aqui. O formato dos bancos pode mudar.')),
              TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('Atualizar diagnóstico')),
            ])),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sugestões de lançamentos'),
            trailing: const Icon(Icons.inbox_outlined),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationInboxScreen()))),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Regras de categoria'),
            subtitle:
                const Text('Regras locais para notificações e importações'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ImportRulesScreen()))),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Esquecer contas sugeridas'),
            subtitle: const Text(
                'Remove apenas as escolhas lembradas neste aparelho'),
            onTap: () async {
              await NotificationPreferences.clear();
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Associações removidas.')));
            }),
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
