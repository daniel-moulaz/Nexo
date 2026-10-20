import 'package:flutter/material.dart';

import '../sync/supabase_auth.dart';
import '../sync/supabase_sync_transport.dart';
import '../sync/sync_config.dart';
import '../sync/sync_lab_check.dart';
import '../sync/sync_protocol.dart' show SyncUnavailable;

/// Account and remote laboratory. Real synchronization of the ledger is not
/// activated here; the lab check only sends a fictitious dataset.
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key, this.config, this.auth});

  /// Overrides for tests; the app uses the build configuration.
  final SyncConfig? config;
  final SupabaseAuth? auth;

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  late final SyncConfig? _config = widget.config ?? SyncConfig.current;
  late final SupabaseAuth? _auth =
      widget.auth ?? (_config == null ? null : SupabaseAuth(_config));
  final _email = TextEditingController();
  final _code = TextEditingController();
  SyncSession? _session;
  bool _loading = true, _busy = false, _codeSent = false;
  String? _message;
  List<SyncLabStep>? _lab;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = await _auth?.session();
    if (mounted) {
      setState(() {
        _session = session;
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on SyncAuthException catch (e) {
      _message = e.message;
    } on SyncUnavailable {
      _message = 'Sem conexão com o servidor. Seus dados locais não mudam.';
    } catch (_) {
      _message = 'Não foi possível concluir agora. Tente novamente.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _requestCode() => _run(() async {
        await _auth!.requestCode(_email.text);
        _codeSent = true;
        _message =
            'E-mail enviado. Digite o código ou, se vier só um link, copie o link sem abrir e cole abaixo.';
      });

  Future<void> _verify() => _run(() async {
        _session = await _auth!.verifyCode(_email.text, _code.text);
        _code.clear();
        _codeSent = false;
      });

  Future<void> _signOut() => _run(() async {
        await _auth!.signOut();
        _session = null;
        _lab = null;
      });

  Future<void> _labCheck() => _run(() async {
        final config = _config!;
        _lab = await SyncLabCheck((device) => SupabaseSyncTransport(
              projectUrl: config.projectUrl,
              publishableKey: config.publishableKey,
              deviceId: device,
              accessToken: _auth!.accessToken,
            )).run();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronizar dispositivos')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'A sincronização dos seus dados ainda não está ativa. Nesta etapa você só entra na sua conta e pode testar o servidor com dados fictícios. Nada do seu Nexo é enviado.'),
          ),
        ),
        const SizedBox(height: 16),
        if (_config == null)
          const Text(
              'Esta versão foi gerada sem servidor configurado. O Nexo continua funcionando normalmente, só no aparelho.')
        else if (_loading)
          const LinearProgressIndicator()
        else if (_session == null)
          ..._signIn()
        else
          ..._signedIn(theme),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
              padding: const EdgeInsets.only(top: 12), child: Text(_message!)),
      ]),
    );
  }

  List<Widget> _signIn() => [
        Text('Entrar com e-mail',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Você recebe um código de uso único. O PIN do Nexo continua só neste aparelho e não é a senha da conta.'),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          enabled: !_busy && !_codeSent,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        const SizedBox(height: 12),
        if (!_codeSent)
          FilledButton(
              onPressed: _busy ? null : _requestCode,
              child: const Text('Enviar código'))
        else ...[
          TextField(
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.text,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
                labelText: 'Código ou link do e-mail',
                helperMaxLines: 3,
                helperText:
                    'Não abra o link: toque e segure (ou clique com o botão direito) e copie o endereço.'),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _busy ? null : _verify, child: const Text('Entrar')),
          TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                        _message = null;
                      }),
              child: const Text('Usar outro e-mail ou pedir novo código')),
        ],
      ];

  List<Widget> _signedIn(ThemeData theme) => [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Conta conectada'),
          subtitle: Text(_session!.email),
          trailing: TextButton(
              onPressed: _busy ? null : _signOut, child: const Text('Sair')),
        ),
        const Divider(),
        Text('Teste do servidor', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Cria um acervo fictício (conta "Banco fictício", valores inventados) e confere pela internet: gravação única, reenvio sem duplicar, dois aparelhos gastando da mesma conta, conflito, recebimento em ordem e revogação. Seus lançamentos não participam.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _busy ? null : _labCheck,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Testar servidor com dados fictícios')),
        if (_lab != null) ...[
          const SizedBox(height: 12),
          for (final step in _lab!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  step.passed ? Icons.check_circle : Icons.error_outline,
                  color: step.passed
                      ? Colors.green.shade700
                      : theme.colorScheme.error),
              title: Text(step.label),
              subtitle: step.detail == null ? null : Text(step.detail!),
            ),
          Text(_lab!.every((s) => s.passed)
              ? 'Servidor aprovado em todos os passos.'
              : 'Algum passo falhou. Nada foi alterado no seu Nexo.'),
        ],
      ];
}
