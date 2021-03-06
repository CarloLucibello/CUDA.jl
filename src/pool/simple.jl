module SimplePool

# simple scan into a list of free buffers

using ..CUDA
import ..CUDA: actual_alloc, actual_free, PerDevice, initialize!

using ..PoolUtils


## tunables

# how much larger a buf can be to fullfil an allocation request.
# lower values improve efficiency, but increase pressure on the underlying GC.
function max_oversize(sz)
    if sz <= 2^20       # 1 MiB
        # small buffers are fine no matter
        return typemax(Int)
    elseif sz <= 2^20   # 32 MiB
        return 2^20
    else
        return 2^22
    end
end


## pooling

const pool_lock = ReentrantLock()
const pool = PerDevice{Set{Block}}() do dev
    Set{Block}()
end

const freed_lock = NonReentrantLock()
const freed = PerDevice{Vector{Block}}() do dev
    Vector{Block}()
end

function scan(dev, sz)
    @lock pool_lock for block in pool[dev]
        if sz <= sizeof(block) <= max_oversize(sz)
            delete!(pool[dev], block)
            return block
        end
    end
    return
end

function repopulate(dev)
    blocks = @lock freed_lock begin
        isempty(freed[dev]) && return
        blocks = Set(freed[dev])
        empty!(freed[dev])
        blocks
    end

    @lock pool_lock begin
        for block in blocks
            @assert !in(block, pool[dev])
            push!(pool[dev], block)
        end
    end

    return
end

function reclaim(dev, sz::Int=typemax(Int))
    repopulate(dev)

    @lock pool_lock begin
        freed_bytes = 0
        while freed_bytes < sz && !isempty(pool[dev])
            block = pop!(pool[dev])
            freed_bytes += sizeof(block)
            actual_free(dev, block)
        end
        return freed_bytes
    end
end

function alloc(dev, sz)
    block = nothing
    for phase in 1:3
        if phase == 2
            @pool_timeit "$phase.0 gc (incremental)" GC.gc(false)
        elseif phase == 3
            @pool_timeit "$phase.0 gc (full)" GC.gc(true)
        end

        @pool_timeit "$phase.1 repopulate" repopulate(dev)

        @pool_timeit "$phase.2 scan" begin
            block = scan(dev, sz)
        end
        block === nothing || break

        @pool_timeit "$phase.3 alloc" begin
            block = actual_alloc(dev, sz)
        end
        block === nothing || break

        @pool_timeit "$phase.4 reclaim + alloc" begin
            reclaim(dev, sz)
            block = actual_alloc(dev, sz, phase==3)
        end
        block === nothing || break
    end

    return block
end

function free(dev, block)
    # we don't do any work here to reduce pressure on the GC (spending time in finalizers)
    # and to simplify locking (preventing concurrent access during GC interventions)
    @spinlock freed_lock begin
        push!(freed[dev], block)
    end
end

function init()
    initialize!(pool, ndevices())
    initialize!(freed, ndevices())
end

function cached_memory(dev=device())
    sz = @lock freed_lock mapreduce(sizeof, +, freed[dev]; init=0)
    sz += @lock pool_lock mapreduce(sizeof, +, pool[dev]; init=0)
    return sz
end

end
