#include "json.hpp"

#include <cmath>
#include <cstdlib>
#include <cstring>

namespace tabgoto {
namespace {

// Guards against stack exhaustion on pathological nesting.
constexpr int kMaxDepth = 64;

void append_utf8(std::string& out, unsigned int codepoint) {
    if (codepoint <= 0x7F) {
        out.push_back(static_cast<char>(codepoint));
    } else if (codepoint <= 0x7FF) {
        out.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
        out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else if (codepoint <= 0xFFFF) {
        out.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
        out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else {
        out.push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
        out.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    }
}

}  // namespace

class JsonParser {
public:
    explicit JsonParser(StringView text) : text_(text) {}

    bool parse(Json& out) {
        skip_whitespace();
        if (!parse_value(out, 0)) {
            return false;
        }
        skip_whitespace();
        if (position_ != text_.size()) {
            error_ = "trailing data after JSON value";
            return false;
        }
        return true;
    }

    const std::string& error() const { return error_; }

private:
    bool at_end() const { return position_ >= text_.size(); }
    char peek() const { return text_[position_]; }

    void skip_whitespace() {
        while (!at_end()) {
            const char c = peek();
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                ++position_;
            } else {
                break;
            }
        }
    }

    bool fail(const std::string& message) {
        if (error_.empty()) {
            error_ = message + " at offset " + std::to_string(position_);
        }
        return false;
    }

    bool expect(char c) {
        if (at_end() || peek() != c) {
            return fail(std::string("expected '") + c + "'");
        }
        ++position_;
        return true;
    }

    bool literal(StringView word) {
        if (word.size() > text_.size() - position_) {
            return fail("invalid literal");
        }
        for (size_t i = 0; i < word.size(); ++i) {
            if (text_[position_ + i] != word[i]) {
                return fail("invalid literal");
            }
        }
        position_ += word.size();
        return true;
    }

    bool parse_value(Json& out, int depth) {
        if (depth > kMaxDepth) {
            return fail("JSON nested too deeply");
        }
        if (at_end()) {
            return fail("unexpected end of input");
        }
        switch (peek()) {
            case '{':
                return parse_object(out, depth);
            case '[':
                return parse_array(out, depth);
            case '"':
                out.type_ = Json::Type::String;
                return parse_string(out.string_);
            case 't':
                if (!literal("true")) return false;
                out.type_ = Json::Type::Bool;
                out.bool_ = true;
                return true;
            case 'f':
                if (!literal("false")) return false;
                out.type_ = Json::Type::Bool;
                out.bool_ = false;
                return true;
            case 'n':
                if (!literal("null")) return false;
                out.type_ = Json::Type::Null;
                return true;
            default:
                return parse_number(out);
        }
    }

    bool parse_object(Json& out, int depth) {
        if (!expect('{')) return false;
        out.type_ = Json::Type::Object;
        out.object_.clear();

        skip_whitespace();
        if (!at_end() && peek() == '}') {
            ++position_;
            return true;
        }
        while (true) {
            skip_whitespace();
            std::string key;
            if (!parse_string(key)) return false;
            skip_whitespace();
            if (!expect(':')) return false;
            skip_whitespace();
            Json value;
            if (!parse_value(value, depth + 1)) return false;
            out.object_[std::move(key)] = std::move(value);

            skip_whitespace();
            if (at_end()) return fail("unterminated object");
            if (peek() == ',') {
                ++position_;
                continue;
            }
            if (peek() == '}') {
                ++position_;
                return true;
            }
            return fail("expected ',' or '}'");
        }
    }

    bool parse_array(Json& out, int depth) {
        if (!expect('[')) return false;
        out.type_ = Json::Type::Array;
        out.array_.clear();

        skip_whitespace();
        if (!at_end() && peek() == ']') {
            ++position_;
            return true;
        }
        while (true) {
            skip_whitespace();
            Json value;
            if (!parse_value(value, depth + 1)) return false;
            out.array_.push_back(std::move(value));

            skip_whitespace();
            if (at_end()) return fail("unterminated array");
            if (peek() == ',') {
                ++position_;
                continue;
            }
            if (peek() == ']') {
                ++position_;
                return true;
            }
            return fail("expected ',' or ']'");
        }
    }

    bool parse_hex4(unsigned int& out) {
        if (position_ + 4 > text_.size()) {
            return fail("truncated \\u escape");
        }
        unsigned int value = 0;
        for (int i = 0; i < 4; ++i) {
            const char c = text_[position_ + static_cast<size_t>(i)];
            value <<= 4;
            if (c >= '0' && c <= '9') {
                value |= static_cast<unsigned int>(c - '0');
            } else if (c >= 'a' && c <= 'f') {
                value |= static_cast<unsigned int>(c - 'a' + 10);
            } else if (c >= 'A' && c <= 'F') {
                value |= static_cast<unsigned int>(c - 'A' + 10);
            } else {
                return fail("invalid \\u escape");
            }
        }
        position_ += 4;
        out = value;
        return true;
    }

    bool parse_string(std::string& out) {
        if (!expect('"')) return false;
        out.clear();
        while (true) {
            if (at_end()) return fail("unterminated string");
            const char c = text_[position_++];
            if (c == '"') return true;
            if (c != '\\') {
                out.push_back(c);
                continue;
            }
            if (at_end()) return fail("unterminated escape");
            const char escape = text_[position_++];
            switch (escape) {
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                case '/': out.push_back('/'); break;
                case 'b': out.push_back('\b'); break;
                case 'f': out.push_back('\f'); break;
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                case 'u': {
                    unsigned int codepoint = 0;
                    if (!parse_hex4(codepoint)) return false;
                    // Combine a UTF-16 surrogate pair into one code point.
                    if (codepoint >= 0xD800 && codepoint <= 0xDBFF && position_ + 1 < text_.size() &&
                        text_[position_] == '\\' && text_[position_ + 1] == 'u') {
                        const size_t saved = position_;
                        position_ += 2;
                        unsigned int low = 0;
                        if (!parse_hex4(low)) return false;
                        if (low >= 0xDC00 && low <= 0xDFFF) {
                            codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00);
                        } else {
                            position_ = saved;
                        }
                    }
                    append_utf8(out, codepoint);
                    break;
                }
                default:
                    return fail("invalid escape sequence");
            }
        }
    }

