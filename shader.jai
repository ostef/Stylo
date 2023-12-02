
ShaderHandle :: u32;

ShaderParam :: struct
{
    DataType :: enum u8
    {
        Int; Int2; Int3; Int4;
        Float; Float2; Float3; Float4;
        Mat3; Mat4;
    }

    location : s32;
    union
    {
        int_values : [4]s32;
        struct
        {
            xi, yi, zi, wi : s32;
        };
        float_values : [4]float;
        struct
        {
            x, y, z, w : float;
        };
        mat3 : Mat3f;
        mat4 : Mat4f;
    };
    data_type : DataType;
}

operator == :: (a : ShaderParam, b : ShaderParam) -> bool #must
{
    if a.data_type != b.data_type
        return false;

    if a.location != b.location
        return false;

    if #complete a.data_type ==
    {
    case .Float; #through;
    case .Int; return a.xi == b.xi;

    case .Float2; #through;
    case .Int2; return a.xi == b.xi && a.yi == b.yi;

    case .Float3; #through;
    case .Int3; return a.xi == b.xi && a.yi == b.yi && a.zi == b.zi;

    case .Float4; #through;
    case .Int4; return a.xi == b.xi && a.yi == b.yi && a.zi == b.zi && a.wi == b.wi;

    case .Mat3; return a.mat3 == b.mat3;
    case .Mat4; return a.mat4 == b.mat4;
    }
}

ShaderParam1i :: inline (location : s32, val : s32) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.xi = val;
    result.data_type = .Int;

    return result;
}

ShaderParam2i :: inline (location : s32, x : s32, y : s32) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.xi = x;
    result.yi = y;
    result.data_type = .Int2;

    return result;
}

ShaderParam3i :: inline (location : s32, x : s32, y : s32, z : s32) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.xi = x;
    result.yi = y;
    result.zi = z;
    result.data_type = .Int3;

    return result;
}

ShaderParam4i :: inline (location : s32, x : s32, y : s32, z : s32, w : s32) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.xi = x;
    result.yi = y;
    result.zi = z;
    result.wi = w;
    result.data_type = .Int4;

    return result;
}

ShaderParam1f :: inline (location : s32, val : float) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = val;
    result.data_type = .Float;

    return result;
}

ShaderParam2f :: inline (location : s32, x : float, y : float) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = x;
    result.y = y;
    result.data_type = .Float2;

    return result;
}

ShaderParam3f :: inline (location : s32, x : float, y : float, z : float) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = x;
    result.y = y;
    result.z = z;
    result.data_type = .Float3;

    return result;
}

ShaderParam4f :: inline (location : s32, x : float, y : float, z : float, w : float) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = x;
    result.y = y;
    result.z = z;
    result.w = w;
    result.data_type = .Float4;

    return result;
}

ShaderParam2f :: inline (location : s32, vec : Vec2f) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = vec.x;
    result.y = vec.y;
    result.data_type = .Float2;

    return result;
}

ShaderParam3f :: inline (location : s32, vec : Vec3f) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = vec.x;
    result.y = vec.y;
    result.z = vec.z;
    result.data_type = .Float3;

    return result;
}

ShaderParam4f :: inline (location : s32, vec : Vec4f) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.x = vec.x;
    result.y = vec.y;
    result.z = vec.z;
    result.w = vec.w;
    result.data_type = .Float4;

    return result;
}

ShaderParamMat3 :: inline (location : s32, mat : Mat3f) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.mat3 = mat;
    result.data_type = .Mat3;

    return result;
}

ShaderParamMat4 :: inline (location : s32, mat : Mat4f) -> ShaderParam #must
{
    result : ShaderParam = ---;
    result.location = location;
    result.mat4 = mat;
    result.data_type = .Mat4;

    return result;
}
