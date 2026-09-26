import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/nexo_security.dart';

class SecurityGate extends StatefulWidget {
  final Widget child;
  const SecurityGate({super.key, required this.child});
  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<SecurityGate>
    with WidgetsBindingObserver {
  final security = NexoSecurity.instance;
  final pin = TextEditingController();
  bool away = false, busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    security.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    security.removeListener(refresh);
    pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      security.resume();
      away = false;
    } else {
      away = true;
      security.background();
      pin.clear();
    }
    refresh();
  }

  Future<void> unlock(bool device) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final ok = device
          ? await security.deviceAuth()
          : await security.verify(pin.text);
      pin.clear();
      if (!ok)
        message = security.retrySeconds > 0
            ? 'Aguarde ${security.retrySeconds}s ou use o desbloqueio do aparelho.'
            : 'Não foi possível desbloquear. Confira o PIN ou use o aparelho.';
    } catch (_) {
      message = 'Não foi possível acessar a proteção local. Tente novamente.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final blocked =
        !security.ready || security.locked || (away && security.enabled);
    return Stack(children: [
      Offstage(
          offstage: blocked,
          child: ExcludeSemantics(excluding: blocked, child: widget.child)),
      if (blocked)
        Positioned.fill(
            child: Material(
                child: Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                    child: SafeArea(child: Center(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 380),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.lock_outline, size: 48),
                                      const SizedBox(height: 16),
                                      Text('Nexo',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineLarge),
                                      const Text(
                                          'Desbloqueie para acessar suas finanças.'),
                                      const SizedBox(height: 24),
                                      if (security.storageError) ...[
                                        const Text(
                                            'Não foi possível ler a proteção local. Seus dados não foram apagados.'),
                                        TextButton(
                                            onPressed: security.load,
                                            child:
                                                const Text('Tentar novamente')),
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () async {
                                                    setState(() => busy = true);
                                                    final ok = await security
                                                        .recoverStorage();
                                                    if (mounted)
                                                      setState(() {
                                                        busy = false;
                                                        message = ok
                                                            ? null
                                                            : 'Não foi possível recuperar a proteção. Nenhum dado financeiro foi apagado.';
                                                      });
                                                  },
                                            child: const Text(
                                                'Recuperar com bloqueio do aparelho')),
                                        if (message != null) Text(message!),
                                      ] else if (security.ready && !away) ...[
                                        FilledButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () => unlock(true),
                                            icon: const Icon(Icons.fingerprint),
                                            label: const Text(
                                                'Biometria ou bloqueio do aparelho')),
                                        const SizedBox(height: 16),
                                        TextField(
                                            controller: pin,
                                            obscureText: true,
                                            enableSuggestions: false,
                                            autocorrect: false,
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                              LengthLimitingTextInputFormatter(
                                                  6)
                                            ],
                                            decoration: const InputDecoration(
                                                labelText:
                                                    'PIN do Nexo • 6 dígitos'),
                                            onSubmitted: (_) => unlock(false)),
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => unlock(false),
                                            child: const Text(
                                                'Desbloquear com PIN')),
                                        if (busy)
                                          const LinearProgressIndicator(),
                                        if (message != null) Text(message!),
                                        const Text(
                                            'Esqueceu o PIN? Use a autenticação do aparelho acima e defina um novo PIN em Segurança.',
                                            textAlign: TextAlign.center),
                                      ] else
                                        const CircularProgressIndicator(),
                                    ])))))))),
    ]);
  }
}
