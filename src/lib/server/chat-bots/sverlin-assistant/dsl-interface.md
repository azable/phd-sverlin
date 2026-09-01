# Sverlin source authoring guide

## Authoring brief

- Turn the participant's algorithm, audience, learning outcomes, and style answers into one clear visual explanation. Use the audience to choose terminology and detail, not to guess an aesthetic.
- Prefer a small representative scenario: usually 3–6 values and 3–7 meaningful typed steps. Each exposed step should visibly advance the explanation.
- Preserve design freedom where the brief is silent. Encode semantic requirements and explicit preferences; leave routine appearance open.
- Treat a seed as a request for another valid presentation, not merely tiny spacing changes. Give major groups room to move and use named alternatives for genuinely different compositions.
- The application owns playback and controls. Do not draw substitute navigation, tabs, preference controls, or interactions inside the visualization.

## Complete public source contract

- `dslApiIndex` is the exhaustive public-name, compiler-inferred type, and per-symbol behavior reference. It is generated from the `Sverlin` facade. Do not infer APIs from private modules or old examples.
- Return body-only Haskell declarations. Do not add a module header, imports, language pragmas, a runner, or seed handling.
- Define exactly these three entry points:

  ```haskell
  domain  :: Domain Initial
  program :: Initial %1 -> Program ()
  render  :: Render ()
  ```

- `Domain` declares typed vocabulary, samples bounded scenario input, and constructs the initial linear resources. `Program` consumes those resources to record one immutable semantic trace. `Render` independently selects trace objects and relations and describes their visual mappings.
- The wrapper supplies the curated linear prelude, qualified `Linear` operations for payload implementations, and `Sverlin` as the sole DSL facade.
- `do` notation is ordinary GHC-checked `RebindableSyntax`; there is no source-rewriting pass. Generator and Render values bind normally, while Domain and Program bindings are linear.
- Do not expose or emulate an unrestricted escape from Domain or Program. Runtime input, payloads, `Block`, `Pending`, `Slot`, and structures containing them must be consumed exactly once.

## Minimal shape

```haskell
data Number
instance Traceable Number where
  type Payload Number = LInt Number

data ValueRole
data InputVariable
data Introduce
data Finish

valueKind :: Kind Number
valueKind = kind @ValueRole

data Initial where
  Initial :: Block Number %1 -> Initial

domain :: Domain Initial
domain = do
  declareKind valueKind
  declareSteps @'[Introduce, Finish]
  value <- variable @InputVariable (between 0 99)
  Create pending <- create (LInt value)
  block <- materialize valueKind pending
  pure (Initial block)

program :: Initial %1 -> Program ()
program (Initial block) = do
  block1 <- step @Introduce (pure block)
  block2 <- step @Finish (pure block1)
  Destroy <- destroy block2
  pure ()

render :: Render ()
render = do
  always $ frame @Introduce
  always $ frame @Finish
  values <- select valueKind
  node values $ do
    label <- bindContent
    fitText label
    width (by 72)
    height (by 52)
    style @Radius (by 10)
```

Use this only as a syntax reference. Choose types, steps, relations, and visual rules for the actual subject.

## Domain: typed input and vocabulary

- A nullary marker type is a stable compiler identity; it is not runtime data or a string key. Use a different marker for every kind, relation, generated variable, and step declaration.
- `kind @Identity` classifies one `Traceable` type. Declare every handle with `declareKind` before materializing a pending value with it. Several kinds may classify the same payload type when they have different semantic roles.
- `orderedRelation @Identity` gives source and target distinct roles. `symmetricRelation @Identity` makes reversing same-typed endpoints equivalent. Declare either with `declareRelation`.
- `declareSteps @'[...]` declares every marker later used by `step`, `frame`, `fragment`, or `fragmentMany`.
- Domain-form `variable @Identity generator` samples once from a deterministic sub-seed. Use `between`, `elementOf`, `weighted`, `listOf`, and `shuffle` to construct valid finite input directly.
- `listOf` returns an ordinary Haskell list while inside Generator. After Domain binds that list, the list is linear: consume every constructor and element while creating the initial resources.
- Generator has ordinary `Functor`, `Applicative`, and `Monad` behavior, so dependent input is allowed. For example, sample a vertex count and then generate exactly that many labels. Do not use retry loops or predicate rejection.
- `elementOf first rest` and `weighted first rest` are non-empty by construction. A fixed complete scenario is a normal choice value, such as `elementOf [1, 3, 2] [[4, 2, 5]]`.
- Give generators containing overloaded strings or tuples an explicit signature, such as `graphScenario :: Generator (String, String, String)`, so GHC does not have to guess their concrete types.
- `create`, `materialize`, `seal`, and `relate` are the only trace-building operations shared by Domain and Program. Domain cannot perform algorithm lifecycle actions.

