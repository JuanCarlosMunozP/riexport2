/// Nombre para mostrar de los roles del sistema (los de las diapositivas del
/// cliente). Los roles creados por el administrador se muestran tal cual.
const _labels = <String, String>{
  'administrador': 'Administrador',
  'usuario_comercial': 'Gestor Comercial',
  'encargado_logistico': 'Gestor de Logística',
  'gestor_inventario': 'Gestor de Inventario',
  'gestor_financiero': 'Gestor Financiero',
  'gestor_cumplimiento': 'Gestor de Cumplimiento UE',
  'cliente': 'Cliente',
};

String roleLabel(Object? name) {
  final text = '${name ?? ''}';
  return _labels[text] ?? text;
}
