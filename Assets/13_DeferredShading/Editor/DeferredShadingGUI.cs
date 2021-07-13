using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

public class DeferredShadingGUI : ShaderGUI {

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
            this.FindProperty("_Tint")
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
        if (EditorGUI.EndChangeCheck() && tex != map.textureValue) {
            this.SetKeyword("_EMISSION_MAP", map.textureValue);
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
        MaterialProperty slider = this.FindProperty("_AlphaCutoff");
        EditorGUI.indentLevel += 2;
        editor.ShaderProperty(slider, MakeLabel(slider));
        EditorGUI.indentLevel -= 2;
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
