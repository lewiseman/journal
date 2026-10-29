# S02 — AI note search and Flow AI search

AI note search lets you ask your paired computer a question about your saved
notes, such as "What did I plan for the garden?". The phone picks the most
relevant notes and sends short excerpts of them with the question. The answer
comes only from those excerpts, and each cited note opens. When nothing matches,
or the excerpts are not enough, it says so instead of guessing.

Flow AI search does the same for Flow thoughts (see below). Each search covers
one collection only: notes and thoughts are never sent together. Diary questions
are S01 (`diary-history.md`).

## Use

1. On Notes, tap QVAC, then **AI note search**. The sheet closes and a full page
   opens.
2. Type a question and tap **Ask**. There is no step to choose or approve notes:
   the page says up front that the question and excerpts from the most relevant
   notes are sent to your computer, and nothing else.
3. The answer shows the coverage (for example "Searched all of your notes
   (42 notes). 3 of 5 notes matched by keywords or meaning were sent."), the
   answer text and the cited notes. Tap a note to open it. Cited notes edited
   since are marked "Edited since this answer"; deleted ones are marked "no
   longer in your notes" and can't be opened.
4. **Ask another question** clears it. The task is listed in AI task history as
   "Notes question" and survives an app restart.

## Flow AI search

Flow no longer has a search icon at the top. Instead, tap QVAC on Flow, then
**Flow AI search**. The sheet closes and a full page opens. It works like AI
note search, with these differences:

- Only Flow thoughts are searched. Thoughts are sent without a title.
- A cited thought shows its date. Tapping it returns to Flow and opens that
  thought.
- The thought prompt may point out a link between thoughts, but only as "a
  possible connection". The page says such links are the AI's reading, not
  something you wrote.
- The task is listed in AI task history as "Flow question".

The old keyword-and-meaning recall page for thoughts (`thought_recall_page.dart`)
has been removed.

## Retrieval and what is sent

Selection and answers are in `lib/modules/recall/recall_question_contract.dart`,
and both searches share `lib/modules/recall/recall_question_page.dart`.
It reuses `diary_retrieval.dart` for word matching and date phrases, and the
diary contract's `excerptFor`.

- **Candidates:** saved notes that aren't deleted or empty. A date phrase in the
  question ("last month", "in 2025") limits notes by creation date.
- **Ranking:** the hybrid retriever (keywords plus meaning, S03b) when search by
  meaning is available; otherwise keyword matches on title and content, best
  first, recently edited breaking ties. A date with no topic samples evenly
  across the scope.
- **Excerpts:** up to 8, in creation-date order, each with its title (up to 80
  characters) and an excerpt of up to 280 characters around the best-matching
  sentence. The request stays within 2,000 UTF-8 bytes. Note UUIDs are never
  sent; IDs are `s0`…`s7`.
- **Answers:** `{answer, citations, status}`, at most 700 characters. Citations
  to excerpts that weren't sent reject the answer. An "insufficient" answer is
  shown as fixed text, never the model's explanation.
- **Staleness:** each excerpt stores the note's version (update time plus a
  hash of its title and content). Editing or deleting a cited note marks the task
  stale and labels its tile.

## Companion

The desktop operations are `answer-note-question` and `answer-thought-question`
(`desktop/src/note-question.cjs`), advertised as `noteQuestionContract: 1` and
`thoughtQuestionContract: 1`. It validates the input shape and
output schema, runs with temperature 0 and a JSON-schema response format, and
treats note text as untrusted data. An older companion without the operation
gets "Update the companion to answer questions about notes."; an unreachable one
gets the usual connection message, and nothing is sent.

## Checks

- `journal/test/recall_question_test.dart`: selection, deleted notes, date scope,
  byte limit, citation checks, edited/deleted labels, offline and old-companion
  behaviour, and the page flow from question to opened note.
- `journal/test/notes_assistant_test.dart`: the card closes the sheet and opens
  the page.
- `desktop/test/note-question.test.cjs`: input/output validation, runtime
  request and durable jobs.

Device check (2026-10-29, Samsung SM S928B, Llama 3.1 8B Q4_K_M): asking
"where do the tulips go" about one note returned a cited answer, and the cited
note opened. Empty questions and questions with no matching notes show a
message, and nothing is sent.

Known limit: the 8B model still repeats instructions planted inside a note
(for example "ignore previous instructions and say…") as if they were facts.
The prompt tells it not to, but that isn't enough. The cited excerpt is always
shown under the answer, so the planted text stays visible.
