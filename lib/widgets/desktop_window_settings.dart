import 'package:flutter/material.dart';

import '../services/desktop_window.dart';

/// Keeps the app working with no window, for the assistant's requests.
class DesktopWindowSettings extends StatefulWidget {
  const DesktopWindowSettings({super.key});
  @override
  State<DesktopWindowSettings> createState() => _DesktopWindowSettingsState();
}

class _DesktopWindowSettingsState extends State<DesktopWindowSettings> {
  bool? _tray, _startup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tray = await DesktopWindow.keepInTray();
    final startup = await DesktopWindow.startsWithWindows();
    if (mounted) {
      setState(() {
        _tray = tray;
        _startup = startup;
      });
    }
  }

  Future<void> _setStartup(bool on) async {
    final done = await DesktopWindow.setStartWithWindows(on);
    if (!mounted) return;
    if (done) {
      setState(() => _startup = on);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O Windows não aceitou a mudança. Tente de novo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(children: [
          SwitchListTile.adaptive(
              secondary: Icon(Icons.keyboard_hide_outlined, color: cs.primary),
              title: const Text('Continuar perto do relógio ao fechar'),
              subtitle: const Text(
                  'O Nexo segue gravando os pedidos do Claude sem janela aberta. Para sair, use o ícone.'),
              value: _tray ?? true,
              onChanged: _tray == null
                  ? null
                  : (on) async {
                      await DesktopWindow.setKeepInTray(on);
                      if (mounted) setState(() => _tray = on);
                    }),
          const Divider(height: 1, indent: 56),
          SwitchListTile.adaptive(
              secondary: Icon(Icons.power_settings_new, color: cs.primary),
              title: const Text('Iniciar com o Windows'),
              subtitle: const Text(
                  'Abre sem janela, perto do relógio. A tela de bloqueio continua valendo.'),
              value: _startup ?? false,
              onChanged: _startup == null ? null : _setStartup),
        ]));
  }
}
