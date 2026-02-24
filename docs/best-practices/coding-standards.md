# C++ Coding Standards

## ✅ Always Include What You Use (IWYU)

**Always include the headers for types you directly use.** Don't rely on transitive includes from other headers - they can change at any time and break your code.

```cpp
// ❌ WRONG - relying on transitive includes
#include "base/memory/ref_counted.h"
// Uses std::string but doesn't include <string>

// ✅ CORRECT - include what you use
#include <string>
#include "base/memory/ref_counted.h"
```

Also remove includes you don't actually use. Double-check all includes in new files.

**For type aliases:** include the header that declares the type alias, not the headers for the underlying types. Same principle as class inheritance — if class B inherits from A, include B's header, not A's.

---

## Naming Conventions

### ✅ Use Positive Form for Booleans and Methods

**Always use the positive form ("Enabled" not "Disabled") for readability and consistency.**

```cpp
// ❌ WRONG - negative form is confusing
bool IsTorDisabled();
pref: kTorDisabled

// ✅ CORRECT - positive form
bool IsTorEnabled();
pref: kTorEnabled
```

### ✅ Consistent Naming Across Layers

**Use the same name for a concept everywhere - C++, JS, prefs, and UI.** Don't arbitrarily use different names in different places for the same thing.

```cpp
// ❌ WRONG - different names for same concept
C++: IsTorDisabledManaged()
JS:  getTorManaged()

// ✅ CORRECT - consistent naming
C++: IsTorManaged()
JS:  isTorManaged()
```

### ✅ Use Conventional Method Prefixes

- `Should*` methods for queries (not `Get*` for bool queries)
- `Record*` for histogram/P3A recording
- `Load*`/`Save*` pairs for persistence

```cpp
// ❌ WRONG
bool GetShouldShowBrandedWallpaper();
void SendSavingsDaily();

// ✅ CORRECT
bool ShouldShowBrandedWallpaper();
void RecordSavingsDaily();
void LoadSavingsDaily();
void SaveSavingsDaily();
```

### ✅ Grammatical Correctness

```cpp
// ❌ WRONG
bool IsBraveCommandIds(int id);  // "Ids" is not grammatically correct

// ✅ CORRECT
bool IsBraveCommandId(int id);
```

---

## Ownership and Memory Management

### ✅ Comment Non-Owned Raw Pointers

**Raw pointers to non-owned objects should be commented with `// not owned`.** This is a Chromium convention.

```cpp
// ✅ CORRECT
ThirdPartyExtractor* third_party_extractor_ = nullptr;  // not owned
```

### ✅ Prefer unique_ptr Over new/delete

**Avoid manual new/delete. Use unique_ptr, stack variables, or member initializer lists.**

```cpp
// ❌ WRONG - manual new/delete
void Init() {
  predictor_ = new BandwidthSavingsPredictor(extractor);
  // ...
  delete predictor_;
}

// ✅ CORRECT - use unique_ptr or member initializer list
: predictor_(std::make_unique<BandwidthSavingsPredictor>(extractor))
```

### ❌ Don't Take Ownership of Unowned Resources

If a class doesn't own a resource, don't create ownership wrappers for it. This is a common source of crashes (see also architecture.md on shared_ptr misuse).

---

## ✅ Use CHECK for Impossible Conditions

**Use `CHECK` (not `DCHECK`) for conditions that should never happen in any build.**

```cpp
// ❌ WRONG - DCHECK for something that should never happen
DCHECK(browser_context);

// ✅ CORRECT - CHECK for impossible conditions
CHECK(browser_context);  // should never be null
```

Also: don't add unnecessary DCHECKs. For example, `DCHECK(g_browser_process)` is unnecessary because the browser wouldn't even be running without it.

---

## ✅ Use Anonymous Namespaces for Internal Code

**If a function or class is strictly internal to a .cc file, put it in an anonymous namespace.**

```cpp
// ❌ WRONG - internal helper visible outside file
static void InternalHelper() { ... }

// ✅ CORRECT - anonymous namespace
namespace {
void InternalHelper() { ... }
}  // namespace
```

**No `static` on `constexpr` inside anonymous namespaces** — the namespace already provides internal linkage, so `static` is redundant.

