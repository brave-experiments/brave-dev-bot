# Architecture: Layering and Dependencies

## Chromium Dependency Layer Hierarchy

All Chromium code is organized into layers with strict downward-only dependencies. **Code in a lower layer must never depend on a higher layer.**

```
┌─────────────────────────────────────────────────────┐
│  //chrome, //android_webview, //ios, ...            │  ← Embedders (top-level apps)
├─────────────────────────────────────────────────────┤
│  //components                                       │  ← Optional reusable features
├─────────────────────────────────────────────────────┤
│  //content (Content API)                            │  ← Multi-process web platform
├─────────────────────────────────────────────────────┤
│  //net, //ui, ...                                   │  ← Core libraries
├─────────────────────────────────────────────────────┤
│  //base                                             │  ← Foundation
└─────────────────────────────────────────────────────┘
```

**Key rules:**
- Dependencies flow **downward only** — never upward
- `//components` is for optional features shared across multiple embedders (Chrome, Android WebView, iOS, etc.)
- Components may depend on `//content`, `//net`, `//base`, and other components — but never on embedder code (`//chrome`, `//android_webview`)
- Components shared with iOS must either have **zero `//content` dependencies** or use a **layered component structure** (`core/` + `content/`)
- In Brave: `brave/browser/` is the embedder layer, `brave/components/` is the components layer. The same downward-only rules apply.

---

## ❌ No Layering Violations - Components Cannot Depend on Browser

**Code in `components/` must never use `g_browser_process` or depend on `brave/browser/`.**

This is a Chromium layering violation. Components are lower-level and must not reference browser-layer code. Fix by passing dependencies via injection (constructor params, `Init()` methods, callbacks).

**BAD:**
```cpp
// ❌ WRONG - components/ code using g_browser_process
// In components/p3a/brave_p3a_service.cc
void BraveP3AService::Init() {
  uploader_.reset(new BraveP3AUploader(
      g_browser_process->shared_url_loader_factory(), ...));  // Layering violation!
}
```

**GOOD:**
```cpp
// ✅ CORRECT - dependency injected via Init()
// In components/p3a/brave_p3a_service.cc
void BraveP3AService::Init(
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory) {
  uploader_.reset(new BraveP3AUploader(url_loader_factory, ...));
}
```

Similarly, code in `components/safe_browsing/` cannot have `brave/browser/` deps. Separate browser-dependent callbacks from component code.

**Specific rules:**
- Never use `Profile` in components - pass `PrefService` instead (use `user_prefs::UserPrefs::Get(browser_context)`)
- Never include `brave/browser/` or `chrome/browser/` from `components/`
- Use `BrowserContext` instead of `Profile` in components

---

## ✅ Pass the Most Specific Dependency, Not "Bag of Stuff" Objects

**Always pass the most fundamental object a function actually needs, not a broader object it could extract it from.** This follows from the Chromium componentization cookbook: "Pass the most fundamental objects possible, rather than passing more complex 'everything' or 'bag of stuff' objects."

```cpp
// ❌ WRONG - passing Profile when only prefs are needed
void MyComponent::Init(Profile* profile) {
  enabled_ = profile->GetPrefs()->GetBoolean(kMyPref);
}

// ✅ CORRECT - pass only what's needed
void MyComponent::Init(PrefService* prefs) {
  enabled_ = prefs->GetBoolean(kMyPref);
}
```

Common substitutions:
- `Profile*` → `PrefService*` (when only prefs are needed)
- `Profile*` → `BrowserContext*` (in components)
- `BrowserContext*` → `scoped_refptr<URLLoaderFactory>` (when only network is needed)

---

## ❌ Never Access Internal/Vendor Headers Directly

**Never use `#include "brave/vendor/..."` to access internal headers.** Internal headers are not part of the public API and should not be accessed using full paths to bypass visibility.

```cpp
// ❌ WRONG - accessing internal headers via full vendor path
#include "brave/vendor/bat-native-ads/src/bat/ads/internal/locale_helper.h"

// ✅ CORRECT - use the public API header
#include "brave/components/brave_ads/browser/locale_helper.h"
```

---

## ✅ Use Abstract Base Classes to Avoid Layering Violations

**When browser-layer code needs to be accessed from components, create an abstract base class in components and implement it in browser.**

```cpp
// ✅ In components/ - abstract interface
class BraveOmniboxClient {
 public:
  virtual bool IsAutocompleteEnabled() = 0;
};

// ✅ In browser/ - concrete implementation
class BraveOmniboxClientImpl : public BraveOmniboxClient {
  bool IsAutocompleteEnabled() override { ... }
};
```

Then cast to the abstract type in components without a layering violation.

---

## ✅ File Organization by Component

**Group files by component, not by platform.** For example, `brave_rewards/android/` is preferred over `android/rewards/`.

