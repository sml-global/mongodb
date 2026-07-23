# Environment Schema Fragments

This directory lets later plans extend the closed dev/uat environment
contract declaratively, without editing
[`../base.manifest`](../base.manifest) or
[`../../../scripts/lib/platform-env.sh`](../../../scripts/lib/platform-env.sh).

## How composition works

`load_platform_env` in `scripts/lib/platform-env.sh` loads
`config/environment-schema/base.manifest` first, then every file in this
directory that matches `*.manifest`, in bytewise lexical (`LC_ALL=C sort`)
order. The concatenation of all of these files is the closed schema for that
invocation. Order across fragment files is deterministic; row order within a
single file is preserved.

A fragment file must:

- Be a regular file. Symlinks and any other non-regular file (FIFO, device,
  directory, etc.) are rejected before any content is read.
- Use the same grammar as `base.manifest`:
  - Key rows: `KEY|required|validator|immutable-key-or--`
  - Constraint rows: `@constraint|predicate|KEY[,KEY...]|argument-or--`
  - Blank lines and lines starting with `#` are ignored.
- Declare only `KEY` names that do not already exist anywhere in the composed
  schema. A key declared twice (in the same fragment, across fragments, or
  against a `base.manifest` key) fails the whole load, closed.
- Name only the built-in validators and cross-key predicates implemented by
  the foundation (`environment`, `account-id`, `region`, `dns-label`,
  `s3-bucket`, `state-prefix`, `state-key`, `promotion-mode`, `nonempty`,
  `enum:<value,...>`, `fixed:<value>`, `integer:<min>:<max>`, `ipv4-cidr`,
  and the constraint predicates `integer-order`, `cidr-contained-by`,
  `cidr-nonoverlap`). An unknown validator, predicate, argument, or
  constraint key reference fails the whole load, closed.
- Bind a key to an immutable constant only through the final field naming a
  key handled by `immutable_environment_value` in
  `scripts/lib/environment-contracts.sh`. Use `-` for configurable keys.

Fragments cannot execute code: they are pure data files parsed with the same
closed, non-executable parsing philosophy used for `config/environments/*.env`
(manifests and dotenv files use two distinct parser functions with different
grammars, but neither ever `source`s, `eval`s, or otherwise executes file
content). A fragment can require a new dotenv key to exist (`required`), but
it cannot change how the parser works, add new validator implementations, or
affect any environment other than the one being loaded.

No fragment ships in this directory yet. This foundation package only owns
`base.manifest`; later packages add their own numbered
`fragments/<NN>-<name>.manifest` files here.
