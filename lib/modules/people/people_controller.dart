import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journal/utils/cache.dart';

import 'friend_store.dart';
import 'people_models.dart';
import 'people_transport.dart';

final peopleSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && Platform.isAndroid,
);
// Bound to the account-reset gate by the application, without coupling the
// networking layer back to Google authentication or journal sync.
final peopleAccessAllowedProvider = Provider<bool>((ref) => true);
final peopleMonotonicNowProvider = Provider<Duration Function()>((ref) {
  final stopwatch = Stopwatch()..start();
  ref.onDispose(stopwatch.stop);
  return () => stopwatch.elapsed;
});
final friendStoreProvider = Provider<FriendStore>(
  (ref) => ProtectedFriendStore(),
);
final peopleTransportProvider = Provider<PeopleTransport>(
  (ref) => BarePeopleTransport(),
);
final peopleDisplayNameProvider = Provider<String>((ref) {
  try {
    final name = (CacheStorage.instance.get(userNameKey) ?? '').trim();
    return name.isEmpty
        ? 'A friend'
        : name.substring(0, name.length.clamp(0, 80));
  } catch (_) {
    return 'A friend';
  }
});
final peopleControllerProvider =
    NotifierProvider<PeopleController, PeopleState>(PeopleController.new);

class PeopleState {
  const PeopleState({
    this.supported = true,
    this.loading = true,
    this.connected = false,
    this.busy = false,
    this.foreground = true,
    this.friends = const [],
    this.notes = const [],
    this.candidates = const [],
    this.invite,
    this.message,
    this.draftEpoch = 0,
  });
  final bool supported, loading, connected, busy, foreground;
  final List<Person> friends, candidates;
  final List<PeopleNote> notes;
  final FriendInvitation? invite;
  final String? message;
  final int draftEpoch;
  PeopleState copy({
    bool? loading,
    bool? connected,
    bool? busy,
    bool? foreground,
    List<Person>? friends,
    List<PeopleNote>? notes,
    List<Person>? candidates,
    FriendInvitation? invite,
    bool clearInvite = false,
    String? message,
    bool clearMessage = false,
    int? draftEpoch,
  }) => PeopleState(
    supported: supported,
    loading: loading ?? this.loading,
    connected: connected ?? this.connected,
    busy: busy ?? this.busy,
    foreground: foreground ?? this.foreground,
    friends: friends ?? this.friends,
    notes: notes ?? this.notes,
    candidates: candidates ?? this.candidates,
    invite: clearInvite ? null : invite ?? this.invite,
    message: clearMessage ? null : message ?? this.message,
    draftEpoch: draftEpoch ?? this.draftEpoch,
  );
  Person? person(String key) => friends.where((p) => p.key == key).firstOrNull;
  PeopleNote? note(int id) => notes.where((n) => n.id == id).firstOrNull;
}

class PeopleController extends Notifier<PeopleState> {
  late FriendStore _store;
  late PeopleTransport _transport;
  FriendRecords _records = const FriendRecords();
  Future<void>? _restoring, _connecting;
  Future<void> _storageQueue = Future.value();
  bool _loaded = false, _blocked = false;
  int _generation = 0, _nextNote = 0;
  String? _key;
  AppLifecycleListener? _lifecycle;
  Timer? _inviteTimer, _readingTimer;
  final _liveNotes = <PeopleNote>{};

