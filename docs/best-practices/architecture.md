# Architecture and Code Organization

<a id="ARCH-001"></a>

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

<a id="ARCH-002"></a>

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

<a id="ARCH-003"></a>

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

<a id="ARCH-004"></a>

## ✅ Prefer Internal Feature Guards Over External Ifdefs

**Code should handle disabled features internally rather than requiring external `#ifdef` guards.**

When a feature can be disabled, prefer making the factory/service return null or no-op when disabled, rather than requiring callers to wrap every usage in `#ifdef` guards. Scattered buildflags lead to missing deps and maintenance burden.

**BAD:**
```cpp
// ❌ WRONG - external ifdef guards everywhere
#if BUILDFLAG(BRAVE_REWARDS_ENABLED)
  auto* rewards_service = RewardsServiceFactory::GetForProfile(profile);
  rewards_service->DoSomething();
#endif
```

**GOOD:**
```cpp
// ✅ CORRECT - factory handles disabled state internally
auto* rewards_service = RewardsServiceFactory::GetForProfile(profile);
if (rewards_service) {  // Returns null when disabled
  rewards_service->DoSomething();
}
```

---

<a id="ARCH-005"></a>

## ❌ Don't Misuse shared_ptr for Unowned Memory

**Don't use `shared_ptr` to take ownership of something you don't own.**

Using `shared_ptr` on memory owned by another class causes crashes when the `shared_ptr` frees memory that is still referenced elsewhere. Avoid shared pointers unless there is a strong reason for shared ownership.

**BAD:**
```cpp
// ❌ WRONG - taking ownership of an unowned resource
void Init(network::ResourceRequest& request) {
  auto shared_request = std::make_shared<network::ResourceRequest>(request);
  // shared_request will free memory that may still be in use!
}
```

**GOOD:**
```cpp
// ✅ CORRECT - pass by reference or raw pointer for unowned resources
void Init(const network::ResourceRequest& request) {
  // Use the request directly, don't take ownership
}
```

---

<a id="ARCH-006"></a>

## Thread Safety - Service Method Calls

**Calling service methods from the wrong thread causes crashes.** Always verify which thread a method expects to be called on. This is especially important for ad-block and shields services.

---

<a id="ARCH-007"></a>

## ❌ Never Access Internal/Vendor Headers Directly

**Never use `#include "brave/vendor/..."` to access internal headers.** Internal headers are not part of the public API and should not be accessed using full paths to bypass visibility.

```cpp
// ❌ WRONG - accessing internal vendor headers directly
#include "brave/vendor/brave_base/random.h"

// ✅ CORRECT - use the public component API header
#include "brave/components/brave_rewards/core/utility/random_util.h"
```

---

<a id="ARCH-008"></a>

## ✅ Use Pref Change Registrar Instead of Custom Observers

**Use the existing `pref_change_registrar_` pattern for observing pref changes.** Don't create custom observer interfaces when the pref change registrar already handles this.

```cpp
// ❌ WRONG - custom observer for pref changes
class MyObserver : public PrefObserver {
  void OnPrefChanged(const std::string& pref_name) override;
};

// ✅ CORRECT - use pref change registrar
pref_change_registrar_.Add(
    prefs::kMyPref,
    base::BindRepeating(&MyClass::OnPrefChanged, base::Unretained(this)));
```

Also: check if the superclass already has a `pref_change_registrar_` before adding a new one.

---

<a id="ARCH-009"></a>

## ❌ Don't Duplicate Pref Storage

**Don't cache pref values in member variables when you can just read the pref at call time.**

```cpp
// ❌ WRONG - duplicating pref storage
bool is_opted_in_ = false;
void OnPrefChanged() { is_opted_in_ = prefs->GetBoolean(kOptedIn); }
bool IsOptedIn() { return is_opted_in_; }

// ✅ CORRECT - read pref when needed
bool IsOptedIn() { return prefs_->GetBoolean(kOptedIn); }
```

---

<a id="ARCH-010"></a>

## Factory Patterns

<a id="ARCH-011"></a>

### ✅ Use DependsOn for Factory Dependencies

**If your KeyedServiceFactory depends on other services, declare it with `DependsOn`.** This ensures proper initialization order.

