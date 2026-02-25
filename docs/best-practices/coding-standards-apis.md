# C++ API Usage, Containers & Type Safety

<!-- See also: coding-standards.md, coding-standards-memory.md, coding-standards-apis.md -->

<a id="CSA-001"></a>

## ✅ Use Existing Utilities Instead of Custom Code

**Always check for existing well-tested utilities before writing custom code.** Chromium and base have extensive libraries for common operations.

```cpp
// ❌ WRONG - custom query string parsing
std::string ParseQueryParam(const std::string& url, const std::string& key) {
  // custom parsing code...
}

// ✅ CORRECT - use existing utility
net::QueryIterator it(url);
while (!it.IsAtEnd()) {
  if (it.GetKey() == key) return it.GetValue();
  it.Advance();
}
```

---

<a id="CSA-002"></a>

## ✅ Use base::OnceCallback and base::BindOnce

**`base::Callback` and `base::Bind` are deprecated.** Use `base::OnceCallback`/`base::RepeatingCallback` and `base::BindOnce`/`base::BindRepeating`. Use `std::move` when passing or calling a `base::OnceCallback`.

---

<a id="CSA-003"></a>

## ✅ Never Use std::time - Use base::Time

**Always use `base::Time` and related classes instead of C-style `std::time`, `ctime`, or `time_t`.** The base library provides cross-platform, type-safe time utilities.

---

<a id="CSA-004"></a>

## ✅ Use `JSONValueConverter` for JSON/Type Conversion

**When parsing JSON into C++ types, prefer `base::JSONValueConverter` over manual key-by-key parsing.** Manual parsing is verbose, error-prone, and results in duplicated boilerplate.

```cpp
// ❌ WRONG - manual JSON parsing
const auto* name = dict->FindStringKey("name");
const auto age = dict->FindIntKey("age");
if (name) result.name = *name;
if (age) result.age = *age;

// ✅ CORRECT - use JSONValueConverter
static void RegisterJSONConverter(
    base::JSONValueConverter<MyType>* converter) {
  converter->RegisterStringField("name", &MyType::name);
  converter->RegisterIntField("age", &MyType::age);
}
```

---

<a id="CSA-005"></a>

## ✅ Use `base::flat_map` Over `std::map` and `std::unordered_map`

**Chromium's container guidelines recommend avoiding `std::unordered_map` and `std::map`.** Use `base::flat_map` as the default choice for associative containers. It has better cache locality and lower overhead for small-to-medium sizes. See `base/containers/README.md` for guidance.

```cpp
// ❌ WRONG
std::unordered_map<std::string, double> feature_map_;
std::map<std::string, int> lookup_;

// ✅ CORRECT
base::flat_map<std::string, double> feature_map_;
base::flat_map<std::string, int> lookup_;
```

---

<a id="CSA-006"></a>

## ❌ Don't Use Deprecated `GetAs*` Methods on `base::Value`

**The `GetAsString()`, `GetAsInteger()`, etc. methods on `base::Value` are deprecated.** Use the newer direct access methods like `GetString()`, `GetInt()`, `GetDouble()`.

```cpp
// ❌ WRONG
std::string str;
value->GetAsString(&str);

// ✅ CORRECT
const std::string& str = value->GetString();
```

---

<a id="CSA-007"></a>

## ✅ Use `GetIfBool`/`GetIfInt`/`GetIfString` for Safe `base::Value` Access

**When extracting values from a `base::Value` where the type may not match, use `GetIf*` accessors instead of `Get*` which CHECK-fails on type mismatch.**

```cpp
// ❌ WRONG - crashes if value is not a bool
if (value.GetBool()) { ... }

// ✅ CORRECT - safe accessor with value_or
if (value.GetIfBool().value_or(false)) { ... }
```

---

<a id="CSA-008"></a>

## ❌ Don't Use `std::to_string` - Use `base::NumberToString`

**`std::to_string` is on Chromium's deprecated list.** Use `base::NumberToString` instead.

```cpp
// ❌ WRONG
std::string port_str = std::to_string(port);

// ✅ CORRECT
std::string port_str = base::NumberToString(port);
```

---

<a id="CSA-009"></a>

## ❌ Don't Use C-Style Casts

**Chromium prohibits C-style casts.** Use C++ casts (`static_cast`, `reinterpret_cast`, etc.) which are safer and more explicit.

