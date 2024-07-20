#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>

static int create_tmpfile_cloexec(char *tmpname);
int os_create_anonymous_file(off_t size);

int write_to_fd(int fd, const unsigned char *buffer, size_t count);

int create_unix_socket(const char *path);
void close_socket(int socket);

static size_t c_msg_len(size_t datalen);
static size_t c_msg_space(size_t datalen);

ssize_t send_bytes(int socket, const void *buffer, size_t length);
ssize_t send_bytes_with_fd(int socket, int fd, const void *data, size_t data_len);

ssize_t recv_bytes(int socket, void *buffer, size_t length);
