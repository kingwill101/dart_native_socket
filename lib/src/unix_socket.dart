import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'address.dart';
import 'native_buffer.dart';
import 'socket_type.dart';
import 'native_socket.dart' as ns;

/// A Unix domain socket.
///
/// Supports both **stream** (`SOCK_STREAM`) and **datagram** (`SOCK_DGRAM`) modes,
/// filesystem-path and abstract namespace addressing, and SCM_RIGHTS file
/// descriptor passing.
///
/// ## Stream vs Datagram
///
/// | Operation | Stream (`SocketType.stream`) | Datagram (`SocketType.datagram`) |
/// |---|---|---|
/// | `send()` / `receive()` | ✅ Byte stream (no boundaries) | ❌ |
/// | `sendTo()` / `receiveFrom()` | ❌ | ✅ Message boundaries preserved |
/// | `connect()` / `accept()` | ✅ Client-server | ❌ (connectionless) |
/// | `bind()` | Server socket | Receiver socket |
/// | `receiveFd()` (SCM_RIGHTS) | ✅ | ✅ |
///
/// In stream mode, data is a continuous byte stream — multiple `send()` calls
/// can merge into one `receive()`.  In datagram mode, each `sendTo()` produces
/// exactly one message that `receiveFrom()` returns whole — boundaries are
/// preserved just like UDP over Unix domain sockets.
///
/// ## Creating a stream client connection
///
/// ```dart
/// final socket = UnixSocket.connect(Address.file('/tmp/my.sock'));
/// socket.send(Uint8List.fromList([1, 2, 3]));
/// final data = socket.receive();
/// ```
///
/// ## Creating a stream server
///
/// ```dart
/// final server = UnixSocket.bind(Address.file('/tmp/server.sock'));
/// final conn = server.accept();
/// conn.send(Uint8List.fromList([4, 5, 6]));
/// ```
///
/// ## Using datagram (connectionless) sockets
///
/// ```dart
/// final server = UnixSocket.bind(Address.file('/tmp/dgram.sock'),
///     type: SocketType.datagram);
/// final client = UnixSocket.create(type: SocketType.datagram);
/// client.sendTo(Address.file('/tmp/dgram.sock'), Uint8List.fromList([1, 2]));
/// final msg = server.receiveFrom(1024); // exactly [1, 2]
/// ```
///
/// ## Splitting for concurrent read/write
///
/// ```dart
/// final (reader, writer) = socket.split();
/// // reader and writer can be used from separate isolates/threads.
/// ```
class UnixSocket {
  final int _fd;
  final Address? _boundAddress;

  /// The raw file descriptor.
  int get fd => _fd;

  /// The address this socket is bound to, if any.
  Address? get boundAddress => _boundAddress;

  UnixSocket._(this._fd, [this._boundAddress]);

  /// Creates a socket pair (two connected anonymous sockets).
  ///
  /// This is useful for testing and intra-process communication
  /// without creating a named socket.
  static (UnixSocket, UnixSocket) pair() {
    final sv = calloc<ffi.Int>(2);
    try {
      final result = ns.create_socketpair(sv);
      if (result != 0) {
        throw Exception('Failed to create socket pair');
      }
      return (
        UnixSocket._(sv[0]),
        UnixSocket._(sv[1]),
      );
    } finally {
      calloc.free(sv);
    }
  }

  /// Creates a new socket and connects it to the given [address].
  static UnixSocket connect(Address address) {
    final cType = 1; // SOCK_STREAM
    final fd = ns.create_socket(cType);
    if (fd == -1) {
      throw Exception('Failed to create socket for connection to ${address.path}');
    }

    final pathPointer = address.path.toNativeUtf8().cast<ffi.Char>();
    try {
      int result;
      if (address.isAbstract) {
        result = ns.connect_unix_socket_abstract(fd, pathPointer);
      } else {
        result = ns.connect_unix_socket(fd, pathPointer);
      }
      if (result == -1) {
        ns.close_socket(fd);
        throw Exception('Failed to connect socket at ${address.path}');
      }
    } finally {
      malloc.free(pathPointer);
    }
    return UnixSocket._(fd, address);
  }

