#include "ui.hpp"

#include <poll.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>

namespace tabgoto {
namespace {

// ANSI SGR foreground/background codes.
constexpr int kBlack = 30;
constexpr int kRed = 31;
constexpr int kGreen = 32;
constexpr int kYellow = 33;
constexpr int kBlue = 34;
constexpr int kMagenta = 35;
constexpr int kCyan = 36;
constexpr int kWhite = 37;
constexpr int kCyanBackground = 46;

// Bare Escape is ambiguous with the start of an escape sequence, so wait a
// short moment for a following byte before treating it as a key press.
constexpr int kEscapeDelayMs = 25;

struct Size {
    int width;
    int height;

    Size() : width(80), height(24) {}
    Size(int columns, int rows) : width(columns), height(rows) {}
};

struct Style {
    int fg;
    int bg;
    bool bold;
    bool dim;

    // C++11 does not allow aggregate initialization for classes with default
    // member initializers.
    Style() : fg(-1), bg(-1), bold(false), dim(false) {}
    Style(int foreground, int background, bool is_bold, bool is_dim)
        : fg(foreground), bg(background), bold(is_bold), dim(is_dim) {}
};

Style bold_style() { return Style{-1, -1, true, false}; }
Style dim_style() { return Style{-1, -1, false, true}; }
Style selected_style() { return Style{kBlack, kCyanBackground, true, false}; }
Style tree_style() { return Style{kWhite, -1, false, true}; }
Style tree_selected_style() { return Style{kBlack, kCyanBackground, false, true}; }
Style current_style() { return Style{kCyan, -1, true, false}; }
Style last_style() { return Style{kYellow, -1, true, false}; }

Style badge_style(StatusKind kind, bool selected) {
    int fg = kWhite;
    switch (kind) {
        case StatusKind::Working: fg = kYellow; break;
        case StatusKind::Idle: fg = kGreen; break;
        case StatusKind::Done: fg = selected ? kBlue : kCyan; break;
        case StatusKind::Blocked: fg = kRed; break;
        case StatusKind::Unknown: fg = kMagenta; break;
        case StatusKind::Other: fg = selected ? kBlack : kWhite; break;
    }
    return Style{fg, selected ? kCyanBackground : -1, true, false};
}

std::string sgr(const Style& style) {
    std::string code = "\x1b[0";
    if (style.bold) code += ";1";
    if (style.dim) code += ";2";
    if (style.fg >= 0) code += ";" + std::to_string(style.fg);
    if (style.bg >= 0) code += ";" + std::to_string(style.bg);
    code += "m";
    return code;
}

// Appends a positioned, styled run. Text is clipped before the last column so
// writing there cannot scroll the popup.
void put(std::string& frame, int screen_width, int y, int x, StringView text,
         const Style& style) {
    if (y < 0 || x < 0 || x >= screen_width) {
        return;
    }
    const int available = screen_width - x - 1;
    if (available <= 0) {
        return;
    }
    const std::string chunk = utf8_prefix(text, static_cast<size_t>(available));
    if (chunk.empty()) {
        return;
    }
    frame += "\x1b[" + std::to_string(y + 1) + ";" + std::to_string(x + 1) + "H";
    frame += sgr(style);
    frame += chunk;
    frame += "\x1b[0m";
}

Size terminal_size() {
    struct winsize window {};
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &window) == 0 && window.ws_col > 0 && window.ws_row > 0) {
        return Size{window.ws_col, window.ws_row};
    }
    return Size{};
}

void write_all(StringView text) {
    size_t written = 0;
    while (written < text.size()) {
        const ssize_t n = ::write(STDOUT_FILENO, text.data() + written, text.size() - written);
        if (n > 0) {
            written += static_cast<size_t>(n);
            continue;
        }
        if (n < 0 && errno == EINTR) {
            continue;
        }
        break;
    }
}

