defmodule DomovoyGitPlugin.Validator.DiffRefsPresentTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyGitPlugin.Runner.BranchDiff
  alias DomovoyGitPlugin.Validator.DiffRefsPresent
  alias Ecto.Changeset

  doctest DiffRefsPresent

  @context %Context{}
  @types %{base_branch: :string, target_branch: :string}

  describe "validate/2" do
    test "leaves the changeset valid when both refs are present" do
      changeset = Runner.changeset(BranchDiff, %{base_branch: "main", target_branch: "feature"})

      assert DiffRefsPresent.validate(changeset, @context) == changeset
    end

    test "names the missing base_branch" do
      checked =
        %{target_branch: "feature"} |> bare_changeset() |> DiffRefsPresent.validate(@context)

      assert checked.errors == [base_branch: {"can't be blank", [validation: :required]}]
    end

    test "names a blank target_branch" do
      checked =
        %{base_branch: "main", target_branch: "  "}
        |> bare_changeset()
        |> DiffRefsPresent.validate(@context)

      assert checked.errors == [target_branch: {"can't be blank", [validation: :required]}]
    end

    test "names both refs when both are missing" do
      checked = %{} |> bare_changeset() |> DiffRefsPresent.validate(@context)

      assert Keyword.keys(checked.errors) |> Enum.sort() == [:base_branch, :target_branch]
    end

    test "adds no second error to a ref the schema already rejected" do
      changeset = Runner.changeset(BranchDiff, %{base_branch: "main"})
      assert [target_branch: _blank] = changeset.errors

      assert DiffRefsPresent.validate(changeset, @context) == changeset
    end
  end

  @spec bare_changeset(params :: map()) :: Changeset.t()
  defp bare_changeset(params),
    do: Changeset.cast({%{}, @types}, params, Map.keys(@types))
end
