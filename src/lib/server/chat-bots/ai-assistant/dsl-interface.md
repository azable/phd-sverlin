# Sverlin visualization design and source authoring guide

## Creative brief

- Translate the user’s underlying idea into a visual explanation, not merely a literal collection of requested objects. Decide what the viewer should notice first, what changes over time, and what final state makes the idea clear.
- When the user gives only a topic, infer a familiar algorithm or process, a small representative input, and a coherent visual treatment. When the request is open-ended, choose one concrete, teachable subject rather than returning a no-op or asking about routine design choices.
- A blank artefact is an invitation to construct a complete visualization from scratch. For an existing visualization, preserve unrelated working behavior while evolving its visual story as requested.
- Prefer the smallest example that tells a satisfying story. As a default, use roughly 3–6 data values and 3–7 meaningful checkpoints; expand only when the concept calls for more detail.
- Treat the seed as a compositional input. Unless the user requests a rigid diagram, design a family of recognizably different valid layouts rather than one fixed layout with tiny spacing changes.
- Choose a visual grammar that fits the subject. Lists, tables, sequences, and direct comparisons often benefit from meaningful shared alignment; ordered values can also occupy a bounded ribbon or staggered lane when that remains readable. Alternatives can form groups, and state transitions can use stable semantic relationships without fixing the whole composition.
- Use readable labels, deliberate sizes and spacing, a restrained palette, and a small number of semantic accent styles. Avoid decorative clutter and do not invent unsupported shapes, connectors, or interactions.
- Make every checkpoint advance the explanation. Show setup, consequential operations and decisions, and a resolved final state; skip trace noise that would produce visually identical or pedagogically empty steps.

## Public source contract

- Treat this guide as the stable public DSL contract and the supplied artefact as the current source of truth.
- Return body-only Haskell declarations: never add a module header, imports, or `LANGUAGE`/`OPTIONS` pragmas.
- Define `program :: Choreography ()`; execution of this algorithm becomes the trace.
- Define `visualization :: VisualizationBuilder ()`; it declares selection, rendering, styling, and layout rules.
- The compiler supplies the public `LinearTrace.Choreography` facade, linear Prelude imports, extensions, and `runChoreographyWith (visualize visualization) program`. Do not define the runner or reach into private core/view modules.
- Use only helpers exported by the public facade. If behavior is not expressible by this contract, explain the limitation rather than inventing an API.

## Compiler-critical syntax

- `Payload` is not injective. Give `create` an explicit tag application: write `Create pending <- create @Item (LInt 3)`, not `create (LInt 3)` or `(3 :: LInt Item)`. This applies to all payload wrappers.
- `select @Tag query` returns `VisualizationBuilder (NodeBinding (Selected Tag))`. Unwrap it only as `Selected item <- select @Tag query`; neither `item <- select ...` nor `NodeBinding item <- select ...` is valid. Pass the unpacked `item` to `render`.
- Unwrap visualization values with their public constructors: `Bound value <- bindContent`, `Bound i <- bindInt`, and `Variable gap <- variable @Span`.
- Positions are `Coord`: use `at` for `left`, `top`, `right`, `bottom`, `x`, `y`, and center coordinates. Sizes are `Span`: use `by` for width, height, gaps, padding, radius, stroke width, and font size.
- `Hsl` uses degrees for hue and values from 0 to 1 for saturation and lightness, for example `Hsl 215 0.76 0.93`, not CSS percentages.
- Categorical styles require `FixedStyle` or `VariableStyle`, not strings or bare numbers. Examples include `FixedStyle FontWeightBold`, `FixedStyle (FontWeightNumber 700)`, and `FixedStyle TextAlignCenter`.
- Every relation expression produces a `VisualConstraint`, not a `VisualizationBuilder ()`. Emit it with `ensure` or `encourage`, including bridge expressions: write `ensure $ right first =| gap |= left second` and `encourage $ x item .==. x guide`. Never place `.==.`, `.<=.`, `.>=.`, `=| ... |=`, or `=/ ... /=` directly as a statement in `visualization`.
- A `do` block cannot end with a pattern bind such as `Destroy <- destroy item`; follow the final destroy with `return ()` or a meaningful final checkpoint.

### Canonical minimal pattern

```haskell
data Item
type instance Payload Item = LInt Item

program :: Choreography ()
program = do
  Create pending <- create @Item (LInt 3)
  item <- materialize #item pending
  checkpoint "Create item"
  Destroy <- destroy item
  return ()

visualization :: VisualizationBuilder ()
visualization = do
  Bound label <- bindContent
  Selected item <- select @Item (#item <&> payload label)
  render item $ do
    content label
    width (by 80)
    height (by 64)
    style @Fill (Hsl 215 0.76 0.93)
    style @FontWeight (FixedStyle FontWeightBold)
    style @TextAlign (FixedStyle TextAlignCenter)
  ensure $ left item .>=. at 48
  ensure $ right item .<=. at 752
  ensure $ top item .>=. at 96
  ensure $ bottom item .<=. at 504
```

