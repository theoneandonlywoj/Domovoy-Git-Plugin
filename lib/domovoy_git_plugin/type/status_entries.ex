defmodule DomovoyGitPlugin.Type.StatusEntries do
  @moduledoc """
  `DomovoyCore.Type` for a parsed `git status --porcelain` listing.

  The raw value holds one entry for each changed path. Each entry holds the
  path, the state of the index, the state of the working tree, and the raw
  two-character code of Git. `DomovoyGitPlugin.Capabilities.StatusEntry`
  makes the entries and names each state.

  The two states say what a code such as `" M"` or `"A "` means. A consumer
  reads `entry.index` and `entry.worktree`. It does not compare characters. The
  code stays in `entry.code` for a consumer that needs the raw text.

  An empty list is correct. It means that the working tree is clean.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> entries = [%{path: "lib/a.ex", code: " M", index: :unmodified, worktree: :modified}]
      iex> {:ok, document} = DomovoyGitPlugin.Type.StatusEntries.dump(entries)
      iex> document
      [%{"path" => "lib/a.ex", "code" => " M", "index" => "unmodified", "worktree" => "modified"}]
      iex> DomovoyGitPlugin.Type.StatusEntries.load(document)
      {:ok, entries}
  """

  use DomovoyCore.Type

  alias DomovoyGitPlugin.Capabilities.StatusEntry

  require StatusEntry

  defguardp is_entry(path, code, index, worktree)
            when is_binary(path) and path != "" and is_binary(code) and
                   StatusEntry.is_state(index) and StatusEntry.is_state(worktree)

  @typedoc "One changed path, with the state of each side and the raw code."
  @type entry() :: StatusEntry.t()

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw_value, _metadata) when is_list(raw_value) do
    if Enum.all?(raw_value, &entry?/1) do
      {:ok, raw_value}
    else
      :error
    end
  end

  def cast(_raw, _metadata), do: :error

  @spec entry?(any()) :: boolean()
  defp entry?(%{path: path, code: code, index: index, worktree: worktree})
       when is_entry(path, code, index, worktree),
       do: true

  defp entry?(_other), do: false

  @entry_keys [:path, :code, :index, :worktree]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, [entry()]} | :error
  def load(document) when is_list(document) do
    with {:ok, entries} <- DomovoyCore.Type.load_each(document, &load_entry/1) do
      cast(entries)
    end
  end

  def load(_document), do: :error

  @spec load_entry(document :: any()) :: {:ok, entry()} | :error
  defp load_entry(%{"index" => index, "worktree" => worktree} = document) do
    with {:ok, index} <- load_state(index),
         {:ok, worktree} <- load_state(worktree) do
      {:ok,
       document
       |> DomovoyCore.Type.atom_keys(@entry_keys)
       |> Map.merge(%{index: index, worktree: worktree})}
    end
  end

  defp load_entry(_document), do: :error

  @spec load_state(document :: any()) :: {:ok, StatusEntry.state()} | :error
  defp load_state(document) when is_binary(document) do
    case Enum.find(StatusEntry.states(), &(Atom.to_string(&1) == document)) do
      nil -> :error
      state -> {:ok, state}
    end
  end

  defp load_state(_document), do: :error
end
