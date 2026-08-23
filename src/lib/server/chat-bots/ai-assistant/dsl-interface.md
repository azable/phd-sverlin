# Sverlin visualization design and source authoring guide

## Creative brief

- Translate the user’s underlying idea into a visual explanation, not merely a literal collection of requested objects. Decide what the viewer should notice first, what changes over time, and what final state makes the idea clear.
- When the user gives only a topic, infer a familiar algorithm or process and a small representative input. Leave routine style fields open for the compiler’s coherent seeded profiles; choose concrete styling only when the user or semantic encoding requires it.
- A blank artefact is an invitation to construct a complete visualization from scratch. For an existing visualization, preserve unrelated working behavior while evolving its visual story as requested.
- Prefer the smallest example that tells a satisfying story. As a default, use roughly 3–6 data values and 3–7 meaningful checkpoints; expand only when the concept calls for more detail.
- Treat the seed as a compositional input. Unless the user requests a rigid diagram, design a family of recognizably different valid layouts rather than one fixed layout with tiny spacing changes.
- Choose a visual grammar that fits the subject. Lists, tables, sequences, and direct comparisons often benefit from meaningful shared alignment; ordered values can also occupy a bounded ribbon or staggered lane when that remains readable. Alternatives can form groups, and state transitions can use stable semantic relationships without fixing the whole composition.
- Use readable labels and deliberate sizes and spacing. Encode semantic accents explicitly, but leave unspecified presentation to the compiler. Avoid decorative clutter and do not invent unsupported shapes, connectors, or interactions.
- Make every checkpoint advance the explanation. Show setup, consequential operations and decisions, and a resolved final state; skip trace noise that would produce visually identical or pedagogically empty steps.

## Public source contract

- Treat the source-derived `dslApiIndex` as the exhaustive public-name, compiler-inferred type, and per-symbol behavior reference. It combines GHC signatures with Haddock export documentation from the `LinearTrace.Choreography` facade; do not infer additional APIs from examples or private modules.
- Treat this guide as the stable composition and authoring contract and the supplied artefact as the current project source of truth. Where this guide adds syntax constraints or examples, they refine rather than expand the facade API.
- Return body-only Haskell declarations: never add a module header, imports, or `LANGUAGE`/`OPTIONS` pragmas.
- Define `program :: Choreography ()`; execution of this algorithm becomes the trace.
- Define `visualization :: VisualizationBuilder ()`; it declares selections, hierarchical nodes, styling, and layout rules.
- The compiler supplies the public `LinearTrace.Choreography` facade, linear Prelude imports, extensions, and a generated runner that enables coherent generative styles. Do not define the runner or reach into private core/view modules.
- Use only helpers exported by the public facade. If behavior is not expressible by this contract, explain the limitation rather than inventing an API.

## Compiler-critical syntax

- `Payload` is not injective. Give `create` an explicit tag application: write `Create pending <- create @Item (LInt 3)`, not `create (LInt 3)` or `(3 :: LInt Item)`. This applies to all payload wrappers.
- `select @Tag query` returns `VisualizationBuilder (NodeBinding (Selected Tag))`. Unwrap it only as `Selected item <- select @Tag query`; neither `item <- select ...` nor `NodeBinding item <- select ...` is valid. Pass the unpacked selection to `node`.
- Unwrap visualization values with their public constructors: `Bound value <- bindContent`, `Bound i <- bindInt`, and `Variable gap <- variable @Span`.
- Positions are `Coord`: use `at` for `left`, `top`, `right`, `bottom`, `x`, `y`, and center coordinates. Sizes are `Span`: use `by` for width, height, gaps, padding, radius, stroke width, and font size.
- `Hsl` uses degrees for hue and values from 0 to 1 for saturation and lightness, for example `Hsl 215 0.76 0.93`, not CSS percentages.
- Categorical styles require `FixedStyle` or `VariableStyle`, not strings or bare numbers. Examples include `FixedStyle FontWeightBold`, `FixedStyle (FontWeightNumber 700)`, and `FixedStyle TextAlignCenter`.
- The compiler, not the browser, chooses text lines and measures the solved content box. With `content`, an authored `style @FontSize` is fixed. With `fitText`, an omitted `FontSize` means the largest feasible fit and an authored `FontSize` is a cap.
- Style authoring has three states. `style @Field value` requires a field, `withoutStyle @Field` requires its absence, and omission leaves it to the compiler’s family profile. Do not add `Fill`, `Radius`, `StrokeWidth`, or typography merely to create seeded variation.
- `styleFamily "key"` gives selected peers one explicit family identity when payload type alone is too broad. `styleCase @Field choice` exhaustively maps a typed categorical choice to `Just value` or `Nothing` for authored conditional presence.
- Every relation expression produces a `VisualConstraint`, not a `VisualizationBuilder ()`. Emit it with `ensure` or `encourage`, including bridge expressions: write `ensure $ right first =| gap |= left second` and `encourage $ x item .==. x guide`. Never place `.==.`, `.<=.`, `.>=.`, `=| ... |=`, or `=/ ... /=` directly as a statement in `visualization`.
- `oneOf` is the deliberate exception: each `alternative` takes a list of raw `VisualConstraint` values, without `ensure`. Write `oneOf "composition" (alternative "row" [y first .==. y second]) [alternative "column" [x first .==. x second]]`. Alternative constraints are always hard.
- A `do` block cannot end with a pattern bind such as `Destroy <- destroy item`; follow the final destroy with `return ()` or a meaningful final checkpoint.

