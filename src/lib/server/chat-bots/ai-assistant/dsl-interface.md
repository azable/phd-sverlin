# Sverlin visualization design and source authoring guide

## Creative brief

- Translate the user’s underlying idea into a visual explanation, not merely a literal collection of requested objects. Decide what the viewer should notice first, what changes over time, and what final state makes the idea clear.
- When the user gives only a topic, infer a familiar algorithm or process, a small representative input, and a coherent visual treatment. When the request is open-ended, choose one concrete, teachable subject rather than returning a no-op or asking about routine design choices.
- A blank artefact is an invitation to construct a complete visualization from scratch. For an existing visualization, preserve unrelated working behavior while evolving its visual story as requested.
- Prefer the smallest example that tells a satisfying story. As a default, use roughly 3–6 data values and 3–7 meaningful checkpoints; expand only when the concept calls for more detail.
- Choose a visual grammar that fits the subject: ordered values can form a row, comparisons can emphasize a focused pair, alternatives can form groups, and state transitions can use stable position with changes in content, color, or emphasis.
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
    left (at 72)
    top (at 120)
    width (by 80)
    height (by 64)
    style @Fill (Hsl 215 0.76 0.93)
    style @FontWeight (FixedStyle FontWeightBold)
    style @TextAlign (FixedStyle TextAlignCenter)
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

## Solver-backed layout

- Layout values are typed expressions: `Coord` for positions, `Span` for sizes and gaps, `Offset` for differences, and `Scalar` for unitless factors.
- `variable @Span` creates a solver variable; `variableFrom expression` creates a derived value. Use `global "name"` only for deliberate sharing and `choice @Domain` for categorical choices.
- Read selection geometry with `x`, `y`, `left`, `right`, `top`, `bottom`, `width`, and `height`, then relate selections instead of fixing every coordinate.
- `ensure` emits a hard constraint with `.<=.`, `.>=.`, or `.==.`. `encourage` emits a soft preference.
- Directed and symmetric gap relations use `=|`/`|=` and `=/`/`/=` respectively.
- Keep constraints relative and reusable. Bound dimensions sensibly and reserve soft preferences for aesthetics.

## Completion check

- Work backward from the intended visual story: choose conceptual objects and state changes, give them typed payloads and semantic facts, then write reusable visual rules.
- Preserve the complete linear lifecycle of every value.
- Ensure every selected object is rendered with visible content or styling and sufficient dimensions/layout constraints.
- Ensure each checkpoint communicates a distinct stage and that the final state resolves the story.
- Return complete source that compiles and communicates the subject without relying on the chat reply.