```cpp
// ❌ WRONG - redundant static
namespace {
static constexpr int kMaxRetries = 3;
}

// ✅ CORRECT
namespace {
constexpr int kMaxRetries = 3;
}
```

---

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

## Lint and Style

- **Opening brace** goes at the end of the previous line (K&R style)
- **Continuation lines** should be indented 4 spaces
- **No `{}` when not required** in C++ (e.g., single-line if/for bodies)

---

## ✅ C++ Variable Naming - Underscores, Not camelCase

**C++ variables use underscores (snake_case), not camelCase.** camelCase is only for class names and method names.

```cpp
// ❌ WRONG
bool isTorDisabled = false;
std::string userName;

// ✅ CORRECT
bool is_tor_disabled = false;
std::string user_name;
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

## ✅ Platform-Specific Code Splitting

**When a method's implementation is completely different on a platform, split it into a separate file** like `my_class_android.cc` rather than filling the main file with `#if defined(OS_ANDROID)` blocks.

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

## ✅ Copyright Rules

**Never copy a Chromium file and use Brave's copyright.** If you copy or derive from Chromium code, you must include their copyright notice. The original year should remain unchanged - don't bump existing copyright years.

---

## ✅ Naming: Only Use `Brave*` Prefix When Overriding Chromium

**Only add the `Brave*` prefix to class names when overriding or subclassing Chromium classes.** For purely Brave-originated code, use the feature name directly.

```cpp
// ❌ WRONG - Brave prefix on a new Brave-only class
class BraveWebcompatReporterService { ... };

// ✅ CORRECT - no prefix needed for Brave-only code
class WebcompatReporterService { ... };

// ✅ CORRECT - Brave prefix when overriding Chromium
class BraveOmniboxController : public OmniboxController { ... };
```

Also: **filename should match the class name.** `WebcompatReporterService` -> `webcompat_reporter_service.h`.

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

## ❌ Don't Define Methods in Headers

**Move method definitions to .cc files.** Headers should only contain declarations. Keep headers minimal - only include what's strictly required for the declarations.

```cpp
// ❌ WRONG - method body in header
class RewardsProtocolHandler {
  static bool HandleURL(const GURL& url) {
    return url.scheme() == "rewards";
  }
};

// ✅ CORRECT - declaration in header, definition in .cc
// rewards_protocol_handler.h
bool HandleRewardsProtocol(const GURL& url);

// rewards_protocol_handler.cc
bool HandleRewardsProtocol(const GURL& url) {
  return url.scheme() == "rewards";
}
```

