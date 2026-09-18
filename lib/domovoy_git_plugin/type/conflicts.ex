defmodule DomovoyGitPlugin.Type.Conflicts do
  @moduledoc """
  `DomovoyCore.Type` for the unmerged paths of a checkout.

  The raw value holds one map for each unmerged path. Each map holds the path,
  the porcelain kind, the raw two-character code, the index stages, and the
  conflict-marker hunks of the working-tree file.
  `DomovoyGitPlugin.Capabilities.Conflict` makes the maps.

  An empty list is correct. It means that the index has no unmerged paths.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> conflicts = [
      ...>   %{
      ...>     path: "lib/a.ex",
      ...>     kind: :both_modified,
      ...>     code: "UU",
      ...>     stages: %{
      ...>       base: %{mode: "100644", oid: "aaa"},
      ...>       ours: %{mode: "100644", oid: "bbb"},
      ...>       theirs: %{mode: "100644", oid: "ccc"}
      ...>     },
      ...>     hunks: [
      ...>       %{
      ...>         ours: ["left"],
      ...>         theirs: ["right"],
      ...>         ancestor_label: nil,
      ...>         ours_label: "HEAD",
      ...>         theirs_label: "feature"
      ...>       }
      ...>     ]
      ...>   }
      ...> ]
      iex> {:ok, document} = DomovoyGitPlugin.Type.Conflicts.dump(conflicts)
      iex> hd(document)["kind"]
      "both_modified"
      iex> DomovoyGitPlugin.Type.Conflicts.load(document)
      {:ok, conflicts}
  """

  use DomovoyCore.Type

  alias DomovoyGitPlugin.Capabilities.Conflict

  require Conflict

  defguardp is_conflict(path, kind, code)
            when is_binary(path) and path != "" and Conflict.is_kind(kind) and is_binary(code)

  @typedoc "One unmerged path, with its kind, stages, and hunks."
  @type conflict() :: Conflict.t()

  @impl Ecto.Type
  def type, do: {:array, :map}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw_value, _metadata) when is_list(raw_value) do
    if Enum.all?(raw_value, &conflict?/1) do
      {:ok, raw_value}
    else
      :error
    end
  end

  def cast(_raw, _metadata), do: :error

  @conflict_keys [:path, :kind, :code, :stages, :hunks]
  @stage_keys [:base, :ours, :theirs]
  @side_keys [:mode, :oid]
  @hunk_keys [:ours, :theirs, :ancestor_label, :ours_label, :theirs_label]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, [conflict()]} | :error
  def load(document) when is_list(document) do
    with {:ok, conflicts} <- DomovoyCore.Type.load_each(document, &load_conflict/1) do
      cast(conflicts)
    end
  end

  def load(_document), do: :error

  @spec conflict?(any()) :: boolean()
  defp conflict?(%{path: path, kind: kind, code: code, stages: stages, hunks: hunks})
       when is_conflict(path, kind, code) and is_list(hunks) do
    stages?(stages) and Enum.all?(hunks, &hunk?/1)
  end

  defp conflict?(_other), do: false

  @spec stages?(any()) :: boolean()
  defp stages?(%{base: base, ours: ours, theirs: theirs}),
    do: stage?(base) and stage?(ours) and stage?(theirs)

  defp stages?(_other), do: false

  @spec stage?(any()) :: boolean()
  defp stage?(nil), do: true

  defp stage?(%{mode: mode, oid: oid})
       when is_binary(mode) and mode != "" and is_binary(oid) and oid != "",
       do: true

  defp stage?(_other), do: false

  @spec hunk?(any()) :: boolean()
  defp hunk?(%{
         ours: ours,
         theirs: theirs,
         ancestor_label: ancestor_label,
         ours_label: ours_label,
         theirs_label: theirs_label
       })
       when is_list(ours) and is_list(theirs) and
              (is_binary(ancestor_label) or is_nil(ancestor_label)) and
              (is_binary(ours_label) or is_nil(ours_label)) and
              (is_binary(theirs_label) or is_nil(theirs_label)) do
    Enum.all?(ours, &is_binary/1) and Enum.all?(theirs, &is_binary/1)
  end

  defp hunk?(_other), do: false

  @spec load_conflict(document :: any()) :: {:ok, conflict()} | :error
  defp load_conflict(%{"kind" => kind, "stages" => stages, "hunks" => hunks} = document) do
    with {:ok, kind} <- load_kind(kind),
         {:ok, stages} <- load_stages(stages),
         {:ok, hunks} <- DomovoyCore.Type.load_each(hunks, &load_hunk/1) do
      {:ok,
       document
       |> DomovoyCore.Type.atom_keys(@conflict_keys)
       |> Map.merge(%{kind: kind, stages: stages, hunks: hunks})}
    end
  end

  defp load_conflict(_document), do: :error

  @spec load_kind(document :: any()) :: {:ok, Conflict.kind()} | :error
  defp load_kind(document) when is_binary(document) do
    case Enum.find(Conflict.kinds(), &(Atom.to_string(&1) == document)) do
      nil -> :error
      kind -> {:ok, kind}
    end
  end

  defp load_kind(_document), do: :error

  @spec load_stages(document :: any()) :: {:ok, Conflict.stages()} | :error
  defp load_stages(document) when is_map(document) do
    stages = DomovoyCore.Type.atom_keys(document, @stage_keys)

    with {:ok, base} <- load_stage(Map.get(stages, :base)),
         {:ok, ours} <- load_stage(Map.get(stages, :ours)),
         {:ok, theirs} <- load_stage(Map.get(stages, :theirs)) do
      {:ok, %{base: base, ours: ours, theirs: theirs}}
    end
  end

  defp load_stages(_document), do: :error

  @spec load_stage(document :: any()) :: {:ok, Conflict.stage() | nil} | :error
  defp load_stage(nil), do: {:ok, nil}

  defp load_stage(document) when is_map(document) do
    stage = DomovoyCore.Type.atom_keys(document, @side_keys)

    case stage do
      %{mode: mode, oid: oid} when is_binary(mode) and is_binary(oid) ->
        {:ok, %{mode: mode, oid: oid}}

      _other ->
        :error
    end
  end

  defp load_stage(_document), do: :error

  @spec load_hunk(document :: any()) :: {:ok, Conflict.hunk()} | :error
  defp load_hunk(document) when is_map(document),
    do: {:ok, DomovoyCore.Type.atom_keys(document, @hunk_keys)}

  defp load_hunk(_document), do: :error
end
