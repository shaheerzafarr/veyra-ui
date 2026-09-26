import 'package:flutter/material.dart';

abstract final class VeyraColors {
  static const background = Color(0xFF0B0F10);
  static const backgroundDeep = Color(0xFF030908);
  static const surface = Color(0xFF151B1C);
  static const elevated = Color(0xFF202829);
  static const emerald = Color(0xFF34D399);
  static const emeraldBright = Color(0xFF42F5C2);
  static const emeraldDeep = Color(0xFF08755D);
  static const text = Color(0xFFF3F6F5);
  static const muted = Color(0xFF94A3A0);
  static const outline = Color(0xFF7D8987);
  static const danger = Color(0xFFF87171);
  static const border = Color(0xFF2B3535);
  static const sent = Color(0xFF08745B);
}

abstract final class VeyraRadii {
  static const control = 18.0;
  static const pill = 999.0;
}

ThemeData veyraTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: VeyraColors.emerald,
    brightness: Brightness.dark,
    surface: VeyraColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: VeyraColors.emerald,
      surface: VeyraColors.surface,
      onSurface: VeyraColors.text,
      error: VeyraColors.danger,
    ),
    scaffoldBackgroundColor: VeyraColors.background,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: VeyraPageTransitionsBuilder(),
        TargetPlatform.iOS: VeyraPageTransitionsBuilder(),
        TargetPlatform.macOS: VeyraPageTransitionsBuilder(),
        TargetPlatform.windows: VeyraPageTransitionsBuilder(),
        TargetPlatform.linux: VeyraPageTransitionsBuilder(),
        TargetPlatform.fuchsia: VeyraPageTransitionsBuilder(),
      },
    ),
    textTheme: ThemeData.dark()
        .textTheme
        .apply(
          bodyColor: VeyraColors.text,
          displayColor: VeyraColors.text,
          fontFamily: 'Roboto',
        )
        .copyWith(
          displayLarge: const TextStyle(
            color: VeyraColors.text,
            fontSize: 54,
            height: .98,
            fontWeight: FontWeight.w800,
            letterSpacing: -2.4,
          ),
          bodyLarge: const TextStyle(
            color: VeyraColors.muted,
            fontSize: 18,
            height: 1.42,
            fontWeight: FontWeight.w400,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VeyraColors.background,
      foregroundColor: VeyraColors.text,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: VeyraColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VeyraColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 76,
      indicatorColor: VeyraColors.emerald.withValues(alpha: .16),
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? VeyraColors.emerald
                : VeyraColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? VeyraColors.emerald
                : VeyraColors.muted,
            size: 21,
          )),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: VeyraColors.elevated,
      selectedColor: VeyraColors.emerald,
      side: const BorderSide(color: VeyraColors.border, width: 1.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      labelStyle: const TextStyle(color: VeyraColors.text, fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VeyraColors.emerald,
        foregroundColor: VeyraColors.background,
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VeyraRadii.control),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VeyraColors.text,
        minimumSize: const Size.fromHeight(58),
        side: const BorderSide(color: VeyraColors.outline, width: 1.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VeyraRadii.control),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VeyraColors.elevated,
      hintStyle: const TextStyle(color: VeyraColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2C3637)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2C3637)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: VeyraColors.emerald, width: 1.4),
      ),
    ),
  );
}

class VeyraPageTransitionsBuilder extends PageTransitionsBuilder {
  const VeyraPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curvedAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.025, 0),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: child,
      ),
    );
  }
}
