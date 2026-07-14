/// Native bindings for Unix domain sockets.
///
/// Provides low-level FFI bindings and high-level APIs for:
/// - Stream and datagram Unix domain sockets
/// - Filesystem-path and abstract namespace addressing
/// - SCM_RIGHTS file descriptor passing
/// - Server sockets (bind, listen, accept)
/// - Socket options (SO_SNDBUF, SO_RCVBUF, SO_LINGER)
/// - Native (off-heap) buffers for zero-copy I/O
/// - Concurrent read/write via split reader/writer halves
library;

export 'src/address.dart';
export 'src/native_buffer.dart';
export 'src/socket_type.dart';
export 'src/unix_socket.dart';

// Re-export low-level FFI bindings for advanced use cases.
export 'src/native_socket.dart';
