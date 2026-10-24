import 'package:uuid/uuid.dart';

import 'supabase_sync_transport.dart';
import 'sync_protocol.dart';

/// What the remote check needs besides push/pull. Implemented by the real
/// Supabase transport; tests provide a local fake.
abstract interface class SyncLabTransport implements SyncTransport {
  Future<void> createSyntheticDataset(String datasetId, String epoch);
  Future<void> revokeDevice(String datasetId, String device);
}

class SyncLabStep {
  const SyncLabStep(this.label, this.passed, [this.detail]);
  final String label;
  final bool passed;
  final String? detail;
}

/// Exercises the real server over HTTP with a brand-new synthetic dataset:
/// fictitious account and amounts, two simulated devices of the signed-in
/// person. Never reads or sends the local ledger.
class SyncLabCheck {
  SyncLabCheck(this.device);

  /// Builds a transport for a given device id, sharing the same session.
  final SyncLabTransport Function(String deviceId) device;

  Future<List<SyncLabStep>> run() async {
    final steps = <SyncLabStep>[];
    final dataset = const Uuid().v4(), epoch = const Uuid().v4();
    final phoneId = const Uuid().v4(), pcId = const Uuid().v4();
    final phone = device(phoneId), pc = device(pcId);
    var at = DateTime.utc(2026, 1, 1, 12);

    SyncOperation op(String deviceId,
        {List<SyncEdit> edits = const [],
        List<SyncEffect> effects = const [],
        List<SyncRequirement> requires = const [],
        String label = 'lab'}) {
      at = at.add(const Duration(minutes: 1));
      return SyncOperation(
          id: const Uuid().v4(),
          datasetId: dataset,
          epoch: epoch,
          deviceId: deviceId,
          createdAt: at,
          edits: edits,
          effects: effects,
          requires: requires,
          label: label);
    }

    const bank = SyncKey('accounts', 'lab-bank');
    SyncOperation spend(String deviceId, String id, int micros, int revision) =>
        op(deviceId, label: 'transaction.add', edits: [
          SyncEdit(SyncKey('transactions', id), 0, {'amount': micros / 1e6})
        ], effects: [
          SyncEffect('lab-bank', -micros)
        ], requires: [
          SyncRequirement(bank, revision)
        ]);

    Future<void> step(String label, Future<String?> Function() action) async {
      try {
        final failure = await action();
        steps.add(SyncLabStep(label, failure == null, failure));
      } on SyncAuthenticationRequired {
        steps.add(
            SyncLabStep(label, false, 'Sessão expirada: entre novamente.'));
      } on SyncUnavailable {
        steps.add(SyncLabStep(
            label, false, 'Servidor indisponível ou sem internet.'));
      } on SyncProtocolException catch (e) {
        steps.add(SyncLabStep(label, false, 'Recusado: ${e.code}'));
      } catch (e) {
        steps.add(SyncLabStep(label, false, e.runtimeType.toString()));
      }
    }

    Future<int?> accepted(SyncLabTransport t, SyncOperation o) async {
      final result = await t.push(o);
      return result is SyncAccepted ? result.receipt.revision : null;
    }

    await step('Login aceito e acervo fictício criado', () async {
      await phone.createSyntheticDataset(dataset, epoch);
      await pc.createSyntheticDataset(dataset, epoch);
      return null;
    });
    if (!steps.last.passed) return steps;

    final opening = op(phoneId, label: 'bootstrap.checkpoint', edits: [
      SyncEdit(bank, 0, {'name': 'Banco fictício'})
    ], effects: [
      SyncEffect('lab-bank', 1000000000)
    ]);
    await step(
        'Saldo inicial fictício gravado',
        () async =>
            await accepted(phone, opening) == 1 ? null : 'revisão inesperada');
    await step(
        'Reenvio da mesma operação não duplica',
        () async =>
            await accepted(phone, opening) == 1 ? null : 'gerou nova revisão');
    await step('Dois aparelhos gastam da mesma conta sem conflito', () async {
      final a = await accepted(phone, spend(phoneId, 'lab-t1', 7500000, 1));
      final b = await accepted(pc, spend(pcId, 'lab-t2', 300000, 1));
      return a == 2 && b == 3 ? null : 'um gasto foi recusado';
    });
    await step('Gasto baseado em conta desatualizada vira conflito', () async {
      final rename = op(phoneId, edits: [
        SyncEdit(bank, 1, {'name': 'Banco fictício renomeado'})
      ]);
      if (await accepted(phone, rename) != 4) return 'renomear falhou';
      final result = await pc.push(spend(pcId, 'lab-t3', 1000000, 1));
      return result is SyncRejected && result.remote.length == 2
          ? null
          : 'operação desatualizada foi aceita';
    });
    await step('Outro aparelho recebe tudo em ordem e íntegro', () async {
      final revisions = <int>[];
      for (var page = 0; page < 10; page++) {
        final received = await pc.pull(
            datasetId: dataset,
            epoch: epoch,
            after: revisions.isEmpty ? 0 : revisions.last,
            limit: 100);
        if (received.isEmpty) break;
        for (final receipt in received) {
          await receipt.validate();
          revisions.add(receipt.revision);
        }
      }
      return revisions.join(',') == '1,2,3,4' ? null : 'recebido: $revisions';
    });
    await step('Aparelho revogado perde acesso', () async {
      await phone.revokeDevice(dataset, pcId);
      try {
        await pc.pull(datasetId: dataset, epoch: epoch, after: 0, limit: 1);
        return 'aparelho revogado ainda lê';
      } on SyncDeviceRevoked {
        return null;
      }
    });
    return steps;
  }
}
