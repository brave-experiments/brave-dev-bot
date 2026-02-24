# C++ Patterns, Utilities, and API Usage

## ❌ Don't Use rapidjson

**Use base::JSONReader/JSONWriter, not rapidjson.** The base libraries are the standard in Chromium.

---

## VLOG Macros Handle Their Own Checks

**Don't use `VLOG_IS_ON` before `VLOG` calls.** The VLOG macro already handles the level check internally and is smart enough to avoid evaluating inline expressions when the level is disabled.

```cpp
// ❌ WRONG - unnecessary check
if (VLOG_IS_ON(2)) {
  VLOG(2) << "Some message";
}

// ✅ CORRECT - VLOG handles it
VLOG(2) << "Some message";
```

Also: be judicious with VLOG - make sure each log statement has a specific purpose and isn't leftover from debugging.

---

## ❌ Don't Override Empty/No-Op Methods

**If you're overriding a virtual method but not implementing any behavior, don't define it at all.**

```cpp
// ❌ WRONG - pointless override
void OnSomethingHappened() override {}

// ✅ CORRECT - just don't override it
```

---

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

## ✅ Use Feature Checks Over Platform Checks

**Prefer feature checks over platform checks when the behavior is feature-dependent, not platform-dependent.**

```cpp
// ❌ WRONG - platform check for feature behavior
#if defined(OS_ANDROID)
  // Don't show notifications
#endif

// ✅ CORRECT - feature check
if (IsDoNotDisturbEnabled()) {
  // Don't show notifications
}
```

---

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

## ❌ Don't Use Static Variables for Per-Profile Settings

**Never use static variables to store per-profile settings.** Static state is shared across all profiles and will cause incorrect behavior in multi-profile scenarios. Use `UserData` or profile-attached keyed services instead.

---

## ❌ Don't Use Environment Variables for Configuration

**Configuration should come from GN args, not environment variables.** For runtime overrides, use command line switches.

```cpp
// ❌ WRONG
std::string api_url = std::getenv("BRAVE_API_URL");

// ✅ CORRECT - GN arg with command line override option
// In BUILD.gn: defines += [ "BRAVE_API_URL=\"$brave_api_url\"" ]
```

---

## ✅ Use the Right Target Type: source_set vs static_library

**Use `source_set` only for internal component dependencies. Public targets for a component should use `static_library` or `component`.** Only internal deps that are not meant to be used outside the component should be `source_set` (with restricted visibility).

---

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

## ✅ Combine Methods That Are Always Called Together

**If two methods are always called in sequence (especially in patches), combine them into a single method.** This reduces patch size and prevents callers from forgetting one of the calls.

```cpp
// ❌ WRONG - two methods always called together in a patch
+SignBinaries(params);
+CopyPreSignedBinaries(params);

// ✅ CORRECT - single combined method
+PrepareBinaries(params);  // internally calls both
```

---

## ✅ Use base::OnceCallback and base::BindOnce

**`base::Callback` and `base::Bind` are deprecated.** Use `base::OnceCallback`/`base::RepeatingCallback` and `base::BindOnce`/`base::BindRepeating`. Use `std::move` when passing or calling a `base::OnceCallback`.

---

## ✅ Never Use std::time - Use base::Time

**Always use `base::Time` and related classes instead of C-style `std::time`, `ctime`, or `time_t`.** The base library provides cross-platform, type-safe time utilities.

---

## ✅ Use Observer Pattern for UI Updates

**Don't make service-layer queries to update UI directly.** Instead, trigger observer notifications and let the UI respond.

```cpp
// ❌ WRONG - service making UI queries
void RewardsService::SavePendingContribution(...) {
  SaveToDB(...);
  GetPendingContributionsTotal();  // updating UI from service
}

// ✅ CORRECT - observer pattern
void RewardsService::SavePendingContribution(...) {
  SaveToDB(...);
  for (auto& observer : observers_)
    observer.OnPendingContributionSaved();
}
// UI layer calls GetPendingContributionsTotal in its observer method
```

---

## ✅ Use Result Codes, Not bool, for Error Reporting

**Return result codes (enums) instead of `bool` for operations that can fail.** This allows providing additional error information and is more future-proof.

---

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

## ❌ Don't Pass `BrowserContext` to Component Services

**Component-level services should take specific dependencies (`PrefService*`, `URLLoaderFactory`) rather than `BrowserContext`.** Passing `BrowserContext` prevents reuse on iOS and creates content-layer dependencies.

