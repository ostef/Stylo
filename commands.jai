DrawCommandList :: struct
{
    first : *DrawCommandBuffer;
    #as last : *DrawCommandBuffer;
}

DrawCommandBuffer :: struct
{
    next : *DrawCommandBuffer;

    current_texture : TextureHandle;
    current_shader : ShaderHandle;
    current_clipping_state : bool;
    current_clip_rect : Recti;

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
        Set_Clipping;
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

SetClippingCommand :: struct
{
    #as using base : DrawCommand;
    base.kind = .Set_Clipping;

    enabled : bool;
    rect : Recti;
}

DrawVerticesCommand :: struct
{
    #as using base : DrawCommand;
    base.kind = .Draw_Vertices;

    offset : s32;
    count : s32;
}

CanPushCommand :: inline (buff : *DrawCommandBuffer, size : int) -> bool #must
{
    return buff != null && buff.command_offset + size <= Command_Buffer_Size;
}

GetLastCommand :: inline (buff : *DrawCommandBuffer) -> *DrawCommand #must
{
    if !buff || buff.command_count == 0
        return null;

    result := cast (*DrawCommand) (buff.command_buffer.data + buff.last_command_offset);

    return result;
}

PushCommandList :: inline (list : *DrawCommandList)
{
    result := New (DrawCommandBuffer);

    first := list.first == null;
    if first
        list.first = result;

    if list.last
    {
        result.current_texture = list.last.current_texture;
        result.current_shader = list.last.current_shader;
        result.current_clipping_state = list.last.current_clipping_state;
        result.current_clip_rect = list.last.current_clip_rect;

        assert (list.last.next == null);
        list.last.next = result;
    }

    list.last = result;

    if first
        SetShader (list, GetDefaultShader ());
}

PushCommand :: (buff : *DrawCommandBuffer, $T : Type) -> *T #must
#modify { #import "Compiler"; return is_subclass_of (cast (*Type_Info) T, "DrawCommand"); }
{
    assert (buff != null, "List is null");
    assert (buff.command_offset + size_of (T) <= Command_Buffer_Size);

    // @Incomplete: what about alignment?
    result := cast (*T) (buff.command_buffer.data + buff.command_offset);
    Initialize (result);

    buff.last_command_offset = buff.command_offset;
    buff.command_offset += size_of (T);
    buff.command_count += 1;

    return result;
}

for_expansion :: (buff : *DrawCommandBuffer, body : Code, flags : For_Flags) #expand
{
    `it_index := 0;
    `it := buff;
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

AllCommands :: (buff : *DrawCommandBuffer, body : Code, flags : For_Flags) #expand
{
    current_offset := 0;
    `it_index := 0;
    while current_offset < buff.command_offset && it_index < buff.command_count
    {
        defer it_index += 1;

        `it := cast (*DrawCommand) (buff.command_buffer.data + current_offset);
        if #complete it.kind ==
        {
        case; #through;
        case .Invalid;
            log_error ("Invalid command in command buff");
            break;
        case .Set_Shader;
            current_offset += size_of (SetShaderCommand);
        case .Set_Shader_Params;
            current_offset += size_of (SetShaderParamsCommand);
        case .Set_Texture;
            current_offset += size_of (SetTextureCommand);
        case .Set_Clipping;
            current_offset += size_of (SetClippingCommand);
        case .Draw_Vertices;
            current_offset += size_of (DrawVerticesCommand);
        }

        #insert body;
    }
}

GetTexture :: inline (list : *DrawCommandList) -> TextureHandle #must
{
    if !list.last
        return 0;

    return list.last.current_texture;
}

SetTexture :: (list : *DrawCommandList, texture : TextureHandle)
{
    if GetTexture (list) == texture
        return;

    if !CanPushCommand (list.last, size_of (SetTextureCommand))
    {
        PushCommandList (list);
    }

    cmd := PushCommand (list.last, SetTextureCommand);
    cmd.texture = texture;
    list.last.current_texture = texture;
}

GetShader :: inline (list : *DrawCommandList) -> ShaderHandle #must
{
    if !list.last
        return 0;

    return list.last.current_shader;
}

SetShader :: (list : *DrawCommandList, shader : ShaderHandle)
{
    if GetShader (list) == shader
        return;

    if !CanPushCommand (list.last, size_of (SetShaderCommand))
    {
        PushCommandList (list);
    }

    cmd := PushCommand (list.last, SetShaderCommand);
    cmd.shader = shader;
    list.last.current_shader = shader;
}

SetShaderParams :: (list : *DrawCommandList, params : ..ShaderParam)
{
    if params.count == 0
        return;

    i : s32 = 0;

    cmd := cast (*SetShaderParamsCommand) GetLastCommand (list.last);
    if cmd && cmd.kind == .Set_Shader_Params && cmd.param_count < Max_Shader_Params_Per_Command
    {
        to_copy := cast (s8) min (params.count, Max_Shader_Params_Per_Command - cmd.param_count);
        memcpy (cmd.params.data, params.data, to_copy);
        i += to_copy;
    }

    while i < params.count
    {
        if !CanPushCommand (list.last, size_of (SetShaderParamsCommand))
        {
            PushCommandList (list);
        }

        cmd := PushCommand (list.last, SetShaderParamsCommand);

        to_copy := cast (s8) min (params.count - i, Max_Shader_Params_Per_Command);
        memcpy (cmd.params.data, params.data + i, to_copy);

        i += to_copy;
        cmd.param_count += to_copy;
    }
}

GetClipping :: (list : *DrawCommandList) -> bool #must, Recti #must
{
    if !list.last
        return false, .{};

    return list.last.current_clipping_state, list.last.current_clip_rect;
}

SetClipping :: (list : *DrawCommandList, enabled : bool, rect : Recti)
{
    if list.last
    {
        if !enabled && !list.last.current_clipping_state
            return;
        if enabled && list.last.current_clipping_state && rect == list.last.current_clip_rect
            return;
    }

    if !CanPushCommand (list.last, size_of (SetClippingCommand))
    {
        PushCommandList (list);
    }

    cmd := PushCommand (list.last, SetClippingCommand);
    cmd.enabled = enabled;
    cmd.rect = rect;

    list.last.current_clipping_state = enabled;
    list.last.current_clip_rect = rect;
}

DisableClipping :: inline (list : *DrawCommandList)
{
    SetClipping (list, false, .{});
}

SetClipRect :: inline (list : *DrawCommandList, rect : Rect)
{
    SetClipping (list, true, Recti.{xx rect.x, xx rect.y, xx rect.w, xx rect.h});
}

SetClipRect :: inline (list : *DrawCommandList, rect : Recti)
{
    SetClipping (list, true, rect);
}

CanPushVertices :: inline (buff : *DrawCommandBuffer, count : s32) -> bool #must
{
    return buff != null && buff.vertex_count + count <= Max_Vertices_Per_Draw_List;
}

PushVertices :: (list : *DrawCommandList, count : s32) -> *Vertex #must
{
    if !CanPushVertices (list.last, count) || !CanPushCommand (list.last, size_of (DrawVerticesCommand))
    {
        PushCommandList (list);
    }

    cmd := cast (*DrawVerticesCommand) GetLastCommand (list.last);
    if cmd && cmd.kind == .Draw_Vertices
    {
        cmd.count += count;

        result := list.last.vertices.data + list.last.vertex_count;

        list.last.vertex_count += count;

        return result;
    }

    cmd = PushCommand (list.last, DrawVerticesCommand);
    cmd.offset = list.last.vertex_count;
    cmd.count = count;

    result := list.last.vertices.data + list.last.vertex_count;

    list.last.vertex_count += count;

    return result;
}
