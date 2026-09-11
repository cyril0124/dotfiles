#pragma once

// herdr CLI access: process execution, JSON payloads, and the popup socket.
// POSIX + libc only.

#include <string>
#include <vector>

#include "model.hpp"
#include "optional.hpp"

namespace tabgoto {

// Resolves the herdr binary from HERDR_BIN_PATH or PATH.
Optional<std::string> herdr_bin(std::string& error);

bool load_tabs(const std::string& bin, std::vector<Row>& rows, std::string& error);
bool focus_tab(const std::string& bin, const std::string& tab_id, std::string& error);

// Opens the picker popup through the herdr socket and prints the response.
bool open_popup(const std::string& bin, std::string& error);

// Last-tab bookkeeping: HERDR_PLUGIN_STATE_DIR, else <cwd>/.state.
std::string state_dir();
Optional<std::string> read_last_tab();
void write_last_tab(const std::string& tab_id);

}  // namespace tabgoto
