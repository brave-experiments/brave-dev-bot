# C++ Memory, Ownership, and Lifetime

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

If a class doesn't own a resource, don't create ownership wrappers for it. This is a common source of crashes (see also architecture-services-api.md on shared_ptr misuse).

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

## ❌ `shared_ptr` Is Banned in Chromium Code

**Do not use `std::shared_ptr` - it is on the Chromium banned features list.** Use `base::RefCounted` / `scoped_refptr` when shared ownership is truly needed, or restructure to use unique ownership.

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

## ✅ Use `base::Unretained(this)` for Self-Owned Timer Callbacks

**When a class owns a `base::RepeatingTimer` or `base::OneShotTimer`, use `base::Unretained(this)`.** The timer is destroyed with the class, so it can only fire while `this` is valid. Using `WeakPtr` is unnecessary overhead.

```cpp
// ❌ WRONG - unnecessary overhead
timer_.Start(FROM_HERE, delay,
    base::BindRepeating(&MyClass::OnTimer, weak_factory_.GetWeakPtr()));

// ✅ CORRECT - timer is owned, so this is always valid when it fires
timer_.Start(FROM_HERE, delay,
    base::BindRepeating(&MyClass::OnTimer, base::Unretained(this)));
```

**Key distinction:** This is the opposite of the "never use Unretained with thread pool" rule. The difference is ownership: you own the timer, so it cannot outlive you.

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

## ✅ Add Thread Checks to `base::Bind` Callback Targets

**Methods used as targets of `base::BindOnce` / `base::BindRepeating` should include `DCHECK_CALLED_ON_VALID_SEQUENCE` to ensure correct thread.**

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

## ❌ Don't Log Sensitive Information

**Never log sensitive data such as sync seeds, private keys, tokens, or credentials.** Even VLOG-level logging can expose data in debug builds.

```cpp
// ❌ WRONG
VLOG(1) << "Sync seed: " << sync_seed;

// ✅ CORRECT
VLOG(1) << "Sync seed set successfully";
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
