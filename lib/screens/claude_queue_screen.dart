import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/platform_capabilities.dart';
import '../sync/assistant_commands.dart';
import '../sync/claude_queue.dart';
import '../widgets/desktop_window_settings.dart';
import '../widgets/nexo_ui.dart';

/// "Fila do Claude": what is waiting on the server, when each device last
/// looked, and what lets the phone record with the app closed.
class ClaudeQueueScreen extends StatefulWidget {
  const ClaudeQueueScreen(
      {super.key,
      required this.load,
      this.thisDevice,
      this.checkNow,
      this.android});

  /// The server's view; null when the server lacks the 1.17.0 migration.
  final Future<QueueStatus?> Function() load;
  final String? thisDevice;

  /// One sync pass now (claims and applies what is waiting).
  final Future<void> Function()? checkNow;

  /// Overrides the platform, for tests.
  final bool? android;

  @override
  State<ClaudeQueueScreen> createState() => _ClaudeQueueScreenState();
}

class _ClaudeQueueScreenState extends State<ClaudeQueueScreen> {
  late Future<QueueStatus?> _status = widget.load();
  QueueCheck? _last, _lastApplied;
  bool? _enabled, _notify, _push;
  ({bool unrestricted, bool xiaomi})? _battery;
  bool _busy = false;

  bool get _android => widget.android ?? ClaudeQueue.supported;

  @override
  void initState() {
    super.initState();
    _local();
  }

  Future<void> _local() async {
    final last = await ClaudeQueue.last();
    final applied = await ClaudeQueue.lastApplied();
    final enabled = await ClaudeQueue.enabled();
    final notify = await ClaudeQueue.notifies();
    final push = _android ? await ClaudeQueue.pushConfigured() : false;
    final battery = _android ? await ClaudeQueue.battery() : null;
    if (!mounted) return;
    setState(() {
      _last = last;
      _lastApplied = applied;
      _enabled = enabled;
      _notify = notify;
      _push = push;
      _battery = battery;
    });
  }

  Future<void> _refresh() async {
    setState(() => _status = widget.load());
    await _status;
    await _local();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await widget.checkNow?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
  }

  static String _when(DateTime? t) {
    if (t == null) return 'nunca';
    final now = DateTime.now();
    final minutes = now.difference(t).inMinutes;
    if (minutes < 1) return 'agora há pouco';
    if (minutes < 60) return 'há $minutes min';
    final sameDay =
        now.year == t.year && now.month == t.month && now.day == t.day;
    return sameDay
        ? 'hoje às ${DateFormat('HH:mm').format(t)}'
        : DateFormat("dd/MM 'às' HH:mm").format(t);
  }

