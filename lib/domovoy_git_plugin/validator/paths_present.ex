defmodule DomovoyGitPlugin.Validator.PathsPresent do
  @moduledoc """
  Makes sure that `paths` is a non-empty list of non-empty path strings.

  `DomovoyGitPlugin.Runner.Add`, `DomovoyGitPlugin.Runner.CheckoutOurs` and
  `DomovoyGitPlugin.Runner.CheckoutTheirs` list this validator. An empty list
  must not become `git add .` or a checkout of every path. A blank path is also
  refused. The validator does not run a Git command.

  If the field is `nil`, or if the field already has an error, the validator
  leaves the changeset as it is.

  ## Examples

      iex> changeset = DomovoyCore.Runner.changeset(
      ...>   DomovoyGitPlugin.Runner.Add,
      ...>   %{paths: ["README.md"]}
      ...> )
      iex> checked = DomovoyGitPlugin.Validator.PathsPresent.validate(changeset, %DomovoyCore.Context{})
      iex> checked.valid?
      true

  An empty list gives an error on the field:

      iex> changeset = DomovoyCore.Runner.changeset(
      ...>   DomovoyGitPlugin.Runner.Add,
      ...>   %{paths: []}
      ...> )
      iex> checked = DomovoyGitPlugin.Validator.PathsPresent.validate(changeset, %DomovoyCore.Context{})
      iex> checked.valid?
      false
      iex> checked.errors
      [paths: {"can't be blank", [validation: :required]}]
  """

  @behaviour DomovoyCore.Validator

  alias DomovoyCore.Context
  alias DomovoyCore.Validator
  alias Ecto.Changeset

  @field :paths

  @impl Validator
  @spec validate(changeset :: Changeset.t(), context :: Context.t()) :: Changeset.t()
  def validate(%Changeset{} = changeset, %Context{}) do
    paths = Changeset.get_field(changeset, @field)

    cond do
      is_nil(paths) or Keyword.has_key?(changeset.errors, @field) ->
        changeset

      present?(paths) ->
        changeset

      true ->
        Changeset.add_error(changeset, @field, "can't be blank", validation: :required)
    end
  end

  @spec present?(paths :: term()) :: boolean()
  defp present?(paths) when is_list(paths) and paths != [] do
    Enum.all?(paths, fn path -> is_binary(path) and String.trim(path) != "" end)
  end

  defp present?(_paths), do: false
end