  /// Creates a socket of the given [type].
  ///
  /// This is a low-level factory for sockets that are bound but not
  /// connected (e.g., server sockets or datagram receivers).
  static UnixSocket create({SocketType type = SocketType.stream}) {
    final cType = type == SocketType.stream ? 1 : 2; // SOCK_STREAM = 1, SOCK_DGRAM = 2
    final fd = ns.create_socket(cType);
    if (fd == -1) {
      throw Exception('Failed to create socket');
    }
    return UnixSocket._(fd);
  }

  /// Creates a bound socket ready for listening (stream servers) or
  /// receiving (datagram receivers).
  ///
  /// For stream sockets, the socket is automatically set to listen
  /// with the given [backlog].
  static UnixSocket bind(Address address, {SocketType type = SocketType.stream, int backlog = 128}) {
    final socket = UnixSocket.create(type: type);
    _bindAddress(socket._fd, address);
    if (type == SocketType.stream) {
      socket._listen(backlog);
    }
    return UnixSocket._(socket._fd, address);
  }

  /// Binds this socket to an [address].
  ///
  /// Only valid for sockets created with [create] that are not yet bound.
  void rebind(Address address) {
    _bindAddress(_fd, address);
  }

  static void _bindAddress(int fd, Address address) {
    final pathPointer = address.path.toNativeUtf8().cast<ffi.Char>();
    try {
      int result;
      if (address.isAbstract) {
        result = ns.bind_socket_abstract(fd, pathPointer);
      } else {
        result = ns.bind_socket(fd, pathPointer);
      }
      if (result != 0) {
        throw Exception('Failed to bind socket to ${address.path}');
      }
    } finally {
      malloc.free(pathPointer);
    }
  }

  void _listen(int backlog) {
    final result = ns.listen_socket(_fd, backlog);
    if (result != 0) {
      throw Exception('Failed to listen on socket');
    }
  }

  /// Accepts an incoming connection.
  ///
  /// Only valid for bound stream sockets. Returns a connected [UnixSocket].
  UnixSocket accept() {
    final clientFd = ns.accept_socket(_fd);
    if (clientFd == -1) {
      throw Exception('Failed to accept connection');
    }
    return UnixSocket._(clientFd);
  }

  /// Sends [data] over this socket.
  ///
  /// If [fd] is provided (and not -1), the file descriptor is sent
  /// alongside the data via SCM_RIGHTS.
  ///
  /// Returns the number of bytes sent.
  int send(Uint8List data, {int fd = -1}) {
    final bytesPointer = malloc<ffi.Uint8>(data.length);
    try {
      final bytesList = bytesPointer.asTypedList(data.length);
      bytesList.setAll(0, data);

      final sent = ns.send_bytes_with_fd(
        _fd,
        fd,
        bytesPointer.cast<ffi.Void>(),
        data.length,
      );
      if (sent == -1) {
        throw Exception('Failed to send data');
      }
      return sent;
    } finally {
      malloc.free(bytesPointer);
    }
  }

  /// Sends a [NativeBuffer] over this socket (zero-copy path).
  ///
  /// For native (off-heap) buffers, this avoids an intermediate copy.
  int sendBuffer(NativeBuffer buffer, {int fd = -1}) {
    final sent = ns.send_bytes_with_fd(
      _fd,
      fd,
      buffer.nativePointer,
      buffer.length,
    );
    if (sent == -1) {
      throw Exception('Failed to send data');
    }
    return sent;
  }

  /// Receives up to [size] bytes from this socket.
  ///
  /// Returns a [Uint8List] with the received data.
  Uint8List receive([int size = 8192]) {
    final bufferPointer = calloc<ffi.Uint8>(size);
    try {
      for (var attempt = 0; attempt < 100; attempt++) {
        final received = ns.recv_bytes(_fd, bufferPointer.cast<ffi.Void>(), size);
        if (received >= 0) {
          // Copy data out before freeing the backing memory
          final result = Uint8List(received);
          result.setRange(0, received, bufferPointer.asTypedList(received));
          return result;
        }
        // recv_bytes returned -1 (likely EAGAIN) — retry after short sleep
        sleep(const Duration(milliseconds: 5));
      }
      throw Exception('Failed to receive data');
    } finally {
      calloc.free(bufferPointer);
    }
  }

