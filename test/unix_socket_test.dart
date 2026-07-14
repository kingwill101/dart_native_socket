import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:native_socket/native_socket.dart';
import 'package:native_socket/src/native_socket.dart' as ns;
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Address
  // ---------------------------------------------------------------------------
  group('Address', () {
    test('creates a filesystem address', () {
      final addr = Address.file('/tmp/test.sock');
      expect(addr.path, equals('/tmp/test.sock'));
      expect(addr.isAbstract, isFalse);
    });

    test('creates an abstract namespace address', () {
      final addr = Address.abstract('myservice');
      expect(addr.path, equals('myservice'));
      expect(addr.isAbstract, isTrue);
    });

    test('throws on too-long path', () {
      final longPath = '/' * 200;
      expect(
        () => Address.file(longPath),
        throwsArgumentError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // NativeBuffer
  // ---------------------------------------------------------------------------
  group('NativeBuffer', () {
    test('fromList creates heap-backed buffer', () {
      final buf = NativeBuffer.fromList(Uint8List.fromList([1, 2, 3]));
      expect(buf.length, equals(3));
      expect(buf.isNative, isFalse);
      expect(buf.asTypedList(), equals([1, 2, 3]));
    });

    test('allocate creates native buffer', () {
      final buf = NativeBuffer.allocate(1024);
      expect(buf.length, equals(1024));
      expect(buf.isNative, isTrue);
      buf.free();
    });

    test('slice returns correct sub-range', () {
      final buf = NativeBuffer.fromList(Uint8List.fromList([1, 2, 3, 4, 5]));
      final sliced = buf.slice(1, 3);
      expect(sliced.length, equals(3));
      expect(sliced.asTypedList(), equals([2, 3, 4]));
    });

    test('duplicate creates an equal-length view', () {
      final buf = NativeBuffer.fromList(Uint8List.fromList([10, 20, 30]));
      final dup = buf.duplicate();
      expect(dup.length, equals(3));
      expect(dup.asTypedList(), equals([10, 20, 30]));
    });

    test('native buffer can be used for FFI', () {
      final buf = NativeBuffer.allocate(8);
      // Write to the underlying memory via typed list
      final view = buf.asTypedList();
      view[0] = 0xAB;
      view[1] = 0xCD;
      // The nativePointer should point to the same data
      final ptr = buf.nativePointer.cast<Uint8>();
      expect(ptr.asTypedList(2)[0], equals(0xAB));
      expect(ptr.asTypedList(2)[1], equals(0xCD));
      buf.free();
    });
  });

  // ---------------------------------------------------------------------------
  // UnixSocket - pair
  // ---------------------------------------------------------------------------
  group('UnixSocket.pair()', () {
    test('creates a pair of connected sockets', () {
      final (a, b) = UnixSocket.pair();
      try {
        expect(a.fd, greaterThanOrEqualTo(0));
        expect(b.fd, greaterThanOrEqualTo(0));
        expect(a.fd, isNot(b.fd));
        expect(a.boundAddress, isNull);
        expect(b.boundAddress, isNull);
      } finally {
        a.close();
        b.close();
      }
    });

    test('can send and receive data between the pair', () {
      final (a, b) = UnixSocket.pair();
      try {
        a.send(Uint8List.fromList([0x10, 0x20, 0x30]));
        sleep(const Duration(milliseconds: 100));
        final data = b.receive(1024);
        expect(data, equals([0x10, 0x20, 0x30]));
      } finally {
        a.close();
        b.close();
      }
    });

    test('both sockets have no data initially', () {
      final (a, b) = UnixSocket.pair();
      try {
        expect(a.hasData, isFalse);
        expect(b.hasData, isFalse);
      } finally {
        a.close();
        b.close();
      }
    });

    test('sendBuffer works with native buffer', () {
      final (a, b) = UnixSocket.pair();
      try {
        final buf = NativeBuffer.fromList(Uint8List.fromList([0xDE, 0xAD]));
        a.sendBuffer(buf);
        sleep(const Duration(milliseconds: 100));
        final data = b.receive(1024);
        expect(data, equals([0xDE, 0xAD]));
      } finally {
        a.close();
        b.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // UnixSocket - connect / bind / accept
  // ---------------------------------------------------------------------------
  group('UnixSocket connect/bind/accept', () {
    final tmpDir = Directory.systemTemp.path;
    var counter = 0;

    String uniquePath() {
      counter++;
      return '$tmpDir/nss_test_bs_${DateTime.now().microsecondsSinceEpoch}_$counter.sock';
    }

    test('server bound to address', () {
      final path = uniquePath();
      final server = UnixSocket.bind(Address.file(path));
      try {
        expect(server.boundAddress, isNotNull);
        expect(server.boundAddress!.path, equals(path));
        expect(server.boundAddress!.isAbstract, isFalse);
      } finally {
        server.closeAndUnlink();
      }
    });

    test('client can connect and exchange data', () {
      final path = uniquePath();
      final server = UnixSocket.bind(Address.file(path));
      try {
        final client = UnixSocket.connect(Address.file(path));
        try {
          sleep(const Duration(milliseconds: 30));
          client.send(Uint8List.fromList([0x01, 0x02]));

          final conn = server.accept();
          try {
            final data = conn.receive(1024);
            expect(data, equals([0x01, 0x02]));

            conn.send(Uint8List.fromList([0x03]));
            final response = client.receive(1024);
            expect(response, equals([0x03]));
          } finally {
            conn.close();
          }
        } finally {
          client.close();
        }
      } finally {
        server.closeAndUnlink();
      }
    });

    test('waitForData returns true after data sent', () {
      final path = uniquePath();
      final server = UnixSocket.bind(Address.file(path));
      try {
        final client = UnixSocket.connect(Address.file(path));
        try {
          sleep(const Duration(milliseconds: 30));
          client.send(Uint8List.fromList([0x42]));

          final conn = server.accept();
          try {
            expect(conn.waitForData(500), isTrue);
            final data = conn.receive(1024);
            expect(data, equals([0x42]));
          } finally {
            conn.close();
          }
        } finally {
          client.close();
        }
      } finally {
        server.closeAndUnlink();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Abstract namespace (Linux only)
  // ---------------------------------------------------------------------------
  group('abstract namespace', () {
    test('bind and connect via abstract address', () {
      final name = 'nss_test_${DateTime.now().microsecondsSinceEpoch}';
      final addr = Address.abstract(name);

      final server = UnixSocket.bind(addr);
      try {
        expect(server.boundAddress, isNotNull);
        expect(server.boundAddress!.isAbstract, isTrue);

        final client = UnixSocket.connect(addr);
        try {
          client.send(Uint8List.fromList([0xAB]));
          sleep(const Duration(milliseconds: 100));

          final conn = server.accept();
          try {
            sleep(const Duration(milliseconds: 50));
            final data = conn.receive(1024);
            expect(data, equals([0xAB]));
          } finally {
            conn.close();
          }
        } finally {
          client.close();
        }
      } finally {
        // Abstract sockets don't use filesystem paths, no unlink needed
        server.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Socket options
  // ---------------------------------------------------------------------------
  group('socket options', () {
    test('get/set send buffer size', () {
      final (a, _) = UnixSocket.pair();
      try {
        final original = a.getSendBufferSize();
        expect(original, greaterThan(0));

        // Linux doubles the value you set, so test a target range
        a.setSendBufferSize(16384);
        sleep(const Duration(milliseconds: 10));
        final newVal = a.getSendBufferSize();
        // Should be >= 16384 (kernel may round up and double)
        expect(newVal, greaterThanOrEqualTo(16384));
      } finally {
        a.close();
      }
    });

    test('get/set receive buffer size', () {
      final (a, _) = UnixSocket.pair();
      try {
        final original = a.getReceiveBufferSize();
        expect(original, greaterThan(0));

        a.setReceiveBufferSize(16384);
        sleep(const Duration(milliseconds: 10));
        final newVal = a.getReceiveBufferSize();
        expect(newVal, greaterThanOrEqualTo(16384));
      } finally {
        a.close();
      }
    });

    test('set linger option', () {
      final (a, _) = UnixSocket.pair();
      try {
        // Should not throw
        a.setLinger(true, 5);
        a.setLinger(false, 0);
      } finally {
        a.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // SCM_RIGHTS file descriptor passing
  // ---------------------------------------------------------------------------
  group('SCM_RIGHTS fd passing', () {
    test('send and receive a file descriptor', () {
      final xdgDir = Platform.environment['XDG_RUNTIME_DIR'];
      if (xdgDir == null || xdgDir.isEmpty) {
        markTestSkipped('XDG_RUNTIME_DIR is not set');
        return;
      }

      final (a, b) = UnixSocket.pair();
      try {
        // Create a fd to pass using os_create_anonymous_file
        final passedFd = ns.os_create_anonymous_file(4096);
        expect(passedFd, greaterThanOrEqualTo(0));

        // Send the fd via SCM_RIGHTS (data + fd in one sendmsg call)
        a.send(Uint8List.fromList([0xFF]), fd: passedFd);
        sleep(const Duration(milliseconds: 100));

        // receiveFd calls recvmsg() which reads both 1 data byte + the fd.
        // Do NOT call receive() first — that would consume the message
        // and leave no ancillary data for receiveFd().
        final receivedFd = b.receiveFd();
        expect(receivedFd, greaterThanOrEqualTo(0));
        expect(receivedFd, isNot(passedFd));

        ns.close_socket(receivedFd);
        ns.close_socket(passedFd);
      } finally {
        a.close();
        b.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Split
  // ---------------------------------------------------------------------------
  group('split', () {
    test('split returns reader and writer', () {
      final (a, b) = UnixSocket.pair();
      try {
        final (reader, writer) = a.split();
        expect(reader, isA<SocketReader>());
        expect(writer, isA<SocketWriter>());

        // Write from separate writer
        writer.send(Uint8List.fromList([0x11]));
        sleep(const Duration(milliseconds: 100));

        // Read on the other side using raw socket
        final data = b.receive(1024);
        expect(data, equals([0x11]));

        (reader, writer); // suppress unused warning
      } finally {
        a.close();
        b.close();
      }
    });

    test('reader and writer on same socket for concurrent I/O', () {
      final (a, b) = UnixSocket.pair();
      try {
        final (reader, writer) = a.split();

        // Use writer to send, b to send back
        writer.send(Uint8List.fromList([0xAA]));
        sleep(const Duration(milliseconds: 100));

        final dataOnB = b.receive(1024);
        expect(dataOnB, equals([0xAA]));

        // Respond from b
        b.send(Uint8List.fromList([0xBB]));
        sleep(const Duration(milliseconds: 100));

        // Read on reader
        final dataOnReader = reader.receive(1024);
        expect(dataOnReader, equals([0xBB]));
      } finally {
        a.close();
        b.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Datagram
  // ---------------------------------------------------------------------------
  group('datagram socket', () {
    final tmpDir = Directory.systemTemp.path;

    test('sendTo and receiveFrom with datagram sockets', () {
      final serverPath = '$tmpDir/nss_test_dgram_${DateTime.now().microsecondsSinceEpoch}';

      final server = UnixSocket.bind(
        Address.file(serverPath),
        type: SocketType.datagram,
      );
      try {
        final client = UnixSocket.create(type: SocketType.datagram);
        try {
          // Send datagram to server
          client.sendTo(Address.file(serverPath), Uint8List.fromList([0x41, 0x42]));
          sleep(const Duration(milliseconds: 100));

          // Receive on server
          final data = server.receiveFrom(1024);
          expect(data, equals([0x41, 0x42]));
        } finally {
          client.close();
        }
      } finally {
        server.closeAndUnlink();
      }
    });

    test('datagram sendTo preserves message boundaries', () {
      final serverPath = '$tmpDir/nss_test_dgram2_${DateTime.now().microsecondsSinceEpoch}';

      final server = UnixSocket.bind(
        Address.file(serverPath),
        type: SocketType.datagram,
      );
      try {
        final client = UnixSocket.create(type: SocketType.datagram);
        try {
          // Send two separate datagrams
          client.sendTo(Address.file(serverPath), Uint8List.fromList([0x01]));
          client.sendTo(Address.file(serverPath), Uint8List.fromList([0x02, 0x03]));
          sleep(const Duration(milliseconds: 100));

          // Each recvFrom should return exactly one datagram
          final first = server.receiveFrom(1024);
          expect(first, equals([0x01]));

          final second = server.receiveFrom(1024);
          expect(second, equals([0x02, 0x03]));
        } finally {
          client.close();
        }
      } finally {
        server.closeAndUnlink();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Error paths
  // ---------------------------------------------------------------------------
  group('error paths', () {
    test('connect to non-existent path throws', () {
      expect(
        () => UnixSocket.connect(Address.file('/tmp/nonexistent_socket_xyz')),
        throwsA(isA<Exception>()),
      );
    });

    test('accept on unbound socket throws', () {
      final sock = UnixSocket.create();
      try {
        expect(
          () => sock.accept(),
          throwsA(isA<Exception>()),
        );
      } finally {
        sock.close();
      }
    });

    test('receive on closed socket returns empty data', () {
      final (a, b) = UnixSocket.pair();
      a.close();
      final data = b.receive(1024);
      expect(data, isEmpty);
      b.close();
    });

    test('closeAndUnlink removes the socket file', () {
      final tmpDir = Directory.systemTemp.path;
      final path = '$tmpDir/nss_test_cleanup_${DateTime.now().microsecondsSinceEpoch}.sock';

      final sock = UnixSocket.bind(Address.file(path));
      expect(File(path).existsSync(), isTrue);

      sock.closeAndUnlink();
      expect(File(path).existsSync(), isFalse);
    });

    test('unlink before close cleans up path', () {
      final tmpDir = Directory.systemTemp.path;
      final path = '$tmpDir/nss_test_unlink_${DateTime.now().microsecondsSinceEpoch}.sock';

      final sock = UnixSocket.bind(Address.file(path));
      sock.unlink();
      expect(File(path).existsSync(), isFalse);
      sock.close();
    });
  });

  // ---------------------------------------------------------------------------
  // Stream vs Datagram mode enforcement
  // ---------------------------------------------------------------------------
  group('stream vs datagram mode', () {
    test('send throws on datagram socket', () {
      final (a, b) = UnixSocket.pair();
      try {
        // socketpair creates stream sockets — datagram can't pair
        // Instead create a datagram socket and verify send() can't be used
        final sock = UnixSocket.create(type: SocketType.datagram);
        expect(
          () => sock.send(Uint8List.fromList([0x01])),
          throwsA(isA<Exception>()),
        );
        sock.close();
      } finally {
        a.close();
        b.close();
      }
    });

    test('datagram socket preserves message boundaries across multiple sends', () {
      final tmpDir = Directory.systemTemp.path;
      final serverPath = '$tmpDir/nss_dgram_boundary_${DateTime.now().microsecondsSinceEpoch}.sock';

      final server = UnixSocket.bind(
        Address.file(serverPath),
        type: SocketType.datagram,
      );
      try {
        final client = UnixSocket.create(type: SocketType.datagram);
        try {
          // Send 3 datagrams of different sizes
          client.sendTo(Address.file(serverPath), Uint8List.fromList([0x01]));
          client.sendTo(Address.file(serverPath), Uint8List.fromList([0x02, 0x03]));
          client.sendTo(Address.file(serverPath), Uint8List.fromList([0x04, 0x05, 0x06]));
          sleep(const Duration(milliseconds: 100));

          // Each receiveFrom returns exactly the bytes from one sendTo
          expect(server.receiveFrom(1024), equals([0x01]));
          expect(server.receiveFrom(1024), equals([0x02, 0x03]));
          expect(server.receiveFrom(1024), equals([0x04, 0x05, 0x06]));
        } finally {
          client.close();
        }
      } finally {
        server.closeAndUnlink();
      }
    });

    test('stream socket does not preserve message boundaries', () {
      // With a stream socket, two sends can merge into one receive
      final (a, b) = UnixSocket.pair();
      try {
        a.send(Uint8List.fromList([0x01]));
        a.send(Uint8List.fromList([0x02, 0x03]));
        sleep(const Duration(milliseconds: 100));

        // Stream may merge — the receive returns at least the first byte
        final data = b.receive(1024);
        expect(data.length, greaterThanOrEqualTo(1));
        expect(data[0], equals(0x01));
      } finally {
        a.close();
        b.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // SocketType enum
  // ---------------------------------------------------------------------------
  group('SocketType', () {
    test('stream is value 0', () {
      expect(SocketType.stream.index, equals(0));
    });

    test('datagram is value 1', () {
      expect(SocketType.datagram.index, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // CloseFd helper (re-exported compat)
  // ---------------------------------------------------------------------------
  group('closeFd compatibility', () {
    test('closeFd can close a socket from fd_utilities', () {
      final (a, b) = UnixSocket.pair();
      expect(a.fd, greaterThanOrEqualTo(0));
      expect(b.fd, greaterThanOrEqualTo(0));
      // Using the old closeFd from fd_utilities
      ns.close_socket(a.fd);
      ns.close_socket(b.fd);
    });
  });
}
