import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const family = 'Inter';
  static const greeting = TextStyle(
    fontSize: 21,
    height: 28 / 21,
    fontWeight: FontWeight.w700,
    color: AppColors.inkBlue,
  );
  static const sectionTitle = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    color: AppColors.inkBlue,
  );
  static const topBarTitle = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
    color: AppColors.inkBlue,
  );
  static const cardTitle = TextStyle(
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w600,
  );
  static const navigation = TextStyle(
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w500,
  );
  static const button = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );
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
        titleMedium: cardTitle,
        titleSmall: sectionTitle,
        bodyLarge: bodyLarge,
        bodyMedium: body,
        labelLarge: label,
        bodySmall: caption,
        labelSmall: tiny,
      ).apply(
        fontFamily: family,
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      );
}