  /// Receives a file descriptor via SCM_RIGHTS.
  ///
  /// Returns the received file descriptor, or throws if no fd is available.
  int receiveFd() {
    final fd = ns.recv_fd(_fd);
    if (fd == -1) {
      throw Exception('Failed to receive file descriptor');
    }
    return fd;
  }

  /// Sends a datagram with [data] to the given [address].
  ///
  /// Only valid on datagram sockets (created with `SocketType.datagram`).
  /// Each call produces exactly one message on the wire — message boundaries
  /// are preserved so the receiver's `receiveFrom()` returns the same bytes.
  int sendTo(Address address, Uint8List data) {
    final pathPointer = address.path.toNativeUtf8().cast<ffi.Char>();
    final dataPointer = malloc<ffi.Uint8>(data.length);
    try {
      dataPointer.asTypedList(data.length).setAll(0, data);

      int sent;
      if (address.isAbstract) {
        sent = ns.send_to_abstract(_fd, pathPointer, dataPointer.cast<ffi.Void>(), data.length);
      } else {
        sent = ns.send_to(_fd, pathPointer, dataPointer.cast<ffi.Void>(), data.length);
      }
      if (sent == -1) {
        throw Exception('Failed to send datagram');
      }
      return sent;
    } finally {
      malloc.free(dataPointer);
      malloc.free(pathPointer);
    }
  }

  /// Receives exactly one datagram (up to [maxSize] bytes).
  ///
  /// Only valid on datagram sockets (created with `SocketType.datagram`).
  /// Returns the received data as a [Uint8List] — the data corresponds to
  /// exactly one `sendTo()` call by the sender (message boundary preservation).
  Uint8List receiveFrom([int maxSize = 8192]) {
    final bufferPointer = calloc<ffi.Uint8>(maxSize);
    try {
      for (var attempt = 0; attempt < 100; attempt++) {
        final received = ns.recv_from(_fd, bufferPointer.cast<ffi.Void>(), maxSize);
        if (received >= 0) {
          // Copy data out before freeing the backing memory
          final result = Uint8List(received);
          result.setRange(0, received, bufferPointer.asTypedList(received));
          return result;
        }
        // recv_from returned -1 (likely EAGAIN) — retry after short sleep
        sleep(const Duration(milliseconds: 5));
      }
      throw Exception('Failed to receive datagram');
    } finally {
      calloc.free(bufferPointer);
    }
  }

  /// Checks whether this socket has data available to read.
  bool get hasData {
    final result = ns.socket_has_data(_fd, 0);
    if (result == -1) {
      throw Exception('Error checking socket for data');
    }
    return result == 1;
  }

  /// Waits up to [timeoutMs] milliseconds for data to become available.
  ///
  /// Returns `true` if data is available, `false` on timeout.
  bool waitForData(int timeoutMs) {
    final result = ns.socket_has_data(_fd, timeoutMs);
    if (result == -1) {
      throw Exception('Error waiting for socket data');
    }
    return result == 1;
  }

  // ---------------------------------------------------------------------------
  // Socket options
  // ---------------------------------------------------------------------------

  /// Sets the send buffer size (`SO_SNDBUF`).
  void setSendBufferSize(int size) {
    if (ns.set_so_sndbuf(_fd, size) != 0) {
      throw Exception('Failed to set SO_SNDBUF');
    }
  }

  /// Gets the send buffer size (`SO_SNDBUF`).
  int getSendBufferSize() {
    final value = ns.get_so_sndbuf(_fd);
    if (value == -1) {
      throw Exception('Failed to get SO_SNDBUF');
    }
    return value;
  }

