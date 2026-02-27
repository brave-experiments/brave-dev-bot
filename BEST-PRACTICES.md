# Brave Browser Best Practices

This document is an index of best practices for the Brave Browser codebase, discovered from code reviews, test fixes, and development experience. Each section links to a detailed document.

## Nala / Leo Design System

- **[Nala / Leo Design System](./docs/best-practices/nala.md)** - Android icons, Android color tokens, WebUI SVG icons, C++ vector icons

## Code & Architecture

- **[Architecture and Code Organization](./docs/best-practices/architecture.md)** - Layering violations, dependency injection, factory patterns, pref management
- **[C++ Coding Standards](./docs/best-practices/coding-standards.md)** - IWYU, naming conventions, CHECK vs DCHECK, style, comments, logging
- **[C++ Memory, Lifetime & Threading](./docs/best-practices/coding-standards-memory.md)** - Ownership, WeakPtr, Unretained, raw_ptr, KeyedService shutdown, threading
- **[C++ API Usage, Containers & Types](./docs/best-practices/coding-standards-apis.md)** - base utilities, containers, type safety, optional, span, callbacks
- **[Documentation](./docs/best-practices/documentation.md)** - Inline comments, method docs, READMEs, keeping docs fresh, avoiding duplication
- **[Front-End (TypeScript/React)](./docs/best-practices/frontend.md)** - Component props, spread args, XSS prevention
- **[Android (Java/Kotlin)](./docs/best-practices/android.md)** - Activity/Fragment lifecycle, null safety, LazyHolder singletons, theme handling, Robolectric, bytecode patching, NullAway (`@Nullable` placement, `@MonotonicNonNull`, assert/assume patterns, destruction, view binders, Supplier variance, JNI nullness)
- **[chromium_src Overrides](./docs/best-practices/chromium-src-overrides.md)** - Overrides vs patches, minimizing duplication, ChromiumImpl fallback
- **[Build System](./docs/best-practices/build-system.md)** - BUILD.gn organization, buildflags, DEPS, GRD resources
- **[Patches](./docs/best-practices/patches.md)** - Patch style, minimality, extensibility via defines/includes, GN patch patterns
- **[iOS (Swift/ObjC/UIKit)](./docs/best-practices/ios.md)** - Swift idioms, SwiftUI, UIKit lifecycle, ObjC bridge, Tab architecture, chromium_src iOS overrides

## Testing

- **[Async Testing Patterns](./docs/best-practices/testing-async.md)** - Root cause analysis, RunUntil, RunUntilIdle, nested run loops, TestFuture
- **[JavaScript Evaluation in Tests](./docs/best-practices/testing-javascript.md)** - MutationObserver, polling loops, isolated worlds, renderer setup
- **[Navigation and Timing](./docs/best-practices/testing-navigation.md)** - Same-document navigation, timeouts, page distillation
- **[Test Isolation and Specific Patterns](./docs/best-practices/testing-isolation.md)** - Fakes, API testing, HTTP request testing, throttle testing, Chromium patterns

## Quick Checklist

Before writing async tests, verify:

- [ ] No `RunLoop::RunUntilIdle()` usage
- [ ] No `EvalJs()` or `ExecJs()` inside `RunUntil()` lambdas
- [ ] Using manual polling loops for JavaScript conditions
- [ ] Using `base::test::RunUntil()` only for C++ conditions
- [ ] Waiting for specific completion signals, not arbitrary timeouts
- [ ] Using isolated worlds (`ISOLATED_WORLD_ID_BRAVE_INTERNAL`) for test JS
- [ ] Per-resource expected values for HTTP request testing
- [ ] Large throttle windows for throttle behavior tests
- [ ] Proper observers for same-document navigation
- [ ] Testing public APIs, not implementation details
- [ ] Searched Chromium codebase for similar patterns
- [ ] Included Chromium code references in comments when following patterns
- [ ] Prefer event-driven JS (MutationObserver) over C++ polling for DOM changes

## References

- [Chromium C++ Testing Best Practices](https://www.chromium.org/chromium-os/developer-library/guides/testing/cpp-writing-tests/)
- [Progress Log](./progress.txt) - Real examples from fixing intermittent tests
- [Agent Instructions](./CLAUDE.md) - Full workflow and testing requirements
