# ADR 0001 — Supabase como backend
**Estado:** Aceptada
**Contexto:** El proyecto se prototipó con un backend propio (FastAPI y luego Django) y se consolidó en Supabase. El repositorio no contiene servidor de aplicaciones propio.
**Decisión:** La lógica de negocio vive en la base (restricciones, triggers, funciones SQL) y en Edge Functions solo para tareas que no caben en SQL (PDF). La app habla con PostgREST/Auth/Storage.
**Consecuencias:** Sin servidor que operar; las migraciones en `database/migrations/` son la fuente del esquema; la lógica compleja debe escribirse en PL/pgSQL y probarse con `database/tests/`.