Also: `static` has no meaning for free functions in C++ (it's a C holdover). Use anonymous namespaces instead.

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

## ✅ Naming: `Maybe*` for Conditional Actions

**Use `Maybe*` prefix for functions that conditionally perform an action.**

```cpp
// ❌ WRONG
void ShowFirstLaunchNotification();  // always sounds like it shows

// ✅ CORRECT
void MaybeShowFirstLaunchNotification();  // clear that it may not show
void MaybeHideReferrer();
```

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

## ✅ Break Up Bloated Files

**Don't keep dumping code into already-large files.** Encapsulate related functionality into smaller, focused helper files and targets. This improves readability, reduces rebase conflicts, and makes dependency tracking easier.

```cpp
// ❌ WRONG - adding more P3A code to 5000-line RewardsServiceImpl
void RewardsServiceImpl::RecordP3AMetric1() { ... }
void RewardsServiceImpl::RecordP3AMetric2() { ... }

// ✅ CORRECT - separate helper file
// brave/browser/p3a/brave_p3a_utils.h
void RecordRewardsP3A(RewardsService* service);
```

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

## ✅ Use `SEQUENCE_CHECKER` Consistently - All Methods or None

**If a class is single-threaded, either apply `DCHECK_CALLED_ON_VALID_SEQUENCE` to all methods or remove the sequence checker entirely.** Partial checking is misleading and makes correct code look unsafe.

---

## ✅ Invalidate WeakPtrs During Teardown

**Call `weak_factory_.InvalidateWeakPtrs()` at the start of shutdown/cleanup.** Without this, pending callbacks can fire on partially-destroyed objects.

```cpp
// ❌ WRONG - teardown without invalidating
void MyClass::Shutdown() {
  CleanupResources();
}

// ✅ CORRECT - invalidate first
void MyClass::Shutdown() {
  weak_factory_.InvalidateWeakPtrs();
  CleanupResources();
}
```

---

## ✅ Always Check WeakPtr Validity Before Use

**Always check a `base::WeakPtr` is valid before dereferencing, especially after async operations.** Add thread checkers to methods using WeakPtrs.

```cpp
// ❌ WRONG
void OnCallback() {
  request_->Complete(result);  // request_ could be invalid!
}

// ✅ CORRECT
void OnCallback() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!request_)
    return;
  request_->Complete(result);
}
```

---

## ✅ Clean Up Resources in `KeyedService::Shutdown`

**For `KeyedService` implementations, clean up owned resources in `Shutdown()`, not just the destructor.** The service graph has dependencies requiring orderly teardown.

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

## ❌ `shared_ptr` Is Banned in Chromium Code

**Do not use `std::shared_ptr` - it is on the Chromium banned features list.** Use `base::RefCounted` / `scoped_refptr` when shared ownership is truly needed, or restructure to use unique ownership.

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

## ✅ Add Thread Checks to `base::Bind` Callback Targets

**Methods used as targets of `base::BindOnce` / `base::BindRepeating` should include `DCHECK_CALLED_ON_VALID_SEQUENCE` to ensure correct thread.**

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

## ✅ Use Forward Declarations in Headers, Include in `.cc`

**Headers should use forward declarations instead of `#include` for types only used as pointers or references.** Move the full `#include` to the `.cc` file.

```cpp
// ❌ WRONG - full include in header for pointer-only usage
// my_class.h
#include "components/foo/bar.h"

// ✅ CORRECT - forward declare in header, include in .cc
// my_class.h
namespace foo { class Bar; }
// my_class.cc
#include "components/foo/bar.h"
```

---

## ✅ `friend` Declarations Go Right After `private:`

**In class declarations, `friend` statements should be placed immediately after the `private:` access specifier,** before any member variables or methods.

```cpp
// ❌ WRONG
class MyClass {
 private:
  int value_ = 0;
  friend class MyClassTest;  // buried among members
};

// ✅ CORRECT
class MyClass {
 private:
  friend class MyClassTest;

  int value_ = 0;
};
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

## ❌ Don't Log Sensitive Information

**Never log sensitive data such as sync seeds, private keys, tokens, or credentials.** Even VLOG-level logging can expose data in debug builds.

```cpp
// ❌ WRONG
VLOG(1) << "Sync seed: " << sync_seed;

// ✅ CORRECT
VLOG(1) << "Sync seed set successfully";
```

---

## ✅ Prefer `base::WeakPtrFactory` Over `SupportsWeakPtr`

**Use `base::WeakPtrFactory<T>` as a member rather than inheriting from `base::SupportsWeakPtr<T>`.** WeakPtrFactory performs more safety checks and is the recommended pattern.

```cpp
// ❌ WRONG
class MyClass : public base::SupportsWeakPtr<MyClass> {};

// ✅ CORRECT
class MyClass {
  base::WeakPtrFactory<MyClass> weak_factory_{this};  // must be last member
};
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

## ❌ Never Use `base::Unretained` with Thread Pool

**Never use `base::Unretained` when posting work to thread pools.** Instead, run OS-specific or blocking functions on the thread pool and handle results on the main thread via `PostTaskAndReplyWithResult` with a WeakPtr. Using `Unretained` across threads leads to use-after-free.

```cpp
// ❌ WRONG - Unretained across threads causes UaF
base::ThreadPool::PostTask(
    FROM_HERE, base::BindOnce(&MyClass::DoWork, base::Unretained(this)));

// ✅ CORRECT - static function on pool, weak reply on main thread
base::ThreadPool::PostTaskAndReplyWithResult(
    FROM_HERE, base::BindOnce(&DoBlockingWork),
    base::BindOnce(&MyClass::OnWorkDone, weak_factory_.GetWeakPtr()));
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

## ✅ `NOTREACHED`/`CHECK(false)` Only for Security-Critical Invariants

**`NOTREACHED`/`CHECK(false)` should only crash the browser for security-critical invariants.** For non-security cases (like invalid enum values from data processing), prefer returning `std::optional`/`std::nullopt` or a default value.

```cpp
// ❌ WRONG - crashes browser for non-security enum mismatch
mojom::AdType ToMojomAdType(const std::string& type) {
  // ...
  NOTREACHED();  // This isn't a security issue!
}

// ✅ CORRECT - return optional for non-security case
std::optional<mojom::AdType> ToMojomAdType(const std::string& type) {
  // ...
  return std::nullopt;  // Caller handles gracefully
}
```

---

## ✅ Feature Flag Comments Go in `.cc` Files

**Comments explaining what a `base::Feature` does should be placed in the `.cc` file where the feature is defined, not in the `.h` file.**

```cpp
// ❌ WRONG - feature comment in .h
// my_features.h
// Enables the new tab workaround for flash prevention.
BASE_DECLARE_FEATURE(kBraveWorkaroundNewWindowFlash);

// ✅ CORRECT - feature comment in .cc
// my_features.cc
// Enables the new tab workaround for flash prevention.
BASE_FEATURE(kBraveWorkaroundNewWindowFlash, ...);
```

---

## ✅ Unsubscribe Observers in `::Shutdown()` Even with `ScopedObservation`

**`ScopedObservation` can still lead to use-after-free.** Always explicitly unsubscribe observers and pref registrars in `KeyedService::Shutdown()`. Event-triggered callbacks (like pref observers) can fire after your service's `Shutdown()` if another service triggers them during its own shutdown sequence.

```cpp
// ❌ WRONG - relying solely on ScopedObservation destructor
class MyService : public KeyedService {
  base::ScopedObservation<PrefService, PrefObserver> observation_{this};
};

// ✅ CORRECT - explicit unsubscribe in Shutdown
void MyService::Shutdown() {
  pref_change_registrar_.RemoveAll();
  observation_.Reset();
}
```

---

## ✅ Use `base::Unretained(this)` for Self-Owned Timer Callbacks

**When a class owns a `base::RepeatingTimer` or `base::OneShotTimer`, prefer `base::Unretained(this)`.** The timer is destroyed with the class, so it can only fire while `this` is valid. Using `WeakPtr` adds unnecessary overhead but is not functionally wrong — it's a style preference, not a correctness issue.

```cpp
// ⚠️ AVOID - unnecessary overhead (but not a bug)
timer_.Start(FROM_HERE, delay,
    base::BindRepeating(&MyClass::OnTimer, weak_factory_.GetWeakPtr()));

// ✅ PREFERRED - timer is owned, so this is always valid when it fires
timer_.Start(FROM_HERE, delay,
    base::BindRepeating(&MyClass::OnTimer, base::Unretained(this)));
```

**Key distinction:** This is the opposite of the "never use Unretained with thread pool" rule. The difference is ownership: you own the timer, so it cannot outlive you. If a developer prefers `WeakPtr` for defensive coding, that's a valid choice — do not insist on changing it.

---

## ✅ WeakPtr - Bind to Member Function, Not Lambda Capture

**When using WeakPtr with async callbacks, bind directly to a member function.** Don't capture a WeakPtr in a lambda — the weak_ptr could be invalidated before the lambda runs, and there's no automatic cancellation.

```cpp
// ❌ WRONG - weak_ptr captured in lambda, no automatic cancellation
auto weak_this = weak_ptr_factory_.GetWeakPtr();
rpc_->GetNetworkName(base::BindOnce(
    [](base::WeakPtr<MyService> self, Callback cb, const std::string& name) {
      if (!self) return;
      std::move(cb).Run(name);
    }, weak_this, std::move(callback)));

// ✅ CORRECT - weak_ptr bound to member function, auto-cancelled if invalid
rpc_->GetNetworkName(base::BindOnce(
    &MyService::OnGetNetworkName,
    weak_ptr_factory_.GetWeakPtr(),
    std::move(callback)));
```

---

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

## ✅ Function Ordering in `.cc` Should Match `.h`

**Function definitions in `.cc` files should appear in the same order as their declarations in the corresponding `.h` file.**

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

## ❌ Don't Use `auto` Where Style Guide Wants Explicit Types

**Don't use `auto` merely to avoid writing a type name.** Spell out types like `base::TimeDelta`, `base::Time`, etc. Per Google style guide: "Do not use [auto] merely to avoid the inconvenience of writing an explicit type."

```cpp
// ❌ WRONG - auto hides the type
auto elapsed = timer.Elapsed();

// ✅ CORRECT - explicit type
base::TimeDelta elapsed = timer.Elapsed();
```

---

## ✅ Member Initialization - Don't Add Default When Constructor Always Sets

Per Chromium C++ dos and donts: "Initialize class members in their declarations, **except where a member's value is explicitly set by every constructor**."

```cpp
// ❌ WRONG - misleading, constructor always sets this
class TreeTabNode {
  raw_ptr<TabInterface> current_tab_ = nullptr;  // never actually nullptr
  explicit TreeTabNode(TabInterface* tab);  // always sets current_tab_
};

// ✅ CORRECT - constructor handles initialization
class TreeTabNode {
  raw_ptr<TabInterface> current_tab_;
  explicit TreeTabNode(TabInterface* tab) : current_tab_(tab) {}
};
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

## ✅ Comments Must Make Sense to Future Readers of the Codebase

**Every comment should be meaningful to someone reading the code for the first time, with no knowledge of the PR or change history.** Do not add comments that reference removed code, prior behavior, or the change itself. Comments are part of the codebase, not a changelog.

```cpp
// ❌ WRONG - references removed code / change history
// Removed the old caching logic that was causing race conditions.
// Previously this used a raw pointer, now using unique_ptr.
// Changed from std::map to base::flat_map per review feedback.

// ❌ WRONG - describes what was removed rather than what exists
// The timeout parameter was removed since it's no longer needed.
int ProcessRequest(const GURL& url);

// ✅ CORRECT - describes the code as it is now
// Processes the request synchronously. Returns the HTTP status code.
int ProcessRequest(const GURL& url);

// ✅ CORRECT - explains current behavior, not history
// Uses base::flat_map for better cache locality with small key sets.
base::flat_map<std::string, int> lookup_;
```

---

## ✅ Document All New Classes, Public Methods, and Fields

**All new classes, public methods, and non-obvious fields must have documentation comments.** For IDL types, document dictionaries and fields.

---

## ✅ Document Non-Obvious Failure Branches

**When a function has multiple early-return failure branches, add a brief comment before each summarizing what it handles.**

```cpp
// ❌ WRONG - unclear what each branch handles
if (!parent_hash) return std::nullopt;
if (!state_root) return std::nullopt;
if (!number) return std::nullopt;

// ✅ CORRECT
// Parent block hash is required for chain continuity.
if (!parent_hash) return std::nullopt;
// State root validates the block's state trie.
if (!state_root) return std::nullopt;
// Block number must be present and valid.
if (!number) return std::nullopt;
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

## ✅ Use `CHECK` Only for Invariants Within Code's Control

**Use `CHECK` only for conditions fully within the code's control.** For data from databases, user input, or external sources, use graceful error handling instead. `CHECK` failures crash the user's browser.

```cpp
// ❌ WRONG - crashes on external data
CHECK(db_value.has_value());  // Data from database!

// ✅ CORRECT - graceful handling of external data
if (!db_value.has_value()) {
  DLOG(ERROR) << "Missing expected database value";
  return std::nullopt;
}
```

See also: [Chromium CHECK style guide](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/styleguide/c++/checks.md)

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

## ❌ Never Bind `std::vector<raw_ptr<T>>` in Callbacks

**Never capture `std::vector<raw_ptr<T>>` in async callbacks.** The raw pointers may dangle by the time the callback runs. Use `std::vector<base::WeakPtr<T>>` instead.

```cpp
// ❌ WRONG - raw_ptrs may dangle
base::BindOnce(&OnComplete, std::move(raw_ptr_vector));

// ✅ CORRECT - weak ptrs are safe
std::vector<base::WeakPtr<Tab>> weak_tabs;
for (auto* tab : tabs) {
  weak_tabs.push_back(tab->GetWeakPtr());
}
base::BindOnce(&OnComplete, std::move(weak_tabs));
```

---

## ✅ Place `raw_ptr<>` Members Last in Class Declarations

**In class declarations, place unowned `raw_ptr<>` members after owning members** (like `std::unique_ptr<>`). This follows Chromium convention and makes ownership semantics visually clear.

```cpp
// ❌ WRONG - mixed ownership order
class MyService {
  raw_ptr<PrefService> prefs_;
  std::unique_ptr<Fetcher> fetcher_;
  raw_ptr<ProfileManager> profile_manager_;
};

// ✅ CORRECT - owning members first, then unowned
class MyService {
  std::unique_ptr<Fetcher> fetcher_;
  raw_ptr<PrefService> prefs_;
  raw_ptr<ProfileManager> profile_manager_;
};
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

## ✅ Copyright Year in New Files Must Be Current Year

**New files must use the current year in the copyright header.** Always determine the current year from the system date (e.g., `date +%Y`), never from training data or memory — the training cutoff year is often outdated. Don't copy-paste old copyright years from other files.

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

## ✅ Consider `base::SequenceBound` for Thread-Isolated Operations

**When a class performs blocking or IO operations and needs to be accessed asynchronously from the UI thread, use `base::SequenceBound<T>`.** This binds the object to a specific task runner and automatically posts all calls to that sequence.

```cpp
// ❌ WRONG - manual thread management
class ContentScraper {
  void Process(const std::string& html);  // blocking
};
// Caller must manually post to thread pool and bind weak ptr

// ✅ CORRECT - SequenceBound handles threading
base::SequenceBound<ContentScraper> scraper_;
scraper_.AsyncCall(&ContentScraper::Process).WithArgs(html);
```

---

## ✅ Explicitly Specify `base::TaskPriority` in Thread Pool Tasks

**When posting tasks to the thread pool, explicitly specify `base::TaskPriority` and shutdown behavior** rather than relying on defaults. Use `BEST_EFFORT` for non-urgent work and `SKIP_ON_SHUTDOWN` when work can be safely abandoned.

```cpp
// ❌ WRONG - implicit priority
base::ThreadPool::PostTask(FROM_HERE, {base::MayBlock()}, task);

// ✅ CORRECT - explicit priority and shutdown behavior
base::ThreadPool::PostTask(
    FROM_HERE,
    {base::MayBlock(), base::TaskPriority::BEST_EFFORT,
     base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
    task);
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

## ❌ Don't Use Positional Terms in Code Comments

**Do not use "above" or "below" in comments to reference other code.** Other developers may insert code between the comment and referenced item, breaking the meaning. Reference items explicitly by name or identifier instead.

```cpp
// ❌ WRONG - fragile positional reference
// Same root cause as the test above
-BrowserTest.SomeOtherTest

// ✅ CORRECT - explicit reference by name
// Same root cause as BrowserTest.FirstTest (kPromptForDownload override)
-BrowserTest.SomeOtherTest
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

## ✅ VLOG Component Name Should Match Directory

**The component name used in VLOG messages should match the component directory name** (e.g., `policy` or `brave/components/brave_policy`).

---

## ❌ Don't Use `public:` in Structs

**Do not use `public:` labels in struct declarations since struct members are public by default.** Either remove the label or change `struct` to `class` if access control is intended.

```cpp
// ❌ WRONG - redundant public label
struct TestData {
 public:
  std::string name;
  int value;
};

// ✅ CORRECT - struct is public by default
struct TestData {
  std::string name;
  int value;
};
```

---

## ✅ Prefer `GlobalFeatures` Over `NoDestructor` for Global Services

**For global/singleton services, prefer registering in `GlobalFeatures` (the Chromium replacement for `BrowserProcessImpl`) over `base::NoDestructor`.** `NoDestructor` makes testing difficult since you can't reset the instance between tests.

```cpp
// ❌ WRONG - hard to test
BraveOriginState* BraveOriginState::GetInstance() {
  static base::NoDestructor<BraveOriginState> instance;
  return instance.get();
}

// ✅ CORRECT - register in GlobalFeatures for testability
// Access via g_browser_process or dependency injection
```
