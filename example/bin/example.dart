import 'dart:io';
import 'dart:typed_data';

import 'package:native_socket/native_socket.dart';

/// Demonstrates the native_socket package APIs.
///
/// Run with: `dart run example/bin/example.dart`
void main() async {
  await demoPair();
  await demoBindConnectAccept();
  await demoDatagram();
  await demonativeBuffer();
  await demoUnlink();

  print('\nAll demos completed successfully!');
}

// ---------------------------------------------------------------------------
// Demo 1: Socket pair (intra-process communication)
// ---------------------------------------------------------------------------
Future<void> demoPair() async {
  print('=== Demo: UnixSocket.pair() ===');

  final (a, b) = UnixSocket.pair();
  try {
    a.send(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]));
    final data = b.receive(1024);
    print('  Sent:    [0xDE, 0xAD, 0xBE, 0xEF]');
    print('  Received: $data');
  } finally {
    a.close();
    b.close();
  }
}

// ---------------------------------------------------------------------------
// Demo 2: Bind / connect / accept (client-server)
// ---------------------------------------------------------------------------
Future<void> demoBindConnectAccept() async {
  print('\n=== Demo: UnixSocket.bind/connect/accept ===');

  final tmpDir = Directory.systemTemp.path;
  final path = '$tmpDir/native_socket_demo_${DateTime.now().microsecondsSinceEpoch}.sock';

  final server = UnixSocket.bind(Address.file(path));
  try {
    print('  Server bound to: $path');

    // Connect a client to the server
    final client = UnixSocket.connect(Address.file(path));
    try {
      client.send(Uint8List.fromList([0x41, 0x42])); // 'AB'

      final conn = server.accept();
      try {
        final data = conn.receive(1024);
        print('  Server received: $data');

        // Echo back
        conn.send(data);
        final echo = client.receive(1024);
        print('  Client echoed:   $echo');
      } finally {
        conn.close();
      }
    } finally {
      client.close();
    }
  } finally {
    server.closeAndUnlink();
  }
}

// ---------------------------------------------------------------------------
// Demo 3: Datagram sockets (message boundaries preserved)
// ---------------------------------------------------------------------------
Future<void> demoDatagram() async {
  print('\n=== Demo: Datagram Sockets ===');

  final tmpDir = Directory.systemTemp.path;
  final path = '$tmpDir/native_socket_dgram_demo_${DateTime.now().microsecondsSinceEpoch}.sock';

  final server = UnixSocket.bind(Address.file(path), type: SocketType.datagram);
  try {
    final client = UnixSocket.create(type: SocketType.datagram);
    try {
      // Send two separate datagrams
      client.sendTo(Address.file(path), Uint8List.fromList([0x01]));
      client.sendTo(Address.file(path), Uint8List.fromList([0x02, 0x03, 0x04]));
      sleep(const Duration(milliseconds: 50));

      // Each recvFrom returns exactly one datagram
      final first = server.receiveFrom(1024);
      print('  Datagram 1: $first (1 byte, as sent)');

      final second = server.receiveFrom(1024);
      print('  Datagram 2: $second (3 bytes, as sent)');
    } finally {
      client.close();
    }
  } finally {
    server.closeAndUnlink();
  }
}

// ---------------------------------------------------------------------------
// Demo 4: NativeBuffer (zero-copy I/O)
// ---------------------------------------------------------------------------
Future<void> demonativeBuffer() async {
  print('\n=== Demo: NativeBuffer ===');

  // Heap-backed buffer
  final heapBuf = NativeBuffer.fromList(Uint8List.fromList([10, 20, 30, 40, 50]));
  print('  Heap buffer:  ${heapBuf.asTypedList()}');

  // Native (off-heap) buffer
  final nativeBuf = NativeBuffer.allocate(8);
  nativeBuf.asTypedList()[0] = 0xFF;
  nativeBuf.asTypedList()[1] = 0xFE;
  print('  Native buffer: ${nativeBuf.asTypedList().take(2).toList()} ... (${nativeBuf.length} bytes)');
  nativeBuf.free();

  // Slice (zero-copy view, shares underlying memory)
  final sliced = heapBuf.slice(1, 3);
  print('  Slice [1..3]:  ${sliced.asTypedList()}');
}

// ---------------------------------------------------------------------------
// Demo 5: unlink / closeAndUnlink
// ---------------------------------------------------------------------------
Future<void> demoUnlink() async {
  print('\n=== Demo: Socket path cleanup ===');

  final tmpDir = Directory.systemTemp.path;
  final path = '$tmpDir/native_socket_cleanup_demo_${DateTime.now().microsecondsSinceEpoch}.sock';

  final sock = UnixSocket.bind(Address.file(path));
  print('  Socket file exists: ${File(path).existsSync()}');

  sock.closeAndUnlink();
  print('  After closeAndUnlink: ${File(path).existsSync()}');
}
