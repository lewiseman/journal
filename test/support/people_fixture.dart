import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/modules/people/friend_store.dart';
import 'package:journal/modules/people/people_controller.dart';
import 'package:journal/modules/people/people_models.dart';
import 'package:journal/modules/people/people_transport.dart';

final peopleAliceKey = 'a' * 64;
final peopleBobKey = 'b' * 64;
final peopleSeed = 'c' * 64;

class MemoryFriendStore implements FriendStore {
  MemoryFriendStore([this.records = const FriendRecords()]);
  FriendRecords records;
  final writes = <Map<String, dynamic>>[];
  bool failLoad = false, failSave = false;
  int clears = 0;
  @override
  Future<FriendRecords> load() async {
    if (failLoad) throw const PeopleFailure('Protected storage locked');
    return records;
  }

  @override
  Future<void> save(FriendRecords records) async {
    if (failSave) throw const PeopleFailure('Protected storage locked');
    writes.add(records.toJson());
    this.records = records;
  }

  @override
  Future<void> clear() async {
    clears++;
    records = const FriendRecords();
  }
}

class FakePeopleTransport implements PeopleTransport {
  final input = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  @override
  Stream<Map<String, dynamic>> get events => input.stream;
  int starts = 0, stops = 0, sends = 0;
  bool failSend = false;
  Completer<void>? pendingSend;
  List<String> trusted = [];
  FriendInvitation? invitation;
  final confirmations = <bool>[];
  @override
  Future<String> start(String seed, String name) async {
    starts++;
    return peopleAliceKey;
  }

  @override
  Future<void> configure(List<String> friends, FriendInvitation? invite) async {
    trusted = friends;
    invitation = invite;
  }

  @override
  Future<Person> pair(FriendInvitation invite) async =>
      Person(key: invite.key, name: invite.name);
  @override
  Future<void> confirm(String key, bool accepted) async {
    confirmations.add(accepted);
  }

  @override
  Future<void> send(String key, String text) async {
    sends++;
    if (failSend) throw const PeopleFailure();
    await pendingSend?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pendingSend?.isCompleted == false) {
      pendingSend!.completeError(const PeopleFailure());
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await input.close();
  }

  void note(String text, {String? key}) =>
      input.add({'type': 'note', 'key': key ?? peopleBobKey, 'text': text});
}

class PeopleFixture {
  PeopleFixture({bool withFriend = true, bool supported = true}) {
    store = MemoryFriendStore(
      FriendRecords(
        seed: withFriend ? peopleSeed : null,
        friends: withFriend ? [Person(key: peopleBobKey, name: 'Bob')] : [],
      ),
    );
    container = ProviderContainer.test(
      overrides: [
        peopleSupportedProvider.overrideWithValue(supported),
        friendStoreProvider.overrideWithValue(store),
        peopleTransportProvider.overrideWithValue(transport),
        peopleDisplayNameProvider.overrideWithValue('Alice'),
        peopleMonotonicNowProvider.overrideWithValue(() => elapsed),
      ],
    );
    controller = container.read(peopleControllerProvider.notifier);
  }
  late final MemoryFriendStore store;
  final transport = FakePeopleTransport();
  late final ProviderContainer container;
  late final PeopleController controller;
  Duration elapsed = Duration.zero;
  PeopleState get state => container.read(peopleControllerProvider);
  Future<void> ready() async {
    await controller.restore();
    if (state.supported) await controller.connect();
  }
}
