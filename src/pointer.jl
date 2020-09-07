# CUDA pointer types

export CuPtr, CU_NULL, PtrOrCuPtr, CuArrayPtr, CUA_NULL, CuRef, RefOrCuRef


#
# CUDA device pointer
#

# forward declaration
abstract type CuRef{T} end

# FIXME: should be called CuDevicePtr...

"""
    CuPtr{T}

A memory address that refers to data of type `T` that is accessible from the GPU. A `CuPtr`
is ABI compatible with regular `Ptr` objects, e.g. it can be used to `ccall` a function that
expects a `Ptr` to GPU memory, but it prevents erroneous conversions between the two.
"""
CuPtr

if sizeof(Ptr{Cvoid}) == 8
    primitive type CuPtr{T} <: CuRef{T} 64 end
else
    primitive type CuPtr{T} <: CuRef{T} 32 end
end

# constructor
CuPtr{T}(x::Union{Int,UInt,CuPtr}) where {T} = Base.bitcast(CuPtr{T}, x)

const CU_NULL = CuPtr{Cvoid}(0)


## getters

Base.eltype(::Type{<:CuPtr{T}}) where {T} = T


## conversions

# to and from integers
## pointer to integer
Base.convert(::Type{T}, x::CuPtr) where {T<:Integer} = T(UInt(x))
## integer to pointer
Base.convert(::Type{CuPtr{T}}, x::Union{Int,UInt}) where {T} = CuPtr{T}(x)
Int(x::CuPtr)  = Base.bitcast(Int, x)
UInt(x::CuPtr) = Base.bitcast(UInt, x)

# between regular and CUDA pointers
Base.convert(::Type{<:Ptr}, p::CuPtr) =
    throw(ArgumentError("cannot convert a GPU pointer to a CPU pointer"))

# between CUDA pointers
Base.convert(::Type{CuPtr{T}}, p::CuPtr) where {T} = Base.bitcast(CuPtr{T}, p)

# defer conversions to unsafe_convert
Base.cconvert(::Type{<:CuPtr}, x) = x

# fallback for unsafe_convert
Base.unsafe_convert(::Type{P}, x::CuPtr) where {P<:CuPtr} = convert(P, x)


## limited pointer arithmetic & comparison

Base.isequal(x::CuPtr, y::CuPtr) = (x === y)
Base.isless(x::CuPtr{T}, y::CuPtr{T}) where {T} = x < y

Base.:(==)(x::CuPtr, y::CuPtr) = UInt(x) == UInt(y)
Base.:(<)(x::CuPtr,  y::CuPtr) = UInt(x) < UInt(y)
Base.:(-)(x::CuPtr,  y::CuPtr) = UInt(x) - UInt(y)

Base.:(+)(x::CuPtr, y::Integer) = oftype(x, Base.add_ptr(UInt(x), (y % UInt) % UInt))
Base.:(-)(x::CuPtr, y::Integer) = oftype(x, Base.sub_ptr(UInt(x), (y % UInt) % UInt))
Base.:(+)(x::Integer, y::CuPtr) = y + x



#
# Host or device pointer
#

"""
    PtrOrCuPtr{T}

A special pointer type, ABI-compatible with both `Ptr` and `CuPtr`, for use in `ccall`
expressions to convert values to either a GPU or a CPU type (in that order). This is
required for CUDA APIs which accept pointers that either point to host or device memory.
"""
PtrOrCuPtr


if sizeof(Ptr{Cvoid}) == 8
    primitive type PtrOrCuPtr{T} 64 end
else
    primitive type PtrOrCuPtr{T} 32 end
end

function Base.cconvert(::Type{PtrOrCuPtr{T}}, val) where {T}
    # `cconvert` is always implemented for both `Ptr` and `CuPtr`, so pick the first result
    # that has done an actual conversion

    gpu_val = Base.cconvert(CuPtr{T}, val)
    if gpu_val !== val
        return gpu_val
    end

    cpu_val = Base.cconvert(Ptr{T}, val)
    if cpu_val !== val
        return cpu_val
    end

    return val
end

function Base.unsafe_convert(::Type{PtrOrCuPtr{T}}, val) where {T}
    # FIXME: this is expensive; optimize using isapplicable?
    ptr = try
        Base.unsafe_convert(Ptr{T}, val)
    catch
        try
            Base.unsafe_convert(CuPtr{T}, val)
        catch
            throw(ArgumentError("cannot convert to either a CPU or GPU pointer"))
        end
    end
    return Base.bitcast(PtrOrCuPtr{T}, ptr)
end


#
# CUDA array pointer
#

if sizeof(Ptr{Cvoid}) == 8
    primitive type CuArrayPtr{T} 64 end
else
    primitive type CuArrayPtr{T} 32 end
end

# constructor
CuArrayPtr{T}(x::Union{Int,UInt,CuArrayPtr}) where {T} = Base.bitcast(CuArrayPtr{T}, x)


## getters

Base.eltype(::Type{<:CuArrayPtr{T}}) where {T} = T


## conversions