// Puts the terminal in raw mode with the alternate screen and SGR mouse
// reporting enabled; restores everything on destruction.
class Terminal {
public:
    Terminal() {
        if (tcgetattr(STDIN_FILENO, &saved_) != 0) {
            return;
        }
        struct termios raw = saved_;
        raw.c_lflag &= static_cast<tcflag_t>(~(ECHO | ICANON | ISIG | IEXTEN));
        raw.c_iflag &= static_cast<tcflag_t>(~(IXON | ICRNL | BRKINT | INPCK | ISTRIP));
        raw.c_cc[VMIN] = 1;
        raw.c_cc[VTIME] = 0;
        // TCSANOW keeps keystrokes typed while the popup is opening.
        if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) != 0) {
            return;
        }
        active_ = true;
        // 1049 alternate screen, 25 hide cursor, 1003 any-motion tracking, 1006 SGR coords.
        write_all("\x1b[?1049h\x1b[?25l\x1b[?1003h\x1b[?1006h");
    }

    ~Terminal() {
        if (!active_) {
            return;
        }
        write_all("\x1b[?1006l\x1b[?1003l\x1b[?25h\x1b[?1049l");
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved_);
    }

    Terminal(const Terminal&) = delete;
    Terminal& operator=(const Terminal&) = delete;

    bool active() const { return active_; }

private:
    struct termios saved_ {};
    bool active_ = false;
};

enum class Key { Char, Up, Down, Left, Right, Enter, Escape, Backspace, CtrlU, Ignore };

struct Event {
    enum class Kind { Key, Mouse };
    Kind kind = Kind::Key;
    Key key = Key::Ignore;
    char ch = 0;
    // Mouse, converted to 0-based screen cells.
    int x = 0;
    int y = 0;
    bool press = false;
    bool motion = false;
};

// Decodes a byte stream into key and SGR mouse events.
class Input {
public:
    explicit Input(int fd) : fd_(fd) {}

    // Blocks until one complete event is available; false on EOF.
    bool next(Event& event) {
        while (true) {
            if (parse(event) == ParseResult::Event) {
                return true;
            }
            if (!fill(-1)) {
                return false;
            }
        }
    }

private:
    enum class ParseResult { Event, NeedMore };

    // Appends newly available bytes. A negative timeout blocks; otherwise it
    // waits at most `timeout_ms` and reports false when nothing arrived.
    bool fill(int timeout_ms) {
        if (timeout_ms >= 0) {
            struct pollfd descriptor {fd_, POLLIN, 0};
            const int ready = poll(&descriptor, 1, timeout_ms);
            if (ready <= 0) {
                return false;
            }
        }
        char chunk[256];
        while (true) {
            const ssize_t n = ::read(fd_, chunk, sizeof chunk);
            if (n > 0) {
                buffer_.append(chunk, static_cast<size_t>(n));
                return true;
            }
            if (n < 0 && errno == EINTR) {
                continue;
            }
            return false;
        }
    }

    ParseResult parse(Event& event) {
        if (buffer_.empty()) {
            return ParseResult::NeedMore;
        }

        const auto first = static_cast<unsigned char>(buffer_[0]);
        if (first != 0x1b) {
            buffer_.erase(0, 1);
            event = Event{};
            switch (first) {
                case 13: case 10: event.key = Key::Enter; return ParseResult::Event;
                case 127: case 8: event.key = Key::Backspace; return ParseResult::Event;
                case 21: event.key = Key::CtrlU; return ParseResult::Event;
                default:
                    if (first >= 32 && first <= 126) {
                        event.key = Key::Char;
                        event.ch = static_cast<char>(first);
                    }
                    return ParseResult::Event;
            }
        }

        // A lone Escape only counts once nothing follows within the delay.
        if (buffer_.size() == 1) {
            if (fill(kEscapeDelayMs)) {
                return ParseResult::NeedMore;
            }
            buffer_.erase(0, 1);
            event = Event{};
            event.key = Key::Escape;
            return ParseResult::Event;
        }

        if (buffer_[1] == '[') {
            if (buffer_.size() >= 3 && buffer_[2] == '<') {
                return parse_sgr_mouse(event);
            }
            const size_t end = csi_end();
            if (end == std::string::npos) {
                return ParseResult::NeedMore;
            }
            const char final = buffer_[end];
            // Legacy X10 mouse report: ESC [ M plus three raw bytes. Terminals
            // without SGR support report this way, and the payload would
            // otherwise be misread as keystrokes.
            if (final == 'M') {
                return parse_legacy_mouse(event, end);
            }
            buffer_.erase(0, end + 1);
            event = Event{};
            event.key = arrow_key(final);
            return ParseResult::Event;
        }

        if (buffer_[1] == 'O') {
            if (buffer_.size() < 3) {
                return ParseResult::NeedMore;
            }
            const char final = buffer_[2];
            buffer_.erase(0, 3);
            event = Event{};
            event.key = arrow_key(final);
            return ParseResult::Event;
        }

        // Unknown escape: emit Escape and keep the remaining bytes.
        buffer_.erase(0, 1);
        event = Event{};
        event.key = Key::Escape;
        return ParseResult::Event;
    }

