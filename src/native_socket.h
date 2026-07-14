#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>

// ---------------------------------------------------------------------------
// File / anonymous memory
// ---------------------------------------------------------------------------

int create_tmpfile_cloexec(char *tmpname);
int os_create_anonymous_file(off_t size);
ssize_t write_to_fd(int fd, const unsigned char *buffer, size_t count);

// ---------------------------------------------------------------------------
// Socket types
// ---------------------------------------------------------------------------

/// Create a socket of the given type (SOCK_STREAM or SOCK_DGRAM).
/// Returns fd on success, -1 on error. Socket is set NONBLOCK | CLOEXEC.
int create_socket(int type);

/// Bind a socket to a filesystem path.
int bind_socket(int socket, const char *path);

/// Bind a socket to an abstract namespace address.
/// The abstract name does NOT include the leading null byte (it's added by this function).
int bind_socket_abstract(int socket, const char *name);

/// Listen for incoming connections (stream sockets only).
int listen_socket(int socket, int backlog);

/// Accept an incoming connection. Returns new fd on success, -1 on error.
int accept_socket(int socket);

void close_socket(int socket);

/// Unlink a socket path from the filesystem.
int unlink_socket_path(const char *path);

// ---------------------------------------------------------------------------
// Socket options
// ---------------------------------------------------------------------------

int get_socket_option(int socket, int level, int optname, int *value);
int set_socket_option(int socket, int level, int optname, int value);

// Convenience wrappers for common socket options
int set_so_sndbuf(int socket, int size);
int get_so_sndbuf(int socket);
int set_so_rcvbuf(int socket, int size);
int get_so_rcvbuf(int socket);
int set_so_linger(int socket, int on_off, int linger_secs);

// ---------------------------------------------------------------------------
// Connection (client)
// ---------------------------------------------------------------------------

int create_unix_socket(const char *path);

/// Connect a socket to a filesystem path.
int connect_unix_socket(int socket, const char *path);

int create_socketpair(int sv[2]);

/// Connect a socket to an abstract namespace address.
int connect_unix_socket_abstract(int socket, const char *name);

// ---------------------------------------------------------------------------
// Datagram (sendto / recvfrom)
// ---------------------------------------------------------------------------

/// Send data to a specific address on a datagram socket.
/// Returns bytes sent or -1 on error.
ssize_t send_to(int socket, const char *path, const void *data, size_t data_len);

/// Send data to an abstract address on a datagram socket.
ssize_t send_to_abstract(int socket, const char *name, const void *data, size_t data_len);

/// Receive data from a datagram socket. Returns bytes received or -1.
/// The sender address is NOT returned (lower-level).
ssize_t recv_from(int socket, void *buffer, size_t length);

// ---------------------------------------------------------------------------
// Data send/recv (stream)
// ---------------------------------------------------------------------------

ssize_t send_bytes(int socket, const void *buffer, size_t length);
ssize_t send_bytes_with_fd(int socket, int fd, const void *data, size_t data_len);
ssize_t recv_bytes(int socket, void *buffer, size_t length);

// ---------------------------------------------------------------------------
// SCM_RIGHTS helpers
// ---------------------------------------------------------------------------

int recv_fd(int socket);
void *unix_rights(int *fds, int num_fds, unsigned char *buf, size_t buflen);
int parse_unix_rights(struct cmsghdr *cm, int *fds, int max_fds);
size_t c_msg_len(size_t datalen);
size_t c_msg_space(size_t datalen);

// ---------------------------------------------------------------------------
// Socket polling
// ---------------------------------------------------------------------------

int socket_has_data(int socket, int timeout);
