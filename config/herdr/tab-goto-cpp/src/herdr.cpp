#include "herdr.hpp"

#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace tabgoto {
namespace {

constexpr size_t kReadBufferSize = 4096;

std::string errno_message(StringView what) {
    return to_string(what) + ": " + std::strerror(errno);
}

bool is_executable_file(const std::string& path) {
    struct stat info {};
    if (stat(path.c_str(), &info) != 0) {
        return false;
    }
    return S_ISREG(info.st_mode) && access(path.c_str(), X_OK) == 0;
}

std::vector<char*> to_argv(const std::vector<std::string>& args) {
    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (const std::string& arg : args) {
        argv.push_back(const_cast<char*>(arg.c_str()));
    }
    argv.push_back(nullptr);
    return argv;
}

// Waits for `pid` and reports whether it exited with status 0.
bool wait_for_success(pid_t pid, std::string& error) {
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        error = errno_message("waitpid");
        return false;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        error = "command failed";
        return false;
    }
    return true;
}

// Runs a command and captures stdout; stderr is discarded.
bool capture_stdout(const std::vector<std::string>& args, std::string& out, std::string& error) {
    int pipe_fds[2];
    if (pipe(pipe_fds) != 0) {
        error = errno_message("pipe");
        return false;
    }

    const pid_t pid = fork();
    if (pid < 0) {
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        error = errno_message("fork");
        return false;
    }

    if (pid == 0) {
        dup2(pipe_fds[1], STDOUT_FILENO);
        const int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            dup2(devnull, STDERR_FILENO);
        }
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        std::vector<char*> argv = to_argv(args);
        execvp(argv[0], argv.data());
        _exit(127);
    }

    close(pipe_fds[1]);
    out.clear();
    char buffer[kReadBufferSize];
    while (true) {
        const ssize_t n = read(pipe_fds[0], buffer, sizeof buffer);
        if (n > 0) {
            out.append(buffer, static_cast<size_t>(n));
            continue;
        }
        if (n < 0 && errno == EINTR) {
            continue;
        }
        break;
    }
    close(pipe_fds[0]);
    return wait_for_success(pid, error);
}

// Runs a command with stdout and stderr discarded.
bool run_quiet(const std::vector<std::string>& args, std::string& error) {
    const pid_t pid = fork();
    if (pid < 0) {
        error = errno_message("fork");
        return false;
    }
    if (pid == 0) {
        const int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
        }
        std::vector<char*> argv = to_argv(args);
        execvp(argv[0], argv.data());
        _exit(127);
    }
    return wait_for_success(pid, error);
}

std::string join_args(const std::vector<std::string>& args) {
    std::string joined;
    for (const std::string& arg : args) {
        if (!joined.empty()) {
            joined.push_back(' ');
        }
        joined += arg;
    }
    return joined;
}

bool read_json_payload(const std::string& bin, const std::vector<std::string>& args, Json& out,
                       std::string& error) {
    std::vector<std::string> command;
    command.reserve(args.size() + 1);
    command.push_back(bin);
    command.insert(command.end(), args.begin(), args.end());

    std::string raw;
    if (!capture_stdout(command, raw, error)) {
        error = "herdr " + join_args(args) + " failed: " + error;
        return false;
    }
    Json payload;
    if (!Json::parse(raw, payload, error)) {
        error = "herdr " + join_args(args) + ": bad json: " + error;
        return false;
    }
    const Json* result = payload.find("result");
    out = (result != nullptr && result->is_object()) ? *result : payload;
    return true;
}

}  // namespace

Optional<std::string> herdr_bin(std::string& error) {
    const char* override = std::getenv("HERDR_BIN_PATH");
    if (override != nullptr && is_executable_file(override)) {
        return std::string(override);
    }

    const char* path = std::getenv("PATH");
    if (path != nullptr) {
        std::string search(path);
        size_t start = 0;
        while (start <= search.size()) {
            const size_t colon = search.find(':', start);
            const std::string dir =
                search.substr(start, colon == std::string::npos ? std::string::npos : colon - start);
            if (!dir.empty()) {
                const std::string candidate = dir + "/herdr";
                if (is_executable_file(candidate)) {
                    return candidate;
                }
            }
            if (colon == std::string::npos) {
                break;
            }
            start = colon + 1;
        }
    }

    error = "herdr not found (set HERDR_BIN_PATH or PATH)";
    return Optional<std::string>();
}

bool load_tabs(const std::string& bin, std::vector<Row>& rows, std::string& error) {
    Json tab_result;
    if (!read_json_payload(bin, {"tab", "list"}, tab_result, error)) {
        return false;
    }

    // Workspace labels are cosmetic: fall back to the raw ID when unavailable.
    Json workspace_result;
    std::string ignored;
    const bool have_workspaces = read_json_payload(bin, {"workspace", "list"}, workspace_result, ignored);

    rows = rows_from_json(tab_result, have_workspaces ? &workspace_result : nullptr);
    return true;
}

bool focus_tab(const std::string& bin, const std::string& tab_id, std::string& error) {
    return run_quiet({bin, "tab", "focus", tab_id}, error);
}

