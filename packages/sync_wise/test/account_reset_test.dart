import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_wise/sync_wise.dart';

void main() {
  late Directory directory;
  late AccountResetStorage storage;
  late List<String> events;
  late _Engine engine;
  late _Backend backend;
  late _LocalData localData;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sync-reset-');
    storage = AccountResetStorage(directory: () async => directory);
    events = [];
    engine = _Engine(events);
    backend = _Backend(events);
    localData = _LocalData(events);
  });
  tearDown(() => directory.delete(recursive: true));

  Future<AccountResetController> controller() async {
    final provider =
        NotifierProvider<AccountResetController, AccountResetState>(
          () => AccountResetController(
            (ref) => AccountResetConfig(
              storage: storage,
              engine: engine,
              backend: backend,
              network: backend.network,
              localData: localData,
            ),
          ),
          retry: (_, _) => null,
        );
    final container = ProviderContainer.test();
    final reset = container.read(provider.notifier);
    _states[reset] = () => container.read(provider);
    await reset.ready;
    return reset;
  }

  test('native provider reset deletes remote then local data and retains device identity', () async {
    final identity = File('${directory.path}/device_identity.id');
    await identity.writeAsString('device');
    await SyncAccountBinding(directory: () async => directory)
        .verify(backendId: 'native', accountId: 'owner');
    final reset = await controller();
    await reset.reset(expectedAccountId: 'owner');

    expect(_state(reset).completed, isTrue, reason: _state(reset).error);
    expect(events, ['pause', 'open', 'remote', 'local', 'signOut', 'resume']);
    expect(backend.closed, 1);
    expect(await storage.canSync(), isTrue);
    expect(await File('${directory.path}/sync_account.json').exists(), isFalse);
    expect(await identity.readAsString(), 'device');
  });

  test(
    'unconfirmed reset cannot open a cloud session or clear local data',
    () async {
      final reset = await controller();
      await reset.reset();
      expect(_state(reset).error, contains('Confirm the account reset'));
      expect(events, ['pause', 'resume']);
      expect(await storage.canSync(), isTrue);
    },
  );

  test(
    'remote failure survives restart and keeps local data and sync paused',
    () async {
      backend.store.failDelete = true;
      final first = await controller();
      await first.reset(expectedAccountId: 'owner');
      expect(_state(first).blocksDataAccess, isTrue);
      expect(await storage.canSync(), isFalse);
      expect((await storage.read())!.remoteDeleted, isFalse);
      expect(localData.calls, 0);
      expect(events, isNot(contains('resume')));

      final restarted = await controller();
      backend.store.failDelete = false;
      await restarted.reset();
      expect(_state(restarted).completed, isTrue);
      expect(localData.calls, 1);
      expect(backend.store.deletions, 2);
      expect(backend.closed, 2);
    },
  );

  test(
    'local cleanup failure resumes offline without repeating remote deletion',
    () async {
      localData.fail = true;
      final first = await controller();
      await first.reset(expectedAccountId: 'owner');
      expect(_state(first).pending, isTrue);
      expect((await storage.read())!.remoteDeleted, isTrue);
      expect(backend.closed, 1);

      final restarted = await controller();
      backend.network.online = false;
      localData.fail = false;
      await restarted.reset();
      expect(_state(restarted).completed, isTrue);
      expect(backend.store.deletions, 1);
      expect(localData.calls, 2);
    },
  );

  test(
    'provider mismatch cannot delete through the currently selected provider',
    () async {
      await storage.write(const ResetIntent('owner', backendId: 'different'));
      final reset = await controller();
      await reset.reset();
      expect(_state(reset).error, contains('Reconnect the sync provider'));
      expect(_state(reset).blocksDataAccess, isTrue);
      expect(localData.calls, 0);
      expect(backend.store.deletions, 0);
      expect(events, isNot(contains('open')));
    },
  );

  test(
    'malformed durable intent keeps sync and local data access blocked',
    () async {
      await File('${directory.path}/account_reset.json')
          .writeAsString('broken');
      final reset = await controller();
      await reset.reset();
      expect(_state(reset).error, isNotNull);
      expect(_state(reset).blocksDataAccess, isTrue);
      expect(await storage.canSync(), isFalse);
      expect(backend.store.deletions, 0);
      expect(localData.calls, 0);
    },
  );

  test('drains active sync before starting deletion', () async {
    final release = Completer<void>();
    engine.drain = release.future;
    final reset = await controller();
    final resetting = reset.reset(expectedAccountId: 'owner');
    await Future<void>.delayed(Duration.zero);
    expect(events, ['pause']);
    expect(backend.store.deletions, 0);
    release.complete();
    await resetting;
    expect(_state(reset).completed, isTrue);
  });
  test(
    'rebuilding during session opening drains the old reset before resuming',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      backend.beforeOpen = () async {
        entered.complete();
        await release.future;
      };
      final provider =
          NotifierProvider<AccountResetController, AccountResetState>(
            () => AccountResetController(
              (ref) => AccountResetConfig(
                storage: storage,
                engine: engine,
                backend: backend,
                network: backend.network,
                localData: localData,
              ),
            ),
            retry: (_, _) => null,
          );
      final container = ProviderContainer.test();
      final reset = container.read(provider.notifier);
      await reset.ready;
      final resetting = reset.reset(expectedAccountId: 'owner');
      await entered.future;
      container.invalidate(provider);
      final rebuilt = container.read(provider.notifier);
      release.complete();
      await resetting;
      await rebuilt.ready;
      expect(container.read(provider).blocksDataAccess, isFalse);
      expect(backend.store.deletions, 0);
      expect(localData.calls, 0);
      expect(events, contains('resume'));
      expect(backend.closed, 1);
    },
  );
}

