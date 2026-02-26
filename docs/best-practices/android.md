# Android Best Practices (Java/Kotlin)

<a id="AND-001"></a>

## ✅ Check `isActivityFinishingOrDestroyed()` Before UI Operations in Async Callbacks

**Always check `isActivityFinishingOrDestroyed()` before performing UI operations (showing dialogs, starting activities, manipulating views) in async callbacks, animation listeners, or lambdas.** Activities can be destroyed between when a callback is scheduled and when it executes.

```java
// ❌ WRONG - no lifecycle check in async callback
private void maybeRequestDefaultBrowser() {
    showDefaultBrowserDialog();
}

// ✅ CORRECT - guard against destroyed activity
private void maybeRequestDefaultBrowser() {
    if (isActivityFinishingOrDestroyed()) return;
    showDefaultBrowserDialog();
}

// ✅ CORRECT - guard in animation callbacks
animator.addListener(new AnimatorListenerAdapter() {
    @Override
    public void onAnimationEnd(Animator animation) {
        if (isActivityFinishingOrDestroyed()) return;
        mSplashContainer.setVisibility(View.GONE);
        showPager();
    }
});
```

---

<a id="AND-002"></a>

## ✅ Check Fragment Attachment Before Async UI Updates

**When async callbacks update UI through a Fragment, verify the fragment is still added and its host Activity is available.** Fragments can be detached or their Activity destroyed while async work is in progress.

```java
// ❌ WRONG - no fragment state checks
void onServiceResult(Result result) {
    updateUI(result);
}

// ✅ CORRECT - verify fragment is still attached
void onServiceResult(Result result) {
    if (!isAdded() || isDetached()) return;
    Activity activity = getActivity();
    if (activity == null || activity.isFinishing()) return;
    updateUI(result);
}
```

This applies to any asynchronous path: service callbacks, `PostTask.postTask()`, Mojo responses, etc.

---

<a id="AND-003"></a>

## ✅ Disable Interactive UI During Async Operations

**Disable buttons, preferences, and other interactive elements while an async operation is in progress to prevent double-clicks.** Re-enable when the callback completes.

```java
// ❌ WRONG - allows double-clicks during async operation
preference.setOnPreferenceClickListener(pref -> {
    accountService.resendConfirmationEmail(callback);
    return true;
});

// ✅ CORRECT - disable during async
preference.setOnPreferenceClickListener(pref -> {
    preference.setEnabled(false);
    accountService.resendConfirmationEmail(result -> {
        preference.setEnabled(true);
        // handle result
    });
    return true;
});
```

---

<a id="AND-004"></a>

## ✅ Apply Null Checks Consistently

**If a member field (e.g., a View reference) is checked for null in some code paths, check it in all code paths that use it.** Inconsistent null checking suggests some paths may crash.

```java
// ❌ WRONG - null check in some places but not others
private void showSplash() {
    if (mSplashContainer != null) {
        mSplashContainer.setVisibility(View.VISIBLE);
    }
}
private void hideSplash() {
    mSplashContainer.setVisibility(View.GONE);  // crash if null!
}

// ✅ CORRECT - consistent null checks
private void hideSplash() {
    if (mSplashContainer != null) {
        mSplashContainer.setVisibility(View.GONE);
    }
}
```

---

<a id="AND-005"></a>

## ✅ Add Null Checks for Services Unavailable in Incognito

**Services accessed through bridges or native code may be null in incognito profiles.** Always add explicit null checks at the point of use, even if upstream logic theoretically handles this.

```cpp
// ❌ WRONG - assumes service is always available
void NTPBackgroundImagesBridge::GetCurrentWallpaperForDisplay() {
  view_counter_service_->GetCurrentWallpaperForDisplay();
}

// ✅ CORRECT - explicit null check
void NTPBackgroundImagesBridge::GetCurrentWallpaperForDisplay() {
  if (!view_counter_service_)
    return;
  view_counter_service_->GetCurrentWallpaperForDisplay();
}
```

---

<a id="AND-006"></a>

## ✅ Use LazyHolder Pattern for Singleton Factories

**Use the LazyHolder idiom for singleton service factories instead of explicit `synchronized` blocks with a lock `Object`.** This is more compact and thread-safe by leveraging Java's class loading guarantees.