std::string state_dir() {
    const char* override = std::getenv("HERDR_PLUGIN_STATE_DIR");
    if (override != nullptr && *override != '\0') {
        return std::string(override);
    }
    char cwd[4096];
    if (getcwd(cwd, sizeof cwd) == nullptr) {
        return ".state";
    }
    return std::string(cwd) + "/.state";
}

Optional<std::string> read_last_tab() {
    const std::string path = state_dir() + "/last-tab";
    FILE* file = std::fopen(path.c_str(), "r");
    if (file == nullptr) {
        return Optional<std::string>();
    }
    std::string content;
    char buffer[256];
    while (std::fgets(buffer, sizeof buffer, file) != nullptr) {
        content += buffer;
    }
    std::fclose(file);
    const std::string trimmed = trim(content);
    if (trimmed.empty()) {
        return Optional<std::string>();
    }
    return Optional<std::string>(trimmed);
}

void write_last_tab(const std::string& tab_id) {
    const std::string dir = state_dir();
    ::mkdir(dir.c_str(), 0755);  // Ignore EEXIST; the write below reports real failures.
    const std::string path = dir + "/last-tab";
    const std::string tmp = path + ".tmp";
    FILE* file = std::fopen(tmp.c_str(), "w");
    if (file == nullptr) {
        return;
    }
    std::fputs(tab_id.c_str(), file);
    std::fputc('\n', file);
    std::fclose(file);
    std::rename(tmp.c_str(), path.c_str());
}

bool open_popup(const std::string& bin, std::string& error) {
    std::vector<Row> rows;
    if (!load_tabs(bin, rows, error)) {
        return false;
    }

    Json layout;
    if (!read_json_payload(bin, {"pane", "layout"}, layout, error)) {
        return false;
    }
    const Json* area = layout.find("layout");
    area = (area != nullptr) ? area->find("area") : nullptr;
    const Json* cols = (area != nullptr) ? area->find("width") : nullptr;
    const Json* lines = (area != nullptr) ? area->find("height") : nullptr;
    if (cols == nullptr || lines == nullptr || !cols->is_integer() || !lines->is_integer() ||
        cols->as_integer() <= 0 || lines->as_integer() <= 0) {
        error = "pane layout is missing a positive area size";
        return false;
    }

    const std::pair<int, int> popup =
        content_size(rows, static_cast<int>(cols->as_integer()), static_cast<int>(lines->as_integer()));
    const int width = popup.first;
    const int height = popup.second;

    const char* socket_path = std::getenv("HERDR_SOCKET_PATH");
    if (socket_path == nullptr || *socket_path == '\0') {
        error = "HERDR_SOCKET_PATH is not set";
        return false;
    }

    const std::string request =
        std::string("{\"id\":\"local.tab-goto-cpp.open\",\"method\":\"plugin.pane.open\",\"params\":{") +
        "\"plugin_id\":\"local.tab-goto-cpp\",\"entrypoint\":\"picker\",\"placement\":\"popup\"," +
        "\"width\":" + std::to_string(width) + ",\"height\":" + std::to_string(height) +
        ",\"focus\":true}}";

    const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        error = errno_message("socket");
        return false;
    }

    struct sockaddr_un address {};
    address.sun_family = AF_UNIX;
#ifdef __APPLE__
    // BSD socket addresses carry their own length.
    address.sun_len = sizeof address;
#endif
    if (std::strlen(socket_path) >= sizeof address.sun_path) {
        close(fd);
        error = "HERDR_SOCKET_PATH is too long";
        return false;
    }
    std::strncpy(address.sun_path, socket_path, sizeof address.sun_path - 1);

    if (connect(fd, reinterpret_cast<struct sockaddr*>(&address), sizeof address) != 0) {
        error = errno_message(std::string("connect ") + socket_path);
        close(fd);
        return false;
    }

    const std::string payload = request + "\n";
    size_t written = 0;
    while (written < payload.size()) {
        const ssize_t n = write(fd, payload.data() + written, payload.size() - written);
        if (n > 0) {
            written += static_cast<size_t>(n);
            continue;
        }
        if (n < 0 && errno == EINTR) {
            continue;
        }
        error = errno_message("write to herdr socket");
        close(fd);
        return false;
    }

    std::string response;
    char buffer[4096];
    while (response.find('\n') == std::string::npos) {
        const ssize_t n = read(fd, buffer, sizeof buffer);
        if (n > 0) {
            response.append(buffer, static_cast<size_t>(n));
            continue;
        }
        if (n < 0 && errno == EINTR) {
            continue;
        }
        break;
    }
    close(fd);

    Json parsed;
    if (!Json::parse(response, parsed, error)) {
        error = "malformed response from herdr: " + error;
        return false;
    }
    const Json* failure = parsed.find("error");
    if (failure != nullptr && !failure->is_null()) {
        error = "plugin.pane.open: " + std::string(response.substr(0, response.find('\n')));
        return false;
    }
    const Json* result = parsed.find("result");
    if (result == nullptr || !result->is_object()) {
        error = "plugin.pane.open: malformed response";
        return false;
    }

    const std::string reply = trim(response);
    std::fputs(reply.c_str(), stdout);
    std::fputc('\n', stdout);
    return true;
}

}  // namespace tabgoto
