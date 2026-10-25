import 'dart:convert';

/// Represents a Version Vector (Causal Clock) for tracking distributed revisions.
/// Maps device IDs to their respective monotonically increasing counter.
class VersionVector {
  final Map<String, int> _clocks;

  VersionVector([Map<String, int>? clocks])
    : _clocks = clocks != null
          ? Map<String, int>.from(clocks)
          : <String, int>{};

  /// Returns an immutable map of device clocks.
  Map<String, int> get clocks => Map.unmodifiable(_clocks);

  /// Returns clock value for a given device, defaulting to 0.
  int getClock(String deviceId) => _clocks[deviceId] ?? 0;

  /// Returns a new VersionVector with the clock for [deviceId] incremented by 1.
  VersionVector increment(String deviceId) {
    final updated = Map<String, int>.from(_clocks);
    updated[deviceId] = (updated[deviceId] ?? 0) + 1;
    return VersionVector(updated);
  }

  /// Merges this vector with [other] by taking the maximum clock for every device.
  /// Resulting vector causally dominates or equals both operands.
  VersionVector merge(VersionVector other) {
    final merged = Map<String, int>.from(_clocks);
    for (final entry in other._clocks.entries) {
      final current = merged[entry.key] ?? 0;
      if (entry.value > current) {
        merged[entry.key] = entry.value;
      }
    }
    return VersionVector(merged);
  }

  /// Returns true if this vector is causally strictly newer than [other].
  /// (i.e., this >= other everywhere and this > other for at least one device).
  bool strictlyDominates(VersionVector other) {
    bool strictlyGreaterInAtLeastOne = false;
    final allKeys = {..._clocks.keys, ...other._clocks.keys};

    for (final key in allKeys) {
      final thisVal = getClock(key);
      final otherVal = other.getClock(key);

      if (thisVal < otherVal) {
        return false;
      }
      if (thisVal > otherVal) {
        strictlyGreaterInAtLeastOne = true;
      }
    }

    return strictlyGreaterInAtLeastOne;
  }

  /// Returns true if this vector is equal to or newer than [other] across all devices.
  bool isGreaterOrEqualTo(VersionVector other) {
    final allKeys = {..._clocks.keys, ...other._clocks.keys};
    for (final key in allKeys) {
      if (getClock(key) < other.getClock(key)) {
        return false;
      }
    }
    return true;
  }

  /// Returns true if two vectors are identical in all clocks.
  bool isEqualTo(VersionVector other) {
    final allKeys = {..._clocks.keys, ...other._clocks.keys};
    for (final key in allKeys) {
      if (getClock(key) != other.getClock(key)) {
        return false;
      }
    }
    return true;
  }

  /// Returns true if neither vector dominates the other (concurrent edit conflict).
  /// (i.e., this has some clock higher than other, AND other has some clock higher than this).
  bool isConcurrentWith(VersionVector other) {
    bool thisHasHigher = false;
    bool otherHasHigher = false;

    final allKeys = {..._clocks.keys, ...other._clocks.keys};
    for (final key in allKeys) {
      final thisVal = getClock(key);
      final otherVal = other.getClock(key);

      if (thisVal > otherVal) {
        thisHasHigher = true;
      } else if (otherVal > thisVal) {
        otherHasHigher = true;
      }

      if (thisHasHigher && otherHasHigher) {
        return true;
      }
    }

    return false;
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_clocks);

  String toJsonString() => jsonEncode(_clocks);

  factory VersionVector.fromJson(Map<String, dynamic> json) {
    final map = <String, int>{};
    json.forEach((key, value) {
      if (key.isEmpty || value is! int || value < 0) {
        throw const FormatException('Invalid version vector clock.');
      }
      if (value > 0) map[key] = value;
    });
    return VersionVector(map);
  }

  factory VersionVector.fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) {
      return VersionVector();
    }
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid version vector.');
    }
    return VersionVector.fromJson(decoded);
  }

  @override
  String toString() => _clocks.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is VersionVector && isEqualTo(other));

  @override
  int get hashCode {
    final keys = _clocks.keys.where((key) => _clocks[key] != 0).toList()
      ..sort();
    return Object.hashAll(keys.map((key) => Object.hash(key, _clocks[key])));
  }
}
