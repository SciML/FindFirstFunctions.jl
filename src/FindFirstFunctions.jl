module FindFirstFunctions

findfirstequal(vpivot, ivars) = findfirst(isequal(vpivot), ivars)
function findfirstequal(vpivot::Int64, ivars::DenseVector{Int64})
  GC.@preserve ivars begin
    ret = Base.llvmcall(("""
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
    """, "entry"), Int64, Tuple{Int64,Ptr{Int64},Int64}, vpivot, pointer(ivars),
      length(ivars))
  end
  ret < 0 ? nothing : ret + 1
end


end
