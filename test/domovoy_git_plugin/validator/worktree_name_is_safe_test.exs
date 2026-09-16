defmodule DomovoyGitPlugin.Validator.WorktreeNameIsSafeTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.WorktreeResolve
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Type.Worktree, as: WorktreeType
  alias DomovoyGitPlugin.Validator.WorktreeNameIsSafe
  alias Ecto.Changeset

  doctest WorktreeNameIsSafe

  @context %Context{}

  describe "validate/2" do
    test "leaves the changeset valid for a single safe path segment" do
      for safe <- ["feature", "bro-19", "bro_19.2", "BRO-19-add-metadata"] do
        changeset = changeset(%{worktree_name: safe})

        assert WorktreeNameIsSafe.validate(changeset, @context) == changeset
      end
    end

    test "rejects a name that leaves the worktrees directory" do
      checked =
        %{worktree_name: "../escape"} |> changeset() |> WorktreeNameIsSafe.validate(@context)

      refute checked.valid?

      assert checked.errors == [
               worktree_name: {"is not a safe path segment", [validation: :worktree_name_is_safe]}
             ]
    end

    test "rejects separators, parent references and the current directory" do
      for unsafe <- ["a/b", "..", ".", "a\\b", "nested/deep/name"] do
        checked = %{worktree_name: unsafe} |> changeset() |> WorktreeNameIsSafe.validate(@context)

        assert [worktree_name: _error] = checked.errors
      end
    end

    test "leaves a nil name to the input schema" do
      changeset = Changeset.cast({%{}, %{worktree_name: :string}}, %{}, [:worktree_name])

      assert WorktreeNameIsSafe.validate(changeset, @context) == changeset
    end

    test "adds no second error to a name the schema already rejected" do
      changeset = changeset(%{worktree_name: ""})
      assert [worktree_name: _blank] = changeset.errors

      assert WorktreeNameIsSafe.validate(changeset, @context) == changeset
    end

    test "stops the node before the runner through the validators of the runner" do
      node =
        Node.new(%{
          name: "worktree_resolve",
          runner: WorktreeResolve,
          type: WorktreeType,
          bind: %{worktree_name: {"name", StringType}}
        })

      name = Value.cast!("../escape", StringType)

      assert %Error{} = error = NodeRunner.run(node, [{"name", name}])
      assert error.type == :invalid_input

      assert error.reason == [
               worktree_name: {"is not a safe path segment", [validation: :worktree_name_is_safe]}
             ]
    end
  end

  @spec changeset(params :: map()) :: Changeset.t()
  defp changeset(params), do: Runner.changeset(WorktreeResolve, params)
end