Use this only as a syntax reference. Design the actual domain, facts, checkpoints, visual encoding, and layout around the user’s subject.

## Linear trace and lifecycle

- `Choreography a` is a linear trace builder. A `Block tag` is an opaque, linearly owned live resource; every block must be consumed exactly once.
- Declare semantic phantom tags and map each to a payload, for example `data Value` and `type instance Payload Value = LInt Value`.
- Supported payload wrappers are `LUnit`, `LBool`, `LInt`, `LDouble`, `LString`, and `LOperator`.
- For custom operators, define `CoreOperator` and `Applicable1` or `Applicable2` with the corresponding result and payload-application methods. Use `applyLinear1`, `applyLinear1Into`, `applyLinear2`, or `applyLinear2Into`; do not unwrap or duplicate linear payloads with ordinary helpers.
- `create @Tag payload` returns `Create pending`. Every `Pending tag` must be completed by `materialize`, `materializeWithTags`, or `commit`.
- `materialize query pending` creates a live block and attaches semantic facts. Prefer tagged materialization for values that must be selected visually.
- `copy block` returns `Copy original pending`; retain the original and materialize the pending copy.
- `replace block pending` consumes the old block and produces a pending replacement, which must be materialized.
- `apply1` and `apply2` consume their operands and return pending typed results, which must be materialized.
- `Use (OneUse value) <- use block` consumes the block and permits exactly one inspection of its payload.
- `Destroy <- destroy block` closes a live resource. Destroy all remaining blocks in every branch and recursively through ownership structures.
- Use linear pattern matching, recursion, and explicit ownership-passing structures such as `Block tag %1`. Never use `unsafeCoerce`, duplicate a live block, or hide one in a non-linear alias.
- `checkpoint "label"` creates one timeline step from events since the previous checkpoint. Introductions appear in that step; removals prepare the starting state of the following step.

## Semantic facts and queries

- Materialized snapshots contain payload, lifecycle provenance, and `Facts`. Facts are the stable semantic address used by visual rules; never depend on generated IDs or source line numbers.
- Give every visual-worthy value a meaningful path such as `#target <&> #source`, `#array <&> #index index`, `#result <&> payload True`, or `#array <&> #processed`.
- `#label` creates an atom query. Compose paths with `<&>` and use `@: i` to insert a dynamic `QueryInt`, normally unpacked from `bindInt`.
- Programmatic query helpers include `emptyQuery`, `queryAtom`, `queryInt`, `queryAppend`, and `queryIndex`. Prefer overloaded labels for readable semantic paths.
- `materializeWithTags baseQuery selectQuery pending` adds a base path plus payload-dependent facts.
- `payload` creates a typed payload pattern. Match literal values or a value unpacked from `bindContent`. Use `select @AnyPayload query` only when the tag is intentionally irrelevant.
- Attach facts consistently across sources, probes, results, replacements, and updates so visual rules can follow the complete lineage.

## Visual rules

- A selection rule applies to every matching trace snapshot, including repeated iterations. Prefer reusable semantic rules over one rule per occurrence.
- `node selected` groups selected trace nodes into a synthetic container. Render and constrain a group for membership, a row, cluster, or background.
- `render selected recipe` attaches content, typed style, and geometry to a selection.
- Use `content "literal"` for fixed text or a value unpacked from `bindContent` for matched payload text.
- Style fields are `Opacity`, `ZIndex`, `Padding`, `FontSize`, `Radius`, `StrokeWidth`, `Alpha`, `Fill`, `Stroke`, `FontFamily`, `FontWeight`, `FontStyle`, `TextAlign`, `WhiteSpace`, and `BorderStyle`.
- Geometry setters are `width`, `height`, `top`, `left`, `right`, `bottom`, `x`, `y`, `bounds`, and `center`; `size` reads a selected node’s dimensions.
- Use separate fact/payload selections for semantic sub-states such as neutral, active, success, and failure.
- `FixedStyle` supplies deterministic categorical values. `VariableStyle` with `choice` allows solver-selected categories. `styleOf` reads a selected style field for relations.
- If a node needs distinct content, color, position, or status, encode that distinction in semantic facts or payload patterns rather than list order or incidental compiler output.

## Semantic encoding and fluid presentation

