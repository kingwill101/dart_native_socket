import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:native_socket/native_socket.dart';

final _libc = ffi.DynamicLibrary.open('libc.so.6');
final _close =
    _libc
        .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
          'close',
        );
final _open = _libc.lookupFunction<
  ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32),
  int Function(ffi.Pointer<Utf8>, int)
>('open');

/// Opens /dev/null through libc for fd-passing probes.
int _openProbeFd() {
  final path = '/dev/null'.toNativeUtf8();
  try {
    final fd = _open(path, 0);
    expect(fd, greaterThanOrEqualTo(0));
    return fd;
  } finally {
    calloc.free(path);
  }
}

void main() {
  group('receiveMessage (SCM_RIGHTS)', () {
    test('round-trips bytes with an attached fd', () {
      final (a, b) = UnixSocket.pair();
      try {
        final probe = _openProbeFd();
        try {
          final sent = a.send(
            Uint8List.fromList([1, 2, 3, 4]),
            fd: probe,
          );
          expect(sent, 4);
          final msg = b.receiveMessage();
          expect(msg.bytes, [1, 2, 3, 4]);
          expect(msg.fds, hasLength(1));
          // SCM_RIGHTS duplicates the descriptor: a successful transfer
          // yields a fresh, distinct number.
          expect(msg.fds.single, greaterThanOrEqualTo(0));
          expect(msg.fds.single, isNot(equals(probe)));
          _close(msg.fds.single);
        } finally {
          _close(probe);
        }
      } finally {
        a.close();
        b.close();
      }
    });

    test('plain messages yield no fds', () {
      final (a, b) = UnixSocket.pair();
      try {
        a.send(Uint8List.fromList([9, 9]));
        final msg = b.receiveMessage();
        expect(msg.bytes, [9, 9]);
        expect(msg.fds, isEmpty);
      } finally {
        a.close();
        b.close();
      }
    });
  });
}
