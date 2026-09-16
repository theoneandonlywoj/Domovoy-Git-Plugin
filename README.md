# DomovoyGitPlugin

Git capabilities, types, validators, and runners for Domovoy.

Capabilities talk to Git through `DomovoyCore.Shell` with argument lists.
Runners, types, and validators sit on `DomovoyCore`. The host owns each
`DomovoyCore.Runtime`.

## Installation

Add to your `mix.exs`:

```elixir
defp deps do
  [
    {:domovoy_git_plugin, github: "theoneandonlywoj/Domovoy-Git-Plugin"}
  ]
end
```

## Verification

```sh
mix quality
mix test
```