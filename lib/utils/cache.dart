import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences/util/legacy_to_async_migration_util.dart';

// final storage = CacheStorage.instance;

// // Save
// await storage.set(userNameKey, 'Lewis');
// await storage.set(firstTimeUserKey, false);

// // Read
// final name = storage.get(userNameKey);

// // Read with default
// final isFirstTime = storage.getOrDefault(
//   firstTimeUserKey,
//   true,
// );

// // Check existence
// final hasName = storage.contains(userNameKey);

// // Remove
// await storage.remove(userNameKey);

// // Store JSON-compatible settings
// await storage.set(localSettingsKey, {
//   'theme': 'dark',
//   'accentColor': '#8B5CF6',
//   'notifications': true,
// });

// // Retrieve settings
// final settings = storage.get(localSettingsKey);

// // Clear app namespace
// await storage.clearNamespace(CacheNamespace.app);

// // Clear all managed preferences
// await storage.clearAll();

// ─────────────────────────────────────────────
// Keys
// ─────────────────────────────────────────────

enum CacheNamespace { app, user }

final class CacheKey<T> {
  const CacheKey(this.namespace, this.name) : assert(name != '');

  final CacheNamespace namespace;
  final String name;
}

// App settings
const localSettingsKey = CacheKey<Map<String, dynamic>>(
  CacheNamespace.app,
  'localSettings',
);

const lastPageRouteKey = CacheKey<String>(CacheNamespace.app, 'lastPageRoute');

const firstTimeUserKey = CacheKey<bool>(CacheNamespace.app, 'firstTimeUser');

const userNameKey = CacheKey<String>(CacheNamespace.app, 'userName');

// The text-to-speech engine and voice for companion replies: {engine, name, locale}.
const replyVoiceKey = CacheKey<Map<String, dynamic>>(
  CacheNamespace.app,
  'replyVoice',
);

// ─────────────────────────────────────────────
// Storage abstraction
// ─────────────────────────────────────────────

abstract interface class KeyValueStore {
  Object? get(String key);

  Future<void> put(String key, Object value);

  bool containsKey(String key);

  Set<String> getKeys();

  Future<void> remove(String key);

  Future<void> reload();
}

// ─────────────────────────────────────────────
// SharedPreferences implementation
// ─────────────────────────────────────────────

final class SharedPrefsStore implements KeyValueStore {
  SharedPrefsStore(this._prefs);

  final SharedPreferencesWithCache _prefs;

  @override
  Object? get(String key) => _prefs.get(key);

  @override
  bool containsKey(String key) => _prefs.containsKey(key);

  @override
  Set<String> getKeys() => _prefs.keys;

  @override
  Future<void> remove(String key) => _prefs.remove(key);

  @override
  Future<void> reload() => _prefs.reloadCache();

  @override
  Future<void> put(String key, Object value) async {
    switch (value) {
      case String v:
        await _prefs.setString(key, v);

      case bool v:
        await _prefs.setBool(key, v);

      case int v:
        await _prefs.setInt(key, v);

      case double v:
        await _prefs.setDouble(key, v);

      case List<String> v:
        await _prefs.setStringList(key, v);

      default:
        throw UnsupportedError(
          'Unsupported storage type: ${value.runtimeType}',
        );
    }
  }
}

// ─────────────────────────────────────────────
// CacheStorage
// ─────────────────────────────────────────────

final class CacheStorage {
  CacheStorage._(this._store);

  /// Allows independent instances in unit tests.
  CacheStorage.test(this._store);

  final KeyValueStore _store;

  static CacheStorage? _instance;
  static Future<void>? _initialization;

  static CacheStorage get instance {
    return _instance ??
        (throw StateError(
          'CacheStorage is not initialized. '
          'Call CacheStorage.init() first.',
        ));
  }

  // ───────────────────────────────────────────
  // Configuration
  // ───────────────────────────────────────────