```java
// ❌ WRONG - explicit lock-based singleton
public class BraveAccountServiceFactory {
    private static final Object sLock = new Object();
    private static BraveAccountServiceFactory sInstance;

    public static BraveAccountServiceFactory getInstance() {
        synchronized (sLock) {
            if (sInstance == null) {
                sInstance = new BraveAccountServiceFactory();
            }
            return sInstance;
        }
    }
}

// ✅ CORRECT - LazyHolder pattern
public class BraveAccountServiceFactory {
    private static class LazyHolder {
        static final BraveAccountServiceFactory INSTANCE =
                new BraveAccountServiceFactory();
    }

    public static BraveAccountServiceFactory getInstance() {
        return LazyHolder.INSTANCE;
    }
}
```

---

<a id="AND-007"></a>

## ✅ Resolve Theme Colors at Bind Time

**When a custom Preference or view resolves colors from theme attributes, do so at `onBindViewHolder` time (or equivalent), not during construction.** This ensures colors update correctly when the user switches between light and dark themes without the view being recreated.

```java
// ❌ WRONG - resolve color during construction
public class MyPreference extends Preference {
    private final int mTextColor;

    public MyPreference(Context context) {
        super(context);
        mTextColor = resolveThemeColor(context, R.attr.textColor);  // stale if theme changes
    }
}

// ✅ CORRECT - resolve at bind time
public class MyPreference extends Preference {
    @Override
    public void onBindViewHolder(PreferenceViewHolder holder) {
        super.onBindViewHolder(holder);
        int textColor = resolveThemeColor(getContext(), R.attr.textColor);
        ((TextView) holder.findViewById(R.id.title)).setTextColor(textColor);
    }
}
```

---

<a id="AND-008"></a>

## ✅ Use `app:isPreferenceVisible="false"` for Conditionally Shown Preferences

**When a preference in XML will be programmatically removed or hidden based on a feature flag, set `app:isPreferenceVisible="false"` in XML to avoid a brief visual flash before the code hides it.**

```xml
<!-- ✅ Prevents flash of preference before programmatic removal -->
<org.chromium.chrome.browser.settings.BraveAccountPreference
    android:key="brave_account"
    app:isPreferenceVisible="false"
    android:title="@string/brave_account_title" />
```

---

<a id="AND-009"></a>

## ✅ Use `assert` Alongside `Log` for Validation

**Pair defensive null/validation checks with `assert` statements.** Assertions crash in debug builds making problems immediately visible, while graceful handling still protects release builds. Log-only guards are easily missed in logcat output.

```java
// ❌ WRONG - log-only guard, easily missed
if (contractAddress == null || contractAddress.length() < MIN_LENGTH) {
    Log.e(TAG, "Invalid contract address");
    return "";
}

// ✅ CORRECT - assert for debug + graceful fallback for release
assert contractAddress != null && contractAddress.length() >= MIN_LENGTH
        : "Invalid contract address";
if (contractAddress == null || contractAddress.length() < MIN_LENGTH) {
    Log.e(TAG, "Invalid contract address");
    return "";
}
```

---

<a id="AND-010"></a>

## ✅ Cache Expensive System Service Lookups

**When a method internally fetches system services (e.g., `PackageManager`, `AppOpsManager`), avoid calling it repeatedly in a hot path.** Compute the value once and store it in a member variable.

**Exception:** Don't cache values that can change without notification in multi-window or configuration-change scenarios (e.g., PiP availability can change when a second app starts).

```java
// ❌ WRONG - repeated expensive service lookup
@Override
public void onResume() {
    if (hasPipPermission()) { /* fetches PackageManager + AppOpsManager */ }
}

// ✅ CORRECT - cache on creation
private boolean mHasPipPermission;

@Override
public void onCreate() {
    mHasPipPermission = hasPipPermission();
}
```

---

<a id="AND-011"></a>

## ✅ Prefer Core/Native-Side Validation

**Before implementing validation logic in Android/Java code, check whether unified validation exists on the core/native side.** Prefer core-side validation to avoid cross-platform inconsistencies between Android, iOS, and desktop.

---

<a id="AND-012"></a>

## ✅ Skip Native/JNI Checks in Robolectric Tests

**Robolectric tests do not have native/JNI available.** When code paths hit JNI calls, use conditional checks (like `FeatureList.isNativeInitialized()`) to gracefully handle the test environment.

```java
// ✅ CORRECT - guard JNI calls for Robolectric compatibility
if (FeatureList.isNativeInitialized()) {
    ChromeFeatureList.isEnabled(BraveFeatureList.SOME_FEATURE);
}
```

See `BraveDynamicColors.java` for an existing example of this pattern.

---

<a id="AND-013"></a>