```cpp
// ❌ WRONG
explicit FtxService(content::BrowserContext* context);

// ✅ CORRECT
FtxService(PrefService* prefs,
           scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory);
```

---

## ✅ Use `sources.gni` Only for Circular Dependencies with Upstream

**Only use `sources.gni` when inserting source files into upstream Chromium targets with circular deps.** For all other cases, use normal `BUILD.gn` targets. Putting everything in `sources.gni` hurts incremental builds because changes trigger rebuilds of large upstream targets.

---

## ❌ Don't Duplicate Enum/Constant Values Across Languages

**When values are defined in Mojo, use the generated bindings in C++, Java, and JS.** Don't manually duplicate constants - they easily drift out of sync.

---

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

## ❌ No C++ Exceptions in Third-Party Libraries

**C++ exceptions are disallowed in Chromium.** When integrating third-party libraries, verify they build with exception support disabled.

---

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

## ✅ Use `base::NoDestructor` for Non-Trivial Static Objects

**Chromium prohibits global objects with non-trivial destructors.** When you need a global/static container (like a map or vector), use `base::NoDestructor` inside a function as a local static. Use `constexpr` for simple arrays/values where possible.

```cpp
// ❌ WRONG - global map with non-trivial destructor
static const std::map<std::string, int> kMyLookup = {{"foo", 1}, {"bar", 2}};

// ✅ CORRECT - local static with NoDestructor
const std::map<std::string, int>& GetMyLookup() {
  static const base::NoDestructor<std::map<std::string, int>> lookup(
      {{"foo", 1}, {"bar", 2}});
  return *lookup;
}
```

---

## ❌ Don't Use `std::to_string` - Use `base::NumberToString`

**`std::to_string` is on Chromium's deprecated list.** Use `base::NumberToString` instead.

```cpp
// ❌ WRONG
std::string port_str = std::to_string(port);

// ✅ CORRECT
std::string port_str = base::NumberToString(port);
```

---

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

## ❌ Don't Use C-Style Casts

**Chromium prohibits C-style casts.** Use C++ casts (`static_cast`, `reinterpret_cast`, etc.) which are safer and more explicit.

```cpp
// ❌ WRONG
double result = (double)integer_value / total;

// ✅ CORRECT
double result = static_cast<double>(integer_value) / total;
```

---

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

## ✅ Return `std::optional` Instead of `bool` + Out Parameter

**When a function needs to return a value that may or may not exist, use `std::optional<T>` instead of returning `bool` with an out parameter.**

```cpp
// ❌ WRONG
bool GetHistorySize(int* out_size);

// ✅ CORRECT
std::optional<int> GetHistorySize();
```

---

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

## ❌ Don't Pass Primitive Types by `const` Reference

**Primitive types (`int`, `bool`, `float`, pointers) should be passed by value, not by `const` reference.** Passing by reference adds unnecessary indirection.

```cpp
// ❌ WRONG
void ProcessItem(const int& id, const bool& enabled);

// ✅ CORRECT
void ProcessItem(int id, bool enabled);
```

---

## ✅ Validate and Sanitize Data Before Injecting as JavaScript

**When constructing JavaScript from C++ data for injection, use JSON serialization (`base::JSONWriter`) for safe encoding.** String concatenation can lead to injection vulnerabilities.

```cpp
// ❌ WRONG - string concatenation
std::string script = "const selectors = [`" + selector + "`];";

// ✅ CORRECT - JSON serialization
std::string json_selectors;
base::JSONWriter::Write(selectors_list, &json_selectors);
std::string script = "const selectors = " + json_selectors + ";";
```

---

## ✅ Emit Histograms from a Single Location

**When recording UMA histograms, emit to each histogram from a single location.** Create a helper function rather than duplicating histogram emission across multiple call sites.

```cpp
// ❌ WRONG - histogram emitted from multiple places
void OnButtonClicked() {
  base::UmaHistogramExactLinear("Brave.NTP.CustomizeUsage", 2, 7);
}

// ✅ CORRECT - single emission point via helper
void RecordNTPCustomizeUsage(NTPCustomizeUsage usage) {
  base::UmaHistogramExactLinear("Brave.NTP.CustomizeUsage",
                                static_cast<int>(usage),
                                static_cast<int>(NTPCustomizeUsage::kSize));
}
```

---

## ✅ Use `EvalJs` Instead of Deprecated `ExecuteScriptAndExtract*`

**In browser tests, use `EvalJs` and `ExecJs` instead of the deprecated `ExecuteScriptAndExtractBool/String/Int` functions.**

