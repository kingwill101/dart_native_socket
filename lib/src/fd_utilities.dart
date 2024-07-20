import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_socket.dart' as ns;

/// Writes the given data to the specified file descriptor.
///
/// This function writes the contents of the provided [data] buffer to the file
/// descriptor [fd]. If the write operation is successful, the number of bytes
/// written is returned. If an error occurs, an [Exception] is thrown.
///
/// Parameters:
/// - [fd]: The file descriptor to write the data to.
/// - [data]: The data to be written to the file descriptor.
///
/// Returns:
/// The number of bytes written to the file descriptor.
///
/// Throws:
/// - [Exception]: If an error occurs while writing to the file descriptor.
writeToFd(int fd, Uint8List data) {
  final pointer = calloc<Uint8>(data.length);
  final buffer = pointer.asTypedList(data.length);
  buffer.setAll(0, data);

  int result = ns.write_to_fd(fd, pointer.cast(), data.length);
  if (result < 0) {
    throw Exception("Failed to write to file.");
  }
  return result;
}

/// Creates an anonymous file with the specified size.
///
/// This function creates an anonymous file with the given size. The file is created
/// with the `O_CLOEXEC` flag set, which ensures the file descriptor is closed when
/// the process executes a new program.
///
/// Parameters:
/// - `size`: The size of the anonymous file to create.
///
/// Returns:
/// The file descriptor of the created anonymous file.
///
/// Throws:
/// - `Exception`: If an error occurs while creating the anonymous file.
int createAnonymousFile(int size) {
  return ns.os_create_anonymous_file(size);
}

/// Creates a Unix domain socket with the specified path.
///
/// This function creates a Unix domain socket with the given path. The socket is
/// created with the `SOCK_CLOEXEC` flag set, which ensures the socket is closed
/// when the process executes a new program.
///
/// Parameters:
/// - `path`: The path of the Unix domain socket to create.
///
/// Returns:
/// The file descriptor of the created Unix domain socket.
///
/// Throws:
/// - `Exception`: If an error occurs while creating the Unix domain socket.
int createUnixSocket(String path) {
  final pathPointer = path.toNativeUtf8().cast<Char>();
  final socket = ns.create_unix_socket(pathPointer);
  malloc.free(pathPointer);

  if (socket == -1) {
    throw Exception('Failed to create socket');
  }
  return socket;
}

/// Creates a temporary file with the specified name.
///
/// This function creates a temporary file with the given name. The file is created
/// with the `O_CLOEXEC` flag set, which ensures the file descriptor is closed when
/// the process executes a new program.
///
/// Parameters:
/// - `name`: The name of the temporary file to create.
///
/// Returns:
/// The file descriptor of the created temporary file.
///
/// Throws:
/// - `Exception`: If an error occurs while creating the temporary file.
int createTmpFile(String name) {
  final pathPointer = name.toNativeUtf8().cast<Char>();
  final fd = ns.create_tmpfile_cloexec(pathPointer);
  malloc.free(pathPointer);
  return fd;
}

/// Sends data to the specified file descriptor.
///
/// This function sends the provided data to the specified file descriptor. If an
/// optional file descriptor is provided, it will be sent along with the data.
///
/// Parameters:
/// - `socket`: The integer file descriptor of the socket to send the data to.
/// - `data`: The data to be sent.
/// - `fd`: An optional file descriptor to be sent along with the data (default is -1).
///
/// Returns:
/// The number of bytes sent.
///
/// Throws:
/// - `Exception`: If an error occurs while sending the data.
int sendToFd(int socket, Uint8List data, [int fd = -1]) {
  final bytesPointer = malloc<Uint8>(data.length);
  final bytesList = bytesPointer.asTypedList(data.length);
  bytesList.setAll(0, data);

  final sent = ns.send_bytes_with_fd(
    socket,
    fd,
    bytesPointer.cast<Void>(),
    data.length,
  );

  malloc.free(bytesPointer);

  if (sent == -1) {
    throw Exception('Failed to send data');
  }
  return sent;
}

/// A message containing the result of reading from a socket.
///
/// This class represents the result of reading data from a socket, including the
/// total number of bytes read and the data that was read.
class SocketMessage {
  final int read;
  final Uint8List data;
  SocketMessage(this.read, this.data);
}

/// Reads all available data from the specified socket.
///
/// This function reads data from the specified socket until no more data is available.
/// It returns a `SocketMessage` object containing the total number of bytes read and the concatenated data.
///
/// Parameters:
/// - `socket`: The integer file descriptor of the socket to read from.
/// - `bufferSize`: The maximum number of bytes to read at once (default is 1024).
///
/// Returns:
/// A `SocketMessage` object containing the total number of bytes read and the concatenated data.
///
/// Throws:
/// - `Exception`: If an error occurs while reading from the socket.
SocketMessage readAll(int socket, [int bufferSize = 1024]) {
  List<SocketMessage> data = [];
  while (true) {
    try {
      final nxt = read(socket, bufferSize);
      if (nxt.read == 0) {
        break;
      }
      data.add(nxt);
    } catch (e) {
      break;
    }
  }

  if(data.isEmpty){
    return SocketMessage(0, Uint8List.fromList([]));
  }

  return data.reduce((a, b) => SocketMessage(
      a.read + b.read, Uint8List.fromList(a.data.toList()..addAll(b.data))));
}

/// Reads data from the specified socket.
///
/// This function reads data from the specified socket and returns a `SocketMessage` object
/// containing the total number of bytes read and the data read.
///
/// Parameters:
/// - `socket`: The integer file descriptor of the socket to read from.
/// - `size`: The maximum number of bytes to read at once (default is 1024).
///
/// Returns:
/// A `SocketMessage` object containing the total number of bytes read and the data read.
///
/// Throws:
/// - `Exception`: If an error occurs while reading from the socket.
SocketMessage read(int socket, [int size = 1024]) {
  List<int> data = [];
  int totalRead = 0;
  final bufferPointer = calloc<Uint8>(size);
  final receivedBytes = ns.recv_bytes(socket, bufferPointer.cast<Void>(), size);
  data.addAll(bufferPointer.cast<Uint8>().asTypedList(receivedBytes));
  calloc.free(bufferPointer);
  if (receivedBytes == -1) {
    throw Exception("recv_bytes: nothing to read");
  }

  totalRead += receivedBytes;
  if (data.isEmpty) {
    return SocketMessage(totalRead, Uint8List.fromList([]));
  }

  return SocketMessage(totalRead, Uint8List.fromList(data));
}

/// Closes the specified socket.
///
/// This function is used to close a socket that was previously opened.
/// It calls the `close_socket` function from the `ns` module to perform the actual socket closure.
///
/// Parameters:
/// - `socket`: The integer file descriptor of the socket to be closed.
void closeFd(int socket) {
  ns.close_socket(socket);
}
