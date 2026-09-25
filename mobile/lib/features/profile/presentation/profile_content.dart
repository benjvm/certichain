import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
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
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting ? 'Hola, ${profile.fullName}' : profile.fullName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(switch (profile.role) {
                  'holder' => 'Estudiante',
                  'institution_admin' => 'Administrador institucional',
                  'platform_admin' => 'Administrador de plataforma',
                  _ => 'Cuenta autenticada',
                }),
                if (!greeting)
                  const Text(
                    'Consulta de perfil · Edición no disponible todavía.',
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