    // Index of the CSI final byte (0x40..0x7e), or npos when incomplete.
    size_t csi_end() const {
        size_t i = 2;
        while (i < buffer_.size()) {
            const auto c = static_cast<unsigned char>(buffer_[i]);
            if (c >= 0x40 && c <= 0x7e) {
                return i;
            }
            ++i;
        }
        return std::string::npos;
    }

    static Key arrow_key(char final) {
        switch (final) {
            case 'A': return Key::Up;
            case 'B': return Key::Down;
            case 'C': return Key::Right;
            case 'D': return Key::Left;
            default: return Key::Ignore;
        }
    }

    // ESC [ M <button> <column> <row>, each byte offset by 32.
    ParseResult parse_legacy_mouse(Event& event, size_t end) {
        if (buffer_.size() < end + 4) {
            return ParseResult::NeedMore;
        }
        const auto decode = [](char raw) {
            return static_cast<int>(static_cast<unsigned char>(raw)) - 32;
        };
        const int buttons = decode(buffer_[end + 1]);
        event = Event{};
        event.kind = Event::Kind::Mouse;
        event.x = decode(buffer_[end + 2]) - 1;
        event.y = decode(buffer_[end + 3]) - 1;
        event.motion = (buttons & 32) != 0;
        event.press = (buttons & 3) == 0 && !event.motion;
        buffer_.erase(0, end + 4);
        return ParseResult::Event;
    }

    // Format: ESC [ < button ; column ; row (M | m). M is press, m is release.
    ParseResult parse_sgr_mouse(Event& event) {
        const size_t end = buffer_.find_first_of("Mm", 3);
        if (end == std::string::npos) {
            return ParseResult::NeedMore;
        }

        long values[3] = {0, 0, 0};
        int index = 0;
        for (size_t i = 3; i < end && index < 3; ++i) {
            const char c = buffer_[i];
            if (c == ';') {
                ++index;
            } else if (c >= '0' && c <= '9') {
                values[index] = values[index] * 10 + (c - '0');
            }
        }
        const char terminator = buffer_[end];
        buffer_.erase(0, end + 1);

        const long buttons = values[0];
        event = Event{};
        event.kind = Event::Kind::Mouse;
        event.x = static_cast<int>(values[1]) - 1;
        event.y = static_cast<int>(values[2]) - 1;
        event.motion = (buttons & 32) != 0;
        event.press = terminator == 'M' && (buttons & 3) == 0 && !event.motion;
        return ParseResult::Event;
    }

    int fd_;
    std::string buffer_;
};

int scroll_top(int cursor, int view_h) {
    int top = 0;
    if (cursor >= top + view_h) {
        top = cursor - view_h + 1;
    }
    if (cursor < top) {
        top = cursor;
    }
    return top;
}

class Picker {
public:
    Picker(const std::vector<Row>& rows, int start, Optional<std::string> last_id)
        : rows_(rows), last_id_(std::move(last_id)) {
        start_index_ = std::max(0, std::min(start, static_cast<int>(rows_.size()) - 1));
        // Default: every workspace expanded; h/l still folds.
        for (const Row& row : rows_) {
            expanded_.insert(row.workspace_id);
        }
        rebuild();
        for (size_t i = 0; i < entries_.size(); ++i) {
            if (entries_[i].kind == EntryKind::Tab && entries_[i].tab_index == start_index_) {
                cursor_ = static_cast<int>(i);
                break;
            }
        }
    }