  static const String _docVersion = 'V001';

  static String get _environment {
    if (kReleaseMode) return 'Prod';
    if (kProfileMode) return 'Test';
    return 'Dev';
  }

  static String get _prefix => '$_environment-$_docVersion';

  String _key<T>(CacheKey<T> key) {
    return '$_prefix:${key.namespace.name}:${key.name}';
  }

  // ───────────────────────────────────────────
  // Initialization
  // ───────────────────────────────────────────

  static Future<void> init({KeyValueStore? store}) {
    if (_instance != null) {
      return Future<void>.value();
    }

    return _initialization ??= _initialize(store);
  }

  static Future<void> _initialize(KeyValueStore? store) async {
    try {
      if (store != null) {
        _instance = CacheStorage._(store);
        return;
      }

      // Migrate values written using the legacy
      // SharedPreferences API, once per installation.
      final legacy = await SharedPreferences.getInstance();

      await migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary(
        legacySharedPreferencesInstance: legacy,
        sharedPreferencesAsyncOptions: const SharedPreferencesOptions(),
        migrationCompletedKey: '__cache_storage_migration_v1',
      );

      final prefs = await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );

      _instance = CacheStorage._(SharedPrefsStore(prefs));
    } catch (_) {
      // Allow initialization to be retried.
      _initialization = null;
      rethrow;
    }
  }

  // ───────────────────────────────────────────
  // Write
  // ───────────────────────────────────────────

  Future<void> set<T>(CacheKey<T> key, T value) {
    final Object storedValue;

    if (value is Map<String, dynamic>) {
      storedValue = jsonEncode(value);
    } else if (value is String ||
        value is bool ||
        value is int ||
        value is double ||
        value is List<String>) {
      storedValue = value as Object;
    } else {
      throw UnsupportedError(
        'Unsupported type for "${key.name}": '
        '${value.runtimeType}',
      );
    }

    return _store.put(_key(key), storedValue);
  }

  // ───────────────────────────────────────────
  // Read
  // ───────────────────────────────────────────

  T? get<T>(CacheKey<T> key) {
    final raw = _store.get(_key(key));

    if (raw == null) return null;

    // JSON maps
    if (T == Map<String, dynamic>) {
      if (raw is! String) return null;

      try {
        final decoded = jsonDecode(raw);

        if (decoded is Map<String, dynamic>) {
          return decoded as T;
        }
      } on FormatException {
        return null;
      }

      return null;
    }

    // String lists
    if (T == List<String>) {
      if (raw is! List || !raw.every((item) => item is String)) {
        return null;
      }

      return List<String>.from(raw) as T;
    }

    // Primitive values
    return raw is T ? raw as T : null;
  }

  // ───────────────────────────────────────────
  // Convenient reads
  // ───────────────────────────────────────────

  T getOrDefault<T>(CacheKey<T> key, T defaultValue) {
    return get(key) ?? defaultValue;
  }

  bool contains<T>(CacheKey<T> key) {
    return _store.containsKey(_key(key));
  }

  // ───────────────────────────────────────────
  // Delete
  // ───────────────────────────────────────────

  Future<void> remove<T>(CacheKey<T> key) {
    return _store.remove(_key(key));
  }

  Future<void> clearNamespace(CacheNamespace namespace) {
    return _clearPrefix('$_prefix:${namespace.name}:');
  }

  /// Clears only keys managed by this version
  /// and environment of CacheStorage.
  Future<void> clearAll() {
    return _clearPrefix('$_prefix:');
  }

  Future<void> _clearPrefix(String prefix) async {
    final keys = _store
        .getKeys()
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);

    for (final key in keys) {
      await _store.remove(key);
    }
  }

  // ───────────────────────────────────────────
  // Refresh
  // ───────────────────────────────────────────

  /// Refresh the local preferences cache from
  /// platform storage when external writes occur.
  Future<void> reload() => _store.reload();
}
