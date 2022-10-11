﻿using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

public class TriplanarMappingGUI : TriplanarMappingBaseGUI {

    enum SmoothnessSource {
        Uniform, Albedo, Metallic
    }

    enum RenderingMode {
        Opaque, Cutout, Fade, Transparent
    }

    enum TessellationMode {
        Uniform, Edge
    }

    struct RenderingSettings {
        public RenderQueue queue;
        public string renderType;
        public BlendMode srcBlend, dstBlend;
        public bool zWrite;

        public static RenderingSettings[] modes = {
            new RenderingSettings() {
                queue = RenderQueue.Geometry,
                renderType = "",
                srcBlend = BlendMode.One,
                dstBlend = BlendMode.Zero,
                zWrite = true
            },
            new RenderingSettings() {
                queue = RenderQueue.AlphaTest,
                renderType = "TransparentCutout",
                srcBlend = BlendMode.One,
                dstBlend = BlendMode.Zero,
                zWrite = true
            },
            new RenderingSettings() {
                queue = RenderQueue.Transparent,
                renderType = "Transparent",
                srcBlend = BlendMode.SrcAlpha,
                dstBlend = BlendMode.OneMinusSrcAlpha,
                zWrite = false
            },
            new RenderingSettings() {
                queue = RenderQueue.Transparent,
                renderType = "Transparent",
                srcBlend = BlendMode.One,
                dstBlend = BlendMode.OneMinusSrcAlpha,
                zWrite = false
            }
        };
    }

    static GUIContent staticLabel = new GUIContent();

    bool shouldShowAlphaCutoff;

    public override void OnGUI(MaterialEditor editor, MaterialProperty[] properties) {

        base.OnGUI(editor, properties);
        this.DoRenderingMode();
        // This way the tessellation parameter is shown only if the used
        // shader supports tessellation rendering.
        if (target.HasProperty("_TessellationUniform")) {
            DoTessellation();
        }
        if (target.HasProperty("_WireframeColor")) {
            DoWireframe();
        }
        this.DoMain();
        this.DoSecondary();
        this.DoAdvanced();
    }

    void DoRenderingMode() {
        RenderingMode mode = RenderingMode.Opaque;
        this.shouldShowAlphaCutoff = false;
        if (IsKeywordEnabled("_RENDERING_CUTOUT")) {
            mode = RenderingMode.Cutout;
            this.shouldShowAlphaCutoff = true;
        } else if (IsKeywordEnabled("_RENDERING_FADE")) {
            mode = RenderingMode.Fade;
        } else if (IsKeywordEnabled("_RENDERING_TRANSPARENT")) {
            mode = RenderingMode.Transparent;
        }
        EditorGUI.BeginChangeCheck();
        mode = (RenderingMode)EditorGUILayout.EnumPopup(
            MakeLabel("Rendering Mode"),
            mode
        );
        if (EditorGUI.EndChangeCheck()) {
            RecordAction("Rendering Mode");
            SetKeyword("_RENDERING_CUTOUT", mode == RenderingMode.Cutout);
            SetKeyword("_RENDERING_FADE", mode == RenderingMode.Fade);
            SetKeyword("_RENDERING_TRANSPARENT", mode == RenderingMode.Transparent);

            RenderingSettings settings = RenderingSettings.modes[(int)mode];
            foreach (Material material in editor.targets) {
                material.renderQueue = (int)settings.queue;
                material.SetOverrideTag("RenderType", settings.renderType);
                material.SetInt("_SrcBlend", (int)settings.srcBlend);
                material.SetInt("_DstBlend", (int)settings.dstBlend);
                material.SetInt("_ZWrite", settings.zWrite ? 1 : 0);
            }
        }
        if (mode == RenderingMode.Fade || mode == RenderingMode.Transparent) {
            this.DoSemitransparentShadows();
        }
    }