## Value-first computation

- `create` is the ingress boundary. Use it to introduce external/source inputs, literal constants, operator values, and genuine prose annotations. Never use it to introduce a domain value that is semantically derived from values already present in the trace.
- A meaningful unary or binary derivation must be performed by a typed operator: define `LOperator`, `CoreOperator`, and `Applicable1` or `Applicable2`, then execute it with `apply1` or `apply2`. The returned pending value is the result; materialize it with result facts and introduce its checkpoint there.
- An algorithmic source is incomplete when it precomputes its results in Haskell and passes them to `create`, or when its only account of the computation is fixed text. In a Fibonacci visualization, only the initial `0` and `1` are input values; every later term must be produced by applying addition to owned copies of the preceding terms. Strings such as `"1 + 1 = 2"` may annotate those events only after the corresponding values and application exist in the trace.
- `apply1` and `apply2` consume the operator and their operands. If an input or result must remain available, `copy` it first, materialize or `commit` the pending copy, and consume the appropriate owned copy. Create and materialize a fresh operator value for each repeated application because operators are also consumed.
- Attach facts that distinguish inputs, operators, and results, then render payload-bound values from those facts. Text is appropriate for headings, short narration, and symbols; it must not carry computational meaning that should be present in the typed trace.
- Do not manufacture operators for purely descriptive concepts with no meaningful value transformation. Algorithms based on movement, grouping, replacement, or lifecycle should encode those actual operations instead of forcing arithmetic into the story.

### Canonical value-flow pattern

