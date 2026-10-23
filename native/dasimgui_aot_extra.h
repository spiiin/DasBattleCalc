#pragma once
// Helpers that dasImgui defines in dasIMGUI.main.cpp and binds, but does
// not declare in aot_dasIMGUI.h: AOT-generated code calls them, so the
// declarations come in with imgui_ext's aotRequire.
#include "imgui.h"

namespace das {
    ImU32 GetActiveID();
    ImGuiID DockBuilderAddNode_das(ImGuiID node_id, ImGuiDockNodeFlags_ flags);
    void DockBuilderRemoveNode_das(ImGuiID node_id);
    void DockBuilderRemoveNodeDockedWindows_das(ImGuiID node_id, bool clear_settings_refs);
    void DockBuilderRemoveNodeChildNodes_das(ImGuiID node_id);
    void DockBuilderSetNodeSize_das(ImGuiID node_id, const ImVec2 & size);
    ImGuiID DockBuilderSplitNode_das(ImGuiID parent_id, ImGuiDir split_dir, float ratio,
                                     ImGuiID & out_at_dir, ImGuiID & out_at_opp);
    void DockBuilderDockWindow_das(const char * window_name, ImGuiID node_id);
    void DockBuilderFinish_das(ImGuiID node_id);
    bool DockBuilderHasNode(ImGuiID node_id);
    ImGuiID DockBuilderAddDockSpaceNode(ImGuiID node_id, ImGuiDockNodeFlags_ flags);
}
