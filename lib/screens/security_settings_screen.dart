import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/nexo_security.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final security = NexoSecurity.instance;
  bool busy = false;
  String? message;
  Future<String?> askPin(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6)
                    ],
                    decoration: const InputDecoration(labelText: '6 dígitos')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, ctrl.text),
                      child: const Text('Continuar'))
                ]));
    // Dialog transition may still use the controller; disposal follows route removal.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    ctrl.dispose();
    return result;
  }

  Future<bool> authorize() async {
    if (await security.deviceAuth()) return true;
    if (!mounted || !security.enabled) return false;
    final pin = await askPin('Confirme o PIN atual');
    return pin != null && await security.verify(pin);
  }

  Future<void> changePin() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (!await authorize()) {
        message =
            'Configure o bloqueio do aparelho no Android para ter uma recuperação segura. Nenhum dado foi apagado.';
        return;
      }
      if (!mounted) return;
      final pin = await askPin('Definir PIN do Nexo');
      if (pin == null) return;
      if (!PinVerifier.valid(pin)) {
        message = 'Use exatamente 6 dígitos.';
        return;
      }
      if (!mounted) return;
      final confirmation = await askPin('Repita o PIN');
      if (pin != confirmation) {
        message = 'Os PINs não coincidem.';
        return;
      }
      await security.setPin(pin);
      message =
          'Bloqueio ativado. Guarde seu PIN; a autenticação do aparelho é a alternativa de recuperação.';
    } catch (_) {
      message = 'Não foi possível salvar a proteção local.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disable() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (await authorize()) await security.configure(enabled: false);
    } catch (_) {
      message = 'Não foi possível alterar a proteção.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> configure({int? timeout, bool? recents, bool? capture}) async {
    try {
      await security.configure(
          timeout: timeout, recents: recents, capture: capture);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted)
        setState(() => message = 'Não foi possível salvar a preferência.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Segurança')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Bloqueio do Nexo',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text(
            'Biometria ou bloqueio do Android, com PIN de 6 dígitos do Nexo como alternativa. Segredos ficam protegidos no aparelho e não entram no backup financeiro.'),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(security.enabled ? 'Alterar PIN' : 'Ativar bloqueio'),
            trailing: const Icon(Icons.lock_outline),
            onTap: busy ? null : changePin),
        if (security.enabled) ...[
          DropdownButtonFormField<int>(
              initialValue: security.timeout,
              decoration:
                  const InputDecoration(labelText: 'Bloquear ao voltar após'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Imediatamente')),
                DropdownMenuItem(value: 30, child: Text('30 segundos')),
                DropdownMenuItem(value: 60, child: Text('1 minuto')),
                DropdownMenuItem(value: 300, child: Text('5 minutos'))
              ],
              onChanged: busy ? null : (v) => configure(timeout: v)),
          TextButton(
              onPressed: busy ? null : security.lock,
              child: const Text('Bloquear agora')),
          TextButton(
              onPressed: busy ? null : disable,
              child: const Text('Desativar bloqueio')),
        ],
        const Divider(),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ocultar conteúdo nos aplicativos recentes'),
            subtitle: const Text(
                'Disponível no Android 13 ou superior. Não impede screenshots.'),
            value: security.hideRecents,
            onChanged: busy ? null : (v) => configure(recents: v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bloquear capturas de tela'),
            subtitle: const Text(
                'Opcional. Também impede gravação e compartilhamento da tela.'),
            value: security.blockCapture,
            onChanged: busy ? null : (v) => configure(capture: v)),
        const Text(
            'Esqueceu o PIN? Desbloqueie com a autenticação do aparelho e defina um novo PIN aqui. Se perder também esse acesso, não há recuperação secreta pelo Nexo. Reinstalar pode apagar dados: mantenha um backup financeiro seguro.'),
        if (busy) const LinearProgressIndicator(),
        if (message != null) Text(message!),
      ]));
}