  /// Sets the receive buffer size (`SO_RCVBUF`).
  void setReceiveBufferSize(int size) {
    if (ns.set_so_rcvbuf(_fd, size) != 0) {
      throw Exception('Failed to set SO_RCVBUF');
    }
  }

  /// Gets the receive buffer size (`SO_RCVBUF`).
  int getReceiveBufferSize() {
    final value = ns.get_so_rcvbuf(_fd);
    if (value == -1) {
      throw Exception('Failed to get SO_RCVBUF');
    }
    return value;
  }

  /// Sets `SO_LINGER`.
  ///
  /// If [enabled] is `true`, close() will block up to [seconds] to
  /// flush pending data.
  void setLinger(bool enabled, int seconds) {
    if (ns.set_so_linger(_fd, enabled ? 1 : 0, seconds) != 0) {
      throw Exception('Failed to set SO_LINGER');
    }
  }

  // ---------------------------------------------------------------------------
  // Splitting
  // ---------------------------------------------------------------------------

  /// Splits this socket into separate reader and writer halves.
  ///
  /// The reader and writer can be used from separate isolates or
  /// async tasks concurrently (like Java NIO's SocketChannel or
  /// Tokio's into_split()).
  (SocketReader, SocketWriter) split() {
    return (SocketReader._(_fd), SocketWriter._(_fd));
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Unlinks the bound address from the filesystem.
  ///
  /// Unix domain socket paths persist after the socket is closed and
  /// must be explicitly unlinked. This is a common source of
  /// "address already in use" errors.
  void unlink() {
    if (_boundAddress == null) return;
    final pathPointer = _boundAddress.path.toNativeUtf8().cast<ffi.Char>();
    try {
      ns.unlink_socket_path(pathPointer);
    } finally {
      malloc.free(pathPointer);
    }
  }

  /// Closes this socket.
  void close() {
    ns.close_socket(_fd);
  }

  /// Closes and optionally unlinks the socket.
  void closeAndUnlink() {
    unlink();
    close();
  }
}

/// The read half of a split [UnixSocket].
///
/// Can be used concurrently with [SocketWriter].
class SocketReader {
  final int _fd;
  SocketReader._(this._fd);

  /// Receives data from the socket.
  Uint8List receive([int size = 8192]) {
    final bufferPointer = calloc<ffi.Uint8>(size);
    try {
      for (var attempt = 0; attempt < 100; attempt++) {
        final received = ns.recv_bytes(_fd, bufferPointer.cast<ffi.Void>(), size);
        if (received >= 0) {
          // Copy data out before freeing the backing memory
          final result = Uint8List(received);
          result.setRange(0, received, bufferPointer.asTypedList(received));
          return result;
        }
        sleep(const Duration(milliseconds: 5));
      }
      throw Exception('Failed to receive data');
    } finally {
      calloc.free(bufferPointer);
    }
  }

  /// Receives a file descriptor via SCM_RIGHTS.
  int receiveFd() {
    final fd = ns.recv_fd(_fd);
    if (fd == -1) {
      throw Exception('Failed to receive file descriptor');
    }
    return fd;
  }

  /// Whether this half has data available.
  bool get hasData {
    final result = ns.socket_has_data(_fd, 0);
    if (result == -1) {
      throw Exception('Error checking socket for data');
    }
    return result == 1;
  }
}

/// The write half of a split [UnixSocket].
///
/// Can be used concurrently with [SocketReader].
class SocketWriter {
  final int _fd;
  SocketWriter._(this._fd);

  /// Sends data over the socket.
  int send(Uint8List data, {int fd = -1}) {
    final bytesPointer = malloc<ffi.Uint8>(data.length);
    try {
      final bytesList = bytesPointer.asTypedList(data.length);
      bytesList.setAll(0, data);

      final sent = ns.send_bytes_with_fd(
        _fd,
        fd,
        bytesPointer.cast<ffi.Void>(),
        data.length,
      );
      if (sent == -1) {
        throw Exception('Failed to send data');
      }
      return sent;
    } finally {
      malloc.free(bytesPointer);
    }
  }
}
