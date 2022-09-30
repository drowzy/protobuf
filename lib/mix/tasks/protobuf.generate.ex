defmodule Mix.Tasks.Protobuf.Generate do
  @moduledoc """
  Generate Elixir code from `.proto` files.


  ## Arguments

  * `FILE` - One or more `.proto` files to compile

  ## Required options

  * `--output-path` - Path to output directory

  ## Optional options

  * `--include-path` - Specify the directory in which to search for imports. Eqvivalent to `protoc` `-I` flag.
  * `--tranform-module` - Module to do custom encoding/decoding for messages. See `Protobuf.TransformModule` for details.
  * `--package-prefix` - Prefix generated Elixir modules. For example prefix modules with: `MyApp.Protos` use `--package-prefix=my_app.protos`.
  * `--generate-descriptors` - Includes raw descriptors in the generated modules
  * `--one-file-per-module` - Changes the way files are generated into directories. This option creates a file for each generated Elixir module.
  * `--include-documentation` - Controls visibility of documentation of the generated modules. Setting `true` will not  have `@moduleoc false`
  * `--plugins` - If you write services in protobuf, you can generate gRPC code by passing `--plugins=grpc`.

  ## Examples

      $ mix protobuf.generate --output-path=./lib --include-path=./priv/protos helloworld.proto

      $ mix protobuf.generate \
        --include-path=priv/proto \
        --include-path=deps/googleapis \
        --generate-descriptors=true \
        --output-path=./lib \
        google/api/annotations.proto google/api/http.proto helloworld.proto

  """
  @shortdoc "Generate Elixir code from Protobuf definitions"

  use Mix.Task
  alias Protobuf.Protoc.Context

  @switches [
    output_path: :string,
    include_path: :keep,
    generate_descriptors: :boolean,
    package_prefix: :string,
    transform_module: :string,
    include_docs: :boolean,
    one_file_per_module: :boolean,
    plugins: :keep
  ]

  @impl Mix.Task
  @spec run(any) :: any
  def run(args) do
    {opts, files} = OptionParser.parse!(args, strict: @switches)
    {plugins, opts} = pop_values(opts, :plugins)
    {imports, opts} = pop_values(opts, :include_path)

    transform_module =
      case Keyword.fetch(opts, :transform_module) do
        {:ok, t} -> Module.concat([t])
        :error -> nil
      end

    output_path =
      opts
      |> Keyword.fetch!(:output_path)
      |> Path.expand()

    ctx = %Context{
      imports: imports,
      files: files,
      output_path: output_path,
      gen_descriptors?: Keyword.get(opts, :generate_descriptors, false),
      plugins: plugins,
      transform_module: transform_module,
      package_prefix: Keyword.get(opts, :package_prefix),
      include_docs?: Keyword.get(opts, :include_docs, false)
    }

    Protobuf.load_extensions()

    case protoc(ctx) do
      {:ok, bin} ->
        request = decode(ctx, bin)
        response = generate(ctx, request)

        Enum.each(response.file, &generate_file(ctx, &1))

      {:error, reason} ->
        IO.puts(:stderr, "Failed to generate code: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp decode(ctx, bin) do
    %Google.Protobuf.FileDescriptorSet{file: file_descriptors} =
      Protobuf.Decoder.decode(bin, Google.Protobuf.FileDescriptorSet)

    files = normalize_import_paths(ctx.files, ctx.imports, [])

    Google.Protobuf.Compiler.CodeGeneratorRequest.new(
      file_to_generate: files,
      proto_file: file_descriptors
    )
  end

  defp normalize_import_paths(files, [], _), do: files
  defp normalize_import_paths([], _, acc), do: Enum.reverse(acc)

  defp normalize_import_paths([file | rest], imports, acc) do
    file_path =
      Enum.reduce_while(imports, file, fn i, file ->
        relative_path = Path.relative_to(file, i)

        if relative_path == file do
          {:cont, file}
        else
          {:halt, relative_path}
        end
      end)

    normalize_import_paths(rest, imports, [file_path | acc])
  end

  defp generate(ctx, request) do
    ctx = Context.find_types(ctx, request.proto_file, request.file_to_generate)

    files =
      Enum.flat_map(request.file_to_generate, fn file ->
        desc = Enum.find(request.proto_file, &(&1.name == file))
        Protobuf.Protoc.Generator.generate(ctx, desc)
      end)

    response =
      Google.Protobuf.Compiler.CodeGeneratorResponse.new(
        file: files,
        supported_features: Protobuf.Protoc.CLI.supported_features()
      )

    response
  end

  defp generate_file(%Context{output_path: out}, %{name: file_name, content: content}) do
    path = Path.join([out, file_name])
    dir = Path.dirname(path)

    File.mkdir_p!(dir)
    File.write!(path, content)
  end

  # https://github.com/ahamez/protox/blob/master/lib/protox/protoc.ex
  defp protoc(%Context{files: [proto_file], imports: []}),
    do: run_protoc([proto_file], ["-I", "#{proto_file |> Path.dirname() |> Path.expand()}"])

  defp protoc(%Context{files: [proto_file], imports: paths}),
    do: run_protoc([proto_file], paths_to_protoc_args(paths))

  defp protoc(%Context{files: proto_files, imports: []}),
    do: run_protoc(proto_files, ["-I", "#{common_directory_path(proto_files)}"])

  defp protoc(%Context{files: proto_files, imports: paths}),
    do: run_protoc(proto_files, paths_to_protoc_args(paths))

  defp run_protoc(proto_files, args) do
    outfile_name = "protobuf_#{random_string()}"
    outfile_path = Path.join([Mix.Project.build_path(), outfile_name])

    cmd_args =
      ["--include_imports", "--include_source_info", "-o", outfile_path] ++ args ++ proto_files

    try do
      System.cmd("protoc", cmd_args, stderr_to_stdout: true)
    catch
      :error, :enoent ->
        raise "protoc executable is missing. Please make sure Protocol Buffers " <>
                "is installed and available system wide"
    else
      {_, 0} ->
        file_content = File.read!(outfile_path)
        :ok = File.rm(outfile_path)
        {:ok, file_content}

      {msg, _} ->
        {:error, msg}
    end
  end

  defp paths_to_protoc_args(paths) do
    paths
    |> Enum.map(&["-I", &1])
    |> Enum.concat()
  end

  defp common_directory_path(paths_rel) do
    paths = Enum.map(paths_rel, &Path.expand/1)

    min_path = paths |> Enum.min() |> Path.split()
    max_path = paths |> Enum.max() |> Path.split()

    min_path
    |> Enum.zip(max_path)
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> Enum.map(fn {x, _} -> x end)
    |> Path.join()
  end

  defp random_string(len \\ 16) do
    "#{Enum.take_random(?a..?z, len)}"
  end

  # Custom implementation as Keyword.pop_values/2 is only available since Elixir 1.10
  defp pop_values(opts, key) do
    {values, new_opts} =
      Enum.reduce(opts, {[], []}, fn
        {^key, value}, {values, new_opts} -> {[value | values], new_opts}
        {key, value}, {values, new_opts} -> {values, [{key, value} | new_opts]}
      end)

    {Enum.reverse(values), Enum.reverse(new_opts)}
  end
end
