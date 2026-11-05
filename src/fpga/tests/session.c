#define _XOPEN_SOURCE 600
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static void run(const char *commands, const char *requests, const char *replies,
                const char *expected, const char *error, int code)
{
    int master = posix_openpt(O_RDWR | O_NOCTTY), input[2], output[2], errors[2];
    assert(master >= 0 && grantpt(master) == 0 && unlockpt(master) == 0);
    assert(pipe(input) == 0 && pipe(output) == 0 && pipe(errors) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        assert(dup2(input[0], STDIN_FILENO) >= 0);
        assert(dup2(output[1], STDOUT_FILENO) >= 0);
        assert(dup2(errors[1], STDERR_FILENO) >= 0);
        close(input[0]); close(input[1]); close(output[0]); close(output[1]);
        close(errors[0]); close(errors[1]);
        char *path = ptsname(master);
        close(master);
        execl("build/fpga-uart", "fpga-uart", path, "100", (char *)NULL);
        _exit(127);
    }
    close(input[0]); close(output[1]); close(errors[1]);
    assert(write(input[1], commands, strlen(commands)) == (ssize_t)strlen(commands));
    close(input[1]);
    for (size_t offset = 0; offset < strlen(requests); offset += 7) {
        char request[7];
        for (size_t i = 0; i < sizeof request;) {
            struct pollfd pfd = {master, POLLIN, 0};
            assert(poll(&pfd, 1, 1000) > 0);
            ssize_t n = read(master, request + i, sizeof request - i);
            if (n < 0 && errno == EIO) { usleep(1000); continue; }
            assert(n > 0);
            i += (size_t)n;
        }
        assert(memcmp(request, requests + offset, 7) == 0);
        /* Send each response one byte at a time, including malformed frames. */
        size_t start = offset / 7 * 8;
        for (size_t i = start; i < strlen(replies) && i < start + 8; ++i) {
            assert(write(master, replies + i, 1) == 1);
            usleep(1000);
        }
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == code);
    char text[256] = {0}, diagnostic[256] = {0};
    assert(read(output[0], text, sizeof text - 1) >= 0);
    assert(read(errors[0], diagnostic, sizeof diagnostic - 1) >= 0);
    assert(strcmp(text, expected) == 0 && strstr(diagnostic, error));
    /* A failed command must end the session without sending the queued STEP. */
    char extra[8];
    assert(read(master, extra, sizeof extra) < 0 && errno == EIO);
    close(master); close(output[0]); close(errors[0]);
}

int main(void)
{
    alarm(15);
    run("reset\ninput 03ff\nstep 0000\nstep ffff\nread\n",
        "1R0000\n1I03ff\n1S0000\n1Sffff\n1Q0000\n",
        "1K00000\n1K00000\n1K00000\n1K00000\n1D3ffff\n",
        "K\nK\nK\nK\nD 0x3ffff\n", "", 0);
    const char *bad[] = {"2K00000\n", "1K00001\n", "1D00000\n", "1K0000A\n",
                         "1K000000", "garbage\n", "1E00000\n", "1K0000\r\n", "1K\n"};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; ++i)
        run("reset\nstep 0001\n", "1R0000\n", bad[i], "", "protocol:", 4);
    run("read\n", "1Q0000\n", "1D40000\n", "", "protocol:", 4);
    for (unsigned i = 1; i <= 6; ++i) {
        char reply[9];
        snprintf(reply, sizeof reply, "1E%05x\n", i);
        run("reset\nstep 0001\n", "1R0000\n", reply, "", "board:error:", 5);
    }
    run("reset\nstep 0001\n", "1R0000\n", "1K", "", "transport:timeout", 3);
    run("reset\nstep 0001\n", "1R0000\n", "", "", "transport:timeout", 3);
    run("reset\nread\n", "1R0000\n1Q0000\n", "1K00000\n1D", "K\n", "transport:timeout", 3);
    const char *invalid[] = {"input 0400\n", "step 10000\n", "step FFFF\n",
                             "read\r\n", "reset", "unknown\n"};
    for (size_t i = 0; i < sizeof invalid / sizeof invalid[0]; ++i)
        run(invalid[i], "", "", "", "input:invalid_command", 2);
    return 0;
}
