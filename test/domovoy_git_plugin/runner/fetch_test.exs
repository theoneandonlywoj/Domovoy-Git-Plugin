defmodule DomovoyGitPlugin.Runner.FetchTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Value
  alias DomovoyGitPlugin.Runner.Fetch
  alias DomovoyGitPlugin.Test.NodeRunner
  alias DomovoyGitPlugin.Test.Repository
  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "run/2" do
    test "fetches origin and returns a snapshot" do
      repository = Repository.create!(remote?: true)
      on_exit(fn -> File.rm_rf(repository.parent) end)

      assert %Value{value: state, type: RepoStateType} =
               NodeRunner.run(build_node(repository.root), [])

      assert state.current_branch == "main"
      assert state.upstream_branch == "origin/main"
      assert state.operation == :idle
    end
  end

  @spec build_node(directory :: String.t()) :: Node.t()
  defp build_node(directory) do
    Node.new(%{
      name: "fetch",
      runner: Fetch,
      type: RepoStateType,
      args: %{working_directory: {directory, DirectoryType}}
    })
  end
end
