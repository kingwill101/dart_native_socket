#define _GNU_SOURCE
#include "native_socket.h"
#include <sys/select.h>
#include <unistd.h>
#include <errno.h>

// ---------------------------------------------------------------------------
// Internal helpers (defined first to avoid forward-declaration issues)
// ---------------------------------------------------------------------------

static int set_cloexec_or_close(int fd)
{
    long flags;

    if (fd == -1)
        return -1;

    flags = fcntl(fd, F_GETFD);
    if (flags == -1)
        goto err;

    if (fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == -1)
        goto err;

    return fd;

err:
    close(fd);
    return -1;
}

int create_tmpfile_cloexec(char *tmpname)
{
    int fd;

#ifdef HAVE_MKOSTEMP
    fd = mkostemp(tmpname, O_CLOEXEC);
    if (fd >= 0)
        unlink(tmpname);
#else
    fd = mkstemp(tmpname);
    if (fd >= 0)
    {
        fd = set_cloexec_or_close(fd);
        unlink(tmpname);
    }
    else
    {
        printf("mkstemp error: %s\n", strerror(errno));
    }
#endif

    return fd;
}

size_t c_msg_len(size_t datalen)
{
    return CMSG_LEN(datalen);
}

size_t c_msg_space(size_t datalen)
{
    return CMSG_SPACE(datalen);
}

// ---------------------------------------------------------------------------
// SCM_RIGHTS helpers
// ---------------------------------------------------------------------------

/// Receive a single file descriptor from a Unix socket via SCM_RIGHTS.
int recv_fd(int socket)
{
    struct msghdr msg = {0};
    char m_buffer[256];
    struct iovec io = {.iov_base = m_buffer, .iov_len = sizeof(m_buffer)};

    char c_buffer[c_msg_space(sizeof(int))];
    memset(c_buffer, 0, sizeof(c_buffer));

    msg.msg_iov = &io;
    msg.msg_iovlen = 1;
    msg.msg_control = c_buffer;
    msg.msg_controllen = c_msg_space(sizeof(int));

    if (recvmsg(socket, &msg, 0) < 0)
    {
        printf("recvmsg error: %s\n", strerror(errno));
        return -1;
    }

    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);

    int fd;
    if (cmsg && cmsg->cmsg_len == c_msg_len(sizeof(int)))
    {
        if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS)
        {
            fd = *((int *)CMSG_DATA(cmsg));
            return fd;
        }
    }

    return -1;
}

/// Encode file descriptors into a socket control message buffer.
void *unix_rights(int *fds, int num_fds, unsigned char *buf, size_t buflen)
{
    struct cmsghdr *cm = (struct cmsghdr *)buf;
    if (c_msg_space(num_fds * sizeof(int)) > buflen)
    {
        return NULL;
    }
    cm->cmsg_len = c_msg_len(num_fds * sizeof(int));
    cm->cmsg_level = SOL_SOCKET;
    cm->cmsg_type = SCM_RIGHTS;
    memcpy(CMSG_DATA(cm), fds, num_fds * sizeof(int));
    return buf;
}

/// Decode file descriptors from a socket control message.
int parse_unix_rights(struct cmsghdr *cm, int *fds, int max_fds)
{
    if (cm->cmsg_level != SOL_SOCKET || cm->cmsg_type != SCM_RIGHTS)
    {
        return -1;
    }
    int num_fds = (cm->cmsg_len - CMSG_LEN(0)) / sizeof(int);
    num_fds = num_fds > max_fds ? max_fds : num_fds;
    if (cm->cmsg_len != c_msg_len(num_fds * sizeof(int)))
    {
        return -1;
    }
    memcpy(fds, CMSG_DATA(cm), num_fds * sizeof(int));
    return num_fds;
}

// ---------------------------------------------------------------------------
// Socket creation
// ---------------------------------------------------------------------------

