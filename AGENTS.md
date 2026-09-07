# RDFOP Repository Guide

This file applies to the complete repository. RDFOP is a self-describing RDF
application framework; preserve that architecture instead of growing a second,
hard-coded application framework beside it.

## Primary Extension Model

- Model domain concepts as RDF entity types, properties, methods, and resources.
- Implement UI components as RDF resources of type `rdfop:EditorComponent`.
- Store component behavior in RDF through `rdfop:componentTemplate`, `rdfop:css`,
  and `rdfop:js`. The template language is RDFHP.
- Bind components to entities or entity types with RDF actions such as
  `rdfop:view` and `rdfop:edit`.
- Implement resource actions as `rdfop:Method` resources with RDFHP bodies.
  Actions may be bound directly to one resource or inherited through its type.
- Compose applications from RDF entities and layout components. Do not add a
  bespoke Scheme route, renderer, or data structure for an application feature
  that can be represented by these mechanisms.

When adding a feature, consider these options in order:

1. data or configuration expressed as RDF entities;
2. an existing RDFHP component or method;
3. a new RDFHP component or method;
4. a generally useful extension to RDFHP;
5. a Scheme runtime extension only when the preceding layers cannot provide the
   required capability.

## Application Composition Starts at One Component

- The viewer renders one resource through `render_object`; the application entry
  point is the renderable resource `main`.
- Do not turn the page shell into an application layout. The component selected
  for `main` owns all further composition in RDF.
- A `ComponentSelector` in its empty state is the palette: it lets the user choose
  which component occupies that configurable area.
- Build larger interfaces by nesting RDF components such as `TabGroup`, `Split`,
  `ComponentSelector`, and editors such as `Browser` or `Explorer`.
- Fixed areas are direct layout children. Put a selector/palette only around an
  area whose contents the user is allowed to replace.

## TableView Is the List Abstraction

- Implement every entity-list or record-list UI as a `TableView`. When a list use
  case needs a missing feature, extend the shared `TableView`; do not create a
  parallel application-specific list component.
- `TableView` owns list querying and presentation: entity type, filters, default
  and interactive sorting, visible properties, column order, and presentation of
  multi-valued properties such as lists or chips.
- `TableView` also owns list interaction: global actions such as creating an
  entity and per-item actions such as opening, editing, or invoking a method.
- Large result sets must be supported by extending `TableView` with virtual
  scrolling rather than replacing it with another list implementation.
- Cell rendering and editing belongs to the datatype system. Each datatype
  supplies a component which `TableView` embeds for the corresponding property
  value/cell; do not hard-code datatype presentation into individual tables.
- Table configuration is itself editable through the shared TableView editor.
  Authorization to open or use that editor is a capability decision per user.
  A fixed application may withhold that capability, but must still use the same
  TableView component and configuration model.
- Treat current shortcuts such as a global `rdfop:configurationLocked` flag as
  interim mechanisms, not as a substitute for per-user capabilities.

## Components Are Editable RDF

- Component definitions are application data, not compiled-in UI classes.
- Every new component must be an `rdfop:EditorComponent` and remain editable
  through the component editor. Do not create components which can only be
  changed by editing Scheme or the shared page shell.
- `rdfop:EditorComponent rdfop:edit rdfop:EditorComponent_edit` is the generic
  edit binding for component definitions. The editor changes the component's
  RDFHP template, CSS, and JavaScript and renders a live preview against a chosen
  subject. Preserve this self-hosting development path.
- Components may expose named actions by attaching `rdfop:Method` predicates to
  their resource or type. Keep those action implementations in RDFHP as well.
- Component-specific browser code belongs in the component's `rdfop:js`, not in
  `web/index.rdfhp`. The page shell contains only shared browser/runtime
  facilities needed by multiple components.
- A component which edits domain state must persist that state in RDF. Its view
  and edit interaction must be reconstructible after reload.

## Scheme and RDFHP Boundary

- Scheme implements the RDFHP compiler, storage/runtime integration, HTTP
  transport, and genuinely shared primitives. It is not the normal application
  extension layer.
- Do not keep expanding `web/init.scm`, `lib/rdfop.scm`, or
  `lib/rdfop-parser.scm` with component-specific behavior.
