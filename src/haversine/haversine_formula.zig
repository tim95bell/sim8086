const std = @import("std");

const sin = std.math.sin;
const cos = std.math.cos;
const asin = std.math.asin;
const sqrt = std.math.sqrt;

fn square(a: f64) f64 {
    return (a * a);
}

pub fn radiansFromDegrees(degrees: f64) f64 {
    return 0.01745329251994329577 * degrees;
}

pub const default_earth_radius: f64 = 6372.8;

pub fn referenceHaversine(x0: f64, y0: f64, x1: f64, y1: f64, earth_radius: f64) f64 {
    var lat1 = y0;
    var lat2 = y1;
    const lon1 = x0;
    const lon2 = x1;

    const dLat = radiansFromDegrees(lat2 - lat1);
    const dLon = radiansFromDegrees(lon2 - lon1);
    lat1 = radiansFromDegrees(lat1);
    lat2 = radiansFromDegrees(lat2);

    const a: f64 = square(sin(dLat / 2.0)) + cos(lat1) * cos(lat2) * square(sin(dLon / 2));
    const c: f64 = 2.0 * asin(sqrt(a));

    return earth_radius * c;
}
