# Layout System — Concept

This document describes the layout system that allows users to build their own dashboard and menu structure by composing layout nodes in a tree. Every node is an RDF resource; the entire layout is persisted as triples.

---

## Overview

The layout is a tree of **layout nodes**. Each node is one of:

- **Split** — divides its area into two panes (horizontal or vertical) with a draggable separator
- **TabGroup** — shows multiple children as tabs with a tab bar (top/bottom/left/right)
- **HTMLView** — a leaf node displaying editable HTML content
- **ComponentSelector** — a placeholder that lets the user pick a component type from a palette, then displays it

Non-leaf nodes (Split, TabGroup) use **ComponentSelector** nodes as placeholders for their children. The user picks a concrete type from the palette; the ComponentSelector stores the choice and renders it full-area. A small [x] button removes the selection and returns to the palette.

---

## Tree Structure

Every node has:
- `rdfop:parent` — IRI of the parent node (absent for root)
- `rdfop:order` — numeric ordering among siblings (for tabs, split panes)

Parent nodes reference children via:
- `rdfop:children` — multi-valued, one triple per child IRI

Children are ordered by their `rdfop:order` value.

---

## Node Creation

Every node type has a **constructor** (`rdfop:initTemplate`) that produces default TTL triples. The framework provides:

```scheme
(create_component parent_id type)
```

This:
1. Generates a fresh `urn:uuid:...` for the new node
2. Inserts `<uuid> a <type> . <uuid> rdfop:parent <parent_id> .`
3. Inserts `<parent_id> rdfop:children <uuid> .`
4. Executes the type's `rdfop:initTemplate` to create default children/values
5. Returns the new node IRI

---

## Node Types

### ComponentSelector

The central building block. Every slot that "could be anything" starts as a ComponentSelector.

**RDF properties:**
- `rdfop:selectedType` — IRI of the selected EntityType (absent = show palette)
- `rdfop:selectedNode` — IRI of the child node (absent = show palette)

**Behavior:**
1. If `selectedNode` is absent → render the **palette**: a grid of available component types tagged with `rdfop:paletteVisible true`. Clicking one calls `create_component` and stores the result in `selectedNode`.
2. If `selectedNode` is set → render the selected component via `render_component(selectedNode, "view")`. Show a small [x] button (hover-reveal) that clears `selectedNode` and `selectedType`, deletes the child subtree, and returns to the palette.

**Palette filtering:**
```ttl
rdfop:Split rdfop:paletteVisible true .
rdfop:TabGroup rdfop:paletteVisible true .
rdfop:HTMLView rdfop:paletteVisible true .
```

### Split

Divides its area into two panes separated by a draggable divider.

**RDF properties:**
- `rdfop:splitDirection` — `"horizontal"` (left/right) or `"vertical"` (top/bottom). Default: `"horizontal"`.
- `rdfop:splitRatio` — float between 0.0 and 1.0. Default: `0.64` (golden ratio). Persisted on drag end.
- Two `rdfop:children` — left/top child (`rdfop:order` 1) and right/bottom child (`rdfop:order` 2). Both default to fresh ComponentSelectors.

**View template (RDFHP):**
```rdfhp
@PREFIX rdfop: <https://launix.de/rdfop/schema#> .
SELECT ?dir, ?ratio WHERE { $ID rdfop:splitDirection ?dir . $ID rdfop:splitRatio ?ratio }
BEGIN
?><div class='rdfop-c rdfop-split rdfop-split--<?rdf PRINT HTML ?dir ?>'
     data-rdfop-id='<?rdf PRINT HTML $RAWID ?>' data-rdfop-ratio='<?rdf PRINT HTML ?ratio ?>'
     style='display:flex; flex-direction:<?rdf PRINT HTML ?dir === "horizontal" ? "row" : "column" ?>'>
  <?rdf
  SELECT ?child WHERE { ?child rdfop:parent $ID } BEGIN
  ?><div class='rdfop-split__pane'><?rdf
    CALL render_component(?child, REQ, RES)
  ?></div><?rdf
  END
  ?>
  <div class='rdfop-split__separator'></div>
</div><?rdf
END
```

Note: The actual flex sizing and separator insertion use JS to apply the ratio from `data-rdfop-ratio`.

**Separator drag:**
- `mousedown` on separator starts tracking
- `mousemove` updates flex ratios live (CSS only, no server call)
- `mouseup` persists via `/rdfop-save` (DELETE old ratio + INSERT new ratio using `rdf_quote`)

**No edit mode needed.** The split is always interactive.

### TabGroup

Shows N children as tabs with a tab bar. New tabs can be added; tab headers can be renamed.

**RDF properties:**
- `rdfop:tabDirection` — `"top"` (default), `"bottom"`, `"left"`, `"right"`, `"leftRotated"`, `"rightRotated"`.

