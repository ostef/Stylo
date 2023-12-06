#import "Hash_Table";
#import "freetype-2.12.1";
Unicode :: #import "Unicode";

// @Todo: test performance of ASCII optimization
// @Todo: test performance of glyph blitting (I've heard glTexSubImage2D can be slow)

// How fonts work in Stylo:
// We have a Font struct, that has a FreeType Face, and what we call
// font pages. Font pages store glyphs for a given pixel size. Each
// glyph is rendered onto a texture atlas using FreeType, the size of
// which can be controlled via the Default_Glyph_Atlas_Width/Height
// module parameters.
// Glyphs don't have to be rendered onto the atlas, they can be loaded
// solely for their metrics. The LoadGlyph function loads a glyph and its
// metrics, and the RenderGlyph function does the same thing but renders the
// glyph on top of that.
// For now, the number of glyphs allocated and rendered throughout
// the lifetime of a font page can only go up. This might not be optimal,
// so we might want to change that in the future (although that would require
// more house-keeping, which will have an effect of performance and memory
// usage). You can, however, destroy a font page.
//
//                                                   ostef, 21 November 2023

// This is here so we can test the performance of this optimization.
// It will go away eventually.
Enable_ASCII_Glyph_Array :: true;

Utf8String :: struct
{
    count : s64;
    data : *u8;

    #place count;
    as_string : string;
}

MakeUtf8String :: inline (str : string) -> Utf8String #must
{
    return .{str.count, str.data};
}

MakeUtf8String :: inline (count : s64, data : *u8) -> Utf8String #must
{
    return .{count, data};
}

for_expansion :: (str : Utf8String, body : Code, flags : For_Flags) #expand
{
    `it_index := 0;
    byte_index := 0;
    while byte_index < str.count
    {
        `it, len := Unicode.character_utf8_to_utf32 (str.data + byte_index, str.count - byte_index);

        defer {
            it_index += 1;
            byte_index += len;
        }

        #insert body;
    }
}

#scope_file

Word :: struct
{
    start_byte_index, end_byte_index : s64;
    str : string;
    length : s64;
    spaces : bool;
}

#scope_export

// for_expansion
ByWord :: (str : Utf8String, body : Code, flags : For_Flags) #expand
{
    `it : Word;
    `it_index := 0;
    if str.count != 0
        it.spaces == is_space (str.data[0]);

    while it.end_byte_index < str.count
    {
        codepoint, codepoint_len := Unicode.character_utf8_to_utf32 (str.data + it.end_byte_index, str.count - it.end_byte_index);

        defer {
            it.end_byte_index += codepoint_len;
            it.length += 1;
            it_index += 1;
        }

        space := codepoint < 128 && is_space (xx codepoint);
        if it.spaces != space
        {
            it.str.data = str.data + it.start_byte_index;
            it.str.count = it.end_byte_index - it.start_byte_index;
            #insert body;

            it.start_byte_index = it.end_byte_index;
            it.length = 0;
            it.spaces = space;
        }
    }

    if it.start_byte_index != it.end_byte_index
    {
        it.str.data = str.data + it.start_byte_index;
        it.str.count = it.end_byte_index - it.start_byte_index;
        #insert body;
    }
}

Font :: struct
{
    filename : string;
    ft_face : FT_Face;
    pages : Table (u32, FontPage);
}

FontPage :: struct
{
    font : *Font;
    height : u32;
    atlases : [..]GlyphAtlas;
    glyphs : Table (u32, Glyph);
    ascent, descent : s32;
    space_advance : u32;    // Advance of the space glyph

    #if Enable_ASCII_Glyph_Array
        ascii_glyphs : [128]Glyph;
}

Glyph :: struct
{
    codepoint : u32;

    rendered : bool;
    width, height : u32;
    bearing_x, bearing_y : s32;
    advance : u32;
    bitmap_width, bitmap_height : u32;
    bitmap_left, bitmap_top : s32;

    uv_rect : Rect;
    atlas_texture : TextureHandle;
}

GlyphAtlas :: struct
{
    texture : TextureHandle;
    width, height : u32;
    pen_x, pen_y : s32;
    row_end : s32;
}

OverflowBehavior :: enum
{
    None;
    Wrap;
    Wrap_Word;
}

GetDefaultFont :: inline () -> *Font #must
{
    return g_default_font;
}

SetDefaultFont :: inline (font : *Font)
{
    g_default_font = font;
}

#scope_file

g_default_font : *Font;
g_ft_lib : FT_Library;

InitFonts :: () -> bool
{
    ft_err := FT_Init_FreeType (*g_ft_lib);
    if ft_err != xx FT_Err.Ok
    {
        log_error ("Could not intialize FreeType");
        return false;
    }

    return true;
}

