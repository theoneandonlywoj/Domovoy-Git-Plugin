defmodule DomovoyGitPlugin.Type.Diff do
  @moduledoc """
  `DomovoyCore.Type` for parsed `git diff` output.

  The raw value is the list that
  `DomovoyGitPlugin.Capabilities.DiffParser.parse/1` returns. The list holds
  one entry for each file, and each entry holds its hunks. An empty list is
  correct. It means that the two compared trees are the same.

  Every Git capability that makes a diff casts through this type. This includes
  the tracked changes, the untracked files, the branch comparisons and the
  worktree comparisons. Therefore a node that reads a diff does not need to know
  which capability made the diff.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> diff = [
      ...>   %{
      ...>     file: "lib/a.ex",
      ...>     hunks: [%{added_lines: ["+b"], removed_lines: [], header: "@@ -1 +1,2 @@"}]
      ...>   }
      ...> ]
      iex> {:ok, document} = DomovoyGitPlugin.Type.Diff.dump(diff)
      iex> hd(document)["file"]
      "lib/a.ex"
      iex> DomovoyGitPlugin.Type.Diff.load(document)
      {:ok, diff}
  """

  use DomovoyCore.Type

  alias DomovoyGitPlugin.Capabilities.DiffParser

  defguardp is_file_diff(file, hunks) when is_binary(file) and is_list(hunks)

  defguardp is_hunk(added_lines, removed_lines, header)
            when is_list(added_lines) and is_list(removed_lines) and is_binary(header)

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw_value, _metadata) when is_list(raw_value) do
    if Enum.all?(raw_value, &file_diff?/1) do
      {:ok, raw_value}
    else
      :error
    end
  end

  def cast(_raw, _metadata), do: :error

  @spec file_diff?(any()) :: boolean()
  defp file_diff?(%{file: file, hunks: hunks}) when is_file_diff(file, hunks),
    do: Enum.all?(hunks, &hunk?/1)

  defp file_diff?(_other), do: false

  @spec hunk?(any()) :: boolean()
  defp hunk?(%{added_lines: added_lines, removed_lines: removed_lines, header: header})
       when is_hunk(added_lines, removed_lines, header),
       do: true

  defp hunk?(_other), do: false

  @file_keys [:file, :hunks]
  @hunk_keys [:added_lines, :removed_lines, :header]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, [DiffParser.file_diff()]} | :error
  def load(document) when is_list(document) do
    with {:ok, files} <- DomovoyCore.Type.load_each(document, &load_file/1) do
      cast(files)
    end
  end

  def load(_document), do: :error

  @spec load_file(document :: any()) :: {:ok, DiffParser.file_diff()} | :error
  defp load_file(%{"hunks" => hunks} = document) do
    with {:ok, hunks} <- DomovoyCore.Type.load_each(hunks, &load_hunk/1) do
      {:ok, document |> DomovoyCore.Type.atom_keys(@file_keys) |> Map.put(:hunks, hunks)}
    end
  end

  defp load_file(_document), do: :error

  @spec load_hunk(document :: any()) :: {:ok, DiffParser.hunk()} | :error
  defp load_hunk(document) when is_map(document),
    do: {:ok, DomovoyCore.Type.atom_keys(document, @hunk_keys)}

  defp load_hunk(_document), do: :error
end
