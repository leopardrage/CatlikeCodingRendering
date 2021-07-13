using UnityEngine;
using UnityEditor;

public class OcclusionGUI : ShaderGUI {

    enum SmoothnessSource {
        Uniform, Albedo, Metallic
    }

    static GUIContent staticLabel = new GUIContent();

    Material target;
    MaterialEditor editor;
    MaterialProperty[] properties;

    public override void OnGUI(MaterialEditor editor, MaterialProperty[] properties) {

        this.target = editor.target as Material;
        this.editor = editor;
        this.properties = properties;
        this.DoMain();
        this.DoSecondary();
    }

    void DoMain() {
        GUILayout.Label("Main Maps", EditorStyles.boldLabel);

        MaterialProperty mainTex = this.FindProperty("_MainTex");
        editor.TexturePropertySingleLine(
            MakeLabel(mainTex, "Albedo (RGB)"),
            mainTex,
            this.FindProperty("_Tint")
        );
        this.DoMetallic();
        this.DoSmoothness();
        this.DoNormals();
        this.DoEmission();
        this.DoOcclusion();
        editor.TextureScaleOffsetProperty(mainTex);
    }

    void DoSecondary() {
        GUILayout.Label("Secondary Maps", EditorStyles.boldLabel);

        MaterialProperty detailTex = this.FindProperty("_DetailTex");
        editor.TexturePropertySingleLine(
            MakeLabel(detailTex, "Albedo (RGB) multiplied by 2"),
            detailTex
        );
        this.DoSecondaryNormals();
        editor.TextureScaleOffsetProperty(detailTex);
    }

    void DoMetallic() {
        MaterialProperty map = this.FindProperty("_MetallicMap");
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(map, "Metallic (R)"),
            map,
            map.textureValue ? null : this.FindProperty("_Metallic")
        );
        if (EditorGUI.EndChangeCheck()) {
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
        editor.TexturePropertySingleLine(
            MakeLabel(map),
            map,
            map.textureValue ? this.FindProperty("_BumpScale") : null
        );
    }

    void DoSecondaryNormals() {
        MaterialProperty map = this.FindProperty("_DetailNormalMap");
        editor.TexturePropertySingleLine(
            MakeLabel(map),
            map,
            map.textureValue ? this.FindProperty("_DetailBumpScale") : null
        );
    }

    void DoEmission() {
        MaterialProperty map = this.FindProperty("_EmissionMap");
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertyWithHDRColor(
            MakeLabel(map, "Emission (RGB)"),
            map,
            this.FindProperty("_Emission"),
            false
        );
        if (EditorGUI.EndChangeCheck()) {
            this.SetKeyword("_EMISSION_MAP", map.textureValue);
        }
    }

    void DoOcclusion() {
        MaterialProperty map = this.FindProperty("_OcclusionMap");
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(map, "Occlusion (G)"),
            map,
            map.textureValue ? this.FindProperty("_OcclusionStrength") : null
        );
        if (EditorGUI.EndChangeCheck()) {
            this.SetKeyword("_OCCLUSION_MAP", map.textureValue);
        }
    }

    private MaterialProperty FindProperty(string name) {
        return FindProperty(name, this.properties);
    }

    private void SetKeyword(string keyword, bool state) {
        if (state) {
            this.target.EnableKeyword(keyword);
        } else {
            this.target.DisableKeyword(keyword);
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