#scope_export

LoadFontFromFile :: (filename : string) -> *Font #must
{
    if !g_ft_lib && !InitFonts ()
        return null;

    ft_face : FT_Face;
    ft_err := FT_New_Face (g_ft_lib, temp_c_string (filename), 0, *ft_face);
    if ft_err != xx FT_Err.Ok
        return null;

    font := New (Font);
    font.filename = filename;
    font.ft_face = ft_face;
    font.pages.allocator = context.allocator;

    return font;
}

DestroyFont :: (using font : *Font)
{
    for * pages
        DestroyFontPage (it);

    deinit (*pages);
    FT_Done_Face (ft_face);
}

DestroyAndFreeFont :: inline (font : *Font)
{
    DestroyFont (font);
    free (font);
}

LoadFontPage :: (using font : *Font, height : u32) -> *FontPage
{
    page, new := find_or_add (*pages, height);
    if !new
        return page;

    Initialize (page);
    page.font = font;
    page.height = height;
    page.atlases.allocator = pages.allocator;

    page.glyphs.allocator = pages.allocator;
    resize (*page.glyphs, 512);

    space_glyph := LoadGlyph (page, #char " ");
    page.ascent  = xx (ft_face.size.metrics.ascender >> 6);
    page.descent = xx (ft_face.size.metrics.descender >> 6);
    page.space_advance = xx (space_glyph.advance);

    return page;
}

DestroyFontPage :: inline (using font : *Font, height : u32)
{
    page := table_find_pointer (*pages, height);
    if !page
        return;

    inline DestroyFontPage (page);
}

DestroyFontPage :: (using page : *FontPage)
{
    for * atlases
        DestroyTexture (*it.texture);

    array_reset (*atlases);
    deinit (*glyphs);
    table_remove (*font.pages, height);
}

AddGlyphAtlas :: (using page : *FontPage, atlas_width := Default_Glyph_Atlas_Width, atlas_height := Default_Glyph_Atlas_Height) -> *GlyphAtlas
{
    result := array_add (*atlases);
    result.width = xx atlas_width;
    result.height = xx atlas_height;

    result.texture = CreateTexture (xx atlas_width, xx atlas_height, null);

    return result;
}

#scope_file

SetGlyphMetrics :: (glyph : *Glyph, slot : *FT_GlyphSlotRec)
{
    glyph.width = xx (slot.metrics.width >> 6);
    glyph.height = xx (slot.metrics.height >> 6);
    glyph.bearing_x = xx (slot.metrics.horiBearingX >> 6);
    glyph.bearing_y = xx (slot.metrics.horiBearingY >> 6);
    glyph.advance = xx (slot.metrics.horiAdvance >> 6);

    glyph.bitmap_width = xx slot.bitmap.width;
    glyph.bitmap_height = xx slot.bitmap.rows;
    glyph.bitmap_left = xx slot.bitmap_left;
    glyph.bitmap_top = xx slot.bitmap_top;
}

FindOrAddGlyph :: inline (using page : *FontPage, codepoint : u32) -> *Glyph #must, new : bool
{
    #if Enable_ASCII_Glyph_Array
    {
        if codepoint < 128
        {
            glyph := *ascii_glyphs[codepoint];

            return glyph, codepoint != 0 && glyph.codepoint != codepoint;
        }
    }

    glyph, new := find_or_add (*glyphs, codepoint);

    return glyph, new;
}

#scope_export

LoadGlyph :: (using page : *FontPage, codepoint : u32) -> *Glyph
{
    glyph, new := FindOrAddGlyph (page, codepoint);
    if !new
        return glyph;

    FT_Set_Pixel_Sizes (font.ft_face, 0, height);
    ft_error := FT_Load_Char (font.ft_face, codepoint, FT_LOAD_DEFAULT);
    assert (ft_error == xx FT_Err.Ok);

    Initialize (glyph);
    glyph.codepoint = codepoint;
    SetGlyphMetrics (glyph, font.ft_face.glyph);

    return glyph;
}

FitRectIntoAtlas :: (atlas : GlyphAtlas, width : s32, height : s32) -> bool #must, x : s32, y : s32
{
    if width > xx atlas.width || height > xx atlas.height
        return false, 0, 0;

    pen_x := atlas.pen_x;
    pen_y := atlas.pen_y;

    if pen_y + height > xx atlas.height
        return false, 0, 0;

    if pen_x + width > xx atlas.width
    {
        pen_x = 0;
        pen_y = atlas.row_end;
    }

    if pen_y + height > xx atlas.height
        return false, 0, 0;

    return true, pen_x, pen_y;
}

RenderGlyph :: (using page : *FontPage, codepoint : u32) -> *Glyph
{
    glyph, new := FindOrAddGlyph (page, codepoint);
    if !new && glyph.rendered
        return glyph;

    FT_Set_Pixel_Sizes (font.ft_face, 0, height);
    ft_error := FT_Load_Char (font.ft_face, codepoint, FT_LOAD_RENDER);
    assert (ft_error == xx FT_Err.Ok);

    if new
    {
        Initialize (glyph);
        glyph.codepoint = codepoint;
        SetGlyphMetrics (glyph, font.ft_face.glyph);
    }

    slot := font.ft_face.glyph;

    // Find an atlas to blit the glyph into
    glyph_x, glyph_y : s32;
    atlas : *GlyphAtlas;
    for * atlases
    {
        fit:, glyph_x, glyph_y = FitRectIntoAtlas (it, xx glyph.bitmap_width, xx glyph.bitmap_height);

        if fit
        {
            atlas = it;

            break;
        }
    }

    if !atlas
    {
        atlas = AddGlyphAtlas (page,
            max (cast (s32) glyph.bitmap_width, Default_Glyph_Atlas_Width),
            max (cast (s32) glyph.bitmap_height, Default_Glyph_Atlas_Height)
        );
    }

    assert (FitRectIntoAtlas (atlas, xx glyph.bitmap_width, xx glyph.bitmap_height));

    atlas.pen_x = glyph_x + xx glyph.bitmap_width;
    atlas.pen_y = glyph_y;
    atlas.row_end = max (atlas.row_end, atlas.pen_y + xx glyph.bitmap_height);

    if glyph.bitmap_width > 0 && glyph.bitmap_height > 0
    {
        auto_release_temp ();

        rgba_bitmap := cast (*u32) alloc (size_of (u32) * glyph.bitmap_width * glyph.bitmap_height, temp);
        for y : 0..glyph.bitmap_height - 1
        {
            for x : 0..glyph.bitmap_width - 1
            {
                index := x + y * glyph.bitmap_width;
                alpha := cast (u32) slot.bitmap.buffer[index];
                rgba_bitmap[index] = 0x00ffffff | (alpha << 24);
            }
        }

        BlitToTexture (
            atlas.texture,
            glyph_x, glyph_y,
            glyph.bitmap_width, glyph.bitmap_height,
            rgba_bitmap
        );
    }

    glyph.uv_rect = .{
        glyph_x / cast (float) atlas.width,
        (glyph_y + xx glyph.bitmap_height) / cast (float) atlas.height,
        glyph.bitmap_width / cast (float) atlas.width,
        -(glyph.bitmap_height / cast (float) atlas.height)
    };

    glyph.atlas_texture = atlas.texture;
    glyph.rendered = true;

    return glyph;
}

TextGlyphIterator :: struct
{
    page : *FontPage;
    text : string;
    pen : Vec2f;
    bounds : Vec2f;
    width : float;
    allow_overflow : bool;
    render_glyphs := true;
}

WordWrap :: (iter : *TextGlyphIterator, body : Code, flags : For_Flags) #expand
{
    original_text := iter.text;
    defer iter.text = original_text;

    `it : *Glyph;
    `it_index := 0;
    for :ByWord word, word_index : MakeUtf8String (iter.text)
    {
        if !word.spaces
        {
            word_text_length := 0.0;
            for MakeUtf8String (word.str)
            {
                glyph := LoadGlyph (iter.page, it);
                word_text_length += glyph.advance;
            }
;
            if word_text_length < iter.bounds.x && iter.pen.x + word_text_length > iter.bounds.x
            {
                iter.pen.x = 0;
                iter.pen.y += iter.page.ascent - iter.page.descent;
            }
        }

        iter.text = word.str;
        for glyph, char_index : iter
        {
            defer it_index += 1;

            it = glyph;
            #insert body;
        }
    }
}

for_expansion :: (iter : *TextGlyphIterator, body : Code, flags : For_Flags) #expand
{
    for codepoint, `it_index : MakeUtf8String (iter.text)
    {
        if codepoint ==
        {
        case #char "\n";
            iter.width = max (iter.width, iter.pen.x);
            iter.pen.x = 0;
            iter.pen.y += iter.page.ascent - iter.page.descent;

        case #char "\t";
            glyph := LoadGlyph (iter.page, codepoint);
            iter.pen.x = SnapUp (iter.pen.x + glyph.advance, iter.page.space_advance * 4.0);

            if !iter.allow_overflow && iter.pen.x > iter.bounds.x
            {
                iter.pen.x = 0;
                iter.pen.y += iter.page.ascent - iter.page.descent;
            }

            iter.width = max (iter.width, iter.pen.x);

        case;
            glyph : *Glyph = ---;
            if iter.render_glyphs
                glyph = RenderGlyph (iter.page, codepoint);
            else
                glyph = LoadGlyph (iter.page, codepoint);

            if !iter.allow_overflow && iter.pen.x + glyph.advance > iter.bounds.x
            {
                iter.pen.x = 0;
                iter.pen.y += iter.page.ascent - iter.page.descent;
            }

            `it := glyph;
            #insert body;

            iter.pen.x += glyph.advance;
            iter.width = max (iter.width, iter.pen.x);
        }
    }
}

