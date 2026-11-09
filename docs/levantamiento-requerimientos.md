# Levantamiento de requerimientos: entrevista y taller

**Proyecto:** Plataforma de exportación de café y cacao  
**Versión:** 0.1 - guía y formato de registro  
**Estado:** Guía lista para usar; **los resultados se registran después de la sesión**. Este documento no contiene respuestas de ningún entrevistado.  
**Relacionado con:** `requerimientos.md` v0.3 (secciones 6 y 9.3, decisiones abiertas).

## 1. Objetivo

Resolver con el docente/cliente las decisiones que `requerimientos.md` deja abiertas y confirmar los cambios de la versión 0.3 (backend en Flutter + Supabase, autorregistro con rol `cliente`, cambio de correo por el titular). La sesión debe producir decisiones registradas, no solo opiniones.

## 2. Participantes

| Rol en la sesión | Quién | Qué aporta |
|---|---|---|
| Decisor de negocio | Docente / cliente | Aprueba o rechaza cada decisión. |
| Equipo de desarrollo | Integrantes del proyecto | Explica el alcance y las consecuencias técnicas. |
| Relator | Un integrante | Llena el registro (sección 6) durante la sesión. |
| Usuarios representativos | Perfiles comercial, operativo y administrador (si es posible) | Describen su flujo real de trabajo. |

### 2.1 Preparación

- Enviar con antelación `requerimientos.md` (resumen de RF y RNF) y la lista de decisiones de la sección 5.
- Llevar prototipos o capturas de las pantallas existentes: inicio de sesión, registro, perfil, usuarios y roles.
- Reservar 90 minutos. Si no alcanza, priorizar los bloques A, B y C.

## 3. Agenda del taller (90 min)

| Min | Bloque | Resultado esperado |
|---|---|---|
| 0-10 | Contexto y objetivo; qué cambió en la versión 0.3 | Todos entienden el alcance. |
| 10-30 | **A.** Usuarios, acceso y permisos | Matriz de roles y permisos; decisión de autorregistro. |
| 30-50 | **B.** Pedidos, exportaciones, inventario y pagos | Estados, transiciones, reglas de stock y vencimiento. |
| 50-65 | **C.** Cumplimiento y documentos (HS, EUDR, EUR.1) | Alcance legal y fuentes oficiales. |
| 65-80 | **D.** Requisitos no funcionales | Parámetros de rendimiento, disponibilidad y respaldos. |
| 80-90 | Cierre: revisar el registro, asignar responsables y fechas | Decisiones confirmadas y pendientes con dueño. |

## 4. Guía de entrevista por bloque

Preguntas abiertas primero; después, la pregunta de decisión cerrada. Anotar el motivo de cada respuesta.

### A. Usuarios, acceso y permisos (RF-01 a RF-06, RNF-02 a RNF-04)

1. ¿Quiénes usarán el sistema y qué hace cada uno en un día normal?
2. ¿Cualquier persona puede crear su cuenta o solo personas invitadas? **Decisión:** ¿se aprueba el autorregistro con rol `cliente`?
3. ¿Qué debe poder hacer un `cliente` por defecto? (hoy: nada salvo su perfil).
4. ¿Qué roles existen además de administrador, usuario comercial y encargado logístico? ¿Quién puede asignarlos?
5. ¿Se exige confirmar el correo antes de entrar? ¿Qué se espera cuando un usuario no recibe el correo?
6. ¿Cuánto debe durar una sesión abierta y qué pasa al vencer?
7. ¿Un administrador debe poder corregir el correo de otra persona? (hoy no, por seguridad; implica un servicio de servidor adicional).

### B. Pedidos, exportaciones, inventario y pagos (RF-15 a RF-28)

1. ¿Qué datos son obligatorios al registrar un cliente (por ejemplo, el EORI)? ¿Un pedido puede tener varios productos?
2. ¿Cuáles son los estados de un pedido, quién puede cambiar cada uno y desde cuál a cuál?
3. ¿El inventario se reserva al confirmar el pedido y se descuenta al exportar, o solo en uno de los dos momentos? ¿Se permite stock negativo?
4. ¿En qué unidad se mide cada producto y cuál es el umbral de stock bajo por producto?
5. ¿Los pagos solo se registran o se integrará una pasarela? ¿Cuál es la fecha límite y qué significa "próximo a vencer" (días de antelación)?
6. ¿Con qué moneda base se reporta y qué proveedor de tasas de cambio se usará?

