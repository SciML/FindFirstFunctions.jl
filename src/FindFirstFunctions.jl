module FindFirstFunctions


function _findfirstequal(vpivot::Int64, ptr::Ptr{Int64}, len::Int64)
  Base.llvmcall(("""
                         declare i8 @llvm.cttz.i8(i8, i1);
                         define i64 @entry(i64 %0, i64 %1, i64 %2) #0 {
                         top:
                           %ivars = inttoptr i64 %1 to i64*
                           %btmp = insertelement <8 x i64> undef, i64 %0, i64 0
                           %var = shufflevector <8 x i64> %btmp, <8 x i64> undef, <8 x i32> zeroinitializer
                           %lenm7 = add nsw i64 %2, -7
                           %dosimditer = icmp ugt i64 %2, 7
                           br i1 %dosimditer, label %L9.lr.ph, label %L32

                         L9.lr.ph:
                           %len8 = and i64 %2, 9223372036854775800
                           br label %L9

                         L9:
                           %i = phi i64 [ 0, %L9.lr.ph ], [ %vinc, %L30 ]
                           %ivarsi = getelementptr inbounds i64, i64* %ivars, i64 %i
                           %vpvi = bitcast i64* %ivarsi to <8 x i64>*
                           %v = load <8 x i64>, <8 x i64>* %vpvi, align 8
                           %m = icmp eq <8 x i64> %v, %var
                           %mu = bitcast <8 x i1> %m to i8
                           %matchnotfound = icmp eq i8 %mu, 0
                           br i1 %matchnotfound, label %L30, label %L17

                         L17:
                           %tz8 = call i8 @llvm.cttz.i8(i8 %mu, i1 true)
                           %tz64 = zext i8 %tz8 to i64
                           %vis = add nuw i64 %i, %tz64
                           br label %common.ret

                         common.ret:
                           %retval = phi i64 [ %vis, %L17 ], [ -1, %L32 ], [ %si, %L51 ], [ -1, %L67 ]
                           ret i64 %retval

                         L30:
                           %vinc = add nuw nsw i64 %i, 8
                           %continue = icmp slt i64 %vinc, %lenm7
                           br i1 %continue, label %L9, label %L32

                         L32:
                           %cumi = phi i64 [ 0, %top ], [ %len8, %L30 ]
                           %done = icmp eq i64 %cumi, %2
                           br i1 %done, label %common.ret, label %L51

                         L51:
                           %si = phi i64 [ %inc, %L67 ], [ %cumi, %L32 ]
                           %spi = getelementptr inbounds i64, i64* %ivars, i64 %si
                           %svi = load i64, i64* %spi, align 8
                           %match = icmp eq i64 %svi, %0
                           br i1 %match, label %common.ret, label %L67

                         L67:
                           %inc = add i64 %si, 1
                           %dobreak = icmp eq i64 %inc, %2
                           br i1 %dobreak, label %common.ret, label %L51

                         }
                         attributes #0 = { alwaysinline }
      """, "entry"), Int64, Tuple{Int64,Ptr{Int64},Int64}, vpivot, ptr,
    len)
end

findfirstequal(vpivot, ivars) = findfirst(isequal(vpivot), ivars)
function findfirstequal(vpivot::Int64, ivars::DenseVector{Int64})
  GC.@preserve ivars begin
    ret = _findfirstequal(vpivot, pointer(ivars), length(ivars))
  end
  ret < 0 ? nothing : ret + 1
end

"""
  findfirstsortedequal(vars::DenseVector{Int64}, var::Int64)::Union{Int64,Nothing}

Note that this differs from `searchsortedfirst` by returning `nothing` when absent.
"""
function findfirstsortedequal(var::Int64, vars::DenseVector{Int64},
  ::Val{basecase}=Val(16)) where {basecase}
  len = length(vars)
  offset = 0
  @inbounds while len > basecase
    half = len >>> 1 # half on left, len - half on right
    offset = ifelse(vars[offset+half+1] <= var, half + offset, offset)
    len = len - half
  end
  # maybe occurs in vars[offset+1:offset+len] 
  GC.@preserve vars begin
    ret = _findfirstequal(var, pointer(vars) + 8offset, len)
  end
  ret < 0 ? nothing : ret + offset + 1
end


"""
    bracketstrictlymontonic(v, x, guess; lt=<comparison>, by=<transform>, rev=false)

Starting from an initial `guess` index, find indices `(lo, hi)` such that `v[lo] ≤ x ≤
v[hi]` according to the specified order, assuming that `x` is actually within the range of
values found in `v`.  If `x` is outside that range, either `lo` will be `firstindex(v)` or
`hi` will be `lastindex(v)`.

Note that the results will not typically satisfy `lo ≤ guess ≤ hi`.  If `x` is precisely
equal to a value that is not unique in the input `v`, there is no guarantee that `(lo, hi)`
will encompass *all* indices corresponding to that value.

This algorithm is essentially an expanding binary search, which can be used as a precursor
to `searchsorted` and related functions, which can take `lo` and `hi` as arguments.  The
purpose of using this function first would be to accelerate convergence in those functions
by using correlated `guess`es for repeated calls.  The best `guess` for the next call of
this function would be the index returned by the previous call to `searchsorted`.

See [`sort!`](@ref) for an explanation of the keyword arguments `by`, `lt` and `rev`.
"""
function bracketstrictlymontonic(v::AbstractVector,
  x,
  guess::T,
  o::Base.Order.Ordering)::NTuple{2,keytype(v)} where {T<:Integer}
  bottom = firstindex(v)
  top = lastindex(v)
  if guess < bottom || guess > top
    return bottom, top
    # # NOTE: for cache efficiency in repeated calls, we avoid accessing the first and last elements of `v`
    # # on each call to this function.  This should only result in significant slow downs for calls with
    # # out-of-bounds values of `x` *and* bad `guess`es.
    # elseif lt(o, x, v[bottom])
    #     return bottom, bottom
    # elseif lt(o, v[top], x)
    #     return top, top
  else
    u = T(1)
    lo, hi = guess, min(guess + u, top)
    @inbounds if Base.Order.lt(o, x, v[lo])
      while lo > bottom && Base.Order.lt(o, x, v[lo])
        lo, hi = max(bottom, lo - u), lo
        u += u
      end
    else
      while hi < top && !Base.Order.lt(o, x, v[hi])
        lo, hi = hi, min(top, hi + u)
        u += u
      end
    end
  end
  return lo, hi
end

function searchsortedfirstcorrelated(v::AbstractVector, x, guess)
  lo, hi = bracketstrictlymontonic(v, x, guess, Base.Order.Forward)
  searchsortedfirst(v, x, lo, hi, Base.Order.Forward)
end

function searchsortedlastcorrelated(v::AbstractVector, x, guess)
  lo, hi = bracketstrictlymontonic(v, x, guess, Base.Order.Forward)
  searchsortedlast(v, x, lo, hi, Base.Order.Forward)
end

searchsortedfirstcorrelated(r::AbstractRange, x, _) = searchsortedfirst(r, x)
searchsortedlastcorrelated(r::AbstractRange, x, _) = searchsortedlast(r, x)

end
