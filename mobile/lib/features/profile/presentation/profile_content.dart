import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_button.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_sizes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/read_state.dart';
import '../domain/profile_repository.dart';

class ProfileContent extends StatelessWidget {
  const ProfileContent({
    required this.future,
    required this.onRetry,
    this.greeting = false,
    super.key,
  });
  final Future<UserProfile?> future;
  final VoidCallback onRetry;
  final bool greeting;
  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfile?>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const ReadLoading(label: 'Cargando perfil');
      }
      if (snapshot.hasError) {
        return ReadError(
          message: 'No pudimos cargar tu perfil.',
          onRetry: onRetry,
        );
      }
      final profile = snapshot.data;
      if (profile == null) {
        return ReadError(
          message: 'Tu perfil no está disponible. Reintenta o cierra sesión. Si el problema continúa, contacta con soporte.',
          onRetry: onRetry,
        );
      }
      final identity = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!greeting) ...[_avatar(), const SizedBox(width: AppSpacing.lg)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting ? 'Hola, ${profile.fullName}' : profile.fullName,
                  style: greeting
                      ? AppTypography.greeting
                      : Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  switch (profile.role) {
                    'holder' => 'Estudiante',
                    'institution_admin' => 'Administrador institucional',
                    'platform_admin' => 'Administrador de plataforma',
                    _ => 'Cuenta autenticada',
                  },
                  style: AppTypography.label.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (greeting) ...[const SizedBox(width: AppSpacing.md), _avatar()],
        ],
      );
      if (greeting) return identity;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: identity,
          ),
          const SizedBox(height: AppSpacing.section),
          if (profile.role == 'holder') ...[
            const Text(
              'Comparte voluntariamente tu ID con la institución que vaya a emitir tu certificado. No es tu correo electrónico ni concede acceso a tu cuenta.',
            ),
            AppButton(
              label: 'Copiar mi ID de titular',
              style: AppButtonStyle.outline,
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: profile.id));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ID de titular copiado')),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No pudimos copiar el ID.')),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: AppSpacing.section),
          ],
          for (final option in const [
            (AppIcons.profile, 'Información personal', 'Edición no disponible'),
            (AppIcons.security, 'Seguridad', 'No disponible'),
            (AppIcons.notification, 'Notificaciones', 'No disponible'),
            (AppIcons.settings, 'Configuración', 'No disponible'),
          ]) ...[
            Semantics(
              enabled: false,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Icon(
                        option.$1,
                        color: AppColors.brandPrimary,
                        size: AppSizes.icon,
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(option.$2),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              option.$3,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      );
    },
  );
  Widget _avatar() => Semantics(
    label: 'Avatar genérico',
    image: true,
    child: Container(
      width: greeting ? AppSizes.avatar : AppSizes.profileAvatar,
      height: greeting ? AppSizes.avatar : AppSizes.profileAvatar,
      decoration: const BoxDecoration(
        color: AppColors.brandPrimaryLight,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        AppIcons.profile,
        color: AppColors.brandPrimary,
        size: AppSizes.iconLarge,
      ),
    ),
  );
}
