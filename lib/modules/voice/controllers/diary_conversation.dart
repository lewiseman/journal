import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:journal/modules/settings/companion/companion_protocol.dart';

import 'voice_store.dart';

class DiaryConversation extends ChangeNotifier {
  DiaryConversation({
    required this.computer,
    required this.dateString,
    VoiceStore? store,
    CompanionTransport Function()? transportFactory,
    this.onReply,
    this.diary,
    this.autoOpen = true,
  }) : store = store ?? VoiceStore(),
       transportFactory = transportFactory ?? PinnedCompanionTransport.new;
  final TrustedComputer Function() computer;
  final VoiceStore store;
  final CompanionTransport Function() transportFactory;
  final String dateString;
  // Called with each new companion question so it can be spoken aloud.
  // Mutable so a talk page can take over speaking while it is open.
  void Function(String text)? onReply;
  // Recent diary entries ({daysAgo, text}) the opening question may follow up on.
  final List<Map<String, Object>> Function()? diary;
  // False when a live talk session asks the first question instead.
  final bool autoOpen;
  String id = const Uuid().v4(),
      draft = '',
      message = 'Start anywhere. Type, or record and review your words.';
  int created = DateTime.now().millisecondsSinceEpoch;
  List<Map<String, String>> turns = [];
  Map<String, dynamic>? pending;
  String? computerId, deviceId;
  bool busy = false, disposed = false, saved = false;
  Timer? _poll;
  Future<void> _writes = Future.value();
  void update() {
    if (!disposed) notifyListeners();
  }

  Future<void> persist() {
    if (disposed) return Future.value();
    final snapshot = {
      'id': id,
      'date': dateString,
      'created': created,
      'turns': turns.map((t) => Map<String, String>.from(t)).toList(),
      'draft': draft,
      'pending': pending == null ? null : Map<String, dynamic>.from(pending!),
      'computer': computerId,
      'device': deviceId,
      'saved': saved,
    };
    _writes = _writes
        .catchError((_) {})
        .then((_) => store.save('diary', snapshot));
    return _writes;
  }

  Future<void> restore() async {
    busy = true;
    update();
    try {
      final v = await store.load('diary');
      if (disposed) return;
      if (v == null) {
        busy = false;
        update();
        await open();
        return;
      }
      if (v['date'] != dateString) {
        message =
            'A conversation for ${v['date']} is retained. Open that day to recover it, or discard it here before starting.';
        busy = false;
        saved = true;
        update();
        return;
      }
      id = v['id'] as String;
      created = v['created'] as int;
      turns = (v['turns'] as List)
          .map((t) => Map<String, String>.from(t as Map))
          .toList();
      draft = v['draft'] as String;
      pending = v['pending'] == null
          ? null
          : Map<String, dynamic>.from(v['pending'] as Map);
      computerId = v['computer'] as String?;
      deviceId = v['device'] as String?;
      saved = v['saved'] == true;
      message = saved
          ? 'This conversation has already been saved. Original turns remain recoverable for 24 hours.'
          : 'Recovered conversation. Review the original turns before continuing.';
      busy = false;
      update();
      if (pending != null) {
        await retrieve();
      } else if (turns.isEmpty) {
        await open();
      }
    } catch (_) {
      busy = false;
      message = 'Could not recover this protected conversation. Unlock the phone and reopen.';
      update();
    }
  }

  TrustedComputer trusted() {
    final c = computer();
    if (!c.enabled ||
        (computerId != null &&
            (c.id != computerId || c.deviceId != deviceId))) {
      throw const CompanionFailure(
        'UNAUTHORIZED',
        'This conversation belongs to another trusted pairing. Restore it or start a new conversation explicitly.',
      );
    }
    return c;
  }

  Future<void> add(String text) async {
    if (busy || saved || text.trim().isEmpty || pending != null) return;
    if (turns.length >= 24) {
      throw const CompanionFailure(
        'INPUT_LIMIT',
        'This conversation has reached 24 turns. Review a draft before starting another.',
      );
    }
    turns.add({'speaker': 'user', 'text': text.trim()});
    draft = '';
    await persist();
    update();
  }

  Future<void> correct(int index, String text) async {
    if (busy || saved || pending != null || text.trim().isEmpty) return;
    turns[index] = {'speaker': 'user', 'text': text.trim()};
    draft = '';
    await persist();
    message = 'Source corrected. Generate a new draft from these turns.';
    update();
  }

  /// Lets the companion ask the first question of an empty conversation.
  Future<void> open() async {
    if (autoOpen && turns.isEmpty) await request('open');
  }