```cpp
MyServiceFactory::MyServiceFactory()
    : BrowserContextKeyedServiceFactory(...) {
  DependsOn(RewardsServiceFactory::GetInstance());
  DependsOn(AdsServiceFactory::GetInstance());
}
```

<a id="ARCH-012"></a>

### ✅ Return Null for Incognito Profiles

**If a service shouldn't be active in incognito, return null from `GetForProfile` rather than overriding `GetBrowserContextToUse`.**

<a id="ARCH-013"></a>

### ❌ Components Don't Need Their Own Component Manager

**Each component does not need its own component manager.** Use a component installer policy instead.

---

<a id="ARCH-014"></a>

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

<a id="ARCH-015"></a>

## ❌ Don't Initialize Services for Wrong Profile Types

**Never initialize services for profile types they shouldn't support.** For example, never initialize Rewards service for incognito profiles. The `GetBrowserContextToUse` method in factories must correctly return null for unsupported profile types.

```cpp
// ❌ WRONG - returns the profile even for incognito
content::BrowserContext* GetBrowserContextToUse(
    content::BrowserContext* context) const override {
  return context;  // This creates services for incognito!
}

// ✅ CORRECT - return null for unsupported profiles
content::BrowserContext* GetBrowserContextToUse(
    content::BrowserContext* context) const override {
  if (context->IsOffTheRecord())
    return nullptr;
  return context;
}
```

---

<a id="ARCH-016"></a>

## ✅ Reuse Existing Services and Singletons

**Check for existing services and singletons before creating new ones.** Don't create duplicate singletons for the same purpose (e.g., don't create a new locale helper when `brave_ads::LocaleHelper` already exists).

**Use observers for decoupled notifications instead of adding direct cross-service calls.**

---

<a id="ARCH-017"></a>

## ✅ Encapsulate Cleanup in the Owning Class

**Cleanup logic (like deleting files) should be encapsulated in the class that owns the resource.** Don't spread cleanup code across multiple callers.

```cpp
// ❌ WRONG - caller handles cleanup details
tor_client_updater()->GetExecutablePath();
base::DeleteFile(path);

// ✅ CORRECT - owning class encapsulates cleanup
tor_client_updater()->Cleanup();
```

---

<a id="ARCH-018"></a>

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

<a id="ARCH-019"></a>

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

<a id="ARCH-020"></a>

## ✅ Use Friend Class for Test/Private Access

**When tests or subclasses need access to private members, use `friend` declarations instead of making methods public or protected.**

```cpp
// ❌ WRONG - making methods public just for testing
public:
  void InternalMethod();  // was private, made public for tests

// ✅ CORRECT - friend class
private:
  friend class BraveDownloadProtectionService;
  void InternalMethod();
```

For patches, use a `BRAVE_CLASS_NAME_H` define at the end of `public:` that adds friend declarations.

---

<a id="ARCH-021"></a>

## ✅ Callbacks for Queries, Observers for State Changes

**Observer methods should only be triggered by state changes (Set/Create/Delete), never by query responses (Get/Fetch).** Use callbacks for query responses.

```cpp
// ❌ WRONG - observer triggered by a query
void RewardsService::GetRecurringDonations() {
  ledger->GetRecurringDonations([this](auto list) {
    for (auto& observer : observers_)
      observer.OnRecurringDonationsList(list);  // Wrong!
  });
}

// ✅ CORRECT - callback for query
void RewardsService::GetRecurringDonations(GetDonationsCallback callback) {
  ledger->GetRecurringDonations(std::move(callback));
}

// ✅ CORRECT - observer for state change
void RewardsService::SetRecurringDonation(amount) {
  SaveToDB(amount);
  for (auto& observer : observers_)
    observer.OnRecurringDonationUpdated();
}
```

---

<a id="ARCH-022"></a>

## ❌ Don't Expose Internal Library Types in Public Headers

**Never expose internal implementation types in public component headers.** Use the component's public API types (e.g., Mojo types) instead.

```cpp
// ❌ WRONG - internal database types in public rewards header
#include "brave/components/brave_rewards/core/engine/database/database_publisher_info.h"
void DoSomething(internal::database::DatabasePublisherInfo info);

// ✅ CORRECT - use public Mojo types
#include "brave/components/brave_rewards/common/mojom/rewards.mojom.h"
void DoSomething(mojom::PublisherInfoPtr info);
```

---