```cpp
// ❌ WRONG
bool result;
ASSERT_TRUE(content::ExecuteScriptAndExtractBool(
    web_contents, "domAutomationController.send(someCheck())", &result));

// ✅ CORRECT
EXPECT_EQ(true, content::EvalJs(web_contents, "someCheck()"));
```

---

## ✅ Use `Profile::FromBrowserContext` for Conversion

**When you have a `BrowserContext*` and need a `Profile*`, use `Profile::FromBrowserContext()`.** Don't use `static_cast` - the proper method includes safety checks.

```cpp
// ❌ WRONG
Profile* profile = static_cast<Profile*>(browser_context);

// ✅ CORRECT
Profile* profile = Profile::FromBrowserContext(browser_context);
```

---

## ✅ Add `SCOPED_UMA_HISTOGRAM_TIMER` for Performance-Sensitive Paths

**When writing code that processes data on the UI thread or performs potentially slow operations, add `SCOPED_UMA_HISTOGRAM_TIMER` to measure performance.**

```cpp
void GetUrlCosmeticResourcesOnUI(const GURL& url) {
  SCOPED_UMA_HISTOGRAM_TIMER(
      "Brave.CosmeticFilters.GetUrlCosmeticResourcesOnUI");
  // ... potentially slow work ...
}
```

---

## ✅ Use `GetIfBool`/`GetIfInt`/`GetIfString` for Safe `base::Value` Access

**When extracting values from a `base::Value` where the type may not match, use `GetIf*` accessors instead of `Get*` which CHECK-fails on type mismatch.**

```cpp
// ❌ WRONG - crashes if value is not a bool
if (value.GetBool()) { ... }

// ✅ CORRECT - safe accessor with value_or
if (value.GetIfBool().value_or(false)) { ... }
```

---

## ✅ Use `LOG(WARNING)` or `VLOG` Instead of `LOG(ERROR)` for Non-Critical Failures

**`LOG(ERROR)` should be reserved for truly unexpected and serious failures.** For expected or non-critical failure cases (e.g., a bad user-supplied filter list, a failed parse of optional data), use `VLOG` for debug info or `LOG(WARNING)` for noteworthy but non-critical issues.

```cpp
// ❌ WRONG
LOG(ERROR) << "Failed to parse filter list";

// ✅ CORRECT
VLOG(1) << "Failed to parse filter list";
```

---

## ✅ Prefer `std::string_view` Over `const char*` for Parameters

**Use `std::string_view` instead of `const char*` for function parameters that accept string data.** `std::string_view` is more flexible (accepts `std::string`, `const char*`, string literals) and carries size information.

```cpp
// ❌ WRONG
std::string_view GetDomain(const char* env_from_switch);

// ✅ CORRECT
std::string_view GetDomain(std::string_view env_from_switch);
```

---

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

## ❌ Don't Modify Production Code Solely to Accommodate Tests

**Test-specific workarounds should not affect production behavior.** Use test infrastructure like `kHostResolverRules` command line switches in `SetUpCommandLine` instead of adding production code paths only needed for tests.

**Exception:** Thin `ForTesting()` accessors that expose internalized features (e.g., `base::Feature`) are acceptable. These keep the feature internalized while providing a clean way for tests to reference it, and do not affect production behavior.

---

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

## ✅ Deprecate Prefs Before Removing Them

**When removing a preference that was previously stored in user profiles, first deprecate the pref (register it for clearing) in one release before fully removing it.** This ensures the old value is cleared from existing profiles.

---

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

## ✅ Use Delegates Instead of Raw Callbacks for Cross-Layer Dependencies

**When a component-level class needs platform-specific behavior, use a delegate pattern with a dedicated delegate class instead of passing raw callbacks.** Delegates provide cleaner interfaces, safer lifetime management, and better testability.

```cpp
// ❌ WRONG - raw callbacks for platform-specific behavior
class DefaultBrowserMonitor {
  base::RepeatingCallback<bool()> is_default_browser_callback_;
};

// ✅ CORRECT - delegate pattern
class DefaultBrowserMonitor {
  class Delegate {
   public:
    virtual bool IsDefaultBrowser() = 0;
  };
  std::unique_ptr<Delegate> delegate_;
};
```

---

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

## ❌ Don't Use Synchronous OSCrypt in New Code

**New code must use the async OSCrypt interface, not the legacy synchronous one.** The sync interface is deprecated. See `components/os_crypt/sync/README.md`.

