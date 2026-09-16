defmodule DomovoyGitPlugin.Validator.DiffRefsPresent do
  @moduledoc """
  Makes sure that a node supplies the two refs that a branch diff compares.

  `DomovoyGitPlugin.Runner.BranchDiff` lists this validator. The validator
  reads `base_branch` and `target_branch` from the changeset. If a ref is
  `nil` or blank, the validator adds a `can't be blank` error on that field.
  It does not run a Git command.

  The input schema of `BranchDiff` also requires both refs. Therefore
  `DomovoyCore.Node.new/1` refuses a node that binds neither ref, and
  `DomovoyCore.Runner.changeset/2` rejects a blank ref before this validator runs.
  This validator repeats the rule at execution time and skips a field that
  already has an error. It is the reusable form of the rule for a node
  validator list on another runner that compares two refs.

  ## Examples

      iex> changeset = DomovoyCore.Runner.changeset(
      ...>   DomovoyGitPlugin.Runner.BranchDiff,
      ...>   %{base_branch: "main", target_branch: "feature"}
      ...> )
      iex> checked = DomovoyGitPlugin.Validator.DiffRefsPresent.validate(changeset, %DomovoyCore.Context{})
      iex> checked.valid?
      true

  A changeset without `target_branch` gets an error that names it:

      iex> changeset = Ecto.Changeset.cast(
      ...>   {%{}, %{base_branch: :string, target_branch: :string}},
      ...>   %{base_branch: "main", target_branch: "  "},
      ...>   [:base_branch, :target_branch]
      ...> )
      iex> checked = DomovoyGitPlugin.Validator.DiffRefsPresent.validate(changeset, %DomovoyCore.Context{})
      iex> checked.errors
      [target_branch: {"can't be blank", [validation: :required]}]
  """

  @behaviour DomovoyCore.Validator

  alias DomovoyCore.Context
  alias DomovoyCore.Validator
  alias Ecto.Changeset

  @refs [:base_branch, :target_branch]

  @impl Validator
  @spec validate(changeset :: Changeset.t(), context :: Context.t()) :: Changeset.t()
  def validate(%Changeset{} = changeset, %Context{}) do
    Enum.reduce(@refs, changeset, &ref_present/2)
  end

  @spec ref_present(field :: atom(), changeset :: Changeset.t()) :: Changeset.t()
  defp ref_present(field, %Changeset{} = changeset) do
    ref = Changeset.get_field(changeset, field)

    if present?(ref) or Keyword.has_key?(changeset.errors, field) do
      changeset
    else
      Changeset.add_error(changeset, field, "can't be blank", validation: :required)
    end
  end

  @spec present?(ref :: term()) :: boolean()
  defp present?(ref) when is_binary(ref), do: String.trim(ref) != ""
  defp present?(_ref), do: false
end