## Program: strict linear semantics

- `Traceable` associates an authored semantic type with one trusted payload: `LUnit`, `LBool`, `LInt`, `LDouble`, `LString`, or stateless `LOperator`.
- `create payload` returns `Create pending`; every `Pending` must reach exactly one `materialize kind pending` or `replace old pending` path. Materialization always requires one declared `Kind`.
- Each `Block` is the sole live capability for one semantic value. Thread it through `copy`, `use`, `apply1`, `apply2`, `replace`, `destroy`, `seal`, `unseal`, and `step` by matching their public result wrappers.
- `copy` is the only way to reuse a live semantic value: it returns the original Block and a pending fork. `use`, `apply1`, `apply2`, `replace`, and `destroy` end their input Block lifetimes.
- A copied fork is still `Pending`; materialize it before passing it to an operator. For example: `Copy value1 pendingProbe <- copy value`, then `probe <- materialize probeKind pendingProbe`, then `Apply1 resultPending <- apply1 operator probe`.
- Model a meaningful derivation with `Applicable1` or `Applicable2`, then execute it with `apply1` or `apply2`. Do not precompute algorithm results outside Program and introduce them as if they were inputs.
- Operators are ordinary stateless trace types whose payload is `LOperator Operator`. Runtime parameters are separate operand Blocks.

  ```haskell
  data Add
  instance Traceable Add where
    type Payload Add = LOperator Add

  instance Applicable2 Add Number Number where
    type Apply2Result Add Number Number = Number
    applyPayload2 LOperator (LInt leftValue) (LInt rightValue) =
      LInt (leftValue Linear.+ rightValue)
  ```

- `step @Name action` records one typed, nestable occurrence around the complete action and returns its result unchanged. Repeated calls create distinct occurrences.
- A Program helper receiving generated data or a linear resource uses `%1` arguments. GHC must reject duplication, dropping, or capture by an unrestricted closure before tracing begins.
- A traversal algorithm must advance its queue, frontier, visited set, or equivalent state through typed lifecycle operations. Domain may generate the graph and start value, but it must not generate the finished traversal for Program to replay.

## Slots and semantic relations

- `seal owner occupant` hides the occupant and returns the same owner identity plus `Slot owner occupant`. `unseal owner slot` returns the owner and current occupant. Replacing and resealing an occupant does not change the owner identity.
- `relate relationKind sourceSlot targetSlot` records a relation between stable Slot owners and reissues both Slot capabilities through `Relate`. It returns no public relation token.
- A relation survives unsealing and resealing because it belongs to owners, not their current occupants. It ends when either owner is terminally consumed; a replacement owner does not inherit it.
- There is no mid-lifetime relation removal. To make a semantic transition to a different relation set, end the relevant owner lifetime, materialize successor owners, and relate their Slots.
- Adding a duplicate ordered pair, or either orientation of a duplicate symmetric pair, is a diagnostic.
- The relation becomes visible after its creation event. Its Render rules participate in the fixed visual constraint system for the overlapping endpoint lifetimes; do not author mutually incompatible rules for the same owners.

## Render presence, frames, and hierarchy

