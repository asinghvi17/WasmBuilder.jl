let
    definst!(:i32_load, 0x28, (:memarg,); sig=fixedsig((I32,), (I32,)), alignment=2)
    definst!(:i64_load, 0x29, (:memarg,); sig=fixedsig((I32,), (I64,)), alignment=3)
    definst!(:f32_load, 0x2a, (:memarg,); sig=fixedsig((I32,), (F32,)), alignment=2)
    definst!(:f64_load, 0x2b, (:memarg,); sig=fixedsig((I32,), (F64,)), alignment=3)
    definst!(:i32_load8_s, 0x2c, (:memarg,); sig=fixedsig((I32,), (I32,)), alignment=0)
    definst!(:i32_load8_u, 0x2d, (:memarg,); sig=fixedsig((I32,), (I32,)), alignment=0)
    definst!(:i32_load16_s, 0x2e, (:memarg,); sig=fixedsig((I32,), (I32,)), alignment=1)
    definst!(:i32_load16_u, 0x2f, (:memarg,); sig=fixedsig((I32,), (I32,)), alignment=1)
    definst!(:i64_load8_s, 0x30, (:memarg,); sig=fixedsig((I32,), (I64,)), alignment=0)
    definst!(:i64_load8_u, 0x31, (:memarg,); sig=fixedsig((I32,), (I64,)), alignment=0)
    definst!(:i64_load16_s, 0x32, (:memarg,); sig=fixedsig((I32,), (I64,)), alignment=1)
    definst!(:i64_load16_u, 0x33, (:memarg,); sig=fixedsig((I32,), (I64,)), alignment=1)
    definst!(:i64_load32_s, 0x34, (:memarg,); sig=fixedsig((I32,), (I64,)), alignment=2)
    definst!(:i64_load32_u, 0x35, (:memarg,); sig=fixedsig((I32,), (I64,)), alignment=2)
    definst!(:i32_store, 0x36, (:memarg,); sig=fixedsig((I32, I32), ()), alignment=2)
    definst!(:i64_store, 0x37, (:memarg,); sig=fixedsig((I32, I64), ()), alignment=3)
    definst!(:f32_store, 0x38, (:memarg,); sig=fixedsig((I32, F32), ()), alignment=2)
    definst!(:f64_store, 0x39, (:memarg,); sig=fixedsig((I32, F64), ()), alignment=3)
    definst!(:i32_store8, 0x3a, (:memarg,); sig=fixedsig((I32, I32), ()), alignment=0)
    definst!(:i32_store16, 0x3b, (:memarg,); sig=fixedsig((I32, I32), ()), alignment=1)
    definst!(:i64_store8, 0x3c, (:memarg,); sig=fixedsig((I32, I64), ()), alignment=0)
    definst!(:i64_store16, 0x3d, (:memarg,); sig=fixedsig((I32, I64), ()), alignment=1)
    definst!(:i64_store32, 0x3e, (:memarg,); sig=fixedsig((I32, I64), ()), alignment=2)
    definst!(:memory_size, 0x3f, (:memidx,); sig=fixedsig((), (I32,)))
    definst!(:memory_grow, 0x40, (:memidx,); sig=fixedsig((I32,), (I32,)))
    definst!(:memory_init, (0xfc, 8), (:dataidx, :memidx); sig=fixedsig((I32, I32, I32), ()))
    definst!(:data_drop, (0xfc, 9), (:dataidx,); sig=fixedsig((), ()))
    definst!(:memory_copy, (0xfc, 10), (:memidx, :memidx); sig=fixedsig((I32, I32, I32), ()))
    definst!(:memory_fill, (0xfc, 11), (:memidx,); sig=fixedsig((I32, I32, I32), ()))

    simd(op, n, imms=(); kw...) = definst!(op, leb_code(0xfd, n), imms; kw...)
    simd(:v128_load, 0x00, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=4)
    simd(:v128_load8x8_s, 0x01, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=3)
    simd(:v128_load8x8_u, 0x02, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=3)
    simd(:v128_load16x4_s, 0x03, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=3)
    simd(:v128_load16x4_u, 0x04, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=3)
    simd(:v128_load32x2_s, 0x05, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=3)
    simd(:v128_load32x2_u, 0x06, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=3)
    simd(:v128_load8_splat, 0x07, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=0)
    simd(:v128_load16_splat, 0x08, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=1)
    simd(:v128_load32_splat, 0x09, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=2)
    simd(:v128_load64_splat, 0x0a, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=3)
    simd(:v128_store, 0x0b, (:memarg,); sig=fixedsig((I32, V128), ()), alignment=4)
    simd(:v128_const, 0x0c, (:v128,); sig=fixedsig((), (V128,)))
    simd(:i8x16_shuffle, 0x0d, (:lanes16,); sig=fixedsig((V128, V128), (V128,)))
    simd(:i8x16_extract_lane_s, 0x15, (:lane,); sig=fixedsig((V128,), (I32,)), lanes=16)
    simd(:i8x16_extract_lane_u, 0x16, (:lane,); sig=fixedsig((V128,), (I32,)), lanes=16)
    simd(:i8x16_replace_lane, 0x17, (:lane,); sig=fixedsig((V128, I32), (V128,)), lanes=16)
    simd(:i16x8_extract_lane_s, 0x18, (:lane,); sig=fixedsig((V128,), (I32,)), lanes=8)
    simd(:i16x8_extract_lane_u, 0x19, (:lane,); sig=fixedsig((V128,), (I32,)), lanes=8)
    simd(:i16x8_replace_lane, 0x1a, (:lane,); sig=fixedsig((V128, I32), (V128,)), lanes=8)
    simd(:i32x4_extract_lane, 0x1b, (:lane,); sig=fixedsig((V128,), (I32,)), lanes=4)
    simd(:i32x4_replace_lane, 0x1c, (:lane,); sig=fixedsig((V128, I32), (V128,)), lanes=4)
    simd(:i64x2_extract_lane, 0x1d, (:lane,); sig=fixedsig((V128,), (I64,)), lanes=2)
    simd(:i64x2_replace_lane, 0x1e, (:lane,); sig=fixedsig((V128, I64), (V128,)), lanes=2)
    simd(:f32x4_extract_lane, 0x1f, (:lane,); sig=fixedsig((V128,), (F32,)), lanes=4)
    simd(:f32x4_replace_lane, 0x20, (:lane,); sig=fixedsig((V128, F32), (V128,)), lanes=4)
    simd(:f64x2_extract_lane, 0x21, (:lane,); sig=fixedsig((V128,), (F64,)), lanes=2)
    simd(:f64x2_replace_lane, 0x22, (:lane,); sig=fixedsig((V128, F64), (V128,)), lanes=2)
    simd(:v128_load8_lane, 0x54, (:memarg, :lane); sig=fixedsig((I32, V128), (V128,)), alignment=0, lanes=16)
    simd(:v128_load16_lane, 0x55, (:memarg, :lane); sig=fixedsig((I32, V128), (V128,)), alignment=1, lanes=8)
    simd(:v128_load32_lane, 0x56, (:memarg, :lane); sig=fixedsig((I32, V128), (V128,)), alignment=2, lanes=4)
    simd(:v128_load64_lane, 0x57, (:memarg, :lane); sig=fixedsig((I32, V128), (V128,)), alignment=3, lanes=2)
    simd(:v128_store8_lane, 0x58, (:memarg, :lane); sig=fixedsig((I32, V128), ()), alignment=0, lanes=16)
    simd(:v128_store16_lane, 0x59, (:memarg, :lane); sig=fixedsig((I32, V128), ()), alignment=1, lanes=8)
    simd(:v128_store32_lane, 0x5a, (:memarg, :lane); sig=fixedsig((I32, V128), ()), alignment=2, lanes=4)
    simd(:v128_store64_lane, 0x5b, (:memarg, :lane); sig=fixedsig((I32, V128), ()), alignment=3, lanes=2)
    simd(:v128_load32_zero, 0x5c, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=2)
    simd(:v128_load64_zero, 0x5d, (:memarg,); sig=fixedsig((I32,), (V128,)), alignment=3)

    for (op, code) in (
        :i8x16_swizzle => 0x0e,
        :i8x16_eq => 0x23,
        :i8x16_ne => 0x24,
        :i8x16_lt_s => 0x25,
        :i8x16_lt_u => 0x26,
        :i8x16_gt_s => 0x27,
        :i8x16_gt_u => 0x28,
        :i8x16_le_s => 0x29,
        :i8x16_le_u => 0x2a,
        :i8x16_ge_s => 0x2b,
        :i8x16_ge_u => 0x2c,
        :i16x8_eq => 0x2d,
        :i16x8_ne => 0x2e,
        :i16x8_lt_s => 0x2f,
        :i16x8_lt_u => 0x30,
        :i16x8_gt_s => 0x31,
        :i16x8_gt_u => 0x32,
        :i16x8_le_s => 0x33,
        :i16x8_le_u => 0x34,
        :i16x8_ge_s => 0x35,
        :i16x8_ge_u => 0x36,
        :i32x4_eq => 0x37,
        :i32x4_ne => 0x38,
        :i32x4_lt_s => 0x39,
        :i32x4_lt_u => 0x3a,
        :i32x4_gt_s => 0x3b,
        :i32x4_gt_u => 0x3c,
        :i32x4_le_s => 0x3d,
        :i32x4_le_u => 0x3e,
        :i32x4_ge_s => 0x3f,
        :i32x4_ge_u => 0x40,
        :f32x4_eq => 0x41,
        :f32x4_ne => 0x42,
        :f32x4_lt => 0x43,
        :f32x4_gt => 0x44,
        :f32x4_le => 0x45,
        :f32x4_ge => 0x46,
        :f64x2_eq => 0x47,
        :f64x2_ne => 0x48,
        :f64x2_lt => 0x49,
        :f64x2_gt => 0x4a,
        :f64x2_le => 0x4b,
        :f64x2_ge => 0x4c,
        :v128_and => 0x4e,
        :v128_andnot => 0x4f,
        :v128_or => 0x50,
        :v128_xor => 0x51,
        :i8x16_narrow_i16x8_s => 0x65,
        :i8x16_narrow_i16x8_u => 0x66,
        :i8x16_add => 0x6e,
        :i8x16_add_sat_s => 0x6f,
        :i8x16_add_sat_u => 0x70,
        :i8x16_sub => 0x71,
        :i8x16_sub_sat_s => 0x72,
        :i8x16_sub_sat_u => 0x73,
        :i8x16_min_s => 0x76,
        :i8x16_min_u => 0x77,
        :i8x16_max_s => 0x78,
        :i8x16_max_u => 0x79,
        :i8x16_avgr_u => 0x7b,
        :i16x8_q15mulr_sat_s => 0x82,
        :i16x8_narrow_i32x4_s => 0x85,
        :i16x8_narrow_i32x4_u => 0x86,
        :i16x8_add => 0x8e,
        :i16x8_add_sat_s => 0x8f,
        :i16x8_add_sat_u => 0x90,
        :i16x8_sub => 0x91,
        :i16x8_sub_sat_s => 0x92,
        :i16x8_sub_sat_u => 0x93,
        :i16x8_mul => 0x95,
        :i16x8_min_s => 0x96,
        :i16x8_min_u => 0x97,
        :i16x8_max_s => 0x98,
        :i16x8_max_u => 0x99,
        :i16x8_avgr_u => 0x9b,
        :i16x8_extmul_low_i8x16_s => 0x9c,
        :i16x8_extmul_high_i8x16_s => 0x9d,
        :i16x8_extmul_low_i8x16_u => 0x9e,
        :i16x8_extmul_high_i8x16_u => 0x9f,
        :i32x4_add => 0xae,
        :i32x4_sub => 0xb1,
        :i32x4_mul => 0xb5,
        :i32x4_min_s => 0xb6,
        :i32x4_min_u => 0xb7,
        :i32x4_max_s => 0xb8,
        :i32x4_max_u => 0xb9,
        :i32x4_dot_i16x8_s => 0xba,
        :i32x4_extmul_low_i16x8_s => 0xbc,
        :i32x4_extmul_high_i16x8_s => 0xbd,
        :i32x4_extmul_low_i16x8_u => 0xbe,
        :i32x4_extmul_high_i16x8_u => 0xbf,
        :i64x2_add => 0xce,
        :i64x2_sub => 0xd1,
        :i64x2_mul => 0xd5,
        :i64x2_eq => 0xd6,
        :i64x2_ne => 0xd7,
        :i64x2_lt_s => 0xd8,
        :i64x2_gt_s => 0xd9,
        :i64x2_le_s => 0xda,
        :i64x2_ge_s => 0xdb,
        :i64x2_extmul_low_i32x4_s => 0xdc,
        :i64x2_extmul_high_i32x4_s => 0xdd,
        :i64x2_extmul_low_i32x4_u => 0xde,
        :i64x2_extmul_high_i32x4_u => 0xdf,
        :f32x4_add => 0xe4,
        :f32x4_sub => 0xe5,
        :f32x4_mul => 0xe6,
        :f32x4_div => 0xe7,
        :f32x4_min => 0xe8,
        :f32x4_max => 0xe9,
        :f32x4_pmin => 0xea,
        :f32x4_pmax => 0xeb,
        :f64x2_add => 0xf0,
        :f64x2_sub => 0xf1,
        :f64x2_mul => 0xf2,
        :f64x2_div => 0xf3,
        :f64x2_min => 0xf4,
        :f64x2_max => 0xf5,
        :f64x2_pmin => 0xf6,
        :f64x2_pmax => 0xf7,)
        simd(op, code; sig=fixedsig((V128, V128), (V128,)))
    end

    for (op, code) in (
        :i8x16_splat => 0x0f,
        :i16x8_splat => 0x10,
        :i32x4_splat => 0x11,)
        simd(op, code; sig=fixedsig((I32,), (V128,)))
    end

    simd(:i64x2_splat, 0x12; sig=fixedsig((I64,), (V128,)))

    simd(:f32x4_splat, 0x13; sig=fixedsig((F32,), (V128,)))

    simd(:f64x2_splat, 0x14; sig=fixedsig((F64,), (V128,)))

    for (op, code) in (
        :v128_not => 0x4d,
        :f32x4_demote_f64x2_zero => 0x5e,
        :f64x2_promote_low_f32x4 => 0x5f,
        :i8x16_abs => 0x60,
        :i8x16_neg => 0x61,
        :i8x16_popcnt => 0x62,
        :f32x4_ceil => 0x67,
        :f32x4_floor => 0x68,
        :f32x4_trunc => 0x69,
        :f32x4_nearest => 0x6a,
        :f64x2_ceil => 0x74,
        :f64x2_floor => 0x75,
        :f64x2_trunc => 0x7a,
        :i16x8_extadd_pairwise_i8x16_s => 0x7c,
        :i16x8_extadd_pairwise_i8x16_u => 0x7d,
        :i32x4_extadd_pairwise_i16x8_s => 0x7e,
        :i32x4_extadd_pairwise_i16x8_u => 0x7f,
        :i16x8_abs => 0x80,
        :i16x8_neg => 0x81,
        :i16x8_extend_low_i8x16_s => 0x87,
        :i16x8_extend_high_i8x16_s => 0x88,
        :i16x8_extend_low_i8x16_u => 0x89,
        :i16x8_extend_high_i8x16_u => 0x8a,
        :f64x2_nearest => 0x94,
        :i32x4_abs => 0xa0,
        :i32x4_neg => 0xa1,
        :i32x4_extend_low_i16x8_s => 0xa7,
        :i32x4_extend_high_i16x8_s => 0xa8,
        :i32x4_extend_low_i16x8_u => 0xa9,
        :i32x4_extend_high_i16x8_u => 0xaa,
        :i64x2_abs => 0xc0,
        :i64x2_neg => 0xc1,
        :i64x2_extend_low_i32x4_s => 0xc7,
        :i64x2_extend_high_i32x4_s => 0xc8,
        :i64x2_extend_low_i32x4_u => 0xc9,
        :i64x2_extend_high_i32x4_u => 0xca,
        :f32x4_abs => 0xe0,
        :f32x4_neg => 0xe1,
        :f32x4_sqrt => 0xe3,
        :f64x2_abs => 0xec,
        :f64x2_neg => 0xed,
        :f64x2_sqrt => 0xef,
        :i32x4_trunc_sat_f32x4_s => 0xf8,
        :i32x4_trunc_sat_f32x4_u => 0xf9,
        :f32x4_convert_i32x4_s => 0xfa,
        :f32x4_convert_i32x4_u => 0xfb,
        :i32x4_trunc_sat_f64x2_s_zero => 0xfc,
        :i32x4_trunc_sat_f64x2_u_zero => 0xfd,
        :f64x2_convert_low_i32x4_s => 0xfe,
        :f64x2_convert_low_i32x4_u => 0xff,)
        simd(op, code; sig=fixedsig((V128,), (V128,)))
    end

    simd(:v128_bitselect, 0x52; sig=fixedsig((V128, V128, V128), (V128,)))

    for (op, code) in (
        :v128_any_true => 0x53,
        :i8x16_all_true => 0x63,
        :i8x16_bitmask => 0x64,
        :i16x8_all_true => 0x83,
        :i16x8_bitmask => 0x84,
        :i32x4_all_true => 0xa3,
        :i32x4_bitmask => 0xa4,
        :i64x2_all_true => 0xc3,
        :i64x2_bitmask => 0xc4,)
        simd(op, code; sig=fixedsig((V128,), (I32,)))
    end

    for (op, code) in (
        :i8x16_shl => 0x6b,
        :i8x16_shr_s => 0x6c,
        :i8x16_shr_u => 0x6d,
        :i16x8_shl => 0x8b,
        :i16x8_shr_s => 0x8c,
        :i16x8_shr_u => 0x8d,
        :i32x4_shl => 0xab,
        :i32x4_shr_s => 0xac,
        :i32x4_shr_u => 0xad,
        :i64x2_shl => 0xcb,
        :i64x2_shr_s => 0xcc,
        :i64x2_shr_u => 0xcd,)
        simd(op, code; sig=fixedsig((V128, I32), (V128,)))
    end

    for (op, code) in (
        :i8x16_relaxed_swizzle => 0x100,
        :f32x4_relaxed_min => 0x10d,
        :f32x4_relaxed_max => 0x10e,
        :f64x2_relaxed_min => 0x10f,
        :f64x2_relaxed_max => 0x110,
        :i16x8_relaxed_q15mulr_s => 0x111,
        :i16x8_relaxed_dot_i8x16_i7x16_s => 0x112,)
        simd(op, code; sig=fixedsig((V128, V128), (V128,)), relaxed=true)
    end

    for (op, code) in (
        :i32x4_relaxed_trunc_f32x4_s => 0x101,
        :i32x4_relaxed_trunc_f32x4_u => 0x102,
        :i32x4_relaxed_trunc_f64x2_s_zero => 0x103,
        :i32x4_relaxed_trunc_f64x2_u_zero => 0x104,)
        simd(op, code; sig=fixedsig((V128,), (V128,)), relaxed=true)
    end

    for (op, code) in (
        :f32x4_relaxed_madd => 0x105,
        :f32x4_relaxed_nmadd => 0x106,
        :f64x2_relaxed_madd => 0x107,
        :f64x2_relaxed_nmadd => 0x108,
        :i8x16_relaxed_laneselect => 0x109,
        :i16x8_relaxed_laneselect => 0x10a,
        :i32x4_relaxed_laneselect => 0x10b,
        :i64x2_relaxed_laneselect => 0x10c,
        :i32x4_relaxed_dot_i8x16_i7x16_add_s => 0x113,)
        simd(op, code; sig=fixedsig((V128, V128, V128), (V128,)), relaxed=true)
    end
end
