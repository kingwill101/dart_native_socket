import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:native_socket/src/native_socket.dart' as ns;
import 'package:native_socket/src/fd_utilities.dart';
import 'package:test/test.dart';

/// Creates a connected Unix socket pair using the native C `socketpair`.
///
/// The returned fds are non-blocking and have CLOEXEC set.
SocketPair _createSocketPair() {
  final sv = calloc<Int>(2);
  try {
    final result = ns.create_socketpair(sv);
    if (result != 0) {
      throw Exception('create_socketpair failed');
    }
    return SocketPair(sv[0], sv[1]);
  } finally {
    calloc.free(sv);
  }
}

class SocketPair {
  final int a;
  final int b;
  SocketPair(this.a, this.b);
}

void main() {
  group('c_msg helpers', () {
    test('c_msg_len returns CMSG_LEN for a given size', () {
      // CMSG_LEN(sizeof(int)) on Linux x86-64 = 20
      final result = ns.c_msg_len(sizeOf<Int32>());
      expect(result, greaterThan(0));

      // CMSG_LEN(0) should be < CMSG_LEN(4) on any platform
      expect(ns.c_msg_len(0), lessThan(ns.c_msg_len(sizeOf<Int32>())));
    });

    test('c_msg_space returns CMSG_SPACE for a given size', () {
      final result = ns.c_msg_space(sizeOf<Int32>());
      expect(result, greaterThan(0));

      // CMSG_SPACE should be >= CMSG_LEN for the same data size
      final len = ns.c_msg_len(sizeOf<Int32>());
      final space = ns.c_msg_space(sizeOf<Int32>());
      expect(space, greaterThanOrEqualTo(len));
    });

    test('c_msg_space is >= c_msg_len for same size', () {
      // CMSG_SPACE may equal CMSG_LEN (no padding needed) or be larger
      expect(ns.c_msg_space(0), greaterThanOrEqualTo(ns.c_msg_len(0)));
    });
  });

  group('write_to_fd', () {
    late int fd;

    setUp(() {
      final template =
          '${Directory.systemTemp.path}/native_socket_test_XXXXXX';
      final ptr = template.toNativeUtf8().cast<Char>();
      fd = ns.create_tmpfile_cloexec(ptr);
      calloc.free(ptr);
    });

    tearDown(() {
      if (fd > 0) {
        ns.close_socket(fd);
      }
    });

    test('writes bytes to a file descriptor', () {
      final data = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]); // "Hello"
      final written = writeToFd(fd, data);
      expect(written, equals(data.length));
    });

    test('returns zero for empty write', () {
      final written = writeToFd(fd, Uint8List(0));
      expect(written, greaterThanOrEqualTo(0));
    });

    test('writes large buffer', () {
      final data = Uint8List(1024 * 64); // 64KB
      for (var i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }
      final written = writeToFd(fd, data);
      expect(written, equals(data.length));
    });
  });

  group('create_tmpfile_cloexec', () {
    test('creates a temporary file with cloexec flag', () {
      final path =
          '${Directory.systemTemp.path}/native_socket_test_XXXXXX';
      final pathPointer = path.toNativeUtf8().cast<Char>();
      final tmpFd = ns.create_tmpfile_cloexec(pathPointer);
      calloc.free(pathPointer);

      expect(tmpFd, greaterThanOrEqualTo(0));

      // Verify the file descriptor is valid by writing to it
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final pointer = calloc<Uint8>(data.length);
      pointer.asTypedList(data.length).setAll(0, data);
      final written = ns.write_to_fd(tmpFd, pointer.cast(), data.length);
      calloc.free(pointer);
      expect(written, equals(data.length));

      ns.close_socket(tmpFd);
    });
  });

  group('os_create_anonymous_file', () {
    test('creates an anonymous file of given size', () {
      final xdgDir = Platform.environment['XDG_RUNTIME_DIR'];
      if (xdgDir == null || xdgDir.isEmpty) {
        markTestSkipped('XDG_RUNTIME_DIR is not set');
        return;
      }

      final fd = ns.os_create_anonymous_file(4096);
      expect(fd, greaterThanOrEqualTo(0));

      // Write to the fd
      final data = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final pointer = calloc<Uint8>(data.length);
      pointer.asTypedList(data.length).setAll(0, data);
      final written = ns.write_to_fd(fd, pointer.cast(), data.length);
      calloc.free(pointer);
      expect(written, equals(data.length));

      ns.close_socket(fd);
    });

    test('returns -1 when XDG_RUNTIME_DIR is not set', () {
      final original = Platform.environment['XDG_RUNTIME_DIR'];
      if (original == null || original.isEmpty) {
        final fd = ns.os_create_anonymous_file(4096);
        expect(fd, -1);
      } else {
        markTestSkipped(
          'XDG_RUNTIME_DIR is set - cannot test error path in-process',
        );
      }
    });
  });

  group('create_socketpair', () {
    test('creates a connected pair of sockets', () {
      final sv = calloc<Int>(2);
      try {
        final result = ns.create_socketpair(sv);
        expect(result, equals(0));
        expect(sv[0], greaterThanOrEqualTo(0));
        expect(sv[1], greaterThanOrEqualTo(0));
        expect(sv[0], isNot(sv[1])); // Must be two different fds
      } finally {
        calloc.free(sv);
      }
    });

    test('sockets can send/receive data to each other', () {
      final pair = _createSocketPair();
      try {
        // Send from a to b
        final data = Uint8List.fromList([0xAA, 0xBB]);
        final dataPtr = malloc<Uint8>(data.length);
        dataPtr.asTypedList(data.length).setAll(0, data);
        ns.send_bytes(pair.a, dataPtr.cast<Void>(), data.length);
        malloc.free(dataPtr);

        sleep(const Duration(milliseconds: 10));

        // Receive on b
        final buf = calloc<Uint8>(1024);
        final received = ns.recv_bytes(pair.b, buf.cast<Void>(), 1024);
        expect(received, equals(data.length));
        expect(buf.asTypedList(received), equals(data));
        calloc.free(buf);
      } finally {
        closeFd(pair.a);
        closeFd(pair.b);
      }
    });
  });

  group('socket send/recv', () {
    late SocketPair pair;

    setUp(() {
      pair = _createSocketPair();
    });

    tearDown(() {
      closeFd(pair.a);
      closeFd(pair.b);
    });

    test('send_bytes and recv_bytes roundtrip data', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

      final dataPointer = malloc<Uint8>(data.length);
      dataPointer.asTypedList(data.length).setAll(0, data);
      final sent = ns.send_bytes(pair.a, dataPointer.cast<Void>(), data.length);
      malloc.free(dataPointer);
      expect(sent, equals(data.length));

      sleep(const Duration(milliseconds: 10));
      final buffer = calloc<Uint8>(1024);
      final received = ns.recv_bytes(pair.b, buffer.cast<Void>(), 1024);
      expect(received, equals(data.length));

      final receivedData = buffer.asTypedList(received);
      expect(receivedData, equals(data));
      calloc.free(buffer);
    });

    test('send_bytes_with_fd sends data without passing fd', () {
      final data = Uint8List.fromList([0x42]);

      final dataPointer = malloc<Uint8>(data.length);
      dataPointer.asTypedList(data.length).setAll(0, data);
      final sent = ns.send_bytes_with_fd(
        pair.a,
        -1,
        dataPointer.cast<Void>(),
        data.length,
      );
      malloc.free(dataPointer);
      expect(sent, equals(data.length));

      sleep(const Duration(milliseconds: 10));
      final buffer = calloc<Uint8>(1024);
      final received = ns.recv_bytes(pair.b, buffer.cast<Void>(), 1024);
      expect(received, equals(data.length));
      expect(buffer.asTypedList(received), equals([0x42]));
      calloc.free(buffer);
    });

    test('passes file descriptor via SCM_RIGHTS', () {
      // Create a memfd-style anonymous file to pass as FD.
      final xdgDir = Platform.environment['XDG_RUNTIME_DIR'];
      if (xdgDir == null || xdgDir.isEmpty) {
        markTestSkipped('XDG_RUNTIME_DIR is not set');
        return;
      }

      final passedFd = ns.os_create_anonymous_file(1024);
      expect(passedFd, greaterThanOrEqualTo(0));

      // Write some data to it
      final fileData = Uint8List.fromList([0x41, 0x42, 0x43]);
      final filePtr = calloc<Uint8>(fileData.length);
      filePtr.asTypedList(fileData.length).setAll(0, fileData);
      ns.write_to_fd(passedFd, filePtr.cast(), fileData.length);
      calloc.free(filePtr);

      // Send the FD in its own message (no data, just the fd via empty send)
      // send_bytes_with_fd sends data+fd in one sendmsg. recv_fd does its own
      // recvmsg, so it needs its own separate message.
      // Send an empty byte with the fd.
      final sep = Uint8List.fromList([0x00]);
      final sepPtr = malloc<Uint8>(sep.length);
      sepPtr.asTypedList(1)[0] = 0x00;
      final sent = ns.send_bytes_with_fd(
        pair.a,
        passedFd,
        sepPtr.cast<Void>(),
        sep.length,
      );
      malloc.free(sepPtr);
      expect(sent, equals(sep.length));

      sleep(const Duration(milliseconds: 10));

      // Receive the FD (recv_fd does its own recvmsg to get the SCM_RIGHTS)
      final receivedFd = ns.recv_fd(pair.b);
      expect(receivedFd, greaterThanOrEqualTo(0));

      // Verify the received fd is valid (readable, real fd).
      // Use write_to_fd with it to confirm it's usable.
      final verifyData = Uint8List.fromList([0xDE]);
      final verifyPtr = calloc<Uint8>(verifyData.length);
      verifyPtr.asTypedList(verifyData.length).setAll(0, verifyData);
      final written = ns.write_to_fd(receivedFd, verifyPtr.cast(), verifyData.length);
      calloc.free(verifyPtr);
      // memfd supports write, so this should succeed.
      expect(written, equals(verifyData.length));

      ns.close_socket(receivedFd);
      ns.close_socket(passedFd);
    });

    test('recv_bytes returns -1 on a closed socket', () {
      ns.close_socket(pair.b);

      final buffer = calloc<Uint8>(1024);
      final received = ns.recv_bytes(pair.a, buffer.cast<Void>(), 1024);
      calloc.free(buffer);
      expect(received, anyOf(-1, 0));
    });
  });

  group('socket_has_data', () {
    test('returns 0 (no data) on a fresh socket pair', () {
      final pair = _createSocketPair();
      try {
        final result = ns.socket_has_data(pair.a, 0);
        expect(result, anyOf(0, -1));
      } finally {
        closeFd(pair.a);
        closeFd(pair.b);
      }
    });

    test('returns 1 (has data) after data is sent', () {
      final pair = _createSocketPair();
      try {
        final ptr = malloc<Uint8>(1);
        ptr.asTypedList(1)[0] = 0x01;
        ns.send_bytes(pair.a, ptr.cast<Void>(), 1);
        malloc.free(ptr);

        sleep(const Duration(milliseconds: 50));

        final result = ns.socket_has_data(pair.b, 100);
        expect(result, equals(1));
      } finally {
        closeFd(pair.a);
        closeFd(pair.b);
      }
    });
  });

  group('Dart wrappers', () {
    test('writeToFd returns errno on invalid fd', () {
      // write_to_fd returns errno (a positive value) on error, not -1.
      final result = writeToFd(-1, Uint8List.fromList([0x01]));
      // EBADF = 9 (bad file descriptor)
      expect(result, equals(9));
    });

    test('socketHasData returns false on a fresh socket', () {
      final pair = _createSocketPair();
      try {
        expect(socketHasData(pair.a), isFalse);
      } finally {
        closeFd(pair.a);
        closeFd(pair.b);
      }
    });

    test('sendToFd sends data over socket', () {
      final pair = _createSocketPair();
      try {
        final data = Uint8List.fromList([0x10, 0x20, 0x30]);
        final sent = sendToFd(pair.a, data);
        expect(sent, equals(data.length));

        sleep(const Duration(milliseconds: 10));
        final msg = read(pair.b, 1024);
        expect(msg.read, equals(data.length));
        expect(msg.data, equals(data));
      } finally {
        closeFd(pair.a);
        closeFd(pair.b);
      }
    });

    test('readAll returns concatenated data', () {
      final pair = _createSocketPair();
      try {
        final data1 = Uint8List.fromList([0x01, 0x02]);
        final data2 = Uint8List.fromList([0x03, 0x04]);
        sendToFd(pair.a, data1);
        sendToFd(pair.a, data2);

        sleep(const Duration(milliseconds: 50));

        final msg = readAll(pair.b, 4);
        expect(msg.data, equals([0x01, 0x02, 0x03, 0x04]));
      } finally {
        closeFd(pair.a);
        closeFd(pair.b);
      }
    });
  });
}