```
# ❌ WRONG
brave/browser/android/rewards/brave_rewards_native_worker.cc

# ✅ CORRECT
brave/components/brave_rewards/android/brave_rewards_native_worker.cc
```

This keeps related code together and is consistent with Chromium patterns like `chrome/browser/history/android/`.

---

## ✅ Exclude Entire Feature API from GN When Disabled

**When a feature is disabled via buildflag, exclude the entire API from the build.** Don't leave API declarations with no implementation.

```gn
# ❌ WRONG - API always built, implementation conditionally empty
source_set("wallet_api") {
  sources = [ "wallet_api.cc" ]  # has empty stubs when disabled
}

# ✅ CORRECT - entire API excluded
if (brave_wallet_enabled) {
  source_set("wallet_api") {
    sources = [ "wallet_api.cc" ]
  }
}
```

---

## ✅ source_set Name Should Match Directory

**GN source_set names should match their directory name.** This makes paths predictable and readable.

```gn
# ❌ WRONG
# In brave/components/brave_referrals/BUILD.gn
source_set("referrals") { ... }
# Referenced as //brave/components/brave_referrals:referrals

# ✅ CORRECT
source_set("browser") { ... }
# Referenced as //brave/components/brave_referrals/browser
```

---

## ❌ No Content-Layer Dependencies for iOS-Targeted Components

**Components that must build for iOS (like `brave_wallet`) cannot depend on content-layer types** (`content::WebContents`, `content::BrowserContext`). iOS uses WebKit, not Chromium's content layer. Pass specific dependencies (`PrefService*`, `URLLoaderFactory`) instead.

---

## ✅ Use Layered Component Structure (`core/` + `content/`) for iOS-Compatible Components

**When a component needs to work on both iOS and content-based platforms, use a layered component structure.** Split the component into `core/` (iOS-compatible, no `//content` dependency) and `content/` (uses `//content` APIs). This follows the Chromium componentization cookbook pattern.

```
components/brave_shields/
├── core/           # iOS-compatible code, no //content deps
│   ├── browser/    # Browser-process logic (no content types)
│   ├── common/     # Shared across processes
│   └── test/
└── content/        # Content-layer integration (WebContents, etc.)
    ├── browser/    # Browser-process code using content types
    └── test/
```

**Rules:**
- `core/` must never depend on `//content` or `content/` subdirectories
- `content/` may depend on `core/` and `//content`
- iOS builds only pull in `core/`
- Business logic belongs in `core/`; content-layer glue belongs in `content/`

---

## ❌ No Circular Dependencies Between Components

**Component dependencies must form a strictly tree-shaped graph — no circular dependencies.** If component A depends on component B, then B must never depend on A (directly or transitively). Use delegate interfaces or observers to break cycles.

---

## ❌ Avoid Inverted Dependency Direction Between Related Components

**Foundational components must not depend on higher-level features built upon them.** Even when there's no circular dependency, the semantic direction matters. If component A is the foundation that component B builds upon, A should never depend on B.

```
# ❌ WRONG - foundational component depends on feature built upon it
# brave_account is the auth foundation; email_aliases is a feature that uses it
# In components/brave_account/BUILD.gn
deps = [
  "//brave/components/email_aliases:features",  # Inverted!
]

# ✅ CORRECT - use a registration/callback mechanism
# Features register themselves as "account enablers" so the foundation
# doesn't need to know about specific features
```

When a foundational component needs to react to higher-level features (e.g., "enable account if any dependent feature is enabled"), use a registration or callback mechanism rather than hardcoding the dependency. This prevents the pattern from growing as more features are added.

---

## ✅ Service/Decoder Code Belongs in `services/` Not `components/.../browser/`

**Mojo service implementations and data decoders should live in a `services/` directory**, not inside `components/.../browser/`. This follows Chromium conventions and keeps service code at the correct architectural layer.

---

## ❌ Utility Process Code Must Not Depend on Browser Process Code

**Code that runs in the utility process must never depend on browser process code.** Any code shared between the browser process and the utility process must live in a `common/` directory, not a `browser/` directory.

This is a multi-process architecture boundary. The utility process (where sandboxed services run) is a separate process from the browser process, and dependency direction must be respected:

- `components/.../browser/` — browser process only
- `components/.../common/` — shared between processes (browser, utility, renderer)
- `components/services/...` — utility process service implementations

```
# ❌ WRONG - utility process service depending on browser/ code
# In components/services/brave_shields/BUILD.gn
deps = [
  "//brave/components/brave_shields/core/browser/adblock",  # Browser-only!
]

# ✅ CORRECT - shared code moved to common/
# In components/services/brave_shields/BUILD.gn
deps = [
  "//brave/components/brave_shields/core/common/adblock",  # Shared!
]
```

When code needs to be used by both processes, move it from `browser/` to `common/`.

---
