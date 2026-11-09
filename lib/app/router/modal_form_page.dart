import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Página de go_router que muestra su contenido como un modal sobre la pantalla
/// anterior (en lugar de una pantalla completa). Se cierra con `Navigator.pop`
/// y devuelve su resultado a quien hizo `push`, igual que una ruta normal.
class ModalFormPage<T> extends Page<T> {
  const ModalFormPage({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return DialogRoute<T>(
      context: context,
      settings: this,
      barrierDismissible: false,
      barrierLabel: 'Cerrar formulario',
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final narrow = size.width < 600;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: EdgeInsets.symmetric(
            horizontal: narrow ? 12 : 32,
            vertical: narrow ? 24 : 32,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 680,
              maxHeight: size.height * 0.92,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Ruta cuyo contenido se presenta como modal. Usa los mismos parámetros que
/// [GoRoute] para poder sustituirla sin tocar el resto de la definición.
GoRoute formRoute({
  required String path,
  String? name,
  required GoRouterWidgetBuilder builder,
}) => GoRoute(
  path: path,
  name: name,
  pageBuilder: (context, state) => ModalFormPage<Object?>(
    key: state.pageKey,
    name: state.name ?? state.path,
    child: builder(context, state),
  ),
);