    Optional<int> run() {
        Terminal terminal;
        if (!terminal.active()) {
            return Optional<int>();
        }
        Input input(STDIN_FILENO);

        while (!finished_) {
            rebuild();
            const Size size = terminal_size();

            if (size.height < 4 || size.width < 16) {
                std::string frame;
                put(frame, size.width, 0, 0, "window too small", bold_style());
                write_all(frame);
                pending_g_ = false;
                Event event;
                if (!input.next(event)) {
                    return Optional<int>();
                }
                if (event.kind == Event::Kind::Key &&
                    (event.key == Key::Escape ||
                     (event.key == Key::Char && event.ch == 'q'))) {
                    return Optional<int>();
                }
                continue;
            }

            write_all(render(size));
            Event event;
            if (!input.next(event)) {
                return Optional<int>();
            }
            handle(event, size);
        }
        return result_;
    }

private:
    void rebuild() {
        const std::vector<int> tabs = filtered_tab_indices(rows_, filter_on_, query_);
        entries_ = build_entries(rows_, tabs, expanded_);
        if (entries_.empty()) {
            cursor_ = 0;
            return;
        }
        cursor_ = std::max(0, std::min(cursor_, static_cast<int>(entries_.size()) - 1));
    }

    void snap_to_workspace(const std::string& workspace_id) {
        const std::vector<int> tabs = filtered_tab_indices(rows_, filter_on_, query_);
        const std::vector<Entry> entries = build_entries(rows_, tabs, expanded_);
        for (size_t i = 0; i < entries.size(); ++i) {
            if (entries[i].kind == EntryKind::Workspace &&
                entries[i].workspace_id == workspace_id) {
                cursor_ = static_cast<int>(i);
                return;
            }
        }
        cursor_ = std::max(0, std::min(cursor_, static_cast<int>(entries.size()) - 1));
    }

    std::string render(const Size& size) const {
        std::string frame;
        const int inner = std::max(0, size.width - 1);

        const std::string help =
            query_mode_ ? "/" + query_ + "█  arrows move  esc done  ^u clear"
                        : "j/k · gg/G · 1-9 · n last · / filter · click · h/l fold · enter/space · f · esc";
        put(frame, size.width, 0, 1, fit(help, std::max(0, inner - 1)), dim_style());

        std::string flags;
        if (filter_on_) flags += "F";
        if (!query_.empty()) flags += "/";
        if (!flags.empty()) {
            put(frame, size.width, 0, std::max(0, inner - static_cast<int>(flags.size()) - 1), flags,
                bold_style());
        }

        const std::pair<int, int> widths = tree_tab_width(inner);
        const int name_width = widths.first;
        const int status_width = widths.second;
        const std::string separator = " " + repeat("─", std::max(0, inner - 2));
        put(frame, size.width, 1, 0, fit(separator, inner), dim_style());

        const int list_top = 2;
        const int footer_row = size.height - 1;
        const int separator_bottom = size.height - 2;
        const int view_h = std::max(1, separator_bottom - list_top);

        // 1-9 jump numbers over the visible tab entries.
        std::map<int, int> tab_ordinal;
        int visible_tabs = 0;
        for (size_t i = 0; i < entries_.size(); ++i) {
            if (entries_[i].kind != EntryKind::Tab) {
                continue;
            }
            ++visible_tabs;
            if (visible_tabs <= 9) {
                tab_ordinal[static_cast<int>(i)] = visible_tabs;
            }
        }

        if (entries_.empty()) {
            std::string message = "no matches";
            if (!query_.empty()) {
                message += " — edit / or ^u clear";
            } else if (filter_on_) {
                message += " — press f";
            }
            put(frame, size.width, list_top, 1, fit(message, std::max(0, inner - 1)), dim_style());
        } else {
            const int top = scroll_top(cursor_, view_h);
            for (int row_i = 0; row_i < view_h; ++row_i) {
                const int entry_index = top + row_i;
                if (entry_index >= static_cast<int>(entries_.size())) {
                    break;
                }
                const Entry& entry = entries_[entry_index];
                const bool selected = entry_index == cursor_;
                const int y = list_top + row_i;

                Style base = bold_style();
                Style tree = tree_style();
                if (selected) {
                    base = selected_style();
                    tree = tree_selected_style();
                    put(frame, size.width, y, 0, repeat(" ", inner), base);
                }

                if (entry.kind == EntryKind::Workspace) {
                    const bool open = entry.expanded;
                    std::string label = entry.label;
                    if (!open) {
                        label += "  (" + std::to_string(entry.count) + ")";
                    }
                    put(frame, size.width, y, 1, open ? "▾ " : "▸ ", tree);
                    put(frame, size.width, y, 3, fit(label, std::max(0, inner - 3)), base);
                    continue;
                }

                const Row& row = rows_[static_cast<size_t>(entry.tab_index)];
                const bool is_current = row.focused;
                const bool is_last =
                    last_id_.has_value() && *last_id_ == row.tab_id && !is_current;
                const std::string name = strip_num_prefix(row.tab);
                // Columns: 1 branch(3) | 4 num(2) | 6 cur(2) | 8 last(2) | 10 name | badge
                const int leaf_name_width =
                    std::max(8, std::min(name_width, inner - 10 - 2 - status_width));
                const int badge_at = 10 + leaf_name_width + 2;

                put(frame, size.width, y, 1, entry.is_last_child ? "└─ " : "├─ ", tree);

                const auto ordinal = tab_ordinal.find(entry_index);
                put(frame, size.width, y, 4,
                    ordinal == tab_ordinal.end() ? "  " : std::to_string(ordinal->second) + " ",
                    selected ? base : tree);

                put(frame, size.width, y, 6, is_current ? "● " : "  ",
                    is_current ? (selected ? base : current_style()) : tree);
                put(frame, size.width, y, 8, is_last ? "○ " : "  ",
                    is_last ? (selected ? base : last_style()) : tree);
                put(frame, size.width, y, 10, fit(name, leaf_name_width), base);

                if (badge_at < inner) {
                    put(frame, size.width, y, badge_at,
                        fit(status_badge(row.status),
                            std::min(status_width, std::max(0, inner - badge_at))),
                        badge_style(status_kind(row.status), selected));
                }
            }
        }

        put(frame, size.width, separator_bottom, 0, separator, dim_style());

        std::string footer;
        if (entries_.empty()) {
            footer = "0/0";
            if (!query_.empty()) {
                footer += " /" + query_;
            }
        } else {
            footer = std::to_string(cursor_ + 1) + "/" + std::to_string(entries_.size());
            if (filter_on_) footer += " F";
            if (!query_.empty()) footer += " /" + query_;
            if (entries_[cursor_].kind == EntryKind::Workspace) {
                const bool open = entries_[cursor_].expanded;
                if (query_mode_) {
                    footer += open ? " ← fold" : " → open";
                } else {
                    footer += open ? " h fold" : " l open";
                }
            }
        }
        put(frame, size.width, footer_row, 0, fit(footer, inner), dim_style());

        return "\x1b[2J" + frame;
    }

