# Registro de decisiones de arquitectura (ADR) — PLAT-415

Formato: contexto, decisión, consecuencias. Estado `Aceptada` significa que está implementada en el repositorio; no implica aprobación del cliente.

| ADR | Decisión |
|---|---|
| [0001](0001-supabase-como-backend.md) | Supabase (PostgreSQL + Auth + Storage + Edge Functions) como backend |
| [0002](0002-autorizacion-por-rls-y-rpc.md) | Autorización por RLS, permisos y RPC SECURITY DEFINER |
| [0003](0003-acceso-a-datos-desde-flutter.md) | Un único `ApiClient` con adaptadores Supabase y local |
| [0004](0004-codigos-otp-por-correo.md) | Confirmación de correo y recuperación con código OTP |
| [0005](0005-exportaciones-parciales-y-eudr.md) | Exportaciones parciales y regla de validez EUDR |
| [0006](0006-documentos-pdf-en-edge-function.md) | PDF generados en Edge Function (ver `docs/decision-generacion-documentos.md`) |
