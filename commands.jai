DrawCommandLists :: struct
{
    first : *DrawCommandList;
    #as last : *DrawCommandList;
}

DrawCommandList :: struct
{
    next : *DrawCommandList;

    current_texture : TextureHandle;
    current_shader : ShaderHandle;

    command_count : s32;
    last_command_offset : s32;
    command_offset : s32;

    vertex_count : s32;

    command_buffer : [Command_Buffer_Size]u8 = ---;
    vertices : [Max_Vertices_Per_Draw_List]Vertex = ---;
}

DrawCommand :: struct
{
    Kind :: enum u8
    {
        Invalid;
        Set_Shader;
        Set_Shader_Params;
        Set_Texture;
        Draw_Vertices;
    }

    kind : Kind;
}

SetShaderCommand :: struct
{
    #as using base : DrawCommand;
    base.kind = .Set_Shader;

    shader : ShaderHandle;
}

#assert Max_Shader_Params_Per_Command < 128;

SetShaderParamsCommand :: struct
{
    #as using base : DrawCommand;
    base.kind = .Set_Shader_Params;

    param_count : s8;
    params : [Max_Shader_Params_Per_Command]ShaderParam;
}

SetTextureCommand :: struct
{
    #as using base : DrawCommand;
    base.kind = .Set_Texture;

    texture : TextureHandle;
}

DrawVerticesCommand :: struct
{
    #as using base : DrawCommand;
    base.kind = .Draw_Vertices;

    offset : s32;
    count : s32;
}

#scope_module

g_draw_lists : DrawCommandLists;

#scope_export

GetGlobalCommandLists :: inline () -> *DrawCommandLists #must
{
    return *g_draw_lists;
}

CanPushCommand :: inline (list : *DrawCommandList, size : int) -> bool #must
{
    return list != null && list.command_offset + size <= Command_Buffer_Size;
}

GetLastCommand :: inline (list : *DrawCommandList) -> *DrawCommand #must
{
    if !list || list.command_count == 0
        return null;

    result := cast (*DrawCommand) (list.command_buffer.data + list.last_command_offset);

    return result;
}

PushCommandList :: inline (lists : *DrawCommandLists)
{
    result := New (DrawCommandList);

    first := lists.first == null;
    if first
        lists.first = result;

    if lists.last
    {
        result.current_texture = lists.last.current_texture;
        result.current_shader = lists.last.current_shader;

        assert (lists.last.next == null);
        lists.last.next = result;
    }

    lists.last = result;

    if first
        SetShader (GetDefaultShader (), lists);
}

PushCommand :: (list : *DrawCommandList, $T : Type) -> *T #must
#modify { #import "Compiler"; return is_subclass_of (cast (*Type_Info) T, "DrawCommand"); }
{
    assert (list != null, "List is null");
    assert (list.command_offset + size_of (T) <= Command_Buffer_Size);

    // @Incomplete: what about alignment?
    result := cast (*T) (list.command_buffer.data + list.command_offset);
    Initialize (result);

    list.last_command_offset = list.command_offset;
    list.command_offset += size_of (T);
    list.command_count += 1;

    return result;
}

for_expansion :: (list : *DrawCommandList, body : Code, flags : For_Flags) #expand
{
    `it_index := 0;
    `it := list;
    while it
    {
        next := it.next;
        defer {
            it = next;
            it_index += 1;
        }

        #insert body;
    }
}

AllCommands :: (list : *DrawCommandList, body : Code, flags : For_Flags) #expand
{
    current_offset := 0;
    `it_index := 0;
    while current_offset < list.command_offset && it_index < list.command_count
    {
        defer it_index += 1;

        `it := cast (*DrawCommand) (list.command_buffer.data + current_offset);
        if #complete it.kind ==
        {
        case; #through;
        case .Invalid;
            log_error ("Invalid command in command list");
            break;
        case .Set_Shader;
            current_offset += size_of (SetShaderCommand);
        case .Set_Shader_Params;
            current_offset += size_of (SetShaderParamsCommand);
        case .Set_Texture;
            current_offset += size_of (SetTextureCommand);
        case .Draw_Vertices;
            current_offset += size_of (DrawVerticesCommand);
        }

        #insert body;
    }
}

GetTexture :: inline (lists : *DrawCommandLists = null) -> TextureHandle #must
{
    if !lists
        lists = *g_draw_lists;

    if !lists.last
        return 0;

    return lists.last.current_texture;
}

SetTexture :: (texture : TextureHandle, lists : *DrawCommandLists = null)
{
    if !lists
        lists = *g_draw_lists;

    if GetTexture (lists) == texture
        return;

    if !CanPushCommand (lists.last, size_of (SetTextureCommand))
    {
        PushCommandList (lists);
    }

    cmd := PushCommand (lists.last, SetTextureCommand);
    cmd.texture = texture;
    lists.last.current_texture = texture;
}

GetShader :: inline (lists : *DrawCommandLists = null) -> ShaderHandle #must
{
    if !lists
        lists = *g_draw_lists;

    if !lists.last
        return 0;

    return lists.last.current_shader;
}

SetShader :: (shader : ShaderHandle, lists : *DrawCommandLists = null)
{
    if !lists
        lists = *g_draw_lists;

    if GetShader (lists) == shader
        return;

    if !CanPushCommand (lists.last, size_of (SetShaderCommand))
    {
        PushCommandList (lists);
    }

    cmd := PushCommand (lists.last, SetShaderCommand);
    cmd.shader = shader;
    lists.last.current_shader = shader;
}

SetShaderParams :: (params : ..ShaderParam, lists : *DrawCommandLists = null)
{
    if !lists
        lists = *g_draw_lists;

    if params.count == 0
        return;

    i : s32 = 0;

    cmd := cast (*SetShaderParamsCommand) GetLastCommand (lists.last);
    if cmd && cmd.kind == .Set_Shader_Params && cmd.param_count < Max_Shader_Params_Per_Command
    {
        to_copy := cast (s8) min (params.count, Max_Shader_Params_Per_Command - cmd.param_count);
        memcpy (cmd.params.data, params.data, to_copy);
        i += to_copy;
    }

    while i < params.count
    {
        if !CanPushCommand (lists.last, size_of (SetShaderParamsCommand))
        {
            PushCommandList (lists);
        }

        cmd := PushCommand (lists.last, SetShaderParamsCommand);

        to_copy := cast (s8) min (params.count - i, Max_Shader_Params_Per_Command);
        memcpy (cmd.params.data, params.data + i, to_copy);

        i += to_copy;
        cmd.param_count += to_copy;
    }
}

CanPushVertices :: inline (list : *DrawCommandList, count : s32) -> bool #must
{
    return list != null && list.vertex_count + count <= Max_Vertices_Per_Draw_List;
}

PushVertices :: (count : s32, lists : *DrawCommandLists = null) -> *Vertex #must
{
    if !lists
        lists = *g_draw_lists;

    if !CanPushVertices (lists.last, count)
    {
        PushCommandList (lists);
    }

    cmd := cast (*DrawVerticesCommand) GetLastCommand (lists.last);
    if cmd && cmd.kind == .Draw_Vertices
    {
        cmd.count += count;

        result := lists.last.vertices.data + lists.last.vertex_count;

        lists.last.vertex_count += count;

        return result;
    }

    cmd = PushCommand (lists.last, DrawVerticesCommand);
    cmd.offset = lists.last.vertex_count;
    cmd.count = count;

    result := lists.last.vertices.data + lists.last.vertex_count;

    lists.last.vertex_count += count;

    return result;
}
