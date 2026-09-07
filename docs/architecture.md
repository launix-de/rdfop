# RDFOP Architecture

This document describes the contracts between RDF data, the Scheme server,
RDFHP rendering, and the browser runtime. The shorter `AGENTS.md` turns these
contracts into rules for repository changes.

## 1. System model

RDFOP treats application structure and application data alike: both are RDF
resources. A resource's type or direct mode binding selects an RDFHP component,
and that component renders a DOM fragment.

```text
RDF graph
   │
   ├── resource type / direct view binding
   ▼
RDFHP EditorComponent
   │
   ▼
HTML fragment (`.rdfop-c`)
   │ user action
   ▼
RDF DELETE/INSERT
   │
   └── rerender smallest stable component
```

The RDF graph is authoritative. Browser state may support an interaction in
progress, but committed state must survive a complete reload.

Resource URIs are used end to end. The same identifier appears in RDF triples,
request parameters, `data-testid`, action URLs, and drag payloads.

### 1.1 One viewer, one root component

The full-page template is a viewer, not an application-specific page. Its
canvas makes one call to `render_object(?id, REQ, RES)`. The root redirect opens
the conventional application resource `main`; the component selected for
`main` then composes the complete interface as RDF.

```text
viewer
└── render_object(main)
    └── one root component
        ├── Split
        ├── TabGroup
        ├── ComponentSelector / palette
        ├── TableView
        └── Browser, Explorer, or another editor component
```

The alternatives in this diagram can be nested arbitrarily; they are not extra
page roots. The shared HTML shell must not acquire application navigation,
lists, panels, or workflows. Those remain editable component resources below
`main`.

## 2. Routing

### 2.1 Handler chain

`lib/rdfop.scm` creates `rdfop_routes`, a request-path-to-handler registry. It
also wraps the previously installed `http_handler`:

```text
request
   │
   ▼
latest RDFOP handler layer
   ├── registered exact route → route handler
   └── unknown route → previous handler
```

`web/init.scm` adds another handler layer for the public resource-action form:

```text
/<action>/<percent-encoded-resource-id>
```

The action name must start with an ASCII letter and may otherwise contain ASCII
letters, digits, and underscores. The remainder of the path is decoded as the
resource ID. Every handler wrapper must retain the old handler and delegate
requests it does not own. Replacing the chain instead of wrapping it makes
routes disappear depending on module load order.

### 2.2 Action dispatch

`view` is an action, not a separate routing scheme. The HTTP dispatcher treats
it specially because it needs a complete browser page: it injects the decoded
ID into the request and invokes the `/view` page-template handler registered for
`web/index.rdfhp`. The page template calls `render_object`, whose default mode is
`view`.

Every other action is sent to `_dispatch_action`. Dispatch succeeds only if the
corresponding schema resource is declared as a method:

```ttl
rdfop:edit a rdfop:Method .
```

The dispatcher resolves the RDFHP template in this order:

1. `resource rdfop:<action> template`;
2. `resource a type` and `type rdfop:<action> template`.

It then evaluates the template with `?id` and the URL query parameters. The
internal `rdfop_action(action, id, ...)` function deliberately uses the same
`_dispatch_action` implementation. Do not introduce a second action-resolution
path.

### 2.3 Full pages and fragments

Action routing and SPA fragment rendering are distinct surfaces:

| URL | Result | Intended use |
| --- | --- | --- |
| `/<action>/<id>` | RDF-defined action; `view` returns the complete page shell | Public resource links and actions |
| `/rdfop-render?id=<id>&mode=<mode>` | One component fragment | SPA refresh, overlay content |
| `/rdfop-render?comp=<component>&id=<id>` | Explicit component fragment | Editors and framework tools |

Only `web/index.rdfhp` owns the document shell and shared browser runtime.
Components and other endpoints return fragments, JSON, or plain data—not a
nested `<html>` document.

`/rdfop-render` is an exact technical endpoint in `rdfop_routes`; it is not an
alternative public resource-route format.

### 2.4 Route handler contract

A route handler should:

1. validate and decode its parameters;
2. set a specific `Content-Type`;
3. set an explicit success or error status;
4. mutate RDF only after validation succeeds;
5. return data suitable for the caller rather than rendering a second shell.

