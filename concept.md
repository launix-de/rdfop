# Layout System — Concept

This document describes the layout system that allows users to build their own dashboard and menu structure by composing layout nodes in a tree. Every node is an RDF resource; the entire layout is persisted as triples.

---

## Overview

The layout is a tree of **layout nodes**. Each node is one of:

- **Split** — divides its area into two panes (horizontal or vertical) with a draggable separator
- **TabGroup** — shows multiple children as tabs with a tab bar (top/bottom/left/right)
- **HTMLView** — a leaf node displaying editable HTML content
- **ComponentSelector** — a leaf node that lets the user pick a component type from a palette, then displays it

Non-leaf nodes (Split, TabGroup) spawn **ComponentSelector** nodes as placeholders for their children. The user then picks a concrete component type from the palette. Once selected, the ComponentSelector stores the choice and renders the chosen component in its full area. A small [x] button allows removing the selection and returning to the palette.

## Tree Structure

rdfop:parent -> store the parent of each node! (or leave if its the root node)
rdfop:children -> multiple-assignable ids of child nodes
rdfop:order -> order number for ordering of tabs/splits

---

## Node Creation
Every node type must have a constructor ttl with some default values. the node ID is (if unknown) a new uuid (scm function uuid already available)
new builtin create_component(parent_id, type, parameters...) as incomplete example creates a new component with fresh uuid, rdfop:parent, and type and calls the type-specific constructor for the default values

## Node Types

### ComponentSelector

The central building block. Every slot that "could be anything" starts as a ComponentSelector.

**RDF properties:**
- `rdfop:selectedType` — IRI of the selected EntityType (nil/not set = show palette)
- `rdfop:selectedNode` — IRI of the child node that was created (nil = show palette)

**Behavior:**
1. If `selectedNode` is nil → render the **palette**: a grid/list of available component types tagged with `rdfop:paletteVisible true`. Clicking one creates a new node of that type (with `uuid` IRI), stores it in `selectedNode`, and renders it.
2. If `selectedNode` is set → render the selected component via `render_component(selectedNode, "view")`. Show a small [x] button (top-right, hover-reveal) that clears `selectedNode` and `selectedType`, returning to the palette.

**Palette filtering:**
Only EntityTypes with `rdfop:paletteVisible true` appear in the palette. This allows controlling which types are user-instantiable.

```ttl
rdfop:Split rdfop:paletteVisible true .
rdfop:TabGroup rdfop:paletteVisible true .
rdfop:HTMLView rdfop:paletteVisible true .
```

### Split

Divides its area into two panes separated by a draggable divider.

**RDF properties:**
- `rdfop:splitDirection` — `"horizontal"` (left/right) or `"vertical"` (top/bottom). Default: `"horizontal"`.
- `rdfop:splitRatio` — float between 0.0 and 1.0. Default: `0.64` golden ratio. Persisted on drag end.
- `rdfop:children` — IRI of the left/top child node (default: a fresh ComponentSelector rdfop:order=1)
- `rdfop:children` — IRI of the right/bottom child node (default: a fresh ComponentSelector rdfop:order=2)

**Initialization:**
When a Split is created, two ComponentSelector children are automatically created (blank nodes → `urn:uuid:...`) and linked via `splitLeft` / `splitRight`.

**View template structure:**
```html
<div class="rdfop-c rdfop-split rdfop-split--horizontal"
     data-rdfop-id="..." data-rdfop-ratio="0.5"
     style="display:flex; flex-direction:row;">
  <div class="rdfop-split__pane" style="flex: 0.5;">
    <!-- render_component(splitLeft, "view") -->
  </div>
  <div class="rdfop-split__separator" draggable></div>
  <div class="rdfop-split__pane" style="flex: 0.5;">
    <!-- render_component(splitRight, "view") -->
  </div>
</div>
```

**Separator drag:**
- `mousedown` on separator starts tracking
- `mousemove` updates the flex ratios live (CSS only, no server call)
- `mouseup` persists the new ratio via `/rdfop-save` (DELETE old ratio + INSERT new ratio)

**No edit mode needed.** The split is always interactive. Direction and ratio could be changed via a small settings popover if needed later.

### TabGroup

Shows N children as tabs with a tab bar. New tabs can be added; tab headers can be renamed.

**RDF properties:**
- `rdfop:tabDirection` — `"top"` (default), `"bottom"`, `"left"`, `"right", "leftRotated", "rightRotated"`. Controls where the tab bar is placed.
- `rdfop:children` — IDs of the children (ordered by their attribute rdfop:order)

Each **tab** is a node of type `rdfop:Tab`:
- `rdfop:tabLabel` — display name (editable, default: "New Tab")
- `rdfop:tabContent` — IRI of the child node (a ComponentSelector)
- `rdfop:order`
- `rdfop:parent`

