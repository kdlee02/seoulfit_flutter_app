// The itinerary 'confirm' turn runs RAG retrieval, the planner and
// critic-repair end to end. Measured against a warm local backend it takes
// 60-71s, while ordinary conversational turns take 3-7s.
//
// A single 30s timeout covering both silently failed generation: the request
// was cut off, TravelState came back without an itinerary, and
// ItineraryGenerationScreen showed "Need a bit more info" with a Back to Chat
// button. Verified directly against the backend — a 30s client budget raises
// TimeoutError, a 180s budget returns a 3-day itinerary in 60.9s.
import 'package:flutter_test/flutter_test.dart';
import 'package:seoulfit_flutter/services/api_service.dart';

void main() {
  test('generation timeout leaves real headroom over the measured 71s', () {
    expect(ApiService.generationTimeout.inSeconds, greaterThanOrEqualTo(120),
        reason: 'the confirm turn was measured at 60-71s; anything close to '
            'that fails itinerary generation intermittently');
  });

  test('generation timeout is far longer than the conversational one', () {
    expect(ApiService.generationTimeout,
        greaterThan(ApiService.chatTimeout * 3),
        reason: 'the two turns differ by an order of magnitude in cost; '
            'collapsing them back into one budget reintroduces the bug');
  });

  test('conversational timeout still bounds a dead network', () {
    expect(ApiService.chatTimeout.inSeconds, greaterThan(10),
        reason: 'must not cut off a normal 3-7s turn');
    expect(ApiService.chatTimeout.inSeconds, lessThanOrEqualTo(60),
        reason: 'an unreachable host must surface quickly, not hang');
  });
}
