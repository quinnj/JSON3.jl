@testset "Generate Types" begin
    menu = """
    {
      "menu": {
        "header": "SVG Viewer",
        "items": [
          {
            "id": "Open"
          },
          {
            "id": "OpenNew",
            "label": "Open New"
          },
          {
            "id": "ZoomIn",
            "label": "Zoom In"
          },
          {
            "id": "ZoomOut",
            "label": "Zoom Out"
          },
          {
            "id": "OriginalView",
            "label": "Original View"
          },
          {
            "id": "Quality"
          },
          {
            "id": "Pause"
          },
          {
            "id": "Mute"
          },
          null,
          {
            "id": "Find",
            "label": "Find..."
          },
          {
            "id": "FindAgain",
            "label": "Find Again"
          },
          {
            "id": "Copy"
          },
          {
            "id": "CopyAgain",
            "label": "Copy Again"
          },
          {
            "id": "CopySVG",
            "label": "Copy SVG"
          },
          {
            "id": "ViewSVG",
            "label": "View SVG"
          },
          {
            "id": "ViewSource",
            "label": "View Source"
          },
          {
            "id": "SaveAs",
            "label": "Save As"
          },
          null,
          {
            "id": "Help"
          },
          {
            "id": "About",
            "label": "About Adobe SVG Viewer..."
          }
        ]
      }
    }
    """

    menu_array = """
    [
        {
          "menu": {
            "header": "SVG Viewer",
            "items": [
              {
                "id": "Open"
              },
              {
                "id": "OpenNew",
                "label": "Open New"
              },
              {
                "id": "ZoomIn",
                "label": "Zoom In"
              },
              {
                "id": "ZoomOut",
                "label": "Zoom Out"
              },
              {
                "id": "OriginalView",
                "label": "Original View"
              },
              {
                "id": "Quality"
              },
              {
                "id": "Pause"
              },
              {
                "id": "Mute"
              },
              null,
              {
                "id": "Find",
                "label": "Find..."
              },
              {
                "id": "FindAgain",
                "label": "Find Again"
              },
              {
                "id": "Copy"
              },
              {
                "id": "CopyAgain",
                "label": "Copy Again"
              },
              {
                "id": "CopySVG",
                "label": "Copy SVG"
              },
              {
                "id": "ViewSVG",
                "label": "View SVG"
              },
              {
                "id": "ViewSource",
                "label": "View Source"
              },
              {
                "id": "SaveAs",
                "label": "Save As"
              },
              null,
              {
                "id": "Help"
              },
              {
                "id": "About",
                "label": "About Adobe SVG Viewer..."
              }
            ]
          }
        },
        {
          "menu": {
            "header": "A second item",
            "items": [
              {
                "id": "Open"
              },
              {
                "id": "OpenNew",
                "label": "Open New"
              }
            ]
          }
        }
    ]
    """

    @testset "Object & Array" begin
        json = JSON3.read(menu) # JSON.Object

        # build a type for the JSON
        raw_json_type = JSON3.generate_type(json)
        @test raw_json_type <: NamedTuple

        # turn the type into struct expressions, including replacing sub types with references to a struct
        json_exprs = JSON3.generate_exprs(raw_json_type; root_name=:MyStruct)
        @test length(json_exprs) == 3

        # write the types to a file, then can be edited/included as needed
        path = mktempdir()
        file = joinpath(path, "test_type.jl")
        JSON3.write_exprs(json_exprs, file)
        lines = readlines(file)
        @test length(lines) > 3

        json_arr = JSON3.read(menu_array) # JSON.Array

        # build a type for the JSON
        raw_json_arr_type = JSON3.generate_type(json_arr)
        @test raw_json_arr_type <: Array

        # turn the type into struct expressions, including replacing sub types with references to a struct
        json_arr_exprs = JSON3.generate_exprs(raw_json_arr_type; root_name=:MyStruct)
        @test length(json_arr_exprs) == 3

        # write the types to a file, then can be edited/included as needed
        path = mktempdir()
        file_arr = joinpath(path, "test_arr.jl")
        JSON3.write_exprs(json_arr_exprs, file_arr)
        arr_lines = readlines(file_arr)
        @test length(arr_lines) > 3
        @test arr_lines == lines
    end

    @testset "Write & Read" begin
        path = mktempdir()
        file_path_default = joinpath(path, "default.jl")
        JSON3.writetypes(menu, file_path_default)

        include(file_path_default)
        json = JSON3.read(menu, JSONTypes.Root)

        @test json.menu.header == "SVG Viewer"
        @test length(json.menu.items) > 0
        @test json.menu.items[1].id == "Open"

        @test fieldnames(JSONTypes.Item) == (:id, :label)

        file_path_json = joinpath(path, "menu_array.json")
        Base.write(file_path_json, menu_array)
        file_path_mod = joinpath(path, "my_mod.jl")
        JSON3.writetypes(file_path_json, file_path_mod; module_name=:MyMod, root_name=:MenuArray)

        include(file_path_mod)
        json_arr = JSON3.read(menu_array, Vector{MyMod.MenuArray})
        @test length(json_arr) == 2
        @test json_arr[1].menu.header == "SVG Viewer"
    end

    @testset "Struct" begin
        json = """
            [
                {"a": 1, "b": 2, "c": {"d": 4}},
                {"a": "w", "b": 5, "c": {"d": 4}},
                {"a": 3, "b": 4, "c": {"d": 6}},
                {"a": 7, "b": 7, "c": {"d": 7}}
            ]
        """

        path = mktempdir()
        file_path = joinpath(path, "struct.jl")

        JSON3.writetypes(json, file_path; mutable=false)
        include(file_path)
        parsed = JSON3.read(json, Vector{JSONTypes.Root})

        @test !ismutabletype(JSONTypes.Root)
        @test parsed[1].c.d == 4
        @test fieldtype(JSONTypes.Root, 1) == Union{Int64, String}
    end

    @testset "Raw Types" begin
        json = """
            [
                {"a": 1, "b": 2, "c": 5},
                {"a": "w", "b": 5, "c": 9},
                {"a": 3, "b": 4, "c": 2},
                {"a": 7, "b": 7, "c": 0}
            ]
        """
        parsed = JSON3.read(json) # JSON.Array

        # build a type for the JSON
        raw_json_type = JSON3.generate_type(parsed)
        @test raw_json_type <: Array

        res = JSON3.read(json, raw_json_type)
        @test isa(res, raw_json_type)

        @test res[4].b == 7

        json = """{"a": 1, "b": 2, "c": 5}"""
        parsed = JSON3.read(json) # JSON.Object

        # build a type for the JSON
        raw_json_type = JSON3.generate_type(parsed)
        @test raw_json_type <: NamedTuple

        res = JSON3.read(json, raw_json_type)
        @test isa(res, raw_json_type)

        @test res.b == 2

        empty_json = "[]"
        raw_json_type = JSON3.generate_type(JSON3.read(empty_json))
        @test raw_json_type === Vector{Any}

        two_json = """[[], [1]]"""
        raw_json_type = JSON3.generate_type(JSON3.read(two_json))
        @test raw_json_type === Vector{Vector{Int}}
    end

    @testset "Pascal Case" begin
        @test JSON3.pascalcase(:items) == :Item
        @test JSON3.pascalcase(:i) == :I
        @test JSON3.pascalcase(:is) == :I
        @test JSON3.pascalcase(:daisies) == :Daisie # don't let perfect be the enemy of good?
        @test JSON3.pascalcase(:ties) == :Tie
        @test JSON3.pascalcase(:my_types) == :MyType
        @test JSON3.pascalcase(:witness) == :Witness
    end

    @testset "Macro" begin
        JSON3.@generatetypes(menu)
        json = JSON3.read(menu, JSONTypes.Root)

        @test json.menu.header == "SVG Viewer"
        @test length(json.menu.items) > 0
        @test json.menu.items[1].id == "Open"

        @test fieldnames(JSONTypes.Item) == (:id, :label)

        JSON3.@generatetypes(menu_array, :MyMod)
        json_arr = JSON3.read(menu_array, Vector{MyMod.Root})
        @test length(json_arr) == 2
        @test json_arr[1].menu.header == "SVG Viewer"
    end
end