  Widget _summary(QueueStatus? s, ThemeData theme) {
    final String title, detail;
    final IconData icon;
    final Color tone;
    if (s == null) {
      title = 'Fila no servidor indisponível';
      detail =
          'O servidor ainda não tem a atualização da fila (1.17.0). Os pedidos continuam sendo gravados como antes.';
      icon = Icons.cloud_off_outlined;
      tone = theme.colorScheme.onSurfaceVariant;
    } else if (s.pending == 0) {
      title = 'Nenhum pedido esperando';
      detail = s.lastDoneAt == null
          ? 'Quando o Claude pedir algo, aparece aqui até ser gravado.'
          : 'Último pedido gravado ${_when(s.lastDoneAt)}.';
      icon = Icons.check_circle_outline;
      tone = theme.colorScheme.primary;
    } else if (s.waitingForUpdate > 0) {
      title = s.pending == 1
          ? '1 pedido esperando atualização'
          : '${s.pending} pedidos esperando atualização';
      detail =
          'Um pedido precisa de uma versão mais nova do Nexo do que a dos aparelhos. Ele não é gravado errado: espera até um aparelho atualizado abrir.';
      icon = Icons.system_update_outlined;
      tone = NexoTones.warning(context);
    } else {
      title =
          s.pending == 1 ? '1 pedido na fila' : '${s.pending} pedidos na fila';
      detail = 'Esperando ${_when(s.oldestPendingAt)}.';
      icon = Icons.schedule;
      tone = NexoTones.info(context);
    }
    return NexoCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: tone, size: 28),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(detail, style: theme.textTheme.bodyMedium),
      ])),
    ]));
  }

  List<Widget> _devices(QueueStatus? s, ThemeData theme) {
    final devices = s?.devices ?? const <QueueDevice>[];
    if (devices.isEmpty) return const [];
    return [
      const NexoSectionTitle('Aparelhos'),
      for (final d in devices)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(d.id == widget.thisDevice
              ? Icons.smartphone
              : Icons.devices_other_outlined),
          title: Text(d.id == widget.thisDevice
              ? 'Este aparelho · ${d.version}'
              : 'Outro aparelho · ${d.version}'),
          subtitle: Text([
            'Conferiu a fila ${_when(d.checkedAt)}',
            if (d.push) 'acorda com o aviso do servidor',
          ].join(' · ')),
        ),
    ];
  }

  List<Widget> _thisDevice(ThemeData theme) => [
        const NexoSectionTitle('Neste aparelho'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.update),
          title: Text('Última conferência: ${_when(_last?.at)}'),
          subtitle: Text(_last == null
              ? 'Ainda não conferiu desde a atualização.'
              : [
                  _last!.sourceLabel,
                  if (!_last!.ok) 'sem conexão naquela hora',
                  if (_lastApplied != null)
                    'último gravado ${_when(_lastApplied!.at)} (${_lastApplied!.sourceLabel})',
                ].join(' · ')),
        ),
      ];

  List<Widget> _background(ThemeData theme) {
    if (!_android) {
      if (!PlatformCapabilities.windows) return const [];
      return [
        const NexoSectionTitle('No PC'),
        const Text(
            'Com o Nexo na bandeja, o PC confere a fila a cada 20 segundos, mesmo com a janela fechada. Ligue "Iniciar com o Windows" para isso continuar depois de reiniciar.'),
        const SizedBox(height: 8),
        const DesktopWindowSettings(),
      ];
    }
    final battery = _battery;
    return [
      const NexoSectionTitle('Com o app fechado'),
      SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Gravar pedidos com o app fechado'),
          subtitle: Text(_push == true
              ? 'O servidor avisa este celular na hora; além disso, ele confere a cada 15 minutos.'
              : 'O celular confere a fila a cada 15 minutos. O aviso instantâneo do servidor não está configurado nesta versão.'),
          value: _enabled ?? true,
          onChanged: _enabled == null
              ? null
              : (on) async {
                  await ClaudeQueue.setEnabled(on);
                  setState(() => _enabled = on);
                }),
      SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Avisar quando gravar'),
          subtitle: const Text(
              'Uma notificação discreta, sem valores, quando algo for gravado com o app fechado.'),
          value: _notify ?? true,
          onChanged: _notify == null || _enabled == false
              ? null
              : (on) async {
                  await ClaudeQueue.setNotifies(on);
                  setState(() => _notify = on);
                }),
      if (battery != null && !battery.unrestricted)
        NexoCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('A economia de bateria pode atrasar',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(battery.xiaomi
              ? 'No Xiaomi, libere a bateria do Nexo ("Sem restrições") e ligue o "Início automático". Sem isso, o sistema pode segurar a checagem por horas.'
              : 'Libere a bateria do Nexo para o Android não segurar a checagem.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(
                onPressed: () async {
                  await ClaudeQueue.openBattery();
                },
                child: const Text('Liberar bateria')),
            if (battery.xiaomi)
              OutlinedButton(
                  onPressed: () async {
                    if (!await ClaudeQueue.openAutostart()) {
                      await ClaudeQueue.openBattery();
                    }
                  },
                  child: const Text('Início automático')),
          ]),
        ]))
      else if (battery != null && battery.xiaomi)
        const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
                'Bateria liberada. No Xiaomi, confira também o "Início automático" do Nexo.')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fila do Claude')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<QueueStatus?>(
          future: _status,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final s = snapshot.hasError ? null : snapshot.data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (snapshot.hasError)
                  const NexoCard(
                      child: Text(
                          'Não foi possível falar com o servidor agora. Confira a conexão e puxe para atualizar.'))
                else
                  _summary(s, theme),
                const SizedBox(height: 8),
                if (widget.checkNow != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                        onPressed: _busy ? null : _check,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync),
                        label: const Text('Conferir agora')),
                  ),
                ..._thisDevice(theme),
                ..._devices(s, theme),
                ..._background(theme),
              ],
            );
          },
        ),
      ),
    );
  }
}