```cpp
// ❌ WRONG
double result = (double)integer_value / total;

// ✅ CORRECT
double result = static_cast<double>(integer_value) / total;
```

---

<a id="CSA-010"></a>

## ✅ Prefer std::move Over Clone

**Use `std::move` instead of cloning when you don't need the original value anymore.** This avoids unnecessary copies. This is especially important when passing `std::vector` or other large objects to callback `.Run()` calls — forgetting `std::move` silently copies the entire buffer.

```cpp
// ❌ WRONG - copies the entire vector into the callback
std::vector<unsigned char> buffer = BuildData();
std::move(cb).Run(buffer, other_arg);

// ✅ CORRECT - moves the vector, no copy
std::vector<unsigned char> buffer = BuildData();
std::move(cb).Run(std::move(buffer), other_arg);
```

---

<a id="CSA-011"></a>

## ❌ Don't Create Unnecessary Wrapper Types

**Don't create plural/container types when you can use arrays of the singular type.** Extra wrapper types add complexity without value.

```cpp
// ❌ WRONG - unnecessary plural type
struct MonthlyStatements {
  std::vector<MonthlyStatement> statements;
};

// ✅ CORRECT - just use the vector directly
std::vector<MonthlyStatement> GetMonthlyStatements();
```

---

<a id="CSA-012"></a>

## ✅ Use Pref Dict/List Values Directly

**Don't serialize to JSON strings when storing structured data in prefs.** Use `SetDict`/`SetList` directly instead of `JSONWriter::Write` + `SetString`.

```cpp
// ❌ WRONG - serializing to JSON string unnecessarily
std::string result;
base::JSONWriter::Write(root, &result);
prefs->SetString(prefs::kMyPref, result);

// ✅ CORRECT - use native pref value types
prefs->SetDict(prefs::kMyPref, std::move(dict_value));
prefs->SetList(prefs::kMyPref, std::move(list_value));
```

---

<a id="CSA-013"></a>

## ✅ Use `extern const char[]` Over `#define` for Strings

**Use `extern const char[]` instead of `#define` for string constants to keep them namespaced.**

```cpp
// ❌ WRONG - pollutes preprocessor namespace
#define MY_URL "https://example.com"

// ✅ CORRECT - properly namespaced
extern const char kMyUrl[];
// In .cc:
const char kMyUrl[] = "https://example.com";
```

Exception: use `#define` when you need to pass the value in from GN.

---

<a id="CSA-014"></a>

## ✅ Prefer Enum Types Over String Constants for Typed Values

**When a value has a fixed set of valid options, use an enum with string conversion rather than passing raw strings.** This enables compiler-checked switch statements and prevents invalid values.

```cpp
// ❌ WRONG - raw strings
void SetWalletType(const std::string& type);

// ✅ CORRECT - enum with conversion
enum class WalletType { kUphold, kGemini };
void SetWalletType(WalletType type);
```

---

<a id="CSA-015"></a>

## ❌ No C++ Exceptions in Third-Party Libraries

**C++ exceptions are disallowed in Chromium.** When integrating third-party libraries, verify they build with exception support disabled.

---

<a id="CSA-016"></a>

## ✅ Use `base::EraseIf` / `std::erase_if` Instead of Manual Erase Loops

**Prefer `base::EraseIf` (for `base::flat_*` containers) or `std::erase_if` (for standard containers) over manual iterator-based erase loops.** Cleaner and less error-prone.

```cpp
// ❌ WRONG - manual erase loop
for (auto it = items.begin(); it != items.end();) {
  if (it->IsExpired()) {
    it = items.erase(it);
  } else {
    ++it;
  }
}

// ✅ CORRECT
base::EraseIf(items, [](const auto& item) { return item.IsExpired(); });
// or for std containers:
std::erase_if(items, [](const auto& item) { return item.IsExpired(); });
```

---

<a id="CSA-017"></a>

## ✅ Use `base::span` at API Boundaries Instead of `const std::vector&`

**Prefer `base::span<const T>` over `const std::vector<T>&` for function parameters that only read data.** Spans are lightweight, non-owning views that accept any contiguous container (`std::vector`, `base::HeapArray`, C arrays, `base::FixedArray`), making APIs more flexible.

```cpp
// ❌ WRONG - forces callers to use std::vector
void ProcessBuffer(const std::vector<uint8_t>& data);

// ✅ CORRECT - accepts any contiguous container
void ProcessBuffer(base::span<const uint8_t> data);
```

