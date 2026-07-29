import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/mcp/session_pool.dart';
import 'package:matrix/models/webshell.dart';

/// 验证 SessionPool 隔离：每个连接持有独立 pool，
/// shell_use 不会跨客户端串用。
void main() {
  group('SessionPool isolation', () {
    /// 构造一个最小 WebShell 用于 pool 测试。
    Webshell _dummyShell(int id) => Webshell(
          id: id,
          projectId: 1,
          name: 'test-shell-$id',
          url: 'http://127.0.0.1/test$id.jsp',
          type: 'jsp',
          method: 'POST',
          connectorType: 'jsp_behinder',
          password: 'test',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

    test('defaultShellId in one pool does not affect another pool', () async {
      // 用可预测的 lookup 替代真实数据库
      final shells = <int, Webshell>{
        1: _dummyShell(1),
        2: _dummyShell(2),
      };
      Future<Webshell?> Function(int) lookup = (id) =>
          Future.value(shells[id]);

      final poolA = SessionPool(lookup);
      final poolB = SessionPool(lookup);

      // Pool A 切换到 shell 1
      poolA.defaultShellId = 1;
      final svcA = await poolA.resolve(null);
      expect(svcA.webshell.id, 1);

      // Pool B 不受影响
      expect(poolB.defaultShellId, isNull,
          reason: 'poolB 不应被 poolA 的 shell_use 影响');
    });

    test('each pool caches independently', () async {
      final shells = <int, Webshell>{
        1: _dummyShell(1),
        2: _dummyShell(2),
      };
      Future<Webshell?> Function(int) lookup = (id) =>
          Future.value(shells[id]);

      final poolA = SessionPool(lookup);
      final poolB = SessionPool(lookup);

      // 两个 pool 各自缓存 shell 1（应创建不同 WebshellService 实例）
      final svcA1 = await poolA.get(1);
      final svcB1 = await poolB.get(1);

      expect(poolA.size, 1);
      expect(poolB.size, 1);

      // 同一 pool 内复用
      final svcA1again = await poolA.get(1);
      expect(identical(svcA1, svcA1again), isTrue,
          reason: '同一 pool 内应复用实例');

      // 跨 pool 不共享
      expect(identical(svcA1, svcB1), isFalse,
          reason: '不同 pool 的缓存应独立');
    });

    test('clear on one pool does not affect another', () async {
      final shells = <int, Webshell>{
        1: _dummyShell(1),
      };
      Future<Webshell?> Function(int) lookup = (id) =>
          Future.value(shells[id]);

      final poolA = SessionPool(lookup);
      final poolB = SessionPool(lookup);

      await poolA.get(1);
      await poolB.get(1);

      expect(poolA.size, 1);
      expect(poolB.size, 1);

      poolA.clear();
      expect(poolA.size, 0);
      expect(poolB.size, 1,
          reason: 'poolB 不应受 poolA.clear() 影响');
    });
  });
}
