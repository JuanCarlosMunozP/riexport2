# ADR 0004 — Códigos OTP por correo
**Estado:** Aceptada
**Contexto:** Los enlaces de correo exigen deep links en móvil y web.
**Decisión:** El registro (`signup`) y la recuperación (`recovery`) envían un código de 6 dígitos (`{{ .Token }}`) con plantillas en `supabase/templates/`. La app lo canjea con `auth/v1/verify` (`POST /auth/email-confirmations`, `POST /auth/password-resets`) y descarta la sesión temporal.
**Consecuencias:** No hay deep links; el correo debe llegar con el código (SMTP configurado en el entorno alojado).
