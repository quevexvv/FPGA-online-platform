#ifndef FPGA_SERIAL_H
#define FPGA_SERIAL_H
#include <stddef.h>
#include <stdint.h>
enum serial_result { SERIAL_OK, SERIAL_IO, SERIAL_TIMEOUT, SERIAL_EOF };
int serial_open(const char *path);
int64_t serial_deadline(unsigned timeout_ms);
enum serial_result serial_transfer(int fd, void *buffer, size_t size,
                                   int writing, int64_t deadline);
#endif
