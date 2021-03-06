using AutoDiffSource

remap(x::AFArray) = Array(x)
remap(y) = map(x -> isa(x, AFArray) ? Array(x) : x, y)

function checkdiff_inferred(f, δf, x0...)
    x = [x0...]
    y0 = f(x...)
    @assert length(y0) == 1 "Scalar functions only"
    y, ∇f = Test.@inferred δf(x...)
    @assert isapprox(y0, y) "Return values do not match"
    @assert typeof(y0) === typeof(y) "Return type doesn't match"
    ∂x = @inferred ∇f(1.0)
    if isa(∂x, Tuple)
        @assert typeof(x0) === typeof(∂x) "Gradient type doesn't match: $(typeof(x0)) vs $(typeof(∂x))"
    else
        @assert typeof(x0) === typeof((∂x,)) "Gradient type doesn't match: : $(typeof(x0)) vs $(typeof((∂x,)))"
    end
    checkgrad(f, remap(x), remap(∂x))
end

import AutoDiffSource: δsum, δdot_power, δdot_power_const1, δdot_power_const2
import AutoDiffSource: δabs, δsqrt, δexp, δlog, δtimes, δtimes_const1, δtimes_const2

δsum(x::AFArray) = (t = size(x); (sum(x), z->constant(z, t)))
δdot_power(x::AFArray, y::AbstractFloat) = (t = x.^y; (t, z->(z.*y.*t ./ x, sum(z.*t.*log(x)))))
δdot_power(x::AbstractFloat, y::AFArray) = (t = x.^y; (t, z->(sum(z.*y.*t)./x, z.*t.*log(x))))
δdot_power(x::AFMatrix, y::AFVector) = (t = x.^y; (t, z->(z.*y.*t./x, vec(sum(z.*t.*log(x), 2)))))
δdot_power(x::AFVector, y::AFMatrix) = (t = x.^y; (t, z->(vec(sum(z.*y.*t./x, 2)), z.*t.*log(x))))
δdot_power_const1(x, y::AFArray) = (t = x.^y; (t, z->z.*t.*log(x)))
δdot_power_const2(x::AFArray, y) = (t = x.^y; (t, z-> y == 2 ? z.*2x : z.*y.*t./x))
δdot_power(x::AFArray, y::AFArray) = (t = x.^y; (t, z->(z.*y.*t./x, z.*t.*log(x))))
δabs(x::AFArray) = (abs(x), z->z.*sign(x))
δsqrt(x::AFArray) = (t = sqrt(x); (t, z->0.5*z./t))
δexp(x::AFArray) = (t = exp(x); (t, z->z.*t))
δlog(x::AFArray) = (log(x), z->z./x)
δtimes(x::AFVector, y::AFMatrix) = (x*y, z->(@show typeof(x), typeof(y), typeof(z); (vec(A_mul_Bt(z,y)), At_mul_B(x,z))))
δtimes(x::AFMatrix, y::AFVector) = (x*y, z->(A_mul_Bt(z,y), vec(At_mul_B(x,z))))
δtimes(x::AFMatrix, y::AFMatrix) = (x*y, z->(A_mul_Bt(z,y), At_mul_B(x,z)))
δtimes_const1(x, y::AFArray) = (x*y, z->(At_mul_B(x,z)))
δtimes_const2(x::AFArray, y) = (x*y, z->(A_mul_Bt(z,y)))

rnd() = rand(AFArray{Float64}, 1)
rnd(len) = rand(AFArray{Float64}, len)
rnd(len1, len2) = rand(AFArray{Float64}, (len1, len2))
rndn(len) = randn(AFArray{Float64}, len)
rndn(len1, len2) = randn(AFArray{Float64}, (len1, len2))

@testset "Autodiff" begin
@test checkdiff_inferred(sum, δsum, rndn(3)+rnd(3))
@test checkdiff_inferred(sum, δsum, rnd(3, 2) + rndn(3, 2))

