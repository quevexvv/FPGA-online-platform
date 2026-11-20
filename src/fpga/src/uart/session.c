#define _POSIX_C_SOURCE 200809L
#include "serial.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int hex_value(const char *text, size_t length, unsigned *value)
{
    *value = 0;
    for (size_t i = 0; i < length; ++i) {
        char c = text[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return 0;
        *value = *value * 16 + (unsigned)(c <= '9' ? c - '0' : c - 'a' + 10);
    }
    return 1;
}

static int exchange(int fd, char command, unsigned value, unsigned timeout_ms)
{
    char request[8], response[8];
    int64_t deadline = serial_deadline(timeout_ms);
    snprintf(request, sizeof request, "1%c%04x\n", command, value);
    enum serial_result result = serial_transfer(fd, request, 7, 1, deadline);
    for (size_t i = 0; result == SERIAL_OK && i < sizeof response; ++i) {
        result = serial_transfer(fd, response + i, 1, 0, deadline);
        if (result == SERIAL_OK && response[i] == '\n' && i != 7) goto malformed;
    }
    if (result != SERIAL_OK) {
        fprintf(stderr, "transport:%s\n", result == SERIAL_TIMEOUT ? "timeout" :
                result == SERIAL_EOF ? "eof" : "io");
        return 3;
    }
    unsigned answer;
    if (response[0] != '1' || response[7] != '\n' ||
        !hex_value(response + 2, 5, &answer)) goto malformed;
    if (response[1] == 'E' && answer >= 1 && answer <= 6) {
        fprintf(stderr, "board:error:%u\n", answer);
        return 5;
    }
    if (command == 'Q') {
        if (response[1] != 'D' || answer > 0x3ffff) goto malformed;
        printf("D 0x%05x\n", answer);
    } else {
        if (response[1] != 'K' || answer != 0) goto malformed;
        puts("K");
    }
    return fflush(stdout) == 0 ? 0 : 3;
malformed:
    fputs("protocol:invalid_response\n", stderr);
    return 4;
}

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        puts("Usage: fpga-uart PORT TIMEOUT_MS < commands\n"
             "Commands: reset, input hhhh, step hhhh, read (one per line).\n"
             "Lowercase hex only. Replies: K or D 0xhhhhh. No retries.\n"
             "Exit: 2 input/open, 3 transport, 4 protocol, 5 board error.");
        return 0;
    }
    if (argc != 3 || !argv[2][0] || strspn(argv[2], "0123456789") != strlen(argv[2])) {
        fputs("input:expected_port_and_timeout_ms\n", stderr);
        return 2;
    }
    char *end;
    errno = 0;
    unsigned long timeout = strtoul(argv[2], &end, 10);
    if (errno || *end || timeout == 0 || timeout > 60000) {
        fputs("input:timeout_range_1_60000_ms\n", stderr);
        return 2;
    }
    int fd = serial_open(argv[1]);
    if (fd < 0) { perror("transport:open"); return 2; }
    int code = 0;
    char line[32];
    while (fgets(line, sizeof line, stdin)) {
        char command;
        unsigned value = 0;
        if (strcmp(line, "reset\n") == 0) command = 'R';
        else if (strcmp(line, "read\n") == 0) command = 'Q';
        else if (strlen(line) == 11 && line[10] == '\n' &&
                 strncmp(line, "input ", 6) == 0 &&
                 hex_value(line + 6, 4, &value)) {
            command = 'I';
            if (value > 0x3ff) goto invalid;
        } else if (strlen(line) == 10 && strncmp(line, "step ", 5) == 0 &&
                   line[9] == '\n' && hex_value(line + 5, 4, &value)) command = 'S';
        else goto invalid;
        code = exchange(fd, command, value, (unsigned)timeout);
        if (code) break;
        continue;
invalid:
        fputs("input:invalid_command\n", stderr);
        code = 2;
        break;
    }
    if (ferror(stdin)) { fputs("input:read_failed\n", stderr); code = 2; }
    if (close(fd) < 0 && !code) { perror("transport:close"); code = 3; }
    return code;
}
