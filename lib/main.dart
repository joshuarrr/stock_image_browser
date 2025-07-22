import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/browser_home_screen.dart';

void main() {
  // Set up global error handler to suppress verbose image loading 404s
  FlutterError.onError = (FlutterErrorDetails details) {
    // Check if this is an image loading 404 error
    final exception = details.exception;
    final exceptionString = exception.toString();
    final contextString = details.context.toString();

    // Suppress verbose HTTP 404 errors from image loading
    if ((exceptionString.contains('HttpExceptionWithStatus') ||
            exceptionString.contains('HttpException')) &&
        (exceptionString.contains('Invalid statusCode: 404') ||
            exceptionString.contains('statusCode: 404')) &&
        (contextString.contains('IMAGE RESOURCE SERVICE') ||
            contextString.contains('resolving an image codec') ||
            exceptionString.contains('CachedNetworkImageProvider'))) {
      // Silently ignore - these are handled by errorWidget in the UI
      return;
    }

    // For all other errors, use the default handler
    FlutterError.presentError(details);
  };

  runApp(const StockImageBrowserApp());
}

class StockImageBrowserApp extends StatelessWidget {
  const StockImageBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock Image Browser',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,

        // Color scheme using your provided colors
        colorScheme: const ColorScheme.dark(
          surface: Color(0x5C583473), // Surface default
          primary: Color(0xFFFFFFFF), // Primary button default
          secondary: Color(0xFF313131), // Secondary button default
          error: Color(0xFFE02954), // Alert color
          onSurface: Color(0xFFFFFFFF), // Text default
          onPrimary: Color(0xFF1A131F), // On primary button default
          onSecondary: Color(0xFFFFFFFF), // On secondary button default
          onError: Color(0xFFFFFFFF),
        ),

        // Scaffold background
        scaffoldBackgroundColor: const Color(0xFF1A131F),

        // App bar theme
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1A131F),
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 0,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFFFFF),
          ),
        ),

        // Text theme using Inter font
        textTheme: TextTheme(
          // Header 1 - 40 Bold
          displayLarge: GoogleFonts.inter(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFFFFF),
          ),
          // Header 2 - 28 Bold
          displayMedium: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFFFFF),
          ),
          // Header 3 - 22 Bold
          displaySmall: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFFFFF),
          ),
          // Header 4 - 20 Bold
          headlineLarge: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFFFFF),
          ),
          // Large - 20 Regular
          headlineMedium: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.normal,
            color: const Color(0xFFFFFFFF),
          ),
          // Bold - 16 Bold
          titleLarge: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFFFFF),
          ),
          // Regular - 16 Regular
          titleMedium: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: const Color(0xFFFFFFFF),
          ),
          // Small Bold - 14 Bold
          titleSmall: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFFFFF),
          ),
          // Small - 14 Regular
          bodyLarge: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: const Color(0xFFFFFFFF),
          ),
          // Tiny Bold - 12 Bold
          bodyMedium: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFFFFFFF),
          ),
          // Tiny - 12 Regular
          bodySmall: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: const Color(0x80FFFFFF), // Secondary text
          ),
          // Micro - 10 Regular
          labelSmall: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.normal,
            color: const Color(0x80FFFFFF), // Secondary text
          ),
        ),

        // Tab bar theme
        tabBarTheme: TabBarTheme(
          labelColor: const Color(0xFFFFFFFF),
          unselectedLabelColor: const Color(0x80FFFFFF), // Secondary text
          indicatorColor: const Color(0xFFFFFFFF),
          labelStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.normal,
          ),
        ),

        // Search bar theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0x5C583473), // Surface default
          hintStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: const Color(0x80FFFFFF), // Secondary text
          ),
          prefixIconColor: const Color(0x80FFFFFF), // Icon secondary
          suffixIconColor: const Color(0x80FFFFFF), // Icon secondary
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFFFFFF), width: 1),
          ),
        ),

        // Icon theme
        iconTheme: const IconThemeData(
          color: Color(0xFFFFFFFF), // Icon default
          size: 24,
        ),

        // Button themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFFFFF), // Primary default
            foregroundColor: const Color(
              0xFF1A131F,
            ), // On primary button default
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // Outlined button for secondary style
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xFF313131), // Secondary default
            foregroundColor: const Color(
              0xFFFFFFFF,
            ), // On secondary button default
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            side: const BorderSide(color: Color(0xFF313131)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const BrowserHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