<a id="ARCH-023"></a>

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

<a id="ARCH-024"></a>

## ✅ Use `CHECK_IS_TEST` for Null Checks That Should Only Occur in Tests

**When a pointer should never be null in production but may be null in certain test configurations, use `CHECK_IS_TEST()` before the null check.** This documents that the null case is test-only and prevents confusion about whether null is a valid production state.

```cpp
// ❌ WRONG - ambiguous null check
if (!g_brave_browser_process->speedreader_rewriter_service())
  return;

// ✅ CORRECT - explicit test-only guard
if (!service) {
  CHECK_IS_TEST();
  return;
}
```

---

<a id="ARCH-025"></a>

## ✅ Pass Dependencies via Constructors, Not Setter Callbacks

**When a service needs a dependency, pass it through the constructor rather than using a separate `Set*Callback` method.** Constructor injection makes dependencies explicit and avoids confusing initialization ordering.

```cpp
// ❌ WRONG - setting callback from an unrelated factory
void BraveVpnServiceFactory::BuildServiceInstanceFor(...) {
  auto* api = BraveVPNOSConnectionAPI::GetInstance();
  api->SetInstallSystemServiceCallback(base::BindRepeating(...));
}

// ✅ CORRECT - pass dependency via constructor
BraveVPNOSConnectionAPI::BraveVPNOSConnectionAPI(
    base::RepeatingCallback<void()> install_callback)
    : install_system_service_callback_(std::move(install_callback)) {}
```

---

<a id="ARCH-026"></a>

## ✅ Use `ServiceIsNULLWhileTesting` for Optional Keyed Services

**When a `KeyedService` should not be created during unit tests that don't provide the required dependencies, override `ServiceIsNULLWhileTesting()` to return `true` in the factory.** This is cleaner than scattering null checks throughout the codebase.

```cpp
// ❌ WRONG - null checks scattered everywhere
void MyService::DoSomething() {
  if (!local_state_) return;  // might be null in tests
}

// ✅ CORRECT - factory controls creation
bool MyServiceFactory::ServiceIsNULLWhileTesting() const {
  return true;
}
```

---

<a id="ARCH-027"></a>

## ❌ Never Call `GetOriginalProfile()` to Bypass Factory Checks

**Never call `GetOriginalProfile()` or similar methods to circumvent factory profile checks.** If a factory returns null for a given profile type, that profile is not supposed to use the service. Respect the factory's decision.

```cpp
// ❌ WRONG - circumventing factory profile checks
auto* profile = Profile::FromBrowserContext(context)->GetOriginalProfile();
auto* service = MyServiceFactory::GetForProfile(profile);

// ✅ CORRECT - respect what the factory returns
auto* service = MyServiceFactory::GetForProfile(
    Profile::FromBrowserContext(context));
if (!service)
  return;
```

---

<a id="ARCH-028"></a>

## ✅ Use `MaybeCreateForWebContents` for Conditional Tab Helpers

**When a tab helper should not be attached to all web contents (e.g., skipped for incognito or when a feature is disabled), use a static `MaybeCreateForWebContents` method** with the appropriate guards instead of always creating and checking internally.

```cpp
// ❌ WRONG - always create, check internally
SerpMetricsTabHelper::CreateForWebContents(web_contents);

// ✅ CORRECT - conditionally create with proper guards
static void MaybeCreateForWebContents(content::WebContents* web_contents) {
  auto* profile = Profile::FromBrowserContext(
      web_contents->GetBrowserContext());
  if (!profile->IsRegularProfile())
    return;
  if (!base::FeatureList::IsEnabled(kSerpMetrics))
    return;
  SerpMetricsTabHelper::CreateForWebContents(web_contents);
}
```

---

<a id="ARCH-029"></a>

## ✅ Use `ProfileKeyedServiceFactory` for New Desktop Factories

**New keyed service factories on desktop should inherit from `ProfileKeyedServiceFactory`** rather than the older `BrowserContextKeyedServiceFactory`. See the Brave keyed services documentation.

---

<a id="ARCH-030"></a>

## ✅ Guard New Functionality Behind `base::Feature`

**New functionality should always be guarded behind a `base::Feature` flag.** Unguarded code that crashes can't be disabled remotely via Griffin/feature flags. Use `raw_ptr` checked before use for services that may not exist in all configurations (System profile, Guest profile, disabled feature).

