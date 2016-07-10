# CUDAnative.jl

**CUDA programming interface for Julia, with native code execution support.**

[![Coverage Status](https://codecov.io/gh/JuliaGPU/CUDAnative.jl/coverage.svg)](https://codecov.io/gh/JuliaGPU/CUDAnative.jl)

This package wraps key functions in CUDA driver API for Julia, and provides
support for writing native Julia kernels for execution on an NVIDIA GPU. It
requires a version of Julia capable of generating PTX code, such as
[JuliaGPU/julia](https://github.com/JuliaGPU/julia).


## Setup

1. Install the NVIDIA driver, and make sure `libcuda` is in your library loading
   path. If NVIDIA hardware is unavailable, you can use the [GPU Ocelot
   emulator](https://github.com/maleadt/gpuocelot) instead, but note that this
   emulator is not actively maintained and many API functions are not (properly)
   implemented.

2. Install the CUDA toolkit (not all versions are supported, you might need to
   install an older version). This is independent from whether you're using the
   NVIDIA driver or GPU Ocelot emulator. If you want to run the test suite, make
   sure the location of `nvcc` is part of your `PATH` environment variable.

3. Install a version of Julia with PTX support, and use that `julia` binary for
   all future steps.

4. Clone and test this package in Julia:

   ```julia
   Pkg.clone("https://github.com/JuliaGPU/CUDAnative.jl.git")
   Pkg.test("CUDAnative")
   ```


## Example

The following example shows how to add two vectors on the GPU:

**Writing the kernel**

First you have to write the computation kernel and mark it `@target ptx`:

```julia
using CUDAnative

@target ptx function kernel_vadd(a, b, c)
    i = blockIdx().x +  (threadIdx().x-1) * gridDim().x
    c[i] = a[i] + b[i]

    return nothing
end

```

**Launching the kernel**

Using the `@cuda` macro, you can launch the kernel on a GPU of your choice:

```julia
using CUDAnative

# select a CUDA device
dev = CuDevice(0)

# create context on the selected device
ctx = CuContext(dev)

# generate random arrays and load them to GPU
a = round(rand(Float32, (3, 4)) * 100)
b = round(rand(Float32, (3, 4)) * 100)
d_a = CuArray(a)
d_b = CuArray(b)

# create an array on GPU to store results
d_c = CuArray(Float32, (3, 4))

# run the kernel and fetch results
# syntax: @cuda (dims...) kernel(args...)
@cuda (12, 1) kernel_vadd(d_a, d_b, d_c)
c = Array(d_c)

# print the results
println("Results:")
println("a = \n$a")
println("b = \n$b")
println("c = \n$c")

# finalize: destroy context
destroy(ctx)
```

See `examples` or `tests/native.jl` for more comprehensive examples.


## Advanced use

### Override autodetection

The library tries to autodetect some properties of the available toolkit and
hardware when it is initialized. If these results are wrong, or you want to
override settings, there are several environment variables to use:

* `CUDA_FORCE_API_VERSION`: this mimics the macro from `cuda.h`, with the same
  format.
* `CUDA_FORCE_GPU_ARCH`: GPU architecture to pass to `nvcc` when compiling
  inline CUDA sources
