import 'package:flutter/material.dart';

class RoleCreateDialog extends StatefulWidget {
  const RoleCreateDialog({super.key});

  @override
  State<RoleCreateDialog> createState() => _RoleCreateDialogState();
}

class _RoleCreateDialogState extends State<RoleCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Crear rol'),
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'supervisor_logistico',
              ),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : 'Ingresa un nombre para el rol.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, <String, Object?>{
            'name': _name.text.trim(),
            'description': _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
          });
        },
        child: const Text('Crear'),
      ),
    ],
  );
}
