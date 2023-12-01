Rect :: struct
{
    x, y, w, h : float;

    #place x;
    position, size : Vec2f;
}

MakeRectMinMax :: inline (min : Vec2f, max : Vec2f) -> Rect #must
{
    return .{min.x, min.y, max.x - min.x, max.y - min.y};
}

MakeRectMinMax :: inline (min_x : float, min_y : float, max_x : float, max_y : float) -> Rect #must
{
    return .{min_x, min_y, max_x - min_x, max_y - min_y};
}

RectMinMax :: inline (using rect : Rect) -> min : Vec2f, max : Vec2f
{
    return .{x, y}, .{x + w, y + h};
}

TruncateRect :: inline (rect : *Rect, left : float, top : float, right : float, bottom : float)
{
    rect.x += left;
    rect.w -= left;
    rect.w -= right;

    rect.y += top;
    rect.h -= top;
    rect.h -= bottom;
}

TruncateRect :: inline (rect : Rect, left : float, top : float, right : float, bottom : float) -> Rect #must
{
    result := rect;
    TruncateRect (*result, left, top, right, bottom);

    return result;
}

TruncateRect :: inline (rect : Rect, amount : float) -> Rect #must
{
    return TruncateRect (rect, amount, amount, amount, amount);
}

Round :: (value : float) -> float #must #expand
{
    if value < 0
        return cast (float) (cast (int) (value - 0.5));

    return cast (float) (cast (int) (value + 0.5));
}

SnapDown :: (value : float, grid_size : float) -> float #must #expand
{
    return Math.floor (value / grid_size) * grid_size;
}

Snap :: (value : float, grid_size : float) -> float #must #expand
{
    return Round (value / grid_size) * grid_size;
}

SnapUp :: (value : float, grid_size : float) -> float #must #expand
{
    return Math.ceil (value / grid_size) * grid_size;
}

MakeOrthograpicProjection :: inline (l : float, r : float, b : float, t : float, n : float, f : float) -> Mat4f #must
{
    return .{
        2 / (r - l),           0,           0, (r + l) / (l - r),
                  0, 2 / (t - b),           0, (t + b) / (b - t),
                  0,           0, 2 / (f - n), (n + f) / (n - f),
                  0,           0,           0,                 1
    };
}

operator + :: inline (a : Vec2f, b : Vec2f) -> Vec2f #must
{
    return .{a.x + b.x, a.y + b.y};
}

operator + :: inline (a : Vec3f, b : Vec3f) -> Vec3f #must
{
    return .{a.x + b.x, a.y + b.y, a.z + b.z};
}

operator + :: inline (a : Vec4f, b : Vec4f) -> Vec4f #must
{
    return .{a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w};
}

operator - :: inline (a : Vec2f, b : Vec2f) -> Vec2f #must
{
    return .{a.x - b.x, a.y - b.y};
}

operator - :: inline (a : Vec3f, b : Vec3f) -> Vec3f #must
{
    return .{a.x - b.x, a.y - b.y, a.z - b.z};
}

operator - :: inline (a : Vec4f, b : Vec4f) -> Vec4f #must
{
    return .{a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w};
}

operator * :: inline (a : Vec2f, b : float) -> Vec2f #must #symmetric
{
    return .{a.x * b, a.y * b};
}

operator * :: inline (a : Vec3f, b : float) -> Vec3f #must #symmetric
{
    return .{a.x * b, a.y * b, a.z * b};
}

operator * :: inline (a : Vec4f, b : float) -> Vec4f #must #symmetric
{
    return .{a.x * b, a.y * b, a.z * b, a.w * b};
}

operator / :: inline (a : Vec2f, b : float) -> Vec2f #must
{
    return .{a.x / b, a.y / b};
}

operator / :: inline (a : Vec3f, b : float) -> Vec3f #must
{
    return .{a.x / b, a.y / b, a.z / b};
}

operator / :: inline (a : Vec4f, b : float) -> Vec4f #must
{
    return .{a.x / b, a.y / b, a.z / b, a.w / b};
}

operator == :: inline (a : Vec2f, b : Vec2f) -> bool #must
{
    return memcmp (*a, *b, size_of (type_of (a))) == 0;
}

operator == :: inline (a : Vec3f, b : Vec3f) -> bool #must
{
    return memcmp (*a, *b, size_of (type_of (a))) == 0;
}

operator == :: inline (a : Vec4f, b : Vec4f) -> bool #must
{
    return memcmp (*a, *b, size_of (type_of (a))) == 0;
}

operator == :: inline (a : Mat3f, b : Mat3f) -> bool #must
{
    return memcmp (*a, *b, size_of (type_of (a))) == 0;
}

operator == :: inline (a : Mat4f, b : Mat4f) -> bool #must
{
    return memcmp (*a, *b, size_of (type_of (a))) == 0;
}
