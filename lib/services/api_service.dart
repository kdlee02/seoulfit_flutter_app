import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/travel_state.dart';

class ApiService {
  static final Map<String, String> _summaryCache = {};
  static final Map<String, String> _imageCache = {};
  static final Map<String, String> _detailCache = {};
  /// Base URL for the backend.
  ///
  /// - In local dev, defaults to `http://localhost:8000` so `flutter run`
  ///   works without flags.
  /// - In production, build with
  ///   `--dart-define=API_BASE_URL=https://<backend-host>`.
  /// - An empty string is treated as "same origin".
  static const String _baseRaw = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Empty string → same-origin; otherwise the literal value (no trailing slash).
  static String get _base {
    if (_baseRaw.isEmpty) return '';
    return _baseRaw.endsWith('/')
        ? _baseRaw.substring(0, _baseRaw.length - 1)
        : _baseRaw;
  }

  /// Per-instance thread id. With auth=none we don't want every visitor
  /// landing on the same shared LangGraph thread, so each ApiService instance
  /// gets a fresh random id. Override via `ApiService(threadId: '...')` to
  /// resume a specific conversation.
  final String threadId;

  ApiService({String? threadId}) : threadId = threadId ?? _newThreadId();

  static String _newThreadId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = Random.secure();
    final tail = List.generate(
      8,
      (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[rand.nextInt(36)],
    ).join();
    return 'trip-$ts-$tail';
  }

  /// Sends a user message (or null for the initial greeting) and returns
  /// the updated [TravelState] including the latest AI reply.
  Future<TravelState> chat(String? message) async {
    final body = jsonEncode({
      'thread_id': threadId,
      'message': message,
    });

    final response = await http.post(
      Uri.parse('$_base/chat'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return TravelState.fromJson(json);
    } else {
      throw Exception('Backend error ${response.statusCode}: ${response.body}');
    }
  }

  /// Resets the conversation on the backend.
  Future<void> reset() async {
    await http.post(Uri.parse('$_base/reset?thread_id=$threadId'));
  }

  /// Fetches a 1–2 sentence Gemini summary for a Seoul POI.
  Future<String> fetchPoiSummary(String name, {String type = ''}) async {
    if (_summaryCache.containsKey(name)) return _summaryCache[name]!;
    final body = jsonEncode({'name': name, 'type': type});
    final response = await http.post(
      Uri.parse('$_base/poi-summary'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode == 200) {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final result = (json['summary'] as String?) ?? '';
      _summaryCache[name] = result;
      return result;
    }
    return '';
  }

  /// Fetches the best-matching thumbnail for a Seoul POI via SerpApi + Gemini.
  Future<String> fetchPoiImage(String name, {String type = ''}) async {
    if (_imageCache.containsKey(name)) return _imageCache[name]!;
    final body = jsonEncode({'name': name, 'type': type});
    final response = await http.post(
      Uri.parse('$_base/poi-image'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode == 200) {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final result = (json['image_url'] as String?) ?? '';
      _imageCache[name] = result;
      return result;
    }
    return '';
  }

  /// Fetches structured Tavily visitor info for a Seoul POI (stop selection screen).
  Future<String> fetchPoiDetail(String name, {String type = ''}) async {
    if (_detailCache.containsKey(name)) return _detailCache[name]!;
    final body = jsonEncode({'name': name, 'type': type});
    final response = await http.post(
      Uri.parse('$_base/poi-detail'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode == 200) {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final result = (json['detail'] as String?) ?? '';
      _detailCache[name] = result;
      return result;
    }
    return '';
  }

  /// Recomputes transit (distance / walk / car / Kakao / ODsay) for an
  /// arbitrary ordered list of [stops]. Returns one leg per consecutive pair.
  Future<List<TransitLeg>> fetchTransitLegs(List<Poi> stops) async {
    final body = jsonEncode({
      'stops': [
        for (final s in stops) {'name': s.name, 'lat': s.lat, 'lng': s.lng},
      ],
    });

    final response = await http.post(
      Uri.parse('$_base/transit-legs'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final list = json['transit_legs'] as List? ?? const [];
      return [
        for (final l in list)
          if (l is Map) TransitLeg.fromJson(Map<String, dynamic>.from(l)),
      ];
    } else {
      throw Exception('Backend error ${response.statusCode}: ${response.body}');
    }
  }
}