    bool parse_number(Json& out) {
        const size_t start = position_;
        if (!at_end() && peek() == '-') ++position_;
        if (at_end() || !is_digit(peek())) return fail("invalid number");
        if (peek() == '0') {
            // JSON forbids leading zeros, so a lone 0 cannot start a longer run.
            ++position_;
        } else {
            while (!at_end() && is_digit(peek())) ++position_;
        }
        if (!at_end() && peek() == '.') {
            ++position_;
            if (at_end() || !is_digit(peek())) return fail("invalid number fraction");
            while (!at_end() && is_digit(peek())) ++position_;
        }
        if (!at_end() && (peek() == 'e' || peek() == 'E')) {
            ++position_;
            if (!at_end() && (peek() == '+' || peek() == '-')) ++position_;
            if (at_end() || !is_digit(peek())) return fail("invalid number exponent");
            while (!at_end() && is_digit(peek())) ++position_;
        }

        const std::string token = to_string(text_.substr(start, position_ - start));
        char* end = nullptr;
        const double value = std::strtod(token.c_str(), &end);
        if (end == nullptr || *end != '\0') {
            return fail("invalid number");
        }
        out.type_ = Json::Type::Number;
        out.number_ = value;
        return true;
    }

    static bool is_digit(char c) { return c >= '0' && c <= '9'; }

    StringView text_;
    size_t position_ = 0;
    std::string error_;
};

bool Json::parse(StringView text, Json& out, std::string& error) {
    JsonParser parser(text);
    Json parsed;
    if (!parser.parse(parsed)) {
        error = parser.error();
        return false;
    }
    out = std::move(parsed);
    error.clear();
    return true;
}

bool Json::is_integer() const {
    if (type_ != Type::Number) {
        return false;
    }
    return number_ == std::trunc(number_) && std::fabs(number_) <= 9.0e15;
}

const Json* Json::find(StringView key) const {
    if (type_ != Type::Object) {
        return nullptr;
    }
    // Linear scan: these objects hold a handful of keys, and this avoids
    // building a temporary std::string for every lookup.
    for (std::map<std::string, Json>::const_iterator it = object_.begin(); it != object_.end();
         ++it) {
        if (it->first.size() == key.size() &&
            std::memcmp(it->first.data(), key.data(), key.size()) == 0) {
            return &it->second;
        }
    }
    return nullptr;
}

std::string json_string_or(const Json& value, StringView key, StringView fallback) {
    const Json* field = value.find(key);
    if (field != nullptr && field->is_string() && !field->as_string().empty()) {
        return field->as_string();
    }
    return to_string(fallback);
}

}  // namespace tabgoto
