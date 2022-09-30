defmodule Protobuf.Protoc.ContextTest do
  use ExUnit.Case, async: true

  alias Protobuf.Protoc.Context

  alias Google.Protobuf.{
    DescriptorProto,
    EnumDescriptorProto,
    FileDescriptorProto
  }

  describe "find_types/2" do
    test "returns multiple files" do
      ctx = %Context{}
      descs = [FileDescriptorProto.new(name: "file1"), FileDescriptorProto.new(name: "file2")]

      assert %Context{global_type_mapping: %{"file1" => %{}, "file2" => %{}}} =
               Context.find_types(ctx, descs, [])
    end

    test "merge message and enum" do
      desc =
        FileDescriptorProto.new(
          name: "file1",
          package: "pkg",
          message_type: [DescriptorProto.new(name: "Msg")],
          enum_type: [EnumDescriptorProto.new(name: "Enum")]
        )

      assert %{
               "file1" => %{
                 ".pkg.Msg" => %{type_name: "Pkg.Msg"},
                 ".pkg.Enum" => %{type_name: "Pkg.Enum"}
               }
             } = Context.find_types(%Context{}, [desc], []).global_type_mapping
    end

    test "have nested message types" do
      desc =
        FileDescriptorProto.new(
          name: "file1",
          package: "pkg",
          message_type: [
            DescriptorProto.new(
              name: "Msg",
              nested_type: [DescriptorProto.new(name: "NestedMsg")],
              enum_type: [EnumDescriptorProto.new(name: "NestedEnumMsg")]
            )
          ]
        )

      assert %{
               "file1" => %{
                 ".pkg.Msg" => %{type_name: "Pkg.Msg"},
                 ".pkg.Msg.NestedMsg" => %{type_name: "Pkg.Msg.NestedMsg"},
                 ".pkg.Msg.NestedEnumMsg" => %{type_name: "Pkg.Msg.NestedEnumMsg"}
               }
             } = Context.find_types(%Context{}, [desc], []).global_type_mapping
    end

    test "have deeper nested message types" do
      desc =
        FileDescriptorProto.new(
          name: "file1",
          package: "pkg",
          message_type: [
            DescriptorProto.new(
              name: "Msg",
              nested_type: [
                DescriptorProto.new(
                  name: "NestedMsg",
                  nested_type: [DescriptorProto.new(name: "NestedMsg2")]
                )
              ]
            )
          ]
        )

      assert %{
               "file1" => %{
                 ".pkg.Msg" => %{type_name: "Pkg.Msg"},
                 ".pkg.Msg.NestedMsg" => %{type_name: "Pkg.Msg.NestedMsg"},
                 ".pkg.Msg.NestedMsg.NestedMsg2" => %{type_name: "Pkg.Msg.NestedMsg.NestedMsg2"}
               }
             } = Context.find_types(%Context{}, [desc], []).global_type_mapping
    end

    test "supports elixir_module_prefix" do
      opts = Google.Protobuf.FileOptions.new()
      custom_opts = Elixirpb.FileOptions.new(module_prefix: "FooBar.Prefix")

      opts =
        Google.Protobuf.FileOptions.put_extension(opts, Elixirpb.PbExtension, :file, custom_opts)

      desc =
        FileDescriptorProto.new(
          name: "file1",
          package: "pkg",
          message_type: [DescriptorProto.new(name: "Msg")],
          enum_type: [EnumDescriptorProto.new(name: "Enum")],
          options: opts
        )

      assert %{
               "file1" => %{
                 ".pkg.Msg" => %{type_name: "FooBar.Prefix.Msg"},
                 ".pkg.Enum" => %{type_name: "FooBar.Prefix.Enum"}
               }
             } = Context.find_types(%Context{}, [desc], []).global_type_mapping
    end

    test "supports package_prefix" do
      ctx = %Context{package_prefix: "pkg_prefix"}
      files_to_generate = ["file1"]

      descs = [
        FileDescriptorProto.new(
          name: "file1",
          package: "pkg",
          message_type: [DescriptorProto.new(name: "Msg")]
        )
      ]

      assert Context.find_types(ctx, descs, files_to_generate).global_type_mapping == %{
               "file1" => %{".pkg.Msg" => %{type_name: "PkgPrefix.Pkg.Msg"}}
             }
    end

    test "doesn't prepend package_prefix to type mappings for files that are not to be generated" do
      ctx = %Context{package_prefix: "pkg_prefix"}
      files_to_generate = ["file_to_generate"]

      descs = [
        FileDescriptorProto.new(
          name: "file_to_generate",
          package: "pkg",
          message_type: [DescriptorProto.new(name: "Msg")]
        ),
        FileDescriptorProto.new(
          name: "not_in_files_to_generate",
          package: "other_pkg",
          message_type: [DescriptorProto.new(name: "OtherMsg")]
        )
      ]

      assert Context.find_types(ctx, descs, files_to_generate).global_type_mapping == %{
               "file_to_generate" => %{
                 ".pkg.Msg" => %{type_name: "PkgPrefix.Pkg.Msg"}
               },
               "not_in_files_to_generate" => %{
                 ".other_pkg.OtherMsg" => %{type_name: "OtherPkg.OtherMsg"}
               }
             }
    end
  end
end