**View template structure:**
```html
<div class="rdfop-c rdfop-tabs rdfop-tabs--top" data-rdfop-id="...">
  <div class="rdfop-tabs__bar">
    <div class="rdfop-tabs__tab rdfop-tabs__tab--active"
         data-tab-id="urn:uuid:...">
      <span class="rdfop-tabs__label" ondblclick="rdfopTabRename(this)">Tab 1</span>
      <button class="rdfop-tabs__close" onclick="rdfopTabRemove(this)">&#x2715;</button>
    </div>
    <div class="rdfop-tabs__tab" data-tab-id="urn:uuid:...">
      <span class="rdfop-tabs__label" ondblclick="rdfopTabRename(this)">Tab 2</span>
      <button class="rdfop-tabs__close" onclick="rdfopTabRemove(this)">&#x2715;</button>
    </div>
    <button class="rdfop-tabs__add" onclick="rdfopTabAdd(this)">+</button>
  </div>
  <div class="rdfop-tabs__content">
    <!-- render_component(activeTab.tabContent, "view") -->
  </div>
</div>
```

done with a rdfhp subselect on the rdfop:children ORDER BY rdfop:order

**Tab bar behavior:**
- Clicking a tab switches the content area (client-side: hide/show, or server-side: re-render)
- Double-clicking a tab label makes it editable (inline input, save on blur/enter)
- The [x] on each tab removes it (DELETE tab triples + its ComponentSelector subtree)
- The [+] button creates a new Tab with a fresh ComponentSelector child

**Tab direction:**
- `"top"` / `"bottom"`: horizontal tab bar, tabs are normal width
- `"left"` / `"right"`: vertical sidebar, tab labels are NOT rotated and the sidebar is wider (~200px) to fit readable text
- `"leftRotated"` / `"rightRotated"`: vertical sidebar, tab labels are rotated

### HTMLView

Already implemented. A leaf node that stores and renders HTML content. Has `"view"` and `"edit"` components.

---

## Palette

The palette is rendered by the ComponentSelector when no component is selected. It queries all EntityTypes that have `rdfop:paletteVisible true` and displays them as clickable cards.

```rdfhp
@prefix rdfop: <https://launix.de/rdfop/schema#> .
SELECT ?type, ?label WHERE {
  ?type rdfop:paletteVisible true .
  OPTIONAL { ?type rdfs:label ?label }
  BEGIN
  PRINT etc.
}
```

Each card shows the type label (or IRI as fallback). Clicking a card:
1. Creates a new instance of that type (with `urn:uuid:...` IRI)
2. If the type has an `rdfop:initTemplate`, executes it to create default child nodes (e.g., Split creates two ComponentSelectors)
3. Stores the new node IRI in the ComponentSelector's `selectedNode`
4. Re-renders the ComponentSelector area with the new component

---

## Init Templates

When a component is instantiated from the palette, its type's `rdfop:initTemplate` is executed to set up default data. This is an RDFHP template that produces TTL triples to insert.

**incomplete Example: Split init template**
Creates the Split node with default direction, ratio, and two ComponentSelector children:

```rdfhp
@PREFIX rdfop: <https://launix.de/rdfop/schema#> .
?>
?id a rdfop:Split ;
  rdfop:splitDirection "horizontal" ;
  rdfop:splitRatio "0.64" ;
  rdfop:cildren <urn:uuid:<?rdf PRINT create_component(parent_id, type usw) ?>> ;
  rdfop:children <urn:uuid:<?rdf PRINT create_component(parent_id, type usw) ?>> .
<?rdf
```

(The exact mechanism for init templates needs refinement — the UUIDs for children must be generated and used consistently within a single init.)

**incomplete Example: TabGroup init template**
Creates the TabGroup with one default tab containing a ComponentSelector:

```
?id a rdfop:TabGroup ;
  rdfop:tabDirection "top" .

_:tab1 a rdfop:Tab ;
  rdfop:tabLabel "Tab 1" ;
  rdfop:tabContent _:sel1 .

_:sel1 a rdfop:ComponentSelector .

?id rdfop:order unix_timestamp .
```

---

## Node Tree Example

A typical dashboard layout:

```
main (ComponentSelector)
 └─ selectedNode → urn:uuid:split1 (Split, horizontal, 0.3)
     ├─ splitLeft → urn:uuid:sel-left (ComponentSelector)
     │   └─ selectedNode → urn:uuid:tabs1 (TabGroup, left)
     │       ├─ Tab "Menu" → urn:uuid:sel-menu (ComponentSelector)
     │       │   └─ selectedNode → urn:uuid:htmlview1 (HTMLView)
     │       └─ Tab "Settings" → urn:uuid:sel-settings (ComponentSelector)
     │           └─ (empty, shows palette)
     └─ splitRight → urn:uuid:sel-right (ComponentSelector)
         └─ selectedNode → urn:uuid:htmlview2 (HTMLView, "Hello World")
```

