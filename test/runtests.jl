using FindFirstFunctions
using Test

@testset "FindFirstFunctions.jl" begin

  for n = 0:128
    x = unique!(rand(Int, n))
    for i = eachindex(x)
      @test FindFirstFunctions.findfirstequal(x[i], x) == i
    end
    if length(x) > 0
      @test FindFirstFunctions.findfirstequal(x[begin], @view(x[begin:end])) === 1
      @test FindFirstFunctions.findfirstequal(x[begin], @view(x[begin+1:end])) === nothing
      @test FindFirstFunctions.findfirstequal(x[end], @view(x[begin:end-1])) === nothing
    end
    y = rand(Int)
    @test FindFirstFunctions.findfirstequal(y, x) === findfirst(==(y), x)
  end

end