```haskell
data Addition = Addition
type instance Payload Addition = LOperator Addition Addition

instance CoreOperator Addition where
  operatorPayloadText Addition = "+"
  persistOperatorPayload Addition = Ur Addition

data Number
type instance Payload Number = LInt Number

instance Applicable2 Addition Number Number where
  type Apply2Result Addition Number Number = Number
  applyPayload2 (LOperator Addition) = applyLinear2Into (Linear.+)

program :: Choreography ()
program = do
  Create pendingLeft <- create @Number (LInt 1)
  leftInput <- materialize (#number <&> #input <&> #left) pendingLeft
  Create pendingRight <- create @Number (LInt 1)
  rightInput <- materialize (#number <&> #input <&> #right) pendingRight
  Create pendingAddition <- create @Addition (LOperator Addition)
  addition <- materialize #operator pendingAddition
  checkpoint "Introduce inputs"

  Apply2 pendingResult <- apply2 addition leftInput rightInput
  result <- materialize (#number <&> #result) pendingResult
  checkpoint "Apply addition"

  Destroy <- destroy result
  return ()

visualization :: VisualizationBuilder ()
visualization = do
  Bound label <- bindContent
  Selected numbers <- select @Number (#number <&> payload label)
  node numbers $ do
    content label
    width (by 72)
    height (by 56)
  ensure $ left numbers .>=. at 48
  ensure $ right numbers .<=. at 752
  ensure $ top numbers .>=. at 120
  ensure $ bottom numbers .<=. at 480

  Selected addition <- select @Addition #operator
  node addition $ do
    content "+"
    width (by 48)
    height (by 48)
    style @FontSize (by 24)
    style @FontWeight (FixedStyle FontWeightBold)
    style @TextAlign (FixedStyle TextAlignCenter)
  ensure $ left addition .>=. at 48
  ensure $ right addition .<=. at 752
  ensure $ top addition .>=. at 120
  ensure $ bottom addition .<=. at 480
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
- `node selected $ do ...` declares every trace output matched by a selection and attaches content, box geometry, style, and constraints. Each materialized trace output must match exactly one such declaration: unmatched outputs are not visual nodes, while overlapping declarations are a compile error.
- `Selected parent <- node $ do ...` declares an anonymous generated node. Any `node` declarations nested in that `do` block become its children; nesting can be recursive. A trace-selected node is terminal and cannot contain children. A selection may match one or many trace outputs, so an entire selection can be nested without enumerating its members.
- Every node has one parent: either the canvas or one generated node. Empty generated branches are pruned. The compiler emits warning findings when a declaration matches no visible trace output or a generated parent is pruned.
- Generated parents are ordinary selectable node handles. Bind the result and use `left`, `right`, `center`, `size`, `styleOf`, and other relations on it just as on a trace selection. Inside an anonymous node, `Selected current <- self` retrieves the same handle; `canvas` is the ordinary root-layout handle.
- Generated parents default to `Hug` on each axis: their content edge is tight to at least one child edge while containing every child margin box. Use `contentFit Horizontal Contain`, `contentFit Vertical Contain`, or `contentFit Both Contain` when a parent may be larger than its children.
- `padding` and `margin` use a real four-edge box model. Construct insets with `uniform span`, `symmetric vertical horizontal`, or `edges top right bottom left`. Parent containment uses the content box inside padding; child margins remain separate and never collapse.
- Parent-relative setters are explicit and affine: `xAt (percent 50)` and `yAt (percent 50)` place the node center at the midpoint of its parent content box; `widthOf (percent 60)` and `heightOf (percent 40)` size it from that content box. Percent values are in the inclusive range 0–100. These work for children and for canvas children.
- Use `content "literal"` for fixed text or a value unpacked from `bindContent` for matched payload text.
- `content value` uses managed typography and prefers one line, with at most two compiler-selected fallback breaks. When its `FontSize` is omitted, the automatic profile selects a proportional size after geometry is solved; an authored `FontSize` is fixed. `fitText value` instead maximizes the feasible size when `FontSize` is omitted, or treats an authored size as a cap. Automatic fitting uses 0.25 px steps with a 12 px physical minimum. Always provide adequate width and height; no feasible layout is a compile error.
- For exact code or other verbatim output, start with `codeContent value`. Wrap it with `codeWrap` only when up to two compiler-selected visual breaks are acceptable, and wrap that with `highlightCode "language"` for semantic syntax tokens. For example:

  ```haskell
  node example $ do
    emphasizeCode
      "computed"
      [codeRange 4 10]
      (highlightCode
        "haskell"
        (codeWrap
          (codeContent "let answer = 40 + 2\n-- computed result")))
    width (by 280)
    height (by 96)
    style @TextAlign (FixedStyle TextAlignLeft)
  ```

  `emphasizeCode "checkpoint" [codeRange start end] recipe` adds emphasis only when the selected node is visible at a checkpoint with that exact label. Ranges are half-open, zero-based Unicode character offsets in the authored source; the compiler converts them to UTF-8 byte ranges, merges overlap, and rejects invalid or invisible schedules. Emphasis is separate from syntax roles, so do not rewrite highlighted tokens to simulate it. Supported highlighting aliases cover `sverlin`/`haskell`/`hs`, JavaScript/TypeScript and common C-like languages, Python/shell, JSON, CSS, and SQL. Code defaults to the managed non-ligature JetBrains Mono face. Do not simulate code with ordinary wrapped prose.

- Managed font choices are `FontInter`, `FontSystem` (pinned Source Sans 3), `FontMono` (pinned JetBrains Mono NL), `FontSerif` (pinned Source Serif 4), `FontSourceSans3`, `FontAtkinsonHyperlegibleNext`, `FontSpaceGrotesk`, `FontSourceSerif4`, `FontLiterata`, `FontJetBrainsMonoNL`, and `FontIBMPlexMono`.
- Style fields are `Opacity`, `ZIndex`, `FontSize`, `Radius`, `StrokeWidth`, `Alpha`, `Fill`, `Stroke`, `FontFamily`, `FontWeight`, `FontStyle`, `TextAlign`, `WhiteSpace`, and `BorderStyle`. Padding and margin are box declarations, not styles.
- Treat an explicitly requested border as one composite visual property. Set a positive `StrokeWidth`, a contrasting `Stroke`, and a deterministic non-empty `BorderStyle`, normally `FixedStyle BorderSolid`. Do not claim a border was added after changing only its width, and do not rely on renderer fallbacks or automatic profiles for an explicit request; `BorderNone` always suppresses the border.
- Absolute geometry setters are `width`, `height`, `top`, `left`, `right`, `bottom`, `x`, `y`, `bounds`, and `center`; `size` reads a selected node’s dimensions. Prefer parent-relative setters for hierarchical composition when percentages express the intent directly.
- Use separate fact/payload selections for semantic sub-states such as neutral, active, success, and failure.
- `FixedStyle` supplies deterministic categorical values. `VariableStyle` with `choice` allows solver-selected categories. `styleOf` reads a selected style field for relations.
- If a node needs distinct content, color, position, or status, encode that distinction in semantic facts or payload patterns rather than list order or incidental compiler output.

## Semantic encoding and fluid presentation

- Facts and typed selections determine what an element means. “Local” means scoped to a semantic family or state rule, not independently randomized for every matching node.
- The body-only runner assigns trace leaves a semantic family by payload type. Leaf families share surface, weight, palette, and fitted-size decisions, so peers remain coherent within an output while seeds can produce different treatments. Generated structural parents remain transparent unless their node body explicitly styles them.
- Unspecified leaves make balanced choices: one exact managed font face and one text occupancy target are global to the output; surface treatment and weight are per semantic family. Font faces sample equally across all eight managed faces, occupancy across 68%, 78%, 86%, and 94% of the maximum feasible size, surfaces across transparent, outline, flat fill, soft card, and pill treatments, and weights across 400, 500, and 600. These are compiler defaults, not APIs to reproduce manually, and they do not infer a semantic role from payload text or names.
- Let unspecified presentation use those defaults. Choose a font, weight, alignment, surface, or colour only when the user asks for it or the choice actually communicates a semantic distinction—for example, managed monospace for code or left alignment for a scannable table. Do not make a numeric list “technical,” a heading “editorial,” or each state visually different merely to add variety.
- Styles declared on an anonymous parent cascade through all descendants unless a child overrides them, but only for semantic text properties: `FontFamily`, `FontWeight`, `FontStyle`, `FontSize`, `TextAlign`, `WhiteSpace`, and `styleFamily`. Surface properties such as fill, stroke, radius, opacity, and z-index stay local to the node that declares them.
- Use `styleFamily "name"` when one payload type has multiple semantic roles that should vary independently. Apply the same explicit key to peers that should share a family.
- `style @Field value` is a hard authoring requirement and overrides the default for that field. `withoutStyle @Field` is also hard and keeps the field absent for every seed. Omitted fields remain available to the family profile.
- Plain text that must remain unboxed should explicitly forbid fill and border width instead of relying on omission:

  ```haskell
  node caption $ do
    content "Current comparison"
    withoutStyle @Fill
    withoutStyle @StrokeWidth
  ```

- Use `styleCase` only when the requested design itself needs a custom categorical treatment. It is exhaustive and the controlling choice is shared wherever the same choice is reused:

  ```haskell
  data Treatment = Typographic | Highlighted

  instance ChoiceDomain Treatment where
    choiceDomain = [Typographic, Highlighted]
    choiceToken treatment =
      case treatment of
        Typographic -> "typographic"
        Highlighted -> "highlighted"

  Variable treatment <- choice @Treatment
  node items $ do
    styleCase @Fill treatment $ \candidate ->
      case candidate of
        Typographic -> Nothing
        Highlighted -> Just (Hsl 210 0.5 0.9)
    styleCase @Radius treatment $ \candidate ->
      case candidate of
        Typographic -> Nothing
        Highlighted -> Just (by 12)
  ```

- Every candidate supplied to `styleCase` is compiled, but only the selected branch is emitted into the solved IR. Do not use unconditional `styleOf` on a field authored with `styleCase` or `withoutStyle`; `styleOf` requires guaranteed presence and compilation rejects that conflict.
- A state override should change one primary channel and at most one or two supporting channels. Use explicit styling only when a fact such as selected, active, compared, success, or failure must remain visible across every seed.
- `styleOf @Fill item` makes fill required for every matching item. Use it only when a hard relation must read that field; do not use `styleOf` merely to introduce random styling.
- The current renderer has a fixed dark foreground text colour and the public DSL has no foreground-colour field. Any generated fill behind text must therefore remain light, normally with `lightness (styleOf @Fill selection) .>=. (0.78 :: Unit)`. Do not use dark fills for text-bearing nodes. Transparent text is safe on the white canvas.
- The DSL has no separate shape primitive. Express a family shape through shared width, height, radius, stroke width, and border style: small radii suggest cells, large radii suggest pills or badges, and equal width/height with a sufficiently large radius suggests a circle. Do not invent unsupported shape constructors.
- Preserve enough width and height for every valid profile; automatic padding and typography do not replace legibility and containment constraints. Typography reads and then pins the solved box, padding, and stroke inputs, so it cannot enlarge a box during the second solve to rescue weak geometry.
- Compiler findings retain reductions to small text, fallback wrapping, and substituted static weights. Avoid forcing small boxes merely because fitting can make a candidate compile.

## Solver-backed layout

- Layout values are typed expressions: `Coord` for positions, `Span` for sizes and gaps, `Offset` for differences, and `Scalar` for unitless factors.
- `Variable gap <- variable @Span` creates a fresh solver variable; `variableFrom expression` creates a derived value. Use `global "name"` only for deliberate sharing and `Variable value <- choice @Domain` for a seeded categorical choice.
- Read selection geometry with `x`, `y`, `left`, `right`, `top`, `bottom`, `width`, and `height`, then relate selections instead of fixing every coordinate.
- For a repeated list, table, sequence, or set of numbers, allocate a reasonable bounded canvas lane first. Use the known item count to choose or constrain shared cell dimensions and gaps so the collection occupies that lane without overlap; more items should imply smaller cells. Leave `FontSize` unspecified or use uncapped `fitText` so typography follows those solved boxes instead of trial-and-error size edits. The DSL has no runtime selection-count primitive, so derive count-dependent constants from the source structure when the count is statically known.
- `ensure` emits a hard constraint with `.<=.`, `.>=.`, or `.==.`. `encourage` emits a soft preference.
- Directed and symmetric gap relations use `=|`/`|=` and `=/`/`/=` respectively.
- Use `oneOf name firstAlternative remainingAlternatives` when two or more substantially different compositions are all semantically valid. Names and alternative labels must be stable and descriptive. Put minimum semantic, containment, ordering, and readability constraints outside the alternatives; put only the relationships that distinguish each composition inside them. The solver balances feasible named alternatives before sampling continuous geometry:

  ```haskell
  Variable gap <- variable @Span
  ensure $ gap .>=. by 20
  ensure $ gap .<=. by 72
  oneOf
    "comparison.composition"
    (alternative
       "row"
       [right source =| gap |= left result, y source .==. y result])
    [ alternative
        "column"
        [bottom source =| gap |= top result, x source .==. x result]
    ]
  ```

- `caseOf choice $ \value -> ...` is the exhaustive typed form when an existing finite choice also determines numeric layout constraints. Pattern-match every constructor and return a list of `VisualConstraint` values. Define categorical equality/difference constraints globally; conditional alternatives currently accept numeric visual relations only.
- Do not imitate a discrete composition with a continuous selector, magic numeric thresholds, or mutually contradictory soft constraints. Use `oneOf` so infeasible alternatives can be rejected explicitly and the chosen branch is retained in visualization provenance.
- The runner supplies the random seed; it is not a random value available to `program`. The same seed is reproducible. Bounded affine hard constraints are sampled across their feasible region instead of optimized toward one preferred point, and categorical choices are sampled uniformly from satisfying alternatives. Different seeds therefore explore freedom that the hard constraints genuinely leave open.
- Keep a generative numeric problem on that sampling path when practical: use variables, constants, addition/subtraction, and multiplication or division by constants in hard constraints, and give every independent value finite lower and upper bounds. Variable-by-variable multiplication/division, `absExpr`, `minExpr`, `maxExpr`, cyclic equality, or an unbounded value selects the nonlinear penalty fallback and can make seeds converge on similar results.
- On the bounded affine path, `encourage` and `minimize` are deliberately ignored: they describe attraction toward an optimum, which conflicts with broad exploration. Express the user's minimum requirements, semantic relationships, containment, contrast, and legibility with `ensure`, then leave all other values free inside broad hard ranges. Exact hard equalities remain valid but reduce the dimension available for variation.
- Hard constraints must have a non-empty common region. Check fixed widths/heights against containment, accumulated row gaps against canvas width, and shared-variable ranges against every use; the compiler rejects contradictions instead of weakening one of the requirements.
- For generative requests, use at least two independent, bounded, seed-controlled degrees of freedom that affect major spatial composition: parent-node X/Y placement, relationships between parent nodes, spacing, wrapping, lane offsets, or alignment when alignment is not semantic. The automatic family profile supplies routine style variation; do not duplicate it with authored style variables.
- Do not count movement of a few pixels in one shared gap as meaningful variation. Aim for seed changes to move at least one major parent node across a substantial part of its allowed region and to visibly change a second spatial relationship.
- Avoid exact `left (at ...)` and `top (at ...)` pins except for a small number of deliberate anchors. Hard alignment is appropriate when it communicates a list, table, common baseline, ordered sequence, or direct comparison. In that case, align the members relative to one another, then preserve variation by moving the aligned assembly, varying its gap or dimensions, or varying surrounding parent nodes. Do not break a useful alignment merely to satisfy randomness.
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

- Create several independent, bounded variables when layout variation should be large: separate horizontal and vertical gaps, parent-node offsets, and shared sizes. Add HSL or other style variables only for a semantic or explicit user requirement. Keep minimum dimensions, canvas containment, semantic order, and collision-preventing lanes as hard constraints so every seed remains legible.
- Use categorical `choice` only where every remaining alternative fits the semantics, such as a permitted font family or non-empty border style. Do not randomize text alignment for a list or table when that alignment aids scanning, and do not randomize each semantic state independently:

  ```haskell
  Variable border <- choice @BorderStyle
  ensure $ border /= BorderNone
  node labels $ style @BorderStyle (VariableStyle border)
  ```

- Prefer layouts whose safety comes from topology rather than exact coordinates: an aligned list with a movable anchor and variable spacing, an ordered lane with bounded stagger, separated clusters with movable anchors, or a bounded focal/satellite composition. Preserve semantic order, meaningful alignment, and non-overlap while leaving translation, spacing, secondary relationships, and whitespace genuinely free.
- Do not rely on an aesthetic `encourage` equality to shape a generative affine layout; it is ignored so the feasible space remains exploratory. Use broad hard ranges and relative constraints for intended variation. Soft preferences matter only after the problem requires nonlinear/cyclic/unbounded optimizer fallback, where they can pull every seed toward the same arrangement.
- Prefer fresh `variable` bindings and selection-local geometry over named `global` values. A global intentionally couples distant rules and can collapse otherwise independent variation.
- Keep relative constraints reusable and stable across checkpoints so persistent elements do not jitter merely because the trace advances.

## Completion check

- Work backward from the intended visual story: choose conceptual objects and state changes, give them typed payloads and semantic facts, then write reusable visual rules.
- Audit every `create` whose payload is a domain value: it must be an external/source input or literal constant, never a result obtainable from live values. Rewrite any violation as `apply1`, `apply2`, or the corresponding lifecycle operation. An algorithmic visualization with derived values but no matching operation events is not complete.
- Preserve the complete linear lifecycle of every value.
- Ensure every selected object is rendered with visible content or styling and sufficient dimensions/layout constraints.
- Audit every text-bearing box at its longest expected value. Prefer more space or an intentional `codeWrap`/`fitText` policy over relying on minimum-size output.
- For an explicitly requested visual property, audit its complete rendering dependencies before returning source. In particular, requested borders must have a positive width, a contrasting stroke colour, and a non-empty border style on every intended semantic selection.
- Ensure each checkpoint communicates a distinct stage and that the final state resolves the story.
- Audit equivalent peers before returning source: use payload-type family inference by default, add `styleFamily` only when one type has distinct roles, and justify every explicit within-family override with a semantic fact or payload.
- Unless the user requests a rigid composition, preserve meaningful bounded freedom in at least two major spatial relationships and leave routine style fields unspecified for seeded family sampling.
- Return complete source that compiles and communicates the subject without relying on the chat reply.
