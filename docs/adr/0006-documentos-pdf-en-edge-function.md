# ADR 0006 — PDF en Edge Function
**Estado:** Aceptada (función no ejecutada en CI: requiere Deno y Supabase CLI)
Ver `docs/decision-generacion-documentos.md`. La app invoca `POST /exports/:id/documents`, que llama a `generate-document` y devuelve una URL firmada de 1 hora.