As RDF triples:
```ttl
main a rdfop:ComponentSelector ;
  rdfop:selectedNode <urn:uuid:split1> .

<urn:uuid:split1> a rdfop:Split ;
  rdfop:splitDirection "horizontal" ;
  rdfop:splitRatio "0.3" ;
  rdfop:splitLeft <urn:uuid:sel-left> ;
  rdfop:splitRight <urn:uuid:sel-right> .

<urn:uuid:sel-left> a rdfop:ComponentSelector ;
  rdfop:selectedNode <urn:uuid:tabs1> .

<urn:uuid:tabs1> a rdfop:TabGroup ;
  rdfop:tabDirection "left" ;
  rdfop:tabOrder <urn:uuid:tab-menu> ;
  rdfop:tabOrder <urn:uuid:tab-settings> .

<urn:uuid:tab-menu> a rdfop:Tab ;
  rdfop:tabLabel "Menu" ;
  rdfop:tabContent <urn:uuid:sel-menu> .

<urn:uuid:sel-menu> a rdfop:ComponentSelector ;
  rdfop:selectedNode <urn:uuid:htmlview1> .

<urn:uuid:htmlview1> a rdfop:HTMLView ;
  rdfop:html "<nav><a href='#'>Home</a></nav>" .

<urn:uuid:tab-settings> a rdfop:Tab ;
  rdfop:tabLabel "Settings" ;
  rdfop:tabContent <urn:uuid:sel-settings> .

<urn:uuid:sel-settings> a rdfop:ComponentSelector .

<urn:uuid:sel-right> a rdfop:ComponentSelector ;
  rdfop:selectedNode <urn:uuid:htmlview2> .

<urn:uuid:htmlview2> a rdfop:HTMLView ;
  rdfop:html "<h1>Hello World</h1>" .
```

---

## Recursive Rendering

`render_component(id, mode)` already supports recursive rendering via RDFHP's `CALL` statement. A Split's view template calls `render_component` for each child:

```rdfhp
CALL render_component(?leftId, REQ, RES)
```

This naturally produces a nested tree of server-rendered HTML. The client-side `rdfopSwap` replaces individual subtrees without affecting siblings.

---

## Persistence

All layout state is stored as RDF triples:
- Split ratios, directions
- Tab labels, order, active tab
- ComponentSelector selections
- HTMLView content

Changes are saved via the existing `rdfopCommit` / `/rdfop-save` mechanism (DELETE old triple + INSERT new triple). The split separator drag and tab rename use the same endpoint.

---

## CSS Layout

- **Split horizontal**: `display:flex; flex-direction:row;` with panes sized via `flex` property from ratio
- **Split vertical**: `display:flex; flex-direction:column;`
- **Split separator**: 4px wide/tall, `cursor:col-resize` or `cursor:row-resize`, background on hover
- **TabGroup top/bottom**: tab bar is `display:flex; flex-direction:row;`, content fills remaining space
- **TabGroup left/right**: `display:flex; flex-direction:row;` (or `row-reverse`), tab bar is a vertical sidebar (~200px), tabs stacked vertically
- **All layout nodes**: `width:100%; height:100%;` to fill their parent container. The root `main` fills the board area.

---

## Implementation Order

1. **ComponentSelector** — palette + selection + [x] remove (the foundation for everything)
2. **HTMLView in palette** — tag HTMLView as `paletteVisible`, verify ComponentSelector → HTMLView flow
3. **Split** — horizontal/vertical split with draggable separator, ratio persistence
4. **TabGroup** — tab bar, add/remove/rename tabs, tab direction
5. **Init templates** — auto-create children when instantiating Split/TabGroup from palette
6. **Main as ComponentSelector** — change `example.ttl` so `main` is a ComponentSelector (instead of HTMLView directly), enabling the user to build their own dashboard from scratch

---

## Answered Questions

- **Drag and drop**: users must be able to drag tabs between TabGroups, or drag panes to rearrange splits.
- **Undo**: The DELETE+INSERT mechanism is naturally reversible. A transaction log could support undo. -> "a rdfop:undo" nodes with rdfop:insert, rdfop:delete, rdfop:date (later: rdfop:user)
- **Cleanup**: When a ComponentSelector is cleared or a Tab is removed, the orphaned subtree should be cleaned up. `rdfop:deleteCode` rules handle this (defined per type).
