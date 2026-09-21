import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  // TODO: Bundle and register Inter when final brand font assets are supplied.
  static const display = TextStyle(
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w700,
  );
  static const h1 = TextStyle(
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
  );
  static const h2 = TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
  );
  static const h3 = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );
  static const title = TextStyle(
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
  );
  static const bodyLarge = TextStyle(fontSize: 16, height: 24 / 16);
  static const body = TextStyle(fontSize: 14, height: 20 / 14);
  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );
  static const label = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );
  static const caption = TextStyle(fontSize: 12, height: 16 / 12);
  static const tiny = TextStyle(
    fontSize: 10,
    height: 14 / 10,
    fontWeight: FontWeight.w500,
  );
  static final textTheme =
      const TextTheme(
        displayLarge: display,
        headlineLarge: h1,
        headlineMedium: h2,
        headlineSmall: h3,
        titleLarge: title,
        bodyLarge: bodyLarge,
        bodyMedium: body,
        labelLarge: label,
        bodySmall: caption,
        labelSmall: tiny,
      ).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      );
}