```cpp
// ❌ WRONG - deprecated sync interface
OSCrypt::EncryptString(plaintext, &ciphertext);

// ✅ CORRECT - use async interface
os_crypt_async_->GetInstance(
    base::BindOnce(&MyClass::OnOSCryptReady, weak_factory_.GetWeakPtr()));
```

---

## ✅ Document Upstream Workarounds with Issue Links

**When adding a workaround for an upstream Chromium bug:**
1. Add a link to the upstream issue in a code comment
2. File details on the upstream issue explaining what's happening so they can fix it

This allows us to remove the workaround when the upstream fix lands.

```cpp
// ✅ CORRECT
// Workaround for https://crbug.com/123456 - upstream doesn't handle
// the case where X is null. Remove when the upstream fix lands.
if (!x) return;
```

---

## ✅ Use `tabs::TabHandle` Over Raw `WebContents*` for Stored References

**When storing tab references, prefer `tabs::TabHandle` (integer identifiers) over raw `WebContents*` pointers.** TabHandles are guaranteed not to accidentally point to a different tab, unlike raw pointers which can become dangling and be reused for a different allocation.

```cpp
// ❌ WRONG - raw pointer can dangle and point to wrong tab
std::vector<content::WebContents*> tabs_to_close_;

// ✅ CORRECT - integer IDs, safe from pointer reuse
std::vector<tabs::TabHandle> tabs_to_close_;
// Use TabInterface::GetFromWebContents to map WC to Handle
```

---

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

## ✅ Use `base::FixedArray` Over `std::vector` for Known-Size Runtime Allocations

**When the size is known at creation but not at compile time, use `base::FixedArray`.** It avoids heap allocation for small sizes and communicates immutable size.

```cpp
// ❌ WRONG - vector suggests dynamic resizing
std::vector<uint8_t> out(size);

// ✅ CORRECT - size is fixed after construction
base::FixedArray<uint8_t> out(size);
```

---

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

## ✅ Prefer Contiguous Containers Over Linked Lists

**Never use `std::list` for pure traversal — poor cache locality.** Use `std::list` only when stable iterators or frequent mid-container insert/remove is required. Prefer `std::vector` with `reserve()` for known sizes.

---

## ✅ Use `std::optional` Instead of Sentinel Values

**Never use empty string `""`, `-1`, or other magic values as sentinels for "no value".** Use `std::optional<T>`.

```cpp
// ❌ WRONG - "" as sentinel for "no custom title"
void SetCustomTitle(const std::string& title);  // "" means "unset"

// ✅ CORRECT - explicit optionality
void SetCustomTitle(std::optional<std::string> title);  // nullopt means "unset"
```

---

## ✅ Use `.emplace()` for `std::optional` Initialization Clarity

**When engaging a `std::optional` member, prefer `.emplace()` for clarity about the intent.**

```cpp
// Less clear
elapsed_timer_ = base::ElapsedTimer();

// ✅ CORRECT - explicit engagement intent
elapsed_timer_.emplace();
```

---

## ✅ Prefer Free Functions Over Complex Inline Lambdas

**When a lambda is complex enough to make surrounding code harder to parse, extract it into a named free function in the anonymous namespace.**

```cpp
// ❌ WRONG - complex lambda obscures call site
DoSomething(base::BindOnce([](int a, int b, int c) {
  // 20 lines of complex logic...
}));

// ✅ CORRECT - named function in anonymous namespace
namespace {
void ProcessResult(int a, int b, int c) {
  // 20 lines of complex logic...
}
}  // namespace
DoSomething(base::BindOnce(&ProcessResult));
```

---

## ✅ Consolidate Feature Flag Checks to Entry Points

**Don't scatter `CHECK`/`DCHECK` for feature flag status throughout the codebase.** Follow the upstream pattern: check at entry points only. Add comments on downstream functions like "Only called when X is enabled".

```cpp
// ❌ WRONG - CHECK in every function
void TabStripModel::SetCustomTitle(...) {
  CHECK(base::FeatureList::IsEnabled(kRenamingTabs));
}
void TabStripModel::ClearCustomTitle(...) {
  CHECK(base::FeatureList::IsEnabled(kRenamingTabs));
}

// ✅ CORRECT - check at entry point, comment downstream
void OnTabContextMenuAction(int action) {
  if (!base::FeatureList::IsEnabled(kRenamingTabs)) return;
  model->SetCustomTitle(...);  // Only called when kRenamingTabs enabled
}
```

---

## ✅ Prefer Overloads Over Silently-Ignored Optional Parameters

