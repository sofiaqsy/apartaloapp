import 'package:apartalo_app/screens/tabs/pedidos/widgets/detalle_pedido/info_basica_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Who created each pedido (11 Nov 2026). Fake data only.
  test('the text says who and from where', () {
    expect(InfoBasicaWidget.textoCreadoPor({'origen': 'app', 'nombre': 'Obed Ejemplo'}), 'Obed Ejemplo · Nuevo Pedido en la app');
    expect(InfoBasicaWidget.textoCreadoPor({'origen': 'app', 'email': 'equipo@example.com'}), 'equipo@example.com · Nuevo Pedido en la app');
    expect(InfoBasicaWidget.textoCreadoPor({'origen': 'app'}), 'Alguien del equipo · Nuevo Pedido en la app');
    expect(InfoBasicaWidget.textoCreadoPor({'origen': 'whatsapp'}), 'El cliente, por el bot de WhatsApp');
    expect(InfoBasicaWidget.textoCreadoPor(null), isNull);
  });

  testWidgets('the detail shows Creado por only when it is known', (tester) async {
    final pedido = {'id': 'ORD-EJEMPLO', 'whatsapp': '999000000'};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InfoBasicaWidget(pedido: pedido, creadoPor: const {'origen': 'app', 'nombre': 'Obed Ejemplo'}))));
    expect(find.text('Creado por'), findsOneWidget);
    expect(find.text('Obed Ejemplo · Nuevo Pedido en la app'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: InfoBasicaWidget(pedido: pedido))));
    expect(find.text('Creado por'), findsNothing);
  });
}
