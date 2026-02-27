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

<a id="NA-005"></a>

## ❌ Don't Use HTML elements when there's a relevant Nala component

**In WebUI React code, use Leo components from `@brave/leo/react/*` instead of native HTML elements.** Leo components are design-system-approved, theme-aware, and accessible. Using raw HTML elements produces visual inconsistency, bypasses Brave's design tokens, and requires manual accessibility work.

> **Reviewer note:** Tag `@nala-token-reviewers` when flagging this violation.

<a id="NA-007"></a>

### Common substitutions

| Instead of… | Use… |
|---|---|
| `<select>` | `Dropdown` from `@brave/leo/react/dropdown` |
| `<button>` | `Button` from `@brave/leo/react/button` |
| `<input type="text">` | `Input` from `@brave/leo/react/input` |
| `<input type="checkbox">` | `Checkbox` from `@brave/leo/react/checkbox` |
| `<input type="radio">` | `RadioButton` from `@brave/leo/react/radioButton` |
| Toggle/switch UI | `Toggle` from `@brave/leo/react/toggle` |
| `<dialog>` / modal | `Dialog` from `@brave/leo/react/dialog` |

```tsx
// ❌ WRONG - native HTML select
<select value={value} onChange={e => setValue(e.target.value)}>
  <option value="a">Option A</option>
  <option value="b">Option B</option>
</select>

// ✅ CORRECT - Leo Dropdown
import Dropdown from '@brave/leo/react/dropdown'

<Dropdown value={value} onChange={e => setValue(e.detail.value)}>
  <leo-option value="a">Option A</leo-option>
  <leo-option value="b">Option B</leo-option>
</Dropdown>
```

```tsx
// ❌ WRONG - native HTML button
<button onClick={handleClick} disabled={isLoading}>Submit</button>

// ✅ CORRECT - Leo Button
import Button from '@brave/leo/react/button'

<Button onClick={handleClick} isDisabled={isLoading}>Submit</Button>
```

```tsx
// ❌ WRONG - native HTML input
<input type="text" value={value} onChange={e => setValue(e.target.value)} />

// ✅ CORRECT - Leo Input
import Input from '@brave/leo/react/input'

<Input value={value} onInput={e => setValue(e.detail.value)} />
```

---

<a id="NA-006"></a>

## ❌ Don't Reinvent Components That Already Exist in Leo

**Before creating a custom React component, check whether Leo already provides it.** Custom re-implementations of Leo components add maintenance burden, deviate from the design system, and are often less accessible than the Leo originals.

> **Reviewer note:** Tag `@nala-token-reviewers` when flagging this violation.

<a id="NA-008"></a>

### Components that are commonly reinvented — use Leo instead

| Don't build a custom… | Use… |
|---|---|
| Button with a dropdown menu | `ButtonMenu` from `@brave/leo/react/buttonMenu` |
| Tooltip / hover popover | `Tooltip` from `@brave/leo/react/tooltip` |
| Segmented control / tab switcher | `SegmentedControl` + `SegmentedControlItem` from `@brave/leo/react/segmentedControl` / `@brave/leo/react/segmentedControlItem` |
| Loading spinner / activity indicator | `ProgressRing` from `@brave/leo/react/progressRing` |
| Dropdown/context menu | `Menu` from `@brave/leo/react/menu` |
| Modal / overlay dialog | `Dialog` from `@brave/leo/react/dialog` |
| Toast / notification banner | `Alert` from `@brave/leo/react/alert` |
| Collapsible / accordion | `Collapse` from `@brave/leo/react/collapse` |

```tsx
// ❌ WRONG - hand-rolled loading spinner
function Spinner() {
  return <div className="spinner" aria-label="Loading..." />
}

// ✅ CORRECT - Leo ProgressRing
import ProgressRing from '@brave/leo/react/progressRing'

<ProgressRing />
```

```tsx
// ❌ WRONG - custom tooltip built from a div + hover state
function MyTooltip({ text, children }) {
  const [visible, setVisible] = React.useState(false)
  return (
    <div onMouseEnter={() => setVisible(true)} onMouseLeave={() => setVisible(false)}>
      {children}
      {visible && <div className="tooltip">{text}</div>}
    </div>
  )
}

// ✅ CORRECT - Leo Tooltip
import Tooltip from '@brave/leo/react/tooltip'

<Tooltip text="Helpful hint">
  <Button>Hover me</Button>
</Tooltip>
```

```tsx
// ❌ WRONG - bespoke segmented control
function MySegmentedControl({ options, value, onChange }) {
  return (
    <div className="segmented-control">
      {options.map(opt => (
        <button
          key={opt.value}
          className={value === opt.value ? 'active' : ''}
          onClick={() => onChange(opt.value)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  )
}

// ✅ CORRECT - Leo SegmentedControl
import SegmentedControl from '@brave/leo/react/segmentedControl'
import SegmentedControlItem from '@brave/leo/react/segmentedControlItem'

<SegmentedControl value={value} onChange={e => onChange(e.detail.value)}>
  <SegmentedControlItem value="a">Option A</SegmentedControlItem>
  <SegmentedControlItem value="b">Option B</SegmentedControlItem>
</SegmentedControl>
```

---
