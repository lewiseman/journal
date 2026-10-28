import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:journal/modules/diary/suggestions/diary_suggestion_contract.dart';
import 'package:journal/modules/flow/models/thought_entity.dart';
import 'package:journal/modules/notes/summary/summary_controller.dart'
    show validSummaryText;

/// L01: one optional, one-line reflection on a single saved thought.
const thoughtReflectionOperation = 'reflect-thought';
const thoughtReflectionContract = 1;
const thoughtReflectionInputBytes = 2000;
const thoughtReflectionOutputBytes = 512;
const thoughtReflectionChars = 200;

/// Fingerprint of the exact thought a reflection was written for. A thought
/// is creation-only, but sync may still replace a record with another
/// device's copy, so every result is checked against this before it is shown.
String thoughtRevision(ThoughtEntity thought) => const DartSha256()
    .hashSync(
      utf8.encode(
        jsonEncode([
          thought.uuid,
          thought.createdAt.toUtc().toIso8601String(),
          thought.content,
        ]),
      ),
    )
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

final _lineBreak = RegExp(r'[\r\n\u2028\u2029]');

/// The envelope: one nonempty, well-formed line within the limits.
bool validThoughtReflectionLine(String text) {
  final line = text.trim();
  return validSummaryText(line, thoughtReflectionOutputBytes) &&
      line.runes.length <= thoughtReflectionChars &&
      !_lineBreak.hasMatch(line);
}

class ThoughtReflectionRejected implements Exception {
  const ThoughtReflectionRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[‘’‛`]'), "'")
    .replaceAll(RegExp(r'''[\s"“”„'.,;:!?…-]+'''), ' ')
    .trim();

// English-only safety nets after the prompt; they can miss paraphrases.
// A term the person wrote themselves is allowed back.
final _dramatic = RegExp(
  r"\b(always|never|every(one|body|thing)|nothing|truly|deeply|profound(ly)?|"
  r"forever|destiny|destined|meant to be|life[- ]changing|incredibl[ey]|no matter what|"
  r"(your|the) (whole|entire) life|everything will|you are (so|a|an|the|truly|clearly)|"
  r"you're (so|a|an|the|truly|clearly)|clearly you)\b",
  caseSensitive: false,
);
final _directive = RegExp(
  r"\b(you (must|should|need to|have to)|it's (important|essential|crucial) to|tell me|be honest|admit it|make sure|don't forget)\b",
  caseSensitive: false,
);

// The model speaking as an assistant rather than reflecting.
final _assistant = RegExp(
  r"\b(i('m| am) sorry|i can('t|not) (help|assist)|as an ai|language model|here is|here's a)\b",
  caseSensitive: false,
);

/// Phone-side checks on a reflection for [thought]. The phone holds the
/// thought text, so these checks are authoritative; the companion only
/// bounds the envelope.
String parseThoughtReflection(String text, String thought) {
  if (!validThoughtReflectionLine(text)) {
    throw const FormatException('Not one short line');
  }
  final line = text.trim();
  // Patterns are written with straight apostrophes.
  final plain = line.replaceAll(RegExp('[‘’‛`]'), "'");
  bool introduced(RegExp pattern) =>
      pattern.allMatches(plain).any((m) => !_wrote(thought, m.group(0)!));
  if (_assistant.hasMatch(plain)) {
    throw const ThoughtReflectionRejected(
      'Your computer did not return a reflection, so nothing was shown.',
    );
  }
  // Copying the thought, or a sentence of it, is not a reflection.
  if (_normalize(thought).contains(_normalize(line))) {
    throw const ThoughtReflectionRejected(
      'The reflection only repeated your thought, so it was not shown.',
    );
  }
  if (_sensitiveIntroduced(line, thought)) {
    throw const ThoughtReflectionRejected(
      'The reflection raised something too personal, so it was not shown.',
    );
  }
  if (introduced(_dramatic)) {
    throw const ThoughtReflectionRejected(
      'The reflection sounded more sweeping than your thought, so it was not shown.',
    );
  }
  if (introduced(_directive) || '?'.allMatches(line).length > 1) {
    throw const ThoughtReflectionRejected(
      'The reflection pushed instead of reflecting, so it was not shown.',
    );
  }
  return line;
}

/// Whether [thought] contains [term] as whole words, ignoring case.
bool _wrote(String thought, String term) =>
    RegExp('\\b${RegExp.escape(_normalize(term))}\\b')
        .hasMatch(_normalize(thought));

/// A sensitive one- or two-word term in [line] that [thought] lacks.
bool _sensitiveIntroduced(String line, String thought) {
  if (!introducesSensitiveTerm(line)) return false;
  final words = _normalize(line).split(' ');
  for (var i = 0; i < words.length; i++) {
    final one = words[i];
    if (introducesSensitiveTerm(one)) {
      if (!_wrote(thought, one)) return true;
    } else if (i + 1 < words.length &&
        !introducesSensitiveTerm(words[i + 1]) &&
        introducesSensitiveTerm('$one ${words[i + 1]}') &&
        !_wrote(thought, '$one ${words[i + 1]}')) {
      return true;
    }
  }
  return false;
}
