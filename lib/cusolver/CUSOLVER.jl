module CUSOLVER

using ..APIUtils

using ..CUDA
using ..CUDA: CUstream, cuComplex, cuDoubleComplex, libraryPropertyType, cudaDataType
using ..CUDA: libcusolver, libcusolvermg, @allowscalar, assertscalar, unsafe_free!, @retry_reclaim

using ..CUBLAS: cublasFillMode_t, cublasOperation_t, cublasSideMode_t, cublasDiagType_t
using ..CUSPARSE: cusparseMatDescr_t
using ..CUDALIBMG: allocateBuffers, returnBuffers

using CEnum

using Memoize

using DataStructures


# core library
include("libcusolver_common.jl")
include("error.jl")
include("libcusolver.jl")

# low-level wrappers
include("util.jl")
include("wrappers.jl")

# high-level integrations
include("linalg.jl")

# thread cache for task-local library handles
const thread_dense_handles  = Vector{Union{Nothing,cusolverDnHandle_t}}()
const thread_sparse_handles = Vector{Union{Nothing,cusolverSpHandle_t}}()
const thread_mg_handles  = Vector{Union{Nothing,cusolverMgHandle_t}}()

# cache for created, but unused handles
const handle_cache_lock = ReentrantLock()
const idle_dense_handles = DefaultDict{CuContext,Vector{cusolverDnHandle_t}}(()->cusolverDnHandle_t[])
const idle_sparse_handles = DefaultDict{CuContext,Vector{cusolverSpHandle_t}}(()->cusolverSpHandle_t[])
const idle_mg_handles = DefaultDict{CuContext,Vector{cusolverMgHandle_t}}(()->cusolverMgHandle_t[])

function dense_handle()
    CUDA.detect_state_changes()
    tid = Threads.threadid()
    if @inbounds thread_dense_handles[tid] === nothing
        ctx = context()
        thread_dense_handles[tid] = get!(task_local_storage(), (:CUSOLVER, :dense, ctx)) do
            handle = lock(handle_cache_lock) do
                if isempty(idle_dense_handles[ctx])
                    cusolverDnCreate()
                else
                    pop!(idle_dense_handles[ctx])
                end
            end

            finalizer(current_task()) do task
                lock(handle_cache_lock) do
                    push!(idle_dense_handles[ctx], handle)
                end
            end
            # TODO: cusolverDnDestroy to preserve memory, or at exit?

            cusolverDnSetStream(handle, stream())

            handle
        end
    end
    something(@inbounds thread_dense_handles[tid])
end

function sparse_handle()
    CUDA.detect_state_changes()
    tid = Threads.threadid()
    if @inbounds thread_sparse_handles[tid] === nothing
        ctx = context()
        thread_sparse_handles[tid] = get!(task_local_storage(), (:CUSOLVER, :sparse, ctx)) do
            handle = if isempty(idle_sparse_handles[ctx])
                cusolverSpCreate()
            else
                pop!(idle_sparse_handles[ctx])
            end

            finalizer(current_task()) do task
                push!(idle_sparse_handles[ctx], handle)
            end
            # TODO: cusolverSpDestroy to preserve memory, or at exit?

            cusolverSpSetStream(handle, stream())

            handle
        end
    end
    something(@inbounds thread_sparse_handles[tid])
end

function mg_handle()
    CUDA.detect_state_changes()
    tid = Threads.threadid()
    if @inbounds thread_mg_handles[tid] === nothing
        ctx = context()
        thread_mg_handles[tid] = get!(task_local_storage(), (:CUSOLVER, :mg, ctx)) do
            handle = if isempty(idle_mg_handles[ctx])
                cusolverMgCreate()
            else
                pop!(idle_mg_handles[ctx])
            end

            finalizer(current_task()) do task
                push!(idle_mg_handles[ctx], handle)
            end
            # TODO: cusolverMgDestroy to preserve memory, or at exit?

            #cusolverMgSetStream(handle, stream())

            handle
        end
    end
    something(@inbounds thread_mg_handles[tid])
end

@inline function set_stream(stream::CuStream)
    ctx = context()
    tls = task_local_storage()
    dense_handle = get(tls, (:CUSOLVER, :dense, ctx), nothing)
    if dense_handle !== nothing
        cusolverDnSetStream(dense_handle, stream)
    end
    sparse_handle = get(tls, (:CUSOLVER, :sparse, ctx), nothing)
    if sparse_handle !== nothing
        cusolverSpSetStream(sparse_handle, stream)
    end
    return
end

function __init__()
    resize!(thread_dense_handles, Threads.nthreads())
    fill!(thread_dense_handles, nothing)

    resize!(thread_sparse_handles, Threads.nthreads())
    fill!(thread_sparse_handles, nothing)

    resize!(thread_mg_handles, Threads.nthreads())
    fill!(thread_mg_handles, nothing)

    CUDA.atdeviceswitch() do
        tid = Threads.threadid()
        thread_dense_handles[tid] = nothing
        thread_sparse_handles[tid] = nothing
        thread_mg_handles[tid] = nothing
    end

    CUDA.attaskswitch() do
        tid = Threads.threadid()
        thread_dense_handles[tid] = nothing
        thread_sparse_handles[tid] = nothing
        thread_mg_handles[tid] = nothing
    end
end

end
