defmodule DomovoyGitPlugin.Runner.WorktreeNameTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.WorktreeName
  alias DomovoyGitPlugin.Test.NodeRunner

  doctest WorktreeName

  describe "run/2" do
    test "keeps the last segment of a branch name" do
      target_branch = Value.cast!("theoneandonlywoj/bro-19-add-metadata", StringType)

      assert %Value{value: "bro-19-add-metadata", type: StringType} =
               NodeRunner.run(build_node(%{}), [{"target_branch", target_branch}])
    end

    test "gives a branch name without a separator unchanged" do
      target_branch = Value.cast!("main", StringType)

      assert %Value{value: "main"} =
               NodeRunner.run(build_node(%{}), [{"target_branch", target_branch}])
    end

    test "a worktree_name argument overrides the derivation" do
      node = build_node(%{worktree_name: {"review", StringType}})
      target_branch = Value.cast!("feature/login", StringType)

      assert %Value{value: "review"} = NodeRunner.run(node, [{"target_branch", target_branch}])
    end

    test "refuses a node without a target_branch" do
      assert_raise ArgumentError, ~r/required_input.*target_branch/, fn ->
        Node.new(%{name: "worktree_name", runner: WorktreeName, type: StringType})
      end
    end

    test "rejects a blank target_branch before the runner runs" do
      target_branch = Value.cast!("", StringType)

      assert %Error{} =
               error = NodeRunner.run(build_node(%{}), [{"target_branch", target_branch}])

      assert error.type == :invalid_input
      assert [target_branch: _blank] = error.reason
    end

    test "does not judge the name it derives" do
      node = build_node(%{worktree_name: {"../escape", StringType}})
      target_branch = Value.cast!("main", StringType)

      assert %Value{value: "../escape"} = NodeRunner.run(node, [{"target_branch", target_branch}])
    end

    test "the runner that consumes the name refuses an unsafe one" do
      consumer =
        Node.new(%{
          name: "worktree_resolve",
          runner: DomovoyGitPlugin.Runner.WorktreeResolve,
          type: DomovoyGitPlugin.Type.Worktree,
          bind: %{worktree_name: {"worktree_name", StringType}}
        })

      worktree_name = Value.cast!("../escape", StringType)

      assert %Error{} = error = NodeRunner.run(consumer, [{"worktree_name", worktree_name}])
      assert error.type == :invalid_input
      assert [worktree_name: {"is not a safe path segment", _keys}] = error.reason
    end
  end

  @spec build_node(args :: map()) :: Node.t()
  defp build_node(args) do
    Node.new(%{
      name: "worktree_name",
      runner: WorktreeName,
      type: StringType,
      bind: %{target_branch: {"target_branch", StringType}},
      args: args
    })
  end
end