  /// Records a turn exchanged in a live talk session, where the computer
  /// has already transcribed or written it.
  Future<void> append(String speaker, String text) async {
    if (saved || text.trim().isEmpty) return;
    turns.add({'speaker': speaker, 'text': text.trim()});
    draft = '';
    await persist();
    update();
  }

  Future<void> request(String action) async {
    if (busy ||
        saved ||
        pending != null ||
        (action == 'open'
            ? turns.isNotEmpty
            : turns.every((t) => t['speaker'] != 'user'))) {
      return;
    }
    try {
      final c = trusted();
      final prompt = jsonEncode({
        'action': action,
        'turns': turns,
        if (action == 'open') 'diary': diary?.call() ?? const [],
      });
      if (utf8.encode(prompt).length > 6000) {
        throw const CompanionFailure(
          'INPUT_LIMIT',
          'This conversation exceeds 6,000 UTF-8 bytes. Nothing was truncated or sent. Shorten the source through correction before requesting a draft.',
        );
      }
      computerId = c.id;
      deviceId = c.deviceId;
      pending = {
        'id': const Uuid().v4(),
        'action': action,
        'prompt': prompt,
        'accepted': false,
      };
      await persist();
      await retrieve();
    } catch (e) {
      message = e is CompanionFailure
          ? e.message
          : 'Could not protect this conversation. Unlock the phone and retry.';
      update();
    }
  }

  Future<void> retrieve() async {
    if (pending == null || busy || disposed) return;
    busy = true;
    message = pending!['action'] == 'open'
        ? 'Your companion is starting the conversation…'
        : 'Working on your computer…';
    update();
    final transport = transportFactory();
    try {
      final c = trusted(), client = CompanionClient(transport);
      Map<String, dynamic> job;
      try {
        job = await client.authenticated(
          c,
          'GET',
          '/v1/jobs/${pending!['id']}',
        );
      } on CompanionFailure catch (e) {
        if (e.code != 'NOT_FOUND' || pending!['accepted'] == true) rethrow;
        job = await client.authenticated(
          c,
          'POST',
          '/v1/jobs',
          body: {
            'id': pending!['id'],
            'operation': 'diary.conversation',
            'prompt': pending!['prompt'],
            'expires': created + 86400000,
          },
        );
      }
      if (disposed) return;
      if (job['id'] != pending!['id'] ||
          job['device'] != deviceId ||
          job['operation'] != 'diary.conversation') {
        throw const FormatException();
      }
      pending!['accepted'] = true;
      await persist();
      if (disposed) return;
      if (job['state'] == 'completed') {
        final output = job['text'];
        if (output is! String ||
            output.trim().isEmpty ||
            utf8.encode(output).length > 8000) {
          throw const FormatException();
        }
        if (pending!['action'] == 'draft') {
          draft = output;
          message =
              'Review and edit this first-person draft. Check every fact against your own turns below.';
        } else {
          turns.add({'speaker': 'assistant', 'text': output});
          message = pending!['action'] == 'open'
              ? 'Answer by typing or recording, whenever you are ready.'
              : 'You can answer, correct your earlier words, or finish whenever you like.';
          onReply?.call(output);
        }
        final jobId = pending!['id'];
        pending = null;
        await persist();
        try {
          await client.authenticated(c, 'POST', '/v1/jobs/$jobId/ack');
        } catch (_) {}
      } else if (['queued', 'running'].contains(job['state'])) {
        message = 'Accepted on your computer. This request continues if the app closes.';
        _poll = Timer(const Duration(seconds: 2), () => unawaited(retrieve()));
      } else {
        pending = null;
        await persist();
        message =
            'The request ${job['state']}. Your original turns are retained. Generate again explicitly.';
      }
    } catch (e) {
      if (!disposed) message = e is CompanionFailure ? e.message : 'No verified response. Your original turns and request identity are retained; retrieve again.';
    } finally {
      transport.close();
      busy = false;
      update();
    }
  }

  Future<void> clear() async {
    if (busy) return;
    _poll?.cancel();
    if (pending != null) {
      final transport = transportFactory();
      try {
        await CompanionClient(transport).authenticated(
          trusted(),
          'POST',
          '/v1/jobs/${pending!['id']}/cancel',
          body: {'operation': 'diary.conversation'},
        );
      } catch (_) {
      } finally {
        transport.close();
      }
    }
    await _writes.catchError((_) {});
    await store.clear('diary');
    turns = [];
    draft = '';
    pending = null;
    id = const Uuid().v4();
    created = DateTime.now().millisecondsSinceEpoch;
    computerId = null;
    deviceId = null;
    saved = false;
    busy = false;
    message = 'Start a new conversation whenever you are ready.';
    update();
    await open();
  }

  @override
  void dispose() {
    disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