    void handle(const Event& event, const Size& size) {
        if (event.kind == Event::Kind::Mouse) {
            pending_g_ = false;
            const int list_top = 2;
            const int view_h = std::max(1, (size.height - 2) - list_top);
            const int top = scroll_top(cursor_, view_h);
            const int my = event.y;
            const bool in_list =
                my >= list_top && my < list_top + view_h && !entries_.empty();
            int target = -1;
            if (in_list) {
                target = top + (my - list_top);
                if (target >= static_cast<int>(entries_.size())) {
                    target = -1;
                }
            }

            // Hovering moves the highlight; pressing activates the row.
            if (target >= 0) {
                cursor_ = target;
            }
            if (event.press && target >= 0) {
                if (const auto picked = activate()) {
                    finish(*picked);
                }
            }
            return;
        }

        if (query_mode_) {
            switch (event.key) {
                case Key::Escape: query_mode_ = false; break;
                case Key::CtrlU: query_.clear(); break;
                case Key::Backspace:
                    if (!query_.empty()) query_.pop_back();
                    break;
                case Key::Up: move_up(); break;
                case Key::Down: move_down(); break;
                case Key::Left: fold_left(); break;
                case Key::Right: fold_right(); break;
                case Key::Enter:
                    if (const auto picked = activate()) finish(*picked);
                    break;
                case Key::Char: query_.push_back(event.ch); break;
                default: break;
            }
            return;
        }

        // A second consecutive g jumps to the first visible tree entry.
        if (event.key == Key::Char && event.ch == 'g') {
            if (pending_g_) {
                cursor_ = 0;
            }
            pending_g_ = !pending_g_;
            return;
        }
        pending_g_ = false;

        switch (event.key) {
            case Key::Char:
                // Space activates like enter; inside the filter query it stays a
                // typed character (see the query_mode_ branch above).
                if (event.ch == ' ') {
                    if (const auto picked = activate()) finish(*picked);
                } else {
                    handle_char(event.ch);
                }
                break;
            case Key::Down: move_down(); break;
            case Key::Up: move_up(); break;
            case Key::Right: fold_right(); break;
            case Key::Left: fold_left(); break;
            case Key::Enter:
                if (const auto picked = activate()) finish(*picked);
                break;
            case Key::Escape:
                if (!query_.empty()) {
                    query_.clear();
                } else {
                    finished_ = true;
                }
                break;
            default: break;
        }
    }

