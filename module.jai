#module_parameters (
    Origin_Top_Left := false,
    Math_Types : $T/interface MathTypes = MathTypes,
    Max_Vertices_Per_Draw_List := 10000,
    Command_Buffer_Size := 1500,
    Max_Shader_Params_Per_Command := 5,
    Default_Glyph_Atlas_Width  := 1024,
    Default_Glyph_Atlas_Height := 1024
)
(
    Profile_Glyph_Blitting := false
)
{
    MathTypes :: struct
    {
        Vec2f :: void;
        Vec3f :: void;
        Vec4f :: void;
        Mat3f :: void;
        Mat4f :: void;

        Matrices_Are_Row_Major :: true;
    }
};

// @Todo: use indices to reduce memory usage

#import "Basic";
Math :: #import "Math";

#load "commands.jai";
#load "math.jai";
#load "shader.jai";
#load "font.jai";
#load "gl.jai";

#if Math_Types == MathTypes
{
    Vec2f :: Math.Vector2;
    Vec3f :: Math.Vector3;
    Vec4f :: Math.Vector4;
    Mat3f :: Math.Matrix3;
    Mat4f :: Math.Matrix4;
}
else
{
    Vec2f :: Math_Types.Vec2f;
    Vec3f :: Math_Types.Vec3f;
    Vec4f :: Math_Types.Vec4f;
    Mat3f :: Math_Types.Mat3f;
    Mat4f :: Math_Types.Mat4f;
}

OffsetOf :: ($T : Type, $member : string) -> s64 #must #expand
{
    dummy := cast (*T) null;

    #insert #run sprint ("return cast (s64) *dummy.%;", member);
}

Vertex :: struct
{
    position : Vec2f;
    tex_coords : Vec2f;
    color : Vec4f;
}

TextureHandle :: u32;

LoadTexture :: (filename : string) -> TextureHandle #must
{
    #import "stb_image";

    w, h : s32;
    data := stbi_load (temp_c_string (filename), *w, *h, null, 4);
    if !data
        return 0;

    defer stbi_image_free (data);

    return CreateTexture (xx w, xx h, data);
}

PushTriangle :: (
    list : *DrawCommandList,
    p0 : Vec2f,
    p1 : Vec2f,
    p2 : Vec2f,
    color : Vec4f,
    uv0 : Vec2f,
    uv1 : Vec2f,
    uv2 : Vec2f
)
{
    v := PushVertices (list, 3);

    v.position = p0;
    v.tex_coords = uv0;
    v.color = color;

    v += 1;

    v.position = p1;
    v.tex_coords = uv1;
    v.color = color;

    v += 1;

    v.position = p2;
    v.tex_coords = uv2;
    v.color = color;
}

PushRect :: inline (
    list : *DrawCommandList,
    rect : Rect,
    color := Vec4f.{1,1,1,1},
    uv_rect := Rect.{0, 0, 1, 1}
)
{
    PushRect (
        list,
        .{rect.x, rect.y}, .{rect.x + rect.w, rect.y + rect.h},
        color,
        .{uv_rect.x, uv_rect.y}, .{uv_rect.x + uv_rect.w, uv_rect.y + uv_rect.h}
    );
}

PushRect :: (
    list : *DrawCommandList,
    min : Vec2f,
    max : Vec2f,
    color := Vec4f.{1,1,1,1},
    uv_min := Vec2f.{0,0},
    uv_max := Vec2f.{1,1}
)
{
    v := PushVertices (list, 6);

    v.position = min;
    v.tex_coords = uv_min;
    v.color = color;

    v += 1;

    v.position = .{max.x, min.y};
    v.tex_coords = .{uv_max.x, uv_min.y};
    v.color = color;

    v += 1;

    v.position = max;
    v.tex_coords = uv_max;
    v.color = color;

    v += 1;

    v.position = min;
    v.tex_coords = uv_min;
    v.color = color;

    v += 1;

    v.position = .{min.x, max.y};
    v.tex_coords = .{uv_min.x, uv_max.y};
    v.color = color;

    v += 1;

    v.position = max;
    v.tex_coords = uv_max;
    v.color = color;
}

RectCornerFlags :: enum_flags u8
{
    Top_Left;
    Top_Right;
    Bottom_Left;
    Bottom_Right;

    All :: Top_Left | Top_Right | Bottom_Left | Bottom_Right;
}