### C. Cumplimiento y documentos (RF-18 a RF-23, RNF-16)

1. ¿El sistema genera documentos oficiales o borradores para revisión humana?
2. ¿Qué fuente y versión del arancel (código HS) son las válidas? ¿Puede el usuario sobrescribir el código propuesto?
3. ¿Qué datos exige la declaración de diligencia debida EUDR y quién la valida?
4. ¿Qué documentos son obligatorios por tipo de exportación y cuáles pueden adjuntarse?

### D. Requisitos no funcionales (RNF-05 a RNF-19)

1. ¿Cuántos usuarios simultáneos y qué volumen de datos se esperan? (necesario para medir el límite de 5 s en reportes).
2. ¿Qué disponibilidad se exige y quién responde ante una caída?
3. ¿Con qué frecuencia debe respaldarse la base, cuánto tiempo se conservan los respaldos y cuánto dato se tolera perder (RPO) o tardar en recuperar (RTO)?
4. ¿Qué navegadores, versiones de Android e iOS y dispositivos se soportarán?
5. ¿Qué nivel de accesibilidad se espera (propuesta: WCAG 2.2 AA)?
6. ¿Qué datos personales se guardan, con qué base legal y por cuánto tiempo? ¿Quién atiende las solicitudes de los titulares?
7. Dado que el backend depende de Supabase: ¿se acepta esa dependencia y su plan de servicio como entorno productivo?

## 5. Decisiones a cerrar (de `requerimientos.md`, secciones 6 y 9.3)

| # | Decisión pendiente | Bloque | Prioridad |
|---|---|---|---|
| 1 | Aprobar autorregistro con rol `cliente` y sus permisos por defecto | A | Alta |
| 2 | Exigir o no confirmación de correo | A | Alta |
| 3 | Matriz de roles y permisos por módulo | A | Alta |
| 4 | Estados y transiciones de pedidos, exportaciones, pagos y envíos | B | Alta |
| 5 | Regla de inventario: reserva, descuento, reversos y stock negativo | B | Alta |
| 6 | Alcance de pagos (registro o pasarela) y vencimiento | B | Media |
| 7 | Alcance legal y fuentes para HS, EUDR y EUR.1 | C | Alta |
| 8 | Parámetros de rendimiento, disponibilidad y respaldos | D | Media |
| 9 | Sustituto de OpenAPI para el contrato de servicios | D | Baja |
| 10 | Dependencia de Supabase como entorno productivo | D | Alta |

## 6. Registro de la sesión (completar durante y después)

**Fecha:** ____________  **Modalidad:** ☐ Presencial ☐ Virtual  **Relator:** ____________

**Asistentes:**

| Nombre | Rol | Firma / confirmación |
|---|---|---|
|  |  |  |

**Decisiones:**

| # (sección 5) | Decisión tomada | Motivo | Quién decide | Estado (☐ Aprobada ☐ Rechazada ☐ Pendiente) | Responsable de seguimiento | Fecha límite |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

**Requisitos nuevos o modificados:**

| ID propuesto | Requisito | Origen (quién lo pidió) | Prioridad (MoSCoW) | Criterio de aceptación |
|---|---|---|---|---|
|  |  |  |  |  |

**Riesgos y supuestos detectados:**

-

## 7. Después de la sesión

1. Pasar las decisiones aprobadas a `requerimientos.md` (nueva versión) y retirarlas de las secciones 6 y 9.3.
2. Convertir los requisitos nuevos en historias de usuario (actividad "Definir historias de usuario").
3. Enviar el registro a los asistentes para su confirmación; las decisiones no confirmadas quedan como pendientes.
4. Actualizar el backlog con los cambios de alcance.

## 8. Criterios para dar el levantamiento por cerrado

- Todas las decisiones de prioridad Alta de la sección 5 tienen estado Aprobada o Rechazada, con responsable.
- El registro de la sección 6 está completo y confirmado por el decisor de negocio.
- `requerimientos.md` refleja lo decidido y su sección de decisiones abiertas está al día.
