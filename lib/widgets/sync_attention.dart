import 'package:flutter/material.dart';

import '../screens/sync_settings_screen.dart';
import '../sync/ledger_sync.dart';
import '../sync/sync_controller.dart';
import '../theme/nexo_tokens.dart';

/// On Hoje, only when sync needs the person: an outdated app, a conflict,
/// a session to renew. Network hiccups stay out (they fix themselves).
class SyncAttention extends StatelessWidget {
  const SyncAttention({super.key, this.controller});
  final SyncController? controller;

  static const _needsPerson = {
    LedgerSyncStatus.updateRequired,
    LedgerSyncStatus.conflict,
    LedgerSyncStatus.authenticationRequired,
    LedgerSyncStatus.deviceRevoked,
    LedgerSyncStatus.unattributed,
    LedgerSyncStatus.paused,
  };

  @override
  Widget build(BuildContext context) {
    final sync = controller ?? SyncController.instance;
    if (sync == null) return const SizedBox.shrink();
    return ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          final status = sync.status;
          if (!sync.bound || status == null || !_needsPerson.contains(status)) {
            return const SizedBox.shrink();
          }
          final tone = NexoTones.warning(context);
          final title = switch (status) {
            LedgerSyncStatus.updateRequired => 'Atualize o Nexo neste aparelho',
            LedgerSyncStatus.conflict => 'A sincronização precisa de você',
            LedgerSyncStatus.authenticationRequired =>
              'Entre de novo para sincronizar',
            _ => 'Sincronização pausada',
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SyncSettingsScreen())),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(
                        status == LedgerSyncStatus.updateRequired
                            ? Icons.system_update_outlined
                            : Icons.sync_problem_outlined,
                        color: tone),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(sync.summary,
                              style: Theme.of(context).textTheme.bodySmall),
                        ])),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            ),
          );
        });
  }
}
