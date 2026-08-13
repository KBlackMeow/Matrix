import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/priv_esc_landing.dart';
import 'package:matrix/pages/priv_esc_vectors.dart';

void main() {
  test('substitutes {param} placeholders', () {
    final deploy = substituteTemplate(
      landingById('suid_shell').deployTemplate,
      {'mimic': 'kworker'},
    );
    expect(deploy, contains('/tmp/.kworker'));
    expect(deploy, endsWith('echo DEPLOY_OK'));
  });

  test('verifyStrength classifies each landing', () {
    expect(
      landingById('suid_shell').verifyStrength,
      LandingVerifyStrength.executable,
    );
    expect(
      landingById('sudoers_nopasswd').verifyStrength,
      LandingVerifyStrength.executable,
    );
    expect(
      landingById('passwd_user').verifyStrength,
      LandingVerifyStrength.structural,
    );
    expect(
      landingById('root_authorized_keys').verifyStrength,
      LandingVerifyStrength.structural,
    );
  });

  test('passwd landing has openssl→perl→ruby fallback chain', () {
    final deploy = landingById('passwd_user').deployTemplate;
    expect(deploy, contains('openssl passwd'));
    expect(deploy, contains('perl'));
    expect(deploy, contains('ruby'));
    expect(deploy, contains('/etc/passwd'));
  });

  test('passwd_user verify emits a VERIFY_OK success marker', () {
    expect(landingById('passwd_user').verifyTemplate, contains('VERIFY_OK'));
  });

  test('all four landings are present', () {
    expect(
      landingMethods.map((m) => m.id),
      containsAll(['suid_shell', 'sudoers_nopasswd', 'passwd_user', 'root_authorized_keys']),
    );
  });
}