final _states = Expando<AccountResetState Function()>();
AccountResetState _state(AccountResetController controller) =>
    _states[controller]!();

class _Engine extends Fake implements SyncEngine {
  final List<String> events;
  Future<void>? drain;
  _Engine(this.events);
  @override
  Future<void> suspendForReset() async {
    events.add('pause');
    await drain;
  }

  @override
  void resumeAfterReset({required bool completed}) => events.add('resume');
}

class _LocalData implements AccountResetLocalData {
  final List<String> events;
  var fail = false;
  var calls = 0;
  _LocalData(this.events);
  @override
  Future<void> clear() async {
    calls++;
    events.add('local');
    if (fail) throw StateError('Local cleanup interrupted');
  }
}

class _Network implements SyncNetwork {
  var online = true;
  @override
  Future<bool> isOnline() async => online;
}

class _Auth extends Fake implements SyncAuth {
  final List<String> events;
  _Auth(this.events);
  @override
  SyncAccount? get currentUser =>
      const SyncAccount(id: 'owner', email: 'owner@example.test');
  @override
  Future<void> signOut() async => events.add('signOut');
}

class _Backend extends Fake implements SyncBackend {
  final List<String> events;
  @override
  late final SyncAuth auth = _Auth(events);
  late final _Store store = _Store(events);
  final network = _Network();
  var closed = 0;
  Future<void> Function()? beforeOpen;
  _Backend(this.events);
  @override
  String get id => 'native';
  @override
  String get displayName => 'Native Cloud';
  @override
  Future<SyncSession?> openSession() async {
    events.add('open');
    await beforeOpen?.call();
    return _Session(store, () => closed++);
  }
}

class _Session implements SyncSession {
  @override
  final SyncClient client;
  final void Function() _close;
  _Session(this.client, this._close);
  @override
  void close() => _close();
}

class _Store extends Fake implements SyncClient {
  final List<String> events;
  var deletions = 0;
  var failDelete = false;
  _Store(this.events);
  @override
  Future<void> permanentlyDeleteAllData({
    void Function(int, int)? onProgress,
  }) async {
    events.add('remote');
    deletions++;
    if (failDelete) throw StateError('Remote deletion interrupted');
  }
}
