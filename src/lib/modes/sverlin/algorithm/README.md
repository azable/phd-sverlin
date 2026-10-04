# Algorithm steps

Write the algorithm in one `<script lang="sverlin">` block at the top of the component. Its statements run once, before playback, in a restricted subset of JavaScript. Each `yield 'label';` statement records one step: the label shown in the playback controls, plus a copy of every variable declared at the top level of the block. The view receives those variables as props, together with `step` and `seed`, so a step shows the state exactly as it was at that `yield`.

- Declare state you want to show at the top level with `let` or `const`. Variables declared inside loops or blocks are not recorded; declare a loop index at the top level (`let i = -1;`) and use `for (i = 0; ...)` when the view needs it. A top-level variable not yet declared at a step is `null`.
- `yield` must be its own statement. Labels are non-empty strings and may repeat, such as ``yield `Compare ${values[i]}`;``. A bare `yield;` is labelled `Step n`. `return;` stops the algorithm early.
- Allowed: numbers, strings, booleans, `null`, arrays, plain objects; `if`, `for`, `for (const x of array)`, `while`, `do`, `break`, `continue`; arithmetic, comparison with `===`/`!==`, `&&`, `||`, `??`, `? :`, template strings, `+=` and `++`; `Math.abs/ceil/floor/max/min/pow/round/sign/sqrt/trunc`, `Math.PI`; array `.length`, `.push`, `.pop`, `.shift`, `.unshift`, `.slice`, `.indexOf`, `.includes`, `.reverse`, `.join`.
- Not allowed: functions of any kind, `new`, classes, `this`, `==`, string methods, other globals, and the names `step` and `seed`. Write helper logic inline.
- The algorithm does not receive the seed, so every view shows the same steps. Use `seed` in the view only for presentation choices.
- Limits: 200 steps, 1,000,000 operations, 10,000 entries per array or object, and 10,000 characters per string.

Without an algorithm block, a static presentation may instead export `const steps = ['Start', ...]` from `<script module>` with unique labels; the view then receives only `step` and `seed`.
