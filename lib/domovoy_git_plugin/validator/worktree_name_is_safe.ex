defmodule DomovoyGitPlugin.Validator.WorktreeNameIsSafe do
  @moduledoc """
  Makes sure that `worktree_name` is one safe path segment.

  Domovoy puts a managed worktree in `.worktrees/<worktree_name>`. Therefore the
  name must not leave that directory. This validator rejects `..`, `.`, an
  empty name, and a name that contains `/` or `\\\\`.

  The validator reads the `worktree_name` field of the changeset. If the field
  is `nil`, or if the field already has an error, the validator leaves the
  changeset as it is. The input schema of the runner says whether the field is
  required. A runner that runs many operations reads the name in one operation
  only, and this validator does not know which operation runs.

  No runner repeats this check. A check that gives no value belongs to a
  validator, and therefore this module is the only home of the rule.
  `DomovoyGitPlugin.Runner.WorktreeName` derives a name and leaves the judgement
  to the runner that consumes it. Each runner with a `worktree_name` field
  lists this module in its `validators`.

  ## Examples

      iex> changeset = DomovoyCore.Runner.changeset(
      ...>   DomovoyGitPlugin.Runner.WorktreeResolve,
      ...>   %{worktree_name: "bro-19"}
      ...> )
      iex> checked = DomovoyGitPlugin.Validator.WorktreeNameIsSafe.validate(changeset, %DomovoyCore.Context{})
      iex> checked.valid?
      true

  A name that leaves `.worktrees/` gives an error on the field:

      iex> changeset = DomovoyCore.Runner.changeset(
      ...>   DomovoyGitPlugin.Runner.WorktreeResolve,
      ...>   %{worktree_name: "../escape"}
      ...> )
      iex> checked = DomovoyGitPlugin.Validator.WorktreeNameIsSafe.validate(changeset, %DomovoyCore.Context{})
      iex> checked.valid?
      false
      iex> checked.errors
      [worktree_name: {"is not a safe path segment", [validation: :worktree_name_is_safe]}]
  """

  @behaviour DomovoyCore.Validator

  alias DomovoyCore.Context
  alias DomovoyCore.Validator
  alias DomovoyGitPlugin.Capabilities
  alias Ecto.Changeset

  @field :worktree_name

  @impl Validator
  @spec validate(changeset :: Changeset.t(), context :: Context.t()) :: Changeset.t()
  def validate(%Changeset{} = changeset, %Context{}) do
    name = Changeset.get_field(changeset, @field)

    cond do
      is_nil(name) or Keyword.has_key?(changeset.errors, @field) ->
        changeset

      is_binary(name) and Capabilities.valid_worktree_name?(name) ->
        changeset

      true ->
        Changeset.add_error(changeset, @field, "is not a safe path segment",
          validation: :worktree_name_is_safe
        )
    end
  end
end
