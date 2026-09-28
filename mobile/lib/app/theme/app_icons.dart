import 'package:flutter/material.dart';

/// Figma uses text glyphs as icons; Material outlined is the bundled alternative.
abstract final class AppIcons {
  static const home = Icons.home_outlined;
  static const certificate = Icons.workspace_premium_outlined;
  static const profile = Icons.person_outline_rounded;
  static const back = Icons.chevron_left_rounded;
  static const forward = Icons.chevron_right_rounded;
  static const refresh = Icons.refresh_rounded;
  static const add = Icons.add_circle_outline_rounded;
  static const scan = Icons.qr_code_scanner_rounded;
  static const valid = Icons.check_circle_outline_rounded;
  static const revoked = Icons.block_rounded;
  static const time = Icons.schedule_rounded;
  static const calendar = Icons.calendar_today_outlined;
  static const document = Icons.description_outlined;
  static const security = Icons.shield_outlined;
  static const notification = Icons.notifications_none_rounded;
  static const settings = Icons.settings_outlined;
  static const info = Icons.info_outline_rounded;
}
