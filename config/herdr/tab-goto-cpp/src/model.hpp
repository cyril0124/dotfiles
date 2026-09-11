#pragma once

// Pure data model behind the picker: tab rows, the workspace/tab tree, and the
// popup geometry. Kept free of terminal and process handling.

#include <cstddef>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "json.hpp"
#include "string_view.hpp"

namespace tabgoto {

struct Row {
    std::string tab_id;
    std::string workspace_id;
    std::string workspace;
    std::string tab;
    std::string status;
    bool focused = false;
};

enum class EntryKind { Workspace, Tab };

struct Entry {
    EntryKind kind = EntryKind::Tab;
    std::string workspace_id;
    // Workspace entries only.
    std::string label;
    int count = 0;
    bool expanded = false;
    // Tab entries only: index into the row list.
    int tab_index = 0;
    bool is_last_child = false;
};

enum class StatusKind { Working, Idle, Done, Blocked, Unknown, Other };

// UTF-8 aware text helpers; widths and counts are characters, not bytes.
size_t utf8_length(StringView text);
std::string utf8_prefix(StringView text, size_t max_chars);
std::string repeat(StringView unit, int times);
// Pads with spaces to `width` characters, or truncates with a trailing dot.
std::string fit(StringView text, int width);

std::string trim(StringView text);
std::string to_lower_ascii(StringView text);
// Drops herdr's own "12 foo" numeric tab prefix.
std::string strip_num_prefix(StringView tab_label);

StatusKind status_kind(StringView status);
// Fixed-width (7 column) status badge text.
std::string status_badge(StringView status);
// Rows worth showing when the status filter is on.
bool is_interesting_status(StringView status);

std::vector<Row> rows_from_json(const Json& tab_result, const Json* workspace_result);
int initial_index(const std::vector<Row>& rows);

std::vector<int> filtered_tab_indices(const std::vector<Row>& rows, bool filter_on, StringView query);
std::vector<Entry> build_entries(const std::vector<Row>& rows,
                                 const std::vector<int>& tab_indices,
                                 const std::set<std::string>& expanded);

// Popup size for a tab list, clamped to the terminal area.
std::pair<int, int> content_size(const std::vector<Row>& rows, int cols, int lines);

// Column widths for a tab leaf: (name width, status badge width).
std::pair<int, int> tree_tab_width(int inner);

}  // namespace tabgoto
