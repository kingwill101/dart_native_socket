import 'dart:typed_data';

import 'package:native_socket/src/fd_utilities.dart';

// UnixSocket class
/// Represents a Unix domain socket.
///
/// The `UnixSocket` class provides a way to interact with a Unix domain socket.
/// It allows you to send and receive data over the socket, as well as close the
/// socket connection.
///
/// Example usage:
///
/// final socket = UnixSocket('/path/to/socket');
/// socket.send(Uint8List.fromList([1, 2, 3]));
/// final data = socket.receive();
/// socket.close();
///
class UnixSocket {
  final int _socket;
  final String _socketPath;

  UnixSocket._(this._socket, this._socketPath);

  /// Creates a new [UnixSocket] instance connected to the Unix domain socket at the
  /// specified [socketPath].
  ///
  /// Throws an [Exception] if the socket cannot be created or connected.
  factory UnixSocket(String socketPath) {
    return UnixSocket._(createUnixSocket(socketPath), socketPath);
  }

  /// The path of the Unix domain socket.
  String get socketPath => _socketPath;

  /// Sends the provided [data] over the Unix domain socket.
  ///
  /// If [fd] is provided, it will be used as the file descriptor for the send operation.
  /// If [fd] is not provided, the socket's file descriptor will be used.
  ///
  /// Throws an [Exception] if the send operation fails.
  void send(Uint8List data, {int? fd}) {
    final result = sendToFd(_socket, data, fd ?? -1);
    if (result == -1) {
      throw Exception('Failed to send data');
    }
  }

  /// Reads all available data from the Unix domain socket and returns it as a [Uint8List].
  ///
  /// This method reads all the data that is currently available in the socket's receive buffer
  /// and returns it as a [Uint8List]. If there is no data available, an empty [Uint8List] is returned.
  ///
  /// Throws an [Exception] if the read operation fails.
  Uint8List receive() {
    var data = readAll(_socket);
    return Uint8List.fromList(data.data);
  }

  /// Closes the Unix domain socket connection.
  ///
  /// This method closes the file descriptor associated with the Unix domain socket,
  /// effectively terminating the connection.
  void close() {
    closeFd(_socket);
  }
}
