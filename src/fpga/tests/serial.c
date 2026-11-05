#define _XOPEN_SOURCE 600
#include "../src/uart/serial.h"
#include <assert.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static volatile sig_atomic_t signals;
static void tick(int signal_number) { (void)signal_number; ++signals; }
static void pause_ms(unsigned ms) { usleep(ms * 1000); }

int main(void)
{
    assert(serial_open("/no-such-fpga-port") == -1);
    assert(serial_open("/dev/null") == -1);
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    assert(master >= 0 && grantpt(master) == 0 && unlockpt(master) == 0);
    int fd = serial_open(ptsname(master));
    assert(fd >= 0);
    struct termios tty;
    assert(tcgetattr(fd, &tty) == 0);
    assert(cfgetispeed(&tty) == B115200 && cfgetospeed(&tty) == B115200);
    assert((tty.c_cflag & CSIZE) == CS8);
    assert(!(tty.c_cflag & (PARENB | CSTOPB)) && tty.c_iflag == 0 && tty.c_lflag == 0);
    struct sigaction action = {0};
    action.sa_handler = tick;
    sigemptyset(&action.sa_mask);
    assert(sigaction(SIGALRM, &action, NULL) == 0);
    struct itimerval timer = {{0, 1000}, {0, 1000}};
    assert(setitimer(ITIMER_REAL, &timer, NULL) == 0);
    char data[8];
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        close(fd);
        pause_ms(15);
        assert(write(master, "abc", 3) == 3);
        pause_ms(15);
        assert(write(master, "defgh", 5) == 5);
        _exit(0);
    }
    assert(serial_transfer(fd, data, sizeof data, 0, serial_deadline(500)) == SERIAL_OK);
    assert(memcmp(data, "abcdefgh", 8) == 0 && signals > 0);
    int status;
    while (waitpid(child, &status, 0) < 0) {}
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    int64_t start = serial_deadline(0);
    assert(serial_transfer(fd, data, 1, 0, serial_deadline(30)) == SERIAL_TIMEOUT);
    assert(serial_deadline(0) - start < 300);
    timer = (struct itimerval){{0, 0}, {0, 0}};
    assert(setitimer(ITIMER_REAL, &timer, NULL) == 0);
    /* A large transfer and a slow reader force partial writes and EAGAIN. */
    size_t size = 262144;
    unsigned char *large = malloc(size);
    assert(large);
    memset(large, 0xa5, size);
    child = fork();
    assert(child >= 0);
    if (!child) {
        close(fd);
        pause_ms(20);
        size_t received = 0;
        unsigned char block[257];
        while (received < size) {
            ssize_t n = read(master, block, sizeof block);
            assert(n > 0);
            for (ssize_t i = 0; i < n; ++i) assert(block[i] == 0xa5);
            received += (size_t)n;
        }
        _exit(0);
    }
    assert(serial_transfer(fd, large, size, 1, serial_deadline(3000)) == SERIAL_OK);
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(serial_transfer(fd, large, size, 1, serial_deadline(30)) == SERIAL_TIMEOUT);
    free(large);
    close(master);
    enum serial_result result = serial_transfer(fd, data, 1, 0, serial_deadline(100));
    assert(result == SERIAL_EOF || result == SERIAL_IO);
    close(fd);
    int pipefd[2];
    assert(pipe(pipefd) == 0);
    close(pipefd[1]);
    assert(serial_transfer(pipefd[0], data, 1, 0, serial_deadline(100)) == SERIAL_EOF);
    close(pipefd[0]);
    return 0;
}