Unknown paths continue down the handler chain. Server-controlled values such as
upstream hosts, executable names, credentials, and model configuration never
come from untrusted browser parameters.

## 3. Component resolution and rendering

`render_object` resolves a resource for the requested mode (`view` by default):

1. look for a direct binding such as `resource rdfop:view component`;
2. otherwise find `resource a type` and `type rdfop:view component`;
3. render the selected `rdfop:EditorComponent` with the resource as `?id`.

Direct bindings are useful for exceptional resources. Type bindings are the
normal reusable mechanism.

A swappable component follows this wrapper contract:

```html
<div class="rdfop-c"
     data-testid="RESOURCE_ID"
     data-rdfop-params='{"id":"RESOURCE_ID"}'>
  ...
</div>
```

`rdfopSwap()` uses `data-rdfop-params` to request another mode and replaces the
root node. `rdfopMountNode()` initializes component JavaScript after initial
rendering and every fragment replacement.

### 3.1 Components form a nested render tree

Every rendered `rdfop:EditorComponent` instance owns one `.rdfop-c` DOM root.
The root is both its browser boundary and its AJAX replacement boundary. A
component can embed other components from RDFHP with
`CALL render_object(...)` or `CALL render_component(...)`:

```text
.rdfop-c parent
├── ordinary parent markup
├── .rdfop-c child A
└── .rdfop-c child B
    └── .rdfop-c grandchild
```

Each nested component carries its own `data-rdfop-params`. Calling
`rdfopSwap(child, mode)` sends those parameters to `/rdfop-render`, replaces
only the child's root HTML, and calls `rdfopMountNode()` for the replacement.
The parent and sibling DOM remain intact.

Prefer this smallest stable replacement boundary after a mutation. Refresh the
parent only when the mutation changes child membership, ordering, or another
piece of state owned by the parent; refresh the complete canvas only when the
changed ownership cannot be recovered from a stable nested root.

Escaping is contextual:

- `PRINT HTML` for visible text and HTML attributes;
- `PRINT JSON` for JSON and JavaScript values;
- `PRINT URL` for URL path/query components;
- `PRINT RAW` only for markup which is already trusted.

## 4. Layout graph

Layout is ordinary RDF. Four predicates carry most of the structure:

- `rdfop:children`: containment or layout ownership;
- `rdfop:selectedNode`: active content of a selector;
- `rdfop:order`: stable sibling order;
- `rdfop:splitRatio`, `rdfop:splitDirection`, and `rdfop:tabDirection`:
  component-specific presentation state.

### 4.1 ComponentSelector is a capability

A `ComponentSelector` is not merely a convenient `<div>`. It grants the UI the
ability to replace, move, clear, or repopulate that layout position.

Use it for a configurable work area:

```text
ComponentSelector
└── selectedNode → current component
```

Do not use it around fixed application chrome. A permanent navigation panel is
a direct split child:

```text
Split
├── fixed TableView
└── ComponentSelector
    └── configurable workspace
```

Wrapping the fixed table in another selector would expose the selector's clear
and drag controls and would therefore make the navigation removable.

### 4.2 Split

The intended split graph has exactly two effective children. Both children
carry `rdfop:order`; the split carries its direction and persisted ratio.

```ttl
:split a rdfop:Split ;
  rdfop:splitDirection "horizontal" ;
  rdfop:splitRatio "0.25" ;
  rdfop:children :navigation, :workspace .

:navigation rdfop:order "10" .
:workspace  rdfop:order "20" .
```

The renderer does not require the children to be selectors. `SplitH` and
`SplitV` create selectors by default because newly created generic splits are
configurable. Application schemas may deliberately attach fixed components
directly.

The separator updates `rdfop:splitRatio`, so its position survives reload. The
`rdfop:onChildRemoved` action collapses a configurable split when one side is
removed; changes to its graph assumptions require focused removal and reload
tests.

### 4.3 Tabs

A `TabGroup` owns ordered `Tab` resources. A tab has one child. That child may
be a component directly or a selector containing the active component.

```text
TabGroup
├── Tab (order 10)
│   └── fixed component
└── Tab (order 20)
    └── ComponentSelector
        └── selected component
```

