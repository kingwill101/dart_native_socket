import 'dart:typed_data';

import 'package:native_socket/native_socket.dart';

void main(List<String> arguments) {
  final socket = UnixSocket('/run/user/1000/wayland-1');
  socket.send(Uint8List.fromList([1, 2, 3]));
  final data = socket.receive();
  print(data);
  socket.close();
}