This is especially important for byte buffer APIs where the data source may be a `std::vector`, `base::HeapArray`, or a static array.

---

<a id="CSA-018"></a>

## ✅ Use `base::FixedArray` Over `std::vector` for Known-Size Runtime Allocations

**When the size is known at creation but not at compile time, use `base::FixedArray`.** It avoids heap allocation for small sizes and communicates immutable size.

```cpp
// ❌ WRONG - vector suggests dynamic resizing
std::vector<uint8_t> out(size);

// ✅ CORRECT - size is fixed after construction
base::FixedArray<uint8_t> out(size);
```

---

<a id="CSA-019"></a>

## ✅ Use `base::HeapArray<uint8_t>` for Fixed-Size Byte Buffers

**When you need an owned byte buffer that won't be resized after creation, use `base::HeapArray<uint8_t>` instead of `std::vector<unsigned char>` or `std::vector<uint8_t>`.** `HeapArray` communicates that the size is fixed, provides bounds-checked indexing, and converts easily to `base::span`.

```cpp
// ❌ WRONG - vector implies the buffer may grow
std::vector<unsigned char> dat_buffer(size);
ProcessBuffer(dat_buffer.data(), dat_buffer.size());

// ✅ CORRECT - HeapArray communicates fixed-size semantics
auto dat_buffer = base::HeapArray<uint8_t>::WithSize(size);
ProcessBuffer(dat_buffer.as_span());
```

Use `HeapArray::Uninit(size)` for performance-sensitive paths where zero-initialization is unnecessary.

**Note:** When interfaces (e.g., Mojo, Rust FFI) require `std::vector`, you may need to keep using `std::vector` at those boundaries, but prefer `HeapArray` for internal buffer management.

---

<a id="CSA-020"></a>

## ✅ Use `base::ToVector` for Range-to-Vector Conversions

**Use `base::ToVector(range)` instead of manual copy patterns when converting a range to a `std::vector`.** It handles `reserve()` and iteration automatically, and supports projections.

```cpp
// ❌ WRONG - manual reserve + copy + back_inserter
std::vector<unsigned char> buffer;
buffer.reserve(sizeof(kStaticData) - 1);
std::copy_n(kStaticData, sizeof(kStaticData) - 1,
            std::back_inserter(buffer));

// ✅ CORRECT - base::ToVector
auto buffer = base::ToVector(base::span(kStaticData).first<sizeof(kStaticData) - 1>());

// ✅ CORRECT - with projection
auto names = base::ToVector(items, &Item::name);
```

---

<a id="CSA-021"></a>

## ✅ Prefer Contiguous Containers Over Linked Lists

**Never use `std::list` for pure traversal — poor cache locality.** Use `std::list` only when stable iterators or frequent mid-container insert/remove is required. Prefer `std::vector` with `reserve()` for known sizes.

---

<a id="CSA-022"></a>

## ✅ Use `std::optional` Instead of Sentinel Values

**Never use empty string `""`, `-1`, or other magic values as sentinels for "no value".** Use `std::optional<T>`.

```cpp
// ❌ WRONG - "" as sentinel for "no custom title"
void SetCustomTitle(const std::string& title);  // "" means "unset"

// ✅ CORRECT - explicit optionality
void SetCustomTitle(std::optional<std::string> title);  // nullopt means "unset"
```

---

<a id="CSA-023"></a>

## ✅ Use `.emplace()` for `std::optional` Initialization Clarity

**When engaging a `std::optional` member, prefer `.emplace()` for clarity about the intent.**

```cpp
// Less clear
elapsed_timer_ = base::ElapsedTimer();

// ✅ CORRECT - explicit engagement intent
elapsed_timer_.emplace();
```

---

<a id="CSA-024"></a>

## ✅ Return `std::optional` Instead of `bool` + Out Parameter

**When a function needs to return a value that may or may not exist, use `std::optional<T>` instead of returning `bool` with an out parameter.**

```cpp
// ❌ WRONG
bool GetHistorySize(int* out_size);

// ✅ CORRECT
std::optional<int> GetHistorySize();
```

---

<a id="CSA-025"></a>

## ✅ Use `constexpr` for Compile-Time Constants

**Constants defined in anonymous namespaces should use `constexpr` instead of `const` when the value is known at compile time.** Place constants inside the component's namespace.

