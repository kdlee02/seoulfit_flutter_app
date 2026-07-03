import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/api_base.dart';
import '../models/travel_state.dart';

class ApiService {
  static final Map<String, String> _poiCache = {};

  static String get _base => apiBase;

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

  /// POSTs `{name, type}` to a `/poi-*` endpoint and returns `json[field]`,
  /// caching by endpoint+name. Empty string on any non-200. Shared by the four
  /// single-field POI lookups below.
  Future<String> _fetchPoiField(
      String endpoint, String field, String name, String type) async {
    final cacheKey = '$endpoint|$name';
    final cached = _poiCache[cacheKey];
    if (cached != null) return cached;
    final response = await http.post(
      Uri.parse('$_base/$endpoint'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'type': type}),
    );
    if (response.statusCode != 200) return '';
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final result = (json[field] as String?) ?? '';
    _poiCache[cacheKey] = result;
    return result;
  }

  /// 1–2 sentence Gemini summary for a Seoul POI.
  Future<String> fetchPoiSummary(String name, {String type = ''}) =>
      _fetchPoiField('poi-summary', 'summary', name, type);

  /// Best-matching thumbnail for a Seoul POI via SerpApi + Gemini.
  Future<String> fetchPoiImage(String name, {String type = ''}) =>
      _fetchPoiField('poi-image', 'image_url', name, type);

  /// Structured Tavily visitor info for a Seoul POI (stop selection screen).
  Future<String> fetchPoiDetail(String name, {String type = ''}) =>
      _fetchPoiField('poi-detail', 'detail', name, type);

  /// Short "you've arrived" confirmation tip — a visible landmark to recognise
  /// plus what's at the entrance.
  Future<String> fetchPoiArrivalTip(String name, {String type = ''}) =>
      _fetchPoiField('poi-arrival-tip', 'arrival_tip', name, type);

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
