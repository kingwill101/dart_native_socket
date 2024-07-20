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

```yaml
dependencies:
  native_socket: ^0.1.1
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