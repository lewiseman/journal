import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:journal/modules/voice/controllers/reply_voice.dart';
import 'package:journal/utils/cache.dart';

const _sample = 'Hi. How did your day go? Tell me about one thing you noticed.';

String _engineLabel(String engine) => switch (engine) {
  'com.google.android.tts' => 'Google',
  'com.samsung.SMT' => 'Samsung',
  _ => engine,
};

/// Picks the text-to-speech engine and voice that reads companion replies.
/// The choice is kept in [CacheStorage] and used the next time a diary
/// conversation opens. Voices that need the internet are shown but disabled,
/// because replies are never sent off the phone.
class ReplyVoicePage extends StatefulWidget {
  const ReplyVoicePage({super.key});
  @override
  State<ReplyVoicePage> createState() => _ReplyVoicePageState();
}

class _ReplyVoicePageState extends State<ReplyVoicePage> {
  final _tts = FlutterTts();
  Map<String, String>? _saved = savedReplyVoice();
  List<String> _engines = [];
  List<Map<String, String>> _voices = [];
  String? _engine, _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final engines = (await _tts.getEngines as List? ?? const [])
          .cast<String>()
          .toList();
      final engine =
          _saved?['engine'] ?? await _tts.getDefaultEngine as String?;
      _engines = engines;
      await _selectEngine(engine ?? engines.firstOrNull);
    } catch (_) {
      _fail('Could not read this phone’s text-to-speech engines.');
    }
  }

  Future<void> _selectEngine(String? engine) async {
    if (engine == null) return _fail('No text-to-speech engine is installed.');
    setState(() {
      _engine = engine;
      _loading = true;
      _error = null;
    });
    try {
      await _tts.stop();
      await _tts.setEngine(engine);
      final voices = [
        for (final v in (await _tts.getVoices as List? ?? const []))
          Map<String, String>.from(v as Map),
      ]..retainWhere((v) => v['locale']?.startsWith('en') ?? false);
      // Offline voices first, then by accent and name.
      voices.sort(
        (a, b) => [
          (a['network_required'] ?? '0').compareTo(b['network_required'] ?? '0'),
          a['locale']!.compareTo(b['locale']!),
          a['name']!.compareTo(b['name']!),
        ].firstWhere((c) => c != 0, orElse: () => 0),
      );
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _loading = false;
      });
    } catch (_) {
      _fail('${_engineLabel(engine)} could not be started.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Map<String, String> _choice(Map<String, String> voice) => {
    'engine': _engine!,
    'name': voice['name']!,
    'locale': voice['locale']!,
  };

  Future<void> _preview(Map<String, String> voice) async {
    try {
      await _tts.stop();
      await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
      await _tts.speak(_sample);
    } catch (_) {}
  }

  Future<void> _choose(Map<String, String> voice) async {
    final choice = _choice(voice);
    await CacheStorage.instance.set(replyVoiceKey, choice);
    if (!mounted) return;
    setState(() => _saved = choice);
    unawaited(_preview(voice));
  }

  Future<void> _useDefault() async {
    await _tts.stop();
    await CacheStorage.instance.remove(replyVoiceKey);
    if (mounted) setState(() => _saved = null);
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reply voice')),
      body: !Platform.isAndroid
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Choosing a reply voice is available on Android.'),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'The voice that reads your companion’s questions aloud. It runs on this phone. Tap a voice to choose it and hear a sample. For better voices, install Speech Services by Google and download its voice data.',
                  ),
                ),
                if (_engines.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final engine in _engines)
                          ChoiceChip(
                            label: Text(_engineLabel(engine)),
                            selected: engine == _engine,
                            onSelected: _loading
                                ? null
                                : (_) => _selectEngine(engine),
                          ),
                      ],
                    ),
                  ),
                ListTile(
                  key: const ValueKey('reply-voice-default'),
                  leading: Icon(
                    _saved == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('Phone default'),
                  subtitle: const Text('Whatever is set in Android settings'),
                  onTap: _useDefault,
                ),
                const Divider(),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!),
                  )
                else if (_voices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'This engine has no English voices installed. Download voice data in Android text-to-speech settings.',
                    ),
                  )
                else
                  for (final voice in _voices) _tile(voice, theme),
              ],
            ),
    );
  }

  Widget _tile(Map<String, String> voice, ThemeData theme) {
    final online = voice['network_required'] == '1';
    final selected =
        _saved?['engine'] == _engine && _saved?['name'] == voice['name'];
    return ListTile(
      enabled: !online,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: online ? null : theme.colorScheme.primary,
      ),
      title: Text(voice['name']!),
      subtitle: Text(
        [
          voice['locale'],
          if (voice['quality'] case final q? when q != 'unknown') '$q quality',
          if (online) 'needs internet · unavailable',
        ].join(' · '),
      ),
      trailing: online
          ? null
          : IconButton(
              tooltip: 'Play sample',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => _preview(voice),
            ),
      onTap: online ? null : () => _choose(voice),
    );
  }
}
