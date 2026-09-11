#include "model.hpp"

#include <algorithm>
#include <cctype>
#include <map>

namespace tabgoto {
namespace {

// Popup floor and trailing slack: the picker stays comfortably wider than its
// content so tab names are not cramped, even in a session with short labels.
constexpr int kMinPopupWidth = 60;
constexpr int kPopupWidthPadding = 14;

// Layout of a tab leaf:
//   pad(1) + branch(3) + num(2) + cur(2) + last(2) + name + gap(2) + status(7)
constexpr int kFixedLeafColumns = 19;
constexpr int kStatusWidth = 7;
constexpr int kMinNameWidth = 12;

bool is_space(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

}  // namespace

size_t utf8_length(StringView text) {
    size_t count = 0;
    for (const char c : text) {
        // Continuation bytes (10xxxxxx) are part of the previous character.
        if ((static_cast<unsigned char>(c) & 0xC0) != 0x80) {
            ++count;
        }
    }
    return count;
}

std::string utf8_prefix(StringView text, size_t max_chars) {
    size_t chars = 0;
    size_t bytes = 0;
    while (bytes < text.size() && chars < max_chars) {
        ++bytes;
        while (bytes < text.size() && (static_cast<unsigned char>(text[bytes]) & 0xC0) == 0x80) {
            ++bytes;
        }
        ++chars;
    }
    return std::string(text.data(), bytes);
}

std::string repeat(StringView unit, int times) {
    std::string out;
    if (times <= 0) {
        return out;
    }
    out.reserve(unit.size() * static_cast<size_t>(times));
    for (int i = 0; i < times; ++i) {
        out.append(unit.data(), unit.size());
    }
    return out;
}

std::string fit(StringView text, int width) {
    if (width <= 0) {
        return std::string();
    }
    const size_t length = utf8_length(text);
    if (length <= static_cast<size_t>(width)) {
        std::string out = to_string(text);
        out.append(static_cast<size_t>(width) - length, ' ');
        return out;
    }
    if (width == 1) {
        return utf8_prefix(text, 1);
    }
    return utf8_prefix(text, static_cast<size_t>(width) - 1) + ".";
}

std::string trim(StringView text) {
    size_t begin = 0;
    size_t end = text.size();
    while (begin < end && is_space(text[begin])) ++begin;
    while (end > begin && is_space(text[end - 1])) --end;
    return std::string(text.data() + begin, end - begin);
}

std::string to_lower_ascii(StringView text) {
    std::string out = to_string(text);
    for (size_t i = 0; i < out.size(); ++i) {
        out[i] = static_cast<char>(std::tolower(static_cast<unsigned char>(out[i])));
    }
    return out;
}

std::string strip_num_prefix(StringView tab_label) {
    const std::string text = to_string(tab_label);
    size_t digits = 0;
    while (digits < text.size() && std::isdigit(static_cast<unsigned char>(text[digits]))) {
        ++digits;
    }
    if (digits == 0 || digits >= text.size() || !is_space(text[digits])) {
        return text;
    }
    const std::string rest = trim(text.substr(digits));
    return rest.empty() ? text : rest;
}

StatusKind status_kind(StringView status) {
    const std::string key = to_lower_ascii(trim(status));
    if (key == "working") return StatusKind::Working;
    if (key == "idle") return StatusKind::Idle;
    if (key == "done") return StatusKind::Done;
    if (key == "blocked") return StatusKind::Blocked;
    if (key == "unknown") return StatusKind::Unknown;
    return StatusKind::Other;
}

std::string status_badge(StringView status) {
    switch (status_kind(status)) {
        case StatusKind::Working: return "working";
        case StatusKind::Idle: return "idle   ";
        case StatusKind::Done: return "done   ";
        case StatusKind::Blocked: return "blocked";
        case StatusKind::Unknown: return "?      ";
        case StatusKind::Other: break;
    }
    const std::string raw = status.empty() ? "?" : to_string(status);
    return fit(utf8_prefix(raw, kStatusWidth), kStatusWidth);
}

bool is_interesting_status(StringView status) {
    const StatusKind kind = status_kind(status);
    return kind != StatusKind::Idle && kind != StatusKind::Unknown;
}

std::vector<Row> rows_from_json(const Json& tab_result, const Json* workspace_result) {
    std::map<std::string, std::string> labels;
    if (workspace_result != nullptr && workspace_result->is_object()) {
        const Json* list = workspace_result->find("workspaces");
        if (list != nullptr && list->is_array()) {
            for (const Json& ws : list->items()) {
                if (!ws.is_object()) {
                    continue;
                }
                const Json* wid = ws.find("workspace_id");
                if (wid == nullptr || !wid->is_string() || wid->as_string().empty()) {
                    continue;
                }
                labels[wid->as_string()] = json_string_or(ws, "label", wid->as_string());
            }
        }
    }

    std::vector<Row> rows;
    const Json* tabs = tab_result.is_object() ? tab_result.find("tabs") : nullptr;
    if (tabs == nullptr || !tabs->is_array()) {
        return rows;
    }

    for (const Json& tab : tabs->items()) {
        if (!tab.is_object()) {
            continue;
        }
        const Json* tid = tab.find("tab_id");
        if (tid == nullptr || !tid->is_string() || tid->as_string().empty()) {
            continue;
        }
        Row row;
        row.tab_id = tid->as_string();
        row.workspace_id = json_string_or(tab, "workspace_id", "?");

        const auto label = labels.find(row.workspace_id);
        row.workspace = label == labels.end() ? row.workspace_id : label->second;
        row.tab = json_string_or(tab, "label", row.tab_id);

        const Json* status = tab.find("agent_status");
        row.status = (status != nullptr && status->is_string()) ? status->as_string() : "";

        const Json* focused = tab.find("focused");
        row.focused = focused != nullptr && focused->is_bool() && focused->as_bool();

        rows.push_back(std::move(row));
    }
    return rows;
}

int initial_index(const std::vector<Row>& rows) {
    for (size_t i = 0; i < rows.size(); ++i) {
        if (rows[i].focused) {
            return static_cast<int>(i);
        }
    }
    return 0;
}

std::vector<int> filtered_tab_indices(const std::vector<Row>& rows, bool filter_on,
                                      StringView query) {
    const std::string needle = to_lower_ascii(trim(query));
    std::vector<int> indices;
    for (size_t i = 0; i < rows.size(); ++i) {
        const Row& row = rows[i];
        if (filter_on && !is_interesting_status(row.status)) {
            continue;
        }
        if (!needle.empty()) {
            const std::string haystack =
                to_lower_ascii(row.tab + " " + row.workspace + " " + row.status);
            if (haystack.find(needle) == std::string::npos) {
                continue;
            }
        }
        indices.push_back(static_cast<int>(i));
    }
    return indices;
}

std::vector<Entry> build_entries(const std::vector<Row>& rows,
                                 const std::vector<int>& tab_indices,
                                 const std::set<std::string>& expanded) {
    // Group rows by workspace while preserving first-seen workspace order.
    std::vector<std::string> order;
    std::map<std::string, std::vector<int>> by_workspace;
    std::map<std::string, std::string> labels;
    for (const int i : tab_indices) {
        const Row& row = rows[static_cast<size_t>(i)];
        if (by_workspace.find(row.workspace_id) == by_workspace.end()) {
            order.push_back(row.workspace_id);
        }
        by_workspace[row.workspace_id].push_back(i);
        labels[row.workspace_id] = row.workspace;
    }

    std::vector<Entry> entries;
    for (const std::string& wid : order) {
        const auto group = by_workspace.find(wid);
        if (group == by_workspace.end() || group->second.empty()) {
            continue;
        }
        const std::vector<int>& indices = group->second;
        const bool is_open = expanded.count(wid) > 0;

        Entry node;
        node.kind = EntryKind::Workspace;
        node.workspace_id = wid;
        const auto label = labels.find(wid);
        node.label = label == labels.end() ? wid : label->second;
        node.count = static_cast<int>(indices.size());
        node.expanded = is_open;
        entries.push_back(std::move(node));

        if (!is_open) {
            continue;
        }
        for (size_t n = 0; n < indices.size(); ++n) {
            Entry leaf;
            leaf.kind = EntryKind::Tab;
            leaf.workspace_id = wid;
            leaf.tab_index = indices[n];
            leaf.is_last_child = n + 1 == indices.size();
            entries.push_back(std::move(leaf));
        }
    }
    return entries;
}

std::pair<int, int> content_size(const std::vector<Row>& rows, int cols, int lines) {
    std::set<std::string> groups;
    for (const Row& row : rows) {
        groups.insert(row.workspace_id);
    }
    // Four picker chrome rows plus the two outer border rows.
    const int wanted = static_cast<int>(rows.size()) + static_cast<int>(groups.size()) + 6;
    const int height = std::min(std::max(wanted, 10), lines);

    int max_line = 21;
    for (const Row& row : rows) {
        const int line = 2 + static_cast<int>(utf8_length(row.tab)) + 2 +
                         static_cast<int>(utf8_length(row.workspace)) + 2 +
                         std::max(4, static_cast<int>(utf8_length(row.status)));
        max_line = std::max(max_line, line);
    }
    const int width = std::min(std::max(max_line + kPopupWidthPadding, kMinPopupWidth),
                               cols * 92 / 100);
    return {width, height};
}

std::pair<int, int> tree_tab_width(int inner) {
    const int name_width = std::max(kMinNameWidth, inner - kFixedLeafColumns);
    return {name_width, kStatusWidth};
}

}  // namespace tabgoto