**Don't force callers to provide parameters that are silently ignored.** Use function overloads. Similarly, prefer overloads over `std::variant` for distinct call patterns.

```cpp
// ❌ WRONG - body_value silently ignored for GET/HEAD
void ApiFetch(const std::string& verb, const std::string& url,
              const base::Value& body_value, Callback cb);

// ✅ CORRECT - separate overloads
void ApiFetch(const std::string& url, Callback cb);  // GET
void ApiFetch(const std::string& url, const base::Value& body, Callback cb);  // POST
```

---

## ✅ Don't Store Error State - Handle/Log and Store Only Success

**When a field can hold either a success or error, handle/log the error immediately and store only the success type.**

```cpp
// ❌ WRONG - storing error variant
base::expected<ChainMetadata, std::string> chain_metadata_;

// ✅ CORRECT - handle error at failure point, store only success
std::optional<ChainMetadata> chain_metadata_;
```

---

## ❌ Don't Introduce New Uses of Deprecated APIs

**When an API is marked deprecated, never introduce new uses.** Check headers for deprecation notices before using unfamiliar APIs.

```cpp
// ❌ WRONG - base::Hash deprecated for 6+ years
uint32_t hash = base::Hash(str);

// ✅ CORRECT - use the recommended replacement
uint32_t hash = base::FastHash(base::as_byte_span(str));
```

---

## ✅ Security Review for Unrestricted URL Inputs in Mojom

**When creating mojom interfaces that accept URL parameters from less-privileged processes, consider restricting to an allowlist or enum** rather than accepting arbitrary URLs. An unrestricted URL parameter means the renderer can send requests to any endpoint.

**When NOT to flag:** If the implementation already validates or filters the URL downstream, do not request documentation comments about it. Before flagging, check whether similar patterns in surrounding code or elsewhere in the codebase have such comments — if they don't, your suggestion would introduce inconsistency and unnecessary verbosity.

---

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

## ✅ Use `base::StrAppend` Over `+= base::StrCat`

**When appending to an existing string, use `base::StrAppend(&str, {...})` instead of `str += base::StrCat({...})`.** `StrCat` creates a temporary string that is then copied; `StrAppend` appends directly to the target, avoiding unnecessary allocation.

```cpp
// ❌ WRONG - temporary string then copy
result += base::StrCat({kOpenTag, "\n", "=== METADATA ===\n"});

// ✅ CORRECT - append directly
base::StrAppend(&result, {kOpenTag, "\n", "=== METADATA ===\n"});
```

---

## ✅ Use `base::DoNothing()` for No-Op Callbacks

**Use `base::DoNothing()` instead of empty lambdas when a no-op callback is needed.** It is the Chromium-idiomatic way and is more readable.

```cpp
// ❌ WRONG - empty lambda
service->DoAsync([](const std::string&) {});

// ✅ CORRECT
service->DoAsync(base::DoNothing());
```

---

## ✅ Use `DLOG(ERROR)` for Non-Critical Debug-Only Errors

**Use `DLOG(ERROR)` instead of `LOG(ERROR)` for error conditions that are not critical in release builds.** This avoids polluting release build logs with non-actionable errors.

```cpp
// ❌ WRONG - release log noise for non-critical error
LOG(ERROR) << "Failed to parse optional field";

// ✅ CORRECT - debug-only logging
DLOG(ERROR) << "Failed to parse optional field";
```

---

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

## ✅ Use `absl::StrFormat` Over `base::StringPrintf`

**Prefer `absl::StrFormat` for formatted string construction.** `base::StringPrintf` is being deprecated in favor of `absl::StrFormat`.

```cpp
// ❌ WRONG - deprecated
std::string msg = base::StringPrintf("Error %d: %s", code, desc.c_str());

// ✅ CORRECT
std::string msg = absl::StrFormat("Error %d: %s", code, desc);
```

---

## ✅ Use `base::expected<T, E>` Over Optional + Error Out-Parameter

**When a function can fail and needs to communicate error details, use `base::expected<T, E>` instead of `std::optional<T>` with a separate error out-parameter.** This bundles success and error into a single return value.

```cpp
// ❌ WRONG - separate error out-parameter
std::optional<Result> Parse(const std::string& input, std::string* error);

// ✅ CORRECT - base::expected bundles both
base::expected<Result, std::string> Parse(const std::string& input);
```

---

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

## ✅ Pass-by-Value for Sink Parameters (Google Style)