Tab labels, order, children, and active content are RDF state. Reordering or
closing a tab must update the graph before rerendering the group.

## 5. URI-based drag and drop

RDFOP uses URLs as the interchange format between drag sources and drop targets.
Resource links follow the generic action form:

```text
/<action>/<percent-encoded-resource-id>
```

### 5.1 Objects should be links and drag sources

Wherever practical, an RDF object displayed in the UI is represented by a real
`<a href>` carrying one of its action URLs. The URL is simultaneously:

- a normal browser navigation and bookmark target;
- the stable identity exported through drag and drop;
- an interchange format understood across components and browser contexts.

Object renderers should therefore publish the absolute action URL as
`text/uri-list` and `text/plain`. RDFOP-specific payloads supplement that URI;
they must not replace it. For example, `application/x-rdfop-source` describes
the layout owner that may need cleanup after a successful move, while the URI
continues to identify the dragged RDF resource.

The current component drag/drop implementation accepts only the `view` instance
of that action URL (`action = view`). This restriction belongs to
`rdfopDragReadViewIdFromUri`; it is not the router's resource-URL model:

```text
/view/<percent-encoded-resource-id>
```

The shared drag source writes:

```text
text/uri-list:                 absolute resource view-action URL
text/plain:                    absolute resource view-action URL
application/x-rdfop-kind:     component
application/x-rdfop-source:   optional layout-source metadata
application/x-rdfop-tab-label optional suggested label
```

The common lifecycle is:

```text
rdfopDragStartLink
        │
        ▼
drop target validates URI/kind
        │
        ▼
rdfopDragMaterializeDroppedComponent
        │
        ├── internal view-action URL → existing RDF resource
        └── external HTTP(S)   → new Website resource
        │
        ▼
persist destination binding
        │
        ▼
rdfopDragMarkDropped
        │
        ├── source metadata present → clean old layout owner
        └── no source metadata      → copy/open; preserve source
        │
        ▼
rdfopDragFinish
```

`application/x-rdfop-source` changes semantics. A selector or tab drag includes
it because the old layout owner may need cleanup. A TableView row deliberately
does not include it: the row represents a domain entity, so dropping it opens
or embeds the entity without deleting any RDF data or removing the row.

Drop targets must complete the destination mutation before requesting source
cleanup. This ordering prevents a failed drop from destroying the only layout
reference.

### 5.2 Drop targets express slot semantics

Drop is not limited to rearranging existing layout DOM. Any component whose RDF
model contains a resource-valued slot should consider accepting compatible URI
drags. Important examples are:

- a `ComponentSelector`, including an empty palette, accepting its selected
  component;
- an edge of a configurable area creating or populating a `Split`;
- a `TabGroup` opening the resource in an existing or new tab;
- a dropdown, autocomplete, or relation editor selecting the dropped RDF
  resource as its value;
- a datatype-provided table-cell editor accepting a compatible resource value.

The target owns interpretation. It resolves the action URL to the resource,
checks the accepted RDF type/datatype and local capability, persists the target
predicate or layout relationship, and rerenders the smallest stable component.
An incompatible or unauthorized resource is rejected without changing source
or destination state.

Opening/copying and moving are distinct. A dragged domain entity normally
remains in its source collection. Source cleanup is used only when explicit
layout-owner metadata says that a successfully dropped component is being
moved out of a selector, tab, or similar container.

## 6. Mutations and refresh

`rdfopSave(deleteTtl, insertTtl)` and `/rdfop-save` are the general exact-triple
mutation path. Typed endpoints implement operations with additional semantics,
such as creating an entity, creating a child, cleaning a drag source, or deleting
a component tree.

Choose the narrowest stable refresh owner after a mutation:

- refresh the component with `rdfopSwap()` when its identity remains stable;
- refresh a TabGroup after tab membership/order changes;
- call `rdfopRefreshCanvas()` when ownership changed above the current fragment.

Do not treat a DOM removal as persistence. Do not delete a domain entity merely
because a selector, tab, or split stopped displaying it.

## 7. TableView contract

