# ADR 0003 — Acceso a datos desde Flutter
**Estado:** Aceptada
**Decisión:** Las pantallas reciben callbacks (`loadX`, `onSave`) y las rutas del router los conectan a `ApiClient` (REST con rutas de dominio como `/orders`, `/exports/:id/eudr`). `SupabaseBackendClient` traduce esas rutas a PostgREST/RPC; `LocalBackendClient` las implementa en memoria para desarrollo y pruebas. Estado global con `provider`.
**Consecuencias:** Las pantallas no conocen Supabase y se prueban con funciones falsas; cada ruta nueva debe implementarse en ambos adaptadores (o devolver un error explícito en el local).
