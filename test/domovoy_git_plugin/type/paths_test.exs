defmodule DomovoyGitPlugin.Type.PathsTest do
  use ExUnit.Case, async: true

  alias DomovoyGitPlugin.Type.Paths, as: PathsType

  doctest PathsType

  describe "cast/2" do
    test "wraps a list of path strings" do
      paths = ["README.md", "lib/a.ex"]

      assert {:ok, ^paths} = PathsType.cast(paths, %{})
    end

    test "wraps an empty list" do
      assert {:ok, []} = PathsType.cast([], %{})
    end

    test "rejects a non-list and a list that holds a non-string" do
      assert :error = PathsType.cast("README.md", %{})
      assert :error = PathsType.cast(["README.md", 1], %{})
    end
  end

  describe "dump/1" do
    test "round-trips a list of paths" do
      paths = ["README.md"]

      assert {:ok, document} = PathsType.dump(paths)
      assert PathsType.load(document) == {:ok, paths}
    end
  end
end
