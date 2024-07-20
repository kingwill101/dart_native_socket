import 'dart:typed_data';
import './fd_utilities.dart';

/// Represents a Unix domain socket connection.
///
/// The `UnixSocket` class provides a way to interact with a Unix domain socket.
/// It allows sending data to and receiving data from the socket.
class UnixSocket {
  final int _socket;

  UnixSocket._(this._socket);

  factory UnixSocket(String socketPath) {
    print(socketPath);
    final socket = createUnixSocket(socketPath);
    return UnixSocket._(socket);
  }

  /// Sends data through the Unix domain socket.
  ///
  /// Sends the provided [data] through the Unix domain socket. If an optional [fd] is provided, it will be used as the file descriptor for the send operation.
  /// If the send operation fails, an [Exception] is thrown with the message 'Failed to send data'.
  void send(Uint8List data, {int? fd}) {
    int result = -1;

    result = sendToFd(_socket, data, fd ?? -1);

    if (result == -1) {
      throw Exception('Failed to send data');
    }
  }

  /// Reads all available data from the Unix domain socket and returns it as a [Uint8List].
  ///
  /// This method reads all the data currently available in the Unix domain socket and returns it as a [Uint8List]. If there is no data available, an empty [Uint8List] is returned.
  Uint8List receive() {
    final payload = readAll(_socket, 1024);
    return payload.data;
  }

  /// Closes the Unix domain socket connection.
  ///
  /// This method closes the Unix domain socket connection represented by this `UnixSocket` instance.
  void close() {
    closeFd(_socket);
  }
}
