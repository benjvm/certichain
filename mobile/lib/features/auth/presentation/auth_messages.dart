import '../domain/auth_repository.dart';

String authMessage(Object error) => switch (error) {
  AuthFailure.invalidCredentials => 'Email o contraseña incorrectos. Comprueba tus datos y la confirmación de tu correo.',
  AuthFailure.weakPassword =>
    'La contraseña no cumple los requisitos. Usa al menos 8 caracteres.',
  AuthFailure.invalidEmail => 'Introduce un email válido.',
  AuthFailure.registrationRejected || AuthFailure.profileProvisioning =>
    'No hemos podido crear la cuenta. Revisa los datos e inténtalo de nuevo.',
  AuthFailure.network =>
    'No se pudo conectar. Comprueba tu conexión e inténtalo de nuevo.',
  AuthFailure.timeout => 'La solicitud tardó demasiado. Inténtalo de nuevo.',
  AuthFailure.rateLimited =>
    'Demasiados intentos. Espera unos minutos antes de continuar.',
  _ => 'No se pudo completar la operación. Inténtalo de nuevo.',
};
