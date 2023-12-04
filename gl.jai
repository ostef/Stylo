#scope_file

g_gl_initialized : bool;
g_vao, g_vbo : u32;
g_shader : u32;

#scope_export

GetDefaultShader :: inline () -> ShaderHandle #must
{
    return cast (ShaderHandle) g_shader;
}

GL_Vertex_Shader :: #string GLSL
#version 330 core

layout (location = 0) in vec2 a_Position;
layout (location = 1) in vec2 a_Tex_Coords;
layout (location = 2) in vec4 a_Color;

out vec2 Tex_Coords;
out vec4 Color;

uniform mat4 u_View_Projection_Matrix;

void main ()
{
    gl_Position = u_View_Projection_Matrix * vec4 (a_Position, 0, 1);
    Tex_Coords = a_Tex_Coords;
    Color = a_Color;
}
GLSL

GL_Fragment_Shader :: #string GLSL
#version 330 core

in vec2 Tex_Coords;
in vec4 Color;

out vec4 Frag_Color;

uniform sampler2D u_Texture;
uniform bool u_Use_Texture;

void main ()
{
    if (u_Use_Texture)
        Frag_Color = texture (u_Texture, Tex_Coords) * Color;
    else
        Frag_Color = Color;
}
GLSL

SetShaderParam :: inline (param : ShaderParam)
{
    #import "GL";

    if #complete param.data_type ==
    {
    case .Int; glUniform1i (param.location, param.xi);
    case .Int2; glUniform2i (param.location, param.xi, param.yi);
    case .Int3; glUniform3i (param.location, param.xi, param.yi, param.zi);
    case .Int4; glUniform4i (param.location, param.xi, param.yi, param.zi, param.wi);
    case .Float; glUniform1f (param.location, param.x);
    case .Float2; glUniform2f (param.location, param.x, param.y);
    case .Float3; glUniform3f (param.location, param.x, param.y, param.z);
    case .Float4; glUniform4f (param.location, param.x, param.y, param.z, param.w);
    case .Mat3; glUniformMatrix3fv (param.location, 1, Math_Types.Matrices_Are_Row_Major, cast (*float) *param.mat3);
    case .Mat4; glUniformMatrix4fv (param.location, 1, Math_Types.Matrices_Are_Row_Major, cast (*float) *param.mat4);
    }
}

