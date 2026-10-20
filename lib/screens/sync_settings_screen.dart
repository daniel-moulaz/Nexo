import 'package:flutter/material.dart';

import '../sync/supabase_auth.dart';
import '../sync/supabase_sync_transport.dart';
import '../sync/sync_config.dart';
import '../sync/sync_lab_check.dart';
import '../sync/sync_protocol.dart' show SyncUnavailable;
import '../sync/sync_controller.dart';
import '../services/desktop_profile.dart';
import 'package:intl/intl.dart';

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
  late final SupabaseAuth? _auth = widget.auth ??
      SupabaseAuth.app ??
      (_config == null ? null : SupabaseAuth(_config));
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  SyncSession? _session;
  bool _loading = true, _busy = false, _codeSent = false, _withPassword = false;
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
    _password.dispose();
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
    } catch (e) {
      // Type only: never the message, which could carry server text.
      _message =
          'Não foi possível concluir agora (${e.runtimeType}). Tente novamente.';
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
        SyncController.instance?.syncNow();
      });

  Future<void> _create() async {
    final name = TextEditingController(
        text: DesktopProfile.testName.isEmpty
            ? 'Teste do Nexo'
            : 'Teste ${DesktopProfile.testName}');
    final label = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: const Text('Criar acervo de teste'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Os dados deste perfil de teste viram o acervo. Outro perfil de teste pode entrar nele e as alterações passam a sincronizar automaticamente.'),
                TextField(
                    controller: name,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'Nome')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, name.text.trim()),
                    child: const Text('Criar')),
              ],
            ));
    name.dispose();
    if (label == null || label.isEmpty) return;
    await _run(() => SyncController.instance!.createDataset(label));
  }

  Future<void> _join() async {
    List<RemoteDataset> options = const [];
    await _run(() async => options = await SyncController.instance!.datasets());
    if (!mounted || _message != null) return;
    if (options.isEmpty) {
      setState(() => _message =
          'Nenhum acervo encontrado. Crie um no outro perfil de teste primeiro.');
      return;
    }
    final chosen = await showDialog<RemoteDataset>(
        context: context,
        builder: (dialog) => SimpleDialog(
              title: const Text('Entrar em qual acervo?'),
              children: [
                for (final d in options)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialog, d),
                    child: ListTile(
                        title: Text(d.label),
                        subtitle: Text(
                            '${d.devices} aparelho(s) · revisão do servidor')),
                  ),
              ],
            ));
    if (chosen == null) return;
    await _run(() => SyncController.instance!.join(chosen));
  }

  Future<void> _passwordSignIn() => _run(() async {
        try {
          _session =
              await _auth!.signInWithPassword(_email.text, _password.text);
        } finally {
          _password.clear();
        }
        // Resume automatic sync that was waiting for a session.
        SyncController.instance?.syncNow();
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
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Código por e-mail')),
            ButtonSegment(value: true, label: Text('Senha')),
          ],
          selected: {_withPassword},
          onSelectionChanged: _busy || _codeSent
              ? null
              : (v) => setState(() {
                    _withPassword = v.single;
                    _message = null;
                  }),
        ),
        const SizedBox(height: 12),
        Text(
            _withPassword
                ? 'Use a senha definida para esta conta no Supabase. Não envia e-mail.'
                : 'Você recebe um código de uso único por e-mail.',
            style: Theme.of(context).textTheme.bodyMedium),
        const Text(
            'O PIN do Nexo continua só neste aparelho e não é a senha da conta.'),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          enabled: !_busy && !_codeSent,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        const SizedBox(height: 12),
        if (_withPassword) ...[
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Senha'),
            onSubmitted: (_) => _passwordSignIn(),
          ),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _busy ? null : _passwordSignIn,
              child: const Text('Entrar')),
        ] else if (!_codeSent)
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

  Widget _syncCard(SyncController sync, ThemeData theme) {
    if (!sync.bound) {
      if (!DesktopProfile.isTest) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
              'A sincronização com os seus dados reais será liberada na próxima etapa, com backup antes e confirmação sua. Por enquanto ela pode ser testada no Nexo do Windows em perfil de teste.'),
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Sincronização de teste', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Neste perfil de teste você pode criar um acervo ou entrar num acervo criado por outro perfil de teste. Depois disso, tudo sincroniza sozinho.'),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Criar acervo a partir deste perfil')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _busy ? null : _join,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Entrar num acervo existente')),
      ]);
    }
    final last = sync.lastSuccess;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
            sync.running
                ? Icons.sync
                : sync.conflicts.isNotEmpty || sync.pending > 0
                    ? Icons.sync_problem_outlined
                    : Icons.cloud_done_outlined,
            color: sync.conflicts.isNotEmpty ? theme.colorScheme.error : null),
        title: Text(sync.running ? 'Sincronizando…' : sync.summary),
        subtitle: Text([
          if (sync.datasetLabel != null) 'Acervo: ${sync.datasetLabel}',
          'Automática: ao salvar, ao abrir o app e a cada minuto',
          if (last != null)
            'Última sincronização: ${DateFormat('dd/MM HH:mm').format(last)}',
        ].join('\n')),
      ),
      OutlinedButton.icon(
          onPressed: sync.running ? null : sync.syncNow,
          icon: const Icon(Icons.sync),
          label: const Text('Sincronizar agora')),
      for (final conflict in sync.conflicts) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Conflito: ${_kind(conflict.operation.kind)}',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                  'Outro aparelho alterou o mesmo registro antes. Este aparelho já mostra a versão do outro; a sua alteração ficou guardada aqui.'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _run(() => sync.discard(conflict.operation.id)),
                    child: const Text('Manter a versão do outro aparelho')),
                if (conflict.canReapply)
                  OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () =>
                              _run(() => sync.reapply(conflict.operation.id)),
                      child: const Text('Usar a minha versão'))
                else
                  const Text(
                      'Para usar a sua versão, refaça a alteração no app.'),
              ]),
            ]),
          ),
        ),
      ],
    ]);
  }

  static String _kind(String kind) => switch (kind.split('.').first) {
        'transaction' => 'lançamento',
        'transfer' => 'transferência',
        'invoice' => 'pagamento de fatura',
        'account' => 'conta',
        'category' => 'categoria',
        'recurring' => 'recorrente',
        'goal' => 'objetivo',
        'lended' || 'lended_person' => 'dinheiro emprestado',
        'loan' => 'empréstimo',
        'budget' => 'orçamento',
        'investment' => 'investimento',
        _ => 'alteração',
      };

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
        if (SyncController.instance case final sync?)
          ListenableBuilder(
              listenable: sync,
              builder: (context, _) => _syncCard(sync, theme)),
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