```cpp
// ❌ WRONG
namespace {
const int kMaxRetries = 3;
}

// ✅ CORRECT
namespace brave_stats {
namespace {
constexpr int kMaxRetries = 3;
}  // namespace
}  // namespace brave_stats
```

---

<a id="CSA-026"></a>

## ✅ Use Raw String Literals for Multiline Strings

**When embedding multiline strings (JavaScript, SQL, etc.), use raw string literals (`R"()"`) instead of escaping each line.**

```cpp
// ❌ WRONG
const char kScript[] =
    "(function() {\n"
    "  let x = 1;\n"
    "})();";

// ✅ CORRECT
const char kScript[] = R"(
  (function() {
    let x = 1;
  })();
)";
```

---

<a id="CSA-027"></a>

## ❌ Don't Pass Primitive Types by `const` Reference

**Primitive types (`int`, `bool`, `float`, pointers) should be passed by value, not by `const` reference.** Passing by reference adds unnecessary indirection.

```cpp
// ❌ WRONG
void ProcessItem(const int& id, const bool& enabled);

// ✅ CORRECT
void ProcessItem(int id, bool enabled);
```

---

<a id="CSA-028"></a>

## ❌ Don't Add `DISALLOW_COPY_AND_ASSIGN` in New Code

**The `DISALLOW_COPY_AND_ASSIGN` macro is deprecated.** Explicitly delete the copy constructor and copy assignment operator instead.

```cpp
// ❌ WRONG
class MyClass {
 private:
  DISALLOW_COPY_AND_ASSIGN(MyClass);
};

// ✅ CORRECT
class MyClass {
 public:
  MyClass(const MyClass&) = delete;
  MyClass& operator=(const MyClass&) = delete;
};
```

---

<a id="CSA-029"></a>

## ✅ Declare Move Operations as `noexcept`

**When defining custom move constructors/assignment operators for structs used in `std::vector`, declare them `noexcept`.** Without `noexcept`, `std::vector` falls back to copying during reallocations.

```cpp
// ❌ WRONG
Topic(Topic&&) = default;

// ✅ CORRECT
Topic(Topic&&) noexcept = default;
Topic& operator=(Topic&&) noexcept = default;
```

---

<a id="CSA-030"></a>

## ✅ Use References for Non-Nullable Parameters; `raw_ref` for Stored References

**When a function parameter cannot be null, use a reference (`T&`) instead of a pointer (`T*`).** For stored member references that cannot be null, use `raw_ref<T>`.

```cpp
// ❌ WRONG - pointer suggests nullability
NetworkClient(PrefService* pref_service);

// ✅ CORRECT - reference communicates non-null requirement
NetworkClient(PrefService& pref_service);

// For stored references:
raw_ref<PrefService> pref_service_;  // not raw_ptr
```

---

<a id="CSA-031"></a>

## ❌ Avoid `std::optional<T>&` References

**Never pass `std::optional<T>&` as a function parameter.** It's confusing and can cause hidden copies. Take by value if storing, or use `base::optional_ref<T>` for non-owning optional references.

```cpp
// ❌ WRONG - confusing, hidden copies
void Process(const std::optional<std::string>& value);

// ✅ CORRECT - take by value if storing
void Process(std::optional<std::string> value);

// ✅ CORRECT - use base::optional_ref for non-owning optional references
void Process(base::optional_ref<const std::string> value);
```

---

<a id="CSA-032"></a>

## ✅ Short-Circuit on Non-HTTP(S) URLs

**In URL processing code (shields, debouncing, content settings), add an early return for non-HTTP/HTTPS URLs.** This prevents wasting time on irrelevant schemes and avoids edge cases.

```cpp
// ✅ CORRECT - early exit
bool ShouldDebounce(const GURL& url) {
  if (!url.SchemeIsHTTPOrHTTPS())
    return false;
  // ...
}
```

---

<a id="CSA-033"></a>

## ❌ Don't Narrow Integer Types in Setters or Parameters

**Setter and function parameter types must match the underlying field type.** Accepting a narrower type (e.g., `uint32_t` when the field is `uint64_t`) silently truncates values. This is especially dangerous in security-sensitive code like wallet/crypto transactions.

```cpp
// ❌ WRONG - parameter narrower than field, silent truncation
class Transaction {
  uint64_t invalid_after_ = 0;
  void set_invalid_after(uint32_t value) { invalid_after_ = value; }
};

// ✅ CORRECT - types match
class Transaction {
  uint64_t invalid_after_ = 0;
  void set_invalid_after(uint64_t value) { invalid_after_ = value; }
};
```

