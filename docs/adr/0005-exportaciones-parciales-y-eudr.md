# ADR 0005 — Exportaciones parciales y validez EUDR
**Estado:** Aceptada (supuestos pendientes de validar con el cliente)
**Decisión:** Un pedido confirmado admite varias exportaciones parciales; `export_line` conserva lote y código HS (snapshot). Un envío transporta la exportación completa. La declaración EUDR (`export_eudr_declaration`) es **válida** solo si hay líneas y todas llegan a lote → finca con coordenadas → proveedor y tienen código HS; si no, devuelve la lista de problemas.
**Consecuencias:** No hay polígonos de parcela (solo punto); si el cliente exige polígonos habrá que ampliar `farm`.
