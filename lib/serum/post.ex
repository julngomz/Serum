defmodule Serum.Post do
  @moduledoc """
  Defines a struct representing a blog post page.

  ## Fields

  * `file`: Source file
  * `type`: Type of source file
  * `title`: Post title
  * `date`: A `DateTime` struct representing the post date
  * `tags`: A list of tags
  * `url`: Absolute URL of the blog post in the website
  * `data`: Source or processed contents data
  * `output`: Destination path
  * `extras`: A map for storing arbitrary key-value data
  * `template`: Name of custom template or `nil`
  """

  require Serum.Result, as: Result
  alias Serum.Fragment
  alias Serum.Renderer
  alias Serum.Tag
  alias Serum.Template.Storage, as: TS

  @type t :: %__MODULE__{
          file: Serum.File.t(),
          type: binary(),
          title: binary(),
          date: DateTime.t(),
          tags: [Tag.t()],
          url: binary(),
          data: binary(),
          output: binary(),
          extras: map(),
          template: binary() | nil
        }

  defstruct [
    :file,
    :type,
    :title,
    :date,
    :tags,
    :url,
    :data,
    :output,
    :extras,
    :template
  ]

  @spec new(Serum.File.t(), {map(), map()}, binary(), map()) :: t()
  def new(file, {header, extras}, data, proj) do
    filename = Path.relative_to(file.src, proj.src)
    tags = Tag.batch_create(header[:tags] || [], proj)
    datetime = header[:date]
    {type, original_ext} = get_type(filename)

    {url, output} =
      with name <- String.replace_suffix(filename, original_ext, "html") do
        {Path.join(proj.base_url, name), Path.join(proj.dest, name)}
      end

    %__MODULE__{
      file: file,
      type: type,
      title: header[:title],
      tags: tags,
      data: data,
      date: datetime,
      url: url,
      output: output,
      template: header[:template],
      extras: extras
    }
  end

  @spec compact(t()) :: map()
  def compact(%__MODULE__{} = post) do
    post
    |> Map.drop(~w(__struct__ file data output type)a)
    |> Map.put(:type, :post)
  end

  @spec get_type(binary()) :: {binary(), binary()}
  defp get_type(filename) do
    filename
    |> Path.basename()
    |> String.split(".", parts: 2)
    |> Enum.reverse()
    |> hd()
    |> case do
      "html.eex" -> {"html", "html.eex"}
      type -> {type, type}
    end
  end

  @spec to_fragment(t()) :: Result.t(Fragment.t())
  def to_fragment(post) do
    metadata = compact(post)
    template_name = post.template || "post"
    bindings = [page: metadata, contents: post.data]

    Result.run do
      template <- TS.get(template_name, :template)
      html <- Renderer.render_fragment(template, bindings)

      Fragment.new(post.file, post.output, metadata, html)
    end
  end

  defimpl Fragment.Source do
    alias Serum.Fragment
    alias Serum.Post
    alias Serum.Result

    @spec to_fragment(Post.t()) :: Result.t(Fragment.t())
    def to_fragment(post) do
      Post.to_fragment(post)
    end
  end
end
