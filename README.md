# Native Socket

Low-level Unix domain socket operations with a high-level Dart API.

Provides stream and datagram Unix domain sockets, filesystem-path and abstract
namespace addressing, SCM_RIGHTS file descriptor passing, server sockets,
native (off-heap) buffers, concurrent read/write via split halves, and
prebuilt release assets for Linux.

## Features

- **Stream sockets** (`SOCK_STREAM`) — connection-oriented, ordered, reliable
- **Datagram sockets** (`SOCK_DGRAM`) — connectionless, message boundaries preserved
- **Address types** — `Address.file()` for filesystem paths, `Address.abstract()` for Linux abstract namespace
- **Client-server** — `bind()`, `listen()`, `accept()`, `connect()`
- **File descriptor passing** — send and receive fds via SCM_RIGHTS
- **Socket pair** — `UnixSocket.pair()` for intra-process communication
- **Native buffers** — heap-backed and off-heap buffers with zero-copy slicing
- **Concurrent I/O** — `split()` into `SocketReader` / `SocketWriter` halves
- **Socket options** — `SO_SNDBUF`, `SO_RCVBUF`, `SO_LINGER`
- **Non-blocking data check** — `hasData` getter, `waitForData(timeout)`
- **Path cleanup** — `unlink()` / `closeAndUnlink()`

## Installation

```yaml
dependencies:
  native_socket: ^0.4.0-wip.3
```

> **Note:** This package uses Dart native assets (hooks/build system).
> Enable the experiment when running:
> ```
> dart --enable-experiment=native-assets run
> ```
>
> Tag releases publish Linux prebuilt assets from GitHub Releases.

## Prerequisites

- Dart SDK `>=3.8.0 <4.0.0`
- Linux (only platform currently supported)
- Clang (for native code compilation via hooks)

## Usage

### Socket pair (intra-process)

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  final (a, b) = UnixSocket.pair();
  a.send(Uint8List.fromList([0xDE, 0xAD]));
  final data = b.receive(1024);
  print(data); // [222, 173]
  a.close();
  b.close();
}
```

### Client-server with bind/connect/accept

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  final server = UnixSocket.bind(Address.file('/tmp/my.sock'));
  final client = UnixSocket.connect(Address.file('/tmp/my.sock'));

  client.send(Uint8List.fromList([0x41, 0x42]));
  final conn = server.accept();
  final data = conn.receive(1024);
  print(data); // [65, 66]

  conn.close();
  client.close();
  server.closeAndUnlink();
}
```

### Datagram sockets (message boundaries preserved)

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  final server = UnixSocket.bind(
    Address.file('/tmp/dgram.sock'),
    type: SocketType.datagram,
  );
  final client = UnixSocket.create(type: SocketType.datagram);

  client.sendTo(Address.file('/tmp/dgram.sock'), Uint8List.fromList([0x01]));
  client.sendTo(Address.file('/tmp/dgram.sock'), Uint8List.fromList([0x02, 0x03]));

  final first = server.receiveFrom(1024);  // [0x01]
  final second = server.receiveFrom(1024); // [0x02, 0x03]

  client.close();
  server.closeAndUnlink();
}
```

### Abstract namespace (Linux only)

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  final addr = Address.abstract('my-service');
  final server = UnixSocket.bind(addr);
  final client = UnixSocket.connect(addr);
  // ... no filesystem path to clean up
  server.close();
  client.close();
}
```

### Native buffers for zero-copy I/O

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  // Heap-backed (convenient)
  final heapBuf = NativeBuffer.fromList(Uint8List.fromList([1, 2, 3]));

  // Native/off-heap (zero-copy for FFI, must free)
  final nativeBuf = NativeBuffer.allocate(1024);
  nativeBuf.asTypedList()[0] = 0xFF;
  // ... use nativeBuf.nativePointer in FFI calls ...
  nativeBuf.free();

  // Zero-copy slice (shares underlying memory)
  final sliced = heapBuf.slice(1, 2); // [2, 3]
}
```

### SCM_RIGHTS file descriptor passing

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  final (a, b) = UnixSocket.pair();
  final fileFd = createAnonymousFile(4096);

  // Send data + fd together
  a.send(Uint8List.fromList([0xFF]), fd: fileFd);

  // Receive fd (recvmsg reads both data byte and fd)
  final receivedFd = b.receiveFd();
  closeFd(receivedFd);
  closeFd(fileFd);
  a.close();
  b.close();
}
```

### Socket options

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  final (a, _) = UnixSocket.pair();
  a.setSendBufferSize(65536);
  print(a.getSendBufferSize()); // kernel may round up
  a.setLinger(true, 5);
  a.close();
}
```

### Split for concurrent read/write

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  final (a, b) = UnixSocket.pair();
  final (reader, writer) = a.split();
  // reader and writer can be used from separate isolates/threads
  writer.send(Uint8List.fromList([0x01]));
  final data = b.receive(1024);
  print(data); // [1]
  a.close();
  b.close();
}
```

## API Reference

See the [full API docs on pub.dev](https://pub.dev/documentation/native_socket/latest/).

## Releases

Tag builds use `native_prebuilt` to generate the release manifest and publish
Linux release assets on GitHub.

## Contributing

Contributions welcome! Please open issues or submit pull requests on
[GitHub](https://github.com/kingwill101/dart_native_socket).