```cpp
// ❌ WRONG - no feature guard, crash can't be remotely disabled
auto* service = MyNewServiceFactory::GetForProfile(profile);
service->DoSomething();  // Crashes if service unavailable

// ✅ CORRECT - guarded behind feature flag
if (!base::FeatureList::IsEnabled(features::kMyNewFeature))
  return;
auto* service = MyNewServiceFactory::GetForProfile(profile);
if (!service)
  return;
service->DoSomething();
```

---

<a id="ARCH-031"></a>

## ✅ Unify Platform-Specific Delegates

**When implementing functionality for both Android and desktop, unify the code in a single delegate** rather than duplicating it across platforms. Extract only the platform-specific parts (like tab handling) into the delegate interface.

```cpp
// ❌ WRONG - duplicated logic
class DesktopDelegate { /* same logic with BrowserList */ };
class AndroidDelegate { /* same logic with TabModel */ };

// ✅ CORRECT - unified logic, platform-specific tab access
class UnifiedDelegate {
  virtual std::vector<TabInfo> GetOpenTabs() = 0;  // platform-specific
  void DoSharedLogic() { /* uses GetOpenTabs() */ }  // shared
};
```

---

<a id="ARCH-032"></a>

## ❌ Don't Silently Fall Back on Unknown Types

**When handling unknown/unsupported types, prefer an explicit error rather than silently falling back to a default.** Silent fallbacks mask bugs and make debugging harder.

```cpp
// ❌ WRONG - silently treats unknown files as images
FileType GetFileType(const std::string& mime) {
  if (mime == "application/pdf") return FileType::kPDF;
  return FileType::kImage;  // Silent fallback!
}

// ✅ CORRECT - explicit error on unknown
std::optional<FileType> GetFileType(const std::string& mime) {
  if (mime == "application/pdf") return FileType::kPDF;
  if (mime.starts_with("image/")) return FileType::kImage;
  return std::nullopt;  // Caller handles unknown types
}
```

---

<a id="ARCH-033"></a>

## ✅ Separate Lifecycle Events from Data Change Events in Mojo

**A Mojo `Changed` event should only fire when actual data changes occur.** Don't conflate lifecycle events (model loading, listener registration) with data mutation events. Provide separate events.

```cpp
// ❌ WRONG - Changed fires on initialization, not actual change
interface BookmarksListener {
  Changed(BookmarksChange change);  // Fires on model load AND data change
};

// ✅ CORRECT - separate lifecycle and data events
interface BookmarksListener {
  OnBookmarksReady();                // Fires once when model is loaded
  OnBookmarksChanged(BookmarksChange change);  // Only fires on actual changes
};
```

---

<a id="ARCH-034"></a>

## ✅ Use `base::BarrierCallback` for Parallel Async Aggregation

**Use `base::BarrierCallback` to aggregate results from multiple parallel async operations** rather than manually tracking completion counts. This simplifies multi-callback aggregation.

```cpp
// ❌ WRONG - manual tracking
int pending_count_ = 3;
std::vector<Result> results_;
void OnResult(Result r) {
  results_.push_back(std::move(r));
  if (--pending_count_ == 0) OnAllComplete();
}

// ✅ CORRECT - barrier callback
auto barrier = base::BarrierCallback<Result>(
    3, base::BindOnce(&MyClass::OnAllComplete, weak_factory_.GetWeakPtr()));
service1->Fetch(barrier);
service2->Fetch(barrier);
service3->Fetch(barrier);
```

---

<a id="ARCH-035"></a>

## ❌ Mojom Enums Must Be Top-Level When Targeting iOS

**Mojom enums cannot be nested inside mojom structs when the target includes iOS.** The Objective-C++ code generator produces invalid code for nested enums (`common.mojom.objc.mm` build failure). Always define mojom enums at the top level of the `.mojom` file.

```mojom
// ❌ WRONG - nested enum breaks iOS build
struct ModelConfig {
  enum Category {
    kChat = 0,
    kCompletion = 1,
  };
  Category category;
};

// ✅ CORRECT - top-level enum
enum ModelCategory {
  kChat = 0,
  kCompletion = 1,
};

struct ModelConfig {
  ModelCategory category;
};
```

---

<a id="ARCH-036"></a>

