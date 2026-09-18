defmodule DomovoyGitPlugin.Validator.CommitMessagePresentTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.Commit
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType
  alias DomovoyGitPlugin.Validator.CommitMessagePresent

  doctest CommitMessagePresent

  @context %Context{}

  describe "validate/2" do
    test "leaves the changeset valid for a non-blank message" do
      changeset = Runner.changeset(Commit, %{message: "Add the snapshot"})

      assert CommitMessagePresent.validate(changeset, @context) == changeset
    end

    test "rejects a blank message" do
      checked =
        Commit
        |> Runner.changeset(%{message: "   "})
        |> CommitMessagePresent.validate(@context)

      refute checked.valid?
      assert checked.errors == [message: {"can't be blank", [validation: :required]}]
    end

    test "stops the node before the runner" do
      node =
        Node.new(%{
          name: "commit",
          runner: Commit,
          type: RepoStateType,
          bind: %{message: {"message", StringType}}
        })

      message = Value.cast!("   ", StringType)

      assert %Error{} = error = NodeRunner.run(node, [{"message", message}])
      assert error.type == :invalid_input
      assert error.reason == [message: {"can't be blank", [validation: :required]}]
    end
  end
end
