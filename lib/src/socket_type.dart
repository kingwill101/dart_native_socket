/// The type of a Unix domain socket.
enum SocketType {
  /// Connection-oriented, ordered, reliable delivery.
  /// Equivalent to TCP over Unix domain sockets.
  stream,

  /// Connectionless, message-boundary-preserving delivery.
  /// Supported on all Unix-like platforms.
  datagram,
}
