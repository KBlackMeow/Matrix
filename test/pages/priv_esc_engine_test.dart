import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/pages/priv_esc_engine.dart';

void main() {
  test('parseVerifySuccess accepts root markers', () {
    expect(parseVerifySuccess('VERIFY_OK:foo'), isTrue);
    expect(parseVerifySuccess('uid=0(root) gid=0(root)'), isTrue);
    expect(parseVerifySuccess('euid=0(root)'), isTrue);
    expect(parseVerifySuccess('uid=1000(user)'), isFalse);
  });

  test('isErrorOutput detects transport error prefixes', () {
    expect(isErrorOutput('[Error] boom'), isTrue);
    expect(isErrorOutput('[Timeout]'), isTrue);
    expect(isErrorOutput('[HTTP 500]'), isTrue);
    expect(isErrorOutput('[Connection Error] x'), isTrue);
    expect(isErrorOutput('normal output'), isFalse);
  });

  test('parseDeploySuccess requires DEPLOY_OK', () {
    expect(parseDeploySuccess('ok DEPLOY_OK'), isTrue);
    expect(parseDeploySuccess('DEPLOY_FAILED'), isFalse);
  });

  test('proofSucceeded needs any marker and rejects errors', () {
    expect(proofSucceeded('uid=0(root) gid=0(root)', ['uid=0(root)']), isTrue);
    expect(proofSucceeded('uid=1000(user)', ['uid=0(root)']), isFalse);
    expect(proofSucceeded('[Timeout]', ['uid=0(root)']), isFalse);
  });
}