---

<a id="CSA-034"></a>

## ✅ Deprecate Prefs Before Removing Them

**When removing a preference that was previously stored in user profiles, first deprecate the pref (register it for clearing) in one release before fully removing it.** This ensures the old value is cleared from existing profiles.

---

<a id="CSA-035"></a>

## ❌ Don't Modify Production Code Solely to Accommodate Tests

**Test-specific workarounds should not affect production behavior.** Use test infrastructure like `kHostResolverRules` command line switches in `SetUpCommandLine` instead of adding production code paths only needed for tests.

**Only flag this rule when you are certain the code exists solely for tests.** Clear signals include `CHECK_IS_TEST()`, `#if defined(UNIT_TEST)`, `_for_testing` suffixes, or comments explicitly mentioning test support. Do NOT flag legitimate production logic such as handling empty/null/default values, reset paths, or cleanup behavior — these are normal defensive coding patterns, not test accommodations. When uncertain, do not flag.

**Exception:** Thin `ForTesting()` accessors that expose internalized features (e.g., `base::Feature`) are acceptable. These keep the feature internalized while providing a clean way for tests to reference it, and do not affect production behavior.

---

<a id="CSA-036"></a>

## ✅ Use `url::kStandardSchemeSeparator` Instead of Hardcoded `"://"`

**When constructing URLs, use `url::kStandardSchemeSeparator` instead of the hardcoded string `"://"`.** This is more maintainable and consistent with Chromium conventions.

```cpp
// ❌ WRONG
std::string url = scheme + "://" + host + path;

// ✅ CORRECT
std::string url = base::StrCat({url::kHttpsScheme,
                                url::kStandardSchemeSeparator,
                                host, path});
```

---

<a id="CSA-037"></a>

## ✅ Use `base::DoNothing()` for No-Op Callbacks

**Use `base::DoNothing()` instead of empty lambdas when a no-op callback is needed.** It is the Chromium-idiomatic way and is more readable.

```cpp
// ❌ WRONG - empty lambda
service->DoAsync([](const std::string&) {});

// ✅ CORRECT
service->DoAsync(base::DoNothing());
```

---

<a id="CSA-038"></a>

## ✅ Use `base::StrAppend` Over `+= base::StrCat`

**When appending to an existing string, use `base::StrAppend(&str, {...})` instead of `str += base::StrCat({...})`.** `StrCat` creates a temporary string that is then copied; `StrAppend` appends directly to the target, avoiding unnecessary allocation.

```cpp
// ❌ WRONG - temporary string then copy
result += base::StrCat({kOpenTag, "\n", "=== METADATA ===\n"});

// ✅ CORRECT - append directly
base::StrAppend(&result, {kOpenTag, "\n", "=== METADATA ===\n"});
```

---

<a id="CSA-039"></a>

## ✅ Use `base::Reversed()` for Reverse Iteration

**Prefer `base::Reversed()` with range-based for loops over explicit reverse iterators.** Always add a comment explaining why reverse order is needed.

```cpp
// ❌ WRONG - explicit reverse iterators
for (auto it = history.crbegin(); it != history.crend(); ++it) {
  ProcessEntry(*it);
}

// ✅ CORRECT - base::Reversed with comment
// Process newest entries first to prioritize recent content.
for (const auto& entry : base::Reversed(history)) {
  ProcessEntry(entry);
}
```

---

<a id="CSA-040"></a>

## ✅ Use `absl::StrFormat` Over `base::StringPrintf`

**Prefer `absl::StrFormat` for formatted string construction.** `base::StringPrintf` is being deprecated in favor of `absl::StrFormat`.

```cpp
// ❌ WRONG - deprecated
std::string msg = base::StringPrintf("Error %d: %s", code, desc.c_str());

// ✅ CORRECT
std::string msg = absl::StrFormat("Error %d: %s", code, desc);
```

---

<a id="CSA-041"></a>

## ✅ Use `base::saturated_cast` for Safe Numeric Conversions

**When converting between integer types, use `base::saturated_cast<TargetType>()` combined with `.value_or(default)` for safe, concise conversion of optional numeric values.**

