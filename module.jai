#module_parameters (
    Origin_Top_Left := false,
    Math_Types : $T/interface MathTypes = MathTypes,
    Max_Vertices_Per_Draw_List := 10000,
    Command_Buffer_Size := 1500,
    Max_Shader_Params_Per_Command := 5,
    Default_Glyph_Atlas_Width  := 1024,
    Default_Glyph_Atlas_Height := 1024
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
    p0 : Vec2f,
    p1 : Vec2f,
    p2 : Vec2f,
    color : Vec4f,
    uv0 : Vec2f,
    uv1 : Vec2f,
    uv2 : Vec2f,
    list : *DrawCommandList = null
)
{
    v := PushVertices (3, list);

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
    rect : Rect,
    color := Vec4f.{1,1,1,1},
    uv_rect := Rect.{0, 0, 1, 1},
    list : *DrawCommandList = null
)
{
    PushRect (
        .{rect.x, rect.y}, .{rect.x + rect.w, rect.y + rect.h},
        color,
        .{uv_rect.x, uv_rect.y}, .{uv_rect.x + uv_rect.w, uv_rect.y + uv_rect.h},
        list
    );
}

PushRect :: (
    min : Vec2f,
    max : Vec2f,
    color := Vec4f.{1,1,1,1},
    uv_min := Vec2f.{0,0},
    uv_max := Vec2f.{1,1},
    list : *DrawCommandList = null
)
{
    v := PushVertices (6, list);

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
    rect : Rect,
    radius : float,
    color := Vec4f.{1,1,1,1},
    corners := RectCornerFlags.All,
    uv_rect := Rect.{0,0,1,1},
    list : *DrawCommandList = null
)
{
    min, max := RectMinMax (rect);
    uv_min, uv_max := RectMinMax (uv_rect);
    PushRoundedRect (min, max, radius, color, corners, uv_min, uv_max, list);
}

PushRoundedRect :: (
    min : Vec2f,
    max : Vec2f,
    radius : float,
    color := Vec4f.{1,1,1,1},
    corners := RectCornerFlags.All,
    uv_min := Vec2f.{0,0},
    uv_max := Vec2f.{1,1},
    list : *DrawCommandList = null
)
{
    FourthCircle :: (
        center : Vec2f,
        radius : float,
        resolution : int,
        color : Vec4f,
        index : int,
        min : Vec2f,
        max : Vec2f,
        uv_min : Vec2f,
        uv_max : Vec2f,
        list : *DrawCommandList
    )
    {
        if resolution <= 0
            resolution = Max (cast (int) radius, 20);

        center_uv := Vec2f.{
            uv_min.x + ((center.x - min.x) / (max.x - min.x)) * (uv_max.x - uv_min.x),
            uv_min.y + ((center.y - min.y) / (max.y - min.y)) * (uv_max.y - uv_min.y)
        };

        for i : resolution * index..resolution * (index + 1) - 1
        {
            p := i / cast (float) (resolution * 4);
            first := center + radius * Vec2f.{Math.cos (p * Math.PI * 2), Math.sin (p * Math.PI * 2)};
            first_uv := Vec2f.{
                uv_min.x + ((first.x - min.x) / (max.x - min.x)) * (uv_max.x - uv_min.x),
                uv_min.y + ((first.y - min.y) / (max.y - min.y)) * (uv_max.y - uv_min.y)
            };

            p = (i + 1) / cast (float) (resolution * 4);
            second := center + radius * Vec2f.{Math.cos (p * Math.PI * 2), Math.sin (p * Math.PI * 2)};
            second_uv := Vec2f.{
                uv_min.x + ((second.x - min.x) / (max.x - min.x)) * (uv_max.x - uv_min.x),
                uv_min.y + ((second.y - min.y) / (max.y - min.y)) * (uv_max.y - uv_min.y)
            };

            v := PushVertices (3, list);
            v.position = center;
            v.tex_coords = center_uv;
            v.color = color;

            v += 1;

            v.position = first;
            v.tex_coords = first_uv;
            v.color = color;

            v += 1;

            v.position = second;
            v.tex_coords = second_uv;
            v.color = color;
        }
    }

    if !corners || radius <= 0
    {
        PushRect (min, max, color, uv_min, uv_max, list);
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
    PushRect (.{xx1, y1}, .{xx2, yy1}, color, list = list);
    // Right
    PushRect (.{xx2, yy1}, .{x2, yy2}, color, list = list);
    // Bottom
    PushRect (.{xx1, yy2}, .{xx2, y2}, color, list = list);
    // Left
    PushRect (.{x1, yy1}, .{xx1, yy2}, color, list = list);
    // Center
    PushRect (.{xx1, yy1}, .{xx2, yy2}, color, list = list);

    // Bottom right
    if corners & .Bottom_Right
        FourthCircle (.{xx2, yy2}, radius, 0, color, 0, min, max, uv_min, uv_max, list);
    else
        PushRect (.{xx2, yy2}, .{x2, y2}, color, list = list);

    // Bottom left
    if corners & .Bottom_Left
        FourthCircle (.{xx1, yy2}, radius, 0, color, 1, min, max, uv_min, uv_max, list);
    else
        PushRect (.{x1, yy2}, .{xx1, y2}, color, list = list);

    // Top left
    if corners & .Top_Left
        FourthCircle (.{xx1, yy1}, radius, 0, color, 2, min, max, uv_min, uv_max, list);
    else
        PushRect (.{x1, y1}, .{xx1, yy1}, color, list = list);

    // Top right
    if corners & .Top_Right
        FourthCircle (.{xx2, yy1}, radius, 0, color, 3, min, max, uv_min, uv_max, list);
    else
        PushRect (.{xx2, y1}, .{x2, yy2}, color, list = list);
}

// Goes clockwise, starting from +X axis
PushSemiCircle :: (
    center : Vec2f,
    radius : float,
    start_angle : float,
    angle : float,
    color := Vec4f.{1,1,1,1},
    resolution := 0,
    uv_center := Vec2f.{ 0.5, 0.5 },
    uv_radius :=  0.5,
    list : *DrawCommandList = null
)
{
    if radius <= 0
        return;

    if resolution <= 0
        resolution = max (cast (int) radius, 20);

    theta := -angle / cast (float) resolution;
    tan_factor := Math.tan (theta);
    rad_factor := Math.cos (theta);
    p := Vec2f.{ Math.cos (-start_angle), Math.sin (-start_angle) };

    for 0..resolution - 1
    {
        p1 := p;

        t := Vec2f.{-p.y, p.x};

        p = p + t * tan_factor;
        p *= rad_factor;

        p2 := p;

        PushTriangle (
            center,
            center + p1 * radius,
            center + p2 * radius,
            color,
            uv0 = uv_center,
            uv1 = uv_center + p1 * uv_radius,
            uv2 = uv_center + p2 * uv_radius,
            list = list
        );
    }
}

PushCircle :: (
    center : Vec2f,
    radius : float,
    color := Vec4f.{1,1,1,1},
    resolution := 0,
    uv_center := Vec2f.{0.5, 0.5},
    uv_radius := 0.5,
    list : *DrawCommandList = null
)
{
    PushSemiCircle (center, radius, 0, 2 * Math.PI, color, resolution, uv_center, uv_radius, list);
}
