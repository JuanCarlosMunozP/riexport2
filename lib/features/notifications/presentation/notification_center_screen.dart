import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

/// Centro de notificaciones (PLAT-654): avisos de stock bajo, pagos por vencer o
/// vencidos y cambios de estado de envíos. Se abre ejecutando las reglas
/// programadas como respaldo del cron (la base limita la frecuencia).
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({
    super.key,
    required this.loadNotifications,
    required this.markRead,
    required this.markAllRead,
    this.refreshAlerts,
    this.onOpenEntity,
  });

  final Future<List<Map<String, dynamic>>> Function({bool unreadOnly})
  loadNotifications;
  final Future<void> Function(int notificationId) markRead;
  final Future<void> Function() markAllRead;

  /// Ejecuta las reglas de alerta pendientes antes de listar.
  final Future<void> Function()? refreshAlerts;

  /// Abre la pantalla del elemento al que se refiere el aviso.
  final void Function(String entityType, int entityId)? onOpenEntity;

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _unreadOnly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (refresh && widget.refreshAlerts != null) {
        try {
          await widget.refreshAlerts!();
        } catch (_) {
          // Las alertas son un respaldo: si fallan, se muestran los avisos existentes.
        }
      }
      final rows = await widget.loadNotifications(unreadOnly: _unreadOnly);
      if (mounted) setState(() => _items = rows);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar las notificaciones.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isUnread(Map<String, dynamic> item) => item['read_at'] == null;

  Future<void> _open(Map<String, dynamic> item) async {
    if (_isUnread(item)) {
      try {
        await widget.markRead(item['id'] as int);
        if (mounted) {
          setState(() {
            final index = _items.indexOf(item);
            if (index >= 0) {
              _items = [..._items]
                ..[index] = {
                  ...item,
                  'read_at': DateTime.now().toIso8601String(),
                };
            }
          });
        }
      } catch (_) {
        // Marcar como leída no debe impedir abrir el elemento.
      }
    }
    final type = item['entity_type'];
    final id = item['entity_id'];
    if (widget.onOpenEntity != null && type is String && id is int) {
      widget.onOpenEntity!(type, id);
    }
  }

  Future<void> _readAll() async {
    try {
      await widget.markAllRead();
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron marcar como leídas.')),
        );
      }
    }
  }

  IconData _icon(Object? type) => switch ('$type') {
    'low_stock' => Icons.inventory_2_outlined,
    'payment_due' => Icons.schedule_outlined,
    'payment_overdue' => Icons.warning_amber_rounded,
    'shipment_status' => Icons.local_shipping_outlined,
    _ => Icons.notifications_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final unread = _items.where(_isUnread).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(unread > 0 ? 'Notificaciones ($unread)' : 'Notificaciones'),
        actions: [
          IconButton(
            tooltip: _unreadOnly ? 'Ver todas' : 'Ver solo no leídas',
            icon: Icon(
              _unreadOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            onPressed: () {
              _unreadOnly = !_unreadOnly;
              _load();
            },
          ),
          IconButton(
            tooltip: 'Marcar todas como leídas',
            icon: const Icon(Icons.done_all),
            onPressed: unread == 0 ? null : _readAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _items.isEmpty
            ? ListView(
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (!_loading && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: Text('No tienes notificaciones.')),
                    ),
                ],
              )
            : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final isUnread = _isUnread(item);
                  return ListTile(
                    key: ValueKey('notification-${item['id']}'),
                    leading: Icon(_icon(item['notification_type'])),
                    title: Text(
                      '${item['title']}',
                      style: TextStyle(
                        fontWeight: isUnread
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if ('${item['body'] ?? ''}'.isNotEmpty)
                          '${item['body']}',
                        '${item['created_at'] ?? ''}'
                            .replaceFirst('T', ' ')
                            .split('.')
                            .first,
                      ].join('\n'),
                    ),
                    isThreeLine: '${item['body'] ?? ''}'.isNotEmpty,
                    trailing: isUnread
                        ? Icon(
                            Icons.circle,
                            size: 12,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () => _open(item),
                  );
                },
              ),
      ),
    );
  }
}
