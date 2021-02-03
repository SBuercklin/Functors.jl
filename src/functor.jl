functor(T, x) = (), _ -> x
functor(x) = functor(typeof(x), x)

functor(::Type{<:Tuple}, x) = x, y -> y
functor(::Type{<:NamedTuple}, x) = x, y -> y

functor(::Type{<:AbstractArray}, x) = x, y -> y
functor(::Type{<:AbstractArray{<:Number}}, x) = (), _ -> x

function makefunctor(m::Module, T, fs = fieldnames(T))
  @eval m begin
    $Functors.functor(::Type{<:$T}, x) = ($([:($f=x.$f) for f in fs]...),), y -> $T(y...)
  end
end

function functorm(T, fs = nothing)
  fs == nothing || isexpr(fs, :tuple) || error("@functor T (a, b)")
  fs = fs == nothing ? [] : [:($(map(QuoteNode, fs.args)...),)]
  :(makefunctor(@__MODULE__, $(esc(T)), $(fs...)))
end

macro functor(args...)
  functorm(args...)
end

isleaf(x) = functor(x)[1] === ()

# for Chain
function functor_tuple(f, x::Tuple, dx::Tuple)
  map(x, dx) do x, x̄
    fmap1(f, x, x̄)
  end
end
functor_tuple(f, x, dx) = f(x, dx)
functor_tuple(f, x, ::Nothing) = x

# @functor Chain
# Chain -> func = (layers = (Dense,Dense),), gs -> (layers...)
function fmap1(f, x, dx)
  func, re = functor(x)
  map(func, dx) do x, x̄
    functor_tuple(f, x, x̄)
  end |> re
end

function fmap1(f, x)
  func, re = functor(x)
  re(map(f, func))
end

# See https://github.com/FluxML/Functors.jl/issues/2 for a discussion regarding the need for
# cache.
function fmap(f, x; cache = IdDict())
  haskey(cache, x) && return cache[x]
  cache[x] = isleaf(x) ? f(x) : fmap1(x -> fmap(f, x, cache = cache), x)
end
# Allow gradients and other constructs that match the structure of the functor
# to allow for `map` style computations and return a modified version of the struct.
# This way we can use `fmap` to update the params with their gradients
function fmap(f, x, dx...; cache = IdDict())
  haskey(cache, x) && return cache[x]
  cache[x] = isleaf(x) ? f(x, dx...) : fmap1((x...) -> fmap(f, x..., cache = cache), x, dx...)
end