- `always action` adds no random decision. `sometimes action` creates one equal include/omit decision at the current match scope. Nested conditions combine, and Render handles returned from an optional action carry that condition into dependent visual components.
- Wrap every `frame @Step` in `always` or `sometimes`; bare frames are invalid. At least one declared step that executes in every scenario must have an `always` frame.
- `sometimes $ frame @Step` independently includes each runtime occurrence. Omission affects playback output only: the compiler still validates topology and prepares layout for every occurrence.
- `select kindHandle` returns all current semantic matches. `select relationHandle` returns active relation matches. No predicate or string-fact language exists.
- `node selected body` maps every current match. `node body` creates and returns one generated visual parent. Both forms may contain child nodes; nested selected nodes map the matching current occupants of selected Slot owners.
- A generated `node $ do ...` returns its handle. Earlier statements in a Render `do` block discard that result normally; if it is the final statement where `Render ()` is required, bind/discard the handle or follow it with `pure ()`.
- Use generated parents to define groups and local constraint scopes. They default to hugging their retained children. `self` is the current generated parent; `canvas` is the persistent root geometry handle.
- A selection may have several visual mappings, but any use of its geometry or as a connector endpoint must resolve to exactly one context-local mapping. Use separate generated-parent scopes to disambiguate deliberate duplicates.
- Visual state must be explicit in Program. To show a current, visited, processed, or frontier value, transition it with `copy`, `replace`, and `materialize` under a dedicated `Kind`, keep that successor alive through the relevant frame, and select/style that Kind in Render. Do not infer visual emphasis from every Block used by a step or create a short-lived probe that is destroyed before the frame.

  ```haskell
  markCurrent :: Block Value %1 -> Program (Block Value)
  markCurrent value = do
    Copy original currentOrigin <- copy value
    Replace currentPending <- replace original currentOrigin
    materialize currentValueKind currentPending

  currentValues <- select currentValueKind
  node currentValues $ style @Stroke (Hsl (num 32) (num 0.8) (num 0.45))
  ```

  A later transition can replace the current-state Block under the ordinary or processed Kind. This is the current equivalent of the older linear tag pattern: Program owns the state lifetime, and Render owns its appearance.

- `within membership owners body` restricts selections inside one current owner match to targets of that ordered owner-to-member relation. It does not itself draw or create hierarchy.

## Relation rules and graph structure

- `relation links body` evaluates the body once for each active relation. Inside it, `first links` and `second links` return the typed endpoint selections for that exact relation occurrence.
- Ordered endpoints preserve source and target meaning. Symmetric endpoints have a stable output order but no semantic direction.
- Relations pair nodes and may support constraints, connectors, or both; selecting a relation draws nothing automatically.
- `asSequence links nodes`, `asTree links nodes`, and `asDag links nodes` validate the complete selected structure and require an ordered relation; symmetric relations are rejected. They do not replace the original selections.
- Inside the matching node body, `rankOf ranking` returns sequence position, tree depth, or longest-path DAG level as a compiler-fixed integer. Use `asScalar` in affine formulas or `asText` in a label.
- `payloadScalar selection` similarly exposes the current `LInt` or `LDouble` payload as a fixed affine coefficient. It is not a fresh variable or Program value.
- `arrange` applies a deterministic relative template: `ArrangeGrid`, `ArrangeLayered`, `ArrangeRadial`, or `ArrangeTree`. `ArrangeLayered` and `ArrangeTree` require an ordered relation; symmetric relations are rejected. Put alternative templates in an explicit `oneOf`; arrangements make no hidden random choice.

## Whole-line text and typed fragments

- `text "literal"` constructs one complete line. `bindContent` reads the current selected payload's display text.
- A `TextBuilder` can concatenate `literal`, `fragment @Step`, and `fragmentMany @'[StepA, StepB]` pieces. Concatenation inserts no whitespace.
- A fragment associates a character range with typed step occurrences so the renderer can highlight the relevant glyph clusters. The compiler still shapes the complete line once, preserving kerning, ligatures, and bidirectional text.

  ```haskell
  comparisonLine :: ContentValue
  comparisonLine = do
    literal "if "
    fragment @ReadElement "A[i]"
    fragmentMany @'[Compare, ReadTarget] " == "
    fragment @ReadTarget "target"
  ```

