import 'dart:convert';
import 'dart:math';

final peopleKeyPattern = RegExp(r'^[a-f0-9]{64}$');
const peoplePrivacy =
    'Notes disappear from Journal after reading. Recipients can still capture them. Connections are encrypted, but network connection details remain visible.';

int peopleWordCount(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
Duration peopleReadingTime(String text) =>
    Duration(seconds: max(20, 10 + (peopleWordCount(text) * 60 / 150).ceil()));
bool validPeopleNote(String text) =>
    text.trim().isNotEmpty &&
    peopleWordCount(text) <= 500 &&
    utf8.encode(text).length <= 8192;
String peopleSecret() {
  final random = Random.secure();
  return List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class PeopleFailure implements Exception {
  const PeopleFailure([
    this.message =
        'People could not connect. Keep both apps open and try again.',
  ]);
  final String message;
  @override
  String toString() => message;
}

class Person {
  const Person({required this.key, required this.name});
  final String key, name;
  Map<String, dynamic> toJson() => {'key': key, 'name': name};
  factory Person.fromJson(Map<String, dynamic> value) {
    final key = value['key'], name = value['name'];
    if (key is! String ||
        !peopleKeyPattern.hasMatch(key) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80) {
      throw const FormatException('Invalid friend');
    }
    return Person(key: key, name: name.trim());
  }
}

class FriendRecords {
  const FriendRecords({this.seed, this.friends = const []});
  final String? seed;
  final List<Person> friends;
  Map<String, dynamic> toJson() => {
    'v': 1,
    'seed': seed,
    'friends': friends.map((p) => p.toJson()).toList(),
  };
  factory FriendRecords.fromJson(Map<String, dynamic> value) {
    final seed = value['seed'];
    if (value['v'] != 1 ||
        seed is! String ||
        !peopleKeyPattern.hasMatch(seed)) {
      throw const FormatException();
    }
    final friends = (value['friends'] as List)
        .map((p) => Person.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    if (friends.length > 100 ||
        friends.map((p) => p.key).toSet().length != friends.length) {
      throw const FormatException();
    }
    return FriendRecords(seed: seed, friends: List.unmodifiable(friends));
  }
}

class FriendInvitation {
  const FriendInvitation({
    required this.key,
    required this.token,
    required this.name,
    required this.expires,
  });
  final String key, token, name;
  final DateTime expires;
  bool get expired => !expires.isAfter(DateTime.now());
  Map<String, dynamic> toJson() => {
    'v': 1,
    'key': key,
    'token': token,
    'name': name,
    'expires': expires.millisecondsSinceEpoch,
  };
  String encode() =>
      'journal-people:${base64Url.encode(utf8.encode(jsonEncode(toJson())))}';
  factory FriendInvitation.parse(String raw) {
    try {
      raw = raw.trim();
      if (raw.length > 2048 || !raw.startsWith('journal-people:')) {
        throw const FormatException();
      }
      final value = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(raw.substring(15)))),
      ) as Map<String, dynamic>;
      final person = Person.fromJson(value);
      final token = value['token'], milliseconds = value['expires'];
      if (value['v'] != 1 ||
          token is! String ||
          !peopleKeyPattern.hasMatch(token) ||
          milliseconds is! int) {
        throw const FormatException();
      }
      final expires = DateTime.fromMillisecondsSinceEpoch(milliseconds);
      final now = DateTime.now();
      if (!expires.isAfter(now) ||
          expires.isAfter(now.add(const Duration(minutes: 5)))) {
        throw const FormatException();
      }
      return FriendInvitation(
        key: person.key,
        token: token,
        name: person.name,
        expires: expires,
      );
    } catch (_) {
      throw const PeopleFailure(
        'This invitation is invalid or expired. Ask your friend for a new one.',
      );
    }
  }
}

// Mutable only so every reader loses access to discarded content immediately.
// Never serialize this object or put it into journal storage.
class PeopleNote {
  PeopleNote({
    required this.id,
    required this.friendKey,
    required String text,
    required this.now,
  }) : _text = text,
       duration = peopleReadingTime(text);
  final int id;
  final String friendKey;
  final Duration duration;
  String _text;
  final Duration Function() now;
  Duration? _openedAt;
  bool opened = false;
  String get text => _text;
  Duration get remaining => Duration(
    milliseconds: max(
      0,
      duration.inMilliseconds -
          (_openedAt == null ? 0 : (now() - _openedAt!).inMilliseconds),
    ),
  );
  void open() {
    if (!opened && _text.isNotEmpty) {
      opened = true;
      _openedAt = now();
    }
  }

  void discard() {
    _text = '';
  }
}
