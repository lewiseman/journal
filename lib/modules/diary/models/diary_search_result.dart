import 'package:journal/modules/diary/models/diary_day.dart';

class DiarySearchMatch {
  const DiarySearchMatch({
    required this.date,
    required this.title,
    required this.excerpt,
    required this.kind,
  });

  final DateTime date;
  final String title;
  final String excerpt;
  final DiaryItemKind kind;
}

class DiarySearchResult {
  const DiarySearchResult({required this.answer, required this.matches});

  final String answer;
  final List<DiarySearchMatch> matches;
}
