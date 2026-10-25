/// Calendar dates, rather than elapsed 24-hour intervals, identify diary sheets.
DateTime diaryDate(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime diaryDayAfter(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

int diaryDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

enum DiaryItemKind { reflection, note, mood, checklist }

class DiaryItem {
  const DiaryItem(this.kind, this.title, this.text, {this.tasks = const []});

  final DiaryItemKind kind;
  final String title;
  final String text;
  final List<({String text, bool done})> tasks;
}

/// Read-only prototype content. Nothing here is written to the user's journal.
class DiaryDay {
  const DiaryDay({
    required this.date,
    required this.title,
    required this.items,
  });

  final DateTime date;
  final String title;
  final List<DiaryItem> items;

  static DiaryDay sample(DateTime value) {
    final date = diaryDate(value);
    final seed = diaryDaysBetween(DateTime(1970), date);
    final length = seed % 3;
    const reflections = [
      DiaryItem(
        DiaryItemKind.reflection,
        'The small things',
        'The light came in through the kitchen window before the rest of the '
            'day had quite begun. I made coffee, left my phone on the table, '
            'and watched the street wake up. Nothing remarkable happened. '
            'Still, it felt like a moment I would want to come back to.',
      ),
      DiaryItem(
        DiaryItemKind.reflection,
        'Taking the long way',
        'I took a different route on my walk and found a little garden tucked '
            'between two buildings. Someone had planted herbs in old pots. '
            'There was a bench in the shade, and for a while I just sat there. '
            'I keep forgetting how much a change of scenery can change the '
            'shape of a thought.',
      ),
      DiaryItem(
        DiaryItemKind.reflection,
        'A conversation to keep',
        'We talked about ordinary things: what to cook, a book neither of us '
            'has finished, the plans we keep moving to next weekend. I felt '
            'lighter afterwards. Maybe being understood often looks like '
            'this — making room for the little details of someone else’s day.',
      ),
      DiaryItem(
        DiaryItemKind.reflection,
        'Making a little space',
        'There are still things I have not figured out. Today I tried leaving '
            'them unfinished without treating that as a failure. I cleared '
            'one corner of the desk, put on a familiar album, and did the '
            'next small thing. That was enough to get going again.',
      ),
      DiaryItem(
        DiaryItemKind.reflection,
        'Before the day ends',
        'I want to remember the sound of rain while dinner was cooking, '
            'the message that arrived exactly when I needed it, and the '
            'feeling of finally closing my laptop. A day can hold so many '
            'different things. Writing them down helps me see what was here.',
      ),
    ];
    const mood = DiaryItem(
      DiaryItemKind.mood,
      'A little more present',
      'Calm, with room for a little wonder.',
    );
    const note = DiaryItem(
      DiaryItemKind.note,
      'A note to myself',
      'Leave a little room for things you didn’t plan.',
    );
    const checklist = DiaryItem(
      DiaryItemKind.checklist,
      'Small intentions',
      '',
      tasks: [
        (text: 'Step outside for a little while', done: true),
        (text: 'Make something just for the joy of it', done: true),
        (text: 'Check in with someone I love', done: false),
      ],
    );
    return DiaryDay(
      date: date,
      title: const [
        'The quiet was enough.',
        'A little room to breathe.',
        'So much in an ordinary day.',
      ][length],
      items: List.unmodifiable([
        mood,
        if (length > 0) reflections[seed % reflections.length],
        if (length == 2)
          for (var i = 1; i <= 2; i++)
            reflections[(seed + i) % reflections.length],
        if (length > 0) checklist,
        note,
        if (length == 2)
          for (var i = 3; i <= 4; i++)
            reflections[(seed + i) % reflections.length],
      ]),
    );
  }
}
