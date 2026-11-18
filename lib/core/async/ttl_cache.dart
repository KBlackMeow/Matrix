/// 带 TTL 的最简缓存（无依赖，便于单测）。
///
/// 用于 Tab 补全：目录列表与命令列表在短时间内复用，避免每次按键都打远端。
class TtlCache<K, V> {
  TtlCache(this.ttl);

  final Duration ttl;
  final Map<K, V> _values = <K, V>{};
  final Map<K, DateTime> _stamps = <K, DateTime>{};

  V? get(K key) {
    final value = _values[key];
    final at = _stamps[key];
    if (value == null || at == null) return null;
    if (DateTime.now().difference(at) > ttl) {
      _values.remove(key);
      _stamps.remove(key);
      return null;
    }
    return value;
  }

  void put(K key, V value) {
    _values[key] = value;
    _stamps[key] = DateTime.now();
  }

  /// 读取或计算：命中直接返回，未命中执行 [loader] 并写入。
  Future<V> fetch(K key, Future<V> Function() loader) async {
    final hit = get(key);
    if (hit != null) return hit;
    final value = await loader();
    put(key, value);
    return value;
  }

  void invalidate(K key) {
    _values.remove(key);
    _stamps.remove(key);
  }

  void clear() {
    _values.clear();
    _stamps.clear();
  }

  int get length => _values.length;
}
