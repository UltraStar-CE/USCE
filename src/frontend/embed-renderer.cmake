# Adapt the pinned sample backend to an embedded renderer. Its default output is
# framebuffer zero, while the game also renders menus into transition textures.
file(READ "${rmlui_SOURCE_DIR}/Backends/RmlUi_Renderer_GL3.cpp" backend)
set(begin "void RenderInterface_GL3::BeginFrame()\n{")
set(end "// Draw to backbuffer\n\tglBindFramebuffer(GL_FRAMEBUFFER, 0);")
string(FIND "${backend}" "${begin}" begin_position)
string(FIND "${backend}" "${end}" end_position)
if(begin_position EQUAL -1 OR end_position EQUAL -1)
  message(FATAL_ERROR "Review RmlUi embedded renderer adaptation after updating the dependency")
endif()
string(REPLACE "${begin}" [=[
static GLint saved_draw_framebuffer, saved_read_framebuffer, saved_program;
static GLint saved_vao, saved_array_buffer, saved_texture, saved_renderbuffer;
static GLboolean saved_srgb;
void RenderInterface_GL3::BeginFrame()
{
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saved_draw_framebuffer);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saved_read_framebuffer);
    glGetIntegerv(GL_CURRENT_PROGRAM, &saved_program);
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &saved_vao);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &saved_array_buffer);
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &saved_renderbuffer);
    GLint active_texture;
    glGetIntegerv(GL_ACTIVE_TEXTURE, &active_texture);
    glActiveTexture(GL_TEXTURE0);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &saved_texture);
    glActiveTexture(active_texture);
    saved_srgb = glIsEnabled(GL_FRAMEBUFFER_SRGB);
]=] backend "${backend}")
string(REPLACE "${end}" "// Composite into the game's active render target.\n\tglBindFramebuffer(GL_FRAMEBUFFER, saved_draw_framebuffer);" backend "${backend}")
string(REPLACE "Gfx::CheckGLError(\"EndFrame\");" [=[
    glUseProgram(saved_program);
    glBindVertexArray(saved_vao);
    glBindBuffer(GL_ARRAY_BUFFER, saved_array_buffer);
    glBindRenderbuffer(GL_RENDERBUFFER, saved_renderbuffer);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, saved_draw_framebuffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, saved_read_framebuffer);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, saved_texture);
    glActiveTexture(glstate_backup.active_texture);
    if (saved_srgb) glEnable(GL_FRAMEBUFFER_SRGB); else glDisable(GL_FRAMEBUFFER_SRGB);
    Gfx::CheckGLError("EndFrame");
]=] backend "${backend}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/embedded-renderer.cpp" "${backend}")
