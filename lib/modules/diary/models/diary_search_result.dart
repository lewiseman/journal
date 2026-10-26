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
  const DiarySearchResult({required this.answer, required this.matches});

  final String answer;
  final List<DiarySearchMatch> matches;
}
