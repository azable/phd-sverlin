# Sverlin compatibility patch

This directory is the Hackage `MIP-0.2.0.1` source distribution (BSD-3-Clause).
Sverlin vendors it so Cabal resolves one audited implementation and applies the
minimal compatibility change needed by `xml-conduit >= 1.9`: use `XML.def`
instead of the removed orphan `Default ParseSettings` instance in the CPLEX
solution parser. No solver behavior is changed.

Upstream release: <https://hackage.haskell.org/package/MIP-0.2.0.1>
Upstream repository tag: `v0.2.0.1` (`94b109c7242898e3a4c73ddc91b48bf5c6796d5c`)