PushRoundedRect :: inline (
    list : *DrawCommandList,
    rect : Rect,
    radius : float,
    color := Vec4f.{1,1,1,1},
    corners := RectCornerFlags.All,
    uv_rect := Rect.{0,0,1,1}
)
{
    min, max := RectMinMax (rect);
    uv_min, uv_max := RectMinMax (uv_rect);
    PushRoundedRect (list, min, max, radius, color, corners, uv_min, uv_max);
}

PushRoundedRect :: (
    list : *DrawCommandList,
    min : Vec2f,
    max : Vec2f,
    radius : float,
    color := Vec4f.{1,1,1,1},
    corners := RectCornerFlags.All,
    uv_min := Vec2f.{0,0},
    uv_max := Vec2f.{1,1}
)
{
    if !corners || radius <= 0
    {
        PushRect (list, min, max, color, uv_min, uv_max);
        return;
    }

    radius = Min (radius, (max.x - min.x) * 0.5, (max.y - min.y) * 0.5);

    x1 := min.x;
    y1 := min.y;
    x2 := max.x;
    y2 := max.y;
    xx1 := x1 + radius;
    yy1 := y1 + radius;
    xx2 := x2 - radius;
    yy2 := y2 - radius;

    // @Incomplete: if !Origin_Top_Left, top and bottom are reversed

    // Top
    PushRect (list, .{xx1, y1}, .{xx2, yy1}, color);
    // Right
    PushRect (list, .{xx2, yy1}, .{x2, yy2}, color);
    // Bottom
    PushRect (list, .{xx1, yy2}, .{xx2, y2}, color);
    // Left
    PushRect (list, .{x1, yy1}, .{xx1, yy2}, color);
    // Center
    PushRect (list, .{xx1, yy1}, .{xx2, yy2}, color);

    Pi :: Math.PI;
    Theta :: Pi * 0.5;

    // Bottom right
    if corners & .Bottom_Right
        PushSemiCircle (list, .{xx2, yy2}, radius, Pi * 0.5, Theta, color);
    else
        PushRect (list, .{xx2, yy2}, .{x2, y2}, color);

    // Bottom left
    if corners & .Bottom_Left
        PushSemiCircle (list, .{xx1, yy2}, radius, Pi, Theta, color);
    else
        PushRect (list, .{x1, yy2}, .{xx1, y2}, color);

    // Top left
    if corners & .Top_Left
        PushSemiCircle (list, .{xx1, yy1}, radius, -Pi * 0.5, Theta, color);
    else
        PushRect (list, .{x1, y1}, .{xx1, yy1}, color);

    // Top right
    if corners & .Top_Right
        PushSemiCircle (list, .{xx2, yy1}, radius, 0, Theta, color);
    else
        PushRect (list, .{xx2, y1}, .{x2, yy2}, color);
}

// Goes counter-clockwise, starting from +X axis
PushSemiCircle :: (
    list : *DrawCommandList,
    center : Vec2f,
    radius : float,
    start_angle : float,
    angle : float,
    color := Vec4f.{1,1,1,1},
    resolution := 0,
    uv_center := Vec2f.{ 0.5, 0.5 },
    uv_radius :=  0.5
)
{
    if radius <= 0
        return;

    if resolution <= 0
        resolution = max (cast (int) radius, 20);

    theta := -angle / cast (float) resolution;
    tan_factor := Math.tan (theta);
    rad_factor := Math.cos (theta);
    p := Vec2f.{ Math.cos (start_angle), Math.sin (start_angle) };

    for 0..resolution - 1
    {
        p1 := p;

        t := Vec2f.{-p.y, p.x};

        p = p + t * tan_factor;
        p *= rad_factor;

        p2 := p;

        PushTriangle (
            list,
            center,
            center + p1 * radius,
            center + p2 * radius,
            color,
            uv0 = uv_center,
            uv1 = uv_center + p1 * uv_radius,
            uv2 = uv_center + p2 * uv_radius
        );
    }
}

PushCircle :: (
    list : *DrawCommandList,
    center : Vec2f,
    radius : float,
    color := Vec4f.{1,1,1,1},
    resolution := 0,
    uv_center := Vec2f.{0.5, 0.5},
    uv_radius := 0.5
)
{
    PushSemiCircle (list, center, radius, 0, 2 * Math.PI, color, resolution, uv_center, uv_radius);
}
