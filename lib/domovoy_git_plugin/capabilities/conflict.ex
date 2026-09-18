defmodule DomovoyGitPlugin.Capabilities.Conflict do
  @moduledoc """
  Reads an unmerged path as a kind, index stages, and working-tree hunks.

  Porcelain names the kind. `git ls-files -u` names the stages Git still holds.
  Conflict markers in the working-tree file name the hunks an editor would
  change. The three views can disagree. After an edit without `git add`, the
  hunks may be empty while the stages still show an unmerged path. That is
  correct. Git has not accepted the path.

  The marker parser is total. It never raises. Unknown text around markers is
  dropped. A binary file, a missing file, or a file with no markers gives
  `hunks: []`.

  ## Examples

      iex> Conflict.kind("UU")
      :both_modified

      iex> Conflict.kind("AU")
      :added_by_us

      iex> Conflict.kind("XY")
      :unknown

      iex> Conflict.unmerged?("UU")
      true

      iex> Conflict.unmerged?(" M")
      false

      iex> Conflict.parse_stages("100644 abc 1\\tfile.txt\\n100644 def 2\\tfile.txt\\n")
      %{
        "file.txt" => %{
          base: %{mode: "100644", oid: "abc"},
          ours: %{mode: "100644", oid: "def"},
          theirs: nil
        }
      }

      iex> text = \"\"\"
      ...> <<<<<<< HEAD
      ...> ours line
      ...> =======
      ...> theirs line
      ...> >>>>>>> feature
      ...> \"\"\"
      iex> Conflict.parse_hunks(text)
      [
        %{
          ours: ["ours line"],
          theirs: ["theirs line"],
          ancestor_label: nil,
          ours_label: "HEAD",
          theirs_label: "feature"
        }
      ]
  """

  alias __MODULE__, as: Conflict

  @kinds [
    :both_modified,
    :both_added,
    :both_deleted,
    :added_by_us,
    :added_by_them,
    :deleted_by_us,
    :deleted_by_them,
    :unknown
  ]

  @typedoc "What porcelain reports for an unmerged path."
  @type kind() ::
          :both_modified
          | :both_added
          | :both_deleted
          | :added_by_us
          | :added_by_them
          | :deleted_by_us
          | :deleted_by_them
          | :unknown

  @typedoc "One index stage of an unmerged path."
  @type stage() :: %{mode: String.t(), oid: String.t()}

  @typedoc "The three index stages of an unmerged path. A missing side is `nil`."
  @type stages() :: %{base: stage() | nil, ours: stage() | nil, theirs: stage() | nil}

  @typedoc "One conflict-marker region in a working-tree file."
  @type hunk() :: %{
          ours: [String.t()],
          theirs: [String.t()],
          ancestor_label: String.t() | nil,
          ours_label: String.t() | nil,
          theirs_label: String.t() | nil
        }

  @typedoc "One unmerged path, with its kind, stages, and parsed hunks."
  @type t() :: %{
          path: String.t(),
          kind: kind(),
          code: String.t(),
          stages: stages(),
          hunks: [hunk()]
        }

  @empty_stages %{base: nil, ours: nil, theirs: nil}

  @doc """
  Returns `true` if `value` is a conflict kind that this module gives.
  """
  defguard is_kind(value) when value in @kinds

  @doc """
  Returns every conflict kind that this module gives.

  ## Examples

      iex> :both_modified in Conflict.kinds()
      true
  """
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  Returns the kind for a two-character porcelain code.

  An unmerged code that this module does not name gives `:unknown`. The caller
  still keeps the raw code.

  ## Examples

      iex> Conflict.kind("DD")
      :both_deleted

      iex> Conflict.kind("UA")
      :added_by_them
  """
  @spec kind(code :: String.t()) :: kind()
  def kind("UU"), do: :both_modified
  def kind("AA"), do: :both_added
  def kind("DD"), do: :both_deleted
  def kind("AU"), do: :added_by_us
  def kind("UA"), do: :added_by_them
  def kind("DU"), do: :deleted_by_us
  def kind("UD"), do: :deleted_by_them
  def kind(_code), do: :unknown

  @doc """
  Returns whether a porcelain code is an unmerged path.

  Git writes `U` in either XY position, or the pairs `AA` and `DD`.

  ## Examples

      iex> Conflict.unmerged?("DU")
      true

      iex> Conflict.unmerged?("AA")
      true

      iex> Conflict.unmerged?("M ")
      false
  """
  @spec unmerged?(code :: String.t() | map()) :: boolean()
  def unmerged?(%{code: code}) when is_binary(code), do: unmerged?(code)
  def unmerged?("AA"), do: true
  def unmerged?("DD"), do: true
  def unmerged?(code) when is_binary(code), do: String.contains?(code, "U")
  def unmerged?(_other), do: false

  @doc """
  Parses `git ls-files -u` output into stages keyed by path.

  Each line is `<mode> <oid> <stage>\\t<path>`. Stage `1` is `base`, stage `2`
  is `ours`, and stage `3` is `theirs`. A missing stage is `nil`. Lines this
  function does not understand are dropped.

  ## Examples

      iex> Conflict.parse_stages("")
      %{}

      iex> Conflict.parse_stages("100644 abc 3\\tonly-theirs.txt\\n")
      %{
        "only-theirs.txt" => %{
          base: nil,
          ours: nil,
          theirs: %{mode: "100644", oid: "abc"}
        }
      }
  """
  @spec parse_stages(output :: String.t()) :: %{optional(String.t()) => stages()}
  def parse_stages(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, &put_stage_line/2)
  end

  @doc """
  Parses conflict-marker hunks from working-tree text.

  The parser reads `<<<<<<<`, an optional `|||||||`, `=======`, and `>>>>>>>`.
  It keeps the labels and the ours and theirs lines. It does not keep ancestor
  lines. Incomplete regions and leftover text are dropped.

  ## Examples

      iex> Conflict.parse_hunks("no markers here\\n")
      []

      iex> text = \"\"\"
      ...> <<<<<<< ours
      ...> left
      ...> ||||||| ancestor
      ...> old
      ...> =======
      ...> right
      ...> >>>>>>> theirs
      ...> \"\"\"
      iex> Conflict.parse_hunks(text)
      [
        %{
          ours: ["left"],
          theirs: ["right"],
          ancestor_label: "ancestor",
          ours_label: "ours",
          theirs_label: "theirs"
        }
      ]
  """
  @spec parse_hunks(text :: String.t()) :: [hunk()]
  def parse_hunks(text) when is_binary(text) do
    text |> String.split("\n") |> seek([])
  end

  @doc """
  Returns the hunks of the working-tree file at `path`.

  A missing file, a binary file, or a file with no markers gives `[]`. This
  function does not fail.
  """
  @spec hunks_from_file(path :: String.t()) :: [hunk()]
  def hunks_from_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} -> if text?(contents), do: parse_hunks(contents), else: []
      {:error, _reason} -> []
    end
  end

  @doc """
  Builds one conflict from a porcelain entry, its stages, and a working-tree
  directory.

  Missing stages give `nil` on that side. A missing or binary working-tree file
  gives `hunks: []`.
  """
  @spec conflict(
          entry :: %{path: String.t(), code: String.t()},
          stages :: stages() | nil,
          working_directory :: String.t()
        ) :: Conflict.t()
  def conflict(%{path: path, code: code}, stages, working_directory)
      when is_binary(path) and is_binary(code) and is_binary(working_directory) do
    %{
      path: path,
      kind: kind(code),
      code: code,
      stages: stages || @empty_stages,
      hunks: hunks_from_file(Path.join(working_directory, path))
    }
  end

  @doc """
  Returns the empty stages map, with each side `nil`.
  """
  @spec empty_stages() :: stages()
  def empty_stages, do: @empty_stages

  @spec put_stage_line(line :: String.t(), acc :: %{optional(String.t()) => stages()}) ::
          %{optional(String.t()) => stages()}
  defp put_stage_line(line, acc) do
    case parse_stage_line(line) do
      {:ok, path, side, stage} ->
        current = Map.get(acc, path, @empty_stages)
        Map.put(acc, path, Map.put(current, side, stage))

      :error ->
        acc
    end
  end

  @spec parse_stage_line(line :: String.t()) ::
          {:ok, String.t(), :base | :ours | :theirs, stage()} | :error
  defp parse_stage_line(line) do
    case String.split(line, "\t", parts: 2) do
      [meta, path] when path != "" -> parse_stage_meta(meta, path)
      _other -> :error
    end
  end

  @spec parse_stage_meta(meta :: String.t(), path :: String.t()) ::
          {:ok, String.t(), :base | :ours | :theirs, stage()} | :error
  defp parse_stage_meta(meta, path) do
    case String.split(meta, " ", parts: 3) do
      [mode, oid, stage] when mode != "" and oid != "" ->
        put_stage_side(path, mode, oid, stage)

      _other ->
        :error
    end
  end

  @spec put_stage_side(
          path :: String.t(),
          mode :: String.t(),
          oid :: String.t(),
          stage :: String.t()
        ) :: {:ok, String.t(), :base | :ours | :theirs, stage()} | :error
  defp put_stage_side(path, mode, oid, stage) do
    case stage_side(stage) do
      nil -> :error
      side -> {:ok, path, side, %{mode: mode, oid: oid}}
    end
  end

  @spec stage_side(stage :: String.t()) :: :base | :ours | :theirs | nil
  defp stage_side("1"), do: :base
  defp stage_side("2"), do: :ours
  defp stage_side("3"), do: :theirs
  defp stage_side(_stage), do: nil

  @spec text?(contents :: String.t()) :: boolean()
  defp text?(contents), do: String.valid?(contents) and not String.contains?(contents, <<0>>)

  @spec seek(lines :: [String.t()], hunks :: [hunk()]) :: [hunk()]
  defp seek([], hunks), do: Enum.reverse(hunks)

  defp seek([line | rest], hunks) do
    case marker_kind(line) do
      {:start, ours_label} -> read_ours(rest, new_hunk(ours_label), hunks)
      _other -> seek(rest, hunks)
    end
  end

  @spec read_ours(lines :: [String.t()], hunk :: hunk(), hunks :: [hunk()]) :: [hunk()]
  defp read_ours([], _hunk, hunks), do: Enum.reverse(hunks)

  defp read_ours([line | rest], hunk, hunks) do
    case marker_kind(line) do
      {:ancestor, ancestor_label} ->
        skip_ancestor(rest, %{hunk | ancestor_label: ancestor_label}, hunks)

      {:separator, _label} ->
        read_theirs(rest, hunk, hunks)

      {:start, ours_label} ->
        read_ours(rest, new_hunk(ours_label), hunks)

      {:end, _label} ->
        seek(rest, hunks)

      :content ->
        read_ours(rest, %{hunk | ours: [line | hunk.ours]}, hunks)
    end
  end

  @spec skip_ancestor(lines :: [String.t()], hunk :: hunk(), hunks :: [hunk()]) :: [hunk()]
  defp skip_ancestor([], _hunk, hunks), do: Enum.reverse(hunks)

  defp skip_ancestor([line | rest], hunk, hunks) do
    case marker_kind(line) do
      {:separator, _label} -> read_theirs(rest, hunk, hunks)
      {:start, ours_label} -> read_ours(rest, new_hunk(ours_label), hunks)
      {:end, _label} -> seek(rest, hunks)
      _other -> skip_ancestor(rest, hunk, hunks)
    end
  end

  @spec read_theirs(lines :: [String.t()], hunk :: hunk(), hunks :: [hunk()]) :: [hunk()]
  defp read_theirs([], _hunk, hunks), do: Enum.reverse(hunks)

  defp read_theirs([line | rest], hunk, hunks) do
    case marker_kind(line) do
      {:end, theirs_label} ->
        seek(rest, [finish_hunk(hunk, theirs_label) | hunks])

      {:start, ours_label} ->
        read_ours(rest, new_hunk(ours_label), hunks)

      _other ->
        read_theirs(rest, %{hunk | theirs: [line | hunk.theirs]}, hunks)
    end
  end

  @spec marker_kind(line :: String.t()) ::
          {:start, String.t() | nil}
          | {:ancestor, String.t() | nil}
          | {:separator, String.t() | nil}
          | {:end, String.t() | nil}
          | :content
  defp marker_kind(line) do
    cond do
      String.starts_with?(line, "<<<<<<<") -> {:start, marker_label(line)}
      String.starts_with?(line, "|||||||") -> {:ancestor, marker_label(line)}
      String.starts_with?(line, "=======") -> {:separator, marker_label(line)}
      String.starts_with?(line, ">>>>>>>") -> {:end, marker_label(line)}
      true -> :content
    end
  end

  @spec marker_label(line :: String.t()) :: String.t() | nil
  defp marker_label(line) do
    case line |> String.slice(7..-1//1) |> String.trim() do
      "" -> nil
      label -> label
    end
  end

  @spec new_hunk(ours_label :: String.t() | nil) :: hunk()
  defp new_hunk(ours_label) do
    %{ours: [], theirs: [], ancestor_label: nil, ours_label: ours_label, theirs_label: nil}
  end

  @spec finish_hunk(hunk :: hunk(), theirs_label :: String.t() | nil) :: hunk()
  defp finish_hunk(hunk, theirs_label) do
    %{
      ours: Enum.reverse(hunk.ours),
      theirs: Enum.reverse(hunk.theirs),
      ancestor_label: hunk.ancestor_label,
      ours_label: hunk.ours_label,
      theirs_label: theirs_label
    }
  end
end
