defmodule DomovoyGitPlugin.Runner.BranchDiffTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.BranchDiff
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.Diff, as: DiffType

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    Repository.git!(["-C", repository.root, "checkout", "-q", "-b", "feature"])
    File.write!(Path.join(repository.root, "feature.txt"), "feature\n")
    Repository.git!(["-C", repository.root, "add", "feature.txt"])
    Repository.git!(["-C", repository.root, "commit", "-qm", "feature work"])
    Repository.git!(["-C", repository.root, "checkout", "-q", "main"])

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "diffs two refs given as arguments", %{repository: repository} do
      node = build_node(repository, %{base_branch: "main", target_branch: "feature"})

      assert %Value{value: [file_diff], type: DiffType} = NodeRunner.run(node, [])
      assert file_diff.file == "feature.txt"
      assert [%{added_lines: ["feature"]}] = file_diff.hunks
    end

    test "returns an empty diff when the refs are identical", %{repository: repository} do
      node = build_node(repository, %{base_branch: "main", target_branch: "main"})

      assert %Value{value: []} = NodeRunner.run(node, [])
    end

    test "takes a ref from a bound node", %{repository: repository} do
      node =
        build_node(repository, %{base_branch: "main"}, %{
          target_branch: {"computed_branch", StringType}
        })

      computed_branch = Value.cast!("feature", StringType)

      assert %Value{value: [%{file: "feature.txt"}]} =
               NodeRunner.run(node, [{"computed_branch", computed_branch}])
    end

    test "refuses a node that supplies neither ref", %{repository: repository} do
      assert_raise ArgumentError, ~r/required_input.*target_branch/, fn ->
        build_node(repository, %{base_branch: "main"})
      end
    end

    test "rejects a blank ref before the runner runs", %{repository: repository} do
      node = build_node(repository, %{base_branch: "main", target_branch: " "})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :invalid_input
      assert [target_branch: {"can't be blank", _keys}] = error.reason
    end

    test "rejects a bound value of another type before the runner runs", %{
      repository: repository
    } do
      node =
        build_node(repository, %{base_branch: "main"}, %{
          target_branch: {"computed_branch", StringType}
        })

      computed_branch = Value.cast!([], DiffType)

      assert %Error{} = error = NodeRunner.run(node, [{"computed_branch", computed_branch}])
      assert error.type == :binding_cast_failed
    end

    test "reports an unknown ref as a Git command failure", %{repository: repository} do
      node = build_node(repository, %{base_branch: "main", target_branch: "does-not-exist"})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :git_command_failed
      assert error.metadata[:node_name] == "branch_diff"
    end
  end

  @spec build_node(repository :: Repository.t(), literals :: map(), bind :: map()) :: Node.t()
  defp build_node(repository, literals, bind \\ %{}) do
    args =
      literals
      |> Map.new(fn {field, value} -> {field, {value, StringType}} end)
      |> Map.put(:working_directory, {repository.root, DirectoryType})

    Node.new(%{name: "branch_diff", runner: BranchDiff, type: DiffType, args: args, bind: bind})
  end
end