```cpp
// ❌ WRONG - manual null-check and static_cast
if (value.has_value()) {
  result = static_cast<uint64_t>(*value);
}

// ✅ CORRECT - safe saturated cast with value_or
result = base::saturated_cast<uint64_t>(value.value_or(0));
```

---

<a id="CSA-042"></a>

## ✅ Use `std::ranges` Algorithms Over Manual Loops

**Prefer C++20 `std::ranges::any_of`, `std::ranges::all_of`, `std::ranges::find_if` over manual for-loops with break conditions.** The ranges versions are more concise and readable.

```cpp
// ❌ WRONG - manual loop
bool found = false;
for (const auto& item : items) {
  if (item.IsExpired()) {
    found = true;
    break;
  }
}

// ✅ CORRECT - ranges algorithm
bool found = std::ranges::any_of(items,
    [](const auto& item) { return item.IsExpired(); });
```

---

<a id="CSA-043"></a>

## ✅ Guard `substr()` with Size Check

**Only call `substr()` when the content actually exceeds the limit.** For content within the limit, use the original string to avoid unnecessary memory allocation and copying.

```cpp
// ❌ WRONG - always creates a substring
std::string truncated = content.substr(0, max_length);

// ✅ CORRECT - only substr when needed
const std::string& truncated = (content.size() > max_length)
    ? content.substr(0, max_length)
    : content;
```

---

<a id="CSA-044"></a>

## ✅ Use `base::expected<T, E>` Over Optional + Error Out-Parameter

**When a function can fail and needs to communicate error details, use `base::expected<T, E>` instead of `std::optional<T>` with a separate error out-parameter.** This bundles success and error into a single return value.

```cpp
// ❌ WRONG - separate error out-parameter
std::optional<Result> Parse(const std::string& input, std::string* error);

// ✅ CORRECT - base::expected bundles both
base::expected<Result, std::string> Parse(const std::string& input);
```

---

<a id="CSA-045"></a>

## ✅ Use `base::MakeFixedFlatMap` for Static Enum-to-String Mappings

**For compile-time constant mappings between enums and strings, use `base::MakeFixedFlatMap`.** It provides compile-time verification and is more maintainable than switch statements or runtime-built maps.

```cpp
// ❌ WRONG - runtime map
const std::map<ActionType, std::string> kActionNames = {
    {ActionType::kSummarize, "summarize"},
    {ActionType::kRewrite, "rewrite"},
};

// ✅ CORRECT - compile-time fixed flat map
constexpr auto kActionNames = base::MakeFixedFlatMap<ActionType, std::string_view>({
    {ActionType::kSummarize, "summarize"},
    {ActionType::kRewrite, "rewrite"},
});
```

---

<a id="CSA-046"></a>

## ✅ Use `base::JSONReader::ReadDict` for JSON Dictionary Parsing

**When parsing a JSON string expected to be a dictionary, use `base::JSONReader::ReadDict()`** which returns `std::optional<base::Value::Dict>` directly, instead of `base::JSONReader::Read()` followed by manual `GetIfDict()` extraction.

```cpp
// ❌ WRONG - manual extraction
auto value = base::JSONReader::Read(json_str);
if (!value || !value->is_dict()) return;
auto& dict = value->GetDict();

// ✅ CORRECT - direct dict parsing
auto dict = base::JSONReader::ReadDict(json_str);
if (!dict) return;
```

---

<a id="CSA-047"></a>

## ✅ Pass-by-Value for Sink Parameters (Google Style)

**Per Google C++ Style Guide, use pass-by-value for parameters that will be moved into the callee** (sink parameters) instead of `T&&`. The caller uses `std::move()` either way, and pass-by-value is simpler.

```cpp
// ❌ WRONG - rvalue reference parameter
void SetName(std::string&& name) { name_ = std::move(name); }

// ✅ CORRECT - pass by value
void SetName(std::string name) { name_ = std::move(name); }
```

---

<a id="CSA-048"></a>

## ✅ Annotate Obsolete Pref Migration Entries with Dates

**When adding preference migration code that removes deprecated prefs, annotate the entry with the date it was added.** This makes it easy to identify and clean up old migration code later.

```cpp
// ❌ WRONG - no context for when this was added
profile_prefs->ClearPref(kOldFeaturePref);

// ✅ CORRECT - annotated with date
profile_prefs->ClearPref(kOldFeaturePref);  // Added 2025-01 (safe to remove after ~3 releases)
```

---

<a id="CSA-049"></a>

## ✅ Use `base::FindOrNull()` for Map Lookups