GLRenderCommandLists :: (lists : *DrawCommandLists, width : s32, height : s32)
{
    #import "GL";
    GL_Utils :: #import,file "GL_Utils.jai";

    GL_Utils.StateBlock (GL_VERTEX_ARRAY_BINDING, (prev : GLuint) {glBindVertexArray (prev);});
    GL_Utils.StateBlock (GL_ARRAY_BUFFER_BINDING, (prev : GLuint) {glBindBuffer (GL_ARRAY_BUFFER, prev);});

    if !g_gl_initialized
    {
        glGenVertexArrays (1, *g_vao);
        glGenBuffers (1, *g_vbo);
        assert (g_vao != 0, "Stylo: glGenVertexArrays failed");
        assert (g_vbo != 0, "Stylo: glGenBuffers failed");

        glBindVertexArray (g_vao);
        glBindBuffer (GL_ARRAY_BUFFER, g_vbo);

        glEnableVertexAttribArray (0);
        glVertexAttribPointer (0, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "position"));

        glEnableVertexAttribArray (1);
        glVertexAttribPointer (1, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "tex_coords"));

        glEnableVertexAttribArray (2);
        glVertexAttribPointer (2, 4, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) OffsetOf (Vertex, "color"));

        glBufferData (GL_ARRAY_BUFFER, size_of (Vertex) * Max_Vertices_Per_Draw_List, null, GL_DYNAMIC_DRAW);

        g_shader = GL_Utils.CreateShaderProgram (GL_Vertex_Shader, GL_Fragment_Shader);
        assert (g_shader != 0, "Could not create shader program");

        g_gl_initialized = true;
    }
    else
    {
        glBindVertexArray (g_vao);
        glBindBuffer (GL_ARRAY_BUFFER, g_vbo);
    }

    GL_Utils.EnableBlock (GL_BLEND);
    GL_Utils.BlendFuncStateBlock ();
    GL_Utils.DisableBlock (GL_DEPTH_TEST);
    GL_Utils.DisableBlock (GL_CULL_FACE);
    GL_Utils.DisableBlock (GL_SCISSOR_TEST);
    GL_Utils.StateBlock (GL_ACTIVE_TEXTURE, (prev : GLenum) {glActiveTexture (prev);});
    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});
    GL_Utils.StateBlock (GL_CURRENT_PROGRAM, (prev : GLuint) {glUseProgram (prev);});
    GL_Utils.StateBlock (GL_SCISSOR_BOX, 4, (v : [4]GLint) {glScissor (v[0], v[1], xx v[2], xx v[3]);});

    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glActiveTexture (GL_TEXTURE0);

    loc_use_texture : GLint;

    #if Origin_Top_Left
        view_projection_matrix := MakeOrthograpicProjection (0, xx width, xx height, 0, 0, 1);
    else
        view_projection_matrix := MakeOrthograpicProjection (0, xx width, 0, xx height, 0, 1);

    for lists.first
    {
        glBufferSubData (GL_ARRAY_BUFFER, 0, size_of (Vertex) * it.vertex_count, it.vertices.data);

        for :AllCommands draw_cmd, cmd_i : it
        {
            if #complete draw_cmd.kind ==
            {
            case .Invalid;
            case .Set_Shader;
                cmd := cast (*SetShaderCommand) draw_cmd;

                glUseProgram (cmd.shader);

                loc_view_proj := glGetUniformLocation (cmd.shader, "u_View_Projection_Matrix");
                loc_viewport_size := glGetUniformLocation (cmd.shader, "u_Viewport_Size");
                loc_texture := glGetUniformLocation (cmd.shader, "u_Texture");
                loc_use_texture = glGetUniformLocation (cmd.shader, "u_Use_Texture");

                glUniformMatrix4fv (loc_view_proj, 1, Math_Types.Matrices_Are_Row_Major, cast (*float) *view_projection_matrix);
                glUniform2f (loc_viewport_size, cast (float) width, cast (float) height);
                glUniform1i (loc_texture, 0);

            case .Set_Shader_Params;
                cmd := cast (*SetShaderParamsCommand) draw_cmd;

                for i : 0..cmd.param_count - 1
                {
                    SetShaderParam (cmd.params[i]);
                }

            case .Set_Texture;
                cmd := cast (*SetTextureCommand) draw_cmd;

                glUniform1i (loc_use_texture, cast (s32) (cmd.texture != 0));
                glBindTexture (GL_TEXTURE_2D, cmd.texture);

            case .Set_Clipping;
                cmd := cast (*SetClippingCommand) draw_cmd;

                if cmd.enabled
                {
                    glEnable (GL_SCISSOR_TEST);
                    glScissor (cmd.rect.x, cmd.rect.y, xx cmd.rect.w, xx cmd.rect.h);
                }
                else
                {
                    glDisable (GL_SCISSOR_TEST);
                }

            case .Draw_Vertices;
                cmd := cast (*DrawVerticesCommand) draw_cmd;
                glDrawArrays (GL_TRIANGLES, cmd.offset, cast (u32) cmd.count);
            }
        }

        free (it);
    }

    lists.first = null;
    lists.last = null;
}

CreateTexture :: (width : u32, height : u32, data : *void) -> TextureHandle #must
{
    #import "GL";
    GL_Utils :: #import, file "GL_Utils.jai";

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    result : GLuint;
    glGenTextures (1, *result);
    glBindTexture (GL_TEXTURE_2D, result);

    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);

    return cast (TextureHandle) result;
}

DestroyTexture :: inline (texture : *TextureHandle)
{
    glDeleteTextures (1, texture);
}

BlitToTexture :: (texture : TextureHandle, x : s32, y : s32, width : u32, height : u32, data : *void)
{
    #import "GL";
    GL_Utils :: #import, file "GL_Utils.jai";

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    glBindTexture (GL_TEXTURE_2D, texture);
    glTexSubImage2D (GL_TEXTURE_2D, 0, x, y, xx width, xx height, GL_RGBA, GL_UNSIGNED_BYTE, data);
}

#scope_module

UseTexture :: inline (texture : TextureHandle)
{
    #import "GL";
    GL_Utils :: #import, file "GL_Utils.jai";

    glBindTexture (GL_TEXTURE_2D, texture);
}

#scope_export