#@δ f9(x, y) = sum(x * y)
#@test checkdiff_inferred(f9, δf9, rnd(3), rnd(3)')
#@test checkdiff_inferred(f9, δf9, rnd(3)', rnd(3))
#@test checkdiff_inferred(f9, δf9, rnd(3)', rnd(3, 3))
#@test checkdiff_inferred(f9, δf9, rnd(3, 3), rnd(3))
#@test checkdiff_inferred(f9, δf9, rnd(3, 3), rnd(3, 3))

# (scalar, scalar), (scalar, const), (const, scalar), (const, const)
for o in [:+, :-, :*]
    t = gensym(o)
    δt = Symbol("δ$t")
    @eval @δ $t(x) = sum($o(x, 2.))
    @test @eval checkdiff_inferred($t, $δt, rnd())
    t = gensym(o)
    δt = Symbol("δ$t")
    @eval @δ $t(x) = sum($o(2., x))
    @test @eval checkdiff_inferred($t, $δt, rnd())
end

# (vector, scalar), (matrix, scalar), (scalar, vector), (scalar, matrix), (const, *), (*, const)
for o in [:+, :-, :*]
    t = gensym(o)
    δt = Symbol("δ$t")
    @eval @δ $t(x, y) = sum($o(x, y))
    @eval @test checkdiff_inferred($t, $δt, rnd(5), rand())
    @eval @test checkdiff_inferred($t, $δt, rnd(3, 2), rand())
    @eval @test checkdiff_inferred($t, $δt, rand(), rnd(5))
    @eval @test checkdiff_inferred($t, $δt, rand(), rnd(3, 2))

    t = gensym(o)
    δt = Symbol("δ$t")
    @eval @δ $t(x) = sum($o(x, 4.))
    @eval @test checkdiff_inferred($t, $δt, rnd(5))
    @eval @test checkdiff_inferred($t, $δt, rnd(3, 2))

    t = gensym(o)
    δt = Symbol("δ$t")
    @eval @δ $t(x) = sum($o(5., x))
    @eval @test checkdiff_inferred($t, $δt, rnd(5))
    @eval @test checkdiff_inferred($t, $δt, rnd(3, 2))
end

# (vector, scalar), (matrix, scalar), (*, const)
for o in [:/]
    t = gensym(o)
    δt = Symbol("δ$t")
    @eval @δ $t(x, y) = sum($o(x, y))
    @eval @test checkdiff_inferred($t, $δt, rnd(5), rand())
    @eval @test checkdiff_inferred($t, $δt, rnd(3, 2), rand())

    t = gensym(o)
    δt = Symbol("δ$t")
    @eval @δ $t(x) = sum($o(x, 5.))
    @eval @test checkdiff_inferred($t, $δt, rnd(5))
    @eval @test checkdiff_inferred($t, $δt, rnd(3, 2))
end

#for o in [:dot]
#    t = gensym(o)
#    δt = Symbol("δ$t")
#    @eval @δ $t(x, y) = sum($o(x, y))
#    @eval @test checkdiff_inferred($t, $δt, rnd(5), rnd(5))
#end

# (vector), (matrix)
#for o in [:sqrt, :exp, :log, :-]
#    t = gensym(o)
#    δt = Symbol("δ$t")
#    @eval @δ $t(x) = sum($o(x))
#    @eval @test checkdiff_inferred($t, $δt, rnd(5))
#    @eval @test checkdiff_inferred($t, $δt, rnd(2, 3))
#end

# Test example
#@δ sigmoid(x) = 1 ./ (1 + exp(x))

#@δ function autoencoder(We1, We2, Wd, b1, b2, input)
#    firstLayer = sigmoid(We1 * input + b1)
#    encodedInput = sigmoid(We2 * firstLayer + b2)
#    reconstructedInput = sigmoid(Wd * encodedInput)
#    return reconstructedInput
#end

#@δ function autoencoderError(We1, We2, Wd, b1, b2, input)
#    reconstructedInput = autoencoder(We1, We2, Wd, b1, b2, input)
#    return sum((input - reconstructedInput).^2)
#end

#@assert checkdiff_inferred(autoencoderError, δautoencoderError, rndn(3,3), rndn(3,3), rnd(3,3), rndn(3), rndn(3), rndn(3))
end