**Use `base::FindOrNull()` instead of the manual find-and-check-end pattern for map lookups.** It's more concise and less error-prone.

```cpp
// ❌ WRONG - verbose find + check
auto it = metric_configs_.find(metric_name);
if (it == metric_configs_.end()) {
  return nullptr;
}
return &it->second;

// ✅ CORRECT
return base::FindOrNull(metric_configs_, metric_name);
```

---

<a id="CSA-050"></a>

## ✅ Use `base::Extend` for Appending Ranges to Vectors

**Use `base::Extend(target, source)` instead of manual `insert(end, begin, end)` for appending one collection to another.**

```cpp
// ❌ WRONG - verbose
accelerator_list.insert(accelerator_list.end(),
    brave_accelerators.begin(), brave_accelerators.end());

// ✅ CORRECT
base::Extend(accelerator_list, base::span(kBraveAcceleratorMap));
```

---

<a id="CSA-051"></a>

## ✅ Use `base::test::ParseJson` and `base::ExpectDict*` in Tests

**Use `base::test::ParseJson()` for parsing JSON in tests, and `base::test::*` utilities from `base/test/values_test_util.h` for asserting dict contents.** These are more readable and produce better error messages than manual JSON parsing.

```cpp
// ❌ WRONG - manual JSON parsing in tests
auto value = base::JSONReader::Read(json_str);
ASSERT_TRUE(value);
ASSERT_TRUE(value->is_dict());
auto* name = value->GetDict().FindString("name");
ASSERT_TRUE(name);
EXPECT_EQ(*name, "test");

// ✅ CORRECT - test utilities
auto dict = base::test::ParseJsonDict(json_str);
EXPECT_THAT(dict, base::test::DictHasValue("name", "test"));
```

---

<a id="CSA-052"></a>

## ✅ Use `kOsAll` for Cross-Platform Feature Flags

**When registering feature flags in `about_flags.cc` that should be available on all platforms, use `kOsAll`** instead of listing individual platform constants.

```cpp
// ❌ WRONG - listing platforms individually
{"brave-my-feature", ..., kOsDesktop | kOsAndroid}

// ✅ CORRECT - use kOsAll
{"brave-my-feature", ..., kOsAll}
```

---

<a id="CSA-053"></a>

## ✅ Workaround Code Must Have Tracking Issues

**Any workaround or hack code must reference a tracking issue with a `TODO(issue-url)` comment** explaining when and why it can be removed. Workarounds without tracking issues become permanent technical debt.

```cpp
// ❌ WRONG - unexplained workaround
// HACK: skip validation for now
if (ShouldSkipValidation()) return;

// ✅ CORRECT - tracked workaround
// TODO(https://github.com/nicira/nicira/issues/123): Remove this
// workaround once upstream fixes the validation race condition.
if (ShouldSkipValidation()) return;
```

---

<a id="CSA-054"></a>

## ✅ Use Named Constants for JSON Property Keys

**When accessing JSON object properties in C++, define named constants for the key strings** rather than using inline string literals. This prevents typos and makes refactoring easier.

```cpp
// ❌ WRONG - inline string literals
auto* name = dict.FindString("display_name");
auto* url = dict.FindString("endpoint_url");

// ✅ CORRECT - named constants
constexpr char kDisplayName[] = "display_name";
constexpr char kEndpointUrl[] = "endpoint_url";
auto* name = dict.FindString(kDisplayName);
auto* url = dict.FindString(kEndpointUrl);
```

---

<a id="CSA-055"></a>

## ❌ Never Return `std::string_view` from Functions That Build Strings

**Do not return `std::string_view` from a function that constructs or concatenates a string internally.** The view would point into a temporary string's buffer and become a dangling reference after the function returns. Return `std::string` or `std::optional<std::string>` instead.

```cpp
// ❌ WRONG - dangling reference to temporary
std::string_view BuildUrl(std::string_view host) {
  std::string url = base::StrCat({"https://", host, "/api"});
  return url;  // url destroyed, view dangles!
}

// ✅ CORRECT - return by value
std::string BuildUrl(std::string_view host) {
  return base::StrCat({"https://", host, "/api"});
}
```

---

<a id="CSA-056"></a>

## ✅ Prefer `constexpr int` Over Single-Value Enums

**When a constant is just a single numeric value, use `constexpr int` rather than creating a single-value enum.** Enums are for sets of related values.

