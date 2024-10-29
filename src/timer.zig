const mach_time = @cImport({
    @cInclude("mach/mach_time.h");
});

pub const ns_in_s = 1_000_000_000;

pub fn percentage(a: u64, b: u64) f64 {
    return (@as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b))) * 100;
}

pub fn toNsRatio() f64 {
    var info: mach_time.mach_timebase_info_data_t = undefined;
    _ = mach_time.mach_timebase_info(&info);
    return @as(f64, @floatFromInt(info.numer)) / @as(f64, @floatFromInt(info.denom));
}

pub fn toSRatio() f64 {
    return toNsRatio() / ns_in_s;
}

pub fn time() u64 {
    return mach_time.mach_absolute_time();
}

pub fn toNs(x: u64) f64 {
    return @as(f64, @floatFromInt(x)) * toNsRatio();
}

pub fn nsToS(x: f64) f64 {
    return x / ns_in_s;
}

pub fn toS(x: u64) f64 {
    return @as(f64, @floatFromInt(x)) * toSRatio();
}

pub fn estimateCpuFrequency() usize {
    const start = time();
    var diff: u64 = 0;
    while (toNs(diff) < ns_in_s) {
        diff = time() - start;
    }
    return diff;
}
