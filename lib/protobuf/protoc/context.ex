defmodule Protobuf.Protoc.Context do
  @moduledoc false

  @type t() :: %__MODULE__{}

  # Plugins passed by options
  defstruct plugins: [],
            files: [],
            imports: [],
            output_path: "",
            ### All files scope

            # Mapping from file name to (mapping from type name to metadata, like elixir type name)
            # %{"example.proto" => %{".example.FooMsg" => %{type_name: "Example.FooMsg"}}}
            global_type_mapping: %{},

            ### One file scope

            # Package name
            package: nil,
            package_prefix: nil,
            module_prefix: nil,
            syntax: nil,
            # Mapping from type_name to metadata. It's merged type mapping of dependencies files including itself
            # %{".example.FooMsg" => %{type_name: "Example.FooMsg"}}
            dep_type_mapping: %{},

            # For a message
            # Nested namespace when generating nested messages. It should be joined to get the full namespace
            namespace: [],

            # Include binary descriptors in the generated protobuf modules
            # And expose them via the `descriptor/0` function
            gen_descriptors?: false,

            # Module to transform values before and after encode and decode
            transform_module: nil,

            # Generate one file per module with "proper" directory structure
            # (according to Elixir conventions) if this is true
            one_file_per_module?: false,

            # Include visible module docs in the generated protobuf modules
            include_docs?: false,

            # Elixirpb.FileOptions
            custom_file_options: %{}

  @spec custom_file_options_from_file_desc(t(), Google.Protobuf.FileDescriptorProto.t()) :: t()
  def custom_file_options_from_file_desc(ctx, desc)

  def custom_file_options_from_file_desc(
        %__MODULE__{} = ctx,
        %Google.Protobuf.FileDescriptorProto{options: nil}
      ) do
    %__MODULE__{ctx | custom_file_options: %{}}
  end

  def custom_file_options_from_file_desc(
        %__MODULE__{} = ctx,
        %Google.Protobuf.FileDescriptorProto{options: options}
      ) do
    custom_file_opts =
      Google.Protobuf.FileOptions.get_extension(options, Elixirpb.PbExtension, :file) ||
        Elixirpb.PbExtension.new()

    %__MODULE__{
      ctx
      | custom_file_options: custom_file_opts,
        module_prefix: Map.get(custom_file_opts, :module_prefix)
    }
  end

  @spec find_types(t(), [Google.Protobuf.FileDescriptorProto.t()], [String.t()]) ::
          t()
  def find_types(%__MODULE__{} = ctx, descs, files_to_generate)
      when is_list(descs) and is_list(files_to_generate) do
    global_type_mapping =
      Map.new(descs, fn %Google.Protobuf.FileDescriptorProto{name: filename} = desc ->
        {filename, find_types_in_proto(ctx, desc, files_to_generate)}
      end)

    %__MODULE__{ctx | global_type_mapping: global_type_mapping}
  end

  defp find_types_in_proto(
         %__MODULE__{} = ctx,
         %Google.Protobuf.FileDescriptorProto{} = desc,
         files_to_generate
       ) do
    # Only take package_prefix into consideration for files that we're directly generating.
    package_prefix =
      if desc.name in files_to_generate do
        ctx.package_prefix
      else
        nil
      end

    ctx =
      %Protobuf.Protoc.Context{
        namespace: [],
        package_prefix: package_prefix,
        package: desc.package
      }
      |> custom_file_options_from_file_desc(desc)

    find_types_in_descriptor(_types = %{}, ctx, desc.message_type ++ desc.enum_type)
  end

  defp find_types_in_descriptor(types_acc, ctx, descs) when is_list(descs) do
    Enum.reduce(descs, types_acc, &find_types_in_descriptor(_acc = &2, ctx, _desc = &1))
  end

  defp find_types_in_descriptor(
         types_acc,
         ctx,
         %Google.Protobuf.DescriptorProto{name: name} = desc
       ) do
    new_ctx = update_in(ctx.namespace, &(&1 ++ [name]))

    types_acc
    |> update_types(ctx, name)
    |> find_types_in_descriptor(new_ctx, desc.enum_type)
    |> find_types_in_descriptor(new_ctx, desc.nested_type)
  end

  defp find_types_in_descriptor(
         types_acc,
         ctx,
         %Google.Protobuf.EnumDescriptorProto{name: name}
       ) do
    update_types(types_acc, ctx, name)
  end

  defp update_types(types, %__MODULE__{namespace: ns, package: pkg} = ctx, name) do
    type_name = Protobuf.Protoc.Generator.Util.mod_name(ctx, ns ++ [name])

    mapping_name =
      ([pkg] ++ ns ++ [name])
      |> Enum.reject(&is_nil/1)
      |> Enum.join(".")

    Map.put(types, "." <> mapping_name, %{type_name: type_name})
  end
end