Each child is a `rdfop:Tab` node with:
- `rdfop:tabLabel` — display name (editable, default: "New Tab")
- `rdfop:parent` — points to the TabGroup
- `rdfop:order` — numeric position
- `rdfop:children` — one child, typically a ComponentSelector

**View template (RDFHP):**
The template queries children ordered by `rdfop:order`, renders a tab bar with labels + [x] buttons + [+] add button, and a content area that renders each tab's child. Tab switching is client-side JS (hide/show panels). The template uses nested SELECTs:

```rdfhp
@PREFIX rdfop: <https://launix.de/rdfop/schema#> .
SELECT ?dir WHERE { $ID rdfop:tabDirection ?dir }
BEGIN
?><div class='rdfop-c rdfop-tabs rdfop-tabs--<?rdf PRINT HTML ?dir ?>' data-rdfop-id='<?rdf PRINT HTML $RAWID ?>'>
  <div class='rdfop-tabs__bar'>
    <?rdf
    SELECT ?tab, ?label WHERE { ?tab rdfop:parent $ID . ?tab a rdfop:Tab . ?tab rdfop:tabLabel ?label }
    BEGIN
    ?><div class='rdfop-tabs__tab' data-tab-id='<?rdf PRINT HTML ?tab ?>' onclick='rdfopTabSwitch(this)'>
      <span class='rdfop-tabs__label' ondblclick='rdfopTabRename(this)'><?rdf PRINT HTML ?label ?></span>
      <button class='rdfop-tabs__close' onclick='rdfopTabRemove(this)'>&#x2715;</button>
    </div><?rdf
    END
    ?>
    <button class='rdfop-tabs__add' onclick='rdfopTabAdd(this)'>+</button>
  </div>
  <div class='rdfop-tabs__content'>
    <?rdf
    SELECT ?tab, ?child WHERE { ?tab rdfop:parent $ID . ?tab a rdfop:Tab . ?tab rdfop:children ?child }
    BEGIN
    ?><div class='rdfop-tabs__panel' data-tab-id='<?rdf PRINT HTML ?tab ?>'>
      <?rdf CALL render_component(?child, REQ, RES) ?>
    </div><?rdf
    END
    ?>
  </div>
</div><?rdf
END
```

**Tab bar behavior:**
- Clicking a tab switches the content panel (client-side hide/show)
- Double-clicking a tab label → inline input, save on blur/enter via `/rdfop-save`
- [x] on a tab → removes the tab node + its subtree
- [+] button → `create_component(tabGroupId, rdfop:Tab)`, creates a new Tab with a fresh ComponentSelector child

**Tab direction:**
- `"top"` / `"bottom"`: horizontal tab bar
- `"left"` / `"right"`: vertical sidebar (~200px), tab labels NOT rotated
- `"leftRotated"` / `"rightRotated"`: vertical sidebar, tab labels rotated 90°

### HTMLView

Already implemented. A leaf node that stores and renders HTML content. Has `"view"` and `"edit"` EditorComponents.

---

## Node Tree Example

A typical dashboard layout:

```
main (TabGroup, top)
 ├─ Tab "Dashboard" (order 1)
 │   └─ (ComponentSelector)
 │       └─ Split (horizontal, 0.3)
 │           ├─ (ComponentSelector, order 1)
 │           │   └─ HTMLView "<nav>Menu</nav>"
 │           └─ (ComponentSelector, order 2)
 │               └─ HTMLView "<h1>Hello World</h1>"
 └─ Tab "Settings" (order 2)
     └─ (ComponentSelector)
         └─ (empty — shows palette)
```

As RDF triples:
```ttl
@prefix rdfop: <https://launix.de/rdfop/schema#> .

main a rdfop:TabGroup ;
  rdfop:tabDirection "top" .

_:tab1 a rdfop:Tab ;
  rdfop:parent main ;
  rdfop:tabLabel "Dashboard" ;
  rdfop:order "1" ;
  rdfop:children _:sel1 .

_:sel1 a rdfop:ComponentSelector ;
  rdfop:parent _:tab1 ;
  rdfop:selectedNode _:split1 .

_:split1 a rdfop:Split ;
  rdfop:parent _:sel1 ;
  rdfop:splitDirection "horizontal" ;
  rdfop:splitRatio "0.3" ;
  rdfop:children _:sel2 ;
  rdfop:children _:sel3 .

_:sel2 a rdfop:ComponentSelector ;
  rdfop:parent _:split1 ;
  rdfop:order "1" ;
  rdfop:selectedNode _:hw1 .

_:hw1 a rdfop:HTMLView ;
  rdfop:parent _:sel2 ;
  rdfop:html "<nav>Menu</nav>" .

_:sel3 a rdfop:ComponentSelector ;
  rdfop:parent _:split1 ;
  rdfop:order "2" ;
  rdfop:selectedNode _:hw2 .

_:hw2 a rdfop:HTMLView ;
  rdfop:parent _:sel3 ;
  rdfop:html "<h1>Hello World</h1>" .

_:tab2 a rdfop:Tab ;
  rdfop:parent main ;
  rdfop:tabLabel "Settings" ;
  rdfop:order "2" ;
  rdfop:children _:sel4 .

_:sel4 a rdfop:ComponentSelector ;
  rdfop:parent _:tab2 .
```

