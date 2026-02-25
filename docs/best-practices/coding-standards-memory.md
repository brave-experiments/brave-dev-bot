# C++ Memory Management, Lifetime & Threading

<!-- See also: coding-standards.md, coding-standards-memory.md, coding-standards-apis.md -->

<a id="CSM-001"></a>

## Ownership and Memory Management

<a id="CSM-002"></a>

### ✅ Comment Non-Owned Raw Pointers

**Raw pointers to non-owned objects should be commented with `// not owned`.** This is a Chromium convention.

```cpp
// ✅ CORRECT
ThirdPartyExtractor* third_party_extractor_ = nullptr;  // not owned
```

<a id="CSM-003"></a>

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

<a id="CSM-004"></a>

### ❌ Don't Take Ownership of Unowned Resources

If a class doesn't own a resource, don't create ownership wrappers for it. This is a common source of crashes (see also architecture.md on shared_ptr misuse).

---

<a id="CSM-005"></a>

## ❌ `shared_ptr` Is Banned in Chromium Code

**Do not use `std::shared_ptr` - it is on the Chromium banned features list.** Use `base::RefCounted` / `scoped_refptr` when shared ownership is truly needed, or restructure to use unique ownership.

---

<a id="CSM-006"></a>

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

<a id="CSM-007"></a>

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

<a id="CSM-008"></a>

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

<a id="CSM-009"></a>

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

<a id="CSM-010"></a>

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

<a id="CSM-011"></a>

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

<a id="CSM-012"></a>

## ✅ `base::Unretained(this)` Is Safe with Owned Mojo Endpoints

**Using `base::Unretained(this)` in Mojo disconnect handlers and connection error handlers is safe when the class owns the `mojo::Remote`, `mojo::Receiver`, or `mojo::AssociatedRemote`.** The Mojo endpoint is destroyed with the class, so the callback can only fire while `this` is valid — the same ownership guarantee as timers.

```cpp
// ✅ SAFE - class owns the remote, so Unretained is fine
remote_.set_disconnect_handler(
    base::BindOnce(&MyClass::OnDisconnect, base::Unretained(this)));

// ✅ SAFE - class owns the receiver
receiver_.set_disconnect_handler(
    base::BindOnce(&MyClass::OnDisconnect, base::Unretained(this)));

// ✅ ALSO SAFE - WeakPtr works too but adds unnecessary overhead
remote_.set_disconnect_handler(
    base::BindOnce(&MyClass::OnDisconnect, weak_factory_.GetWeakPtr()));
```

**Do NOT flag `base::Unretained(this)` in Mojo disconnect/error handlers as unsafe.** This is a well-established safe pattern in Chromium. Only flag it if the binding crosses thread boundaries or if `this` does not own the Mojo endpoint.

---

<a id="CSM-013"></a>

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

<a id="CSM-014"></a>

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

<a id="CSM-015"></a>

## ✅ Use `SEQUENCE_CHECKER` Consistently - All Methods or None

**If a class is single-threaded, either apply `DCHECK_CALLED_ON_VALID_SEQUENCE` to all methods or remove the sequence checker entirely.** Partial checking is misleading and makes correct code look unsafe.

---

<a id="CSM-016"></a>

## ✅ Clean Up Resources in `KeyedService::Shutdown`

**For `KeyedService` implementations, clean up owned resources in `Shutdown()`, not just the destructor.** The service graph has dependencies requiring orderly teardown.

---

<a id="CSM-017"></a>

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

<a id="CSM-018"></a>

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

<a id="CSM-019"></a>

## ✅ Add Thread Checks to `base::Bind` Callback Targets

**Methods used as targets of `base::BindOnce` / `base::BindRepeating` should include `DCHECK_CALLED_ON_VALID_SEQUENCE` to ensure correct thread.**

---

<a id="CSM-020"></a>

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

<a id="CSM-021"></a>

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

<a id="CSM-022"></a>

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

<a id="CSM-023"></a>

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

<a id="CSM-024"></a>

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

<a id="CSM-025"></a>

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

<a id="CSM-026"></a>

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

<a id="CSM-027"></a>

## ✅ Security Review for Unrestricted URL Inputs in Mojom

**When creating mojom interfaces that accept URL parameters from less-privileged processes, consider restricting to an allowlist or enum** rather than accepting arbitrary URLs. An unrestricted URL parameter means the renderer can send requests to any endpoint.

**When NOT to flag:** If the implementation already validates or filters the URL downstream, do not request documentation comments about it. Before flagging, check whether similar patterns in surrounding code or elsewhere in the codebase have such comments — if they don't, your suggestion would introduce inconsistency and unnecessary verbosity.

---

<a id="CSM-028"></a>

## ✅ `base::DoNothing()` Doesn't Match `base::FunctionRef` Signatures

**`base::DoNothing()` cannot be used where a `base::FunctionRef<void(T&)>` is expected.** In those cases, use an explicit no-op lambda instead.

```cpp
// ❌ WRONG - won't compile
service->ForEach(base::DoNothing());  // FunctionRef<void(Item&)>

// ✅ CORRECT - explicit lambda
service->ForEach([](Item&) {});
```
