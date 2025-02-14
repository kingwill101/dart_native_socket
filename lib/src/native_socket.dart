// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by `package:ffigen`.
// ignore_for_file: type=lint
import 'dart:ffi' as ffi;

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Char>)>()
external int create_tmpfile_cloexec(
  ffi.Pointer<ffi.Char> tmpname,
);

@ffi.Native<ffi.Int Function(off_t)>()
external int os_create_anonymous_file(
  int size,
);

@ffi.Native<
    ffi.Int Function(ffi.Int, ffi.Pointer<ffi.UnsignedChar>, ffi.Size)>()
external int write_to_fd(
  int fd,
  ffi.Pointer<ffi.UnsignedChar> buffer,
  int count,
);

@ffi.Native<ffi.Int Function(ffi.Int, ffi.Int)>()
external int socket_has_data(
  int socket,
  int timeout,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Char>)>()
external int create_unix_socket(
  ffi.Pointer<ffi.Char> path,
);

@ffi.Native<ffi.Void Function(ffi.Int)>()
external void close_socket(
  int socket,
);

@ffi.Native<ffi.Size Function(ffi.Size)>()
external int c_msg_len(
  int datalen,
);

@ffi.Native<ffi.Size Function(ffi.Size)>()
external int c_msg_space(
  int datalen,
);

@ffi.Native<ssize_t Function(ffi.Int, ffi.Pointer<ffi.Void>, ffi.Size)>()
external int send_bytes(
  int socket,
  ffi.Pointer<ffi.Void> buffer,
  int length,
);

@ffi.Native<
    ssize_t Function(ffi.Int, ffi.Int, ffi.Pointer<ffi.Void>, ffi.Size)>()
external int send_bytes_with_fd(
  int socket,
  int fd,
  ffi.Pointer<ffi.Void> data,
  int data_len,
);

@ffi.Native<ssize_t Function(ffi.Int, ffi.Pointer<ffi.Void>, ffi.Size)>()
external int recv_bytes(
  int socket,
  ffi.Pointer<ffi.Void> buffer,
  int length,
);

typedef off_t = __off_t;
typedef __off_t = ffi.Long;
typedef Dart__off_t = int;
typedef ssize_t = __ssize_t;
typedef __ssize_t = ffi.Long;
typedef Dart__ssize_t = int;
