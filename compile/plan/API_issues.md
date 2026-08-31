# API issues found by the example suite

The ten examples have no blocking expressibility gap. This file records only a
case where the current facade can produce a valid visualization but cannot use
all of its prepared layout options. Ordinary author-local linear container
helpers are repetition, not evidence for restoring queries or indexed mutation.

## Incidence-based graph arrangements

[`DijkstraShortestPath.sverlin`](examples/DijkstraShortestPath.sverlin) models a
weighted edge as an `Edge` Slot owner with `SourceOf Edge Vertex` and
`TargetOf Edge Vertex` relations. This preserves edge identity and gives its
weight a normal child node. It can draw the correct connector and use
`ArrangeGrid`, but `ArrangeRadial` and `ArrangeLayered` currently require one
homogeneous `Relations Vertex Vertex` value and cannot derive topology from the
two incidence relations.

The baseline should keep the valid grid representation. If topology-aware
placement of first-class edge objects proves important, prefer one narrow
derived-adjacency operation that validates exactly one source and target per
edge and preserves the edge identity. Duplicating every edge as an additional
node-to-node Program relation works today, but creates two semantic structures
that authors must keep consistent. Do not add either API until layout tests
show that the grid fallback is materially insufficient.
