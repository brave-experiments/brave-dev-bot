# Patches

<a id="PATCH-001"></a>

## ❌ Minimize Whitespace Changes in Patches

**Leave whitespace intact in patch files to minimize diff size.** Only change what's functionally necessary. Unnecessary whitespace changes make patches harder to review and more likely to conflict.

---

<a id="PATCH-002"></a>

## ❌ Never Add Empty Lines in Patches

**Never add empty lines in patch files.** Keep patches minimal - only change what's functionally necessary.

---

<a id="PATCH-003"></a>

## ❌ Never Add Comments in Patches

**Never add comments, empty lines, or any non-functional changes in patch files.** Patches should contain only the minimal functional changes needed.

---

<a id="PATCH-004"></a>

## ❌ No Multiline Patches - Use Defines

**Never create multiline patches. Use `#define` macros or chromium_src overrides instead.**

---

<a id="PATCH-005"></a>

## ✅ Use `include` for Extensible Patches

**When a patch adds to a list or block, use an `include` directive to make the patch extensible.** This way additional items can be added in brave-core without modifying the patch.

---

<a id="PATCH-006"></a>

## ✅ Patches Should Use `define` for Extensibility

**Patches should use `#define` macros to be extensible.** This allows adding behavior in brave-core without changing the patch.

```cpp
// ❌ WRONG - patching inline code directly
+  if (permission == AUTOPLAY) return true;

// ✅ CORRECT - define macro that can be changed in brave-core
+#include "brave/chromium_src/path/to/override.h"
+BRAVE_PERMISSION_CONTROLLER_IMPL_METHOD
```

Convention for define names: `BRAVE_ALL_CAPS_ORIGINAL_METHOD_NAME`.

---

<a id="PATCH-007"></a>

## Patch Style Guidelines

- **Keep patches to one line** even if it violates lint character line limits (lint doesn't run on patched files)
- **In XML patches, use HTML comments** (`<!-- -->`) instead of deleting lines to reduce the diff
- **Minimize line modifications** - put additions on separate lines to avoid modifying existing lines
- **Match existing code exactly** when possible so patches auto-resolve during updates

```xml
<!-- ❌ WRONG - deleting XML elements -->
-<LinearLayout ...>
-  ...
-</LinearLayout>

<!-- ✅ CORRECT - commenting out -->
+<!--
 <LinearLayout ...>
   ...
 </LinearLayout>
+-->
```

---

<a id="PATCH-008"></a>

## ✅ Use `-=` for List Removal in Patches

**When removing items from GN lists, use `-=` instead of modifying the original line.** This makes the patch an addition rather than a modification.

```gn
# ❌ WRONG - modifying the original deps line
-  public_deps += [ ":chrome_framework_widevine_signature" ]

# ✅ CORRECT - separate removal line (addition-only patch)
+  public_deps -= [ ":chrome_framework_widevine_signature" ]
```

---

<a id="PATCH-009"></a>

## ✅ Use `deps +=` with a Variable for Extensible GN Patches

**When a patch adds dependencies to a Chromium BUILD.gn target, define a variable in Brave code and patch only the variable reference.** This allows adding/removing deps without modifying the patch.

```gn
# ❌ WRONG - patching inline deps
+  deps += [ "//brave/browser/ui/views/location_bar" ]

# ✅ CORRECT - patch references a variable
+  deps += brave_browser_window_deps
# In brave code:
brave_browser_window_deps = [
  "//brave/browser/ui/views/location_bar",
]
```

---

<a id="PATCH-010"></a>

## ❌ Don't Patch Python Build Scripts

**Do not add patches to Python build scripts (e.g., `java_cpp_enum.py` or similar build tools).** These patches prevent correct incremental rebuilds and break remote `siso` build actions. Instead, prefer: (1) a `chromium_src` override, (2) a multiline header patch, or (3) a `#define`-based approach. For Java/C++ enums processed by upstream Python scripts, a multiline patch in the header file is acceptable as a pragmatic solution.
