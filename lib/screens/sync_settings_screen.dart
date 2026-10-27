import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/file_output.dart';
import '../services/mcp_recipes.dart';
import '../services/pluggy_inbox.dart';
import '../sync/mcp_connectors.dart';
import '../sync/supabase_auth.dart';
import '../sync/supabase_sync_transport.dart';
import '../sync/sync_config.dart';
import '../sync/sync_lab_check.dart';
import '../sync/sync_protocol.dart' show SyncUnavailable;
import '../sync/sync_controller.dart';
import '../services/desktop_profile.dart';
import 'package:intl/intl.dart';

/// Account, synchronization and remote laboratory. Real activation always
/// goes through consent, a saved backup, a local rehearsal and a final
/// comparison with the server.
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
  String? _message, _step;
  List<SyncLabStep>? _lab;
  List<PluggyItem>? _pluggy;
  List<McpConnector>? _mcp;

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
    if (session != null) {
      await _loadPluggy();
      await _loadMcp();
    }
  }

  Future<void> _loadMcp() async {
    final mcp = McpConnectors.instance;
    if (mcp == null) return;
    try {
      final list = await mcp.list();
      if (mounted) setState(() => _mcp = list);
    } catch (_) {
      // Optional section; the server part may not be active yet.
    }
  }

  Future<void> _connectClaude(SyncController sync) async {
    final dataset = sync.datasetId;
    if (dataset == null) return;
    String? address;
    await _run(() async {
      try {
        address = await McpConnectors.instance!.create(dataset, 'Claude');
      } on McpUnavailable catch (e) {
        _message = e.message;
      }
    });
    await _loadMcp();
    if (address == null || !mounted) return;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
              title: const Text('Endereço para o Claude'),
              content: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Este endereço é a chave de acesso e aparece só agora. Não envie para ninguém.'),
                      const SizedBox(height: 8),
                      SelectableText(address!,
                          style: const TextStyle(fontFamily: 'monospace')),
                      const SizedBox(height: 12),
                      const Text(
                          'No Claude: Configurações → Conectores → Adicionar conector personalizado. Nome: Nexo. URL: cole este endereço. Depois, numa conversa, ative o conector Nexo.'),
                      const SizedBox(height: 8),
                      // The server is plain MCP over HTTP: any client works.
                      ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Outros assistentes'),
                          children: [
                            for (final r in mcpClientRecipes(address!).skip(1))
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(r.client),
                                  subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(r.steps),
                                        SelectableText(r.snippet,
                                            style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12)),
                                      ]),
                                  trailing: IconButton(
                                      tooltip: 'Copiar',
                                      icon: const Icon(Icons.copy, size: 18),
                                      onPressed: () => Clipboard.setData(
                                          ClipboardData(text: r.snippet)))),
                          ]),
                    ]),
              ),
              actions: [
                TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: address!));
                      if (dialog.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Endereço copiado.')));
                      }
                    },
                    child: const Text('Copiar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Pronto')),
              ],
            ));
  }

  Future<void> _revokeMcp(McpConnector c) async {
    await _run(() async {
      try {
        await McpConnectors.instance!.revoke(c.id);
        _message =
            '${c.label} desconectado. O endereço antigo deixou de funcionar.';
      } on McpUnavailable catch (e) {
        _message = e.message;
      }
    });
    await _loadMcp();
  }

  List<Widget> _mcpSection(SyncController sync, ThemeData theme) => [
        const Divider(),
        Text('Claude (IA)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Deixa o Claude consultar seus dados e fazer pedidos como "lança R\$ 32,90 de iFood no Nubank". Cada pedido é gravado pelo app aberto (celular ou PC) com as regras normais; o Claude pede sua permissão antes. Ele não movimenta dinheiro de verdade, só o seu registro. Você pode desconectar quando quiser.'),
        for (final c
            in (_mcp ?? const <McpConnector>[]).where((c) => !c.revoked))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(c.label),
            subtitle: Text(c.lastUsed == null
                ? 'Ainda não usado'
                : 'Último uso: ${DateFormat('dd/MM HH:mm').format(c.lastUsed!)}'),
            trailing: IconButton(
                tooltip: 'Desconectar',
                onPressed: _busy ? null : () => _revokeMcp(c),
                icon: const Icon(Icons.link_off)),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _busy ? null : () => _connectClaude(sync),
            icon: const Icon(Icons.add_link),
            label: const Text('Conectar ao Claude')),
      ];

  Future<void> _loadPluggy() async {
    final pluggy = PluggyInbox.instance;
    if (pluggy == null) return;
    try {
      final items = await pluggy.remote.items();
      if (mounted) setState(() => _pluggy = items);
    } on PluggyUnavailable catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      // The connections list is optional; the rest of the screen works.
    }
  }

  Future<void> _addPluggyItem() async {
    final id = TextEditingController(), name = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: const Text('Adicionar conexão do Meu Pluggy'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'No painel do Pluggy: Aplicações → seu aplicativo → Demo → Itens Conectados. Abra o item do MeuPluggy e copie o id.'),
                TextField(
                    controller: id,
                    decoration: const InputDecoration(
                        labelText: 'Id do item (itemId)')),
                TextField(
                    controller: name,
                    maxLength: 60,
                    decoration: const InputDecoration(
                        labelText: 'Nome para você reconhecer',
                        hintText: 'Ex.: Nubank')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Adicionar')),
              ],
            ));
    final itemId = id.text.trim(), label = name.text.trim();
    id.dispose();
    name.dispose();
    if (ok != true || itemId.isEmpty) return;
    await _run(() async {
      try {
        await PluggyInbox.instance!.remote
            .addItem(itemId, label.isEmpty ? 'Banco' : label);
        final problem = await PluggyInbox.instance!.sync(force: true);
        _message = problem ??
            'Conexão adicionada. As movimentações dos últimos 35 dias aparecem em Sugestões para você revisar.';
      } on PluggyUnavailable catch (e) {
        _message = e.message;
      }
    });
    await _loadPluggy();
  }

  Future<void> _removePluggyItem(PluggyItem item) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text('Remover ${item.label}?'),
              content: const Text(
                  'As sugestões ainda não revisadas desta conexão somem. Lançamentos já registrados no Nexo não mudam. A autorização no Meu Pluggy continua; revogue por lá se quiser.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Remover')),
              ],
            ));
    if (ok != true) return;
    await _run(() async {
      try {
        await PluggyInbox.instance!.remote.removeItem(item.itemId);
      } on PluggyUnavailable catch (e) {
        _message = e.message;
      }
    });
    await _loadPluggy();
  }

  Future<void> _refreshPluggy() async {
    await _run(() async {
      final problem = await PluggyInbox.instance!.sync(force: true);
      _message = problem ??
          'Busca concluída. Novas movimentações aparecem em Sugestões. O Meu Pluggy atualiza os bancos uma vez por dia.';
    });
    await _loadPluggy();
  }

  List<Widget> _pluggySection(ThemeData theme) => [
        const Divider(),
        Text('Bancos pelo Open Finance', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Movimentações dos bancos conectados no Meu Pluggy entram em Sugestões para você revisar. Nada vira lançamento sozinho. Só leitura: o Nexo não faz pagamentos nem transferências.'),
        for (final item in _pluggy ?? const <PluggyItem>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                switch (item.state) {
                  'ok' => Icons.account_balance_outlined,
                  'updating' => Icons.sync,
                  'unknown' => Icons.hourglass_empty,
                  _ => Icons.warning_amber_outlined,
                },
                color: item.state == 'reconnect' || item.state == 'error'
                    ? theme.colorScheme.error
                    : null),
            title: Text(item.label),
            subtitle: Text('${item.message}\n${bankDataUntil(item)}'),
            isThreeLine: true,
            trailing: IconButton(
                tooltip: 'Remover conexão',
                onPressed: _busy ? null : () => _removePluggyItem(item),
                icon: const Icon(Icons.link_off)),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _busy ? null : _addPluggyItem,
              icon: const Icon(Icons.add_link),
              label: const Text('Adicionar conexão')),
          if (_pluggy?.isNotEmpty == true)
            OutlinedButton.icon(
                onPressed: _busy ? null : _refreshPluggy,
                icon: const Icon(Icons.refresh),
                label: const Text('Buscar no banco agora')),
        ]),
      ];

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on SyncAuthException catch (e) {
      _message = e.message;
    } on SyncActivationFailed catch (e) {
      _message = e.message;
    } on SyncUnavailable {
      _message = 'Sem conexão com o servidor. Seus dados locais não mudam.';
    } catch (e) {
      // Type only: never the message, which could carry server text.
      _message =
          'Não foi possível concluir agora (${e.runtimeType}). Tente novamente.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _step = null;
      });
    }
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
        _loadPluggy();
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

  Future<void> _activate() async {
    final app = context.read<AppProvider>();
    final counts = <String, int>{
      'contas': app.accounts.length,
      'lançamentos': app.transactions.length,
      'recorrentes': app.recurring.length,
      'orçamentos': app.budgets.length,
      'objetivos': app.savingsGoals.length,
      'empréstimos': app.loans.length,
      'dinheiro emprestado': app.lended.length,
      'categorias': app.categories.length,
    };
    var understood = false;
    final go = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (dialog, setDialog) => AlertDialog(
                  title: const Text('Ativar a sincronização'),
                  content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Este aparelho vira a origem. Uma cópia de tudo vai para o seu projeto Supabase e os outros aparelhos passam a receber as mudanças sozinhos:'),
                          const SizedBox(height: 8),
                          Text([
                            for (final e in counts.entries)
                              if (e.value > 0) '• ${e.value} ${e.key}',
                            '• investimentos, faturas, bens, desejos e regras de importação',
                          ].join('\n')),
                          const SizedBox(height: 8),
                          const Text(
                              'Proteção: só a sua conta acessa e a conexão é criptografada. Não há criptografia de ponta a ponta: o servidor guarda os dados legíveis, como um backup na nuvem. As notificações de banco deste aparelho não são enviadas.'),
                          const SizedBox(height: 8),
                          const Text(
                              'Antes de enviar: você salva um backup, o Nexo guarda uma cópia interna e faz um ensaio completo sem internet. Depois do envio ele confere se o servidor ficou idêntico. O app continua funcionando sem internet.'),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: understood,
                            onChanged: (v) =>
                                setDialog(() => understood = v ?? false),
                            title: const Text(
                                'Entendi e quero enviar meus dados para o meu servidor'),
                          ),
                        ]),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: understood
                            ? () => Navigator.pop(dialog, true)
                            : null,
                        child: const Text('Salvar backup e ativar')),
                  ],
                )));
    if (go != true || !mounted) return;
    await _run(() async {
      setState(() => _step = 'Preparando o backup…');
      final saved = await FileOutput.save(
          title: 'Salvar backup antes da sincronização',
          name:
              'nexo_backup_antes_da_sincronizacao_${DateTime.now().millisecondsSinceEpoch}.json',
          extension: 'json',
          bytes: await app.backupBytes());
      if (saved == null) {
        throw const SyncActivationFailed(
            'Ativação cancelada: o backup não foi salvo. Nada foi enviado.');
      }
      await SyncController.instance!.activate('Nexo', onStep: (step) {
        if (mounted) setState(() => _step = step);
      });
      _message =
          'Sincronização ativada. O servidor tem exatamente os dados deste aparelho. Backup salvo em: $saved';
    });
  }

  Future<void> _verifyServer() => _run(() async {
        final difference = await SyncController.instance!.verify();
        _message = difference == null
            ? 'Conferido: este aparelho está idêntico ao servidor.'
            : 'Diferença encontrada em: $difference. Não apague nada e me avise.';
      });

  Future<void> _join() async {
    final real = !DesktopProfile.isTest;
    List<RemoteDataset> options = const [];
    await _run(() async => options = await SyncController.instance!.datasets());
    if (!mounted || _message != null) return;
    if (options.isEmpty) {
      setState(() => _message = real
          ? 'Nenhum acervo encontrado. Ative primeiro no celular.'
          : 'Nenhum acervo encontrado. Crie um no outro perfil de teste primeiro.');
      return;
    }
    if (real) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: const Text('Receber os dados do acervo?'),
                content: const Text(
                    'Este aparelho passa a mostrar os mesmos dados do celular e a sincronizar sozinho. Só é possível se ele não tiver lançamentos próprios; contas zeradas e categorias padrão são substituídas pelas do acervo.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Receber')),
                ],
              ));
      if (ok != true || !mounted) return;
      await _run(() async {
        setState(() => _step = 'Recebendo e conferindo…');
        await SyncController.instance!.join(options.first);
        _message =
            'Pronto: este aparelho está idêntico ao servidor e sincroniza sozinho.';
      });
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
        _loadPluggy();
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
                'Seus dados ficam neste aparelho e funcionam sem internet. Com a sincronização ativa, uma cópia fica no seu projeto Supabase, protegida pelo seu login, e os outros aparelhos recebem as mudanças sozinhos.'),
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
        if (_step != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_step!)),
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
        final hasData = context.watch<AppProvider>().transactions.isNotEmpty;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sincronização', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(hasData
                  ? 'Ative neste aparelho para ele virar a origem dos seus dados. Depois, os outros aparelhos entram e recebem tudo.'
                  : 'Este aparelho ainda não tem lançamentos: entre no acervo criado pelo celular.'),
              const SizedBox(height: 12),
              if (hasData) ...[
                FilledButton.icon(
                    onPressed: _busy ? null : _activate,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Ativar com este aparelho como origem')),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                  onPressed: _busy ? null : _join,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Entrar no acervo do celular')),
            ]);
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
          if (sync.lastVerified case final verified?)
            'Conferido com o servidor: ${DateFormat('dd/MM HH:mm').format(verified)}',
        ].join('\n')),
      ),
      OutlinedButton.icon(
          onPressed: sync.running ? null : sync.syncNow,
          icon: const Icon(Icons.sync),
          label: const Text('Sincronizar agora')),
      if (sync.real) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _busy || sync.running ? null : _verifyServer,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Conferir com o servidor')),
      ],
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
        if (PluggyInbox.instance != null) ..._pluggySection(theme),
        if (McpConnectors.instance != null)
          if (SyncController.instance case final sync?)
            ListenableBuilder(
                listenable: sync,
                builder: (context, _) => sync.bound && sync.real
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _mcpSection(sync, theme))
                    : const SizedBox.shrink()),
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