**Per Google C++ Style Guide, use pass-by-value for parameters that will be moved into the callee** (sink parameters) instead of `T&&`. The caller uses `std::move()` either way, and pass-by-value is simpler.

```cpp
// ❌ WRONG - rvalue reference parameter
void SetName(std::string&& name) { name_ = std::move(name); }

// ✅ CORRECT - pass by value
void SetName(std::string name) { name_ = std::move(name); }
```

---

## ✅ Use `reset_on_disconnect()` for Simple Mojo Cleanup

**For simple Mojo remote cleanup on disconnection (just resetting the remote), use `remote.reset_on_disconnect()`** instead of setting up a manual disconnect handler.

```cpp
// ❌ WRONG - manual disconnect handler just to reset
remote_.set_disconnect_handler(
    base::BindOnce(&MyClass::OnDisconnect, base::Unretained(this)));
void OnDisconnect() { remote_.reset(); }

// ✅ CORRECT - built-in reset on disconnect
remote_.reset_on_disconnect();
```

---

## ✅ Annotate Obsolete Pref Migration Entries with Dates

**When adding preference migration code that removes deprecated prefs, annotate the entry with the date it was added.** This makes it easy to identify and clean up old migration code later.

```cpp
// ❌ WRONG - no context for when this was added
profile_prefs->ClearPref(kOldFeaturePref);

// ✅ CORRECT - annotated with date
profile_prefs->ClearPref(kOldFeaturePref);  // Added 2025-01 (safe to remove after ~3 releases)
```

---

## ✅ `base::DoNothing()` Doesn't Match `base::FunctionRef` Signatures

**`base::DoNothing()` cannot be used where a `base::FunctionRef<void(T&)>` is expected.** In those cases, use an explicit no-op lambda instead.

```cpp
// ❌ WRONG - won't compile
service->ForEach(base::DoNothing());  // FunctionRef<void(Item&)>

// ✅ CORRECT - explicit lambda
service->ForEach([](Item&) {});
```

---

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

## ✅ Use `host_piece()` Over `host()` on GURL

**When comparing or checking GURL hosts, prefer `host_piece()` over `host()`.** `host_piece()` returns a `std::string_view` (zero-copy) while `host()` returns a `std::string` (allocates).

```cpp
// ❌ WRONG - unnecessary allocation
if (url.host() == "search.brave.com") { ... }

// ✅ CORRECT - zero-copy comparison
if (url.host_piece() == "search.brave.com") { ... }
```

---

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

## ✅ Use `kOsAll` for Cross-Platform Feature Flags

**When registering feature flags in `about_flags.cc` that should be available on all platforms, use `kOsAll`** instead of listing individual platform constants.

```cpp
// ❌ WRONG - listing platforms individually
{"brave-my-feature", ..., kOsDesktop | kOsAndroid}

// ✅ CORRECT - use kOsAll
{"brave-my-feature", ..., kOsAll}
```

---

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

## ✅ Prefer `constexpr int` Over Single-Value Enums

**When a constant is just a single numeric value, use `constexpr int` rather than creating a single-value enum.** Enums are for sets of related values.

```cpp
// ❌ WRONG - enum for a single value
enum { kBravePolicySource = 10 };

// ✅ CORRECT - constexpr int
constexpr int kBravePolicySource = 10;
```

---

## ✅ Use `base::FilePath` for File Path Parameters

**Parameters representing file system paths should use `base::FilePath` instead of `std::string`.** This provides type safety, simplifies call sites, and makes APIs self-documenting.

```cpp
// ❌ WRONG - generic string for a path
std::string GetProfileId(const std::string& profile_path);

// ✅ CORRECT - domain-specific type
std::string GetProfileId(const base::FilePath& profile_path);
```

---

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

## ✅ Use `observers_.Notify()` Instead of Manual Iteration

**Use `observers_.Notify(&Observer::Method)` instead of manually iterating observer lists.**

```cpp
// ❌ WRONG - manual iteration
for (auto& observer : observers_) {
  observer.OnPoliciesChanged();
}

// ✅ CORRECT - use Notify helper
observers_.Notify(&Observer::OnPoliciesChanged);
```

---

## ✅ Multiply Before Dividing in Integer Percentage Calculations

**When computing percentages with integer arithmetic, multiply by 100 before dividing.** `(used * 100) / total` preserves precision, while `(used / total) * 100` truncates to 0 when `used < total`.

```cpp
// ❌ WRONG - truncates to 0 for used < total
int pct = (used / total) * 100;

// ✅ CORRECT - preserves precision
int pct = (used * 100) / total;
```

---
