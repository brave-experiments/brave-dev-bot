# C++ Style, Naming, and Organization

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

## ✅ Platform-Specific Code Splitting

**When a method's implementation is completely different on a platform, split it into a separate file** like `my_class_android.cc` rather than filling the main file with `#if defined(OS_ANDROID)` blocks.

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

## ✅ Function Ordering in `.cc` Should Match `.h`

**Function definitions in `.cc` files should appear in the same order as their declarations in the corresponding `.h` file.**

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

## ✅ Copyright Year in New Files Must Be Current Year

**New files must use the current year in the copyright header.** Always determine the current year from the system date (e.g., `date +%Y`), never from training data or memory — the training cutoff year is often outdated. Don't copy-paste old copyright years from other files.

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

## ✅ VLOG Component Name Should Match Directory

**The component name used in VLOG messages should match the component directory name** (e.g., `policy` or `brave/components/brave_policy`).

---
