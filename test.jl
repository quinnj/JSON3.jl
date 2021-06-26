module JSONTypes

import StructTypes

mutable struct Item
    id::String
    label::Union{Missing, String}
    Item() = new()
end

mutable struct Menu
    header::String
    items::Array{Union{Nothing, Item}, 1}
    Menu() = new()
end

mutable struct Root
    menu::Menu
    Root() = new()
end

StructTypes.StructType(::Type{Item}) = StructTypes.Mutable()
StructTypes.StructType(::Type{Menu}) = StructTypes.Mutable()
StructTypes.StructType(::Type{Root}) = StructTypes.Mutable()

end # module