CalculateTextExtents :: inline (text : string, height : u32, rect : Rect, overflow : OverflowBehavior, font : *Font = null) -> Vec2f #must
{
    if !font
    {
        assert (g_default_font != null);
        font = g_default_font;
    }

    page := LoadFontPage (font, height);

    return CalculateTextExtents (text, rect, overflow, page);
}

CalculateTextExtents :: (text : string, rect : Rect, overflow : OverflowBehavior, page : *FontPage) -> Vec2f #must
{
    iter : TextGlyphIterator;
    iter.text = text;
    iter.page = page;
    iter.pen = Vec2f.{0, cast (float) iter.page.ascent};
    iter.bounds = rect.size;
    iter.allow_overflow = overflow == .None;

    if overflow == .Wrap_Word
    {
        for :WordWrap glyph, i : iter {}
    }
    else
    {
        for glyph, i : iter {}
    }

    return .{iter.width, iter.pen.y - iter.page.descent};
}

PushText :: inline (
    text : string,
    height : u32,
    position : Vec2f,
    color := Vec4f.{1,1,1,1},
    align := Vec2f.{0,0},
    font : *Font = null,
    lists : *DrawCommandLists = null
) -> Rect
{
    return PushText (
        text,
        height,
        .{position.x, position.y, 0, 0},
        color,
        align,
        OverflowBehavior.None,
        font,
        lists
    );
}