## ✅ Use Direct Java Patches When Bytecode Patching Fails

**Bytecode (class adapter) patching fails when a class has two constructors.** In these cases, use direct `.java.patch` files instead. Also use direct `BUILD.gn` patches to add sources when circular dependencies prevent using `java_sources.gni`.

---

<a id="AND-014"></a>

## ✅ `ProfileManager.getLastUsedRegularProfile()` Is Acceptable in Widgets

**While the presubmit check flags `ProfileManager.getLastUsedRegularProfile()` as a banned pattern, it is acceptable in Android widget providers** (e.g., `QuickActionSearchAndBookmarkWidgetProvider`) where no Activity or WebContents context is available. This matches upstream Chromium's approach in their own widgets.

---

<a id="AND-015"></a>

## ✅ Remove Unused Interfaces and Dead Code

**Do not leave unused interfaces, listener patterns, or helper methods in the codebase.** If scaffolded during development but never actually called, remove before merging.

```java
// ❌ WRONG - interface defined but never used
public interface OnAnimationCompleteListener {
    void onAnimationComplete();
}

// ✅ CORRECT - remove if nothing implements or calls it
```

---

<a id="AND-016"></a>

## ❌ Don't Set `clickable`/`focusable` on Non-Interactive Views

**Avoid setting `android:clickable="true"` or `android:focusable="true"` on purely decorative or display-only views** (like animation containers). These attributes affect accessibility and touch event handling.

---

<a id="AND-017"></a>

## ✅ Share Identical Assets Across Platforms

**When Android and iOS use identical asset files (e.g., Lottie animation JSON), reference a single shared copy rather than maintaining duplicates.** This ensures future changes only need to be made once.

---

<a id="AND-019"></a>

## ✅ Group Feature-Specific Java Sources into Separate Build Targets

**When Java sources for a specific feature (e.g., `crypto_wallet`) accumulate in `brave_java_sources.gni`, consider creating a separate build target.** This improves build isolation and dependency tracking.

---

<a id="AND-020"></a>

## ✅ Provide Justification for Non-Translatable Strings

**When adding strings with `translatable="false"` in `.grd` or resource files, there should be a clear documented reason** (e.g., brand names, URLs, temporary placeholders). Reviewers will question unmarked non-translatable strings.

---

<a id="AND-021"></a>

## ✅ Prefer Early Returns Over Deep Nesting

**When a condition check determines whether the rest of a method should execute, return early rather than wrapping logic in nested `if` blocks.** This reduces nesting depth and improves readability.

```java
// ❌ WRONG - deep nesting
private void handleState() {
    if (!isFinished) {
        if (hasData) {
            // ... lots of code ...
        }
    }
}

// ✅ CORRECT - early return
private void handleState() {
    if (isFinished) return;
    if (!hasData) return;
    // ... lots of code at top level ...
}
```

---

<a id="AND-022"></a>

## ✅ Bytecode Adapter Changes Require Bytecode Tests

**When adding or modifying a bytecode class adapter (files in `build/android/bytecode/java/org/brave/bytecode/`), add a corresponding bytecode test** in `android/javatests/org/chromium/chrome/browser/BytecodeTest.java`. Tests should verify both class existence (in `testClassesExist`) and method existence with correct return types (in `testMethodsExist`). This ensures upstream refactors are caught at test time rather than causing silent runtime failures.

---

<a id="AND-023"></a>

## ✅ Proguard Rules: Separate Runtime vs Test Keep Rules

**Proguard keep rules must go in the correct file:**
- `android/java/proguard.flags` — Only for classes/methods accessed via reflection at runtime
- `android/java/apk_for_test.flags` — For rules needed only during testing

Putting test-only keep rules in `proguard.flags` unnecessarily increases the production APK size by preventing code shrinking.

---

<a id="AND-025"></a>

## ✅ Use `@VisibleForTesting` for Package-Private Test Accessors

**When a field or method is made package-private solely for testing purposes, annotate it with `@VisibleForTesting(otherwise = VisibleForTesting.PRIVATE)`.** This communicates intent to other developers and allows IDEs to flag improper usage from non-test code.

---

<a id="AND-026"></a>

## ✅ Prefer Programmatic `addView` Over Full XML Layout Replacement

**When customizing Android UI, prefer adding views programmatically (via `addView` in Java) over replacing entire upstream XML layout files.** Replacing full XML files creates maintenance burden during Chromium upgrades. However, if programmatic addition requires extending final classes or leads to equally invasive changes, document the trade-off and accept the XML replacement.

