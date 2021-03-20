module JSONTypes
import StructTypes
mutable struct Item
    id::String
    label::Union{Nothing,String}
    Item() = begin
        #= none:1 =#
        new()
    end
end
mutable struct Menu
    header::String
    items::Array{Union{Nothing,Item},1}
    Menu() = begin
        #= none:1 =#
        new()
    end
end
mutable struct Root
    menu::Menu
    Root() = begin
        #= none:1 =#
        new()
    end
end
StructTypes.StructType(::Type{Item}) = begin
    #= none:1 =#
    StructTypes.Mutable()
end
StructTypes.StructType(::Type{Menu}) = begin
    #= none:1 =#
    StructTypes.Mutable()
end
StructTypes.StructType(::Type{Root}) = begin
    #= none:1 =#
    StructTypes.Mutable()
end
end