PushText :: (
    text : string,
    height : u32,
    rect : Rect,
    color := Vec4f.{1,1,1,1},
    align := Vec2f.{0,0},
    overflow := OverflowBehavior.None,
    font : *Font = null,
    lists : *DrawCommandLists = null
) -> Rect
{
    if !font
    {
        assert (g_default_font != null);
        font = g_default_font;
    }

    prev_texture := GetTexture (lists);
    defer SetTexture (prev_texture, lists);

    iter : TextGlyphIterator;
    iter.text = text;
    iter.page = LoadFontPage (font, height);
    iter.pen = Vec2f.{0, cast (float) iter.page.ascent};
    iter.bounds = rect.size;
    iter.allow_overflow = overflow == .None;

    size := CalculateTextExtents (text, rect, overflow, iter.page);
    offset := Vec2f.{
        rect.w * align.x - size.x * align.x,
        rect.h * align.y - size.y * align.y
    };

    PushGlyph :: () #expand
    {
        #if Origin_Top_Left
        {
            glyph_rect := Rect.{
                Round (`rect.x + `offset.x) + `iter.pen.x + `glyph.bitmap_left,
                Round (`rect.y + `offset.y) + `iter.pen.y - `glyph.bitmap_top,
                xx `glyph.bitmap_width,
                xx `glyph.bitmap_height
            };
        }
        else
        {
            glyph_rect := Rect.{
                Round (`rect.x + `offset.x) + `iter.pen.x + `glyph.bitmap_left,
                Round (`rect.y + `rect.h - `offset.y) - `iter.pen.y + `glyph.bitmap_top - `glyph.bitmap_height,
                xx `glyph.bitmap_width,
                xx `glyph.bitmap_height
            };
        }

        SetTexture (`glyph.atlas_texture, `lists);

        uv_rect := `glyph.uv_rect;
        #if Origin_Top_Left
        {
            uv_rect.h = -uv_rect.h;
            uv_rect.y -= uv_rect.h;
        }

        PushRect (glyph_rect, `color, uv_rect, lists = `lists);
    }

    if overflow == .Wrap_Word
    {
        for :WordWrap glyph, i : iter
        {
            PushGlyph ();
        }
    }
    else
    {
        for glyph, i : iter
        {
            PushGlyph ();
        }
    }

    #if Origin_Top_Left
        return .{Round (rect.x + offset.x), Round (rect.y + offset.y), size.x, size.y};
    else
        return .{Round (rect.x + offset.x), Round (rect.y + rect.h - size.y - offset.y), size.x, size.y};
}
