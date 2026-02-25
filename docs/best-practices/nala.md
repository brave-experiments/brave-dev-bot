# Nala / Leo Design System Best Practices

<a id="NA-001"></a>

## ❌ Don't Add New Android Drawable Icons — Use Nala Icons

**When adding a new icon for Android, add it to `android/nala/icons.gni` instead of creating a new Android drawable resource.** The Nala icon system is the centralized way to manage Android icons. Bypassing it by adding raw drawable files leads to inconsistency, duplicates, and maintenance burden.

> **Reviewer note:** Tag `@nala-token-reviewers` when flagging this violation.

```gn
# ❌ WRONG - adding a new drawable file directly
# android/java/res/drawable/ic_my_new_icon.xml  ← don't do this

# ✅ CORRECT - add the icon entry to the Nala icons list
# android/nala/icons.gni
nala_icons = [
  ...
  "ic_my_new_icon.xml",
  ...
]
```

---

<a id="NA-002"></a>

## ❌ Don't Add New Android Color Tokens — Use Existing Nala Color Tokens

**When adding color values on Android, use existing Nala/Leo color tokens instead of defining new color resources.** New color definitions in `res/values/colors.xml` or similar files bypass the design system and create inconsistency across themes and platforms.

> **Reviewer note:** Tag `@nala-token-reviewers` when flagging this violation.

```xml
<!-- ❌ WRONG - defining a new color resource -->
<!-- res/values/colors.xml -->
<color name="my_custom_blue">#1A73E8</color>

<!-- ✅ CORRECT - use an existing Nala/Leo color token -->
<color name="...">@color/leo_color_button_background</color>
```

---

<a id="NA-003"></a>

## ❌ Don't Add New SVG Icon Files to WebUI — Use Leo Icons

**When adding icons to a WebUI page, add the icon name to the `leo_icons` array in `ui/webui/resources/BUILD.gn` instead of adding a new `.svg` file.** Leo provides a design-system-approved icon set; raw SVG files bypass it and create visual inconsistency.

```html
<!-- ❌ WRONG - raw SVG file added to the WebUI directory -->
<img src="my_icon.svg">

<!-- ✅ CORRECT - Leo icon component (icon added to leo_icons in ui/webui/resources/BUILD.gn) -->
<leo-icon name="my-icon-name"></leo-icon>
```

---

<a id="NA-004"></a>

## ❌ Don't Add New Chromium Vector Icon Files — Add to `leo_icons` in BUILD.gn

**When adding a new icon for use in C++ browser UI, add it to the `leo_icons` array in `components/vector_icons/BUILD.gn` instead of creating a new `.icon` file.** Leo is the canonical icon source; new standalone `.icon` files bypass the design system and create visual inconsistency.

```gn
# ❌ WRONG - new standalone vector icon file
# components/vector_icons/my_new_icon.icon

# ✅ CORRECT - add to the leo_icons list in components/vector_icons/BUILD.gn
leo_icons = [
  ...
  "my-icon-name",
  ...
]
```

---
