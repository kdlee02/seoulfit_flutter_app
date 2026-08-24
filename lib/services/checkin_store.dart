import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_checkin.dart';

/// Local-first store for trip check-ins, following the same
/// `shared_preferences` + JSON pattern as [TripStorageService].
///
/// The recap renders entirely from here; the backend copy written by
/// [ApiService.postCheckin] is best-effort and never read back.
class CheckinStore {
  static const _deviceKey = 'device_id';
  static const _tripPrefix = 'checkin_';
  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// Stable per-install identifier, generated on first call. No account and no
  /// OAuth: this only needs to group one device's records, not authenticate a
  /// person. Mirrors `ApiService._newThreadId`'s alphabet so ids look alike in
  /// logs. Lost on reinstall — acceptable for a single trip's record.
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rand = Random.secure();
    final id =
        'dev-${List.generate(16, (_) => _alphabet[rand.nextInt(36)]).join()}';
    await prefs.setString(_deviceKey, id);
    return id;
  }

  static Future<void> save(TripCheckin trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_tripPrefix${trip.tripId}',
      jsonEncode(trip.toJson()),
    );
  }

  static Future<TripCheckin?> load(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_tripPrefix$tripId');
    if (raw == null) return null;
    return TripCheckin.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
