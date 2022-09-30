defmodule Protobuf.Protoc.CLITest do
  use ExUnit.Case, async: true

  import Protobuf.Protoc.CLI
  import ExUnit.CaptureIO

  alias Protobuf.Protoc.Context

  describe "main/1" do
    test "--version" do
      assert capture_io(fn ->
               main(["--version"])
             end) == Mix.Project.config()[:version] <> "\n"
    end

    test "--help" do
      for flag <- ["--help", "-h"] do
        assert capture_io(fn ->
                 main([flag])
               end) =~ "`protoc` plugin for generating Elixir code"
      end
    end

    test "raises an error with invalid arguments" do
      assert_raise RuntimeError, ~r/invalid arguments/, fn ->
        main(["invalid"])
      end
    end
  end

  describe "parse_params/2" do
    test "parses all the right parameters, regardless of the order" do
      params =
        %{
          "plugins" => "grpc",
          "gen_descriptors" => "true",
          "one_file_per_module" => "true",
          "package_prefix" => "elixir.protobuf",
          "transform_module" => "My.Transform.Module",
          "include_docs" => "true"
        }
        |> Enum.shuffle()
        |> Enum.map_join(",", fn {key, val} -> "#{key}=#{val}" end)

      ctx = parse_params(%Context{}, params)

      assert ctx == %Context{
               plugins: ["grpc"],
               gen_descriptors?: true,
               one_file_per_module?: true,
               package_prefix: "elixir.protobuf",
               transform_module: My.Transform.Module,
               include_docs?: true
             }
    end

    test "ignores unknown parameters" do
      assert parse_params(%Context{}, "unknown=true") == %Context{}
    end

    test "raises an error with invalid arguments" do
      assert_raise RuntimeError, ~r/invalid value for gen_descriptors option/, fn ->
        parse_params(%Context{}, "gen_descriptors=false")
      end

      assert_raise RuntimeError, ~r/invalid value for one_file_per_module option/, fn ->
        parse_params(%Context{}, "one_file_per_module=false")
      end

      assert_raise RuntimeError, ~r/invalid value for include_docs option/, fn ->
        parse_params(%Context{}, "include_docs=false")
      end

      assert_raise RuntimeError, ~r/package_prefix can't be empty/, fn ->
        parse_params(%Context{}, "package_prefix=")
      end

      assert_raise RuntimeError, ~r/package_prefix can't be empty/, fn ->
        parse_params(%Context{}, "package_prefix=,gen_descriptors=true")
      end
    end
  end
end
