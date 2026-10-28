# Android voice

The microphone buttons in Notes, Flow and diary now use real Android capture. Notes inserts reviewed text into its existing editor. Flow explicitly saves one reviewed thought. Diary supports typing, reviewed spoken input, follow-up questions, correction and an editable first-person draft. No diary or note write occurs automatically.

Pair the updated Electron companion in Settings. On the companion, download a multilingual Whisper model and Silero VAD, then select Whisper and load speech. Large v3 Turbo was measured on the local Apple Silicon host. For diary conversation, load a capable writing model first, then speech. Tapping the diary mic opens a hands-free talk page over one live connection to the companion: it speaks, the microphone opens (words appear after short pauses), and when you pause for about a second the computer takes your turn and streams its reply, which the phone speaks before handing the mic back. "I'm done" ends a turn at once. The microphone is off while the companion speaks. Finish returns to the conversation page, where turns can be corrected and the draft is reviewed. The first question can follow up on recent diary entries, selected the same way as the daily question (today's latest four, then up to eight from the past seven days, within 2,000 bytes). Its replies are read aloud by the phone's own text-to-speech (mutable in the app bar, replayable per reply) and also shown as text; playback stops before the microphone opens.

The workspace's full protocol, retention policy, setup and evidence are in [the companion voice guide](../../desktop/docs/VOICE.md). Three consecutive native captures on a Samsung SM-S928B completed over the trusted LAN against real QVAC; both models remained ready after idle. English/Swahili/code-switching recognition quality remains a manual verification gate.

Relevant tests:

```sh
flutter test test/voice_session_test.dart test/voice_capture_recovery_test.dart test/pcm_recorder_test.dart test/flow_page_test.dart \
  test/note_attachments_test.dart test/diary_day_content_test.dart \
  test/diary_conversation_test.dart test/thoughts_storage_test.dart \
  test/diary_storage_test.dart test/account_reset_integration_test.dart
flutter test integration_test/voice_capture_android_test.dart -d emulator-5554 --no-uninstall
flutter test integration_test/voice_repeat_device_test.dart -d DEVICE_SERIAL \
  --no-uninstall --dart-define=RUN_REAL_VOICE_REPEAT=true
```

Before the device test, grant microphone permission to the test app. It creates and deletes a temporary app-private PCM recording; it does not initialize the journal database. The test proves capture/file/stream plumbing, not recognition accuracy or a physical-phone LAN run.

Always pass **`--no-uninstall`** when testing against the installed app: Flutter otherwise uninstalls Journal and deletes its phone-local data after the test. Reinstall the normal APK with `adb install -r` afterward. The repeat diagnostic uses existing protected trust, or an explicitly supplied short-lived pairing code with matching desktop approval. It never writes journal entries and prints byte counts rather than transcripts. The recorder drains the native terminal event before cancelling its subscription; an already stopped controller cannot stop a newer recorder during disposal.