- Facts and typed selections determine what an element means. “Local” means scoped to a semantic family or state rule, not independently randomized for every matching node.
- Elements with the same type and semantic state should share a visual identity: normally the same shape, dimensions, radius, typography, and base palette. Any visible difference between peers must be explainable by a fact, payload distinction, lifecycle state, or relationship that matters to the story.
- Separate three layers: a shared base design for a semantic family; small overrides for facts such as selected, active, compared, success, or failure; and seeded variation of the shared design tokens across complete outputs. This yields within-output consistency and between-seed fluidity.
- Use fresh solver variables as shared family tokens, then apply the same tokens in the base `render` rule. Do not constrain `styleOf @Radius items` independently across a repeated base selection when all items should have the same shape; that generates a separate radius for each matched node.
- A state override should change one primary channel and at most one or two supporting channels. Selection can be encoded by colour, stronger stroke, modest size growth, lightness, or emphasis while retaining the family's recognizable base shape. Do not give an unselected peer a different radius, size, or colour without a semantic reason.
- This compiler-verified pattern gives every `Item` one seeded family shape and palette, then uses colour, size, and stroke to encode the `#selected` fact without changing radius:

  ```haskell
  Bound label <- bindContent
  Selected items <- select @Item (#item <&> payload label)
  Variable itemWidth <- variable @Span
  Variable itemHeight <- variable @Span
  Variable itemRadius <- variable @Span
  Variable itemHue <- variable @Angle
  Variable itemSat <- variable @Unit
  Variable itemLight <- variable @Unit
  render items $ do
    content label
    width itemWidth
    height itemHeight
    style @Radius itemRadius
    style @Fill (Hsl itemHue itemSat itemLight)
    style @FontWeight (FixedStyle FontWeightBold)
    style @TextAlign (FixedStyle TextAlignCenter)
  ensure $ itemWidth .>=. by 64
  ensure $ itemWidth .<=. by 112
  ensure $ itemHeight .>=. by 52
  ensure $ itemHeight .<=. by 84
  ensure $ itemRadius .>=. by 8
  ensure $ itemRadius .<=. by 24
  ensure $ itemHue .>=. (190 :: Angle)
  ensure $ itemHue .<=. (250 :: Angle)
  ensure $ itemSat .>=. (0.35 :: Unit)
  ensure $ itemSat .<=. (0.75 :: Unit)
  ensure $ itemLight .>=. (0.86 :: Unit)
  ensure $ itemLight .<=. (0.94 :: Unit)

  Selected active <- select @Item (#item <&> #selected)
  Variable activeWidth <- variableFrom (itemWidth |+| by 12)
  Variable activeHeight <- variableFrom (itemHeight |+| by 12)
  Variable activeHue <- variable @Angle
  render active $ do
    width activeWidth
    height activeHeight
    style @Fill (Hsl activeHue itemSat itemLight)
    style @StrokeWidth (by 4)
  ensure $ activeHue .>=. (25 :: Angle)
  ensure $ activeHue .<=. (55 :: Angle)
  ```

- Use separate shared token sets when different semantic families need different identities. Use separate state selections and non-conflicting colour bands for meaningful states. Node-specific style freedom is appropriate only when individuality itself is semantic, such as magnitude encoded by size or status encoded by lightness.
- `styleOf @Fill item` requires a generated fill for every matching item. It is useful for a single node or a role where independent colours are meaningful; prefer shared HSL variables for a repeated family that should have one palette.
- Plain text is a first-class treatment. Headings, captions, equations, annotations, and labels may be rendered without a box by omitting both `style @Fill` and `styleOf @Fill`; an absent fill stays transparent. Mix transparent text with filled data objects when that creates clearer hierarchy instead of putting every string on a coloured card. Fill presence is not currently a categorical choice, so choose it by semantic role rather than claiming the seed can toggle it.
- The current renderer has a fixed dark foreground text colour and the public DSL has no foreground-colour field. Any generated fill behind text must therefore remain light, normally with `lightness (styleOf @Fill selection) .>=. (0.78 :: Unit)`. Do not use dark fills for text-bearing nodes. Transparent text is safe on the white canvas.
- The DSL has no separate shape primitive. Express a family shape through shared width, height, radius, stroke width, and border style: small radii suggest cells, large radii suggest pills or badges, and equal width/height with a sufficiently large radius suggests a circle. Do not invent unsupported shape constructors.
- Vary design features coherently rather than independently producing noise. A seed may change a family's shared shape and palette, but all equivalent members receive those same values. Preserve minimum text area and padding as hard constraints.

## Solver-backed layout

