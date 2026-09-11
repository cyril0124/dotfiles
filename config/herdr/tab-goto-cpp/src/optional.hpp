#pragma once

// Minimal optional for the C++11 target (std::optional is C++17). Stores the
// value inline, so no allocation is involved.

#include <new>
#include <type_traits>
#include <utility>

namespace tabgoto {

template <typename T>
class Optional {
public:
    Optional() : engaged_(false) {}

    Optional(const T& value) : engaged_(false) { construct(value); }
    Optional(T&& value) : engaged_(false) { construct(std::move(value)); }

    Optional(const Optional& other) : engaged_(false) {
        if (other.engaged_) {
            construct(*other.pointer());
        }
    }
    Optional(Optional&& other) : engaged_(false) {
        if (other.engaged_) {
            construct(std::move(*other.pointer()));
        }
    }
    ~Optional() { reset(); }

    Optional& operator=(const Optional& other) {
        if (this != &other) {
            reset();
            if (other.engaged_) {
                construct(*other.pointer());
            }
        }
        return *this;
    }

    Optional& operator=(Optional&& other) {
        if (this != &other) {
            reset();
            if (other.engaged_) {
                construct(std::move(*other.pointer()));
            }
        }
        return *this;
    }

    bool has_value() const { return engaged_; }
    explicit operator bool() const { return engaged_; }

    T& value() { return *pointer(); }
    const T& value() const { return *pointer(); }
    T& operator*() { return *pointer(); }
    const T& operator*() const { return *pointer(); }
    T* operator->() { return pointer(); }
    const T* operator->() const { return pointer(); }

    void reset() {
        if (engaged_) {
            pointer()->~T();
            engaged_ = false;
        }
    }

private:
    T* pointer() { return reinterpret_cast<T*>(&storage_); }
    const T* pointer() const { return reinterpret_cast<const T*>(&storage_); }

    template <typename U>
    void construct(U&& value) {
        new (&storage_) T(std::forward<U>(value));
        engaged_ = true;
    }

    typename std::aligned_storage<sizeof(T), alignof(T)>::type storage_;
    bool engaged_;
};

}  // namespace tabgoto
