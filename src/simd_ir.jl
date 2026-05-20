# SIMD LLVM IR scaffolding shared by every "find first lane matching
# predicate" routine in the package:
#
#   - `FFE_IR` / `_findfirstequal`     — exact equality scan, Int64
#                                         (predicate `icmp eq`)
#   - `_SIMD_GT_I64_IR` / `_simd_first_gt(::Int64, …)`     — `icmp sgt`
#   - `_SIMD_GE_I64_IR` / `_simd_first_ge(::Int64, …)`     — `icmp sge`
#   - `_SIMD_GT_F64_IR` / `_simd_first_gt(::Float64, …)`   — `fcmp ogt`
#   - `_SIMD_GE_F64_IR` / `_simd_first_ge(::Float64, …)`   — `fcmp oge`
#
# All five IR strings are generated from the same template, keyed on scalar
# LLVM type (`i64`, `double`) and compare predicate. Adding a new predicate
# is a single `_simd_scan_ir(t, pred)` call plus a corresponding
# `Base.llvmcall` wrapper.

# Generate the SIMD "find first lane matching predicate" IR for an arbitrary
# scalar type and LLVM compare predicate. Load 8 lanes at a time, compare
# against a broadcast of the search value, bitcast the i1×8 mask to i8,
# `cttz` to find the first set bit. The tail past the last full chunk is
# handled scalar-wise.
function _simd_scan_ir(t, pred)
    cmp = pred[1] in ('o', 'u') ? "fcmp" : "icmp"
    return """
    declare i8 @llvm.cttz.i8(i8, i1);
    define i64 @entry($t %0, $(USE_PTR ? "ptr" : "i64") %1, i64 %2) #0 {
    top:
      $(USE_PTR ? "" : "%ivars = inttoptr i64 %1 to $t*")
      %btmp = insertelement <8 x $t> undef, $t %0, i64 0
      %var = shufflevector <8 x $t> %btmp, <8 x $t> undef, <8 x i32> zeroinitializer
      %lenm7 = add nsw i64 %2, -7
      %dosimditer = icmp ugt i64 %2, 7
      br i1 %dosimditer, label %L9.lr.ph, label %L32

    L9.lr.ph:
      %len8 = and i64 %2, 9223372036854775800
      br label %L9

    L9:
      %i = phi i64 [ 0, %L9.lr.ph ], [ %vinc, %L30 ]
      %ivarsi = getelementptr inbounds $t, $(USE_PTR ? "ptr %1" : "$t* %ivars"), i64 %i
      $(USE_PTR ? "" : "%vpvi = bitcast $t* %ivarsi to <8 x $t>*")
      %v = load <8 x $t>, $(USE_PTR ? "ptr %ivarsi" : "<8 x $t> * %vpvi"), align 8
      %m = $cmp $pred <8 x $t> %v, %var
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
      %spi = getelementptr inbounds $t, $(USE_PTR ? "ptr %1" : "$t* %ivars"), i64 %si
      %svi = load $t, $(USE_PTR ? "ptr" : "$t*") %spi, align 8
      %match = $cmp $pred $t %svi, %0
      br i1 %match, label %common.ret, label %L67

    L67:
      %inc = add i64 %si, 1
      %dobreak = icmp eq i64 %inc, %2
      br i1 %dobreak, label %common.ret, label %L51

    }
    attributes #0 = { alwaysinline }
    """
end

const FFE_IR = _simd_scan_ir("i64", "eq")

function _findfirstequal(vpivot::Int64, ptr::Ptr{Int64}, len::Int64)
    return Base.llvmcall(
        (FFE_IR, "entry"),
        Int64,
        Tuple{Int64, Ptr{Int64}, Int64},
        vpivot,
        ptr,
        len
    )
end

const _SIMD_GT_I64_IR = _simd_scan_ir("i64", "sgt")
const _SIMD_GE_I64_IR = _simd_scan_ir("i64", "sge")
const _SIMD_GT_F64_IR = _simd_scan_ir("double", "ogt")
const _SIMD_GE_F64_IR = _simd_scan_ir("double", "oge")

# Reverse-direction predicates: used by `SIMDLinearScan` under
# `Base.Order.Reverse` ordering, where the array is decreasing and we want
# to find the first lane where `v[i] < x` (searchsortedlast) or `v[i] <= x`
# (searchsortedfirst).
const _SIMD_LT_I64_IR = _simd_scan_ir("i64", "slt")
const _SIMD_LE_I64_IR = _simd_scan_ir("i64", "sle")
const _SIMD_LT_F64_IR = _simd_scan_ir("double", "olt")
const _SIMD_LE_F64_IR = _simd_scan_ir("double", "ole")

# Backing primitives for SIMDLinearScan. Each returns the 0-based offset of
# the first lane satisfying the predicate, or -1 if none. Caveat: NaN inputs
# always compare false under the ordered `o*` float predicates, so NaN in `v`
# or `x` produces "no match" rather than an exception — consistent with the
# undefined-input contract for sorted Float64 vectors containing NaN.
function _simd_first_gt(x::Int64, ptr::Ptr{Int64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_GT_I64_IR, "entry"),
        Int64, Tuple{Int64, Ptr{Int64}, Int64},
        x, ptr, len
    )
end
function _simd_first_ge(x::Int64, ptr::Ptr{Int64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_GE_I64_IR, "entry"),
        Int64, Tuple{Int64, Ptr{Int64}, Int64},
        x, ptr, len
    )
end
function _simd_first_gt(x::Float64, ptr::Ptr{Float64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_GT_F64_IR, "entry"),
        Int64, Tuple{Float64, Ptr{Float64}, Int64},
        x, ptr, len
    )
end
function _simd_first_ge(x::Float64, ptr::Ptr{Float64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_GE_F64_IR, "entry"),
        Int64, Tuple{Float64, Ptr{Float64}, Int64},
        x, ptr, len
    )
end

# Reverse-direction primitives.
function _simd_first_lt(x::Int64, ptr::Ptr{Int64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_LT_I64_IR, "entry"),
        Int64, Tuple{Int64, Ptr{Int64}, Int64},
        x, ptr, len
    )
end
function _simd_first_le(x::Int64, ptr::Ptr{Int64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_LE_I64_IR, "entry"),
        Int64, Tuple{Int64, Ptr{Int64}, Int64},
        x, ptr, len
    )
end
function _simd_first_lt(x::Float64, ptr::Ptr{Float64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_LT_F64_IR, "entry"),
        Int64, Tuple{Float64, Ptr{Float64}, Int64},
        x, ptr, len
    )
end
function _simd_first_le(x::Float64, ptr::Ptr{Float64}, len::Int64)
    return Base.llvmcall(
        (_SIMD_LE_F64_IR, "entry"),
        Int64, Tuple{Float64, Ptr{Float64}, Int64},
        x, ptr, len
    )
end