/// Create a pair of connected socket file descriptors (like socketpair syscall).
/// The sockets are set to non-blocking and CLOEXEC.
/// Returns 0 on success, -1 on error. sv[0] and sv[1] are filled on success.
int create_socketpair(int sv[2])
{
    int ret = socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0, sv);
    if (ret < 0) {
        printf("socketpair error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

// -------------------------------------------------------------------------
// Socket creation and lifecycle
// -------------------------------------------------------------------------

int create_socket(int type)
{
    int sockfd = socket(AF_UNIX, type | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (sockfd == -1) {
        printf("socket error: %s\n", strerror(errno));
        return -1;
    }
    return sockfd;
}

int bind_socket(int socket, const char *path)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (bind(socket, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        printf("bind error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int bind_socket_abstract(int socket, const char *name)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    // Abstract namespace: first byte of sun_path is null byte
    // We copy the name AFTER the leading null
    size_t name_len = strlen(name);
    if (name_len > sizeof(addr.sun_path) - 1) {
        name_len = sizeof(addr.sun_path) - 1;
    }
    memcpy(addr.sun_path + 1, name, name_len);
    // Total sockaddr size: offset of sun_path + 1 (null) + name length
    socklen_t addr_len = offsetof(struct sockaddr_un, sun_path) + 1 + name_len;

    if (bind(socket, (struct sockaddr *)&addr, addr_len) == -1) {
        printf("bind abstract error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int listen_socket(int socket, int backlog)
{
    if (listen(socket, backlog) == -1) {
        printf("listen error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int accept_socket(int socket)
{
    int client_fd = accept4(socket, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
    if (client_fd == -1) {
        printf("accept error: %s\n", strerror(errno));
        return -1;
    }
    return client_fd;
}

int unlink_socket_path(const char *path)
{
    if (unlink(path) == -1 && errno != ENOENT) {
        printf("unlink error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

// -------------------------------------------------------------------------
// Socket options
// -------------------------------------------------------------------------

int get_socket_option(int socket, int level, int optname, int *value)
{
    socklen_t len = sizeof(int);
    if (getsockopt(socket, level, optname, (void *)value, &len) == -1) {
        printf("getsockopt error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int set_socket_option(int socket, int level, int optname, int value)
{
    if (setsockopt(socket, level, optname, (void *)&value, sizeof(value)) == -1) {
        printf("setsockopt error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int set_so_sndbuf(int socket, int size)
{
    return set_socket_option(socket, SOL_SOCKET, SO_SNDBUF, size);
}

int get_so_sndbuf(int socket)
{
    int value = 0;
    if (get_socket_option(socket, SOL_SOCKET, SO_SNDBUF, &value) == -1) {
        return -1;
    }
    return value;
}

int set_so_rcvbuf(int socket, int size)
{
    return set_socket_option(socket, SOL_SOCKET, SO_RCVBUF, size);
}

int get_so_rcvbuf(int socket)
{
    int value = 0;
    if (get_socket_option(socket, SOL_SOCKET, SO_RCVBUF, &value) == -1) {
        return -1;
    }
    return value;
}

int set_so_linger(int socket, int on_off, int linger_secs)
{
    struct linger l;
    l.l_onoff = on_off;
    l.l_linger = linger_secs;
    if (setsockopt(socket, SOL_SOCKET, SO_LINGER, (void *)&l, sizeof(l)) == -1) {
        printf("setsockopt SO_LINGER error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

// -------------------------------------------------------------------------
// Unix socket (client connect)
// -------------------------------------------------------------------------

int connect_unix_socket(int socket, const char *path)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (connect(socket, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        printf("connect error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int connect_unix_socket_abstract(int socket, const char *name)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    size_t name_len = strlen(name);
    if (name_len > sizeof(addr.sun_path) - 1) {
        name_len = sizeof(addr.sun_path) - 1;
    }
    memcpy(addr.sun_path + 1, name, name_len);
    socklen_t addr_len = offsetof(struct sockaddr_un, sun_path) + 1 + name_len;

    if (connect(socket, (struct sockaddr *)&addr, addr_len) == -1) {
        printf("connect abstract error: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

int create_unix_socket(const char *path)
{
    int sockfd;
    struct sockaddr_un addr;

    printf("Creating socket %s\n", path);

    if ((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1)
    {
        printf("socket error: %s\n", strerror(errno));
        return -1;
    }

    int flags = fcntl(sockfd, F_GETFL, 0);
    fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (connect(sockfd, (struct sockaddr *)&addr, sizeof(addr)) == -1)
    {
        printf("connect error: %s\n", strerror(errno));
        close(sockfd);
        return -1;
    }

    return sockfd;
}

ssize_t send_bytes_with_fd(int socket, int fd, const void *data, size_t data_len)
{
    struct msghdr msg = {0};
    struct iovec iov[1];

    iov[0].iov_base = (void *)data;
    iov[0].iov_len = data_len;

    msg.msg_iov = iov;
    msg.msg_iovlen = 1;

    char buf[CMSG_SPACE(sizeof(fd))];
    struct cmsghdr *cmsg;

    if (fd != -1) {
        memset(buf, 0, sizeof(buf));
        cmsg = (struct cmsghdr *)buf;
        cmsg->cmsg_level = SOL_SOCKET;
        cmsg->cmsg_type = SCM_RIGHTS;
        cmsg->cmsg_len = CMSG_LEN(sizeof(fd));
        *((int *)CMSG_DATA(cmsg)) = fd;

        msg.msg_control = cmsg;
        msg.msg_controllen = sizeof(buf);
    } else {
        msg.msg_control = NULL;
        msg.msg_controllen = 0;
    }

    ssize_t sent = sendmsg(socket, &msg, 0);
    if (sent < 0)
    {
        printf("socket: %d, fd: %d, length: %zu sendmsg error: %s\n", socket, fd, data_len, strerror(errno));
        perror("sendmsg");
        return -1;
    }

    return sent;
}

ssize_t send_bytes(int socket, const void *buffer, size_t length)
{
    ssize_t sent = send(socket, buffer, length, 0);
    if (sent < 0)
    {
        perror("send");
        return -1;
    }
    else
    {
        printf("sent %zu bytes\n", sent);
        return sent;
    }
}

ssize_t recv_bytes(int socket, void *buffer, size_t length)
{
    ssize_t n;
    // Retry on EINTR (SIGPROF from CPU profiler).
    do {
        n = recv(socket, buffer, length, 0);
    } while (n < 0 && errno == EINTR);
    return n;
}

void close_socket(int socket)
{
    close(socket);
}

// -------------------------------------------------------------------------
// Datagram send/recv
// -------------------------------------------------------------------------

ssize_t send_to(int socket, const char *path, const void *data, size_t data_len)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    ssize_t sent = sendto(socket, data, data_len, 0, (struct sockaddr *)&addr, sizeof(addr));
    if (sent < 0) {
        printf("sendto error: %s\n", strerror(errno));
        return -1;
    }
    return sent;
}

ssize_t send_to_abstract(int socket, const char *name, const void *data, size_t data_len)
{
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    size_t name_len = strlen(name);
    if (name_len > sizeof(addr.sun_path) - 1) {
        name_len = sizeof(addr.sun_path) - 1;
    }
    memcpy(addr.sun_path + 1, name, name_len);
    socklen_t addr_len = offsetof(struct sockaddr_un, sun_path) + 1 + name_len;

    ssize_t sent = sendto(socket, data, data_len, 0, (struct sockaddr *)&addr, addr_len);
    if (sent < 0) {
        printf("sendto abstract error: %s\n", strerror(errno));
        return -1;
    }
    return sent;
}

ssize_t recv_from(int socket, void *buffer, size_t length)
{
    ssize_t n = recvfrom(socket, buffer, length, 0, NULL, NULL);
    if (n < 0) {
        return -1;
    }
    return n;
}

/*
 * Create a new, unique, anonymous file of the given size, and
 * return the file descriptor for it. The file descriptor is set
 * CLOEXEC. The file is immediately suitable for mmap()'ing
 * the given size at offset zero.
 *
 * The file should not have a permanent backing store like a disk,
 * but may have if XDG_RUNTIME_DIR is not properly implemented in OS.
 *
 * The file name is deleted from the file system.
 *
 * The file is suitable for buffer sharing between processes by
 * transmitting the file descriptor over Unix sockets using the
 * SCM_RIGHTS methods.
 *
 * COPIED FROM: https://jan.newmarch.name/Wayland/SharedMemory/
 */
int os_create_anonymous_file(off_t size)
{
    static const char template[] = "/wayland-dart-shared-XXXXXX";
    const char *path;
    char *name;
    int fd;

    path = getenv("XDG_RUNTIME_DIR");
    if (!path)
    {
        errno = ENOENT;
        return -1;
    }

    name = malloc(strlen(path) + sizeof(template));
    if (!name)
        return -1;
    strcpy(name, path);
    strcat(name, template);

    fd = create_tmpfile_cloexec(name);

    free(name);

    if (fd < 0)
        return -1;

    if (ftruncate(fd, size) < 0)
    {
        close(fd);
        return -1;
    }

    return fd;
}

ssize_t write_to_fd(int fd, const unsigned char *buffer, size_t count) {
    ssize_t result = write(fd, buffer, count);
    if (result == -1) {
        return errno;  // Return errno to handle specific error cases in Dart
    }
    return result;
}


/**
 * Checks if the socket has available data to read.
 *
 * @param socket The file descriptor of the socket.
 * @param timeout The timeout in milliseconds. A negative value means an infinite timeout.
 * @return 1 if there is data to read, 0 if there is no data to read, -1 on error.
 */
int socket_has_data(int socket, int timeout) {
    fd_set read_fds;
    struct timeval tv;
    int ret;

    FD_ZERO(&read_fds);
    FD_SET(socket, &read_fds);

    // Retry on EINTR — the Dart CPU profiler sends SIGPROF which
    // interrupts select(). Without retrying, profiling would cause
    // spurious "connection lost" errors on the Wayland socket.
    for (;;) {
        if (timeout >= 0) {
            tv.tv_sec = timeout / 1000;
            tv.tv_usec = (timeout % 1000) * 1000;
            ret = select(socket + 1, &read_fds, NULL, NULL, &tv);
        } else {
            ret = select(socket + 1, &read_fds, NULL, NULL, NULL);
        }

        if (ret >= 0) break;
        if (errno != EINTR) return -1;
    }

    if (ret > 0) {
        if (FD_ISSET(socket, &read_fds)) {
            return 1; // Data is available to read
        }
    }
    // ret == 0: timeout, no data
    return 0;
}