- Text never wraps. A `ContentValue` must contain no newline. Use separate positioned nodes for separate or indented lines; a geometric indent remains correct when the font changes.
- Typed fragments render as continuous background emphasis behind each spatial text run. Use ASCII `->` in authored text when an explicitly selected font is not known to contain a Unicode arrow; use a connector for a semantic arrow between nodes.
- `content value` uses a fixed authored or theme size and contributes intrinsic bounds to a hugging node. `fitText value` keeps one line within its bounded box while leaving `FontSize` free in its feasible finite range. It does not maximize the size.
- Every concrete peer created by one `node selected` mapping shares the same implicit fitted size. Each peer contributes a fit constraint, so the longest label limits that shared size. A separate mapping of the same selection owns a separate size family.
- One node may define content exactly once. Different fonts within one shaped line are unsupported.

## Connectors

- `connector start end body` draws one straight connector from two `anchor` values. `AtBoundary` is useful for graph edges; explicit edge-center placements are `AtTop`, `AtRight`, `AtBottom`, and `AtLeft`.
- `startMarker` and `endMarker` select `NoMarker`, `ArrowMarker`, `CircleMarker`, or `DiamondMarker`. Connector bodies accept only `Stroke`, `StrokeWidth`, and `Opacity` styles; node-only styles are rejected.
- A connector adds no layout constraint. Pair it with explicit geometry rules when its endpoints must be separated or ordered.
- Inside `relation`, a connector inherits that semantic relation's identity and lifetime. Outside, it joins the two context-local node mappings. Endpoint and surrounding presence conditions propagate automatically, so `sometimes` works for arrows, guides, labels, and other visual components, not only frames.

## Bounded affine layout

- Numeric Render values are typed: `Coord` is a non-negative position, `Span` a non-negative length, `Offset` a signed difference, `Scalar` unitless, `Unit` bounded from zero to one, and `Angle` a bounded hue.
- Render-form `variable @Span` (or another supported numeric type) creates one fresh symbolic value. It returns the value directly; there is no wrapper constructor or string-named identity.
- Use `at`, `by`, `shift`, and `num` for constants. Symbolic values use `.+.`, `.-.`, `.*.`, and `./.`; ordinary arithmetic remains for Generator values.
- Every independent symbolic value must have finite lower and upper bounds, either explicitly or through derived constraints. The compiler rejects unbounded, infeasible, and unsupported nonlinear designs; it never falls back to nonlinear optimization.
- Products are affine only when at least one factor is fixed before solving, and division requires a fixed non-zero denominator. Variable-by-variable products and variable denominators are rejected.
- `ensure` records exact `.<=.`, `.>=.`, or `.==.` requirements. Prefer local relative constraints over fixed canvas coordinates:

  ```haskell
  gap <- variable @Span
  ensure $ gap .>=. by 16
  ensure $ gap .<=. by 72
  relation adjacentLinks $ do
    previous <- first adjacentLinks
    next <- second adjacentLinks
    ensure $ left next .==. (right previous .+. gap)
    ensure $ y next .==. y previous
  ```

- `separatedBy gap firstNode secondNode` requires non-overlap without choosing an order. Its four exact geometric cases are compiler bookkeeping and do not make that authored design four times as likely.
- Parent-relative `xAt`, `yAt`, `widthOf`, and `heightOf` use a fixed `percent 0..100`. A sampled percentage times a sampled parent size would be nonlinear and is not supported.
- `padding` and `margin` use `uniform`, `symmetric vertical horizontal`, or `edges top right bottom left`. `contentFit axis Hug` keeps parent edges tight to content; `Contain` permits extra bounded space.
- A free-expanding canvas is invalid because there is no finite interval to sample uniformly. Hugging bounded content can determine its size; a containing canvas needs finite width and height. `aspectRatio` fixes shape, not scale.
- The compiler prepares each feasible affine region once, then independently samples it for every view seed. Reusing preparation does not reuse a layout point.

## Authored choices and optional variation

