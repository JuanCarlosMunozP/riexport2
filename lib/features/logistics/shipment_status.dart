/// Estados logísticos de un envío y sus transiciones (espejo de
/// `shipment_status_transition`; la base es quien las hace cumplir).
const shipmentStatusLabels = {
  'planned': 'Planificado',
  'in_transit': 'En tránsito',
  'in_customs': 'En aduana',
  'delivered': 'Entregado',
  'cancelled': 'Cancelado',
};

const shipmentTransitions = {
  'planned': ['in_transit', 'cancelled'],
  'in_transit': ['in_customs', 'delivered', 'cancelled'],
  'in_customs': ['in_transit', 'delivered', 'cancelled'],
  'delivered': <String>[],
  'cancelled': <String>[],
};

const transportModeLabels = {
  'sea': 'Marítimo',
  'air': 'Aéreo',
  'road': 'Terrestre',
  'rail': 'Ferroviario',
};

String shipmentStatusLabel(Object? code) =>
    shipmentStatusLabels['$code'] ?? '${code ?? ''}';

/// Identificador del envío en una fila de `/shipments` (`id`) o de `/tracking` (`shipment_id`).
int? shipmentIdOf(Map<String, dynamic> row) =>
    (row['id'] ?? row['shipment_id']) as int?;