# to and from integers
## pointer to integer
Base.convert(::Type{T}, x::CuArrayPtr) where {T<:Integer} = T(UInt(x))
## integer to pointer
Base.convert(::Type{CuArrayPtr{T}}, x::Union{Int,UInt}) where {T} = CuArrayPtr{T}(x)
Int(x::CuArrayPtr)  = Base.bitcast(Int, x)
UInt(x::CuArrayPtr) = Base.bitcast(UInt, x)

# between regular and CUDA pointers
Base.convert(::Type{<:Ptr}, p::CuArrayPtr) =
    throw(ArgumentError("cannot convert a GPU array pointer to a CPU pointer"))

# between CUDA array pointers
Base.convert(::Type{CuArrayPtr{T}}, p::CuArrayPtr) where {T} = Base.bitcast(CuArrayPtr{T}, p)

# defer conversions to unsafe_convert
Base.cconvert(::Type{<:CuArrayPtr}, x) = x

# fallback for unsafe_convert
Base.unsafe_convert(::Type{P}, x::CuArrayPtr) where {P<:CuArrayPtr} = convert(P, x)



#
# CUDA reference objects
#

# a GPU reference that lives on the CPU; for use with `ccall`
#abstract type CuRef{T} end

# general methods for CuRef{T} type
Base.eltype(x::Type{<:CuRef{T}}) where {T} = @isdefined(T) ? T : Any
Base.convert(::Type{CuRef{T}}, x::CuRef{T}) where {T} = x

# create CuRef objects for general object conversion
Base.unsafe_convert(::Type{CuRef{T}}, x::CuRef{T}) where {T} = Base.unsafe_convert(CuPtr{T}, x)
Base.unsafe_convert(::Type{CuRef{T}}, x) where {T} = Base.unsafe_convert(CuPtr{T}, x)

# CuRef object backed by a CUDA array at index i
struct CuRefArray{T,A<:AbstractGPUArray{T}} <: Ref{T}
    x::A
    i::Int
    CuRefArray{T,A}(x,i) where {T,A<:AbstractGPUArray{T}} = new(x,i)
end
CuRefArray{T}(x::AbstractGPUArray{T}, i::Int=1) where {T} = CuRefArray{T,typeof(x)}(x, i)
CuRefArray(x::AbstractGPUArray{T}, i::Int=1) where {T} = CuRefArray{T}(x, i)
Base.convert(::Type{CuRef{T}}, x::AbstractGPUArray{T}) where {T} = CuRefArray(x, 1)

function Base.unsafe_convert(P::Type{CuPtr{T}}, b::CuRefArray{T}) where T
    return pointer(b.x, b.i)
end
function Base.unsafe_convert(P::Type{CuPtr{Any}}, b::CuRefArray{Any})
    return convert(P, pointer(b.x, b.i))
end
Base.unsafe_convert(::Type{CuPtr{Cvoid}}, b::CuRefArray{T}) where {T} =
    convert(CuPtr{Cvoid}, Base.unsafe_convert(CuPtr{T}, b))

# indirect constructors using CuRef
CuRef(x::Any) = CuRefArray(CuArray([x]))
CuRef{T}(x) where {T} = CuRefArray{T}(CuArray(T[x]))
CuRef{T}() where {T} = CuRefArray(CuArray{T}(undef, 1))
Base.convert(::Type{CuRef{T}}, x) where {T} = CuRef{T}(x)

# arrays of references or pointers
Base.cconvert(::Type{CuPtr{P}}, a::Array{<:CuPtr}) where {P<:CuPtr} = a
Base.cconvert(::Type{CuRef{P}}, a::Array{<:CuPtr}) where {P<:CuPtr} = a


## RefOrCuRef

const RefOrCuRef{T} = Union{Ref{T}, CuRef{T}}
Base.convert(::Type{RefOrCuRef{T}}, x::Union{RefOrCuRef{T}}) where {T} = x

# prefer conversion to CPU ref: this is generally cheaper
Base.convert(::Type{RefOrCuRef{T}}, x) where {T} = Ref(x)
Base.unsafe_convert(::Type{RefOrCuRef{T}}, x::Ref{T}) where {T} = Base.unsafe_convert(Ptr{T}, x)
Base.unsafe_convert(::Type{RefOrCuRef{T}}, x) where {T} = Base.unsafe_convert(Ptr{T}, x)

# support conversion from GPU ref
Base.unsafe_convert(::Type{RefOrCuRef{T}}, x::CuRef{T}) where {T} = Base.unsafe_convert(CuPtr{T}, x)

# support conversion from arrays
Base.convert(::Type{RefOrCuRef{T}}, x::Array{T}) where {T} = convert(Ref{T}, x)
Base.convert(::Type{RefOrCuRef{T}}, x::AbstractGPUArray{T}) where {T} = convert(CuRef{T}, x)
Base.unsafe_convert(P::Type{RefOrCuRef{T}}, b::CUDA.CuRefArray{T}) where T = Base.unsafe_convert(CuRef{T}, b)
