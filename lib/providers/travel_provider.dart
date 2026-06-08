import 'package:flutter/foundation.dart';

import '../models/travel_state.dart';
import '../services/api_service.dart';

/// One chat bubble in the conversational intake flow.
class ChatMessage {
  final String text;
  final bool isUser;
  const ChatMessage(this.text, {required this.isUser});
}

/// Single source of truth for the trip-planning flow, shared across the
/// conversational intake, slot-parsing, generation, critic-repair and final
/// map screens. Backed by [ApiService] which talks to the FastAPI backend.
class TravelProvider extends ChangeNotifier {
  ApiService _api = ApiService();

  final List<ChatMessage> messages = [];
  TravelState? state;
  bool loading = false;
  String? error;

  /// Stops the user picked on the selection screen, in visit order. Consumed
  /// by the route-variation screen. Empty until the user selects.
  List<Poi> selectedStops = [];

  /// Transit legs recomputed by the backend for [selectedStops] (one per
  /// consecutive pair). Null while loading or on failure → screen falls back
  /// to the original itinerary legs / straight-line estimate.
  List<TransitLeg>? recomputedLegs;
  bool legsLoading = false;

  bool get hasItinerary => state?.itinerary != null;
  bool get confirmed => state?.confirmed ?? false;
  Itinerary? get itinerary => state?.itinerary;

  /// All itinerary POIs flattened across days, in itinerary order.
  List<Poi> get allPois => [
        for (final d in (itinerary?.days ?? const [])) ...d.pois,
      ];

  void setSelectedStops(List<Poi> stops) {
    selectedStops = stops;
    recomputedLegs = null; // invalidate any previous result
    notifyListeners();
  }

  /// Ask the backend for fresh ODsay transit legs for the current selection.
  Future<void> recomputeTransit() async {
    if (selectedStops.length < 2) {
      recomputedLegs = const [];
      notifyListeners();
      return;
    }
    legsLoading = true;
    notifyListeners();
    try {
      recomputedLegs = await _api.fetchTransitLegs(selectedStops);
    } catch (_) {
      recomputedLegs = null; // leave null → screen uses fallback
    } finally {
      legsLoading = false;
      notifyListeners();
    }
  }

  /// The real transit leg the backend computed between two POIs that were
  /// adjacent in the original itinerary, or null if they weren't adjacent.
  TransitLeg? legBetween(Poi a, Poi b) {
    for (final day in itinerary?.days ?? const <ItineraryDay>[]) {
      for (var i = 0; i < day.pois.length - 1; i++) {
        if (_samePoi(day.pois[i], a) &&
            _samePoi(day.pois[i + 1], b) &&
            i < day.transitLegs.length) {
          return day.transitLegs[i];
        }
      }
    }
    return null;
  }

  static bool _samePoi(Poi a, Poi b) =>
      a.name == b.name && a.lat == b.lat && a.lng == b.lng;

  /// Fires the backend greeting once, on first entry to the chat screen.
  Future<void> startGreeting() async {
    if (messages.isNotEmpty || loading) return;
    await _send(null);
  }

  /// Sends a user message, appends it optimistically, then the AI reply.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    messages.add(ChatMessage(trimmed, isUser: true));
    notifyListeners();
    await _send(trimmed);
  }

  Future<void> _send(String? text) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final s = await _api.chat(text);
      state = s;
      final reply = s.reply;
      if (reply != null && reply.isNotEmpty) {
        messages.add(ChatMessage(reply, isUser: false));
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Clears everything and starts a brand-new backend thread.
  Future<void> reset() async {
    try {
      await _api.reset();
    } catch (_) {
      // Ignore — we're discarding this thread anyway.
    }
    _api = ApiService();
    messages.clear();
    state = null;
    error = null;
    loading = false;
    notifyListeners();
  }
}