  @override
  PeopleState build() {
    _store = ref.read(friendStoreProvider);
    _transport = ref.read(peopleTransportProvider);
    final supported = ref.read(peopleSupportedProvider);
    _blocked = !ref.read(peopleAccessAllowedProvider);
    ref.listen(peopleAccessAllowedProvider, (_, allowed) {
      _blocked = !allowed;
      if (_blocked) {
        foreground(false);
      } else {
        foreground(
          WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed,
        );
      }
    });
    final initiallyForeground =
        !_blocked &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed);
    final subscription = _transport.events.listen(
      _event,
      onError: (Object _) => _failure(const PeopleFailure()),
    );
    _lifecycle = AppLifecycleListener(
      onStateChange: (value) => foreground(value == AppLifecycleState.resumed),
    );
    ref.onDispose(() {
      _generation++;
      _inviteTimer?.cancel();
      _readingTimer?.cancel();
      _lifecycle?.dispose();
      for (final note in _liveNotes) {
        note.discard();
      }
      _liveNotes.clear();
      unawaited(subscription.cancel());
      unawaited(_transport.dispose());
    });
    if (supported) {
      scheduleMicrotask(() {
        if (ref.mounted) unawaited(restore());
      });
    }
    return PeopleState(
      supported: supported,
      loading: supported,
      foreground: initiallyForeground,
    );
  }

  void _failure(Object error) {
    if (ref.mounted) {
      state = state.copy(
        loading: false,
        busy: false,
        message: error is PeopleFailure
            ? error.message
            : const PeopleFailure().message,
      );
    }
  }

  Future<void> restore() async {
    if (!state.supported || _loaded) return;
    await (_restoring ??= (() async {
      final generation = _generation;
      try {
        final records = await _store.load();
        if (!ref.mounted || generation != _generation) return;
        _records = records;
        _loaded = true;
        state = state.copy(
          loading: false,
          friends: records.friends,
          clearMessage: true,
        );
        if (records.friends.isNotEmpty && state.foreground && !_blocked) {
          unawaited(connect().catchError((Object _) {}));
        }
      } catch (error) {
        _failure(error);
      }
    })().whenComplete(() => _restoring = null));
  }

  Future<void> _edit(FriendRecords Function(FriendRecords) change) {
    final generation = _generation;
    final result = _storageQueue.then((_) async {
      if (!ref.mounted || generation != _generation || _blocked) {
        throw const PeopleFailure();
      }
      final next = change(_records);
      await _store.save(next);
      if (!ref.mounted || generation != _generation) {
        throw const PeopleFailure();
      }
      _records = next;
      state = state.copy(friends: next.friends);
    });
    _storageQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> connect() async {
    if (!state.supported) {
      throw const PeopleFailure('Friends works on Android phones for now.');
    }
    await restore();
    if (!_loaded || !state.foreground || _blocked) {
      throw const PeopleFailure(
        'Unlock the phone and keep Journal open to use People.',
      );
    }
    if (state.connected) return;
    await (_connecting ??= (() async {
      final generation = _generation;
      try {
        if (_records.seed == null) {
          await _edit(
            (r) => FriendRecords(seed: peopleSecret(), friends: r.friends),
          );
        }
        final key = await _transport.start(
          _records.seed!,
          ref.read(peopleDisplayNameProvider),
        );
        if (!ref.mounted ||
            generation != _generation ||
            _blocked ||
            !state.foreground) {
          await _transport.stop();
          return;
        }
        _key = key;
        await _configure();
        if (ref.mounted && generation == _generation) {
          state = state.copy(connected: true, clearMessage: true);
        }
      } catch (error) {
        _failure(error);
        rethrow;
      }
    })().whenComplete(() => _connecting = null));
  }

  Future<void> _configure() => _transport.configure(
    _records.friends.map((p) => p.key).toList(),
    state.invite?.expired == false ? state.invite : null,
  );
  Future<void> createInvite() async {
    if (state.busy) return;
    state = state.copy(busy: true, clearMessage: true);
    try {
      await connect();
      if (!state.connected) throw const PeopleFailure();
      final invite = FriendInvitation(
        key: _key!,
        token: peopleSecret(),
        name: ref.read(peopleDisplayNameProvider),
        expires: DateTime.now().add(const Duration(minutes: 5)),
      );
      state = state.copy(invite: invite);
      await _configure();
      _inviteTimer?.cancel();
      _inviteTimer = Timer(
        const Duration(minutes: 5),
        () => unawaited(cancelInvite()),
      );
    } catch (error) {
      _failure(error);
    } finally {
      if (ref.mounted) state = state.copy(busy: false);
    }
  }

  Future<void> cancelInvite() async {
    _inviteTimer?.cancel();
    state = state.copy(clearInvite: true);
    if (state.connected) {
      try {
        await _configure();
      } catch (_) {
        /* Revoke locally even offline. */
      }
    }
  }

  Future<bool> acceptInvite(String raw) async {
    if (state.busy) return false;
    final generation = _generation;
    state = state.copy(busy: true, clearMessage: true);
    try {
      final invite = FriendInvitation.parse(raw);
      await connect();
      if (!state.connected || generation != _generation) return false;
      if (invite.key == _key) {
        throw const PeopleFailure(
          'This is your own invitation. Scan a friend’s instead.',
        );
      }
      final person = await _transport.pair(invite);
      if (person.key != invite.key) throw const PeopleFailure();
      if (!ref.mounted || generation != _generation || !state.foreground) {
        return false;
      }
      await _add(person);
      return true;
    } catch (error) {
      _failure(error);
      return false;
    } finally {
      if (ref.mounted) state = state.copy(busy: false);
    }
  }

  Future<void> _add(Person person) async {
    await _edit((r) {
      final friends = [...r.friends.where((p) => p.key != person.key), person];
      if (friends.length > 100) {
        throw const PeopleFailure('Remove a friend before adding another.');
      }
      return FriendRecords(seed: r.seed, friends: List.unmodifiable(friends));
    });
    await _configure();
  }

  Future<void> confirm(Person person, bool accepted) async {
    if (state.busy) return;
    state = state.copy(busy: true);
    try {
      if (accepted) await _add(person);
      await _transport.confirm(person.key, accepted);
      state = state.copy(
        candidates: state.candidates.where((p) => p.key != person.key).toList(),
        clearInvite: true,
      );
    } catch (error) {
      _failure(error);
    } finally {
      if (ref.mounted) state = state.copy(busy: false);
    }
  }

  Future<void> remove(Person person) async {
    _discardWhere((n) => n.friendKey == person.key);
    try {
      await _edit(
        (r) => FriendRecords(
          seed: r.seed,
          friends: List.unmodifiable(
            r.friends.where((p) => p.key != person.key),
          ),
        ),
      );
      _discardWhere((n) => n.friendKey == person.key);
      if (state.connected) await _configure();
    } catch (error) {
      _failure(error);
      rethrow;
    }
  }

  Future<bool> send(String key, String text) async {
    if (state.busy || state.person(key) == null || !validPeopleNote(text)) {
      return false;
    }
    final generation = _generation;
    state = state.copy(busy: true, clearMessage: true);
    try {
      // The 15-second budget covers startup and connection, not just writing.
      await (() async {
        await connect();
        if (generation != _generation ||
            !state.foreground ||
            state.person(key) == null) {
          throw const PeopleFailure();
        }
        await _transport.send(key, text);
      })().timeout(const Duration(seconds: 15));
      return generation == _generation;
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = state.copy(message: 'Could not send. The note was discarded.');
      }
      // A timed-out native attempt must not deliver later after UI reports failure.
      if (generation == _generation) {
        final cancelledGeneration = ++_generation;
        state = state.copy(busy: false, connected: false);
        await _transport.stop();
        if (ref.mounted && cancelledGeneration == _generation) {
          state = state.copy(connected: false);
        }
      }
      return false;
    } finally {
      if (ref.mounted && generation == _generation) {
        state = state.copy(busy: false);
      }
    }
  }

  void _event(Map<String, dynamic> event) {
    if (!ref.mounted || !state.foreground || _blocked) return;
    try {
      final key = event['key'] as String?;
      switch (event['type']) {
        case 'note':
          final text = event['text'];
          if (key == null ||
              state.person(key) == null ||
              text is! String ||
              !validPeopleNote(text) ||
              state.notes.length >= 20) {
            return;
          }
          final note = PeopleNote(
            id: ++_nextNote,
            friendKey: key,
            text: text,
            now: ref.read(peopleMonotonicNowProvider),
          );
          _liveNotes.add(note);
          state = state.copy(notes: List.unmodifiable([...state.notes, note]));
        case 'candidate':
          if (state.invite?.expired != false) return;
          final person = Person.fromJson(event);
          _inviteTimer?.cancel();
          state = state.copy(candidates: [person], clearInvite: true);
        case 'candidateClosed':
          state = state.copy(
            candidates: state.candidates.where((p) => p.key != key).toList(),
          );
        case 'unavailable':
          state = state.copy(
            connected: false,
            message: const PeopleFailure().message,
          );
      }
    } catch (_) {
      /* Reject untrusted or malformed events without logging them. */
    }
  }

  void openNote(int id) {
    final note = state.note(id);
    if (note == null || !state.foreground || _blocked) return;
    note.open();
    _readingTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!ref.mounted) return;
      _discardWhere((n) => n.opened && n.remaining == Duration.zero);
      if (!state.notes.any((n) => n.opened)) {
        _readingTimer?.cancel();
        _readingTimer = null;
      }
      state = state.copy();
    });
    state = state.copy();
  }

  void discardNote(int id) {
    if (ref.mounted) _discardWhere((n) => n.id == id);
  }

  void _discardWhere(bool Function(PeopleNote) predicate) {
    final remaining = <PeopleNote>[];
    for (final note in state.notes) {
      if (predicate(note)) {
        note.discard();
        _liveNotes.remove(note);
      } else {
        remaining.add(note);
      }
    }
    state = state.copy(notes: List.unmodifiable(remaining));
    if (!remaining.any((n) => n.opened)) {
      _readingTimer?.cancel();
      _readingTimer = null;
    }
  }

  void foreground(bool value) {
    if (!ref.mounted) return;
    value = value && !_blocked;
    if (state.foreground == value) return;
    if (!value) {
      _generation++;
      _discardWhere((_) => true);
      _readingTimer?.cancel();
      _readingTimer = null;
      state = state.copy(
        foreground: false,
        connected: false,
        busy: false,
        candidates: [],
        draftEpoch: state.draftEpoch + 1,
      );
      unawaited(_transport.stop());
    } else {
      state = state.copy(
        foreground: true,
        clearInvite: state.invite?.expired == true,
      );
      if (_loaded && (_records.friends.isNotEmpty || state.invite != null)) {
        unawaited(connect().catchError((Object _) {}));
      } else if (!_loaded && state.supported) {
        unawaited(restore());
      }
    }
  }

  Future<void> clear() async {
    _generation++;
    _inviteTimer?.cancel();
    _readingTimer?.cancel();
    _readingTimer = null;
    _discardWhere((_) => true);
    state = state.copy(
      friends: [],
      candidates: [],
      clearInvite: true,
      connected: false,
      busy: false,
      draftEpoch: state.draftEpoch + 1,
    );
    await _transport.stop();
    await _storageQueue;
    if (state.supported) await _store.clear();
    _records = const FriendRecords();
    _key = null;
    _loaded = true;
  }
}
