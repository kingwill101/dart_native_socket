import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// A buffer for I/O operations, supporting both heap-backed and native memory.
///
/// Provides zero-copy slicing and the ability to pin data for FFI operations.
///
/// This is inspired by Java NIO `ByteBuffer` and Netty `ByteBuf` — a two-tier
/// design that allows callers to choose between convenience (heap-backed) and
/// performance (native/pinned memory for zero-copy FFI).
abstract class NativeBuffer {
  /// Creates a heap-backed buffer with the given [data].
  ///
  /// This is the convenient default — good for small payloads and test code.
  factory NativeBuffer.fromList(Uint8List data) = _HeapNativeBuffer;

  /// Creates a native (off-heap) buffer of the given [size].
  ///
  /// Native buffers can be passed directly to FFI calls without a copy step.
  /// They must be freed with [free] when no longer needed.
  factory NativeBuffer.allocate(int size) = _NativeOwnedBuffer;

  /// The number of bytes in this buffer.
  int get length;

  /// Whether the underlying memory is native (off-heap).
  bool get isNative;

  /// A typed view of this buffer (may be a copy or a view depending on isNative).
  Uint8List asTypedList();

  /// A pointer usable for FFI calls.
  ///
  /// For heap-backed buffers, this may require a copy. Use native buffers
  /// for zero-copy FFI.
  ffi.Pointer<ffi.Void> get nativePointer;

  /// Creates a view into a sub-range of this buffer without copying data.
  ///
  /// The returned buffer shares the same underlying memory. Modifications
  /// to one will be visible in the other (like Netty `ByteBuf.slice()`).
  NativeBuffer slice(int start, int length);

  /// Duplicate this buffer sharing the same memory (like `ByteBuf.duplicate()`).
  NativeBuffer duplicate();

  /// Free native memory. No-op for heap-backed buffers.
  void free();
}

/// A heap-backed [NativeBuffer] that wraps a [Uint8List].
class _HeapNativeBuffer implements NativeBuffer {
  final Uint8List _data;
  final int _offset;
  final int _length;

  _HeapNativeBuffer(this._data, [this._offset = 0, int? length])
      : _length = length ?? _data.length;

  @override
  int get length => _length;

  @override
  bool get isNative => false;

  @override
  Uint8List asTypedList() =>
      _data.sublist(_offset, _offset + _length);

  @override
  ffi.Pointer<ffi.Void> get nativePointer {
    // For heap buffers, allocate a native copy
    final ptr = calloc<ffi.Uint8>(_length);
    ptr.asTypedList(_length).setAll(0, _data.sublist(_offset, _offset + _length));
    return ptr.cast();
  }

  @override
  NativeBuffer slice(int start, int length) {
    if (start < 0 || length < 0 || start + length > _length) {
      throw RangeError.range(start, 0, _length - length, 'start');
    }
    return _HeapNativeBuffer(_data, _offset + start, length);
  }

  @override
  NativeBuffer duplicate() =>
      _HeapNativeBuffer(_data, _offset, _length);

  @override
  void free() {
    // No-op for heap buffers
  }
}

/// A native (off-heap) [NativeBuffer] backed by a `calloc` allocation.
class _NativeOwnedBuffer implements NativeBuffer {
  final ffi.Pointer<ffi.Uint8> _pointer;
  final int _length;
  bool _freed = false;

  _NativeOwnedBuffer(int size)
      : _pointer = calloc<ffi.Uint8>(size),
        _length = size;

  @override
  int get length => _length;

  @override
  bool get isNative => true;

  @override
  Uint8List asTypedList() =>
      _pointer.asTypedList(_length);

  @override
  ffi.Pointer<ffi.Void> get nativePointer => _pointer.cast();

  @override
  NativeBuffer slice(int start, int length) {
    if (start < 0 || length < 0 || start + length > _length) {
      throw RangeError.range(start, 0, _length - length, 'start');
    }
    return _NativeViewBuffer(_pointer + start, length, this);
  }

  @override
  NativeBuffer duplicate() =>
      _NativeViewBuffer(_pointer, _length, this);

  @override
  void free() {
    if (!_freed) {
      calloc.free(_pointer);
      _freed = true;
    }
  }
}

/// A view into a native buffer (created by [slice] or [duplicate]).
class _NativeViewBuffer implements NativeBuffer {
  final ffi.Pointer<ffi.Uint8> _pointer;
  final int _length;
  final _NativeOwnedBuffer _owner;
  bool _freed = false;

  _NativeViewBuffer(this._pointer, this._length, this._owner);

  @override
  int get length => _length;

  @override
  bool get isNative => true;

  @override
  Uint8List asTypedList() =>
      _pointer.asTypedList(_length);

  @override
  ffi.Pointer<ffi.Void> get nativePointer => _pointer.cast();

  @override
  NativeBuffer slice(int start, int length) {
    if (start < 0 || length < 0 || start + length > _length) {
      throw RangeError.range(start, 0, _length - length, 'start');
    }
    return _NativeViewBuffer(_pointer + start, length, _owner);
  }

  @override
  NativeBuffer duplicate() =>
      _NativeViewBuffer(_pointer, _length, _owner);

  @override
  void free() {
    if (!_freed) {
      _owner.free();
      _freed = true;
    }
  }
}
