import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:seoulfit_flutter/main.dart';

void main() {
  testWidgets('SeoulFit app smoke test', (WidgetTester tester) async {
    AuthRepository.initialize(appKey: 'eed5776a9133c010bca56513f4be3f7d');
    await tester.pumpWidget(const SeoulFitApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
