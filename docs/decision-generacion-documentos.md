# Decisión: dónde se generan los documentos de exportación (PLAT-580)

## Contexto
Las exportaciones necesitan documentos PDF (por ahora, el resumen de exportación; después packing list y declaración EUDR). El expediente ya existe en la base: `stored_file` + `export_document` y el bucket privado `export-documents` (migración `20261019000000`). Los permisos `documents.generate` / `documents.read` ya están definidos.

## Opciones evaluadas
| Opción | Ventajas | Inconvenientes |
|---|---|---|
| Generar en el cliente Flutter | Sin infraestructura nueva | El archivo depende del dispositivo; el cliente podría alterar los datos; el modo local y el hospedado divergen |
| Servicio propio (Django) | Control total | El backend hospedado es Supabase; habría que desplegar y operar otro servicio |
| **Supabase Edge Function (Deno)** | Mismo proyecto y credenciales; se ejecuta con el JWT del usuario, así que RLS decide qué datos ve; escribe directo a Storage | Entorno Deno con límite de memoria/CPU: sirve para PDFs sencillos, no para maquetación pesada |

## Decisión
Los documentos se generan **en el servidor, en una Edge Function de Supabase** (`supabase/functions/generate-document`), con la librería `pdf-lib` (JavaScript puro, sin binarios nativos, compatible con Deno).

- La función recibe `{export_id, document_type}` con el JWT del usuario y usa un cliente Supabase con ese JWT: RLS y `has_permission('documents.generate')` se aplican sin saltarse reglas. No se usa `service_role`.
- Guarda el PDF en `export-documents/exports/<export_id>/<tipo>/<uuid>.pdf`, calcula SHA-256 y registra `stored_file` y `export_document` (función `register_export_document`) con la siguiente versión; la versión vive en la base, no en la ruta. Los documentos no se sobrescriben.
- Si falla el registro tras subir el archivo, la función borra el objeto subido.
- El cliente Flutter solo invocará la función y descargará con URL firmada; no genera PDFs.

## Consecuencias
- Hay que desplegar la función (`supabase functions deploy generate-document`).
- El modo local (sin Supabase) no genera documentos.
- Los tipos de documento nuevos se añaden como plantillas en `supabase/functions/_shared/templates.ts`.
