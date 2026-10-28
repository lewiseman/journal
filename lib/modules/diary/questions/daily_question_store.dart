import 'package:journal/modules/diary/questions/daily_question_contract.dart';
import 'package:journal/modules/diary/questions/daily_question_entity.dart';
import 'package:journal/objectbox/objectbox.g.dart';

/// Small local history: today's question and enough recent questions to
/// avoid repeating them. At most [keep] rows from the last [days] days.
class DailyQuestionStore {
  DailyQuestionStore(this._store) : _box = _store.box<DailyQuestionEntity>();
  final Store _store;
  final Box<DailyQuestionEntity> _box;
  static const keep = 30, days = 30;

  List<DailyQuestionEntity> _newest() {
    final query = _box
        .query()
        .order(DailyQuestionEntity_.created, flags: Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// The latest question still shown for [day], or null.
  DailyQuestionEntity? current(String day) {
    final query =
        _box
            .query(
              DailyQuestionEntity_.day.equals(day) &
                  DailyQuestionEntity_.status.equals('shown'),
            )
            .order(DailyQuestionEntity_.created, flags: Order.descending)
            .build()
          ..limit = 1;
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  /// Recent question texts, newest first, shown or skipped.
  List<String> recent([int limit = keep]) => [
    for (final row in _newest().take(limit)) row.question,
  ];

  DailyQuestionEntity add(
    String day,
    DailyQuestion question, {
    String basis = '',
    int? now,
  }) {
    final created = now ?? DateTime.now().millisecondsSinceEpoch;
    final row = DailyQuestionEntity(
      day: day,
      question: question.text,
      sourceDate: question.sourceDate,
      sourceItem: question.sourceItem,
      evidence: question.evidence,
      ago: question.ago,
      basis: basis,
      created: created,
    );
    _store.runInTransaction(TxMode.write, () {
      for (final old in _box.getAll()) {
        if (old.day == day && old.status == 'shown') {
          _box.put(old..status = 'skipped');
        }
      }
      _box.put(row);
      final cutoff = created - const Duration(days: days).inMilliseconds;
      final rows = _newest();
      _box.removeMany([
        for (final (index, old) in rows.indexed)
          if (index >= keep || old.created < cutoff) old.id,
      ]);
    });
    return row;
  }

  void skip(int id) {
    final row = _box.get(id);
    if (row != null) _box.put(row..status = 'skipped');
  }

  void clear() => _box.removeAll();

  DailyQuestion? question(DailyQuestionEntity? row) => row == null
      ? null
      : DailyQuestion(
          text: row.question,
          sourceDate: row.sourceDate,
          sourceItem: row.sourceItem,
          evidence: row.evidence,
          ago: row.ago,
        );
}
