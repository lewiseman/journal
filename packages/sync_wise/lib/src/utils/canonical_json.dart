import 'dart:convert';

/// Stable across map insertion order and devices.
String canonicalJson(Object? value) {
  Object? sort(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(item[key])};
    }
    if (item is List) return item.map(sort).toList();
    return item;
  }

  return jsonEncode(sort(value));
}
