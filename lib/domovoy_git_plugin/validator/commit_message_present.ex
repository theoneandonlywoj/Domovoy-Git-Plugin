defmodule DomovoyGitPlugin.Validator.CommitMessagePresent do
  @moduledoc """
  Makes sure that `message` is present after trim.

  `DomovoyGitPlugin.Runner.Commit` lists this validator. An empty message must
  not start the node. The validator does not run a Git command.

  If the field is `nil`, or if the field already has an error, the validator
  leaves the changeset as it is.

  ## Examples

      iex> changeset = DomovoyCore.Runner.changeset(
      ...>   DomovoyGitPlugin.Runner.Commit,
      ...>   %{message: "Add the snapshot"}
      ...> )
      iex> checked = DomovoyGitPlugin.Validator.CommitMessagePresent.validate(changeset, %DomovoyCore.Context{})
      iex> checked.valid?
      true

  A blank message gives an error on the field:

      iex> changeset = DomovoyCore.Runner.changeset(
      ...>   DomovoyGitPlugin.Runner.Commit,
      ...>   %{message: "   "}
      ...> )
      iex> checked = DomovoyGitPlugin.Validator.CommitMessagePresent.validate(changeset, %DomovoyCore.Context{})
      iex> checked.valid?
      false
      iex> checked.errors
      [message: {"can't be blank", [validation: :required]}]
  """

  @behaviour DomovoyCore.Validator

  alias DomovoyCore.Context
  alias DomovoyCore.Validator
  alias Ecto.Changeset

  @field :message

  @impl Validator
  @spec validate(changeset :: Changeset.t(), context :: Context.t()) :: Changeset.t()
  def validate(%Changeset{} = changeset, %Context{}) do
    message = Changeset.get_field(changeset, @field)

    cond do
      is_nil(message) or Keyword.has_key?(changeset.errors, @field) ->
        changeset

      present?(message) ->
        changeset

      true ->
        Changeset.add_error(changeset, @field, "can't be blank", validation: :required)
    end
  end

  @spec present?(message :: term()) :: boolean()
  defp present?(message) when is_binary(message), do: String.trim(message) != ""
  defp present?(_message), do: false
end
