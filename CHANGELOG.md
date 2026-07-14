
## 0.4.0-wip

- **New high-level Dart API**: `UnixSocket` class with `connect()`, `bind()`, `accept()`,
  `pair()`, `send()`, `receive()`, `sendTo()`, `receiveFrom()`, `split()`
- **Address types**: `Address.file()` and `Address.abstract()` for filesystem-path
  and abstract namespace addressing
- **SocketType enum**: `SocketType.stream` (connection-oriented) and
  `SocketType.datagram` (message-boundary-preserving)
- **NativeBuffer**: heap-backed and native (off-heap) buffers with zero-copy
  slicing — inspired by Java NIO `ByteBuffer` and Netty `ByteBuf`
- **Server sockets**: full bind/listen/accept workflow
- **SCM_RIGHTS fd passing**: `send()` with `fd:` argument and `receiveFd()`
- **Socket options**: `setSendBufferSize`, `getSendBufferSize`, `setReceiveBufferSize`,
  `getReceiveBufferSize`, `setLinger`
- **Split halves**: `SocketReader` / `SocketWriter` for concurrent I/O
- **Path cleanup**: `unlink()` and `closeAndUnlink()` for Unix socket files
- **Expanded C API**: `create_socket`, `bind_socket`, `bind_socket_abstract`,
  `listen_socket`, `accept_socket`, `connect_unix_socket`,
  `connect_unix_socket_abstract`, `send_to`, `send_to_abstract`, `recv_from`,
  `set_so_sndbuf`/`rcvbuf`/`linger`, `get_so_sndbuf`/`rcvbuf`,
  `unlink_socket_path`, `socket_has_data`
- Migrate to `package:hooks` 2.0.0, `package:code_assets` 1.0.0+,
  `package:native_toolchain_c` 0.19.0+
- Programmatic `package:ffigen` config (`tool/generate_bindings.dart`)
  replaces YAML `ffigen:` block in `pubspec.yaml`
- **55 tests** covering all new APIs
- Fix: `recv_bytes` return type corrected to `ssize_t`
- Fix: `receive()` no longer returns view into freed calloc memory (use-after-free)
- Fix: `pair()` uses correct pointer width (`Int` not `IntPtr`) on 64-bit
- Fix: EAGAIN retry loop in `receive()` and `receiveFrom()`
- Remove dead `lib/src/socket.dart` (old UnixSocket class)

## 0.3.0

- Initial hooks support

## 0.2.0

- Add support for checking if sockets have data available


## 0.1.0

- Initial version.
