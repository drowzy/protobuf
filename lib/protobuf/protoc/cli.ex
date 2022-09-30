defmodule Protobuf.Protoc.CLI do
  @moduledoc """
  `protoc` plugin for generating Elixir code.

  `protoc-gen-elixir` (this name is important) **must** be in `$PATH`. You are not supposed
  to call it directly, but only through `protoc`.

  ## Examples

      $ protoc --elixir_out=./lib your.proto
      $ protoc --elixir_out=plugins=grpc:./lib/ *.proto
      $ protoc -I protos --elixir_out=./lib protos/namespace/*.proto

  Options:

    * --version       Print version of protobuf-elixir
    * --help (-h)     Print this help

  """

  alias Protobuf.Protoc.Context

  # Entrypoint for the escript (protoc-gen-elixir).
  @doc false
  @spec main([String.t()]) :: :ok
  def main(args)

  def main(["--version"]) do
    {:ok, version} = :application.get_key(:protobuf, :vsn)
    IO.puts(version)
  end

  def main([opt]) when opt in ["--help", "-h"] do
    IO.puts(@moduledoc)
  end

  # When called through protoc, all input is passed through stdin.
  def main([] = _args) do
    Protobuf.load_extensions()

    # See https://groups.google.com/forum/#!topic/elixir-lang-talk/T5enez_BBTI.
    :io.setopts(:standard_io, encoding: :latin1)

    # Read the standard input that protoc feeds us.
    bin = binread_all!(:stdio)

    request = Protobuf.Decoder.decode(bin, Google.Protobuf.Compiler.CodeGeneratorRequest)

    ctx =
      %Context{}
      |> parse_params(request.parameter || "")
      |> Context.find_types(request.proto_file, request.file_to_generate)

    files =
      Enum.flat_map(request.file_to_generate, fn file ->
        desc = Enum.find(request.proto_file, &(&1.name == file))
        Protobuf.Protoc.Generator.generate(ctx, desc)
      end)

    Google.Protobuf.Compiler.CodeGeneratorResponse.new(
      file: files,
      supported_features: supported_features()
    )
    |> Protobuf.encode_to_iodata()
    |> IO.binwrite()
  end

  def main(_args) do
    raise "invalid arguments. See protoc-gen-elixir --help."
  end

  def supported_features() do
    # The only available feature is proto3 with optional fields.
    # This is backwards compatible with proto2 optional fields.
    Google.Protobuf.Compiler.CodeGeneratorResponse.Feature.value(:FEATURE_PROTO3_OPTIONAL)
  end

  # Made public for testing.
  @doc false
  def parse_params(%Context{} = ctx, params_str) when is_binary(params_str) do
    params_str
    |> String.split(",")
    |> Enum.reduce(ctx, &parse_param/2)
  end

  defp parse_param("plugins=" <> plugins, ctx) do
    %Context{ctx | plugins: String.split(plugins, "+")}
  end

  defp parse_param("gen_descriptors=" <> value, ctx) do
    case value do
      "true" ->
        %Context{ctx | gen_descriptors?: true}

      other ->
        raise "invalid value for gen_descriptors option, expected \"true\", got: #{inspect(other)}"
    end
  end

  defp parse_param("package_prefix=" <> package, ctx) do
    if package == "" do
      raise "package_prefix can't be empty"
    else
      %Context{ctx | package_prefix: package}
    end
  end

  defp parse_param("transform_module=" <> module, ctx) do
    %Context{ctx | transform_module: Module.concat([module])}
  end

  defp parse_param("one_file_per_module=" <> value, ctx) do
    case value do
      "true" ->
        %Context{ctx | one_file_per_module?: true}

      other ->
        raise "invalid value for one_file_per_module option, expected \"true\", got: #{inspect(other)}"
    end
  end

  defp parse_param("include_docs=" <> value, ctx) do
    case value do
      "true" ->
        %Context{ctx | include_docs?: true}

      other ->
        raise "invalid value for include_docs option, expected \"true\", got: #{inspect(other)}"
    end
  end

  defp parse_param(_unknown, ctx) do
    ctx
  end

  if Version.match?(System.version(), "~> 1.13") do
    defp binread_all!(device) do
      case IO.binread(device, :eof) do
        data when is_binary(data) -> data
        :eof -> _previous_behavior = ""
        other -> raise "reading from #{inspect(device)} failed: #{inspect(other)}"
      end
    end
  else
    defp binread_all!(device) do
      case IO.binread(device, :all) do
        data when is_binary(data) -> data
        other -> raise "reading from #{inspect(device)} failed: #{inspect(other)}"
      end
    end
  end
end
