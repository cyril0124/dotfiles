#pragma once

// Minimal JSON reader for herdr CLI payloads: objects, arrays, strings, numbers,
// booleans, null.

#include <map>
#include <string>
#include <vector>

#include "string_view.hpp"

namespace tabgoto {

class Json {
public:
    enum class Type { Null, Bool, Number, String, Array, Object };

    Json() = default;

    // Parses `text`; on failure returns false and fills `error`.
    static bool parse(StringView text, Json& out, std::string& error);

    bool is_null() const { return type_ == Type::Null; }
    bool is_bool() const { return type_ == Type::Bool; }
    bool is_string() const { return type_ == Type::String; }
    bool is_array() const { return type_ == Type::Array; }
    bool is_object() const { return type_ == Type::Object; }

    bool as_bool() const { return bool_; }
    const std::string& as_string() const { return string_; }
    const std::vector<Json>& items() const { return array_; }

    // True when the number is an exact integer that fits in a long.
    bool is_integer() const;
    long as_integer() const { return static_cast<long>(number_); }

    // Returns nullptr when the value is not an object or the key is absent.
    // Objects here hold a handful of keys, so a linear scan avoids the
    // allocation a temporary std::string key would cost in C++11.
    const Json* find(StringView key) const;

private:
    friend class JsonParser;

    Type type_ = Type::Null;
    bool bool_ = false;
    double number_ = 0.0;
    std::string string_;
    std::vector<Json> array_;
    std::map<std::string, Json> object_;
};

// Convenience for callers that need a string field with a fallback.
std::string json_string_or(const Json& value, StringView key, StringView fallback);

}  // namespace tabgoto
