class DiarySearchMatch {
  const DiarySearchMatch({
    required this.date,
    required this.title,
    required this.excerpt,
  });

  final DateTime date;
  final String title;
  final String excerpt;
}

class DiarySearchResult {
  const DiarySearchResult({
    required this.answer,
    required this.matches,
    this.note,
  });

  final String answer;
  final List<DiarySearchMatch> matches;

  /// Set when results are keyword-only, saying why.
  final String? note;
}