    void DoSemitransparentShadows() {
        EditorGUI.BeginChangeCheck();
        bool semitransparentShadows = EditorGUILayout.Toggle(
            MakeLabel("Semitransp. Shadows", "Semitransparent Shadows"),
            IsKeywordEnabled("_SEMITRANSPARENT_SHADOWS")
        );
        if (EditorGUI.EndChangeCheck()) {
            this.SetKeyword("_SEMITRANSPARENT_SHADOWS", semitransparentShadows);
        }
        if (!semitransparentShadows) {
            this.shouldShowAlphaCutoff = true;
        }
    }

    void DoMain() {
        GUILayout.Label("Main Maps", EditorStyles.boldLabel);

        MaterialProperty mainTex = this.FindProperty("_MainTex");
        editor.TexturePropertySingleLine(
            MakeLabel(mainTex, "Albedo (RGB)"),
            mainTex,
            this.FindProperty("_Color")
        );

        if (this.shouldShowAlphaCutoff) {
            this.DoAlphaCutoff();
        }
        this.DoMetallic();
        this.DoSmoothness();
        this.DoNormals();
        this.DoEmission();
        this.DoParallax();
        this.DoOcclusion();
        this.DoDetailMask();
        editor.TextureScaleOffsetProperty(mainTex);
    }

