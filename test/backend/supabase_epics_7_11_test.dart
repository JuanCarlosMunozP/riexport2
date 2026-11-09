import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riexport_app/backend/supabase_backend_client.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';

http.Response _json(Object? body, [int status = 200, Map<String, String>? h]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...?h},
    );

ApiClient _api(Future<http.Response> Function(http.Request request) handler) =>
    ApiClient(
      config: ApiConfig(),
      client: SupabaseBackendClient(
        url: 'https://demo.supabase.co',
        anonKey: 'anon-key',
        inner: MockClient(handler),
      ),
      tokenProvider: () => 'jwt',
    );

TypeMatcher<ApiException> _status(int code) =>
    isA<ApiException>().having((e) => e.statusCode, 'status', code);

void main() {
  group('documentos (EP-7)', () {
    test('genera la factura y devuelve una URL firmada', () async {
      final seen = <String>[];
      final api = _api((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.url.path == '/functions/v1/generate-document') {
          expect(jsonDecode(request.body), {
            'export_id': 9,
            'document_type': 'commercial_invoice',
          });
          return _json({
            'id': 3,
            'version': 1,
            'document_number': 'FAC-2026-000001',
            'object_path': 'exports/9/commercial_invoice/a.pdf',
          }, 201);
        }
        return _json({
          'signedURL': '/object/sign/export-documents/a.pdf?token=t',
        });
      });
      final result =
          await api.post(
                '/exports/9/documents',
                body: {'document_type': 'commercial_invoice'},
              )
              as Map;
      expect(result['document_number'], 'FAC-2026-000001');
      expect(
        result['download_url'],
        'https://demo.supabase.co/storage/v1/object/sign/export-documents/a.pdf?token=t',
      );
      expect(seen, [
        'POST /functions/v1/generate-document',
        'POST /storage/v1/object/sign/export-documents/exports/9/commercial_invoice/a.pdf',
      ]);
    });

    test('rechaza tipos que no se generan ni se adjuntan', () async {
      final api = _api((_) async => fail('no debe llamar a Supabase'));
      await expectLater(
        api.post('/exports/9/documents', body: {'document_type': 'hack'}),
        throwsA(_status(422)),
      );
      await expectLater(
        api.post(
          '/exports/9/documents/upload',
          body: {'document_type': 'commercial_invoice'},
        ),
        throwsA(_status(422)),
      );
    });

    test('lista el expediente y firma la descarga de un documento', () async {
      final api = _api((request) async {
        if (request.url.path == '/rest/v1/export_dossier') {
          if (request.url.queryParameters['id'] == 'eq.4') {
            return _json([
              {
                'id': 4,
                'object_path': 'exports/9/packing_list/b.pdf',
                'original_name': 'PL.pdf',
              },
            ]);
          }
          expect(request.url.queryParameters['export_id'], 'eq.9');
          return _json(
            [
              {'id': 4, 'document_type': 'packing_list', 'version': 1},
            ],
            200,
            {'content-range': '0-0/1'},
          );
        }
        return _json({
          'signedURL': '/object/sign/export-documents/b.pdf?token=z',
        });
      });
      final page = await api.get('/exports/9/documents') as Map;
      expect((page['items'] as List).single['document_type'], 'packing_list');
      final download = await api.get('/documents/4/download') as Map;
      expect(download['original_name'], 'PL.pdf');
      expect(download['download_url'], contains('b.pdf?token=z'));
    });

    test('un documento ajeno o inexistente responde 404', () async {
      final api = _api((_) async => _json([]));
      await expectLater(
        api.get('/documents/77/download'),
        throwsA(_status(404)),
      );
    });

    group('adjuntos', () {
      final pdf = base64Encode(List.filled(32, 7));

      test('sube el archivo y lo registra por RPC', () async {
        final seen = <String>[];
        final api = _api((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path.startsWith(
                '/storage/v1/object/export-documents/uploads/9/',
              )) {
            expect(request.headers['Content-Type'], 'application/pdf');
            expect(request.bodyBytes.length, 32);
            expect(request.url.path, endsWith('_fito_2026.PDF'));
            return _json({'Key': 'ok'});
          }
          expect(request.url.path, '/rest/v1/rpc/register_export_document');
          final p = (jsonDecode(request.body) as Map)['p'] as Map;
          expect(p['document_type'], 'phytosanitary_certificate');
          expect(p['mime_type'], 'application/pdf');
          expect(p['byte_size'], 32);
          expect(p['object_path'], startsWith('uploads/9/'));
          return _json({'id': 12, 'version': 1});
        });
        final result =
            await api.post(
                  '/exports/9/documents/upload',
                  body: {
                    'document_type': 'phytosanitary_certificate',
                    'file_name': 'fito 2026.PDF',
                    'content_base64': pdf,
                  },
                )
                as Map;
        expect(result['id'], 12);
        expect(seen.length, 2);
      });

      test(
        'valida extensión, contenido y tamaño sin llamar a Supabase',
        () async {
          final api = _api((_) async => fail('no debe llamar a Supabase'));
          Future<void> rejects(Map<String, dynamic> body) => expectLater(
            api.post(
              '/exports/9/documents/upload',
              body: {'document_type': 'phytosanitary_certificate', ...body},
            ),
            throwsA(_status(422)),
          );
          await rejects({'file_name': 'virus.exe', 'content_base64': pdf});
          await rejects({'file_name': 'sin_extension', 'content_base64': pdf});
          await rejects({'file_name': 'a.pdf', 'content_base64': '***'});
          await rejects({'file_name': 'a.pdf', 'content_base64': ''});
          await rejects({
            'file_name': 'grande.pdf',
            'content_base64': base64Encode(
              List.filled(10 * 1024 * 1024 + 1, 1),
            ),
          });
        },
      );

      test(
        'si la base rechaza el registro, retira el archivo subido',
        () async {
          final calls = <String>[];
          final api = _api((request) async {
            calls.add('${request.method} ${request.url.path}');
            if (request.url.path.startsWith(
                  '/storage/v1/object/export-documents/',
                ) &&
                request.method == 'POST') {
              return _json({'Key': 'ok'});
            }
            if (request.url.path == '/rest/v1/rpc/register_export_document') {
              return _json({
                'code': '22023',
                'message': 'Solo se aceptan archivos PDF, PNG o JPEG.',
              }, 400);
            }
            return _json({});
          });
          await expectLater(
            api.post(
              '/exports/9/documents/upload',
              body: {
                'document_type': 'phytosanitary_certificate',
                'file_name': 'fito.pdf',
                'content_base64': pdf,
              },
            ),
            throwsA(_status(422)),
          );
          expect(
            calls.last,
            startsWith('DELETE /storage/v1/object/export-documents/uploads/9/'),
          );
        },
      );

      test('traduce el rechazo de Storage por permisos', () async {
        final api = _api(
          (_) async => _json({
            'statusCode': '403',
            'message': 'new row violates row-level security policy',
          }, 403),
        );
        await expectLater(
          api.post(
            '/exports/9/documents/upload',
            body: {
              'document_type': 'phytosanitary_certificate',
              'file_name': 'fito.pdf',
              'content_base64': pdf,
            },
          ),
          throwsA(_status(403)),
        );
      });
    });
  });

  group('inventario (EP-8)', () {
    test('consulta el resumen por producto y filtra stock bajo', () async {
      final api = _api((request) async {
        expect(request.url.path, '/rest/v1/inventory_overview');
        expect(request.url.queryParameters['is_low_stock'], 'eq.true');
        return _json(
          [
            {'product_id': 1, 'is_low_stock': true},
          ],
          200,
          {'content-range': '0-0/1'},
        );
      });
      final page =
          await api.get(
                '/inventory/overview',
                queryParameters: {'low_stock': 'true'},
              )
              as Map;
      expect((page['items'] as List).single['is_low_stock'], true);
    });
  });

  group('pagos (EP-9)', () {
    test('cartera con filtros y conversión a otra moneda', () async {
      final api = _api((request) async {
        if (request.url.path == '/rest/v1/payment_portfolio') {
          expect(request.url.queryParameters['status'], 'eq.overdue');
          expect(
            request.url.queryParameters['or'],
            contains('order_number.ilike.*PED*'),
          );
          return _json(
            [
              {'obligation_id': 1, 'balance': 100, 'currency_code': 'EUR'},
              {'obligation_id': 2, 'balance': 50, 'currency_code': 'USD'},
            ],
            200,
            {'content-range': '0-1/2'},
          );
        }
        expect(request.url.path, '/rest/v1/rpc/payment_portfolio_in');
        expect(jsonDecode(request.body), {'p_currency': 'USD'});
        return _json([
          {
            'obligation_id': 1,
            'amount_due_converted': 120,
            'balance_converted': 110,
            'rate': 1.1,
          },
        ]);
      });
      final page =
          await api.get(
                '/payments/portfolio',
                queryParameters: {
                  'status': 'overdue',
                  'q': 'PED',
                  'currency': 'usd',
                },
              )
              as Map;
      final items = (page['items'] as List).cast<Map>();
      expect(items[0]['balance_converted'], 110);
      expect(items[0]['converted_currency'], 'USD');
      expect(items[1]['balance_converted'], isNull);
    });

    test('valida estado y moneda de la cartera', () async {
      final api = _api((_) async => fail('no debe llamar a Supabase'));
      await expectLater(
        api.get('/payments/portfolio', queryParameters: {'status': 'x'}),
        throwsA(_status(422)),
      );
      await expectLater(
        api.get('/payments/portfolio', queryParameters: {'currency': 'DOLAR'}),
        throwsA(_status(422)),
      );
    });

    test('convierte un monto con la función de la base', () async {
      final api = _api((request) async {
        expect(request.url.path, '/rest/v1/rpc/convert_amount');
        expect(jsonDecode(request.body), {
          'p_amount': 100,
          'p_from': 'EUR',
          'p_to': 'USD',
        });
        return _json({'converted': 110.0, 'rate': 1.1, 'source': 'manual'});
      });
      final r =
          await api.get(
                '/payments/convert',
                queryParameters: {'amount': '100', 'from': 'eur', 'to': 'usd'},
              )
              as Map;
      expect(r['converted'], 110.0);
      await expectLater(
        _api(
          (_) async => fail('no'),
        ).get('/payments/convert', queryParameters: {'amount': 'x'}),
        throwsA(_status(422)),
      );
    });

    test('un pago que supera el saldo se informa como validación', () async {
      final api = _api((request) async {
        expect(request.url.path, '/rest/v1/payment_transaction');
        return _json({
          'code': '23514',
          'message': 'El pago supera el saldo de la obligación.',
        }, 400);
      });
      await expectLater(
        api.post(
          '/payments/transactions',
          body: {'obligation_id': 1, 'amount': 999, 'currency_code': 'USD'},
        ),
        throwsA(
          _status(422).having(
            (e) => e.details.first.message,
            'detalle',
            contains('supera el saldo'),
          ),
        ),
      );
    });

    test(
      'actualiza las tasas desde el servicio externo y registra manuales',
      () async {
        final api = _api((request) async {
          if (request.url.path == '/functions/v1/refresh-exchange-rates') {
            return _json({
              'source': 'open.er-api.com',
              'saved': ['EUR', 'COP'],
            });
          }
          expect(request.url.path, '/rest/v1/rpc/register_exchange_rate');
          expect((jsonDecode(request.body) as Map)['p']['rate'], 1.1);
          return _json(7);
        });
        final refreshed =
            await api.post('/payments/exchange-rates/refresh') as Map;
        expect(refreshed['saved'], ['EUR', 'COP']);
        final created =
            await api.post(
                  '/payments/exchange-rates',
                  body: {
                    'base_currency_code': 'EUR',
                    'quote_currency_code': 'USD',
                    'rate': 1.1,
                  },
                )
                as Map;
        expect(created['id'], 7);
      },
    );
  });

  group('logística (EP-10)', () {
    test('cambia el estado por RPC con el id de la ruta', () async {
      final api = _api((request) async {
        expect(request.url.path, '/rest/v1/rpc/update_shipment_status');
        expect(jsonDecode(request.body), {
          'p': {
            'status': 'in_transit',
            'location': 'Cartagena',
            'shipment_id': 5,
          },
        });
        return _json({
          'id': 5,
          'status': 'in_transit',
          'previous_status': 'planned',
        });
      });
      final r =
          await api.post(
                '/shipments/5/status',
                body: {'status': 'in_transit', 'location': 'Cartagena'},
              )
              as Map;
      expect(r['previous_status'], 'planned');
    });

    test('una transición no permitida se informa como conflicto', () async {
      final api = _api(
        (_) async => _json({
          'code': 'P0001',
          'message': 'No se puede pasar el envío de planned a delivered.',
        }, 400),
      );
      await expectLater(
        api.post('/shipments/5/status', body: {'status': 'delivered'}),
        throwsA(
          _status(
            409,
          ).having((e) => e.message, 'mensaje', contains('No se puede pasar')),
        ),
      );
    });

    test('solo se editan los datos de transporte', () async {
      final api = _api((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.queryParameters['id'], 'eq.5');
        final body = jsonDecode(request.body) as Map;
        expect(body.keys, containsAll(['carrier', 'updated_at']));
        expect(body.containsKey('status'), isFalse);
        return _json([
          {'id': 5, 'carrier': 'MSC'},
        ]);
      });
      await api.patch('/shipments/5', body: {'carrier': 'MSC'});
      await expectLater(
        _api(
          (_) async => fail('no'),
        ).patch('/shipments/5', body: {'status': 'delivered'}),
        throwsA(_status(422)),
      );
      await expectLater(
        _api((_) async => fail('no')).patch('/shipments/5', body: {}),
        throwsA(_status(422)),
      );
    });

    test(
      'registra eventos por RPC y consulta el seguimiento del cliente',
      () async {
        final api = _api((request) async {
          if (request.url.path == '/rest/v1/rpc/add_shipment_event') {
            expect((jsonDecode(request.body) as Map)['p']['shipment_id'], 5);
            return _json(31);
          }
          expect(request.url.path, '/rest/v1/customer_shipment_tracking');
          expect(request.url.queryParameters['shipment_id'], 'eq.5');
          return _json(
            [
              {'shipment_id': 5, 'status': 'in_transit'},
            ],
            200,
            {'content-range': '0-0/1'},
          );
        });
        final event =
            await api.post(
                  '/shipments/5/events',
                  body: {'event_type': 'inspeccion'},
                )
                as Map;
        expect(event['id'], 31);
        final tracking =
            await api.get('/tracking', queryParameters: {'id': '5'}) as Map;
        expect((tracking['items'] as List).single['shipment_id'], 5);
      },
    );

    test('el filtro de envíos acepta el estado en aduana y el id', () async {
      final api = _api((request) async {
        expect(request.url.queryParameters['status'], 'eq.in_customs');
        expect(request.url.queryParameters['id'], 'eq.5');
        return _json([], 200, {'content-range': '*/0'});
      });
      await api.get(
        '/shipments',
        queryParameters: {'status': 'in_customs', 'id': '5'},
      );
    });
  });

  group('notificaciones (EP-11)', () {
    test('lista solo las no leídas', () async {
      final api = _api((request) async {
        expect(request.url.path, '/rest/v1/notification');
        expect(request.url.queryParameters['read_at'], 'is.null');
        expect(request.url.queryParameters['limit'], '1');
        return _json(
          [
            {'id': 1},
          ],
          200,
          {'content-range': '0-0/8'},
        );
      });
      final page =
          await api.get(
                '/notifications',
                queryParameters: {'unread': 'true', 'limit': '1'},
              )
              as Map;
      expect((page['pagination'] as Map)['total'], 8);
    });

    test('marca todas como leídas y ejecuta las alertas pendientes', () async {
      final api = _api((request) async {
        if (request.url.path == '/rest/v1/rpc/mark_all_notifications_read') {
          return _json(3);
        }
        expect(request.url.path, '/rest/v1/rpc/run_scheduled_alerts');
        return _json({'skipped': false, 'low_stock': 1, 'payments': 0});
      });
      expect((await api.post('/notifications/read-all') as Map)['updated'], 3);
      expect((await api.post('/notifications/refresh') as Map)['low_stock'], 1);
    });

    test('solo se puede actualizar read_at', () async {
      final api = _api((_) async => fail('no debe llamar a Supabase'));
      await expectLater(
        api.patch('/notifications/1', body: {'title': 'x'}),
        throwsA(_status(422)),
      );
    });
  });
}
