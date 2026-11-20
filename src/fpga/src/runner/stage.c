#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum { COMMAND_FAILED = 1, TIMED_OUT = 124, SUPERVISOR_FAILED = 125 };
enum { POLL_MS = 20, TERMINATE_MS = 250 };
static const char children_path[] = "/proc/thread-self/children";
static volatile sig_atomic_t stop_signal;

static void request_stop(int signal_number)
{
    stop_signal = signal_number;
}

static int64_t monotonic_ms(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) == -1) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static long limit(const char *text)
{
    if (!*text || strspn(text, "0123456789") != strlen(text)) return 0;
    errno = 0;
    long value = strtol(text, NULL, 10);
    return !errno && value > 0 && value <= INT_MAX ? value : 0;
}

static int write_log(int log, const char *buffer, size_t count)
{
    while (count) {
        ssize_t written = write(log, buffer, count);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return -1;
        buffer += written;
        count -= (size_t)written;
    }
    return 0;
}

static void signal_tree(pid_t leader, int leader_done, int signal_number)
{
    if (!leader_done) kill(-leader, signal_number);

    // A tool can start a new process group. Its orphaned children are adopted
    // here and stopped on later passes as their parents exit.
    FILE *children = fopen(children_path, "r");
    if (!children) return;
    int pid;
    while (fscanf(children, "%d", &pid) == 1) {
        if (pid > 0 && (leader_done || getpgid((pid_t)pid) != leader)) {
            kill((pid_t)pid, signal_number);
        }
    }
    fclose(children);
}

static void start_command(char **command, int pipe_read, int pipe_write, int null_input)
{
    if (setpgid(0, 0) == -1 ||
        dup2(null_input, STDIN_FILENO) == -1 ||
        dup2(pipe_write, STDOUT_FILENO) == -1 ||
        dup2(pipe_write, STDERR_FILENO) == -1) _exit(126);
    close(pipe_read);
    close(pipe_write);
    close(null_input);
    signal(SIGHUP, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    signal(SIGTERM, SIG_DFL);
    execvp(command[0], command);
    perror(command[0]);
    _exit(127);
}

static int supervise(pid_t leader, int pipe_read, int log, long log_left, int64_t deadline)
{
    struct pollfd output = { .fd = pipe_read, .events = POLLIN };
    int leader_done = 0, leader_status = 0, result = 0, io_error = 0;
    int64_t kill_at = 0;
    for (;;) {
        int status;
        pid_t child;
        do {
            child = waitpid(-1, &status, WNOHANG);
            if (child == leader) {
                leader_done = 1;
                leader_status = status;
            }
        } while (child > 0 || (child < 0 && errno == EINTR));
        int children_alive = child == 0;

        if (output.fd >= 0) {
            char buffer[8192];
            ssize_t count = read(output.fd, buffer, sizeof buffer);
            if (count > 0 && log_left > 0 && !io_error) {
                size_t keep = (size_t)(count < log_left ? count : log_left);
                if (write_log(log, buffer, keep) == -1) io_error = 1;
                log_left -= (long)keep;
            } else if (count == 0) {
                output.fd = -1;
            } else if (count < 0 && errno != EINTR && (errno != EAGAIN || !children_alive)) {
                io_error = 1;
                output.fd = -1;
            }
        }

        if (!children_alive && output.fd < 0) break;

        if (children_alive) {
            int64_t now = monotonic_ms();
            if (!result) {
                if (io_error || now < 0) result = SUPERVISOR_FAILED;
                else if (stop_signal) result = 128 + stop_signal;
                else if (now >= deadline) result = TIMED_OUT;
                else if (leader_done) result = COMMAND_FAILED;
                if (result) {
                    signal_tree(leader, leader_done, SIGTERM);
                    kill_at = now + TERMINATE_MS;
                }
            }
            if (result && (now < 0 || now >= kill_at)) signal_tree(leader, leader_done, SIGKILL);
        }
        if (poll(&output, 1, POLL_MS) < 0 && errno != EINTR) io_error = 1;
    }
    if (result) return result;
    if (io_error || !leader_done) return SUPERVISOR_FAILED;
    if (stop_signal) return 128 + stop_signal;
    if (WIFEXITED(leader_status)) {
        int code = WEXITSTATUS(leader_status);
        if (code == 0) return 0;
        fprintf(stderr, "fpga-stage: command exited with code %d\n", code);
    } else if (WIFSIGNALED(leader_status)) {
        fprintf(stderr, "fpga-stage: command died from signal %d\n", WTERMSIG(leader_status));
    }
    return COMMAND_FAILED;
}

int main(int argc, char **argv)
{
    long timeout = argc > 1 ? limit(argv[1]) : 0;
    long max_log = argc > 2 ? limit(argv[2]) : 0;
    if (argc < 6 || !timeout || !max_log || strcmp(argv[4], "--") != 0) {
        fputs("Usage: fpga-stage TIMEOUT_MS MAX_LOG_BYTES LOG -- COMMAND [ARGS...]\n", stderr);
        return SUPERVISOR_FAILED;
    }

    struct sigaction stop = { .sa_handler = request_stop };
    if (sigemptyset(&stop.sa_mask) == -1 ||
        sigaction(SIGHUP, &stop, NULL) == -1 ||
        sigaction(SIGINT, &stop, NULL) == -1 ||
        sigaction(SIGTERM, &stop, NULL) == -1 ||
        prctl(PR_SET_CHILD_SUBREAPER, 1L, 0L, 0L, 0L) == -1 ||
        access(children_path, R_OK) == -1) {
        perror("fpga-stage: setup");
        return SUPERVISOR_FAILED;
    }
    int log = open(argv[3], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (log == -1) {
        perror("fpga-stage: log");
        return SUPERVISOR_FAILED;
    }
    int null_input = open("/dev/null", O_RDONLY | O_CLOEXEC);
    int stream[2];
    int64_t start = monotonic_ms();
    if (null_input == -1 || start < 0 || pipe2(stream, O_CLOEXEC) == -1 ||
        fcntl(stream[0], F_SETFL, O_NONBLOCK) == -1) {
        perror("fpga-stage: output pipe");
        return SUPERVISOR_FAILED;
    }
    if (stop_signal) return 128 + stop_signal;
    pid_t child = fork();
    if (child < 0) {
        perror("fpga-stage: fork");
        return SUPERVISOR_FAILED;
    }
    if (child == 0) start_command(argv + 5, stream[0], stream[1], null_input);
    // The child also sets the group before exec, so either scheduling order is safe.
    setpgid(child, child);
    close(null_input);
    close(stream[1]);
    int result = supervise(child, stream[0], log, max_log, start + timeout);
    close(stream[0]);
    if (close(log) == -1 && !result) result = SUPERVISOR_FAILED;
    return result;
}
