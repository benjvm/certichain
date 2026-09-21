# Phase 3 — Registration UI

The reference is view 2.2 in `ChatGPT Image Sep 20, 2026, 09_00_47 PM.png`
in this directory, alongside `CERTICHAIN_UI_IMPLEMENTATION.md` at repository root.
Registration is a single screen: brand, «Crear cuenta», «Únete a CertiChain»,
account preference, full name, email and «Continuar». Neither reference defines
registration password fields or another step, so none were invented.

`/register` is pushed from Login's «Crear cuenta». System back pops to the
existing Login and preserves its form state, without adding another Login route.
The reference has no separate sign-in link on Registration.

Estudiante is initially selected, as in the reference. Institución is a temporary
UI preference with an approval explanation, not a grant of `institution_admin`
or membership. No preference is persisted or mapped to backend authorization.
The green Verificador row is omitted: `docs/REQUIREMENTS.md` defines public
verification and the schema has no verifier account role. Administrative roles
are not offered. Trusted account/profile provisioning, institutional onboarding,
membership and approval must be designed when backend integration is undertaken.

The existing theme, input decorations, spacing, colors, radii, logo and AppButton
are reused. AuthBrand extracts Login's existing compact brand row for both auth
screens. RegistrationRoleSelector encapsulates selectable rows and their checked
semantics. Email validation is shared with Login through AuthFormValidators.

Name must contain non-whitespace text; email is required and must match Login's
basic format check. A role is always selected. Valid submission dismisses the
keyboard and stops at a TODO; it neither creates an account nor reports success.
Autofill, Next/Done, outside-tap dismissal and scroll are supported. No backend,
database, dependencies or other screens were added.

Verification includes formatting, `flutter analyze` and the full widget suite:
Welcome → Login → Register → back, form validation, role selection/semantics,
keyboard flow, existing Login password visibility, and 360×800, 390×844 and
320×568 layouts with 1.5× text and 300px keyboard insets. Physical-device keyboard
verification remains pending. Inter assets remain deferred from Phase 1.
