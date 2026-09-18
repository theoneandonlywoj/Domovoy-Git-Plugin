defmodule DomovoyGitPlugin.Type.RepoStateTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.RepoState, as: RepoStateType

  describe "cast/2" do
    test "wraps a main checkout snapshot" do
      state = state(%{})

      assert {:ok, ^state} = RepoStateType.cast(state, %{})
    end

    test "accepts a detached worktree with no upstream" do
      state =
        state(%{
          checkout: :worktree,
          worktree_name: "feature",
          base_branch: "main",
          current_branch: nil,
          detached?: true,
          upstream_branch: nil,
          ahead: nil,
          behind: nil
        })

      assert {:ok, ^state} = RepoStateType.cast(state, %{})
    end

    test "accepts empty status and conflicts" do
      assert {:ok, _} = RepoStateType.cast(state(%{status: [], conflicts: []}), %{})
    end

    test "rejects a blank path, a bad checkout, or a negative count" do
      assert :error = RepoStateType.cast(state(%{path: ""}), %{})
      assert :error = RepoStateType.cast(state(%{checkout: :other}), %{})
      assert :error = RepoStateType.cast(state(%{ahead: -1}), %{})
      assert :error = RepoStateType.cast(state(%{operation: :stashing}), %{})
    end

    test "rejects a map missing a key" do
      assert :error = RepoStateType.cast(%{path: "/repo"}, %{})
      assert :error = RepoStateType.cast("main", %{})
    end
  end

  describe "dump/1" do
    test "round-trips a snapshot through a document" do
      state =
        state(%{
          dirty?: true,
          status: [%{path: "README.md", code: " M", index: :unmodified, worktree: :modified}],
          conflicts: [
            %{
              path: "lib/a.ex",
              kind: :both_modified,
              code: "UU",
              stages: %{
                base: %{mode: "100644", oid: "aaa"},
                ours: %{mode: "100644", oid: "bbb"},
                theirs: %{mode: "100644", oid: "ccc"}
              },
              hunks: []
            }
          ]
        })

      assert {:ok, document} = RepoStateType.dump(state)
      assert document["checkout"] == "main"
      assert document["operation"] == "idle"
      assert RepoStateType.load(document) == {:ok, state}
    end
  end

  @spec state(map()) :: map()
  defp state(overrides) do
    Map.merge(
      %{
        path: "/repo",
        repo_root: "/repo",
        checkout: :main,
        worktree_name: nil,
        base_branch: nil,
        current_branch: "main",
        detached?: false,
        upstream_branch: "origin/main",
        ahead: 0,
        behind: 0,
        dirty?: false,
        operation: :idle,
        status: [],
        conflicts: []
      },
      overrides
    )
  end
end
