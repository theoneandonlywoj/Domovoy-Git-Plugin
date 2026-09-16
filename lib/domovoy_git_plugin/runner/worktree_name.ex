defmodule DomovoyGitPlugin.Runner.WorktreeName do
  @moduledoc """
  Makes a managed-worktree name from a branch name.

  A branch name can contain a `/` character, as in
  `theoneandonlywoj/bro-19-add-metadata`. A worktree name must be one path
  segment. Therefore this runner keeps the last segment of the branch name.

  The runner does not judge the name it derives. That check gives no value, and
  therefore it belongs to a validator.
  `DomovoyGitPlugin.Validator.WorktreeNameIsSafe` is the only home of the rule.
  The runner that consumes this name lists it, as
  `DomovoyGitPlugin.Runner.WorktreeResolve` does.

  ## Inputs

    * `target_branch` — necessary. A `DomovoyCore.Type.String` with the branch
      name.
    * `worktree_name` — optional. A `DomovoyCore.Type.String` that gives the name
      directly and stops the derivation.

  The node `:type` receives the worktree name. Usually the type is
  `DomovoyCore.Type.String`.

  ## Examples

      iex> params = %{target_branch: "theoneandonlywoj/bro-19-add-metadata"}
      iex> input = DomovoyGitPlugin.Runner.WorktreeName |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "worktree_name"}
      iex> DomovoyGitPlugin.Runner.WorktreeName.run(input, context)
      {:ok, "bro-19-add-metadata"}

  A `worktree_name` argument overrides the derivation:

      iex> params = %{target_branch: "theoneandonlywoj/bro-19-add-metadata", worktree_name: "review"}
      iex> input = DomovoyGitPlugin.Runner.WorktreeName |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "worktree_name"}
      iex> DomovoyGitPlugin.Runner.WorktreeName.run(input, context)
      {:ok, "review"}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType

  input do
    field(:target_branch, StringType)
    field(:worktree_name, StringType)
  end

  required([:target_branch])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{worktree_name: name}, %Context{}) when is_binary(name) and name != "",
    do: {:ok, name}

  def run(%Input{target_branch: branch}, %Context{}),
    do: {:ok, branch |> String.split("/") |> List.last()}
end
