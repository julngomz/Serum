defmodule Serum.Error do
  @moduledoc "Defines a struct describing error information."

  alias Serum.Error.Format

  defstruct [:message, :caused_by, :file, :line]

  @type t :: %__MODULE__{
          message: Format.t(),
          caused_by: [t()],
          file: Serum.File.t() | nil,
          line: integer() | nil
        }

  @doc "Performs pre-order traversal over the given error."
  @spec prewalk(t(), (t() -> t())) :: t()
  def prewalk(error, fun) do
    %__MODULE__{caused_by: errors} = error2 = fun.(error)

    %__MODULE__{error2 | caused_by: Enum.map(errors, &prewalk(&1, fun))}
  end

  defimpl String.Chars do
    alias Serum.Error.Format

    def to_string(error) do
      error
      |> Format.format_text(0)
      |> IO.ANSI.format(false)
      |> IO.iodata_to_binary()
    end
  end

  defimpl Format do
    @type line :: {binary(), integer()}

    def format_text(error, indent) do
      contents = [
        format_file_text(error.file, error.line),
        Format.format_text(error.message, 0),
        format_source_lines(error.file, error.line)
      ]

      head = indented(contents, indent)
      children = Enum.map(error.caused_by, &Format.format_text(&1, indent + 1))

      Enum.intersperse([head | children], ?\n)
    end

    @spec format_file_text(Serum.File.t() | nil, integer()) :: binary()
    defp format_file_text(maybe_file, line)
    defp format_file_text(nil, _line), do: ""

    defp format_file_text(%Serum.File{src: src}, line) do
      case Exception.format_file_line(src, line) do
        "" -> ""
        str when is_binary(str) -> [str, ?\s]
      end
    end

    @spec format_source_lines(Serum.File.t(), integer() | nil) :: IO.ANSI.ansidata()
    defp format_source_lines(file, line)
    defp format_source_lines(nil, _line), do: ""
    defp format_source_lines(%Serum.File{src: nil}, _line), do: ""
    defp format_source_lines(%Serum.File{in_data: nil}, _line), do: ""
    defp format_source_lines(_file, nil), do: ""
    defp format_source_lines(_file, line) when line < 1, do: ""

    defp format_source_lines(%Serum.File{in_data: in_data}, line) do
      {prev, current, next} = extract_lines(in_data, line)

      gutter_width =
        [current | next]
        |> Enum.map(&elem(&1, 1))
        |> Enum.max()
        |> to_string()
        |> String.length()

      [
        ?\n,
        format_other_lines(prev, gutter_width),
        format_current_line(current, gutter_width),
        format_other_lines(next, gutter_width)
      ]
    end

    @spec extract_lines(binary(), integer()) :: {[line()], line(), [line()]}
    defp extract_lines(data, line) do
      {:ok, string_io} = StringIO.open(data)
      stream = string_io |> IO.stream(:line) |> Stream.map(&String.trim_trailing/1)

      [current | prev] =
        stream
        |> Stream.with_index(1)
        |> Stream.take(line)
        |> Enum.reverse()
        |> Enum.take(4)

      next = stream |> Stream.with_index(line + 1) |> Enum.take(3)
      {:ok, _} = StringIO.close(string_io)

      {Enum.reverse(prev), current, next}
    end

    @spec format_current_line(line(), integer()) :: IO.ANSI.ansidata()
    defp format_current_line({str, line}, gutter_width) do
      [
        [:bright, :yellow],
        String.pad_leading(to_string(line), gutter_width),
        [:normal, :light_black, " | ", :bright, :yellow],
        [str, :reset, ?\n]
      ]
    end

    @spec format_other_lines([line()], integer()) :: IO.ANSI.ansidata()
    defp format_other_lines(lines, gutter_width) do
      Enum.map(lines, fn {str, line} ->
        [
          :light_black,
          String.pad_leading(to_string(line), gutter_width),
          [" | ", :reset],
          [str, :reset, ?\n]
        ]
      end)
    end

    @spec indented(IO.ANSI.ansidata(), non_neg_integer()) :: IO.ANSI.ansidata()
    defp indented(str, indent)
    defp indented(str, 0), do: str

    defp indented(str, indent) do
      rest_indent = List.duplicate("  ", indent)

      [line | lines] =
        str
        |> IO.ANSI.format_fragment()
        |> IO.iodata_to_binary()
        |> String.split(~r/\r?\n/)

      [
        [List.duplicate("  ", indent - 1), :red, "- ", :reset, line],
        case lines do
          [] -> ""
          lines -> [?\n, rest_indent, Enum.intersperse(lines, [?\n, rest_indent])]
        end
      ]
    end
  end
end