- `oneOf name first rest` creates one fresh authored choice. Each `alternative label body` contains a complete `Render ()` action, so alternatives may differ in nodes, hierarchy, styles, connectors, and constraints.

  ```haskell
  oneOf "layout"
    (alternative "row" $ ensure $ left result .==. (right source .+. gap))
    [alternative "column" $ ensure $ top result .==. (bottom source .+. gap)]
  ```

- Feasible authored alternatives have equal baseline weight; infeasible ones are removed. Nested choices are weighted locally at the point reached.
- `choice` creates a reusable finite built-in categorical value. `caseOf existingChoice` exhaustively maps it to complete Render actions. Authors cannot define custom categorical domains; use `oneOf` for custom alternatives.
- `fontChoice (fontKind Monospace)` and `fontChoice (fontKind Proportional)` choose among unique concrete bundled faces. Reuse one returned choice when nodes should share a font decision.
- `sometimes` is appropriate when either presence or absence is valid. Use `oneOf` when alternatives are mutually exclusive but at least one representation is required, such as array-only, tree-only, or both views of a heap.
- When the brief leaves composition open, include at least two meaningful layout or representation alternatives. Prefer alternatives such as row/column, graph/tree, or overview/detail over random per-node sizes. Keep essential states visible and make only subordinate explanation frames or components optional.
- Minimize absolute pixel constraints. Give the canvas one broad finite envelope, use only genuine readability minima, and derive ordinary panel, group, and peer geometry through `Hug`, `Contain`, hierarchy, shared dimensions, relations, and relative affine constraints. Do not assign a separate narrow size or coordinate range to every component.

## Style rules

- `style @Field value` requires one field; `withoutStyle @Field` removes an inherited field; omission leaves the theme/default free. Do not invent style fields or private helper classes.
- When routine leaf styles are omitted, the compiler chooses one coherent surface profile per semantic node-mapping lineage and one shared palette for the presentation. It may also choose one concrete managed font. Repeated peers do not independently randomize these fields, and generated text-only labels stay transparent unless explicitly styled.
- Numeric style fields are `Opacity`, `FontSize`, `Radius`, `StrokeWidth`, and paint `Alpha`. Paint uses `Hsl hue saturation lightness` as `Color`, with `Angle` hue and `Unit` components.
- Paint fields are `Fill` and `Stroke`. Categorical fields are `BorderStyle`, `FontFamily`, `FontWeight`, `FontStyle`, and `TextAlign`. Use only the constructors in the API index.
- Font weight and style choices must name a real managed face. Unsupported combinations are removed from the design space rather than synthesized or mapped to a nearby face; `FontWeightBolder` and `FontWeightLighter` resolve from the inherited weight.
- `styleOf @Field selected` reads a mapped final style value from the exact context-local node mapping. It requires that field to exist in every reached branch.
- A requested border needs a positive `StrokeWidth`, a `Stroke`, and a non-empty `BorderStyle`; changing only one does not establish a complete border.
- Prefer one semantic accent channel plus at most one or two supporting changes. Leave unrelated fields unspecified so the compiler can produce coherent seeded variation.
- Array-like peers should normally share dimensions, padding, and typography. If the brief genuinely calls for an organic treatment, put the whole family in one named alternative and constrain each peer to `0.96`–`1.04` of shared base dimensions; do not give every cell an unrelated full-range size.

## Final source audit

- Every declaration marker is unique and registered; every typed step used by Program or Render is declared.
- Every generated value and linear resource is consumed exactly once. Algorithm results come from traced operations, not unrestricted precomputation.
- Every frame has an explicit presence policy, and each scenario executes at least one always-visible frame.
- Every selected mapping and relation endpoint resolves locally without ambiguity. Optional dependencies inherit the correct presence condition.
- Every effectful semantic node mapping can appear in at least one declared frame. A transient probe consumed before the frame cannot carry visual state; materialize a dedicated state successor whose lifetime reaches the frame instead.
- Every symbolic numeric value is finitely bounded; all geometry remains affine and feasible for every surviving authored alternative.
- Every line is shaped as one non-wrapping string, and every connector has mapped endpoints.
- Use only names present in `dslApiIndex`. If the requested behavior is not expressible, explain the limitation instead of inventing an API.