## ❌ No Content-Layer Dependencies for iOS-Targeted Components

**Components that must build for iOS (like `brave_wallet`) cannot depend on content-layer types** (`content::WebContents`, `content::BrowserContext`). iOS uses WebKit, not Chromium's content layer. Pass specific dependencies (`PrefService*`, `URLLoaderFactory`) instead.

---

<a id="ARCH-037"></a>

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

<a id="ARCH-038"></a>

## ❌ No Circular Dependencies Between Components

**Component dependencies must form a strictly tree-shaped graph — no circular dependencies.** If component A depends on component B, then B must never depend on A (directly or transitively). Use delegate interfaces or observers to break cycles.

---

<a id="ARCH-039"></a>

## ✅ Service/Decoder Code Belongs in `services/` Not `components/.../browser/`

**Mojo service implementations and data decoders should live in a `services/` directory**, not inside `components/.../browser/`. This follows Chromium conventions and keeps service code at the correct architectural layer.

---

<a id="ARCH-040"></a>

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

<a id="ARCH-041"></a>

## ✅ Prefer Static Singleton Over KeyedService When No Profile Dependency

**When a service has no per-profile state and doesn't depend on profile-specific data, use a static singleton with `base::NoDestructor` instead of a `KeyedService`.** KeyedService adds unnecessary complexity when there's no profile dependency.

```cpp
// ❌ WRONG - KeyedService for profile-independent data
class ModelListServiceFactory : public BrowserContextKeyedServiceFactory { ... };

// ✅ CORRECT - static singleton
class ModelListService {
 public:
  static ModelListService& GetInstance() {
    static base::NoDestructor<ModelListService> instance;
    return *instance;
  }
};
```

---

<a id="ARCH-042"></a>

## ✅ Flag Destructive Pref Operations for UX Review

**Operations that delete user data (clearing preferences, wiping storage) must be flagged for UX review before implementation.** Silent data deletion is a poor user experience and may violate user expectations.

---

<a id="ARCH-043"></a>

## ✅ Use Pre-Allocated Vectors for Ordered Async Results

**When aggregating results from multiple parallel async calls that must maintain order, pre-allocate a vector and insert results by index** rather than using a map and sorting later.

```cpp
// ❌ WRONG - map loses original order
std::map<int, Result> results_by_index_;

// ✅ CORRECT - pre-allocated vector with indexed insertion
std::vector<Result> results_(num_requests);
// In each callback:
results_[request_index] = std::move(result);
```

---

<a id="ARCH-044"></a>

## ✅ Use Existing Mojom Types Instead of Duplicating in C++

**When mojom types already describe the data shape, use them directly in C++ instead of creating redundant C++ struct types.** Duplicating types creates a synchronization burden and increases the risk of the two definitions drifting apart.

```cpp
// ❌ WRONG - redundant C++ struct
struct ToolConfig {
  std::string name;
  std::string description;
};

// ✅ CORRECT - use the mojom type directly
// mojom::ToolConfig already has name and description fields
void RegisterTool(mojom::ToolConfigPtr config);
```

---

<a id="ARCH-045"></a>

## ❌ Don't Expose Cache Keys in API Interfaces

**Internal cache keys should not leak into public API interfaces.** Auto-generate unique cache keys internally rather than requiring callers to provide or manage them.

```cpp
// ❌ WRONG - caller must know about cache keys
void FetchData(const std::string& url, const std::string& cache_key,
               Callback cb);

// ✅ CORRECT - cache key generated internally
void FetchData(const std::string& url, Callback cb);
// Internally: cache_key = GenerateKey(url, params)
```

---

<a id="ARCH-046"></a>

## ✅ Reorder Data for UI Presentation on Client Side

**Data reordering for UI presentation (sorting, grouping, prioritizing) belongs in the client/UI layer, not in the core data layer or API response.** The backend should return data in its canonical order; the frontend transforms it for display.

---

<a id="ARCH-047"></a>

## ✅ Mojom Interface Naming Should Be UI-Framework Agnostic

**When defining Mojom interfaces that could be consumed by different UI frameworks (WebUI, native iOS, etc.), avoid framework-specific naming like "PageHandler".** Use more neutral naming like "UIHandler" to remain consistent and not imply a web-only interface.

