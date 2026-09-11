// Tab-only herdr goto: C++ port of the Python picker.
// One binary, two modes: `open` (popup launcher) and `picker` (default, TUI).

#include <unistd.h>

#include <cstdio>
#include <string>
#include <vector>

#include "herdr.hpp"
#include "optional.hpp"
#include "ui.hpp"

namespace {

void pause_message(const std::string& message) {
    std::fputs(message.c_str(), stdout);
    std::fputs("\nPress enter to close.\n", stdout);
    std::fflush(stdout);
    char buffer[256];
    if (std::fgets(buffer, sizeof buffer, stdin) == nullptr) {
        return;
    }
}

int picker_mode(const std::string& bin) {
    if (isatty(STDIN_FILENO) == 0 || isatty(STDOUT_FILENO) == 0) {
        pause_message("tab-goto needs a TTY (run from herdr popup).");
        return 1;
    }

    std::vector<tabgoto::Row> rows;
    std::string error;
    if (!tabgoto::load_tabs(bin, rows, error)) {
        pause_message("Failed to list tabs: " + error);
        return 1;
    }
    if (rows.empty()) {
        pause_message("No tabs in this session.");
        return 0;
    }

    const int start = tabgoto::initial_index(rows);
    const std::string here_id = rows[static_cast<size_t>(start)].tab_id;
    const tabgoto::Optional<std::string> last_id = tabgoto::read_last_tab();

    const tabgoto::Optional<int> chosen = tabgoto::pick_index(rows, start, last_id);
    if (!chosen.has_value()) {
        return 0;
    }

    const std::string& tab_id = rows[static_cast<size_t>(*chosen)].tab_id;
    if (tab_id != here_id) {
        // Remember where we came from so `n` can jump back.
        tabgoto::write_last_tab(here_id);
    }
    if (!tabgoto::focus_tab(bin, tab_id, error)) {
        pause_message("herdr tab focus failed for " + tab_id);
        return 1;
    }
    return 0;
}

int open_mode(const std::string& bin) {
    std::string error;
    if (!tabgoto::open_popup(bin, error)) {
        std::fprintf(stderr, "failed to open tab picker: %s\n", error.c_str());
        return 1;
    }
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    const std::string mode = argc > 1 ? argv[1] : "picker";

    std::string error;
    const tabgoto::Optional<std::string> bin = tabgoto::herdr_bin(error);
    if (!bin.has_value()) {
        pause_message(error);
        return 1;
    }

    if (mode == "open") {
        return open_mode(*bin);
    }
    if (mode == "picker") {
        return picker_mode(*bin);
    }

    pause_message("usage: tab-goto [picker|open]");
    return 2;
}
