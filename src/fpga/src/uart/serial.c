#define _POSIX_C_SOURCE 200809L
#include "serial.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static int64_t now_ms(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) < 0) return -1;
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int64_t serial_deadline(unsigned timeout_ms)
{
    int64_t now = now_ms();
    return now < 0 ? -1 : now + timeout_ms;
}

int serial_open(const char *path)
{
    int fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    struct termios tty;
    if (fd < 0) return -1;
    if (tcgetattr(fd, &tty) < 0) goto fail;
    tty.c_iflag = 0;
    tty.c_oflag = 0;
    tty.c_lflag = 0;
    tty.c_cflag = CS8 | CREAD | CLOCAL;
    tty.c_cc[VMIN] = 1;
    tty.c_cc[VTIME] = 0;
    if (cfsetispeed(&tty, B115200) < 0 || cfsetospeed(&tty, B115200) < 0 ||
        tcsetattr(fd, TCSANOW, &tty) < 0 || tcflush(fd, TCIOFLUSH) < 0) goto fail;
    return fd;
fail: {
    int saved = errno;
    close(fd);
    errno = saved;
    return -1;
}
}

enum serial_result serial_transfer(int fd, void *buffer, size_t size,
                                   int writing, int64_t deadline)
{
    unsigned char *bytes = buffer;
    size_t offset = 0;
    if (deadline < 0) return SERIAL_IO;
    while (offset < size) {
        int64_t now = now_ms();
        if (now < 0) return SERIAL_IO;
        if (now >= deadline) return SERIAL_TIMEOUT;
        int64_t left = deadline - now;
        struct pollfd pfd = {fd, writing ? POLLOUT : POLLIN, 0};
        int ready = poll(&pfd, 1, left > INT_MAX ? INT_MAX : (int)left);
        if (ready < 0) {
            if (errno == EINTR) continue;
            return SERIAL_IO;
        }
        if (!ready) continue;
        if (pfd.revents & POLLNVAL) return SERIAL_IO;
        ssize_t count = writing ? write(fd, bytes + offset, size - offset)
                                : read(fd, bytes + offset, size - offset);
        if (count > 0) offset += (size_t)count;
        else if (count == 0) return SERIAL_EOF;
        else if (errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK)
            return SERIAL_IO;
    }
    return SERIAL_OK;
}
