#pragma once

// Minimal non-owning string view for the C++11 target (std::string_view is
// C++17). The referenced characters must outlive the view.

#include <cstddef>
#include <cstring>
#include <string>

namespace tabgoto {

class StringView {
public:
    StringView() : data_(""), size_(0) {}
    StringView(const char* text)
        : data_(text == nullptr ? "" : text), size_(text == nullptr ? 0 : std::strlen(text)) {}
    StringView(const std::string& text) : data_(text.data()), size_(text.size()) {}
    StringView(const char* data, size_t size) : data_(data), size_(size) {}

    const char* data() const { return data_; }
    size_t size() const { return size_; }
    bool empty() const { return size_ == 0; }
    char operator[](size_t index) const { return data_[index]; }

    const char* begin() const { return data_; }
    const char* end() const { return data_ + size_; }

    StringView substr(size_t start) const { return substr(start, size_ - start); }

    StringView substr(size_t start, size_t count) const {
        if (start >= size_) {
            return StringView(data_ + size_, 0);
        }
        const size_t remaining = size_ - start;
        return StringView(data_ + start, count < remaining ? count : remaining);
    }

private:
    const char* data_;
    size_t size_;
};

inline std::string to_string(StringView text) {
    return std::string(text.data(), text.size());
}

}  // namespace tabgoto
