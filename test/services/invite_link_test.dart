import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/services/invite_link.dart';

void main() {
  group('InviteLink.codigoDe', () {
    test('lee el código del enlace de la app', () {
      expect(InviteLink.codigoDe(Uri.parse('fincas://unirse?codigo=abcd-efgh')), 'ABCD-EFGH');
    });
    test('lee el código de la página web', () {
      expect(InviteLink.codigoDe(Uri.parse('https://x.herokuapp.com/unirse/ABCDEFGH')), 'ABCD-EFGH');
    });
    test('ignora enlaces que no son invitaciones o códigos incompletos', () {
      expect(InviteLink.codigoDe(Uri.parse('fincas://otra?codigo=ABCD-EFGH')), isNull);
      expect(InviteLink.codigoDe(Uri.parse('fincas://unirse?codigo=ABC')), isNull);
      expect(InviteLink.codigoDe(Uri.parse('https://x.com/track/1/2')), isNull);
      expect(InviteLink.codigoDe(null), isNull);
    });
  });
}
