/// An address for a Unix domain socket.
///
/// Supports two addressing modes:
/// - **Filesystem path** — a regular path on the filesystem (e.g. `/tmp/my.sock`).
///   Subject to filesystem permissions and the 108-byte `sun_path` limit.
/// - **Abstract namespace** (Linux-only) — a name that does not exist on the filesystem.
///   Identified by a leading null byte in the internal `sockaddr_un`.
///
/// To create a filesystem address:
/// ```dart
/// final addr = Address.file('/tmp/my.sock');
/// ```
///
/// To create an abstract namespace address:
/// ```dart
/// final addr = Address.abstract('myservice');
/// ```
class Address {
  final String _path;
  final bool _isAbstract;

  const Address._(this._path, this._isAbstract);

  /// Creates an address bound to a filesystem path.
  ///
  /// The [path] must not exceed 107 bytes (leaving room for the null terminator
  /// in `sun_path`). Throws [ArgumentError] if the path is too long.
  factory Address.file(String path) {
    final bytes = _encodePath(path);
    if (bytes.length > 107) {
      throw ArgumentError('Socket path too long (${bytes.length} bytes, max 107)');
    }
    return Address._(path, false);
  }

  /// Creates an address in the Linux abstract namespace.
  ///
  /// The [name] does not appear on the filesystem. The leading null byte
  /// required by the abstract namespace is added automatically.
  factory Address.abstract(String name) {
    final bytes = _encodePath(name);
    if (bytes.length > 107) {
      throw ArgumentError('Abstract socket name too long (${bytes.length} bytes, max 107)');
    }
    return Address._(name, true);
  }

  /// The raw path or name string.
  String get path => _path;

  /// Whether this address uses the Linux abstract namespace.
  bool get isAbstract => _isAbstract;

  static List<int> _encodePath(String path) => path.codeUnits;
}