```mojom
// ❌ WRONG - implies web-only
interface HistoryPageHandler { ... };

// ✅ CORRECT - framework-agnostic
interface HistoryUIHandler { ... };
```

---

<a id="ARCH-048"></a>

## ✅ Use Mojo Interfaces for Trusted/Untrusted WebUI Communication

**When communicating between trusted and untrusted WebUI frames, use a mojo interface rather than `postMessage`.** The Chromium documentation advises against `postMessage` across trust boundaries. Only avoid mojo when the frame intentionally executes untrusted code and reducing API surface is a deliberate security choice.

---

<a id="ARCH-049"></a>

## ✅ Gate UI Restrictions at UI Layer, Not in Core Utility Functions

**UI-specific restrictions should be gated at the UI layer, not in core utility functions.** Coupling core logic (like `IsFeatureEnabled()`) to UI state (like WebUI availability) creates unexpected test failures and tight coupling.

```cpp
// ❌ WRONG - core utility coupled to UI state
bool IsZCashShieldedTransactionsEnabled() {
  return IsZCashEnabled() && kShieldedEnabled.Get() && IsWalletWebUIEnabled();
  //                                                   ^^^^^^^^^^^^^^^^^ UI concern!
}

// ✅ CORRECT - gate at UI layer
bool IsZCashShieldedTransactionsEnabled() {
  return IsZCashEnabled() && kShieldedEnabled.Get();
}
// UI layer checks: if (!IsWalletWebUIEnabled()) { hide shielded tx UI }
```

---

<a id="ARCH-050"></a>

## ✅ Policy-Disabled Features: Hide UI Entirely

**When a feature is disabled by admin policy with ENFORCED enforcement, hide the UI entirely** rather than just disabling/greying out controls. For RECOMMENDED policies, the UI should still be visible since the user can override. On macOS, `defaults write` creates RECOMMENDED level policies, not MANDATORY.

```cpp
// ❌ WRONG - just disabling controls
if (IsFeatureManaged()) {
  button->SetEnabled(false);  // greyed out but visible
}

// ✅ CORRECT - hide entirely for enforced, visible for recommended
if (IsFeatureManaged() &&
    enforcement == Enforcement::kEnforced) {
  section->SetVisible(false);  // completely hidden
}
```

---

<a id="ARCH-051"></a>

## ✅ Check Value Changed Before Firing State Notifications

**Before calling observer notification methods, check if the value actually changed.** Store the old value, update, then compare. This avoids unnecessary observer notifications and potential re-renders.

```cpp
// ❌ WRONG - always notifies even when value unchanged
visual_content_used_percentage_ = new_value;
OnStateForConversationEntriesChanged();

// ✅ CORRECT - only notify on actual change
auto old_value = visual_content_used_percentage_;
visual_content_used_percentage_ = new_value;
if (old_value != visual_content_used_percentage_) {
  OnStateForConversationEntriesChanged();
}
```

---

<a id="ARCH-052"></a>

## ✅ Set Default Values in Mojom Struct Fields

**Mojom struct fields should have explicit default values for safety.** Uninitialized mojom fields can lead to unexpected behavior when the struct is partially constructed.

**Exception:** Do not flag fields whose types are opaque resources that must always be provided by the caller — e.g., `mojo_base.mojom.BigBuffer`, `handle`, `pending_remote`, `pending_receiver`, `pending_associated_remote`, `pending_associated_receiver`. Adding empty defaults for these types would mask bugs where a field is accidentally omitted. When in doubt whether a type benefits from a default, don't bother commenting.

```mojom
// ❌ WRONG - no defaults on primitive/string fields
struct ModelConfig {
  string name;
  bool supports_tools;
};

// ✅ CORRECT - explicit defaults on primitive/string fields
struct ModelConfig {
  string name = "";
  bool supports_tools = false;
};

// ✅ CORRECT - no default on opaque resource fields (must always be provided)
struct ModelFiles {
  mojo_base.mojom.BigBuffer weights;
};
```

---

<a id="ARCH-053"></a>

## ❌ Avoid Cross-Feature Module Dependencies

**Feature modules should not import classes from other unrelated feature modules.** For example, a VPN feature should not directly depend on classes from the Rewards or Wallet modules. If shared functionality is needed, extract it into a common utility or use an interface/abstraction layer. Cross-feature dependencies create tight coupling that makes features hard to modify or remove independently.
