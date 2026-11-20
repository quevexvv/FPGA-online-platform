#define _POSIX_C_SOURCE 200809L
#include "serial.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

enum { MAX_BYTES = 64, TIMEOUT_MS = 2000 };

static unsigned hex_digit(char digit)
{
    if (digit >= '0' && digit <= '9') return (unsigned)(digit - '0');
    if (digit >= 'a' && digit <= 'f') return (unsigned)(digit - 'a' + 10);
    if (digit >= 'A' && digit <= 'F') return (unsigned)(digit - 'A' + 10);
    return 16;
}

static size_t parse_bytes(const char *hex, unsigned char bytes[MAX_BYTES])
{
    size_t length = strlen(hex);
    if (length > 2 * MAX_BYTES || length % 2 != 0) return 0;
    for (size_t i = 0; i < length / 2; ++i) {
        unsigned high = hex_digit(hex[2 * i]), low = hex_digit(hex[2 * i + 1]);
        if (high >= 16 || low >= 16) return 0;
        bytes[i] = (unsigned char)(high * 16 + low);
    }
    return length / 2;
}

static void usage(FILE *out)
{
    fputs("Usage: fpga-uart-stimulus <port> <even|odd> <hex-bytes> <reply-bytes>\n"
          "115200 baud, 8 bits, 1 stop bit. Send 1-64 bytes. Read 0-64 bytes.\n", out);
}

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        usage(stdout);
        return 0;
    }
    if (argc != 5 || (strcmp(argv[2], "even") != 0 && strcmp(argv[2], "odd") != 0)) {
        usage(stderr);
        return 2;
    }
    unsigned char bytes[MAX_BYTES];
    size_t size = parse_bytes(argv[3], bytes);
    size_t digits = strspn(argv[4], "0123456789");
    if (!size || digits == 0 || digits > 2 || argv[4][digits] != '\0') {
        usage(stderr);
        return 2;
    }
    unsigned reply = (unsigned)strtoul(argv[4], NULL, 10);
    if (reply > MAX_BYTES) {
        usage(stderr);
        return 2;
    }
    enum serial_parity parity = strcmp(argv[2], "even") == 0 ? SERIAL_PARITY_EVEN
                                                            : SERIAL_PARITY_ODD;
    int fd = serial_open_parity(argv[1], parity);
    if (fd < 0) {
        perror("Cannot configure UART");
        return 1;
    }
    int64_t deadline = serial_deadline(TIMEOUT_MS);
    enum serial_result result = serial_transfer(fd, bytes, size, 1, deadline);
    if (result == SERIAL_OK && reply != 0) {
        result = serial_transfer(fd, bytes, reply, 0, deadline);
    } else if (result == SERIAL_OK) {
        // A send-only call must wait for queued bytes before closing the port.
        alarm(TIMEOUT_MS / 1000);
        if (tcdrain(fd) < 0) result = SERIAL_IO;
        alarm(0);
    }
    close(fd);
    if (result != SERIAL_OK) {
        fputs(result == SERIAL_TIMEOUT ? "UART exchange timed out\n" : "UART exchange failed\n",
              stderr);
        return 1;
    }
    for (unsigned i = 0; i < reply; ++i) printf("%02x", (unsigned)bytes[i]);
    if (reply != 0) putchar('\n');
    return 0;
}
