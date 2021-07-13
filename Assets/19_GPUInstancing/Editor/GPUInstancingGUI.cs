using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

public class GPUInstancingGUI : ShaderGUI {

    enum SmoothnessSource {
        Uniform, Albedo, Metallic
    }

    enum RenderingMode {
        Opaque, Cutout, Fade, Transparent
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

    Material target;
    MaterialEditor editor;
    MaterialProperty[] properties;

    bool shouldShowAlphaCutoff;

    public override void OnGUI(MaterialEditor editor, MaterialProperty[] properties) {

        this.target = editor.target as Material;
        this.editor = editor;
        this.properties = properties;
        this.DoRenderingMode();
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
        // Add choice between None, Baked and Realtime, so that the corresponding
        // global illumination flag is properly set to support emissive light in
        // baked lightmaps, realtime lightmaps or neither of them.
        editor.LightmapEmissionProperty(2);
        if (EditorGUI.EndChangeCheck()) {
            if (tex != map.textureValue) {
                this.SetKeyword("_EMISSION_MAP", map.textureValue);
            }
            foreach (Material m in editor.targets) {
                // For indirect emission to work, the EmissiveIsBlack flag, which is
                // set automatically for new materials, must be not set. We ensure
                // this msking the EmissiveIsBlack bit of the flags value.
                // Note about EmissiveIsBlack: when this flag is enabled, Enlighten
                // (the only lightmapper capable of realtime GI right now) assumes
                // that the emission color is black and takes advantage of it to perform
                // baking optimizations. However in the Standard Shader this flag is not
                // set explicitely by the user, but is the result of setting the emission
                // color to black. However the flag is not automatically changed
                // if the color is changed at runtime via script, e.g. to animate the
                // emission color, so the baked emission results wrong in that cases
                // (causing confusion among users).
                // We use the LightmapEmissionProperty dropdown to give explicit control
                // to the user of about the needed flag, avoiding that hidden and misleading
                // logic. However this dropdown doesn't expose the EmissiveIsBlack
                // option (only None, Realtime and Baked), so we cannot take advantage
                // of the EmissiveIsBlack optimization (although most of the time a fixed
                // black emissive means no emission and the None option is fine).
                m.globalIlluminationFlags &= ~MaterialGlobalIlluminationFlags.EmissiveIsBlack;
            }
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
        // This adds a checkbox to enable/disable GPU Instancing, but only
        // if the shader supports instancing, specifically if it has
        // the #pragma multi_compile_instancing directive in at least one
        // of its passes.
        editor.EnableInstancingField();
    }

    private MaterialProperty FindProperty(string name) {
        return FindProperty(name, this.properties);
    }

    private void SetKeyword(string keyword, bool state) {
        // Loop all targets to update keywords for all selected materials
        if (state) {
            foreach (Material material in editor.targets)
            {
                material.EnableKeyword(keyword);
            }
        } else {
            foreach (Material material in editor.targets)
            {
                material.DisableKeyword(keyword);
            }
        }
    }

    private bool IsKeywordEnabled(string keyword) {
        return this.target.IsKeywordEnabled(keyword);
    }

    void RecordAction(string label) {
        this.editor.RegisterPropertyChangeUndo(label);
    }

    private static GUIContent MakeLabel(string text, string tooltip = null) {
        staticLabel.text = text;
        staticLabel.tooltip = tooltip;
        return staticLabel;
    }

    private static GUIContent MakeLabel(MaterialProperty property, string tooltip = null) {
        staticLabel.text = property.displayName;
        staticLabel.tooltip = tooltip;
        return staticLabel;
    }
}
