#include "ui.hpp"

#include <poll.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>

namespace tabgoto {
namespace {

// Nord palette, encoded as RGB for ANSI true-color runs.
constexpr int kText = 0xD8DEE9;
constexpr int kBrightText = 0xECEFF4;
constexpr int kMuted = 0x7B88A1;
constexpr int kDivider = 0x4C566A;
// Standard ANSI colors preserve the original high-contrast selection.
constexpr int kSelection = 46;
constexpr int kBlack = 30;
constexpr int kRed = 0xBF616A;
constexpr int kGreen = 0xA3BE8C;
constexpr int kYellow = 0xEBCB8B;
constexpr int kMagenta = 0xB48EAD;
constexpr int kCyan = 0x88C0D0;

// Bare Escape is ambiguous with the start of an escape sequence, so wait a
// short moment for a following byte before treating it as a key press.
constexpr int kEscapeDelayMs = 25;
constexpr int kSpinnerIntervalMs = 120;
constexpr char kTabShortcuts[] = "1234567890abcde";

// Both pickers use 1-cell braille frames and the same monotonic cadence.
const char* spinner_frame() {
    static const char* frames[] = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"};
    const auto milliseconds = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    return frames[(milliseconds / kSpinnerIntervalMs) % 10];
}

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

Style bold_style() { return Style{kBrightText, -1, true, false}; }
Style dim_style() { return Style{kMuted, -1, false, false}; }
Style selected_style() { return Style{kBlack, kSelection, true, false}; }
Style current_style() { return Style{kCyan, -1, false, false}; }

Style badge_style(StatusKind kind, bool selected) {
    int fg = kMuted;
    switch (kind) {
        case StatusKind::Working: fg = kYellow; break;
        case StatusKind::Idle: fg = kGreen; break;
        case StatusKind::Done: fg = kCyan; break;
        case StatusKind::Blocked: fg = kRed; break;
        case StatusKind::Unknown: fg = kMagenta; break;
        case StatusKind::Other: break;
    }
    if (selected) {
        switch (kind) {
            case StatusKind::Working: fg = 33; break;
            case StatusKind::Idle: fg = 32; break;
            case StatusKind::Done: fg = 34; break;
            case StatusKind::Blocked: fg = 31; break;
            case StatusKind::Unknown: fg = 35; break;
            case StatusKind::Other: fg = kBlack; break;
        }
    }
    return Style{fg, selected ? kSelection : -1, selected, false};
}

std::string sgr(const Style& style) {
    std::string code = "\x1b[0";
    if (style.bold) code += ";1";
    if (style.dim) code += ";2";
    for (int channel = 0; channel < 2; ++channel) {
        const int color = channel == 0 ? style.fg : style.bg;
        if (color >= 0 && color < 256) {
            code += ";" + std::to_string(color);
        } else if (color >= 256) {
            code += channel == 0 ? ";38;2;" : ";48;2;";
            code += std::to_string((color >> 16) & 255) + ";" +
                    std::to_string((color >> 8) & 255) + ";" +
                    std::to_string(color & 255);
        }
    }
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

enum class Key { Char, Up, Down, Left, Right, Enter, Escape, Backspace, CtrlU, Tick, Ignore };

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

    // Waits for an event or animation tick; false on EOF or an input error.
    bool next(Event& event, int timeout_ms = -1) {
        while (true) {
            if (parse(event) == ParseResult::Event) {
                return true;
            }
            // Finish partial key/mouse sequences before scheduling another tick.
            if (buffer_.empty() && timeout_ms >= 0) {
                struct pollfd descriptor {fd_, POLLIN, 0};
                const int ready = poll(&descriptor, 1, timeout_ms);
                if (ready == 0 || (ready < 0 && errno == EINTR)) {
                    event = Event{};
                    event.key = Key::Tick;
                    return true;
                }
                if (ready < 0) return false;
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

// Shared by rendering and hit testing so compact windows keep matching rows.
struct Layout {
    int inner;
    int search_row;
    int list_top;
    int separator_bottom;
    int footer_rows;
    int view_h;

    explicit Layout(const Size& size)
        : inner(size.width - 1),
          search_row(size.height >= 12 ? 2 : 1),
          list_top(search_row + 2),
          separator_bottom(size.height - (size.width >= 60 && size.height >= 10 ? 2 : 1) - 1),
          footer_rows(size.height - separator_bottom - 1),
          view_h(std::max(1, separator_bottom - list_top)) {}
};

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

            if (size.height < 6 || size.width < 24) {
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
            const bool animating = std::any_of(entries_.begin(), entries_.end(), [&](const Entry& entry) {
                return entry.kind == EntryKind::Tab &&
                    status_kind(rows_[static_cast<size_t>(entry.tab_index)].status) == StatusKind::Working;
            });
            while (true) {
                Event event;
                if (!input.next(event, animating ? kSpinnerIntervalMs : -1)) {
                    return Optional<int>();
                }
                if (event.kind == Event::Kind::Key && event.key == Key::Tick) {
                    const Size current_size = terminal_size();
                    if (current_size.width != size.width || current_size.height != size.height) {
                        break;
                    }
                    write_all(render_spinners(size));
                    continue;
                }
                handle(event, size);
                break;
            }
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

    // Add workspace spacing only when the whole list fits without scrolling.
    std::vector<int> visible_entries(int view_h) const {
        int groups = 0;
        for (const Entry& entry : entries_) {
            if (entry.kind == EntryKind::Workspace) ++groups;
        }
        const bool spaced = static_cast<int>(entries_.size()) + std::max(0, groups - 1) <= view_h;
        const int top = spaced ? 0 : scroll_top(cursor_, view_h);
        std::vector<int> visible;
        for (int i = top; i < static_cast<int>(entries_.size()) &&
                          static_cast<int>(visible.size()) < view_h; ++i) {
            if (spaced && i > 0 && entries_[i].kind == EntryKind::Workspace) {
                visible.push_back(-1);
            }
            visible.push_back(i);
        }
        return visible;
    }

    // Animation ticks update only spinner cells, preserving the rest of the popup.
    std::string render_spinners(const Size& size) const {
        std::string frame;
        const Layout layout(size);
        const std::vector<int> visible = visible_entries(layout.view_h);
        const char* spinner = spinner_frame();
        for (size_t i = 0; i < visible.size(); ++i) {
            const int index = visible[i];
            if (index < 0) continue;
            const Entry& entry = entries_[static_cast<size_t>(index)];
            if (entry.kind != EntryKind::Tab) continue;
            const Row& row = rows_[static_cast<size_t>(entry.tab_index)];
            if (status_kind(row.status) != StatusKind::Working) continue;
            put(frame, size.width, layout.list_top + static_cast<int>(i), layout.inner - 10,
                spinner, badge_style(StatusKind::Working, index == cursor_));
        }
        return frame;
    }

    std::string render(const Size& size) const {
        std::string frame;
        const Layout layout(size);
        const int inner = layout.inner;
        const int right = inner - 1;
        const std::vector<int> matching_tabs = filtered_tab_indices(rows_, filter_on_, query_);
        std::set<std::string> workspaces;
        for (const Row& row : rows_) workspaces.insert(row.workspace_id);

        std::string summary;
        if (filter_on_ || !query_.empty()) {
            summary = std::to_string(matching_tabs.size()) + " / " +
                      std::to_string(rows_.size()) + " matches";
        } else {
            summary = std::to_string(rows_.size()) + " tabs / " +
                      std::to_string(workspaces.size()) + " spaces";
        }
        if (inner < 42) {
            summary = std::to_string(matching_tabs.size()) + "/" + std::to_string(rows_.size());
        }
        put(frame, size.width, 0, 1, "TAB GOTO", bold_style());
        put(frame, size.width, 0, right - static_cast<int>(summary.size()), summary, dim_style());

        const std::string filter_label = filter_on_ ? "[status]" : "";
        const int search_width = right - 3 - static_cast<int>(filter_label.size()) -
                                 (filter_on_ ? 2 : 0);
        std::string search = query_;
        if (query_mode_) {
            search += "█";
        } else if (search.empty()) {
            search = "Search tabs...";
        }
        put(frame, size.width, layout.search_row, 1, "/", current_style());
        put(frame, size.width, layout.search_row, 3, fit(search, search_width),
            query_mode_ ? current_style() : dim_style());
        if (filter_on_) {
            put(frame, size.width, layout.search_row,
                right - static_cast<int>(filter_label.size()), filter_label, current_style());
        }
        const std::string separator = repeat("─", std::max(0, inner - 2));
        const Style divider{kDivider, -1, false, false};
        put(frame, size.width, layout.search_row + 1, 1, separator, divider);

        // Shortcut numbers follow expanded tabs, including entries outside the viewport.
        std::map<int, char> tab_ordinal;
        int ordinal = 0;
        for (size_t i = 0; i < entries_.size(); ++i) {
            if (entries_[i].kind == EntryKind::Tab && ++ordinal <= 15) {
                tab_ordinal[static_cast<int>(i)] = kTabShortcuts[ordinal - 1];
            }
        }

        if (entries_.empty()) {
            const std::string message = query_.empty() ? "No matches. f: reset status" :
                                                        "No matches. /: edit search";
            put(frame, size.width, layout.list_top, 2, fit(message, inner - 3), dim_style());
        }

        const std::vector<int> visible = visible_entries(layout.view_h);
        for (size_t row_i = 0; row_i < visible.size(); ++row_i) {
            const int entry_index = visible[row_i];
            if (entry_index < 0) continue;
            const Entry& entry = entries_[static_cast<size_t>(entry_index)];
            const bool selected = entry_index == cursor_;
            const int y = layout.list_top + static_cast<int>(row_i);
            const int background = selected ? kSelection : -1;
            const Style base{selected ? kBlack : kText, background, selected, false};
            const Style muted{selected ? kBlack : kMuted, background, false, false};
            const Style accent{selected ? kBlack : kCyan, background, true, false};

            if (selected) {
                put(frame, size.width, y, 0, repeat(" ", inner), selected_style());
            }
            if (entry.kind == EntryKind::Workspace) {
                const std::string count = std::to_string(entry.count) +
                                          (entry.count == 1 ? " tab" : " tabs");
                const int count_at = right - static_cast<int>(count.size());
                put(frame, size.width, y, 1, entry.expanded ? "▾" : "▸", accent);
                put(frame, size.width, y, 3, fit(entry.label, count_at - 5),
                    Style{selected ? kBlack : kBrightText, background, true, false});
                put(frame, size.width, y, count_at, count, muted);
                continue;
            }

            const Row& row = rows_[static_cast<size_t>(entry.tab_index)];
            const int name_at = 10;
            const int status_at = right - 7;
            const int name_width = status_at - name_at - 4;
            if (selected) put(frame, size.width, y, 1, ">", accent);
            const auto number = tab_ordinal.find(entry_index);
            if (number != tab_ordinal.end()) {
                put(frame, size.width, y, 3, std::string(1, number->second),
                    selected ? accent : muted);
            }
            put(frame, size.width, y, name_at, fit(strip_num_prefix(row.tab), name_width),
                base);
            if (row.focused) {
                put(frame, size.width, y, 6, "●",
                    Style{selected ? kBlack : 36, background, true, false});
            } else if (last_id_.has_value() && *last_id_ == row.tab_id) {
                put(frame, size.width, y, 8, "○",
                    Style{selected ? kBlack : 33, background, true, false});
            }
            put(frame, size.width, y, status_at, status_badge(row.status),
                badge_style(status_kind(row.status), selected));
        }

        put(frame, size.width, layout.separator_bottom, 1, separator, divider);
        const int footer_row = layout.separator_bottom + 1;
        const bool workspace_selected = !entries_.empty() &&
            entries_[static_cast<size_t>(cursor_)].kind == EntryKind::Workspace;
        const std::string enter_hint = workspace_selected ? "Enter fold" : "Enter switch";
        const std::string escape_hint = query_mode_ ? "Esc done" :
                                       (query_.empty() ? "Esc close" : "Esc clear");
        std::string help;
        std::string extra;
        if (query_mode_) {
            help = "Up/Down move   " + enter_hint;
            extra = "Ctrl-U clear   Esc leave input";
        } else {
            help = "j/k move   " + enter_hint + "   / search   f status";
            extra = "1-9,0,a-e jump   n last   h/l fold   " + escape_hint;
        }
        if (layout.footer_rows == 2) {
            put(frame, size.width, footer_row, 1, fit(help, inner - 2), dim_style());
            put(frame, size.width, footer_row + 1, 1, fit(extra, inner - 2), dim_style());
        } else {
            help = enter_hint + (query_mode_ ? "  " : "  / search  ") + escape_hint;
            if (inner < 34) {
                help = workspace_selected ? "Enter fold" : "Enter pick";
                help += query_mode_ ? "  Esc done" : "  / search";
            }
            put(frame, size.width, footer_row, 1, fit(help, inner - 2), dim_style());
        }
        return "\x1b[2J" + frame + render_spinners(size);
    }

    void handle(const Event& event, const Size& size) {
        if (event.kind == Event::Kind::Mouse) {
            pending_g_ = false;
            const Layout layout(size);
            const std::vector<int> visible = visible_entries(layout.view_h);
            const int my = event.y;
            int target = -1;
            if (my >= layout.list_top && my < layout.list_top + static_cast<int>(visible.size())) {
                target = visible[static_cast<size_t>(my - layout.list_top)];
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
        const char* shortcut = std::strchr(kTabShortcuts, ch);
        if (shortcut != nullptr) {
            jump_to_visible_tab(static_cast<int>(shortcut - kTabShortcuts) + 1);
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
