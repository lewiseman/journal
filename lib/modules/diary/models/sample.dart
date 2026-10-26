import 'dart:convert';

import 'package:journal/utils/time_helper.dart';
import 'package:journal/modules/diary/models/diary_day_entity.dart';
import 'package:journal/modules/diary/models/diary_item.dart';

/// Read-only examples shared by the diary reader, calendar, and search.
final List<DiaryDayEntity> sampleDiaries = buildSampleDiaries(DateTime.now());

/// Builds the latest 30 civil days. A few dates intentionally have no entry.
List<DiaryDayEntity> buildSampleDiaries(DateTime today) {
  const passages = [
    'The light came in through the kitchen window before the rest of the '
        'day had quite begun. I made coffee, left my phone on the table, '
        'and watched the street wake up. Nothing remarkable happened. '
        'Still, it felt like a moment I would want to come back to.',
    'I took a different route on my walk and found a little garden tucked '
        'between two buildings. Someone had planted herbs in old pots. '
        'There was a bench in the shade, and for a while I just sat there. '
        'I keep forgetting how much a change of scenery can change the '
        'shape of a thought.',
    'We talked about ordinary things: what to cook, a book neither of us '
        'has finished, the plans we keep moving to next weekend. I felt '
        'lighter after our conversation. Maybe being understood often '
        'looks like this — making room for the little details of someone '
        'else’s day.',
    'There are still things I have not figured out. Today I tried leaving '
        'them unfinished without treating that as a failure. I cleared '
        'one corner of the desk, put on a familiar album, and did the '
        'next small thing. That was enough to get going again.',
    'I want to remember the sound of rain while dinner was cooking, '
        'the message that arrived exactly when I needed it, and the '
        'feeling of finally closing my laptop. A day can hold so many '
        'different things. Writing them down helps me see what was here.\n\n'
        'Before bed, I opened the window and listened for a while. '
        'There was nothing else I needed to finish tonight.',
  ];
  const quiet =
      'I felt calm and a little more present today, '
      'with room for a little wonder.';
  const note = 'Leave a little room for things you didn’t plan.';
  const moods = [
    (emoji: '😊', name: 'Happy', category: 'happy'),
    (emoji: '😌', name: 'Calm', category: 'calm'),
    (emoji: '🤩', name: 'Excited', category: 'excited'),
    (emoji: '😴', name: 'Tired', category: 'tired'),
    (emoji: '😔', name: 'Low', category: 'low'),
  ];
  return List.unmodifiable([
    for (var offset = 0; offset < 30; offset++)
      if (offset % 7 != 6)
        () {
          final date = TimeHelper.addDays(today, -offset);
          final key = TimeHelper.dateKey(date);
          final seed = TimeHelper.daysBetween(DateTime(1970), date);
          final length = seed % 3;
          final mood = moods[seed % moods.length];
          final content = [
            quiet,
            if (length == 1) passages[seed % passages.length],
            if (length == 2) ...passages,
            note,
          ];
          final items = [
            for (var i = 0; i < content.length; i++)
              DiaryItem(
                itemUuid: 'sample-$key-$i',
                createdAt: DateTime.utc(date.year, date.month, date.day, 8 + i),
                updatedAt: DateTime.utc(date.year, date.month, date.day, 8 + i),
                content: content[i],
              ),
          ];
          return DiaryDayEntity(
            dateString: key,
            dayTitle: const [
              'The quiet was enough.',
              'A little room to breathe.',
              'So much in an ordinary day.',
            ][length],
            dayMood: offset % 4 == 0
                ? null
                : jsonEncode({
                    'emoji': mood.emoji,
                    'name': mood.name,
                    'category': mood.category,
                  }),
            createdAt: items.first.createdAt,
            updatedAt: items.last.updatedAt,
          )..items = items;
        }(),
  ]);
}