---

<a id="AND-027"></a>

## ✅ Brave Resources Go in `brave-res`, Not Upstream Folders

**Brave-specific Android resources (drawables, layouts, etc.) should be placed in a dedicated `brave-res` folder, not copied into upstream Chromium resource directories.** The upstream resource directories should only be used when intentionally overriding an existing upstream resource. Adding new Brave-only resources to upstream folders creates confusion about whether a resource is a Brave addition or an upstream override.

---

<a id="AND-028"></a>

## ✅ Comprehensively Clean Up All Artifacts When Removing a Feature

**When removing a feature from Android, audit and remove all related artifacts:** bytecode class adapters, ProGuard rules, bytecode test entries, Java source files, resource files, JNI bindings, feature flags, and build system references. A feature removal PR should account for all integration points across the codebase.

---

<a id="AND-029"></a>

## ✅ Remove Dead API-Level Checks Below Min SDK

**Remove Android version checks for API levels below the app's minimum SDK version.** Dead code checking for Lollipop (API 21) or Marshmallow (API 23) should be cleaned up since Brave's minimum SDK is higher.

---

<a id="AND-031"></a>

## ✅ Direct Patches: Add New Lines, Don't Modify Existing

**When creating direct patches (non-chromium_src overrides), prefer adding entirely new lines rather than modifying existing upstream lines.** This reduces the risk of patch conflicts during Chromium version upgrades, because new lines have no upstream anchor that might change.

---

<a id="AND-032"></a>

## ✅ Patches Are Acceptable for Anonymous Inner Classes

**When the Brave override system cannot handle anonymous inner classes in upstream Chromium Java code, a `.patch` file is the accepted fallback.** Document the reason in the PR and link to the tracking issue for better override support.

---

<a id="AND-033"></a>

## ✅ Verify Shared Resource Changes Don't Break Other UIs

**When modifying shared Android resource values (colors, dimensions, styles in files like `brave_colors.xml`), verify the impact on ALL UIs that reference those resources.** Shared resources can affect multiple screens — always cross-check usages before modifying.

---

<a id="AND-034"></a>

## ✅ Use Baseline Colors Over Java Code Patches for Theming

**When fixing Android color/theming issues, prefer following upstream's approach of using baseline colors (XML color resources) for non-dynamic color states rather than patching Java code to programmatically set colors.** This is more maintainable and aligns with upstream's theming system. Always verify fixes work with the Dynamic Colors flag both enabled and disabled.

---

<a id="AND-035"></a>

## ❌ Don't Modify Upstream String Resource Files

**Never modify upstream Chromium string resource files (e.g., `chrome_strings.grd`, upstream `strings.xml`).** Add Brave-specific strings to `android_brave_strings.grd` or the appropriate Brave-owned resource file instead. Modifying upstream files creates patch conflicts during Chromium upgrades.

---

<a id="AND-036"></a>

## ✅ Match Upstream Nullability Annotations in Overridden Methods

**When overriding upstream methods in Brave Java code, match the upstream nullability annotations (e.g., `@NullUnmarked`, `@Nullable`, `@NonNull`).** Mismatched annotations cause NullAway build failures and prevent merging.

```java
// ❌ WRONG - upstream method has @NullUnmarked but override doesn't
@Override
public void onResult(Profile profile) { ... }

// ✅ CORRECT - match upstream annotations
@NullUnmarked
@Override
public void onResult(Profile profile) { ... }
```

---

<a id="AND-037"></a>

## ❌ Don't Repeat Class Name in Log TAG

**Android Log TAG fields should use a short, descriptive string — not repeat the full class name when it adds no value.** Keep TAGs concise and informative.

```java
// ❌ WRONG - redundant, TAG just repeats class name
private static final String TAG = "BraveVpnProfileController";

// ✅ CORRECT - short and clear
private static final String TAG = "BraveVPN";
```

---

<a id="AND-038"></a>

## ✅ Use Layout Shorthand Attributes

**Use shorthand XML layout attributes (`paddingHorizontal`, `marginHorizontal`, `paddingVertical`, `marginVertical`) instead of setting start/end or top/bottom separately.** This reduces XML verbosity and improves readability.

```xml
<!-- ❌ WRONG - verbose -->
<View
    android:paddingStart="16dp"
    android:paddingEnd="16dp" />

<!-- ✅ CORRECT - shorthand -->
<View
    android:paddingHorizontal="16dp" />
```