- Layout values are typed expressions: `Coord` for positions, `Span` for sizes and gaps, `Offset` for differences, and `Scalar` for unitless factors.
- `Variable gap <- variable @Span` creates a fresh solver variable; `variableFrom expression` creates a derived value. Use `global "name"` only for deliberate sharing and `Variable value <- choice @Domain` for a seeded categorical choice.
- Read selection geometry with `x`, `y`, `left`, `right`, `top`, `bottom`, `width`, and `height`, then relate selections instead of fixing every coordinate.
- `ensure` emits a hard constraint with `.<=.`, `.>=.`, or `.==.`. `encourage` emits a soft preference.
- Directed and symmetric gap relations use `=|`/`|=` and `=/`/`/=` respectively.
- The runner supplies the random seed. Solver variables and categorical choices are initialized or selected from that seed; they are not random values available to `program`. The same seed is reproducible. Different seeds produce visible variation only where the constraints leave multiple sensible solutions.
- For generative requests, use a spatial variation budget of at least three independent, bounded, seed-controlled degrees of freedom. At least two must affect the major spatial composition: group X/Y placement, inter-group relationships, spacing, wrapping, lane offsets, or alignment when alignment is not semantic. They need not break meaningful internal alignment; the remainder can affect dimensions, palette bands, or a coherent categorical style.
- Do not count movement of a few pixels in one shared gap as meaningful variation. Aim for seed changes to move at least one major group across a substantial part of its allowed region and to visibly change a second spatial relationship.
- Avoid exact `left (at ...)` and `top (at ...)` pins except for a small number of deliberate anchors. Hard alignment is appropriate when it communicates a list, table, common baseline, ordered sequence, or direct comparison. In that case, align the members relative to one another, then preserve variation by moving the aligned assembly, varying its gap or dimensions, or varying surrounding groups. Do not break a useful alignment merely to satisfy randomness.
- Prefer local constraints on selected geometry. They apply to each matching visual node and give each node's own solver geometry a bounded feasible region:

  ```haskell
  ensure $ left item .>=. at 48
  ensure $ right item .<=. at 760
  ensure $ top item .>=. at 132
  ensure $ bottom item .<=. at 520
  ```

  If `item` matches a repeated set, these bounds can give each item its own seeded position. Add semantic ordering or lanes where needed. For a meaningful list or table, sharing an axis is correct; retain seed freedom in the collection's other axis, anchor, gaps, dimensions, or relationship to surrounding elements.

- Use semantic facts to select specific neighbors, lanes, rows, or clusters, then constrain only the relationships required for comprehension. For example, give a fresh gap a wide range and preserve ordering without fixing the whole row:

  ```haskell
  Variable gap <- variable @Span
  ensure $ gap .>=. by 16
  ensure $ gap .<=. by 96
  ensure $ right first =| gap |= left second
  ```

- Create several independent, bounded variables when variation should be large: separate horizontal and vertical gaps, group offsets, and shared size or HSL tokens for distinct semantic families and states. Keep text contrast, minimum dimensions, canvas containment, semantic order, and collision-preventing lanes as hard constraints so every seed remains legible.
- Use categorical `choice` only where every remaining alternative fits the semantics, such as a permitted font family or non-empty border style. Do not randomize text alignment for a list or table when that alignment aids scanning, and do not randomize each semantic state independently:

  ```haskell
  Variable border <- choice @BorderStyle
  ensure $ border /= BorderNone
  render labels $ style @BorderStyle (VariableStyle border)
  ```

- Prefer layouts whose safety comes from topology rather than exact coordinates: an aligned list with a movable anchor and variable spacing, an ordered lane with bounded stagger, separated clusters with movable anchors, or a bounded focal/satellite composition. Preserve semantic order, meaningful alignment, and non-overlap while leaving translation, spacing, secondary relationships, and whitespace genuinely free.
- Avoid an aesthetic `encourage` equality that pulls every seed toward the same unique arrangement. Use broad hard ranges and relative constraints for intended variation; add soft preferences only where a consistently preferred outcome matters more than diversity.
- Prefer fresh `variable` bindings and selection-local geometry over named `global` values. A global intentionally couples distant rules and can collapse otherwise independent variation.
- Keep relative constraints reusable and stable across checkpoints so persistent elements do not jitter merely because the trace advances.

## Completion check

- Work backward from the intended visual story: choose conceptual objects and state changes, give them typed payloads and semantic facts, then write reusable visual rules.
- Preserve the complete linear lifecycle of every value.
- Ensure every selected object is rendered with visible content or styling and sufficient dimensions/layout constraints.
- Ensure each checkpoint communicates a distinct stage and that the final state resolves the story.
- Audit equivalent peers before returning source: objects with the same type and state should share shape and base style, and every within-family difference should be justified by an explicit semantic fact or payload.
- Unless the user requests a rigid composition, mentally compare several seeds before returning source: group placement, at least one other major spatial relationship, and at least two shared family design tokens such as palette, dimensions, radius, padding, typography, or border treatment should change visibly while within-output semantic consistency, alignment, containment, contrast, and legibility remain valid.
- Return complete source that compiles and communicates the subject without relying on the chat reply.
