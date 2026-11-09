# ADR 0002 — Autorización por RLS y RPC
**Estado:** Aceptada
**Contexto:** Roles y permisos son editables (`role`, `permission`, `role_permission`); el cliente externo debe ver solo sus datos.
**Decisión:** Toda tabla tiene RLS; las políticas llaman `has_permission(código)`. Las escrituras sensibles pasan por funciones SECURITY DEFINER con `search_path` fijo que validan permiso y reglas; el cliente no tiene INSERT/UPDATE directo. Las vistas usan `security_barrier` y permisos explícitos. El portal de clientes se aísla con `customer_user` y las funciones `my_*_ids`.
**Consecuencias:** El permiso se evalúa en la base, no en la app; la UI solo oculta acciones. Detalle en `docs/modelo-autorizacion-rls.md`.
