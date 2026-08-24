import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:provider/provider.dart';

import 'providers/travel_provider.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/conversational_intake_screen.dart';
import 'screens/live_help_screen.dart';
import 'screens/slot_parsing_screen.dart';
import 'screens/itinerary_generation_screen.dart';
import 'screens/final_itinerary_map_screen.dart';
import 'screens/user_selection_screen.dart';
import 'screens/route_variation_screen.dart';
import 'screens/trip_checkin_screen.dart';
import 'screens/trip_recap_screen.dart';
import 'screens/transit_explore_screen.dart';
import 'screens/seoul_lens_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AuthRepository.initialize(
    appKey: 'eed5776a9133c010bca56513f4be3f7d',
    baseUrl: 'http://localhost',
  );
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const SeoulFitApp());
}

class SeoulFitApp extends StatelessWidget {
  const SeoulFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TravelProvider(),
      child: MaterialApp(
        title: 'SeoulFit',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        initialRoute: '/',
        routes: {
          '/': (ctx) => const SplashScreen(),
          '/onboarding': (ctx) => const OnboardingScreen(),
          '/chat': (ctx) => const ConversationalIntakeScreen(),
          '/live-help': (ctx) => const LiveHelpScreen(),
          '/slot-parsing': (ctx) => const SlotParsingScreen(),
          '/generating': (ctx) => const ItineraryGenerationScreen(),
          '/itinerary-map': (ctx) => const FinalItineraryMapScreen(),
          '/user-selection': (ctx) => const UserSelectionScreen(),
          '/route-variation': (ctx) => const RouteVariationScreen(),
          '/trip-checkin': (ctx) => const TripCheckinScreen(),
          '/trip-recap': (ctx) => const TripRecapScreen(),
          '/transit-explore': (ctx) => const TransitExploreScreen(),
          '/seoul-lens': (ctx) => const SeoulLensScreen(),
          '/profile': (ctx) => const ProfileScreen(),
        },
      ),
    );
  }
}