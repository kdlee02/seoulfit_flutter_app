import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';

enum ErrorType { network, aiFailure }

class ErrorScreen extends StatelessWidget {
  final ErrorType type;
  final VoidCallback? onRetry;

  const ErrorScreen({
    super.key,
    this.type = ErrorType.network,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isNetwork = type == ErrorType.network;

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isNetwork)
                        Container(
                          width: 96,
                          height: 96,
                          decoration: const BoxDecoration(
                            color: kCardBorder,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            size: 48,
                            color: kSubtext,
                          ),
                        )
                      else
                        Image.asset(
                          'assets/images/seoulfit_mascot.png',
                          width: 120,
                          height: 120,
                          fit: BoxFit.contain,
                        ),
                      const SizedBox(height: 24),
                      Text(
                        isNetwork
                            ? 'No internet connection'
                            : 'Something went wrong.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isNetwork
                            ? 'Please check your network\nand try again.'
                            : 'Please try again.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: kSubtext,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: onRetry ?? () => Navigator.pop(context),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          'Retry',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kMint,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 36, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
