defmodule DomovoyGitPlugin.Validator.PathsPresentTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Runner.Add
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Type.Paths, as: PathsType
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType
  alias DomovoyGitPlugin.Validator.PathsPresent
  alias Ecto.Changeset

  doctest PathsPresent

  @context %Context{}

  describe "validate/2" do
    test "leaves the changeset valid for a non-empty list of paths" do
      changeset = changeset(%{paths: ["README.md"]})

      assert PathsPresent.validate(changeset, @context) == changeset
    end

    test "rejects an empty list" do
      checked = %{paths: []} |> changeset() |> PathsPresent.validate(@context)

      refute checked.valid?
      assert checked.errors == [paths: {"can't be blank", [validation: :required]}]
    end

    test "rejects a blank path in the list" do
      checked = %{paths: ["  "]} |> changeset() |> PathsPresent.validate(@context)

      refute checked.valid?
    end

    test "leaves a nil list to the input schema" do
      changeset = Changeset.cast({%{}, %{paths: {:array, :string}}}, %{}, [:paths])

      assert PathsPresent.validate(changeset, @context) == changeset
    end

    test "stops the node before the runner" do
      node =
        Node.new(%{
          name: "add",
          runner: Add,
          type: RepoStateType,
          bind: %{paths: {"paths", PathsType}}
        })

      paths = DomovoyCore.Value.cast!([], PathsType)

      assert %Error{} = error = NodeRunner.run(node, [{"paths", paths}])
      assert error.type == :invalid_input
      assert error.reason == [paths: {"can't be blank", [validation: :required]}]
    end
  end

  @spec changeset(params :: map()) :: Changeset.t()
  defp changeset(params), do: Runner.changeset(Add, params)
end
