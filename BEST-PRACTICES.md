# Brave Browser Best Practices

This document is an index of best practices for the Brave Browser codebase, discovered from code reviews, test fixes, and development experience. Each section links to a detailed document.

## Code & Architecture

- **Architecture and Code Organization:**
  - [Layering and Dependencies](./docs/best-practices/architecture-layering.md) - Chromium layer hierarchy, layering violations, iOS compatibility, circular deps
  - [Services, Factories, and API Design](./docs/best-practices/architecture-services-api.md) - Factory patterns, KeyedService, dependency injection, pref management, Mojo
- **C++ Coding Standards:**
  - [Style, Naming, and Organization](./docs/best-practices/coding-standards-style.md) - IWYU, naming conventions, headers, comments, documentation
  - [Memory, Ownership, and Lifetime](./docs/best-practices/coding-standards-memory-lifetime.md) - Ownership, CHECK vs DCHECK, WeakPtr, raw_ptr, threading
  - [Patterns, Utilities, and API Usage](./docs/best-practices/coding-standards-patterns.md) - Base utilities, types, callbacks, Mojo patterns, Chromium APIs
- **[Documentation](./docs/best-practices/documentation.md)** - Inline comments, method docs, READMEs, keeping docs fresh, avoiding duplication
- **[Front-End (TypeScript/React)](./docs/best-practices/frontend.md)** - Component props, spread args, XSS prevention
- **[chromium_src Overrides](./docs/best-practices/chromium-src-overrides.md)** - Overrides vs patches, minimizing duplication, ChromiumImpl fallback
- **[Build System](./docs/best-practices/build-system.md)** - BUILD.gn organization, buildflags, DEPS, patches, GRD resources

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
