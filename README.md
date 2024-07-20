# Native Socket 

The Native Socket Package provides low-level socket and file descriptor operations for Dart applications. It offers functionality not available in Dart's built-in Socket class, allowing direct interaction with file descriptors and Unix domain sockets.

## Features

- Create and manage Unix domain sockets
- Perform file descriptor operations
- Send and receive data with attached file descriptors
- Create anonymous files and temporary files
- Non-blocking socket operations

## Installation

To use this package, add `native_socket` as a dependency in your `pubspec.yaml` file:

> **NOTE:** Currently we are unable to publish packages that depend on hooks/build for native dependencies [see issue](https://github.com/dart-lang/pub-dev/pull/7847)


```yaml
dependencies:
  native_socket: 
      git: 
        url: https://github.com/kingwill101/dart_native_socket
```
## Prerequisites
To use this package you need to enable the experimental `native-assets` feature

```
dart --enable-experiment=native-assets run
```

## Usage


Creating a Unix Socket

```dart
import 'package:native_socket/native_socket.dart';

void main() {
  final socket = UnixSocket('/path/to/socket');
  // Use the socket...
  socket.close();
}

```
Sending and receiving data

```dart
import 'dart:typed_data';
import 'package:native_socket/native_socket.dart';

void main() {
  final socket = UnixSocket('/path/to/socket');
  
  // Sending data
  final dataToSend = Uint8List.fromList([1, 2, 3, 4, 5]);
  socket.send(dataToSend);
  
  // Receiving data
  final receivedData = socket.receive();
  print('Received: $receivedData');
  
  socket.close();
}
```

Check if socket has data available

```dart
final socket = UnixSocket('/run/user/1000/wayland-1');
  socket.send(Uint8List.fromList([1, 2, 3]));

  if (socket.hasData()) {
    final data = socket.receive();
    print(data);
  }

  socket.close();
```

Working with File Descriptors


```dart
import 'package:native_socket/native_socket.dart';

void main() {
  // Create an anonymous file
  final fd = createAnonymousFile(1024);
  
  // Write to the file descriptor
  final dataToWrite = Uint8List.fromList([65, 66, 67, 68]); // "ABCD"
  writeToFd(fd, dataToWrite);
  
  // Close the file descriptor
  closeFd(fd);
}
```


## Contributing

Contributions to the Native Socket Package are welcome! Please submit pull requests or open issues on the GitHub repository.
