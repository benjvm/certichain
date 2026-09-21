abstract final class AuthFormValidators {
  static String? newPassword(String? value) {
    if (value == null || value.isEmpty) return 'Introduce tu contraseña';
    if (value.length < 8) return 'Usa al menos 8 caracteres';
    return null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Introduce tu email';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Introduce un email válido';
    }
    return null;
  }
}