A `TableView` is RDFOP's common list abstraction and a central building block
for applications. All entity and record lists use it. A missing list feature is
a reason to extend `TableView`, its RDF configuration, or the datatype system;
it is not a reason to introduce an application-specific list component.

### 7.1 Current configuration and interaction

The existing implementation selects entities with `rdfop:itemType`. Ordered
`TableColumn` children select direct properties. `rdfop:openTarget` determines
whether activation opens an overlay or a `TabGroup`, and `rdfop:openAction`
selects the resource action. `rdfop:TableAction` children provide ordered global
buttons, including creation workflows.

The current editor configures the entity type, columns, open target/action,
default sort column/direction, and one runtime filter property. The view applies
that filter to request state without rewriting the shared table definition.
`rdfop:configurationLocked` currently suppresses the editor and rejects table
configuration writes server-side.

Each row:

- carries its resource in `data-resource`;
- remains activatable by click, Enter, and Space;
- exposes the resource's current `view` action URL to drag and drop;
- never owns the underlying entity.

### 7.2 Required evolution stays in TableView

The shared component is expected to grow with application requirements:

- virtual scrolling and incremental rendering for large result sets;
- interactive and default sorting without duplicating the data-source logic;
- composable persistent and request-scoped filters;
- configurable global actions and per-item actions;
- configurable property selection and column order;
- deliberate rendering of multi-valued properties, including list and chip
  presentations.

These capabilities should be represented in RDF and edited through the shared
TableView editor. Rendering performance may require new RDFHP/runtime
primitives, but the user-facing abstraction remains `TableView`.

### 7.3 Datatypes own cell behavior

Table cells are component slots, not permanently stringified RDF values. The
datatype system must associate each datatype with a component for displaying
and editing one property value. `TableView` selects and embeds that component
for each value/cell. A column may override presentation where the RDF
configuration explicitly allows it, for example to render a multi-valued
property as chips.

This keeps formatting, validation, and editing semantics with the datatype and
makes them reusable outside tables. Do not add growing chains of datatype checks
to `TableView` or create a separate list component for a new cell type.

### 7.4 Configuration is a capability

An editable TableView and a fixed TableView are the same component. The
difference is whether the current user has the capability to invoke its
configuration action. The capability must govern both presentation of the edit
control and acceptance of the configuration mutation on the server.

The existing global `rdfop:configurationLocked` value is useful as a temporary
coarse lock, but it does not model per-user authorization. Future capability
work must replace or subsume that shortcut rather than adding a second, fixed
table implementation.

## 8. Building an application

An application consists of two related layers in the RDF graph:

- definitions describe entity types, properties, components, and methods;
- instances contain domain data and the component/layout tree rooted at `main`.

The top-level schema file composes reusable modules with `rdfop:include`. The
watchers in `web/init.scm` reload the top-level file and its includes while the
server is running. Keep framework components, application schema, and seed data
in separate TTL files so schema reloads do not masquerade as user mutations.

### 8.1 Define the domain and its view

An entity becomes renderable by binding its type to an
`rdfop:EditorComponent`. The component queries the RDF graph and returns one
swappable root:

```ttl
@prefix app: <https://example.test/app#> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix rdfop: <https://launix.de/rdfop/schema#> .

app:Record a rdfop:EntityType ;
  rdfs:label "Record" ;
  rdfop:view app:Record_view .

app:title a rdf:Property ;
  rdfs:label "Title" .

app:Record_view a rdfop:EditorComponent ;
  rdfop:componentTemplate """@PREFIX app: <https://example.test/app#> .
PARAMETER ?id "id"
SELECT ?title WHERE { ?id app:title ?title } LIMIT 1
BEGIN
?><article class='rdfop-c' data-testid='<?rdf PRINT HTML ?id ?>'
  data-rdfop-params='{&quot;id&quot;:<?rdf PRINT JSON ?id ?>}'>
  <h1><?rdf PRINT HTML ?title ?></h1>
</article><?rdf
END""" .
```

Add an `rdfop:edit` binding only when the type supports that mode. Reuse an
existing component where its graph contract fits; create a new component when
the application needs a different query, markup, or browser interaction.

