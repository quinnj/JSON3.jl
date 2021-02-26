@testset "Generate Types" begin
    menu = """
    {
      "menu": {
        "header": "SVG\\tViewer\\u03b1",
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
            "header": "SVG\\tViewer\\u03b1",
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
        json_exprs = JSON3.generate_exprs(raw_json_type, :MyStruct)
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
        json_arr_exprs = JSON3.generate_exprs(raw_json_arr_type, :MyStruct)
        @test length(json_arr_exprs) == 3

        # write the types to a file, then can be edited/included as needed
        path = mktempdir()
        file_arr = joinpath(path, "test_arr.jl")
        JSON3.write_exprs(json_arr_exprs, file_arr)
        arr_lines = readlines(file_arr)
        @test length(arr_lines) > 3
        @test arr_lines == lines
    end
end
