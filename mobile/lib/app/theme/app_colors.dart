import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brandPrimary = Color(0xFF4F5FFF);
  static const brandPrimaryDark = Color(0xFF3947E8);
  static const brandPrimaryLight = Color(0xFFEEF0FF);
  static const brandSecondary = Color(0xFF7657FF);
  static const success = Color(0xFF16B364);
  static const successLight = Color(0xFFECFDF3);
  static const error = Color(0xFFF04438);
  static const errorLight = Color(0xFFFEF3F2);
  static const warning = Color(0xFFF79009);
  static const info = Color(0xFF2E90FA);
  static const background = Color(0xFFF8F9FC);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4E7EC);
  static const textPrimary = Color(0xFF101828);
  static const inkBlue = Color(0xFF0E1950);
  // Accessible text on the pale status surfaces; retain Figma hues for icons.
  static const successText = Color(0xFF067647);
  static const errorText = Color(0xFFB42318);
  static const textSecondary = Color(0xFF667085);
  static const textTertiary = Color(0xFF98A2B3);
  static const disabled = Color(0xFFD0D5DD);
  static const studentAccent = brandPrimary;
  static const institutionAccent = brandSecondary;
  static const institutionLight = Color(0xFFF3F0FF);
  static const verifierAccent = success;
}
