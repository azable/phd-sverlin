import * as c from '$lib/layout/constraints.svelte';
import { createLayout } from '$lib/layout/index.svelte';

export const compile = async (config: Parameters<typeof createLayout>[0]) => {
  const layout = await createLayout(config);
  const { step, constraint, variable } = await layout;

  const intsize = variable('intsize').constraint(c.minimize);

  const int = {
    width: intsize,
    height: intsize,
    backgroundColor: 'lightblue',
    border: '2px solid black',
    borderRadius: '10px',
    fontSize: 40,
    zIndex: 10
  };

  const op = {
    width: intsize,
    height: intsize,
    backgroundColor: 'lightcoral',
    border: '2px solid black',
    borderRadius: '10px',
    fontSize: 30,
    zIndex: 10
  };

  const [v1] = await step([], [[int, '1']]);

  const [plus] = await step([], [[op, '+']]);

  const [v2] = await step([], [[int, '2']]);

  constraint(c.leftOf(v1, plus, 20));
  constraint(c.leftOf(plus, v2, 20));

  const [v3] = await step([v1, v2, plus], [[int, '3']]);

  constraint(c.eq(v3.top, v2.top));
  constraint(c.eq(v3.left, v2.left));

  return layout;
};