```cpp
// ❌ WRONG - enum for a single value
enum { kBravePolicySource = 10 };

// ✅ CORRECT - constexpr int
constexpr int kBravePolicySource = 10;
```

---

<a id="CSA-057"></a>

## ✅ Use `base::FilePath` for File Path Parameters

**Parameters representing file system paths should use `base::FilePath` instead of `std::string`.** This provides type safety, simplifies call sites, and makes APIs self-documenting.

```cpp
// ❌ WRONG - generic string for a path
std::string GetProfileId(const std::string& profile_path);

// ✅ CORRECT - domain-specific type
std::string GetProfileId(const base::FilePath& profile_path);
```

---

<a id="CSA-058"></a>

## ✅ Explicitly Assign Enum Values When Conditionally Compiling Out Members

**When conditionally compiling out enum values behind a build flag, explicitly assign numeric values to remaining members.** This prevents value shifts that break serialization, persistence, or IPC.

```cpp
// ❌ WRONG - values shift when kTalk is compiled out
enum class SidebarItem {
  kBookmarks,
#if BUILDFLAG(ENABLE_BRAVE_TALK)
  kTalk,
#endif
  kHistory,  // value changes depending on build flag!
};

// ✅ CORRECT - explicit values prevent shifts
enum class SidebarItem {
  kBookmarks = 0,
#if BUILDFLAG(ENABLE_BRAVE_TALK)
  kTalk = 1,
#endif
  kHistory = 2,
};
```

---

<a id="CSA-059"></a>

## ✅ Name All Function Parameters in Header Declarations

**Always name function parameters in header declarations, especially when types alone are ambiguous.** Match the parameter names used in the `.cc` file.

```cpp
// ❌ WRONG - ambiguous parameters
void OnSubmitSignedExtrinsic(std::optional<std::string>,
                             std::optional<std::string>);

// ✅ CORRECT - named parameters
void OnSubmitSignedExtrinsic(std::optional<std::string> transaction_hash,
                             std::optional<std::string> error_str);
```

---

<a id="CSA-060"></a>

## ✅ Struct Members: No Trailing Underscores

**Plain struct members should not have trailing underscores.** The trailing underscore convention is for class member variables, not struct fields.

```cpp
// ❌ WRONG
struct ContentSite {
  std::string name_;
  int percentage_;
};

// ✅ CORRECT
struct ContentSite {
  std::string name;
  int percentage;
};
```

---

<a id="CSA-061"></a>

## ✅ Use `TEST` Instead of `TEST_F` When No Fixture Is Needed

**If your test doesn't set up shared state via a fixture class, use `TEST` instead of `TEST_F`.** Move helper functions to an anonymous namespace as free functions.

```cpp
// ❌ WRONG - empty fixture
class MyExtractorTest : public testing::Test {};
TEST_F(MyExtractorTest, ExtractsCorrectly) { ... }

// ✅ CORRECT - no fixture needed
TEST(MyExtractorTest, ExtractsCorrectly) { ... }
```

---

<a id="CSA-062"></a>

## ❌ Don't Introduce New Uses of Deprecated APIs

**When an API is marked deprecated, never introduce new uses.** Check headers for deprecation notices before using unfamiliar APIs.

```cpp
// ❌ WRONG - base::Hash deprecated for 6+ years
uint32_t hash = base::Hash(str);

// ✅ CORRECT - use the recommended replacement
uint32_t hash = base::FastHash(base::as_byte_span(str));
```

---

<a id="CSA-063"></a>

## ✅ Default-Initialize POD-Type Members in Headers

**Plain old data (POD) type members in structs and classes declared in headers must have explicit default initialization.** Uninitialized POD members lead to undefined behavior when read before being written.

```cpp
// ❌ WRONG
struct TopicArticle {
  int id;
  double score;
};

// ✅ CORRECT
struct TopicArticle {
  int id = 0;
  double score = 0.0;
};
```

---

<a id="CSA-064"></a>

## ✅ Prefer `std::string_view` Over `const char*` for Parameters

**Use `std::string_view` instead of `const char*` for function parameters that accept string data.** `std::string_view` is more flexible (accepts `std::string`, `const char*`, string literals) and carries size information.

```cpp
// ❌ WRONG
std::string_view GetDomain(const char* env_from_switch);

// ✅ CORRECT
std::string_view GetDomain(std::string_view env_from_switch);
```
