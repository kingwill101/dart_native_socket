
#include "native_socket.h"
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

    return sent;  // Return the number of bytes sent
}

int recv_fd(int socket)
{
    struct msghdr msg = {0};
    char m_buffer[256];
    struct iovec io = {.iov_base = m_buffer, .iov_len = sizeof(m_buffer)};

    char c_buffer[c_msg_space(sizeof(int))]; // Use c_msg_space function
    memset(c_buffer, 0, sizeof(c_buffer));

    msg.msg_iov = &io;
    msg.msg_iovlen = 1;
    msg.msg_control = c_buffer;
    msg.msg_controllen = c_msg_space(sizeof(int)); // Use c_msg_space function

    if (recvmsg(socket, &msg, 0) < 0)
    {
        printf("recvmsg error: %s\n", strerror(errno));
        return -1;
    }

    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);

    int fd;
    if (cmsg && cmsg->cmsg_len == c_msg_len(sizeof(int))) // Use c_msg_len function
    {
        if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS)
        {
            fd = *((int *)CMSG_DATA(cmsg));
            return fd;
        }
    }

    return -1;
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
    ssize_t read = recv(socket, buffer, length, 0);
    if (read == -1)
    {
        return 0;
    }
    return read;
}

void close_socket(int socket)
{
    close(socket);
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

static int create_tmpfile_cloexec(char *tmpname)
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

// Function to calculate the length of a control message with data length
static size_t c_msg_len(size_t datalen)
{
    return CMSG_LEN(datalen);
}

// Function to calculate the total space needed for a control message with data length
static size_t c_msg_space(size_t datalen)
{
    return CMSG_SPACE(datalen);
}

// Function to encode file descriptors into a socket control message
void *unix_rights(int *fds, int num_fds, unsigned char *buf, size_t buflen)
{
    struct cmsghdr *cm = (struct cmsghdr *)buf;
    if (c_msg_space(num_fds * sizeof(int)) > buflen)
    {
        return NULL; // Ensure buffer is large enough
    }
    cm->cmsg_len = c_msg_len(num_fds * sizeof(int)); // Use c_msg_len function
    cm->cmsg_level = SOL_SOCKET;
    cm->cmsg_type = SCM_RIGHTS;
    memcpy(CMSG_DATA(cm), fds, num_fds * sizeof(int));
    return buf;
}

// Function to decode file descriptors from a socket control message
int parse_unix_rights(struct cmsghdr *cm, int *fds, int max_fds)
{
    if (cm->cmsg_level != SOL_SOCKET || cm->cmsg_type != SCM_RIGHTS)
    {
        return -1; // Error
    }
    int num_fds = (cm->cmsg_len - CMSG_LEN(0)) / sizeof(int);
    num_fds = num_fds > max_fds ? max_fds : num_fds;
    if (cm->cmsg_len != c_msg_len(num_fds * sizeof(int)))
    {
        return -1; // Length mismatch error
    }
    memcpy(fds, CMSG_DATA(cm), num_fds * sizeof(int));
    return num_fds;
}


int write_to_fd(int fd, const unsigned char *buffer, size_t count) {
    ssize_t result = write(fd, buffer, count);
    if (result == -1) {
        return errno;  // Return errno to handle specific error cases in Dart
    }
    return result;  // Return the number of bytes written
}
