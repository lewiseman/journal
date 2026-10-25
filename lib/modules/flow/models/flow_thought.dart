/// Session-only content for the Flow prototype, independent of saved notes.
class FlowThought {
  const FlowThought({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.paper,
    this.isSample = false,
  });

  final int id;
  final String text;
  final DateTime createdAt;
  final int paper;
  final bool isSample;

  static List<FlowThought> samples(DateTime now) {
    const thoughts = [
      'Maybe a slower morning is a good place to start.',
      'I want to make more things just for the joy of making them.',
      'That little walk cleared more space in my head than I expected.',
      'A reminder to myself: I don’t have to figure it all out today.',
      'What if I said yes to the idea I keep coming back to?',
      'Coffee, an open window, and nowhere to rush. More of this, please.',
      'I felt most like myself when I stopped trying to be productive for a moment.',
      'An idea for the weekend: take the long way home and see what I notice.',
      'Some things feel smaller once I put them into words.',
      'I should tell the people I love about the little things they do that stay with me.',
      'Learning to leave a little room for things I didn’t plan.',
      'There was a moment today when everything felt quietly okay. I want to remember that.',
    ];
    return [
      for (var i = 0; i < thoughts.length; i++)
        FlowThought(
          id: i,
          text: thoughts[i],
          createdAt: now.subtract(Duration(hours: i < 3 ? i + 1 : i * 12)),
          paper: i,
          isSample: true,
        ),
    ];
  }
}