The component definition itself is always editable independently of whether
the displayed domain type has an edit mode. Because every component is an
`rdfop:EditorComponent`, the type-level binding
`rdfop:EditorComponent rdfop:edit rdfop:EditorComponent_edit` opens the generic
component editor. It edits `rdfop:componentTemplate`, `rdfop:css`, and
`rdfop:js` as RDF properties and provides a live preview against a selected
subject. New components must preserve this path; they are not native UI classes
hidden in Scheme.

### 8.2 Compose the application layout

`main` is the conventional resource opened by the root redirect. It is an
ordinary renderable layout node, not a hard-coded application class. For
example, a fixed list can sit directly beside a configurable work area:

```ttl
@prefix app: <https://example.test/app#> .
@prefix rdfop: <https://launix.de/rdfop/schema#> .

main a rdfop:Split ;
  rdfop:splitDirection "horizontal" ;
  rdfop:splitRatio "0.3" ;
  rdfop:children app:navigation, app:workspace .

app:navigation a rdfop:TableView ;
  rdfop:order "1" ;
  rdfop:itemType app:Record ;
  rdfop:openTarget rdfop:OverlayTarget ;
  rdfop:openAction rdfop:view ;
  rdfop:children app:titleColumn .

app:titleColumn a rdfop:TableColumn ;
  rdfop:order "1" ;
  rdfop:columnProperty app:title ;
  rdfop:columnLabel "Title" .

app:workspace a rdfop:ComponentSelector ;
  rdfop:order "2" .
```

Direct split children are appropriate for fixed application structure. Insert
a `ComponentSelector` only where the user is meant to choose, replace, move, or
remove content. Use a `TabGroup` when the work area must retain several ordered
resources at once.

### 8.3 Add data and behavior

Domain instances are normal RDF resources:

```ttl
@prefix app: <https://example.test/app#> .

app:firstRecord a app:Record ;
  app:title "First record" .
```

The `TableView` discovers the instance through `rdfop:itemType`; activating it
uses the table's configured `rdfop:openAction` and `rdfop:openTarget`.

Application-specific actions use the shared action dispatcher. The URL action
name maps to a predicate in the RDFOP schema namespace, so declare it as a
method and bind an RDFHP snippet directly to the resource or its type:

```ttl
@prefix app: <https://example.test/app#> .
@prefix rdfop: <https://launix.de/rdfop/schema#> .

rdfop:archive a rdfop:Method .

app:Record rdfop:archive """@PREFIX app: <https://example.test/app#> .
INSERT { ?id app:state "archived" }
""" .
```

The same implementation is reachable through `/<action>/<id>` and through
`rdfop_action(...)` from another RDFHP template. Browser code should normally
use the shared mutation and refresh helpers rather than inventing an additional
state store or endpoint.

### 8.4 Grow the application safely

Keep these boundaries as the application grows:

- domain resources carry business state;
- layout resources describe where and how domain resources are displayed;
- components translate RDF into HTML and user gestures into RDF mutations;
- methods provide named resource behavior through the shared dispatcher;
- focused `rdfop:PlaywrightTest` resources cover interaction and reload behavior.

This allows a domain model, another layout, or another view component to evolve
without replacing the routing and rendering infrastructure.

RDFHP is the normal extension boundary. Scheme should provide only shared
runtime capabilities which RDFHP cannot express itself. When such a primitive
is necessary, register it in `rdf_functions` so templates can use it through
`CALL`, or extend the RDFHP language when a language construct is the cleaner
general abstraction. Verify the feature through an RDFHP component or method so
the native function does not become an inaccessible parallel API.

## 9. Tests and architectural changes

Component regression tests are stored as `rdfop:PlaywrightTest` resources next
to the component they cover. Layout and persistence tests use generated URIs,
perform the interaction, reload, and verify the reconstructed state.

Run one family locally with:

```bash
RDFOP_TEST_FILTER='part of test label' npm run test:playwright
```

RDFOP currently has no CI test runner. Run the complete Playwright suite locally
before handing off changes which can affect shared routing, rendering, layout,
drag/drop, mutation, or component behavior. The filter is for shortening the
development loop, not a replacement for the final full run.

When a change intentionally alters one of these contracts, update this document
and `AGENTS.md` in the same review. For larger decisions, add a short ADR under
`docs/decisions/` and link it from here.