    void handle_char(char ch) {
        switch (ch) {
            case 'G':
                cursor_ = entries_.empty() ? 0 : static_cast<int>(entries_.size()) - 1;
                return;
            case 'j': move_down(); return;
            case 'k': move_up(); return;
            case 'l': fold_right(); return;
            case 'h': fold_left(); return;
            case 'f': case 'F': filter_on_ = !filter_on_; return;
            case '/': query_mode_ = true; return;
            case 'q': finished_ = true; return;
            case 'n': pick_last_tab(); return;
            default: break;
        }
        if (ch >= '1' && ch <= '9') {
            jump_to_visible_tab(ch - '0');
        }
    }

    // `n`: jump straight to the tab visited before the current one.
    void pick_last_tab() {
        if (!last_id_.has_value()) {
            return;
        }
        for (size_t i = 0; i < rows_.size(); ++i) {
            if (rows_[i].tab_id == *last_id_) {
                finish(static_cast<int>(i));
                return;
            }
        }
    }

    void jump_to_visible_tab(int want) {
        int seen = 0;
        for (const Entry& entry : entries_) {
            if (entry.kind != EntryKind::Tab) {
                continue;
            }
            ++seen;
            if (seen == want) {
                finish(entry.tab_index);
                return;
            }
        }
    }

    void move_down() {
        if (!entries_.empty()) {
            cursor_ = (cursor_ + 1) % static_cast<int>(entries_.size());
        }
    }

    void move_up() {
        if (!entries_.empty()) {
            cursor_ = (cursor_ + static_cast<int>(entries_.size()) - 1) %
                      static_cast<int>(entries_.size());
        }
    }

    void fold_right() {
        if (entries_.empty()) {
            return;
        }
        const std::string& workspace_id = entries_[cursor_].workspace_id;
        if (!workspace_id.empty()) {
            expanded_.insert(workspace_id);
        }
    }

    void fold_left() {
        if (entries_.empty()) {
            return;
        }
        const std::string& workspace_id = entries_[cursor_].workspace_id;
        if (workspace_id.empty()) {
            return;
        }
        expanded_.erase(workspace_id);
        snap_to_workspace(workspace_id);
    }

    // Returns the row index when a tab leaf is activated.
    Optional<int> activate() {
        if (entries_.empty()) {
            return Optional<int>();
        }
        const Entry& entry = entries_[cursor_];
        if (entry.kind == EntryKind::Tab) {
            return Optional<int>(entry.tab_index);
        }
        if (entry.workspace_id.empty()) {
            return Optional<int>();
        }
        if (entry.expanded) {
            expanded_.erase(entry.workspace_id);
        } else {
            expanded_.insert(entry.workspace_id);
        }
        return Optional<int>();
    }

    void finish(int picked) {
        result_ = picked;
        finished_ = true;
    }

    const std::vector<Row>& rows_;
    Optional<std::string> last_id_;
    std::set<std::string> expanded_;
    std::vector<Entry> entries_;
    int start_index_ = 0;
    int cursor_ = 0;
    bool filter_on_ = false;
    std::string query_;
    bool query_mode_ = false;
    bool pending_g_ = false;
    bool finished_ = false;
    Optional<int> result_;
};

}  // namespace

Optional<int> pick_index(const std::vector<Row>& rows, int start,
                         const Optional<std::string>& last_id) {
    Picker picker(rows, start, last_id);
    return picker.run();
}

}  // namespace tabgoto
