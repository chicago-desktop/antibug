# windows/antibug — AntiBug

A test scanner for the Windows 95 shell of the terminal desktop
([windows/shell](https://github.com/wippy-windows/windows)), in the style of
McAfee VirusScan 95: Start → Programs → **AntiBug**. A scan is a run of test
suites, an "infected" test is a failed case, and the end of a scan is the
"Scan complete." box. For administrators only.

It scans two kinds of things:

- **This computer** — the application's own `meta.type: test` entries, as a
  tree of groups, suites and entries; they run one at a time inside the
  running runtime, without blocking the shell.
- **Scan targets** — what the application declares beyond its registry: a
  module's working copy through the wippy test runner, or a Go module through
  `go test -json`, each as a child process, its cases arriving as they run.

Findings, progress, the log (Save… writes it on a drive of My Computer) and
Stop, which kills a target's child.

## Scan targets: how an application adds one

A target is a registry entry of the application with
`meta.type: windows.antibug_target`. AntiBug finds every such entry; the
module declares none of its own.

```yaml
- name: antibug_shell
  kind: registry.entry
  meta:
    type: windows.antibug_target
    title: Windows shell
    kind: wippy                        # or go
    dir: /home/me/repos/wippy/windows-module
    wippy: /home/me/repos/wippy/runtime/dist/wippy-linux-amd64
    host: wippy.terminal:host
    order: 2
    env:
      HOME: /home/me
      PATH: /usr/local/bin:/usr/bin:/bin
```

- `title` — the name in the "Scan in" list (the entry id if absent).
- `kind` — `wippy` runs `<wippy> test --host <host>` in `<dir>/test`, as a
  module's `make test` does; `go` runs `go test -json ./...` in `<dir>`.
- `dir` — the working copy or the Go module; a relative path is relative to
  the runtime's working directory.
- `wippy` — for `wippy`, the runner binary; `wippy` from PATH when absent.
  A module of the shell needs a local build of the runtime fork (the shell
  declares `gfx`), so name the build here.
- `host` — for `wippy`, the terminal host of the run; `wippy.terminal:host`
  when absent.
- `order` — the position in the list.
- `env` — **the child's whole environment.**

**The `meta.env` rule.** `exec` does not inherit the runtime's OS
environment: the child gets exactly what `env` names and nothing else. `go`
needs `PATH` and a `HOME` (or `GOCACHE` and `GOPATH`); the wippy runner needs
`HOME` and `PATH`, which the harness it boots reads. Write the values
literally: a `${env:…}` placeholder in a registry entry resolves against the
application's environment registry, not the OS, and a missing variable fails
the whole boot — the reason the module's own `exec` entry has no
`default_env` at all.

The runner builds the command from the registry entry, never from the
window's arguments, with no shell in between. Every child runs under
`nice -n 19`: a module's suite or a Go build takes every core, and the shell
must stay responsive. A target that cannot start is one finding with the
reason; a bad exit with no failed case is one finding too.

## Trust

- **The window is narrow.** Its policies are `windows.antibug:window_scope`
  (talk to the compositor and its target process, find entries, read the
  drives) and `windows.antibug:runner_call` — `funcs.call` on
  `windows.antibug:runner` and nothing else. It never execs.
- **The runner carries the rights.** `windows.antibug:runner` is a function
  entry with its own actor (`windows.antibug:runner`) and the unrestricted
  `windows.antibug:runner_policy`, like the CLI test runner's: tests touch
  the database, fs and gfx, targets run through `exec`. A `funcs` call runs
  the callee under the actor its entry declares, its declared policies added
  to the caller's scope — measured, not assumed, by
  `test/src/antibug_actor_test.lua`. A test entry declares no actor of its
  own and runs under the runner; so does the target process the runner
  spawns. The runner runs only `meta.type: test` entries and declared
  targets, and refuses anything else by name.
- **Administrators only.** The window names `requires: windows.admin`; the
  base's compositor asks the logged-on person's scope before opening it
  (`app.security:admin` has it through `*`). Under a terminal.ssh host anyone
  with an account logs on — without the field AntiBug would open for
  everyone, with the runner behind it.
- Give no other entry `funcs.call` on `windows.antibug:runner`.

## What the application provides

`windows.antibug:process_host` — the process host the target processes run
on, `app:processes` by default. Nothing else: the window is found by the
Start menu from its registry entry, and its picture comes with the module.

## Inside

- `windows.antibug:window` — the window, on the shell's SDK
  (`windows.shell.sdk:app`), with the file dialog and My Computer's drives
  for Save….
- `windows.antibug:scan` — the model, pure: the tree, what a selection
  scans, the scan's state machine over the `wippy.test` events, the
  findings, the log and the box.
- `windows.antibug:targets` — the targets, pure: the declarations, the
  command of each kind, and the parsers of the wippy runner's text and of
  `go test -json` into case events.
- `windows.antibug:runner` — the function that runs one scan item;
  `windows.antibug:target` — the process that runs one target's child
  through `windows.antibug:exec`.
- `windows.antibug:images` — the module carries its own pictures, an image
  pack of the shell (`meta.type: windows.images`) under
  `assets/images/{32,16}`: the magnifier `find`, named
  `windows.antibug:images/find` by the entry and every dialog; copied from
  the shell's icon set (Microsoft's artwork from `shell32.dll`, see
  `assets/images/SOURCE.md`) and embedded at publish through `embed:` in
  `wippy.yaml`.

The design and its measurements are in [docs/antibug.md](docs/antibug.md)
and [docs/rfcs/009-antibug.md](docs/rfcs/009-antibug.md).

## Developing

```bash
make setup     # resolve the dependencies from the Hub (once, and after changing them)
make check     # the repository's invariants
make lint      # late locals, then wippy lint of this namespace and the harness
make test      # the harness in test/, with test/shots/antibug.png and antibug-complete.png
make publish   # to the Hub, after `wippy auth login`
```

The suites: `window_test` (the entry, the picture, the trust shape),
`antibug_actor_test` (the callee's actor), `antibug_test` (the model, every
menu item and button, a live scan of a real harness entry, the shots) and
`antibug_targets_test` (the parsers on captured output, and a live Go target
through the runner, the target process and `exec` — it needs Go under
`/usr/local/go/bin`, see `antibug_go_target` in `test/src/_index.yaml`).

**A local build of the runtime fork is required**
([wippy-windows/runtime](https://github.com/wippy-windows/runtime), branch
`wippy-projects`): the shell declares the `gfx` module, which the release
runtime does not have, and `wippy` from PATH does not load the shell at all.
The Makefile's `WIPPY` names the build; override it with `make test WIPPY=…`.

The window SDK is documented in [docs/sdk.md](docs/sdk.md), a copy of the
shell's guide, and the skill for agents in
[skills/wippy-window-app/SKILL.md](skills/wippy-window-app/SKILL.md); the
rules of this repository are in [AGENTS.md](AGENTS.md).

Made from [the Windows module template](https://github.com/wippy-windows/module-template) for
modules of the Windows 95 shell. Repository:
https://github.com/wippy-windows/antibug.

## Licence

MIT. The picture in `assets/images` is Microsoft's artwork (`shell32.dll`),
copied from the shell's icon set, and is not covered by the licence.
