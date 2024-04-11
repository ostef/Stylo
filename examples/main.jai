#import "Basic";
#import "Math";

Win32 :: #import "Win32" (
    GDI_Basics = true,
    WGL = true,
    Windows_And_Messaging = true,
);

#import "GL";

Stylo :: #import, file "../module.jai" () (
    Profile_Glyph_Blitting = true
);

g_quit := false;

main :: ()
{
    WndProc :: (
        hwnd : Win32.HWND,
        msg : u32,
        wparam : Win32.WPARAM,
        lparam : Win32.LPARAM
    ) -> Win32.LRESULT #c_call
    {
        if msg ==
        {
        case Win32.WM_CLOSE;
            g_quit = true;

        case Win32.WM_SETCURSOR;
            if Win32.LOWORD (lparam) == Win32.HTCLIENT
            {
                Win32.SetCursor (Win32.LoadCursorW (null, Win32.IDC_ARROW));

                return 0;
            }

            return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);
        }


        return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);
    }

    wndclass : Win32.WNDCLASSEXW;
    wndclass.cbSize = size_of (Win32.WNDCLASSEXW);
    wndclass.style = .CS_DBLCLKS | .CS_OWNDC;
    wndclass.lpfnWndProc = WndProc;
    wndclass.hInstance = Win32.GetModuleHandleW (null);
    wndclass.lpszClassName = Utf8ToWide ("WindowClass");
    Win32.RegisterClassExW (*wndclass);

    hwnd := Win32.CreateWindowExW (
        9,
        wndclass.lpszClassName,
        Utf8ToWide ("Window"),
        .WS_OVERLAPPEDWINDOW | .WS_VISIBLE,
        Win32.CW_USEDEFAULT,
        Win32.CW_USEDEFAULT,
        1280,
        720,
        null,
        null,
        Win32.GetModuleHandleW (null),
        null
    );

    defer Win32.DestroyWindow (hwnd);

    hdc := Win32.GetDC (hwnd);

    pfd : Win32.PIXELFORMATDESCRIPTOR;
    pfd.nSize = size_of (Win32.PIXELFORMATDESCRIPTOR);
    pfd.nVersion = 1;
    pfd.dwFlags = Win32.PFD_DRAW_TO_WINDOW | Win32.PFD_SUPPORT_OPENGL | Win32.PFD_DOUBLEBUFFER;
    pfd.iPixelType = Win32.PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;

    pixel_format := Win32.ChoosePixelFormat (hdc, *pfd);
    Win32.SetPixelFormat (hdc, pixel_format, *pfd);

    hglrc := Win32.wglCreateContext (hdc);
    defer Win32.wglDeleteContext (hglrc);

    Win32.wglMakeCurrent (hdc, hglrc);

    gl_load (*gl, Win32.wglGetProcAddress);

    assert (glGenVertexArrays != null, "Could not load GL functions");

    draw_list : Stylo.DrawCommandList;
    font := Stylo.LoadFontFromFile ("Roboto-Regular.ttf");
    assert (font != null);

    while !g_quit
    {
        msg : Win32.MSG;
        while Win32.PeekMessageW (*msg, null, 0, 0, .PM_REMOVE)
        {
            Win32.TranslateMessage (*msg);
            Win32.DispatchMessageW (*msg);
        }

        time := cast (float) to_float64_seconds (current_time_monotonic ());

        viewport_rect : Win32.RECT;
        Win32.GetClientRect (hwnd, *viewport_rect);

        width := viewport_rect.right - viewport_rect.left;
        height := viewport_rect.bottom - viewport_rect.top;

        glViewport (0, 0, xx width, xx height);
        glClearColor (0.2, 0.4, 0.8, 1.0);
        glClear (GL_COLOR_BUFFER_BIT);

        Stylo.PushCircle (
            *draw_list,
            .{width * 0.5, height * 0.5},
            100,
            color = .{0.7,0.4,0.2,1.0}
        );

        Stylo.PushRoundedRect (
            *draw_list,
            .{300,300,100,100},
            25,
            color = .{0.6,0.2,0.7,1.0}
        );

        rect : Stylo.Rect;
        rect.x = 10;
        rect.w = 300 + cos (time * 0.5) * 50;
        rect.h = 300 + sin (time * 0.5) * 50;
        rect.y = height - 10.0 - rect.h;

        Stylo.PushRect (*draw_list, rect, color = .{0.0581, 0.791, 0.830, 1});

        Stylo.SetClipRect (*draw_list, rect);
        Stylo.PushText (*draw_list, font, Lorem_Ipsum, 22, rect, overflow = .Wrap_Word);

        Stylo.GLRenderCommandList (*draw_list, width, height);

        Win32.SwapBuffers (hdc);

        sleep_milliseconds (10);
    }

    {
        avg, min, max := Stylo.GetGlyphBlittingProfileResults ();
        print ("Glyph blitting profile results:\n  avg: % ms\n  min: % ms\n  max: % ms\n",
            to_float64_seconds (avg) * 1000,
            to_float64_seconds (min) * 1000,
            to_float64_seconds (max) * 1000
        );
    }
}

// The result is null terminated even though a Jai string is returned
WideToUtf8 :: (data : *u16) -> string #must, success : bool
{
    result_length := Win32.WideCharToMultiByte (Win32.CP_UTF8, 0, data, -1, null, 0, null, null);
    if result_length <= 0
        return "", false;

    utf8_data := cast (*u8) alloc (result_length);

    written := Win32.WideCharToMultiByte (Win32.CP_UTF8, 0, data, -1, utf8_data, result_length, null, null);
    if written > 0
    {
        str : string = ---;
        str.data  = utf8_data;
        str.count = written - 1;

        return str, true;
    }

    return "", false;
}

// The result is null terminated
Utf8ToWide :: (utf8_str : string) -> wide_str : *u16 #must, length : s32
{
    if !utf8_str
    {
        wide_str := cast (*u16) alloc (size_of (u16));
        wide_str[0] = 0;

        return wide_str, 0;
    }

    result_length := Win32.MultiByteToWideChar (Win32.CP_UTF8, 0, utf8_str.data, cast (s32) utf8_str.count, null, 0);
    if result_length <= 0
        return null, 0;

    wide_str := cast (*u16) alloc ((result_length + 1) * size_of (u16));
    written := Win32.MultiByteToWideChar (Win32.CP_UTF8, 0, utf8_str.data, cast (s32) utf8_str.count, wide_str, result_length);
    if written > 0
    {
        wide_str[written] = 0;

        return wide_str, written;
    }

    return null, 0;
}

Lorem_Ipsum :: #string END
LONGWORDLONGWORDLONGWORDLONGWORDLONGWORDLONGWORDLONGWORDLONGWORDLONGWORDLONGWORDLONGWORD
Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.
END
