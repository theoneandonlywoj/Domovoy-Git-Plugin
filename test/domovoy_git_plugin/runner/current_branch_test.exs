defmodule DomovoyGitPlugin.Runner.CurrentBranchTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.CurrentBranch
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository

  setup do
    repository = Repository.create!(remote?: false)
    on_exit(fn -> File.rm_rf(repository.parent) end)

    {:ok, repository: repository}
  end

  describe "run/2" do
    test "returns the branch of the working_directory argument", %{repository: repository} do
      node = literal_node(repository.root)

      assert %Value{value: "main", type: StringType} = NodeRunner.run(node, [])
    end

    test "returns the branch of a directory that a bound node gives", %{
      repository: repository
    } do
      Repository.git!(["-C", repository.root, "checkout", "-q", "-b", "feature/login"])

      node = bound_node("checkout")
      checkout = Value.cast!(repository.root, DirectoryType)

      assert %Value{value: "feature/login"} = NodeRunner.run(node, [{"checkout", checkout}])
    end

    test "reports a detached HEAD as the literal HEAD", %{repository: repository} do
      head = repository.root |> detached_head() |> String.trim()
      Repository.git!(["-C", repository.root, "checkout", "-q", "--detach", head])

      assert %Value{value: "HEAD"} = NodeRunner.run(literal_node(repository.root), [])
    end

    test "returns a contextual error when the directory is not a repository" do
      outside = outside_directory()

      assert %Error{} = error = NodeRunner.run(literal_node(outside), [])
      assert error.type == :git_command_failed
      assert error.metadata[:command] == ["git", "rev-parse", "--abbrev-ref", "HEAD"]
      assert error.metadata[:node_name] == "current_branch"
      assert error.metadata[:field_name] == :working_directory
      refute Map.has_key?(error.metadata, :node_input)
    end

    test "rejects a directory literal that does not exist" do
      node = literal_node("/no/such/directory")

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :invalid_input
      assert [working_directory: _cast] = error.reason
    end

    test "rejects a bound value of another type before the runner runs" do
      node = bound_node("checkout")
      checkout = Value.cast!("main", StringType)

      assert %Error{} = error = NodeRunner.run(node, [{"checkout", checkout}])
      assert error.type == :binding_cast_failed
      assert error.reason.field == :working_directory
    end

    test "is never reached when a bound node failed" do
      node = bound_node("checkout")
      upstream = Error.new(%{type: :upstream_failed})

      assert %Error{} = error = NodeRunner.run(node, [{"checkout", upstream}])
      assert error.type == :binding_source_not_found
    end
  end

  @spec literal_node(directory :: String.t()) :: Node.t()
  defp literal_node(directory) do
    Node.new(%{
      name: "current_branch",
      runner: CurrentBranch,
      type: StringType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end

  @spec bound_node(source :: Node.name()) :: Node.t()
  defp bound_node(source) do
    Node.new(%{
      name: "current_branch",
      runner: CurrentBranch,
      type: StringType,
      bind: %{working_directory: {source, DirectoryType}}
    })
  end

  @spec outside_directory() :: String.t()
  defp outside_directory do
    outside = Path.join(System.tmp_dir!(), "domovoy-plain-#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf(outside) end)

    outside
  end

  @spec detached_head(String.t()) :: String.t()
  defp detached_head(root), do: Repository.git!(["-C", root, "rev-parse", "HEAD"])
end