---

## Recursive Rendering

`render_component(id, mode)` supports recursive rendering via RDFHP's `CALL` statement:

```rdfhp
CALL render_component(?child, REQ, RES)
```

This produces a nested tree of server-rendered HTML. The client-side `rdfopSwap` replaces individual subtrees without affecting siblings.

**Template variable convention:**
- `$ID` — replaced with the SPARQL-safe subject IRI (e.g., `<urn:uuid:...>` or `main`)
- `$RAWID` — replaced with the raw IRI string (for HTML attributes, without angle brackets)

---

## Save-Back

All mutations use `/rdfop-save` with `delete=TTL&insert=TTL`:

- **String values**: use `rdf_quote()` in Scheme or `JSON.stringify()` in JS to produce escaped TTL string literals
- **Split ratio drag**: `delete=<id> <rdfop:splitRatio> "0.5" .` + `insert=<id> <rdfop:splitRatio> "0.3" .`
- **Tab rename**: `delete=<tabId> <rdfop:tabLabel> "Old" .` + `insert=<tabId> <rdfop:tabLabel> "New" .`
- **ComponentSelector selection**: `insert=<selectorId> <rdfop:selectedNode> <newChildId> .`

`delete_ttl` parses the TTL and deletes matching triples via `scan` + `$update`. `load_ttl` inserts new triples.

---

## CSS Layout

- **Split horizontal**: `display:flex; flex-direction:row;` with panes sized via `flex` from ratio
- **Split vertical**: `display:flex; flex-direction:column;`
- **Split separator**: 4px wide/tall, `cursor:col-resize` or `cursor:row-resize`, highlight on hover
- **TabGroup top/bottom**: `display:flex; flex-direction:column;` (or `column-reverse`), tab bar horizontal
- **TabGroup left/right**: `display:flex; flex-direction:row;` (or `row-reverse`), tab bar vertical (~200px)
- **TabGroup leftRotated/rightRotated**: same but `writing-mode:vertical-lr` on tab labels
- **All layout nodes**: `width:100%; height:100%;` to fill parent. Root `main` fills the board area.

---

## JS Helpers

| Function | Description |
|----------|-------------|
| `rdfopSwap(el, mode)` | Replace `.rdfop-c` element with a different component mode via AJAX |
| `rdfopEdit(btn)` | Find nearest `.rdfop-c`, swap to `"edit"` |
| `rdfopCancel(btn)` | Find nearest `.rdfop-c`, swap to `"view"` |
| `rdfopCommit(btn)` | Save textarea changes via DELETE+INSERT, swap to `"view"` |
| `rdfopTabSwitch(tab)` | Client-side tab switching (show/hide panels) |
| `rdfopTabRename(span)` | Inline-edit tab label (dblclick → input → save on blur) |
| `rdfopTabAdd(btn)` | Create new Tab with ComponentSelector child |
| `rdfopTabRemove(btn)` | Remove tab + subtree |
| `rdfopSplitDrag(sep)` | Start separator drag, persist ratio on mouseup |

---

## Implementation Order

1. **Fix RDFHP parsing** — `$ID` with `<urn:uuid:...>` in templates (currently broken after init.scm loads)
2. **TabGroup rendering** — get the existing TabGroup view template working with recursive child rendering
3. **Tab interactions** — switch, rename, add, remove tabs
4. **Split** — horizontal/vertical split with draggable separator
5. **ComponentSelector** — palette + selection + [x] remove
6. **Init templates** — `create_component` with type-specific defaults
7. **Main as ComponentSelector** — user builds own dashboard from scratch

---

## Answered Questions

- **Drag and drop**: users must be able to drag tabs between TabGroups and rearrange split panes (future enhancement).
- **Undo**: DELETE+INSERT is naturally reversible. Transaction log via `rdfop:UndoEntry` nodes with `rdfop:insertTtl`, `rdfop:deleteTtl`, `rdfop:timestamp` (later: `rdfop:user`).
- **Cleanup**: When a ComponentSelector is cleared or a Tab removed, orphaned subtrees are cleaned up via `rdfop:deleteCode` rules per type.
