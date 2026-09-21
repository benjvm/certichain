import 'package:flutter/material.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../domain/auth_repository.dart';
import 'auth_form_validators.dart';
import 'auth_messages.dart';
import 'widgets/auth_brand.dart';

class RegistrationCredentials extends StatefulWidget {
  const RegistrationCredentials({
    required this.repository,
    required this.fullName,
    required this.email,
    required this.institutionPreference,
    super.key,
  });
  final AuthRepository repository;
  final String fullName;
  final String email;
  final bool institutionPreference;

  @override
  State<RegistrationCredentials> createState() =>
      _RegistrationCredentialsState();
}

class _RegistrationCredentialsState extends State<RegistrationCredentials> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _confirmationFocus = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _loading = false;
  bool _submitted = false;
  bool _pending = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _submitted = true);
    if (!_form.currentState!.validate()) return;
    if (widget.fullName.trim().isEmpty ||
        AuthFormValidators.email(widget.email) != null) {
      setState(() => _error = 'Vuelve al paso anterior y revisa tus datos.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final outcome = await widget.repository.signUp(
        fullName: widget.fullName.trim(),
        email: widget.email.trim(),
        password: _password.text,
      );
      if (mounted && outcome == SignupOutcome.confirmationRequired) {
        _password.clear();
        _confirmation.clear();
        setState(() => _pending = true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = authMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _returnToLogin() => Navigator.of(context).popUntil(
    (route) => route.settings.name == AppRouter.loginRoute || route.isFirst,
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_loading && !_pending,
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: !_pending
            ? IconButton(
                tooltip: 'Volver al paso anterior',
                onPressed: _loading ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _loading,
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
              child: _pending
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AuthBrand(),
                        const SizedBox(height: AppSpacing.section),
                        const Text('Revisa tu correo'),
                        const Text(
                          'Solicitud recibida. Si es necesario confirmar la cuenta, recibirás las instrucciones por correo antes de iniciar sesión.',
                        ),
                        // Do not repeat the complete address on a success screen.
                        Text(
                          'Correo: ${widget.email.substring(0, 1)}•••@${widget.email.split('@').last}',
                        ),
                        const SizedBox(height: AppSpacing.section),
                        AppButton(
                          label: 'Volver a Iniciar sesión',
                          onPressed: _returnToLogin,
                        ),
                      ],
                    )
                  : AutofillGroup(
                      onDisposeAction: AutofillContextAction.cancel,
                      child: Form(
                        key: _form,
                        autovalidateMode: _submitted
                            ? AutovalidateMode.onUserInteraction
                            : AutovalidateMode.disabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AuthBrand(),
                            const SizedBox(height: AppSpacing.section),
                            Text(
                              'Protege tu cuenta',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const Text('Paso 2 de 2 · Contraseña'),
                            if (widget.institutionPreference)
                              const Text(
                                'El onboarding y la aprobación institucional se completarán en una fase futura. Esta cuenta no concede permisos institucionales.',
                              ),
                            const SizedBox(height: AppSpacing.section),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Mostrar contraseña'
                                      : 'Ocultar contraseña',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [AutofillHints.newPassword],
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _confirmationFocus.requestFocus(),
                              validator: AuthFormValidators.newPassword,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _confirmation,
                              focusNode: _confirmationFocus,
                              obscureText: _obscureConfirmation,
                              decoration: InputDecoration(
                                labelText: 'Confirmar contraseña',
                                suffixIcon: IconButton(
                                  tooltip: _obscureConfirmation
                                      ? 'Mostrar confirmación'
                                      : 'Ocultar confirmación',
                                  onPressed: () => setState(
                                    () => _obscureConfirmation =
                                        !_obscureConfirmation,
                                  ),
                                  icon: Icon(
                                    _obscureConfirmation
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [AutofillHints.newPassword],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Confirma tu contraseña'
                                  : value != _password.text
                                  ? 'Las contraseñas no coinciden'
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.section),
                            if (_error case final error?)
                              Semantics(liveRegion: true, child: Text(error)),
                            AppButton(
                              label: 'Crear cuenta',
                              isLoading: _loading,
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
