#pragma once

// Interactive picker UI: raw termios mode and ANSI escapes.

#include <string>
#include <vector>

#include "model.hpp"
#include "optional.hpp"

namespace tabgoto {

// Runs the picker and returns the chosen row index, or an empty Optional when
// cancelled.
Optional<int> pick_index(const std::vector<Row>& rows, int start,
                         const Optional<std::string>& last_id);

}  // namespace tabgoto