- If a missing capability is general enough for templates, extend RDFHP rather
  than bypassing it from one component.
- If a new Scheme library function is unavoidable, register a useful interface
  in `rdf_functions` so RDFHP can invoke it with `CALL` (or add an equally
  general RDFHP language construct when that is the better abstraction).
- Test new primitives through an RDFHP component or method, not only by calling
  the Scheme implementation directly.
- Keep the exposed primitive narrow: RDFHP remains responsible for queries,
  control flow, rendering, and composition whenever possible.

## RDF and Rendering Invariants

- RDF is the source of truth for domain data, component definitions, actions,
  and layout state. The DOM is only a projection.
- Use RDF resource URIs as identities; do not introduce parallel UI identities.
- `render_object` resolves a mode binding first on the resource and then
  on its type. `render_component` evaluates the selected component's RDFHP.
- Every rendered editor-component instance lives in one DOM root with class
  `rdfop-c` and carries its rerender parameters in `data-rdfop-params`.
- A component may render subcomponents with `CALL render_object(...)` or
  `CALL render_component(...)`. Each subcomponent keeps its own `.rdfop-c` root
  and may be rerendered independently of its parent.
- Use `rdfopSwap(...)` for a local mode change or refresh. It requests fresh HTML
  from `/rdfop-render`, replaces only that component root, and mounts the new
  fragment. Do not refresh the complete canvas when a stable nested component is
  sufficient.
- Use contextual output filters (`PRINT HTML`, `PRINT JSON`, and `PRINT URL`).
  Use `PRINT RAW` only for deliberately trusted markup.
- Persist mutations before rerendering. Reloading must reconstruct committed
  application and layout state.

## Actions and Routing

- Public resource actions use `/<action>/<percent-encoded-id>`.
- Actions handled by `_dispatch_action` must be declared as
  `rdfop:<action> a rdfop:Method`; resolution is direct binding first, type
  binding second. Internal `rdfop_action(...)` uses the same dispatcher.
- `view` is an action in this URL scheme. Its HTTP handling is special only
  because it renders the complete `web/index.rdfhp` shell.
- `/rdfop-render` is the technical fragment endpoint used by the SPA; it is not
  a second public resource-routing convention.
- Exact infrastructure endpoints belong in `rdfop_routes`. Any additional
  `http_handler` layer must delegate requests it does not own.

## Layout and Drag-and-Drop

- Layout is RDF: `rdfop:children` represents containment, `rdfop:selectedNode`
  the active selector content, and `rdfop:order` stable sibling order.
- A `ComponentSelector` grants the ability to choose, replace, move, and remove
  content.
- Represent every RDF object as a navigable action URL wherever practical. Use
  real links and the shared URI payload so the same object can be opened,
  bookmarked, dragged, and dropped without a component-specific identity.
- Make object renderers useful drag sources. At minimum publish the action URL in
  `text/uri-list` and `text/plain`; add RDFOP metadata only for semantics the URI
  cannot express, such as layout-source cleanup.
- Make components useful semantic drop targets where appropriate. Examples
  include inserting content into a `Split`, opening it in a `TabGroup`, assigning
  it to a `ComponentSelector`, or selecting an RDF resource in a dropdown or
  relation field.
- A drop target must validate whether the dragged resource is meaningful for its
  slot or datatype and then persist the resulting RDF relationship. Do not treat
  drop as a DOM-only operation.
- Use the shared URI-based drag protocol. Do not invent component-specific
  payloads or confuse moving a layout reference with deleting a domain entity.
- Complete the destination mutation before cleaning a drag source.

See `docs/architecture.md` for the routing, component, layout, and drag/drop
contracts and for a minimal application example.

## Tests and Review

- Put component regression tests in RDF as `rdfop:PlaywrightTest` resources next
  to the component they exercise. A new component or RDFHP capability needs a
  focused test at that level.
- Persistence tests perform the interaction, reload, and verify the reconstructed
  state. Use generated URIs and clean fixtures in `finally`.
- Use `RDFOP_TEST_FILTER` for quick, focused development runs. RDFOP currently has
  no CI test runner, so run the complete Playwright suite locally before handing
  off a change that can affect shared behavior.
- Preserve unrelated worktree and runtime-data changes. Keep documentation in
  sync when an architectural contract intentionally changes.
