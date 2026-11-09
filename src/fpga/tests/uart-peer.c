#define _XOPEN_SOURCE 600
#include <assert.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    assert(argc == 3);
    alarm(20);
    FILE *transcript = fopen(argv[1], "r");
    assert(transcript);
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    assert(master >= 0 && grantpt(master) == 0 && unlockpt(master) == 0);
    const char *path = ptsname(master);
    assert(path);
    /* Keep the PTY alive while the runner switches from probing to testing. */
    int slave = open(path, O_RDWR | O_NOCTTY);
    assert(slave >= 0);
    FILE *ready = fopen(argv[2], "w");
    assert(ready && fprintf(ready, "%s\n", path) > 0 && fclose(ready) == 0);

    char expected[8], response[8];
    while (fscanf(transcript, "%7s %7s", expected, response) == 2) {
        char frame[7];
        for (size_t offset = 0; offset < sizeof frame;) {
            struct pollfd pfd = {master, POLLIN, 0};
            assert(poll(&pfd, 1, 5000) == 1 && (pfd.revents & POLLIN));
            ssize_t count = read(master, frame + offset, sizeof frame - offset);
            assert(count > 0);
            offset += (size_t)count;
        }
        assert(strlen(expected) == 6 && memcmp(frame, expected, 6) == 0 && frame[6] == '\n');
        if (strcmp(response, "-") != 0) {
            char reply[9];
            assert(snprintf(reply, sizeof reply, "%s\n", response) == 8);
            assert(write(master, reply, 8) == 8);
        }
    }
    assert(feof(transcript) && fclose(transcript) == 0);
    /* The test stops the peer after the runner consumes the last reply. */
    pause();
    close(slave);
    close(master);
    return 0;
}
