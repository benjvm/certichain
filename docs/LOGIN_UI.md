# Phase 2 — Login UI

Implemented `/login` using the existing named-route router. The welcome screen's
«Comenzar» opens Login; system back returns to welcome. No other screens were added.

The screen reuses the Phase 1 logo, button, typography, spacing and colors. Input
decoration is centralized in the existing theme with the existing radius tokens.
The form supports email/password autofill, Next/Done keyboard actions, dismissal
on outside taps or scrolling, and a labelled password visibility toggle.

Submission validates a required, reasonably formatted email and a nonempty
password. Phase 4B now authenticates through the injected AuthRepository, with loading,
duplicate-submit protection and safe Spanish errors. Successful session events
replace the auth navigation stack with the temporary authenticated boundary.
Email/password remain on failure. Registration opens the two-step flow; recovery
remains disabled. Social login and its separator are omitted
because no provider is configured. Phase 2 originally changed no backend or dependencies.

Visual reference: `CERTICHAIN_UI_IMPLEMENTATION.md`. The referenced
`docs/references/certichain-wireframe.png` is absent, so exact visual comparison
and image-specific copy could not be verified. The description uses the specified
«Tus logros, verificados en blockchain» subtitle. Inter assets remain pending
from Phase 1; the existing typography is preserved.

Verification: `flutter analyze` and `flutter test`. Widget tests cover validation,
visibility, keyboard actions/dismissal, welcome navigation and system back, and
scrolling with 300px keyboard insets at 360×800, 390×844 and 320×568 with 1.5× text.
Physical-device keyboard and manual visual verification remain pending.

Phase 4B bootstrap, configuration, restoration and logout are documented in
[AUTHENTICATION.md](AUTHENTICATION.md). The official Supabase Flutter dependency
was added in that phase; the screen itself only depends on the domain contract.
