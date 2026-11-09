import 'package:flutter_test/flutter_test.dart';
import 'package:riexport_app/backend/local_backend_client.dart';
import 'package:riexport_app/core/api/api_client.dart';
import 'package:riexport_app/core/api/api_exception.dart';
import 'package:riexport_app/core/config/api_config.dart';

void main() {
  late ApiClient api;
  late String? token;

  setUp(() async {
    token = null;
    api = ApiClient(
      config: ApiConfig(),
      client: LocalBackendClient(),
      tokenProvider: () => token,
    );
    final login =
        await api.post(
              '/auth/login',
              body: {'email': 'admin@riexport.com', 'password': 'Admin123!'},
            )
            as Map<String, dynamic>;
    token = login['access_token'] as String;
  });

  Future<List> items(String path) async =>
      ((await api.get(path)) as Map)['items'] as List;

  test(
    'el modo local trae envíos, cartera, tasas y avisos de demostración',
    () async {
      expect(await items('/shipments'), hasLength(3));
      expect(await items('/shipment-statuses'), hasLength(5));
      expect(await items('/tracking'), hasLength(3));
      expect(await items('/payments/exchange-rates'), isNotEmpty);
      expect(await items('/notifications'), hasLength(4));

      final portfolio = await items('/payments/portfolio');
      expect(portfolio.map((o) => (o as Map)['status']).toSet(), {
        'pending',
        'partial',
        'overdue',
        'paid',
      });
      final overdue = await items('/payments/portfolio?status=overdue');
      expect(overdue.single['days_overdue'], greaterThan(0));
    },
  );

  test('cambia el estado de un envío solo por transiciones válidas', () async {
    await expectLater(
      api.post('/shipments/3/status', body: {'status': 'delivered'}),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
    await api.post('/shipments/3/status', body: {'status': 'in_transit'});
    final shipments = await items('/shipments?status=in_transit');
    expect(shipments, hasLength(2));
    expect(await items('/shipments/3/events'), hasLength(2));
    expect(await items('/notifications'), hasLength(5));
  });

  test('registra pagos sin superar el saldo y convierte montos', () async {
    await expectLater(
      api.post(
        '/payments/transactions',
        body: {'obligation_id': 1, 'amount': 99999},
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
    await api.post(
      '/payments/transactions',
      body: {'obligation_id': 1, 'amount': 2880},
    );
    final paid = await items('/payments/portfolio?status=paid');
    expect(paid, hasLength(2));

    final r =
        await api.get('/payments/convert?amount=100&from=USD&to=EUR') as Map;
    expect(r['converted'], 92);
  });

  test('marca avisos como leídos', () async {
    expect(await items('/notifications?unread=true'), hasLength(3));
    await api.post('/notifications/read-all', body: {});
    expect(await items('/notifications?unread=true'), isEmpty);
  });
}