    void DoSecondary() {
        GUILayout.Label("Secondary Maps", EditorStyles.boldLabel);

        MaterialProperty detailTex = this.FindProperty("_DetailTex");
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(detailTex, "Albedo (RGB) multiplied by 2"),
            detailTex
        );
        if (EditorGUI.EndChangeCheck()) {
            this.SetKeyword("_DETAIL_ALBEDO_MAP", detailTex.textureValue);
        }
        this.DoSecondaryNormals();
        editor.TextureScaleOffsetProperty(detailTex);
    }

    void DoMetallic() {
        MaterialProperty map = this.FindProperty("_MetallicMap");
        Texture tex = map.textureValue;
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(map, "Metallic (R)"),
            map,
            tex ? null : this.FindProperty("_Metallic")
        );
        if (EditorGUI.EndChangeCheck() && tex != map.textureValue) {
            this.SetKeyword("_METALLIC_MAP", map.textureValue);
        }
    }

    void DoSmoothness() {
        SmoothnessSource source = SmoothnessSource.Uniform;
        if (this.IsKeywordEnabled("_SMOOTHNESS_ALBEDO")) {
            source = SmoothnessSource.Albedo;
        } else if (this.IsKeywordEnabled("_SMOOTHNESS_METALLIC")) {
            source = SmoothnessSource.Metallic;
        }

        MaterialProperty slider = this.FindProperty("_Smoothness");
        EditorGUI.indentLevel += 2;
        editor.ShaderProperty(slider, MakeLabel(slider));
        EditorGUI.indentLevel += 1;
        EditorGUI.BeginChangeCheck();
        source = (SmoothnessSource)EditorGUILayout.EnumPopup(MakeLabel("Source"), source);
        if (EditorGUI.EndChangeCheck()) {
            this.RecordAction("Smoothness Source");
            this.SetKeyword("_SMOOTHNESS_ALBEDO", source == SmoothnessSource.Albedo);
            this.SetKeyword("_SMOOTHNESS_METALLIC", source == SmoothnessSource.Metallic);
        }
        EditorGUI.indentLevel -= 3;
    }

    void DoNormals() {
        MaterialProperty map = this.FindProperty("_NormalMap");
        Texture tex = map.textureValue;
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(map),
            map,
            tex ? this.FindProperty("_BumpScale") : null
        );
        if (EditorGUI.EndChangeCheck() && tex != map.textureValue) {
            this.SetKeyword("_NORMAL_MAP", map.textureValue);
        }
    }

    void DoSecondaryNormals() {
        MaterialProperty map = this.FindProperty("_DetailNormalMap");
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(map),
            map,
            map.textureValue ? this.FindProperty("_DetailBumpScale") : null
        );
        if (EditorGUI.EndChangeCheck()) {
            this.SetKeyword("_DETAIL_NORMAL_MAP", map.textureValue);
        }
    }

    void DoEmission() {
        MaterialProperty map = this.FindProperty("_EmissionMap");
        Texture tex = map.textureValue;
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertyWithHDRColor(
            MakeLabel(map, "Emission (RGB)"),
            map,
            this.FindProperty("_Emission"),
            false
        );
        editor.LightmapEmissionProperty(2);
        if (EditorGUI.EndChangeCheck()) {
            if (tex != map.textureValue) {
                this.SetKeyword("_EMISSION_MAP", map.textureValue);
            }
            foreach (Material m in editor.targets) {
                m.globalIlluminationFlags &= ~MaterialGlobalIlluminationFlags.EmissiveIsBlack;
            }
        }
    }

    void DoParallax() {
        MaterialProperty map = this.FindProperty("_ParallaxMap");
        Texture tex = map.textureValue;
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(map, "Parallax (G)"),
            map,
            tex ? this.FindProperty("_ParallaxStrength") : null
        );
        if (EditorGUI.EndChangeCheck() && tex != map.textureValue) {
            this.SetKeyword("_PARALLAX_MAP", map.textureValue);
        }
    }

    void DoOcclusion() {
        MaterialProperty map = this.FindProperty("_OcclusionMap");
        Texture tex = map.textureValue;
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(map, "Occlusion (G)"),
            map,
            tex ? this.FindProperty("_OcclusionStrength") : null
        );
        if (EditorGUI.EndChangeCheck() && tex != map.textureValue) {
            this.SetKeyword("_OCCLUSION_MAP", map.textureValue);
        }
    }

    void DoDetailMask() {
        MaterialProperty mask = this.FindProperty("_DetailMask");
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(mask, "Detail Mask (A)"),
            mask
        );
        if (EditorGUI.EndChangeCheck()) {
            this.SetKeyword("_DETAIL_MASK", mask.textureValue);
        }
    }

    void DoAlphaCutoff() {
        MaterialProperty slider = this.FindProperty("_Cutoff");
        EditorGUI.indentLevel += 2;
        editor.ShaderProperty(slider, MakeLabel(slider));
        EditorGUI.indentLevel -= 2;
    }

    void DoAdvanced() {
        GUILayout.Label("Advanced Options", EditorStyles.boldLabel);
        editor.EnableInstancingField();
    }

    void DoWireframe() {
        GUILayout.Label("Wireframe", EditorStyles.boldLabel);
        EditorGUI.indentLevel += 2;
        editor.ShaderProperty(
            FindProperty("_WireframeColor"),
            MakeLabel("Color")
        );
        editor.ShaderProperty(
            FindProperty("_WireframeSmoothing"),
            MakeLabel("Smoothing", "In screen space.")
        );
        editor.ShaderProperty(
            FindProperty("_WireframeThickness"),
            MakeLabel("Thickness", "In screen space.")
        );
        EditorGUI.indentLevel -= 2;
    }

    void DoTessellation() {
        GUILayout.Label("Tessellation", EditorStyles.boldLabel);
        EditorGUI.indentLevel += 2;

        TessellationMode mode = TessellationMode.Uniform;
        if (IsKeywordEnabled("_TESSELLATION_EDGE")) {
            mode = TessellationMode.Edge;
        }
        EditorGUI.BeginChangeCheck();
        mode = (TessellationMode)EditorGUILayout.EnumPopup(
            MakeLabel("Mode"), mode
        );
        if (EditorGUI.EndChangeCheck()) {
            RecordAction("Tessellation Mode");
            SetKeyword("_TESSELLATION_EDGE", mode == TessellationMode.Edge);
        }

        if (mode == TessellationMode.Uniform) {
            editor.ShaderProperty(
                FindProperty("_TessellationUniform"),
                MakeLabel("Uniform")
            );
        } else {
            editor.ShaderProperty(
                FindProperty("_TessellationEdgeLength"),
                MakeLabel("Edge Length")
            );
        }
        
        EditorGUI.indentLevel -= 2;
    }
}
